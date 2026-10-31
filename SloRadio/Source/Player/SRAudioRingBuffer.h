//
//  SRAudioRingBuffer.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

// A lock free single producer / single consumer ring buffer of interleaved float audio frames.
// The decoder thread writes, the audio render thread reads. The C functions below do not lock,
// allocate or call Objective-C, so they are safe to use on the real time render thread.
typedef struct SRAudioRingBuffer SRAudioRingBuffer;

// Owns the ring buffer memory. Keep a strong reference to it for as long as the ring is used.
@interface SRAudioBuffer : NSObject

- (instancetype)initWithCapacityFrames:(uint32_t)capacityFrames channels:(uint32_t)channels;

@property (nonatomic, readonly) SRAudioRingBuffer *ring;
@property (nonatomic, readonly) uint32_t capacityFrames;
@property (nonatomic, readonly) uint32_t channels;

@end

// Producer: copies up to `frames` interleaved frames, returns how many fit.
uint32_t SRAudioRingBufferWrite(SRAudioRingBuffer *ring, const float *interleaved, uint32_t frames);
// Consumer: reads up to `frames` frames into one buffer per channel (deinterleaving), returns how many were read.
uint32_t SRAudioRingBufferRead(SRAudioRingBuffer *ring, float *const *channelBuffers, uint32_t frames);
uint32_t SRAudioRingBufferAvailableFrames(SRAudioRingBuffer *ring);
uint32_t SRAudioRingBufferFreeFrames(SRAudioRingBuffer *ring);
