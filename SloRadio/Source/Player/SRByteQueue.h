//
//  SRByteQueue.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

// A thread safe FIFO of stream bytes between the network (producer) and the decoder thread (consumer).
@interface SRByteQueue : NSObject

// capacity: the producer should pause when this many bytes are queued (see isFull and spaceAvailableHandler).
- (instancetype)initWithCapacity:(NSUInteger)capacity;

// Producer side.
- (void)appendData:(NSData *)data;
// No more data will be appended. A nil error means the stream ended normally.
- (void)finishWithError:(NSError *)error;
@property (nonatomic, readonly) BOOL isFull;
// Called on the consumer thread when a full queue drained to three quarters of its capacity. Keep it short:
// a paused URLSession task keeps its timeout timer running.
@property (atomic, copy) void (^spaceAvailableHandler)(void);

// Consumer side. Blocks until data is available. Returns the number of bytes read, 0 at the end of the stream
// and -1 when the stream failed or the queue was aborted.
- (NSInteger)readBytes:(uint8_t *)buffer maxLength:(NSUInteger)length;

// Wakes up and fails all readers, also while blocked. Used to stop the decoder thread.
- (void)abort;
@property (nonatomic, readonly) BOOL isAborted;

@property (nonatomic, readonly) NSUInteger length;
@property (nonatomic, readonly) uint64_t totalBytesAppended;
@property (nonatomic, readonly) NSError *error;

@end
