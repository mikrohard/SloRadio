//
//  SRRadioPlayerNetworkTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//
//  Plays real stations, so these tests need network access and are skipped unless SR_NETWORK_TESTS=1:
//  TEST_RUNNER_SR_NETWORK_TESTS=1 xcodebuild test -scheme SloRadio -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
//

#import <XCTest/XCTest.h>
#import "SRRadioPlayer.h"
#import "SRStreamResolver.h"

static NSTimeInterval const SRNetworkTestTimeout = 30.0;

@interface SRRadioPlayerNetworkTests : XCTestCase <SRRadioPlayerDelegate>

@property (nonatomic, strong) SRRadioPlayer *player;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *states;
@property (nonatomic, strong) XCTestExpectation *playingExpectation;
@property (nonatomic, strong) XCTestExpectation *metaDataExpectation;

@end

@implementation SRRadioPlayerNetworkTests

- (void)setUp {
	[super setUp];
	if (![[NSProcessInfo processInfo].environment[@"SR_NETWORK_TESTS"] isEqualToString:@"1"]) {
		XCTSkip(@"network tests are disabled, set SR_NETWORK_TESTS=1 to run them");
	}
	self.continueAfterFailure = NO;
	self.player = [[SRRadioPlayer alloc] init];
	self.player.delegate = self;
	// silent, the tests only check that audio is decoded
	[self.player setVolume:0];
	self.states = [NSMutableArray array];
}

- (void)tearDown {
	self.player.delegate = nil;
	[self.player stop];
	self.player = nil;
	[super tearDown];
}

#pragma mark - Helpers

- (void)playAndWaitForPlaying:(NSString *)urlString {
	self.playingExpectation = [self expectationWithDescription:@"playing"];
	[self.player playStreamAtUrl:[NSURL URLWithString:urlString]];
	[self waitForExpectations:@[self.playingExpectation] timeout:SRNetworkTestTimeout];
	self.playingExpectation = nil;
	XCTAssertFalse([self.states containsObject:@(SRRadioPlayerStateError)], @"states: %@", self.states);
	XCTAssertFalse([self.states containsObject:@(SRRadioPlayerStateStopped)], @"states: %@", self.states);
	XCTAssertEqualObjects(self.states.firstObject, @(SRRadioPlayerStateOpening));
}

- (void)assertTimeAdvances {
	NSTimeInterval start = self.player.timePlaying;
	[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3.0]];
	XCTAssertEqual(self.player.state, SRRadioPlayerStatePlaying);
	XCTAssertGreaterThan(self.player.timePlaying - start, 1.5);
}

- (NSString *)engineClassName {
	return NSStringFromClass([[self.player valueForKey:@"engine"] class]);
}

#pragma mark - SRRadioPlayerDelegate

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state {
	[self.states addObject:@(state)];
	if (state == SRRadioPlayerStatePlaying) {
		[self.playingExpectation fulfill];
		self.playingExpectation = nil;
	}
}

- (void)radioPlayer:(SRRadioPlayer *)player didChangeMetaData:(NSDictionary *)metadata {
	if ([metadata[SRRadioPlayerMetaDataNowPlayingKey] length] > 0) {
		[self.metaDataExpectation fulfill];
		self.metaDataExpectation = nil;
	}
}

#pragma mark - Tests

- (void)testHLSPlaysWithAVPlayer {
	// Radio KAOS: HLS with an H.264 video track and an incomplete certificate chain
	[self playAndWaitForPlaying:@"https://stream.radiokaos.info:4433/hls/radiokaos/index.m3u8"];
	XCTAssertEqualObjects([self engineClassName], @"SRAVPlayerEngine");
	[self assertTimeAdvances];
}

- (void)testIcecastPlaysWithMetaData {
	// ARS: Icecast, AAC, ICY metadata
	XCTestExpectation *metaDataExpectation = [self expectationWithDescription:@"now playing"];
	self.metaDataExpectation = metaDataExpectation;
	[self playAndWaitForPlaying:@"http://mp3.rtvslo.si/ars"];
	XCTAssertEqualObjects([self engineClassName], @"SRVLCEngine");
	[self assertTimeAdvances];
	[self waitForExpectations:@[metaDataExpectation] timeout:SRNetworkTestTimeout];
	XCTAssertGreaterThan([self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey] length], 0u);
}

- (void)testShoutcastV1Plays {
	// STUDIO-S answers "ICY 200 OK"
	[self playAndWaitForPlaying:@"http://31.15.234.118:8000"];
	XCTAssertEqualObjects([self engineClassName], @"SRVLCEngine");
	[self assertTimeAdvances];
}

- (void)testPLSIsUnwrapped {
	// Radio M: PLS playlist
	XCTestExpectation *expectation = [self expectationWithDescription:@"resolved"];
	SRStreamResolver *resolver = [[SRStreamResolver alloc] initWithURL:[NSURL URLWithString:@"http://team-data.ba:8030/listen.pls?sid=1"]];
	[resolver resolveWithCompletion:^(NSURL *url, SRStreamFormat format) {
		XCTAssertEqualObjects(url.absoluteString, @"http://team-data.ba:8030/;");
		XCTAssertEqual(format, SRStreamFormatAudio);
		[expectation fulfill];
	}];
	[self waitForExpectations:@[expectation] timeout:SRNetworkTestTimeout];
}

- (void)testStopNotifiesStoppedAndClearsMetaData {
	[self playAndWaitForPlaying:@"http://mp3.rtvslo.si/ars"];
	[self.player stop];
	XCTAssertEqual(self.player.state, SRRadioPlayerStateStopped);
	XCTAssertEqualObjects(self.states.lastObject, @(SRRadioPlayerStateStopped));
	XCTAssertEqual(self.player.metaData.count, 0u);
	XCTAssertEqual(self.player.timePlaying, 0.0);
}

- (void)testSwitchingStationsNeverReportsStopped {
	[self playAndWaitForPlaying:@"http://mp3.rtvslo.si/ars"];
	[self.states removeAllObjects];
	[self playAndWaitForPlaying:@"https://stream.radiokaos.info:4433/hls/radiokaos/index.m3u8"];
	XCTAssertEqualObjects([self engineClassName], @"SRAVPlayerEngine");
}

@end
