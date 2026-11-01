//
//  SRFFmpegEngine.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRFFmpegEngine.h"
#import "SRByteQueue.h"
#import "SRStreamInput.h"
#import "SRICYParser.h"
#import "SRMetadataDecoder.h"
#import "SRFFmpegDecoder.h"
#import "SRAudioRingBuffer.h"
#import "SRAudioOutput.h"

// audio buffered before playback starts (and after running out) when no buffer duration is set
static NSTimeInterval const SRFFmpegEngineDefaultBufferDuration = 1.0;
// room for decoded audio beyond the pre-roll
static NSTimeInterval const SRFFmpegEngineExtraBufferDuration = 4.0;
// compressed data read ahead of the decoder (about 30 s of a 128 kbit/s stream)
static NSUInteger const SRFFmpegEngineQueueCapacity = 512 * 1024;
// no data received for this long while there is nothing left to play means the connection is dead
static NSTimeInterval const SRFFmpegEngineDefaultNetworkStallTimeout = 3.0;
// fallback: no audio played for this long (since the last played audio, or since starting) means the stream stalled
static NSTimeInterval const SRFFmpegEngineDefaultStallTimeout = 10.0;
// the output counts as starved when it played nothing for this long
static NSTimeInterval const SRFFmpegEngineStarvedInterval = 0.5;
static NSTimeInterval const SRFFmpegEngineTickInterval = 0.05;

@interface SRTimedMetadata : NSObject
@property (nonatomic, strong) NSDictionary *metadata;
@property (nonatomic, assign) uint64_t frame;
@end

@implementation SRTimedMetadata
@end

@interface SRFFmpegEngine () <SRStreamInputDelegate, SRFFmpegDecoderDelegate>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSTimeInterval bufferDuration;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) SRRadioPlayerState state;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, assign) BOOL opened;
@property (nonatomic, assign) BOOL ended;
@property (nonatomic, assign) uint32_t prerollFrames;

@property (nonatomic, strong) SRByteQueue *queue;
@property (nonatomic, strong) SRStreamInput *input;
@property (nonatomic, strong) SRFFmpegDecoder *decoder;
@property (nonatomic, strong) SRAudioBuffer *buffer;
@property (nonatomic, strong) SRAudioOutput *output;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) NSMutableArray<SRTimedMetadata *> *timeline;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *metaData;
@property (nonatomic, assign) BOOL receivedStreamTitle;
@property (nonatomic, assign) uint64_t lastRenderedFrames;
@property (nonatomic, strong) NSDate *lastAudio;
@property (nonatomic, assign) uint64_t lastBytesReceived;
@property (nonatomic, strong) NSDate *lastData;
@property (nonatomic, strong) NSError *inputError;

@end

@implementation SRFFmpegEngine

@synthesize delegate = _delegate;
@synthesize stallTimeout = _stallTimeout;
@synthesize networkStallTimeout = _networkStallTimeout;

- (instancetype)initWithURL:(NSURL *)url bufferDuration:(NSTimeInterval)bufferDuration {
	self = [super init];
	if (self) {
		_url = url;
		_bufferDuration = bufferDuration;
		_volume = 1.f;
		_stallTimeout = SRFFmpegEngineDefaultStallTimeout;
		_networkStallTimeout = SRFFmpegEngineDefaultNetworkStallTimeout;
		_state = SRRadioPlayerStateStopped;
		_timeline = [NSMutableArray array];
		_metaData = [NSMutableDictionary dictionary];
	}
	return self;
}

- (void)dealloc {
	[self stop];
}

#pragma mark - SRPlaybackEngine

- (void)start {
	if (self.started) {
		return;
	}
	self.started = YES;
	NSTimeInterval preroll = self.bufferDuration > 0 ? self.bufferDuration : SRFFmpegEngineDefaultBufferDuration;
	self.prerollFrames = (uint32_t)(preroll * SRFFmpegDecoderOutputSampleRate);
	uint32_t capacity = (uint32_t)((preroll + SRFFmpegEngineExtraBufferDuration) * SRFFmpegDecoderOutputSampleRate);

	self.buffer = [[SRAudioBuffer alloc] initWithCapacityFrames:capacity channels:SRFFmpegDecoderOutputChannels];
	self.queue = [[SRByteQueue alloc] initWithCapacity:SRFFmpegEngineQueueCapacity];
	self.input = [[SRStreamInput alloc] initWithURL:self.url queue:self.queue];
	self.input.delegate = self;
	self.decoder = [[SRFFmpegDecoder alloc] initWithInput:self.queue output:self.buffer];
	self.decoder.delegate = self;
	self.lastAudio = [NSDate date];
	self.lastData = self.lastAudio;

	[self setStateAndNotify:SRRadioPlayerStateOpening];
	[self.input start];
	[self.decoder start];
	self.timer = [NSTimer timerWithTimeInterval:SRFFmpegEngineTickInterval target:self selector:@selector(tick:) userInfo:nil repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
	if (!self.started || self.stopped) {
		return;
	}
	self.stopped = YES;
	[self.timer invalidate];
	self.timer = nil;
	self.decoder.delegate = nil;
	[self.decoder stop];
	self.input.delegate = nil;
	[self.input cancel];
	[self.output stop];
}

- (void)setVolume:(float)volume {
	_volume = volume;
	self.output.volume = volume;
}

- (NSTimeInterval)playbackTime {
	return self.output.renderedFrames / SRFFmpegDecoderOutputSampleRate;
}

#pragma mark - State

- (void)setStateAndNotify:(SRRadioPlayerState)state {
	if (state != self.state && !self.stopped) {
		self.state = state;
		[self.delegate playbackEngine:self didChangeState:state];
	}
}

- (void)failWithError:(NSError *)error {
	NSLog(@"FFmpeg engine failed to play %@: %@ (input: %@)", self.url, error.localizedDescription, self.inputError.localizedDescription ?: @"ok");
	[self setStateAndNotify:SRRadioPlayerStateError];
	[self stop];
}

- (void)stallBecause:(NSString *)reason {
	if (self.stopped) {
		return;
	}
	NSLog(@"FFmpeg engine stalled on %@: %@ (played %.1f s, buffered %.1f s decoded + %lu KB, last data %.1f s ago after %llu KB, input: %@)",
		  self.url, reason, self.playbackTime,
		  SRAudioRingBufferAvailableFrames(self.buffer.ring) / SRFFmpegDecoderOutputSampleRate,
		  (unsigned long)(self.queue.length / 1024), -[self.lastData timeIntervalSinceNow],
		  self.queue.totalBytesAppended / 1024, self.inputError.localizedDescription ?: @"no error");
	[self.delegate playbackEngineDidStall:self];
}

- (void)tick:(NSTimer *)timer {
	if (self.stopped) {
		return;
	}
	NSDate *now = [NSDate date];
	uint64_t bytes = self.queue.totalBytesAppended;
	if (bytes != self.lastBytesReceived) {
		self.lastBytesReceived = bytes;
		self.lastData = now;
	}
	// Watchdog. A reconnect interrupts the playback, so it's only done when it's needed:
	// - right away when there is nothing left to play and nothing arrives (both the buffer and the network are empty),
	//   a quiet network is fine as long as buffered audio is playing, and a slow one as long as data trickles in
	// - as a fallback when no audio was played for stallTimeout (also while opening), e.g. data that can't be decoded
	uint64_t rendered = self.output.renderedFrames;
	if (rendered != self.lastRenderedFrames) {
		self.lastRenderedFrames = rendered;
		self.lastAudio = now;
	}
	NSTimeInterval silentPlayback = [now timeIntervalSinceDate:self.lastAudio];
	NSTimeInterval silentNetwork = [now timeIntervalSinceDate:self.lastData];
	BOOL bufferEmpty = silentPlayback >= SRFFmpegEngineStarvedInterval && self.queue.length == 0;
	BOOL networkEmpty = bytes > 0 && silentNetwork >= self.networkStallTimeout;
	if (bufferEmpty && networkEmpty) {
		[self stallBecause:[NSString stringWithFormat:@"buffer empty and no data for %.1f s", silentNetwork]];
		return;
	}
	if (silentPlayback >= self.stallTimeout) {
		NSString *reason = rendered > 0 ? @"no audio played" : (self.opened ? @"no audio since opening the stream" : @"couldn't open the stream");
		[self stallBecause:[NSString stringWithFormat:@"%@ for %.0f s", reason, self.stallTimeout]];
		return;
	}
	if (!self.opened) {
		return;
	}

	uint32_t available = SRAudioRingBufferAvailableFrames(self.buffer.ring);
	if (!self.output.playing) {
		// start (again) once enough audio is buffered, or play out what's left of an ended stream
		if (available >= self.prerollFrames || available >= self.buffer.capacityFrames - 1024 || (self.ended && available > 0)) {
			self.output.playing = YES;
		}
	} else if (self.output.underrun) {
		if (self.ended) {
			[self stallBecause:@"the stream ended and the buffer ran empty"];
			return;
		}
		// rebuffer, the watchdog above reconnects if no audio arrives
		self.output.playing = NO;
	}
	if (self.output.playing && rendered > 0) {
		[self setStateAndNotify:SRRadioPlayerStatePlaying];
	} else {
		[self setStateAndNotify:SRRadioPlayerStateBuffering];
	}
	[self deliverDueMetadata];
}

#pragma mark - Metadata timeline

- (void)deliverDueMetadata {
	uint64_t rendered = self.output.renderedFrames;
	uint64_t latency = self.output.latencyFrames;
	uint64_t heard = rendered > latency ? rendered - latency : 0;
	BOOL changed = NO;
	while (self.timeline.count > 0 && self.timeline.firstObject.frame <= heard) {
		SRTimedMetadata *timed = self.timeline.firstObject;
		[self.timeline removeObjectAtIndex:0];
		changed |= [self applyMetadata:timed.metadata];
	}
	if (changed) {
		[self.delegate playbackEngine:self didChangeMetaData:[self.metaData copy]];
	}
}

// Maps stream tags to the player's keys. Returns YES when something changed.
- (BOOL)applyMetadata:(NSDictionary<NSString *, NSString *> *)tags {
	NSDictionary *keys = @{@"streamtitle": SRRadioPlayerMetaDataNowPlayingKey,
						   @"title": SRRadioPlayerMetaDataTitleKey,
						   @"artist": SRRadioPlayerMetaDataArtistKey,
						   @"genre": SRRadioPlayerMetaDataGenreKey,
						   @"icy-genre": SRRadioPlayerMetaDataGenreKey};
	BOOL changed = NO;
	for (NSString *tag in tags) {
		NSString *key = keys[tag.lowercaseString];
		NSString *value = tags[tag];
		if (key && value && ![self.metaData[key] isEqualToString:value]) {
			self.metaData[key] = value;
			changed = YES;
		}
	}
	return changed;
}

#pragma mark - SRStreamInputDelegate

- (void)streamInput:(SRStreamInput *)input didReceiveHeaders:(NSDictionary<NSString *, NSString *> *)headers {
	NSString *genre = headers[@"icy-genre"];
	if (genre.length > 0 && [self applyMetadata:@{@"icy-genre": genre}]) {
		[self.delegate playbackEngine:self didChangeMetaData:[self.metaData copy]];
	}
}

- (void)streamInput:(SRStreamInput *)input didReceiveMetadataBlock:(SRICYMetadataBlock *)block {
	NSString *title = [SRMetadataDecoder fieldsFromICYMetadata:block.data][@"StreamTitle"];
	if (!title) {
		return;
	}
	// The first title describes the song that is already playing when we tune in, it applies from the start.
	// Later titles apply exactly where they appear in the stream.
	uint64_t offset = self.receivedStreamTitle ? block.audioOffset : 0;
	self.receivedStreamTitle = YES;
	[self.decoder addMetadata:@{@"streamtitle": title} atStreamOffset:offset];
}

- (void)streamInput:(SRStreamInput *)input didFinishWithError:(NSError *)error {
	// the decoder notices the end of its input, remember why for the log
	self.inputError = error;
}

#pragma mark - SRFFmpegDecoderDelegate (decoder thread)

- (void)onMainThread:(void (^)(SRFFmpegEngine *engine))block {
	__weak SRFFmpegEngine *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		SRFFmpegEngine *engine = weakSelf;
		if (engine && !engine.stopped) {
			block(engine);
		}
	});
}

- (void)decoder:(SRFFmpegDecoder *)decoder didOpenStreamWithDescription:(NSString *)description {
	[self onMainThread:^(SRFFmpegEngine *engine) {
		NSLog(@"Playing %@ (%@)", engine.url, description);
		engine.opened = YES;
		engine.output = [SRAudioOutput outputWithBuffer:engine.buffer sampleRate:SRFFmpegDecoderOutputSampleRate];
		engine.output.volume = engine.volume;
		NSError *error = nil;
		if (![engine.output start:&error]) {
			[engine failWithError:error];
			return;
		}
		[engine setStateAndNotify:SRRadioPlayerStateBuffering];
	}];
}

- (void)decoder:(SRFFmpegDecoder *)decoder didFailWithError:(NSError *)error {
	[self onMainThread:^(SRFFmpegEngine *engine) {
		[engine failWithError:error];
	}];
}

- (void)decoderDidReachEnd:(SRFFmpegDecoder *)decoder {
	[self onMainThread:^(SRFFmpegEngine *engine) {
		NSLog(@"Stream %@ ended (input: %@)", engine.url, engine.inputError.localizedDescription ?: @"closed");
		// play out the buffered audio, then report the stall (see -tick:)
		engine.ended = YES;
		if (SRAudioRingBufferAvailableFrames(engine.buffer.ring) == 0) {
			[engine stallBecause:@"the stream ended"];
		}
	}];
}

- (void)decoder:(SRFFmpegDecoder *)decoder didReachMetadata:(NSDictionary<NSString *, NSString *> *)metadata atFrame:(uint64_t)frame {
	[self onMainThread:^(SRFFmpegEngine *engine) {
		SRTimedMetadata *timed = [[SRTimedMetadata alloc] init];
		timed.metadata = metadata;
		timed.frame = frame;
		[engine.timeline addObject:timed];
		// frames only grow, but keep the order safe
		[engine.timeline sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(SRTimedMetadata *a, SRTimedMetadata *b) {
			return a.frame < b.frame ? NSOrderedAscending : (a.frame > b.frame ? NSOrderedDescending : NSOrderedSame);
		}];
		[engine deliverDueMetadata];
	}];
}

@end
