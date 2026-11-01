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
#import "SRStreamInput.h"
#import "SRByteQueue.h"

static NSTimeInterval const SRNetworkTestTimeout = 30.0;

@interface SRRadioPlayerNetworkTests : XCTestCase <SRRadioPlayerDelegate>

@property (nonatomic, strong) SRRadioPlayer *player;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *states;
@property (nonatomic, strong) XCTestExpectation *playingExpectation;
@property (nonatomic, strong) XCTestExpectation *metaDataExpectation;
@property (nonatomic, strong) XCTestExpectation *titleExpectation;

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
	if ([metadata[SRRadioPlayerMetaDataTitleKey] length] > 0 && [metadata[SRRadioPlayerMetaDataArtistKey] length] > 0) {
		[self.titleExpectation fulfill];
		self.titleExpectation = nil;
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
	XCTAssertEqualObjects([self engineClassName], @"SRFFmpegEngine");
	[self assertTimeAdvances];
	[self waitForExpectations:@[metaDataExpectation] timeout:SRNetworkTestTimeout];
	XCTAssertGreaterThan([self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey] length], 0u);
}

- (void)testShoutcastV1Plays {
	// STUDIO-S answers "ICY 200 OK"
	XCTestExpectation *metaDataExpectation = [self expectationWithDescription:@"now playing"];
	self.metaDataExpectation = metaDataExpectation;
	[self playAndWaitForPlaying:@"http://31.15.234.118:8000"];
	XCTAssertEqualObjects([self engineClassName], @"SRFFmpegEngine");
	[self assertTimeAdvances];
	// its in-body ICY headers were parsed, so the metadata is separated from the audio
	[self waitForExpectations:@[metaDataExpectation] timeout:SRNetworkTestTimeout];
}

- (void)testOggVorbisCommentsAreMetaData {
	// Radio Net: Ogg Vorbis, titles in Vorbis comments instead of ICY metadata
	XCTestExpectation *metaDataExpectation = [self expectationWithDescription:@"title and artist"];
	self.titleExpectation = metaDataExpectation;
	[self playAndWaitForPlaying:@"https://stream.radionet.si/stream.ogg"];
	XCTAssertEqualObjects([self engineClassName], @"SRFFmpegEngine");
	[self assertTimeAdvances];
	[self waitForExpectations:@[metaDataExpectation] timeout:SRNetworkTestTimeout];
}

- (void)testHEAACPlays {
	// Center 80-a: HE-AAC (the AudioToolbox decoder failed on it)
	[self playAndWaitForPlaying:@"http://stream3.radiocenter.si:8064/;stream/1"];
	XCTAssertEqualObjects([self engineClassName], @"SRFFmpegEngine");
	[self assertTimeAdvances];
}

- (void)testWindows1250TitlesAreDecoded {
	// these stations send Windows-1250 titles, mostly with č, š and ž
	for (NSString *url in @[@"http://zvok.ragla.si/rrprk", @"http://93.103.130.12/tomi.mp3"]) {
		XCTestExpectation *metaDataExpectation = [self expectationWithDescription:url];
		self.metaDataExpectation = metaDataExpectation;
		[self playAndWaitForPlaying:url];
		[self waitForExpectations:@[metaDataExpectation] timeout:SRNetworkTestTimeout];
		NSString *title = self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey];
		NSLog(@"%@ title: %@", url, title);
		NSCharacterSet *mojibake = [NSCharacterSet characterSetWithCharactersInString:@"\uFFFD\u00C3\u00C4\u00C5\u00E8\u00B9\u00BE"];
		XCTAssertEqual([title rangeOfCharacterFromSet:mojibake].location, NSNotFound, @"%@", title);
		[self.player stop];
		[self.states removeAllObjects];
	}
}

- (void)testShoutcastV2WithoutMetaDataPlays {
	// Radio Rogla: Shoutcast v2 that sends no icy-metaint
	[self playAndWaitForPlaying:@"http://193.105.67.24:8010/;?type=http&nocache=3804"];
	XCTAssertEqualObjects([self engineClassName], @"SRFFmpegEngine");
	[self assertTimeAdvances];
}

- (void)testVLCEngineCanStillBeSelected {
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SRPlayerUseVLCEngine"];
	[self addTeardownBlock:^{
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SRPlayerUseVLCEngine"];
	}];
	[self playAndWaitForPlaying:@"http://mp3.rtvslo.si/ars"];
	XCTAssertEqualObjects([self engineClassName], @"SRVLCEngine");
	[self assertTimeAdvances];
}

// Plays every station of the stations API for a few seconds. Slow (several minutes), so it only runs with
// SR_ALL_STATIONS=1 on top of SR_NETWORK_TESTS=1.
- (void)testAllStationsPlay {
	if (![[NSProcessInfo processInfo].environment[@"SR_ALL_STATIONS"] isEqualToString:@"1"]) {
		XCTSkip(@"set SR_ALL_STATIONS=1 to play every station");
	}
	NSData *json = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://iphone.jernej.org/sloradio/stations.php"]];
	NSArray *stations = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil][@"stations"];
	XCTAssertGreaterThan(stations.count, 100u);
	NSMutableArray *failed = [NSMutableArray array];
	NSCountedSet *engines = [NSCountedSet set];
	for (NSDictionary *station in stations) {
		@autoreleasepool {
			[self.states removeAllObjects];
			self.playingExpectation = [self expectationWithDescription:station[@"name"]];
			[self.player playStreamAtUrl:[NSURL URLWithString:station[@"url"]]];
			XCTWaiterResult result = [XCTWaiter waitForExpectations:@[self.playingExpectation] timeout:20.0];
			self.playingExpectation = nil;
			NSTimeInterval start = self.player.timePlaying;
			[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
			BOOL playing = result == XCTWaiterResultCompleted && self.player.state == SRRadioPlayerStatePlaying && self.player.timePlaying - start > 1.0;
			NSString *engine = [self engineClassName];
			[engines addObject:engine ?: @"none"];
			NSLog(@"STATION %@ %@ via %@, title: %@", playing ? @"OK  " : @"FAIL", station[@"name"], engine,
				  self.player.metaData[SRRadioPlayerMetaDataNowPlayingKey] ?: self.player.metaData[SRRadioPlayerMetaDataTitleKey]);
			if (!playing) {
				if ([self isReachable:[NSURL URLWithString:station[@"url"]]]) {
					[failed addObject:[NSString stringWithFormat:@"%@ (%@, states %@)", station[@"name"], station[@"url"], self.states]];
				} else {
					NSLog(@"STATION OFFLINE %@: the server can't be reached at all", station[@"name"]);
				}
			}
			[self.player stop];
		}
	}
	NSLog(@"STATIONS played with %@", engines);
	XCTAssertEqual(failed.count, 0u, @"%lu of %lu stations failed: %@", (unsigned long)failed.count, (unsigned long)stations.count, failed);
}

- (void)testDownloadPausesAndResumesWhenTheQueueIsFull {
	// ARS sends 192 kbit/s, read only 128 kbit/s from a tiny queue: the download is paused and resumed over and over
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:32 * 1024];
	SRStreamInput *input = [[SRStreamInput alloc] initWithURL:[NSURL URLWithString:@"http://mp3.rtvslo.si/ars"] queue:queue];
	[input start];
	__block NSInteger total = 0;
	__block BOOL failed = NO;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		uint8_t bytes[4000];
		NSDate *end = [NSDate dateWithTimeIntervalSinceNow:20];
		while ([end timeIntervalSinceNow] > 0) {
			NSInteger count = [queue readBytes:bytes maxLength:sizeof(bytes)];
			if (count <= 0) {
				failed = YES;
				break;
			}
			total += count;
			usleep(250000);	// 4000 bytes every 0.25 s = 128 kbit/s
		}
		dispatch_semaphore_signal(done);
	});
	while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW) != 0) {
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	}
	[input cancel];
	// (how much was downloaded in total isn't checked: while a task is paused the system keeps receiving
	// into its socket buffers and hands everything over on resume, so that depends on the kernel)
	XCTAssertFalse(failed, @"the download failed: %@", queue.error);
	XCTAssertGreaterThan(total, 280000);
}

// Whether the server responds at all (a station whose server is down isn't a player failure).
- (BOOL)isReachable:(NSURL *)url {
	NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	configuration.timeoutIntervalForRequest = 8.0;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
	NSURLSessionDataTask *task = [session dataTaskWithURL:url];
	[task resume];
	// the response headers are enough, a stream never completes
	NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:10];
	while ([timeout timeIntervalSinceNow] > 0 && task.state == NSURLSessionTaskStateRunning && task.response == nil) {
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	}
	BOOL reachable = task.response != nil;
	[session invalidateAndCancel];
	return reachable;
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
