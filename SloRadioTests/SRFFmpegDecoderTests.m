//
//  SRFFmpegDecoderTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//
//  Decodes the synthetic fixtures in Fixtures/ (Scripts/make-test-fixtures.sh) through the byte queue,
//  the FFmpeg decoder and the ring buffer, the way SRFFmpegEngine plays a stream.
//

#import <XCTest/XCTest.h>
#import "SRFFmpegDecoder.h"
#import "SRByteQueue.h"
#import "SRAudioRingBuffer.h"

static double const SRSampleRate = 48000.0;

@interface SRDecodeResult : NSObject
@property (nonatomic, copy) NSString *streamDescription;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) uint64_t frames;
@property (nonatomic, assign) double leftRMS;
@property (nonatomic, assign) double rightRMS;
@property (nonatomic, strong) NSMutableArray<NSArray *> *metadata;	// [frame, dictionary]
@end

@implementation SRDecodeResult
@end

@interface SRFFmpegDecoderTests : XCTestCase <SRFFmpegDecoderDelegate>

@property (nonatomic, strong) SRDecodeResult *result;
@property (nonatomic, strong) XCTestExpectation *finished;
@property (atomic, assign) BOOL ended;

@end

@implementation SRFFmpegDecoderTests

- (NSData *)fixture:(NSString *)name {
	NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:name withExtension:nil subdirectory:@"Fixtures"];
	XCTAssertNotNil(url, @"missing fixture %@", name);
	return [NSData dataWithContentsOfURL:url];
}

// Decodes the data completely. Metadata blocks are added at their stream offsets before decoding starts.
- (SRDecodeResult *)decode:(NSData *)data metadata:(NSDictionary<NSNumber *, NSDictionary *> *)metadata {
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:16 * 1024 * 1024];
	[queue appendData:data];
	[queue finishWithError:nil];
	// big enough for every fixture, so the decoder never waits for room
	SRAudioBuffer *buffer = [[SRAudioBuffer alloc] initWithCapacityFrames:(uint32_t)(SRSampleRate * 20) channels:2];
	SRFFmpegDecoder *decoder = [[SRFFmpegDecoder alloc] initWithInput:queue output:buffer];
	decoder.delegate = self;
	for (NSNumber *offset in metadata) {
		[decoder addMetadata:metadata[offset] atStreamOffset:offset.unsignedLongLongValue];
	}
	self.result = [[SRDecodeResult alloc] init];
	self.result.metadata = [NSMutableArray array];
	self.finished = [self expectationWithDescription:@"finished"];
	[decoder start];
	[self waitForExpectations:@[self.finished] timeout:10.0];

	SRDecodeResult *result = self.result;
	uint32_t frames = SRAudioRingBufferAvailableFrames(buffer.ring);
	float *left = calloc(frames, sizeof(float));
	float *right = calloc(frames, sizeof(float));
	float *channels[2] = {left, right};
	XCTAssertEqual(SRAudioRingBufferRead(buffer.ring, channels, frames), frames);
	double leftSum = 0, rightSum = 0;
	for (uint32_t i = 0; i < frames; i++) {
		leftSum += left[i] * left[i];
		rightSum += right[i] * right[i];
	}
	free(left);
	free(right);
	result.frames = frames;
	result.leftRMS = frames ? sqrt(leftSum / frames) : 0;
	result.rightRMS = frames ? sqrt(rightSum / frames) : 0;
	XCTAssertEqual(decoder.decodedFrames, (uint64_t)frames);
	return result;
}

- (void)assertDecodes:(NSString *)fixture seconds:(double)seconds {
	SRDecodeResult *result = [self decode:[self fixture:fixture] metadata:nil];
	XCTAssertNil(result.error, @"%@: %@", fixture, result.error);
	XCTAssertNotNil(result.streamDescription, @"%@", fixture);
	XCTAssertEqualWithAccuracy(result.frames / SRSampleRate, seconds, 0.2, @"%@ (%@)", fixture, result.streamDescription);
	// the fixtures are sine tones with an RMS of about 0.09 (lavfi's default amplitude 1/8)
	XCTAssertGreaterThan(result.leftRMS, 0.05, @"%@", fixture);
	XCTAssertGreaterThan(result.rightRMS, 0.05, @"%@ (mono must be played on both channels)", fixture);
	XCTAssertLessThan(result.leftRMS, 0.2, @"%@", fixture);
}

#pragma mark - SRFFmpegDecoderDelegate (decoder thread)

- (void)decoder:(SRFFmpegDecoder *)decoder didOpenStreamWithDescription:(NSString *)description {
	self.result.streamDescription = description;
}

- (void)decoder:(SRFFmpegDecoder *)decoder didFailWithError:(NSError *)error {
	self.result.error = error;
	[self.finished fulfill];
}

- (void)decoderDidReachEnd:(SRFFmpegDecoder *)decoder {
	self.ended = YES;
	[self.finished fulfill];
}

- (void)decoder:(SRFFmpegDecoder *)decoder didReachMetadata:(NSDictionary<NSString *, NSString *> *)metadata atFrame:(uint64_t)frame {
	@synchronized (self.result.metadata) {
		[self.result.metadata addObject:@[@(frame), metadata]];
	}
}

#pragma mark - Library

- (void)testLinkedAgainstOwnFFmpeg {
	// MobileVLCKit exports the symbols of its own, much older FFmpeg. When it comes first in the link order,
	// the app silently calls into it and crashes.
	NSString *version = [SRFFmpegDecoder libraryVersion];
	XCTAssertGreaterThanOrEqual(version.integerValue, 9, @"linked against FFmpeg %@", version);
}

#pragma mark - Formats

- (void)testMP3 {
	[self assertDecodes:@"tone-44k-stereo.mp3" seconds:3.0];
}

- (void)testMonoMP3IsResampledAndUpmixed {
	[self assertDecodes:@"tone-22k-mono.mp3" seconds:3.0];
}

- (void)testAACLC {
	[self assertDecodes:@"tone-aac-lc.aac" seconds:3.0];
}

- (void)testHEAAC {
	SRDecodeResult *result = [self decode:[self fixture:@"tone-he-aac.aac"] metadata:nil];
	XCTAssertTrue([result.streamDescription containsString:@"HE-AAC"], @"%@", result.streamDescription);
	[self assertDecodes:@"tone-he-aac.aac" seconds:3.1];
}

- (void)testOpus {
	[self assertDecodes:@"tone.opus" seconds:3.0];
}

- (void)testFLAC {
	[self assertDecodes:@"tone.flac" seconds:3.0];
}

- (void)testMPEGTS {
	[self assertDecodes:@"tone-aac.ts" seconds:2.9];
}

- (void)testStreamCutAtAnyPointStillDecodes {
	// a live stream starts in the middle of a frame
	NSData *data = [self fixture:@"tone-44k-stereo.mp3"];
	SRDecodeResult *result = [self decode:[data subdataWithRange:NSMakeRange(1000, data.length - 1000)] metadata:nil];
	XCTAssertNil(result.error);
	XCTAssertEqualWithAccuracy(result.frames / SRSampleRate, 2.94, 0.2);
}

- (void)testGarbageFails {
	NSMutableData *garbage = [NSMutableData dataWithLength:64 * 1024];
	for (NSUInteger i = 0; i < garbage.length; i++) {
		((uint8_t *)garbage.mutableBytes)[i] = (uint8_t)(i * 31 % 251);
	}
	SRDecodeResult *result = [self decode:garbage metadata:nil];
	XCTAssertNotNil(result.error);
	XCTAssertEqual(result.frames, 0u);
	XCTAssertNotNil([self decode:[NSData data] metadata:nil].error);
}

#pragma mark - Metadata

- (void)testChainedOggSongsAreMetadataUpdates {
	SRDecodeResult *result = [self decode:[self fixture:@"chained.ogg"] metadata:nil];
	XCTAssertEqualWithAccuracy(result.frames / SRSampleRate, 3.0, 0.2, @"both songs are played");
	NSArray *first = nil;
	NSArray *second = nil;
	for (NSArray *entry in result.metadata) {
		NSString *title = entry[1][@"title"];
		if ([title isEqualToString:@"First Song"] && !first) {
			first = entry;
		} else if ([title isEqualToString:@"Second Song"] && !second) {
			second = entry;
		}
	}
	XCTAssertEqualObjects(first[1][@"artist"], @"First Artist");
	XCTAssertEqual([first[0] unsignedLongLongValue], 0u);
	XCTAssertEqualObjects(second[1][@"artist"], @"Second Artist");
	// the second song starts after 1.5 s, give or take a Vorbis block
	XCTAssertEqualWithAccuracy([second[0] doubleValue] / SRSampleRate, 1.5, 0.06, @"%@", result.metadata);
}

- (void)testICYMetadataIsPlacedAtItsStreamPosition {
	NSData *data = [self fixture:@"tone-44k-stereo.mp3"];
	NSDictionary *metadata = @{@0: @{@"streamtitle": @"First"},
							   @(data.length / 2): @{@"streamtitle": @"Middle"},
							   @(data.length * 9 / 10): @{@"streamtitle": @"End"}};
	SRDecodeResult *result = [self decode:data metadata:metadata];
	XCTAssertEqual(result.metadata.count, 3u, @"%@", result.metadata);
	NSMutableDictionary *frames = [NSMutableDictionary dictionary];
	for (NSArray *entry in result.metadata) {
		frames[entry[1][@"streamtitle"]] = entry[0];
	}
	// constant bit rate: byte position and time are proportional, accurate to an MP3 frame (26 ms)
	XCTAssertEqual([frames[@"First"] unsignedLongLongValue], 0u);
	XCTAssertEqualWithAccuracy([frames[@"Middle"] doubleValue] / SRSampleRate, 1.5, 0.06);
	XCTAssertEqualWithAccuracy([frames[@"End"] doubleValue] / SRSampleRate, 2.7, 0.06);
}

#pragma mark - Stopping

- (void)testStopWhileWaitingForData {
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:1024];
	SRAudioBuffer *buffer = [[SRAudioBuffer alloc] initWithCapacityFrames:4800 channels:2];
	SRFFmpegDecoder *decoder = [[SRFFmpegDecoder alloc] initWithInput:queue output:buffer];
	self.result = [[SRDecodeResult alloc] init];
	decoder.delegate = self;
	[decoder start];
	[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	[decoder stop];
	[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
	XCTAssertNil(self.result.error, @"no callbacks after stop");
	XCTAssertTrue(queue.isAborted);
}

- (void)testDecoderWaitsForRoomInTheOutput {
	// a ring buffer of 0.5 s: the decoder must wait for the "audio output" instead of dropping audio
	NSData *data = [self fixture:@"tone-44k-stereo.mp3"];
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:1024 * 1024];
	[queue appendData:data];
	[queue finishWithError:nil];
	SRAudioBuffer *buffer = [[SRAudioBuffer alloc] initWithCapacityFrames:24000 channels:2];
	SRFFmpegDecoder *decoder = [[SRFFmpegDecoder alloc] initWithInput:queue output:buffer];
	self.result = [[SRDecodeResult alloc] init];
	decoder.delegate = self;
	[decoder start];
	float left[4800], right[4800];
	float *channels[2] = {left, right};
	uint64_t consumed = 0;
	NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:10];
	// play the "output" until the decoder is done
	while (!self.ended && [timeout timeIntervalSinceNow] > 0) {
		consumed += SRAudioRingBufferRead(buffer.ring, channels, 4800);
		usleep(5000);
	}
	XCTAssertTrue(self.ended);
	consumed += SRAudioRingBufferAvailableFrames(buffer.ring);
	XCTAssertEqualWithAccuracy(consumed / SRSampleRate, 3.0, 0.2);
}

@end
