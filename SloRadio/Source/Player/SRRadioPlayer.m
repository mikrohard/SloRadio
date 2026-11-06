//
//  SRRadioPlayer.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioPlayer.h"
#import "SRRadioStation.h"
#import "SRDataManager.h"
#import "SRPlaybackEngine.h"
#import "SRStreamResolver.h"
#import "SRAVPlayerEngine.h"
#import "SRFFmpegEngine.h"
#import "SRAudioOutput.h"
#import "NSString+Additions.h"

NSString * const SRRadioPlayerStateDidChangeNotification = @"SRRadioPlayerStateDidChangeNotification";
NSString * const SRRadioPlayerMetaDataDidChangeNotification = @"SRRadioPlayerMetaDataDidChangeNotification";
NSString * const SRRadioPlayerMetaDataArtistKey = @"SRRadioPlayerMetaDataArtistKey";
NSString * const SRRadioPlayerMetaDataTitleKey = @"SRRadioPlayerMetaDataTitleKey";
NSString * const SRRadioPlayerMetaDataGenreKey = @"SRRadioPlayerMetaDataGenreKey";
NSString * const SRRadioPlayerMetaDataNowPlayingKey = @"SRRadioPlayerMetaDataNowPlayingKey";

// reconnect delays after consecutive stalls: immediately, then 1, 2, 4, 8, 10, 10, ... seconds
static NSTimeInterval const SRRadioPlayerMaxReconnectDelay = 10.0;

@interface SRRadioPlayer () <SRPlaybackEngineDelegate>

@property (nonatomic, strong) id<SRPlaybackEngine> engine;
@property (nonatomic, strong) SRStreamResolver *resolver;
@property (nonatomic, strong) NSURL *streamURL;
@property (nonatomic, assign) SRStreamFormat streamFormat;
@property (nonatomic, strong) NSTimer *reconnectTimer;
@property (nonatomic, assign) NSUInteger reconnectCount;
@property (nonatomic, assign) int fadeVolume;
@property (nonatomic, strong) SRSilenceOutput *silence;

@end

@implementation SRRadioPlayer

@synthesize state = _state;
@synthesize currentRadioStation = _currentRadioStation;
@synthesize metaData = _metaData;
@synthesize delegate = _delegate;

#pragma mark - Singleton

+ (SRRadioPlayer *)sharedPlayer {
	static SRRadioPlayer *sharedRadioPlayer;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedRadioPlayer = [[self alloc] init];
	});
	return sharedRadioPlayer;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_fadeVolume = 100;
		_state = SRRadioPlayerStateStopped;
		_metaData = @{};
	}
	return self;
}

- (void)dealloc {
	[self tearDownPlayback];
}

#pragma mark - Playback control

- (void)playRadioStation:(SRRadioStation *)station {
	_currentRadioStation = station;
	[self startStreamAtUrl:station.url];
}

- (void)playStreamAtUrl:(NSURL *)url {
	_currentRadioStation = nil;
	[self startStreamAtUrl:url];
}

- (void)startStreamAtUrl:(NSURL *)url {
	[self tearDownPlayback];
	self.streamURL = url;
	self.reconnectCount = 0;
	[self setMetaDataAndNotify:@{}];
	if (!url) {
		[self setStateAndNotify:SRRadioPlayerStateError];
		return;
	}
	[self setStateAndNotify:SRRadioPlayerStateOpening];

	SRStreamResolver *resolver = [[SRStreamResolver alloc] initWithURL:url];
	self.resolver = resolver;
	__weak SRRadioPlayer *weakSelf = self;
	[resolver resolveWithCompletion:^(NSURL *resolvedURL, SRStreamFormat format) {
		SRRadioPlayer *player = weakSelf;
		if (player.resolver != resolver) {
			return;
		}
		player.resolver = nil;
		// reconnects reuse the resolved stream
		player.streamURL = resolvedURL;
		player.streamFormat = format;
		[player startEngine];
	}];
}

- (void)startEngine {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	NSTimeInterval bufferDuration = dataManager.playerCachingEnabled ? dataManager.playerCacheSize : 0.0;
	Class engineClass = [self engineClassForFormat:self.streamFormat];
	id<SRPlaybackEngine> engine = [[engineClass alloc] initWithURL:self.streamURL bufferDuration:bufferDuration];
	engine.delegate = self;
	self.engine = engine;
	[self updateVolume];
	[engine start];
}

// Overridden by tests to inject a fake engine.
- (Class)engineClassForFormat:(SRStreamFormat)format {
	if (format == SRStreamFormatHLS) {
		return [SRAVPlayerEngine class];
	}
	return [SRFFmpegEngine class];
}

- (void)stop {
	[self tearDownPlayback];
	[self setStateAndNotify:SRRadioPlayerStateStopped];
	_currentRadioStation = nil;
	[self setMetaDataAndNotify:@{}];
}

// Stops everything that is going on without notifying anybody.
- (void)tearDownPlayback {
	[self.resolver cancel];
	self.resolver = nil;
	[self.reconnectTimer invalidate];
	self.reconnectTimer = nil;
	self.engine.delegate = nil;
	[self.engine stop];
	self.engine = nil;
}

- (NSTimeInterval)timePlaying {
	return self.engine.playbackTime;
}

#pragma mark - Reconnecting

- (void)reconnect {
	self.engine.delegate = nil;
	[self.engine stop];
	self.engine = nil;
	[self.reconnectTimer invalidate];

	NSTimeInterval delay = 0.0;
	if (self.reconnectCount > 0) {
		delay = MIN(pow(2.0, self.reconnectCount - 1), SRRadioPlayerMaxReconnectDelay);
	}
	self.reconnectCount++;
	[self setStateAndNotify:SRRadioPlayerStateBuffering];
	self.reconnectTimer = [NSTimer timerWithTimeInterval:delay target:self selector:@selector(reconnectTimerFired:) userInfo:nil repeats:NO];
	[[NSRunLoop mainRunLoop] addTimer:self.reconnectTimer forMode:NSRunLoopCommonModes];
}

- (void)reconnectTimerFired:(NSTimer *)timer {
	self.reconnectTimer = nil;
	[self startEngine];
}

#pragma mark - Volume

- (void)setVolume:(int)volume {
	self.fadeVolume = volume;
	[self updateVolume];
}

- (void)updateVolume {
	float volume = self.fadeVolume / 100.f * [SRDataManager sharedManager].playerVolume;
	[self.engine setVolume:MIN(MAX(volume, 0.f), 1.f)];
}

#pragma mark - SRPlaybackEngineDelegate

- (void)playbackEngine:(id<SRPlaybackEngine>)engine didChangeState:(SRRadioPlayerState)state {
	if (engine != self.engine) {
		return;
	}
	if (state == SRRadioPlayerStatePlaying) {
		self.reconnectCount = 0;
	}
	if (state == SRRadioPlayerStateError) {
		[self tearDownPlayback];
	}
	if (state == SRRadioPlayerStateOpening && self.state == SRRadioPlayerStateBuffering) {
		// a reconnecting engine opens the stream again, keep showing that we are buffering
		return;
	}
	[self setStateAndNotify:state];
}

- (void)playbackEngine:(id<SRPlaybackEngine>)engine didChangeMetaData:(NSDictionary<NSString *, NSString *> *)rawMetaData {
	if (engine != self.engine) {
		return;
	}
	NSMutableDictionary *metaData = [NSMutableDictionary dictionary];
	for (NSString *key in rawMetaData) {
		NSString *value = [self decodedMetadataString:rawMetaData[key]];
		if (value) {
			metaData[key] = value;
		}
	}
	if (!metaData[SRRadioPlayerMetaDataNowPlayingKey] && self.metaData[SRRadioPlayerMetaDataNowPlayingKey]) {
		// some updates only carry the static stream info, keep the current song
		metaData[SRRadioPlayerMetaDataNowPlayingKey] = self.metaData[SRRadioPlayerMetaDataNowPlayingKey];
	}
	[self setMetaDataAndNotify:metaData];
}

- (void)playbackEngineDidStall:(id<SRPlaybackEngine>)engine {
	if (engine != self.engine) {
		return;
	}
	NSLog(@"Stream %@ stalled, reconnecting (attempt %lu)", self.streamURL, (unsigned long)self.reconnectCount + 1);
	[self reconnect];
}

#pragma mark - State and meta data

- (void)setStateAndNotify:(SRRadioPlayerState)state {
	if (state != _state) {
		_state = state;
		[self updateSilence];
		[[NSNotificationCenter defaultCenter] postNotificationName:SRRadioPlayerStateDidChangeNotification
															object:self];
		if ([self.delegate respondsToSelector:@selector(radioPlayer:didChangeState:)]) {
			[self.delegate radioPlayer:self didChangeState:_state];
		}
	}
}

// Bridges the gaps without audio while a station is opened or buffered (see SRSilenceOutput).
// Not needed on the Mac, where the now playing state is set explicitly.
- (void)updateSilence {
	BOOL loading = _state == SRRadioPlayerStateOpening || _state == SRRadioPlayerStateBuffering;
	if (loading && ![NSProcessInfo processInfo].isMacCatalystApp) {
		if (!self.silence) {
			self.silence = [[SRSilenceOutput alloc] init];
		}
		[self.silence start];
	} else {
		[self.silence stop];
	}
}

- (void)setMetaDataAndNotify:(NSDictionary *)metaData {
	_metaData = [NSDictionary dictionaryWithDictionary:metaData];
	if ([self.delegate respondsToSelector:@selector(radioPlayer:didChangeMetaData:)]) {
		[self.delegate radioPlayer:self didChangeMetaData:self.metaData];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:SRRadioPlayerMetaDataDidChangeNotification
														object:self
													  userInfo:_metaData];
}

- (NSString *)decodedMetadataString:(NSString *)input {
	if (![input isKindOfClass:[NSString class]]) {
		return nil;
	}
	NSString *output = [input stringByStrippingHTML];
	NSRegularExpression *expr = [NSRegularExpression regularExpressionWithPattern:@"&[#a-zA-Z0-9]+;"
																		  options:NSRegularExpressionCaseInsensitive
																			error:nil];
	if ([expr numberOfMatchesInString:input options:0 range:NSMakeRange(0, input.length)]) {
		NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
		if (data != nil) {
			NSAttributedString *attrStr = [[NSAttributedString alloc] initWithData:data
																		   options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
																					 NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)}
																documentAttributes:nil
																			 error:nil];
			if (attrStr.string != nil) {
				output = attrStr.string;
			}
		}
	}

	// trim output string
	if (output != nil) {
		NSMutableCharacterSet *set = [NSMutableCharacterSet characterSetWithCharactersInString:@"-"];
		[set formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
		output = [output stringByTrimmingCharactersInSet:set];
	}

	// cleanup multiple spaces
	if (output != nil) {
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
		output = [regex stringByReplacingMatchesInString:output options:0 range:NSMakeRange(0, output.length) withTemplate:@" "];
	}

	// an empty string is kept: it clears the current song (e.g. during ads)
	return output;
}

@end
