//
//  SRAudioOutput.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRAudioOutput.h"
#import "SRAudioRingBuffer.h"
#import <AVFoundation/AVFoundation.h>

// shared between the main thread and the render thread
typedef struct {
	int32_t playing;
	int32_t underrun;
	uint64_t renderedFrames;
} SRAudioOutputState;

@interface SRAudioOutput () {
	SRAudioOutputState *_state;
}

@property (nonatomic, strong) SRAudioBuffer *buffer;
@property (nonatomic, assign) double sampleRate;
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioSourceNode *sourceNode;
@property (nonatomic, assign) BOOL running;

@end

@interface SRSampleBufferAudioOutput : SRAudioOutput
@end

@implementation SRAudioOutput

+ (instancetype)outputWithBuffer:(SRAudioBuffer *)buffer sampleRate:(double)sampleRate {
	if ([NSProcessInfo processInfo].isMacCatalystApp) {
		return [self sampleBufferOutputWithBuffer:buffer sampleRate:sampleRate];
	}
	return [[SRAudioOutput alloc] initWithBuffer:buffer sampleRate:sampleRate];
}

+ (instancetype)sampleBufferOutputWithBuffer:(SRAudioBuffer *)buffer sampleRate:(double)sampleRate {
	return [[SRSampleBufferAudioOutput alloc] initWithBuffer:buffer sampleRate:sampleRate];
}

- (instancetype)initWithBuffer:(SRAudioBuffer *)buffer sampleRate:(double)sampleRate {
	self = [super init];
	if (self) {
		_buffer = buffer;
		_sampleRate = sampleRate;
		_volume = 1.f;
		_state = calloc(1, sizeof(SRAudioOutputState));
	}
	return self;
}

- (void)dealloc {
	[self stop];
	// the engine was stopped above, the render block doesn't run any more
	free(_state);
}

- (BOOL)start:(NSError **)error {
	if (self.running) {
		return YES;
	}
	AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:self.sampleRate channels:self.buffer.channels];
	SRAudioBuffer *buffer = self.buffer;
	SRAudioRingBuffer *ring = buffer.ring;
	SRAudioOutputState *state = _state;
	AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
		// real time thread: no locks, no allocations, no Objective-C messages
		(void)buffer; // keeps the ring buffer alive for as long as the block exists
		float *channels[8];
		UInt32 channelCount = outputData->mNumberBuffers < 8 ? outputData->mNumberBuffers : 8;
		for (UInt32 c = 0; c < channelCount; c++) {
			channels[c] = (float *)outputData->mBuffers[c].mData;
		}
		uint32_t read = 0;
		if (__atomic_load_n(&state->playing, __ATOMIC_ACQUIRE)) {
			read = SRAudioRingBufferRead(ring, channels, frameCount);
			__atomic_add_fetch(&state->renderedFrames, read, __ATOMIC_RELEASE);
			if (read < frameCount) {
				__atomic_store_n(&state->underrun, 1, __ATOMIC_RELEASE);
			}
		}
		for (UInt32 c = 0; c < channelCount; c++) {
			memset(channels[c] + read, 0, (frameCount - read) * sizeof(float));
		}
		// not flagged as silence: the output keeps counting as playing audio while it (re)buffers
		return noErr;
	}];

	AVAudioEngine *engine = [[AVAudioEngine alloc] init];
	[engine attachNode:sourceNode];
	[engine connect:sourceNode to:engine.mainMixerNode format:format];
	engine.mainMixerNode.outputVolume = self.volume;
	[engine prepare];
	if (![engine startAndReturnError:error]) {
		return NO;
	}
	self.engine = engine;
	self.sourceNode = sourceNode;
	self.running = YES;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(engineConfigurationChanged:) name:AVAudioEngineConfigurationChangeNotification object:engine];
	return YES;
}

- (void)stop {
	if (!self.running) {
		return;
	}
	self.running = NO;
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioEngineConfigurationChangeNotification object:self.engine];
	[self.engine stop];
	[self.engine detachNode:self.sourceNode];
	self.sourceNode = nil;
	self.engine = nil;
}

- (void)engineConfigurationChanged:(NSNotification *)notification {
	// the output route or format changed (e.g. headphones, Bluetooth), the engine stopped itself
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.running && !self.engine.isRunning) {
			NSError *error = nil;
			if (![self.engine startAndReturnError:&error]) {
				NSLog(@"Couldn't restart the audio output: %@", error);
			}
		}
	});
}

#pragma mark - Properties

- (void)setPlaying:(BOOL)playing {
	__atomic_store_n(&_state->underrun, 0, __ATOMIC_RELEASE);
	__atomic_store_n(&_state->playing, playing ? 1 : 0, __ATOMIC_RELEASE);
}

- (BOOL)playing {
	return __atomic_load_n(&_state->playing, __ATOMIC_ACQUIRE) != 0;
}

- (BOOL)underrun {
	return __atomic_load_n(&_state->underrun, __ATOMIC_ACQUIRE) != 0;
}

- (uint64_t)renderedFrames {
	return __atomic_load_n(&_state->renderedFrames, __ATOMIC_ACQUIRE);
}

- (void)setVolume:(float)volume {
	_volume = volume;
	self.engine.mainMixerNode.outputVolume = volume;
}

- (uint64_t)latencyFrames {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	NSTimeInterval latency = session.outputLatency + session.IOBufferDuration;
	return (uint64_t)(MAX(latency, 0.0) * self.sampleRate);
}

@end

#pragma mark - Sample buffer output

// Plays through AVSampleBufferAudioRenderer, which follows the app's AirPlay route on the Mac.
// The renderer pulls ahead of the playback on its own (more for AirPlay), so instead of playing silence while
// rebuffering the synchronizer is paused, and `renderedFrames` is the synchronizer's time: the audio that was heard.
@interface SRSampleBufferAudioOutput ()

@property (nonatomic, strong) SRAudioBuffer *ringBuffer;
@property (nonatomic, assign) double rate;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_source_t timer;
@property (nonatomic, strong) AVSampleBufferAudioRenderer *renderer;
@property (nonatomic, strong) AVSampleBufferRenderSynchronizer *synchronizer;
@property (nonatomic, assign) CMAudioFormatDescriptionRef format;
// queue only
@property (nonatomic, assign) BOOL clockRunning;
@property (nonatomic, assign) BOOL wantsPlaying;

@end

@implementation SRSampleBufferAudioOutput {
	int32_t _playingFlag;
	int32_t _underrunFlag;
	// frames enqueued into the renderer, the time of the next sample
	uint64_t _enqueuedFrames;
	BOOL _running;
	float _volumeValue;
	// 8 channels x 4096 frames, used on the queue
	float *_planar;
}

- (instancetype)initWithBuffer:(SRAudioBuffer *)buffer sampleRate:(double)sampleRate {
	self = [super initWithBuffer:buffer sampleRate:sampleRate];
	if (self) {
		_ringBuffer = buffer;
		_rate = sampleRate;
		_volumeValue = 1.f;
		_planar = calloc(8 * 4096, sizeof(float));
		_queue = dispatch_queue_create("org.jernej.SloRadio.SampleBufferOutput", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (void)dealloc {
	[self stop];
	if (_format) {
		CFRelease(_format);
	}
	free(_planar);
}

- (BOOL)start:(NSError **)error {
	if (_running) {
		return YES;
	}
	AudioStreamBasicDescription asbd = {0};
	asbd.mSampleRate = self.rate;
	asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	asbd.mChannelsPerFrame = self.ringBuffer.channels;
	asbd.mBitsPerChannel = 32;
	asbd.mBytesPerFrame = 4 * asbd.mChannelsPerFrame;
	asbd.mFramesPerPacket = 1;
	asbd.mBytesPerPacket = asbd.mBytesPerFrame;
	CMAudioFormatDescriptionRef format = NULL;
	OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &format);
	if (status != noErr) {
		if (error) {
			*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		}
		return NO;
	}
	self.format = format;

	self.renderer = [[AVSampleBufferAudioRenderer alloc] init];
	self.renderer.volume = _volumeValue;
	self.synchronizer = [[AVSampleBufferRenderSynchronizer alloc] init];
	[self.synchronizer addRenderer:self.renderer];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rendererWasFlushed:) name:AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification object:self.renderer];

	__weak SRSampleBufferAudioOutput *weakSelf = self;
	self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
	dispatch_source_set_timer(self.timer, DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);
	dispatch_source_set_event_handler(self.timer, ^{
		[weakSelf feed];
	});
	dispatch_resume(self.timer);
	_running = YES;
	return YES;
}

- (void)stop {
	if (!_running) {
		return;
	}
	_running = NO;
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification object:self.renderer];
	dispatch_source_cancel(self.timer);
	dispatch_sync(self.queue, ^{
		[self.synchronizer setRate:0];
		[self.renderer flush];
		[self.synchronizer removeRenderer:self.renderer atTime:kCMTimeInvalid completionHandler:nil];
	});
	self.timer = nil;
}

#pragma mark - Queue

- (CMTime)endTime {
	return CMTimeMake((int64_t)__atomic_load_n(&_enqueuedFrames, __ATOMIC_ACQUIRE), (int32_t)self.rate);
}

- (void)feed {
	if (!_running) {
		return;
	}
	BOOL playing = __atomic_load_n(&_playingFlag, __ATOMIC_ACQUIRE) != 0;
	if (playing != self.wantsPlaying) {
		self.wantsPlaying = playing;
		if (!playing && self.clockRunning) {
			// rebuffering: pause, whatever is still queued plays when resumed
			[self.synchronizer setRate:0];
			self.clockRunning = NO;
		}
	}
	if (!playing) {
		return;
	}
	CMTime resumeTime = CMTimeMinimum(self.synchronizer.currentTime, [self endTime]);
	BOOL enqueued = NO;
	while (self.renderer.isReadyForMoreMediaData) {
		CMSampleBufferRef sample = [self copyNextSampleBuffer];
		if (!sample) {
			break;
		}
		[self.renderer enqueueSampleBuffer:sample];
		CFRelease(sample);
		enqueued = YES;
	}
	if (!self.clockRunning) {
		if (enqueued) {
			[self.synchronizer setRate:1 time:resumeTime];
			self.clockRunning = YES;
		}
	} else if (CMTimeCompare(self.synchronizer.currentTime, [self endTime]) >= 0) {
		// everything that was enqueued was played
		__atomic_store_n(&_underrunFlag, 1, __ATOMIC_RELEASE);
	}
}

// Up to 4096 frames from the ring buffer, interleaved, or NULL if it's empty.
- (CMSampleBufferRef)copyNextSampleBuffer {
	SRAudioRingBuffer *ring = self.ringBuffer.ring;
	uint32_t frames = MIN(SRAudioRingBufferAvailableFrames(ring), 4096u);
	if (frames == 0) {
		return NULL;
	}
	uint32_t channels = MIN(self.ringBuffer.channels, 8u);
	float *planes[8];
	for (uint32_t c = 0; c < channels; c++) {
		planes[c] = _planar + c * 4096;
	}
	frames = SRAudioRingBufferRead(ring, planes, frames);
	size_t bytes = (size_t)frames * channels * sizeof(float);
	CMBlockBufferRef block = NULL;
	if (CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, bytes, kCFAllocatorDefault, NULL, 0, bytes, kCMBlockBufferAssureMemoryNowFlag, &block) != noErr) {
		return NULL;
	}
	float *interleaved = NULL;
	CMBlockBufferGetDataPointer(block, 0, NULL, NULL, (char **)&interleaved);
	for (uint32_t f = 0; f < frames; f++) {
		for (uint32_t c = 0; c < channels; c++) {
			interleaved[f * channels + c] = planes[c][f];
		}
	}
	CMSampleBufferRef sample = NULL;
	OSStatus status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(kCFAllocatorDefault, block, self.format, frames, [self endTime], NULL, &sample);
	CFRelease(block);
	if (status != noErr) {
		return NULL;
	}
	__atomic_add_fetch(&_enqueuedFrames, frames, __ATOMIC_RELEASE);
	return sample;
}

- (void)rendererWasFlushed:(NSNotification *)notification {
	// the output route changed (e.g. to AirPlay) and the renderer dropped what was queued: continue from where it stopped
	dispatch_async(self.queue, ^{
		if (!self->_running) {
			return;
		}
		NSValue *value = notification.userInfo[AVSampleBufferAudioRendererFlushTimeKey];
		CMTime flushTime = value ? value.CMTimeValue : self.synchronizer.currentTime;
		[self.synchronizer setRate:0];
		self.clockRunning = NO;
		uint64_t frames = (uint64_t)MAX(CMTimeGetSeconds(flushTime) * self.rate, 0.0);
		if (frames < __atomic_load_n(&self->_enqueuedFrames, __ATOMIC_ACQUIRE)) {
			__atomic_store_n(&self->_enqueuedFrames, frames, __ATOMIC_RELEASE);
		}
	});
}

#pragma mark - Properties

- (void)setPlaying:(BOOL)playing {
	__atomic_store_n(&_underrunFlag, 0, __ATOMIC_RELEASE);
	__atomic_store_n(&_playingFlag, playing ? 1 : 0, __ATOMIC_RELEASE);
}

- (BOOL)playing {
	return __atomic_load_n(&_playingFlag, __ATOMIC_ACQUIRE) != 0;
}

- (BOOL)underrun {
	return __atomic_load_n(&_underrunFlag, __ATOMIC_ACQUIRE) != 0;
}

- (uint64_t)renderedFrames {
	if (!self.synchronizer) {
		return 0;
	}
	CMTime heard = CMTimeMinimum(self.synchronizer.currentTime, [self endTime]);
	double seconds = CMTimeGetSeconds(heard);
	return seconds > 0 ? (uint64_t)(seconds * self.rate) : 0;
}

- (uint64_t)latencyFrames {
	// renderedFrames is already what was heard
	return 0;
}

- (void)setVolume:(float)volume {
	_volumeValue = volume;
	self.renderer.volume = volume;
}

- (float)volume {
	return _volumeValue;
}

@end

#pragma mark - Silence

@interface SRSilenceOutput ()
@property (nonatomic, strong) AVAudioEngine *engine;
@end

@implementation SRSilenceOutput

- (void)dealloc {
	[self stop];
}

- (BOOL)isRunning {
	return self.engine != nil;
}

- (void)start {
	if (self.engine) {
		return;
	}
	AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
	AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
		for (UInt32 b = 0; b < outputData->mNumberBuffers; b++) {
			memset(outputData->mBuffers[b].mData, 0, outputData->mBuffers[b].mDataByteSize);
		}
		return noErr;
	}];
	AVAudioEngine *engine = [[AVAudioEngine alloc] init];
	[engine attachNode:sourceNode];
	[engine connect:sourceNode to:engine.mainMixerNode format:format];
	[engine prepare];
	NSError *error = nil;
	if (![engine startAndReturnError:&error]) {
		NSLog(@"Couldn't start the silence output: %@", error);
		return;
	}
	self.engine = engine;
}

- (void)stop {
	[self.engine stop];
	self.engine = nil;
}

@end
