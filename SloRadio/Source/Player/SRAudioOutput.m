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

@implementation SRAudioOutput

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
		*isSilence = read == 0;
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
