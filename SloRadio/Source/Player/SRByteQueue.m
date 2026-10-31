//
//  SRByteQueue.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRByteQueue.h"

@interface SRByteQueue ()

@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) NSUInteger readOffset;
@property (nonatomic, assign) NSUInteger capacity;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL aborted;
@property (nonatomic, assign) BOOL wasFull;
@property (nonatomic, assign) uint64_t appended;
@property (nonatomic, strong) NSError *finishError;

@end

@implementation SRByteQueue

- (instancetype)initWithCapacity:(NSUInteger)capacity {
	self = [super init];
	if (self) {
		_condition = [[NSCondition alloc] init];
		_buffer = [NSMutableData data];
		_capacity = capacity;
	}
	return self;
}

- (void)appendData:(NSData *)data {
	if (data.length == 0) {
		return;
	}
	[self.condition lock];
	if (!self.finished && !self.aborted) {
		[self.buffer appendData:data];
		self.appended += data.length;
		if (self.buffer.length - self.readOffset >= self.capacity) {
			self.wasFull = YES;
		}
		[self.condition broadcast];
	}
	[self.condition unlock];
}

- (void)finishWithError:(NSError *)error {
	[self.condition lock];
	self.finished = YES;
	self.finishError = error;
	[self.condition broadcast];
	[self.condition unlock];
}

- (void)abort {
	[self.condition lock];
	self.aborted = YES;
	[self.condition broadcast];
	[self.condition unlock];
}

- (NSInteger)readBytes:(uint8_t *)bytes maxLength:(NSUInteger)maxLength {
	void (^spaceAvailable)(void) = nil;
	NSInteger result;
	[self.condition lock];
	while (!self.aborted && !self.finished && self.buffer.length == self.readOffset) {
		[self.condition wait];
	}
	NSUInteger available = self.buffer.length - self.readOffset;
	if (self.aborted) {
		result = -1;
	} else if (available == 0) {
		// finished
		result = self.finishError ? -1 : 0;
	} else {
		NSUInteger count = MIN(available, maxLength);
		memcpy(bytes, (const uint8_t *)self.buffer.bytes + self.readOffset, count);
		self.readOffset += count;
		if (self.readOffset >= 64 * 1024 && self.readOffset * 2 >= self.buffer.length) {
			// drop the consumed bytes from time to time
			[self.buffer replaceBytesInRange:NSMakeRange(0, self.readOffset) withBytes:NULL length:0];
			self.readOffset = 0;
		}
		if (self.wasFull && self.buffer.length - self.readOffset <= self.capacity * 3 / 4) {
			self.wasFull = NO;
			spaceAvailable = self.spaceAvailableHandler;
		}
		result = (NSInteger)count;
	}
	[self.condition unlock];
	if (spaceAvailable) {
		spaceAvailable();
	}
	return result;
}

- (BOOL)isFull {
	[self.condition lock];
	BOOL full = self.buffer.length - self.readOffset >= self.capacity;
	[self.condition unlock];
	return full;
}

- (BOOL)isAborted {
	[self.condition lock];
	BOOL aborted = self.aborted;
	[self.condition unlock];
	return aborted;
}

- (NSUInteger)length {
	[self.condition lock];
	NSUInteger length = self.buffer.length - self.readOffset;
	[self.condition unlock];
	return length;
}

- (uint64_t)totalBytesAppended {
	[self.condition lock];
	uint64_t appended = self.appended;
	[self.condition unlock];
	return appended;
}

- (NSError *)error {
	[self.condition lock];
	NSError *error = self.finishError;
	[self.condition unlock];
	return error;
}

@end
