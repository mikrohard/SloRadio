//
//  SRRadioPlayerTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//
//  Tests SRRadioPlayer's state handling, reconnecting and meta data clean up with a fake playback engine.
//

#import <XCTest/XCTest.h>
#import "SRRadioPlayer.h"
#import "SRPlaybackEngine.h"
#import "SRStreamResolver.h"
#import "SRDataManager.h"

#pragma mark - Fake engine

@interface SRFakeEngine : NSObject <SRPlaybackEngine>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) NSTimeInterval playbackTime;

- (void)sendState:(SRRadioPlayerState)state;
- (void)sendMetaData:(NSDictionary *)metaData;
- (void)sendStall;

@end

static NSMutableArray<SRFakeEngine *> *SRFakeEngines;

@implementation SRFakeEngine

@synthesize delegate = _delegate;

- (instancetype)initWithURL:(NSURL *)url bufferDuration:(NSTimeInterval)bufferDuration {
	self = [super init];
	if (self) {
		_url = url;
		[SRFakeEngines addObject:self];
	}
	return self;
}

- (void)start {
	self.started = YES;
}

- (void)stop {
	self.stopped = YES;
}

- (void)sendState:(SRRadioPlayerState)state {
	[self.delegate playbackEngine:self didChangeState:state];
}

- (void)sendMetaData:(NSDictionary *)metaData {
	[self.delegate playbackEngine:self didChangeMetaData:metaData];
}

- (void)sendStall {
	[self.delegate playbackEngineDidStall:self];
}

@end

#pragma mark - Player with the fake engine

@interface SRRadioPlayer (Testing)
- (Class)engineClassForFormat:(SRStreamFormat)format;
@end

@interface SRTestRadioPlayer : SRRadioPlayer
@end

@implementation SRTestRadioPlayer

- (Class)engineClassForFormat:(SRStreamFormat)format {
	return [SRFakeEngine class];
}

@end

#pragma mark - Tests

@interface SRRadioPlayerTests : XCTestCase <SRRadioPlayerDelegate>

@property (nonatomic, strong) SRTestRadioPlayer *player;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *states;

@end

@implementation SRRadioPlayerTests

- (void)setUp {
	[super setUp];
	SRFakeEngines = [NSMutableArray array];
	self.states = [NSMutableArray array];
	self.player = [[SRTestRadioPlayer alloc] init];
	self.player.delegate = self;
}

- (void)tearDown {
	self.player.delegate = nil;
	[self.player stop];
	self.player = nil;
	SRFakeEngines = nil;
	[super tearDown];
}

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state {
	[self.states addObject:@(state)];
}

// mms:// isn't loaded by the resolver, so no network is involved
- (SRFakeEngine *)play {
	[self.player playStreamAtUrl:[NSURL URLWithString:@"mms://example.com/live"]];
	return [self waitForEngineCount:1];
}

- (SRFakeEngine *)waitForEngineCount:(NSUInteger)count {
	NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:3.0];
	while (SRFakeEngines.count < count && [timeout timeIntervalSinceNow] > 0) {
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	}
	XCTAssertEqual(SRFakeEngines.count, count);
	return SRFakeEngines.lastObject;
}

- (void)spin:(NSTimeInterval)seconds {
	[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

#pragma mark - State

- (void)testEngineStatesArePassedOn {
	SRFakeEngine *engine = [self play];
	XCTAssertTrue(engine.started);
	XCTAssertEqualObjects(engine.url.absoluteString, @"mms://example.com/live");
	[engine sendState:SRRadioPlayerStateBuffering];
	[engine sendState:SRRadioPlayerStatePlaying];
	NSArray *expected = @[@(SRRadioPlayerStateOpening), @(SRRadioPlayerStateBuffering), @(SRRadioPlayerStatePlaying)];
	XCTAssertEqualObjects(self.states, expected);
	engine.playbackTime = 12.5;
	XCTAssertEqual(self.player.timePlaying, 12.5);
}

- (void)testStopWhileResolvingNeverStartsAnEngine {
	[self.player playStreamAtUrl:[NSURL URLWithString:@"mms://example.com/live"]];
	[self.player stop];
	[self spin:0.2];
	XCTAssertEqual(SRFakeEngines.count, 0u);
	NSArray *expected = @[@(SRRadioPlayerStateOpening), @(SRRadioPlayerStateStopped)];
	XCTAssertEqualObjects(self.states, expected);
}

- (void)testErrorReleasesTheEngine {
	SRFakeEngine *engine = [self play];
	[engine sendState:SRRadioPlayerStateError];
	XCTAssertEqual(self.player.state, SRRadioPlayerStateError);
	XCTAssertTrue(engine.stopped);
	[self spin:0.2];
	XCTAssertEqual(SRFakeEngines.count, 1u, @"errors are not retried");
}

- (void)testMissingURLIsAnError {
	[self.player playStreamAtUrl:nil];
	XCTAssertEqual(self.player.state, SRRadioPlayerStateError);
}

- (void)testSwitchingStreamsStopsTheOldEngineWithoutReportingStopped {
	SRFakeEngine *first = [self play];
	[first sendState:SRRadioPlayerStatePlaying];
	[self.player playStreamAtUrl:[NSURL URLWithString:@"mms://example.com/other"]];
	SRFakeEngine *second = [self waitForEngineCount:2];
	XCTAssertTrue(first.stopped);
	XCTAssertFalse(second.stopped);
	XCTAssertFalse([self.states containsObject:@(SRRadioPlayerStateStopped)]);
	XCTAssertEqualObjects(self.states.lastObject, @(SRRadioPlayerStateOpening));
}

#pragma mark - Reconnecting

- (void)testStallReconnectsWithBackoff {
	SRFakeEngine *first = [self play];
	[first sendState:SRRadioPlayerStatePlaying];

	// first reconnect is immediate
	[first sendStall];
	XCTAssertTrue(first.stopped);
	XCTAssertEqual(self.player.state, SRRadioPlayerStateBuffering);
	SRFakeEngine *second = [self waitForEngineCount:2];
	XCTAssertEqualObjects(second.url, first.url);
	XCTAssertTrue(second.started);

	// the new engine opening the stream keeps the player buffering
	[self.states removeAllObjects];
	[second sendState:SRRadioPlayerStateOpening];
	XCTAssertEqual(self.player.state, SRRadioPlayerStateBuffering);
	XCTAssertEqual(self.states.count, 0u);

	// it fails again without playing: wait a second before the next attempt
	[second sendStall];
	[self spin:0.5];
	XCTAssertEqual(SRFakeEngines.count, 2u);
	SRFakeEngine *third = [self waitForEngineCount:3];

	// once playing again the next stall reconnects immediately
	[third sendState:SRRadioPlayerStatePlaying];
	[third sendStall];
	[self spin:0.1];
	XCTAssertEqual(SRFakeEngines.count, 4u);
}

- (void)testCallbacksFromReplacedEnginesAreIgnored {
	SRFakeEngine *first = [self play];
	[first sendState:SRRadioPlayerStatePlaying];
	[first sendStall];
	[self waitForEngineCount:2];
	[first sendState:SRRadioPlayerStateError];
	[first sendMetaData:@{SRRadioPlayerMetaDataNowPlayingKey: @"stale"}];
	[first sendStall];
	[self spin:0.1];
	XCTAssertEqual(self.player.state, SRRadioPlayerStateBuffering);
	XCTAssertNil(self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey]);
	XCTAssertEqual(SRFakeEngines.count, 2u);
}

- (void)testStopCancelsAPendingReconnect {
	SRFakeEngine *first = [self play];
	[first sendStall];
	[self waitForEngineCount:2];
	[SRFakeEngines.lastObject sendStall];	// next attempt is a second away
	[self.player stop];
	[self spin:1.5];
	XCTAssertEqual(SRFakeEngines.count, 2u);
	XCTAssertEqual(self.player.state, SRRadioPlayerStateStopped);
}

#pragma mark - Meta data

- (void)testMetaDataIsCleanedUp {
	SRFakeEngine *engine = [self play];
	[engine sendMetaData:@{SRRadioPlayerMetaDataNowPlayingKey: @"  JANI KOVA&#x10D;I&#x10D;  - DELAM ",
						   SRRadioPlayerMetaDataGenreKey: @"Pop"}];
	// &#x10D; is a lowercase č, decoded exactly as the station (Radio Capris Slo) sends it
	XCTAssertEqualObjects(self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey], @"JANI KOVA\u010DI\u010D - DELAM");
	XCTAssertEqualObjects(self.player.metaData[SRRadioPlayerMetaDataGenreKey], @"Pop");
	[engine sendMetaData:@{SRRadioPlayerMetaDataNowPlayingKey: @"SALT&#39;N&#39;PEPA - LET&#39;S TALK ABOUT SEX"}];
	XCTAssertEqualObjects(self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey], @"SALT'N'PEPA - LET'S TALK ABOUT SEX");
	[engine sendMetaData:@{SRRadioPlayerMetaDataNowPlayingKey: @"MARKO &Scaron;KUGOR - Sreča AXWELL &amp; INGROSSO"}];
	XCTAssertEqualObjects(self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey], @"MARKO ŠKUGOR - Sreča AXWELL & INGROSSO");
}

- (void)testNowPlayingIsKeptUntilReplacedOrCleared {
	SRFakeEngine *engine = [self play];
	[engine sendMetaData:@{SRRadioPlayerMetaDataNowPlayingKey: @"ED SHEERAN - SAPPHIRE"}];
	// an update with only the static stream info keeps the song
	[engine sendMetaData:@{SRRadioPlayerMetaDataGenreKey: @"Pop"}];
	XCTAssertEqualObjects(self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey], @"ED SHEERAN - SAPPHIRE");
	// an empty title (e.g. " - " during ads) clears it
	[engine sendMetaData:@{SRRadioPlayerMetaDataNowPlayingKey: @" - "}];
	XCTAssertEqualObjects(self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey], @"");
}

- (void)testMetaDataSurvivesReconnectAndIsClearedOnStop {
	SRFakeEngine *engine = [self play];
	[engine sendMetaData:@{SRRadioPlayerMetaDataNowPlayingKey: @"ED SHEERAN - SAPPHIRE"}];
	[engine sendStall];
	[self waitForEngineCount:2];
	XCTAssertEqualObjects(self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey], @"ED SHEERAN - SAPPHIRE");
	[self.player stop];
	XCTAssertEqual(self.player.metaData.count, 0u);
}

#pragma mark - Volume

- (void)testVolumeCombinesFadeAndAppVolume {
	SRFakeEngine *engine = [self play];
	float appVolume = [SRDataManager sharedManager].playerVolume;
	XCTAssertEqualWithAccuracy(engine.volume, appVolume, 0.001);
	[self.player setVolume:50];
	XCTAssertEqualWithAccuracy(engine.volume, appVolume * 0.5f, 0.001);
	// reconnected engines get the current volume
	[engine sendStall];
	SRFakeEngine *second = [self waitForEngineCount:2];
	XCTAssertEqualWithAccuracy(second.volume, appVolume * 0.5f, 0.001);
}

@end
