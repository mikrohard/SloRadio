//
//  SRAVPlayerEngine.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRAVPlayerEngine.h"
#import <AVFoundation/AVFoundation.h>

// how long the player may wait for data after it started playing before the stream is considered stalled
static NSTimeInterval const SRAVPlayerEngineStallTimeout = 12.0;

static void *SRAVPlayerEngineItemStatusContext = &SRAVPlayerEngineItemStatusContext;
static void *SRAVPlayerEngineItemTracksContext = &SRAVPlayerEngineItemTracksContext;
static void *SRAVPlayerEngineTimeControlStatusContext = &SRAVPlayerEngineTimeControlStatusContext;

@interface SRAVPlayerEngine () <AVPlayerItemMetadataOutputPushDelegate>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSTimeInterval bufferDuration;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) AVPlayerItemMetadataOutput *metadataOutput;
@property (nonatomic, assign) SRRadioPlayerState state;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, assign) BOOL hasPlayed;
@property (nonatomic, assign) CMTime playbackStartTime;
@property (nonatomic, strong) NSDate *waitingSince;
@property (nonatomic, strong) NSTimer *stallTimer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *metaData;

@end

@implementation SRAVPlayerEngine

@synthesize delegate = _delegate;

- (instancetype)initWithURL:(NSURL *)url bufferDuration:(NSTimeInterval)bufferDuration {
	self = [super init];
	if (self) {
		_url = url;
		_bufferDuration = bufferDuration;
		_volume = 1.f;
		_state = SRRadioPlayerStateStopped;
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

	AVPlayerItem *item = [AVPlayerItem playerItemWithURL:self.url];
	if (self.bufferDuration > 0) {
		item.preferredForwardBufferDuration = self.bufferDuration;
	}
	AVPlayerItemMetadataOutput *metadataOutput = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:nil];
	[metadataOutput setDelegate:self queue:dispatch_get_main_queue()];
	[item addOutput:metadataOutput];

	AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
	// radio: AirPlay should route the audio only, never show a video
	player.allowsExternalPlayback = NO;
	// some HLS radio streams carry a video track, keep playing in the background anyway
	player.audiovisualBackgroundPlaybackPolicy = AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible;
	player.volume = self.volume;

	self.item = item;
	self.metadataOutput = metadataOutput;
	self.player = player;

	NSKeyValueObservingOptions options = NSKeyValueObservingOptionNew;
	[item addObserver:self forKeyPath:@"status" options:options context:SRAVPlayerEngineItemStatusContext];
	[item addObserver:self forKeyPath:@"tracks" options:options context:SRAVPlayerEngineItemTracksContext];
	[player addObserver:self forKeyPath:@"timeControlStatus" options:options context:SRAVPlayerEngineTimeControlStatusContext];
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(itemFailedToPlayToEnd:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
	[nc addObserver:self selector:@selector(itemDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];

	self.stallTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(stallTimerFired:) userInfo:nil repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:self.stallTimer forMode:NSRunLoopCommonModes];

	[self setStateAndNotify:SRRadioPlayerStateOpening];
	[player play];
}

- (void)stop {
	if (!self.started || self.stopped) {
		return;
	}
	self.stopped = YES;
	[self.stallTimer invalidate];
	self.stallTimer = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self.item removeObserver:self forKeyPath:@"status" context:SRAVPlayerEngineItemStatusContext];
	[self.item removeObserver:self forKeyPath:@"tracks" context:SRAVPlayerEngineItemTracksContext];
	[self.player removeObserver:self forKeyPath:@"timeControlStatus" context:SRAVPlayerEngineTimeControlStatusContext];
	[self.metadataOutput setDelegate:nil queue:nil];
	[self.player pause];
	[self.player replaceCurrentItemWithPlayerItem:nil];
	self.player = nil;
	self.item = nil;
	self.metadataOutput = nil;
}

- (void)setVolume:(float)volume {
	_volume = volume;
	self.player.volume = volume;
}

- (NSTimeInterval)playbackTime {
	if (!self.hasPlayed || !self.player) {
		return 0.0;
	}
	NSTimeInterval time = CMTimeGetSeconds(CMTimeSubtract(self.player.currentTime, self.playbackStartTime));
	return isfinite(time) ? MAX(time, 0.0) : 0.0;
}

#pragma mark - State

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == SRAVPlayerEngineItemStatusContext || context == SRAVPlayerEngineTimeControlStatusContext) {
		[self performOnMainThread:^(SRAVPlayerEngine *engine) {
			[engine updateState];
		}];
	} else if (context == SRAVPlayerEngineItemTracksContext) {
		[self performOnMainThread:^(SRAVPlayerEngine *engine) {
			[engine disableVideoTracks];
		}];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)performOnMainThread:(void (^)(SRAVPlayerEngine *engine))block {
	// KVO notifications for AVPlayerItem may arrive on any thread
	__weak SRAVPlayerEngine *weakSelf = self;
	void (^guarded)(void) = ^{
		SRAVPlayerEngine *engine = weakSelf;
		if (engine && !engine.stopped) {
			block(engine);
		}
	};
	if ([NSThread isMainThread]) {
		guarded();
	} else {
		dispatch_async(dispatch_get_main_queue(), guarded);
	}
}

- (void)updateState {
	if (self.state == SRRadioPlayerStateError) {
		return;
	}
	SRRadioPlayerState state = self.state;
	if (self.item.status == AVPlayerItemStatusFailed || self.player.status == AVPlayerStatusFailed) {
		state = SRRadioPlayerStateError;
	} else {
		switch (self.player.timeControlStatus) {
			case AVPlayerTimeControlStatusPlaying:
				state = SRRadioPlayerStatePlaying;
				break;
			case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
				state = self.item.status == AVPlayerItemStatusUnknown ? SRRadioPlayerStateOpening : SRRadioPlayerStateBuffering;
				break;
			case AVPlayerTimeControlStatusPaused:
				// only paused by the system (e.g. an audio session interruption), never by us
				state = self.hasPlayed ? SRRadioPlayerStatePaused : self.state;
				break;
		}
	}
	if (state == SRRadioPlayerStatePlaying && !self.hasPlayed) {
		self.hasPlayed = YES;
		self.playbackStartTime = self.player.currentTime;
	}
	if (state == SRRadioPlayerStateBuffering || state == SRRadioPlayerStateOpening) {
		if (!self.waitingSince) {
			self.waitingSince = [NSDate date];
		}
	} else {
		self.waitingSince = nil;
	}
	if (state == SRRadioPlayerStateError) {
		NSLog(@"AVPlayer failed to play %@: %@", self.url, self.item.error ?: self.player.error);
	}
	[self setStateAndNotify:state];
}

- (void)setStateAndNotify:(SRRadioPlayerState)state {
	if (state != self.state) {
		self.state = state;
		[self.delegate playbackEngine:self didChangeState:state];
	}
}

- (void)stallTimerFired:(NSTimer *)timer {
	// AVPlayer keeps waiting for data forever, report a stall so the stream is reconnected
	if (self.hasPlayed && self.waitingSince && -[self.waitingSince timeIntervalSinceNow] >= SRAVPlayerEngineStallTimeout) {
		self.waitingSince = nil;
		[self.delegate playbackEngineDidStall:self];
	}
}

- (void)itemFailedToPlayToEnd:(NSNotification *)notification {
	[self performOnMainThread:^(SRAVPlayerEngine *engine) {
		NSLog(@"AVPlayer stream %@ failed: %@", engine.url, notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]);
		[engine.delegate playbackEngineDidStall:engine];
	}];
}

- (void)itemDidPlayToEnd:(NSNotification *)notification {
	// a live stream shouldn't end (e.g. the playlist got an #EXT-X-ENDLIST), reconnect
	[self performOnMainThread:^(SRAVPlayerEngine *engine) {
		[engine.delegate playbackEngineDidStall:engine];
	}];
}

- (void)disableVideoTracks {
	for (AVPlayerItemTrack *track in self.item.tracks) {
		if ([track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo] && track.enabled) {
			track.enabled = NO;
		}
	}
}

#pragma mark - AVPlayerItemMetadataOutputPushDelegate

- (void)metadataOutput:(AVPlayerItemMetadataOutput *)output didOutputTimedMetadataGroups:(NSArray<AVTimedMetadataGroup *> *)groups fromPlayerItemTrack:(AVPlayerItemTrack *)track {
	if (self.stopped) {
		return;
	}
	BOOL changed = NO;
	for (AVTimedMetadataGroup *group in groups) {
		for (AVMetadataItem *item in group.items) {
			NSString *key = [SRAVPlayerEngine metaDataKeyForItem:item];
			NSString *value = key ? [SRAVPlayerEngine stringValueForItem:item] : nil;
			if (key && value && ![self.metaData[key] isEqualToString:value]) {
				self.metaData[key] = value;
				changed = YES;
			}
		}
	}
	if (changed) {
		[self.delegate playbackEngine:self didChangeMetaData:[self.metaData copy]];
	}
}

+ (NSString *)metaDataKeyForItem:(AVMetadataItem *)item {
	AVMetadataIdentifier identifier = item.identifier;
	if ([identifier isEqualToString:AVMetadataIdentifierIcyMetadataStreamTitle]) {
		return SRRadioPlayerMetaDataNowPlayingKey;
	}
	if ([identifier isEqualToString:AVMetadataIdentifierID3MetadataTitleDescription] ||
		[item.commonKey isEqualToString:AVMetadataCommonKeyTitle]) {
		return SRRadioPlayerMetaDataTitleKey;
	}
	if ([identifier isEqualToString:AVMetadataIdentifierID3MetadataLeadPerformer] ||
		[item.commonKey isEqualToString:AVMetadataCommonKeyArtist]) {
		return SRRadioPlayerMetaDataArtistKey;
	}
	if ([identifier isEqualToString:AVMetadataIdentifierID3MetadataContentType] ||
		[item.commonKey isEqualToString:AVMetadataCommonKeyType]) {
		return SRRadioPlayerMetaDataGenreKey;
	}
	return nil;
}

+ (NSString *)stringValueForItem:(AVMetadataItem *)item {
	// timed metadata items are delivered fully loaded, reading the value synchronously doesn't block
	id value = item.value;
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSData class]]) {
		NSString *string = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
		return string ?: [[NSString alloc] initWithData:value encoding:NSISOLatin1StringEncoding];
	}
	return nil;
}

@end
