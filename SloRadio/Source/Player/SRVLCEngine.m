//
//  SRVLCEngine.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRVLCEngine.h"
#import <MobileVLCKit/MobileVLCKit.h>

// no input, demuxed or decoded data for this long while buffering or playing means the stream stalled
static NSTimeInterval const SRVLCEngineStallTimeout = 5.0;

@interface SRVLCEngine () <VLCMediaDelegate, VLCMediaPlayerDelegate>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSTimeInterval bufferDuration;
@property (nonatomic, strong) VLCMediaListPlayer *listPlayer;
@property (nonatomic, strong) VLCMediaPlayer *player;
@property (nonatomic, strong) VLCMedia *media;
@property (nonatomic, assign) SRRadioPlayerState state;
@property (nonatomic, assign) NSTimeInterval time;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, strong) NSTimer *stallTimer;
@property (nonatomic, assign) VLCMediaStats lastStats;
@property (nonatomic, strong) NSDate *inputTimestamp;
@property (nonatomic, strong) NSDate *demuxTimestamp;
@property (nonatomic, strong) NSDate *decodeTimestamp;

@end

@implementation SRVLCEngine

@synthesize delegate = _delegate;

- (instancetype)initWithURL:(NSURL *)url bufferDuration:(NSTimeInterval)bufferDuration {
	self = [super init];
	if (self) {
		_url = url;
		_bufferDuration = bufferDuration;
		_volume = 1.f;
		_state = SRRadioPlayerStateStopped;
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
	NSArray *options = nil;
	if (self.bufferDuration > 0) {
		options = @[[NSString stringWithFormat:@"--network-caching=%.0f", self.bufferDuration * 1000]];
	}
	self.listPlayer = [[VLCMediaListPlayer alloc] initWithOptions:options];
	self.player = self.listPlayer.mediaPlayer;
	self.player.delegate = self;
	VLCMedia *media = [VLCMedia mediaWithURL:self.url];
	[self registerMedia:media];
	[self.listPlayer setRootMedia:media];
	[self.listPlayer playMedia:media];
	[self updateState];
}

- (void)stop {
	if (!self.started || self.stopped) {
		return;
	}
	self.stopped = YES;
	self.player.delegate = nil;
	[self registerMedia:nil];
	[self.player stop];
	self.player = nil;
	self.listPlayer = nil;
}

- (void)setVolume:(float)volume {
	_volume = volume;
	[self applyVolume];
}

- (void)applyVolume {
	self.player.audio.volume = (int)roundf(self.volume * 100.f);
}

- (NSTimeInterval)playbackTime {
	return self.time;
}

#pragma mark - Media

- (void)registerMedia:(VLCMedia *)media {
	if (self.media != media) {
		[self stopStallTimer];
		if (self.media) {
			[self.media removeObserver:self forKeyPath:@"state"];
		}
		self.media.delegate = nil;
		self.media = media;
		self.media.delegate = self;
		if (self.media) {
			[self.media addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:nil];
			[self startStallTimer];
		}
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (object == self.media && [keyPath isEqualToString:@"state"]) {
		VLCMediaState oldMediaState = [[change objectForKey:NSKeyValueChangeOldKey] integerValue];
		VLCMediaState newMediaState = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
		if (oldMediaState != newMediaState) {
			[self updateState];
		}
	}
}

#pragma mark - Stall detection

- (void)startStallTimer {
	[self stopStallTimer];
	self.lastStats = self.media.statistics;
	NSDate *now = [NSDate date];
	self.inputTimestamp = now;
	self.demuxTimestamp = now;
	self.decodeTimestamp = now;
	self.stallTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(stallTimerFired:) userInfo:nil repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:self.stallTimer forMode:NSRunLoopCommonModes];
}

- (void)stopStallTimer {
	[self.stallTimer invalidate];
	self.stallTimer = nil;
}

- (void)stallTimerFired:(NSTimer *)timer {
	NSDate *now = [NSDate date];
	VLCMediaStats stats = self.media.statistics;
	VLCMediaStats last = self.lastStats;
	if (stats.readBytes != last.readBytes) {
		self.inputTimestamp = now;
	}
	if (stats.demuxReadBytes != last.demuxReadBytes) {
		self.demuxTimestamp = now;
	}
	if (stats.decodedAudio != last.decodedAudio) {
		self.decodeTimestamp = now;
	}
	self.lastStats = stats;
	NSTimeInterval idle = -[[self.inputTimestamp earlierDate:[self.demuxTimestamp earlierDate:self.decodeTimestamp]] timeIntervalSinceDate:now];
	if (idle >= SRVLCEngineStallTimeout &&
		(self.state == SRRadioPlayerStateBuffering || self.state == SRRadioPlayerStatePlaying)) {
		[self stopStallTimer];
		[self.delegate playbackEngineDidStall:self];
	}
}

#pragma mark - VLCMediaPlayerDelegate

- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification {
	self.time = self.player.time.value.doubleValue / 1000.0;
	if (self.state != SRRadioPlayerStatePlaying && self.time > 0) {
		[self updateState];
	}
}

- (void)mediaPlayerStateChanged:(NSNotification *)aNotification {
	[self registerMedia:self.player.media];
	if (self.player.state == VLCMediaPlayerStateESAdded || self.player.state == VLCMediaPlayerStatePlaying) {
		// the volume only sticks once the audio output exists, each new player starts at full volume
		[self applyVolume];
	}
	[self updateState];
}

#pragma mark - VLCMediaDelegate

- (void)mediaMetaDataDidChange:(VLCMedia *)aMedia {
	[self reportMetaData];
}

- (void)mediaDidFinishParsing:(VLCMedia *)aMedia {
	[self reportMetaData];
}

- (void)reportMetaData {
	if (self.stopped) {
		return;
	}
	VLCMediaMetaData *mediaMetaData = self.media.metaData;
	NSMutableDictionary *metaData = [NSMutableDictionary dictionary];
	metaData[SRRadioPlayerMetaDataGenreKey] = mediaMetaData.genre;
	metaData[SRRadioPlayerMetaDataTitleKey] = mediaMetaData.title;
	metaData[SRRadioPlayerMetaDataArtistKey] = mediaMetaData.artist;
	metaData[SRRadioPlayerMetaDataNowPlayingKey] = mediaMetaData.nowPlaying;
	[self.delegate playbackEngine:self didChangeMetaData:metaData];
}

#pragma mark - State

- (void)updateState {
	if (self.stopped) {
		return;
	}
	SRRadioPlayerState state = SRRadioPlayerStateOpening;
	BOOL ended = NO;
	switch (self.player.state) {
		case VLCMediaPlayerStateBuffering:
			state = SRRadioPlayerStateBuffering;
			break;
		case VLCMediaPlayerStatePlaying:
			state = self.time > 0 ? SRRadioPlayerStatePlaying : SRRadioPlayerStateBuffering;
			break;
		case VLCMediaPlayerStatePaused:
			state = SRRadioPlayerStatePaused;
			break;
		case VLCMediaPlayerStateError:
			state = SRRadioPlayerStateError;
			break;
		case VLCMediaPlayerStateESAdded:
			state = self.state == SRRadioPlayerStateStopped ? SRRadioPlayerStateOpening : self.state;
			break;
		case VLCMediaPlayerStateStopped:
		case VLCMediaPlayerStateEnded:
			// the stream ended by itself after it played (e.g. the server closed the connection)
			ended = self.time > 0;
			state = self.state == SRRadioPlayerStateStopped ? SRRadioPlayerStateOpening : self.state;
			break;
		default:
			break;
	}
	if (self.media && self.media.state != VLCMediaStateNothingSpecial) {
		switch (self.media.state) {
			case VLCMediaStateBuffering:
				state = SRRadioPlayerStateBuffering;
				break;
			case VLCMediaStatePlaying:
				state = self.time > 0 ? SRRadioPlayerStatePlaying : SRRadioPlayerStateBuffering;
				break;
			case VLCMediaStateError:
				state = SRRadioPlayerStateError;
				break;
			default:
				break;
		}
	}
	if (state != self.state) {
		self.state = state;
		if (state == SRRadioPlayerStatePlaying) {
			[self applyVolume];
			[self.media parseWithOptions:VLCMediaParseNetwork];
		}
		[self.delegate playbackEngine:self didChangeState:state];
	}
	if (ended && state != SRRadioPlayerStateError && !self.stopped) {
		[self.delegate playbackEngineDidStall:self];
	}
}

@end
