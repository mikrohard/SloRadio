//
//  SRFFmpegEngineTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//
//  Plays scripted streams from a local HTTP server through SRFFmpegEngine to test its stall detection:
//  the stream is only reconnected when both the buffer and the network are empty (or, as a fallback,
//  when no audio was played for a long time).
//

#import <XCTest/XCTest.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import "SRFFmpegEngine.h"

#pragma mark - Test server

// Serves one connection: an HTTP header, then the script (NSData to send, NSNumber seconds to stay silent).
// Afterwards the connection is closed or kept open without sending anything.
@interface SRTestStreamServer : NSObject

@property (nonatomic, readonly) NSURL *url;

- (instancetype)initWithScript:(NSArray *)script closeAtEnd:(BOOL)closeAtEnd;
- (void)stop;

@end

@interface SRTestStreamServer ()
@property (atomic, assign) BOOL stopped;
@property (atomic, assign) int listenSocket;
@property (atomic, assign) int clientSocket;
@end

@implementation SRTestStreamServer

- (instancetype)initWithScript:(NSArray *)script closeAtEnd:(BOOL)closeAtEnd {
	self = [super init];
	if (self) {
		int listenSocket = socket(AF_INET, SOCK_STREAM, 0);
		int yes = 1;
		setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
		struct sockaddr_in address = {0};
		address.sin_len = sizeof(address);
		address.sin_family = AF_INET;
		address.sin_addr.s_addr = inet_addr("127.0.0.1");
		address.sin_port = 0;
		bind(listenSocket, (struct sockaddr *)&address, sizeof(address));
		socklen_t length = sizeof(address);
		getsockname(listenSocket, (struct sockaddr *)&address, &length);
		listen(listenSocket, 4);
		_listenSocket = listenSocket;
		_clientSocket = -1;
		_url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/stream", ntohs(address.sin_port)]];
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
			[self serveScript:script closeAtEnd:closeAtEnd];
		});
	}
	return self;
}

- (void)serveScript:(NSArray *)script closeAtEnd:(BOOL)closeAtEnd {
	int client = accept(self.listenSocket, NULL, NULL);
	if (client < 0) {
		return;
	}
	self.clientSocket = client;
	int yes = 1;
	setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
	char request[4096];
	recv(client, request, sizeof(request), 0);
	const char *header = "HTTP/1.0 200 OK\r\nContent-Type: audio/mpeg\r\n\r\n";
	send(client, header, strlen(header), 0);
	for (id step in script) {
		if (self.stopped) {
			return;
		}
		if ([step isKindOfClass:[NSData class]]) {
			NSData *data = step;
			send(client, data.bytes, data.length, 0);
		} else {
			[NSThread sleepForTimeInterval:[step doubleValue]];
		}
	}
	if (closeAtEnd) {
		close(client);
		self.clientSocket = -1;
	}
}

- (void)stop {
	self.stopped = YES;
	if (self.clientSocket >= 0) {
		close(self.clientSocket);
	}
	close(self.listenSocket);
}

@end

#pragma mark - Tests

@interface SRFFmpegEngineTests : XCTestCase <SRPlaybackEngineDelegate>

@property (nonatomic, strong) SRFFmpegEngine *engine;
@property (nonatomic, strong) SRTestStreamServer *server;
@property (nonatomic, strong) NSDate *start;
@property (nonatomic, strong) NSDate *stalledAt;
@property (nonatomic, assign) NSTimeInterval playbackTimeAtStall;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *states;

@end

@implementation SRFFmpegEngineTests

- (void)tearDown {
	[self.engine stop];
	[self.server stop];
	[super tearDown];
}

// 3 s of MP3
- (NSData *)audio {
	NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:@"tone-44k-stereo" withExtension:@"mp3" subdirectory:@"Fixtures"];
	return [NSData dataWithContentsOfURL:url];
}

- (void)playScript:(NSArray *)script closeAtEnd:(BOOL)closeAtEnd networkStallTimeout:(NSTimeInterval)networkStallTimeout stallTimeout:(NSTimeInterval)stallTimeout {
	self.server = [[SRTestStreamServer alloc] initWithScript:script closeAtEnd:closeAtEnd];
	self.states = [NSMutableArray array];
	self.engine = [[SRFFmpegEngine alloc] initWithURL:self.server.url bufferDuration:0];
	self.engine.networkStallTimeout = networkStallTimeout;
	self.engine.stallTimeout = stallTimeout;
	self.engine.delegate = self;
	[self.engine setVolume:0];
	self.start = [NSDate date];
	[self.engine start];
}

- (void)runUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout {
	NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!condition() && [end timeIntervalSinceNow] > 0) {
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	}
}

#pragma mark - SRPlaybackEngineDelegate

- (void)playbackEngine:(id<SRPlaybackEngine>)engine didChangeState:(SRRadioPlayerState)state {
	[self.states addObject:@(state)];
}

- (void)playbackEngine:(id<SRPlaybackEngine>)engine didChangeMetaData:(NSDictionary<NSString *, NSString *> *)metaData {
}

- (void)playbackEngineDidStall:(id<SRPlaybackEngine>)engine {
	if (!self.stalledAt) {
		self.stalledAt = [NSDate date];
		self.playbackTimeAtStall = engine.playbackTime;
	}
}

#pragma mark - Tests

- (void)testNetworkSilenceCoveredByTheBufferIsNotAStall {
	// 6 s of audio, then the server is silent for 4 s (four times the network timeout): buffered audio keeps
	// playing all the time, so the stream must not be interrupted
	NSData *audio = [self audio];
	[self playScript:@[audio, audio, @4.0, audio, audio] closeAtEnd:NO networkStallTimeout:1.0 stallTimeout:2.0];
	[self runUntil:^BOOL{
		return self.stalledAt != nil || self.engine.playbackTime >= 8.0;
	} timeout:15];
	XCTAssertNil(self.stalledAt, @"reconnected after %.1f s of audio", self.playbackTimeAtStall);
	XCTAssertGreaterThanOrEqual(self.engine.playbackTime, 8.0);
	XCTAssertEqualObjects(self.states.lastObject, @(SRRadioPlayerStatePlaying), @"never ran out of audio: %@", self.states);
}

- (void)testSlowNetworkRebuffersWithoutReconnecting {
	// data arrives at half the stream's speed: the playback runs out and rebuffers again and again,
	// but data keeps coming, so reconnecting wouldn't help
	NSData *audio = [self audio];
	NSMutableArray *script = [NSMutableArray array];
	for (NSUInteger offset = 0; offset < audio.length; offset += 1600) {
		[script addObject:[audio subdataWithRange:NSMakeRange(offset, MIN(1600, audio.length - offset))]];
		[script addObject:@0.2];	// 8 KB/s, the stream needs 16 KB/s
	}
	[self playScript:script closeAtEnd:NO networkStallTimeout:1.0 stallTimeout:3.0];
	[self runUntil:^BOOL{
		return self.stalledAt != nil;
	} timeout:5.5];
	XCTAssertNil(self.stalledAt, @"reconnected after %.1f s of audio", self.playbackTimeAtStall);
	XCTAssertGreaterThan(self.engine.playbackTime, 1.0);
	NSUInteger playing = [self.states indexOfObject:@(SRRadioPlayerStatePlaying)];
	XCTAssertNotEqual(playing, NSNotFound);
	XCTAssertTrue([[self.states subarrayWithRange:NSMakeRange(playing, self.states.count - playing)] containsObject:@(SRRadioPlayerStateBuffering)],
				  @"the playback ran out of audio in between: %@", self.states);
}

- (void)testDeadConnectionReconnectsAsSoonAsTheBufferIsPlayed {
	// the connection stays open but goes silent for good: play all buffered audio, then reconnect right away
	// instead of waiting for the 10 s fallback
	[self playScript:@[[self audio]] closeAtEnd:NO networkStallTimeout:1.0 stallTimeout:10.0];
	[self runUntil:^BOOL{
		return self.stalledAt != nil;
	} timeout:15];
	XCTAssertNotNil(self.stalledAt);
	XCTAssertEqualWithAccuracy(self.playbackTimeAtStall, 3.0, 0.3, @"the buffered audio is played before reconnecting");
	NSTimeInterval elapsed = [self.stalledAt timeIntervalSinceDate:self.start];
	XCTAssertGreaterThan(elapsed, 3.0);
	XCTAssertLessThan(elapsed, 5.0, @"didn't wait for the fallback");
}

- (void)testStreamEndReconnectsOnceTheBufferIsPlayed {
	// the server closes the stream: reconnect as soon as the buffer is played
	[self playScript:@[[self audio]] closeAtEnd:YES networkStallTimeout:5.0 stallTimeout:10.0];
	[self runUntil:^BOOL{
		return self.stalledAt != nil;
	} timeout:15];
	XCTAssertNotNil(self.stalledAt);
	XCTAssertEqualWithAccuracy(self.playbackTimeAtStall, 3.0, 0.3);
	XCTAssertLessThan([self.stalledAt timeIntervalSinceDate:self.start], 5.0);
}

- (void)testUnreachableServerStallsAfterTheTimeout {
	// nothing ever arrives: the fallback reconnects stallTimeout after starting
	self.server = [[SRTestStreamServer alloc] initWithScript:@[@30.0] closeAtEnd:NO];
	self.engine = [[SRFFmpegEngine alloc] initWithURL:self.server.url bufferDuration:0];
	self.engine.stallTimeout = 2.0;
	self.engine.delegate = self;
	self.start = [NSDate date];
	[self.engine start];
	[self runUntil:^BOOL{
		return self.stalledAt != nil;
	} timeout:10];
	XCTAssertNotNil(self.stalledAt);
	XCTAssertEqualWithAccuracy([self.stalledAt timeIntervalSinceDate:self.start], 2.0, 0.5);
	XCTAssertEqual(self.playbackTimeAtStall, 0.0);
}

@end
