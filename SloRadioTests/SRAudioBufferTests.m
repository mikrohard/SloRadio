//
//  SRAudioBufferTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SRAudioRingBuffer.h"
#import "SRByteQueue.h"

@interface SRAudioBufferTests : XCTestCase

@end

@implementation SRAudioBufferTests

#pragma mark - Ring buffer

- (void)testWrapAroundAndDeinterleave {
	SRAudioBuffer *buffer = [[SRAudioBuffer alloc] initWithCapacityFrames:10 channels:2];
	SRAudioRingBuffer *ring = buffer.ring;
	float left[10], right[10];
	float *channels[2] = {left, right};
	float next = 0;
	float expected = 0;
	// many rounds of uneven writes and reads so the indices wrap around repeatedly
	for (int round = 0; round < 50; round++) {
		uint32_t writeFrames = (uint32_t)(round % 7) + 1;
		float frames[16];
		for (uint32_t i = 0; i < writeFrames; i++) {
			frames[i * 2] = next;
			frames[i * 2 + 1] = -next;
			next += 1;
		}
		uint32_t space = SRAudioRingBufferFreeFrames(ring);
		uint32_t written = SRAudioRingBufferWrite(ring, frames, writeFrames);
		XCTAssertEqual(written, MIN(writeFrames, space));
		next -= writeFrames - written;	// what didn't fit is written again in the next round
		uint32_t read = SRAudioRingBufferRead(ring, channels, (uint32_t)(round % 5) + 1);
		for (uint32_t i = 0; i < read; i++) {
			XCTAssertEqual(left[i], expected);
			XCTAssertEqual(right[i], -expected);
			expected += 1;
		}
		XCTAssertEqual(SRAudioRingBufferAvailableFrames(ring) + SRAudioRingBufferFreeFrames(ring), 10u);
	}
}

- (void)testFullAndEmpty {
	SRAudioBuffer *buffer = [[SRAudioBuffer alloc] initWithCapacityFrames:4 channels:2];
	float frames[12] = {0};
	XCTAssertEqual(SRAudioRingBufferWrite(buffer.ring, frames, 6), 4u);
	XCTAssertEqual(SRAudioRingBufferWrite(buffer.ring, frames, 1), 0u);
	float left[8], right[8];
	float *channels[2] = {left, right};
	XCTAssertEqual(SRAudioRingBufferRead(buffer.ring, channels, 8), 4u);
	XCTAssertEqual(SRAudioRingBufferRead(buffer.ring, channels, 8), 0u);
}

#pragma mark - Byte queue

- (void)testBlockingReadIsWokenByData {
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:1024];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		[queue appendData:[@"hello" dataUsingEncoding:NSASCIIStringEncoding]];
	});
	uint8_t bytes[16];
	XCTAssertEqual([queue readBytes:bytes maxLength:sizeof(bytes)], 5);
	XCTAssertEqual(memcmp(bytes, "hello", 5), 0);
}

- (void)testEndOfStreamAndErrors {
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:1024];
	[queue appendData:[@"abc" dataUsingEncoding:NSASCIIStringEncoding]];
	[queue finishWithError:nil];
	uint8_t bytes[2];
	XCTAssertEqual([queue readBytes:bytes maxLength:2], 2);
	XCTAssertEqual([queue readBytes:bytes maxLength:2], 1, @"queued data is read before the end");
	XCTAssertEqual([queue readBytes:bytes maxLength:2], 0);

	SRByteQueue *failed = [[SRByteQueue alloc] initWithCapacity:1024];
	[failed finishWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
	XCTAssertEqual([failed readBytes:bytes maxLength:2], -1);
}

- (void)testAbortWakesBlockedReader {
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:1024];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		[queue abort];
	});
	uint8_t bytes[2];
	XCTAssertEqual([queue readBytes:bytes maxLength:2], -1);
	XCTAssertTrue(queue.isAborted);
}

- (void)testSpaceAvailableAfterBeingFull {
	SRByteQueue *queue = [[SRByteQueue alloc] initWithCapacity:100];
	__block NSUInteger calls = 0;
	queue.spaceAvailableHandler = ^{
		calls++;
	};
	[queue appendData:[NSMutableData dataWithLength:120]];
	XCTAssertTrue(queue.isFull);
	uint8_t bytes[40];
	[queue readBytes:bytes maxLength:40];	// 80 left, still more than three quarters
	XCTAssertEqual(calls, 0u);
	[queue readBytes:bytes maxLength:10];	// 70 left
	XCTAssertEqual(calls, 1u);
	XCTAssertFalse(queue.isFull);
	[queue readBytes:bytes maxLength:40];
	XCTAssertEqual(calls, 1u, @"only once per time it was full");
	XCTAssertEqual(queue.totalBytesAppended, 120u);
}

@end
