//
//  SRAudioRingBuffer.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRAudioRingBuffer.h"

struct SRAudioRingBuffer {
	float *samples;
	uint32_t capacityFrames;
	uint32_t channels;
	// monotonically increasing frame counters, only written by their own side
	uint64_t writeIndex;
	uint64_t readIndex;
};

@implementation SRAudioBuffer

- (instancetype)initWithCapacityFrames:(uint32_t)capacityFrames channels:(uint32_t)channels {
	self = [super init];
	if (self) {
		_capacityFrames = capacityFrames;
		_channels = channels;
		_ring = calloc(1, sizeof(SRAudioRingBuffer));
		_ring->samples = calloc((size_t)capacityFrames * channels, sizeof(float));
		_ring->capacityFrames = capacityFrames;
		_ring->channels = channels;
	}
	return self;
}

- (void)dealloc {
	free(_ring->samples);
	free(_ring);
}

@end

uint32_t SRAudioRingBufferAvailableFrames(SRAudioRingBuffer *ring) {
	uint64_t write = __atomic_load_n(&ring->writeIndex, __ATOMIC_ACQUIRE);
	uint64_t read = __atomic_load_n(&ring->readIndex, __ATOMIC_ACQUIRE);
	return (uint32_t)(write - read);
}

uint32_t SRAudioRingBufferFreeFrames(SRAudioRingBuffer *ring) {
	return ring->capacityFrames - SRAudioRingBufferAvailableFrames(ring);
}

uint32_t SRAudioRingBufferWrite(SRAudioRingBuffer *ring, const float *interleaved, uint32_t frames) {
	uint64_t write = __atomic_load_n(&ring->writeIndex, __ATOMIC_RELAXED);
	uint64_t read = __atomic_load_n(&ring->readIndex, __ATOMIC_ACQUIRE);
	uint32_t space = ring->capacityFrames - (uint32_t)(write - read);
	uint32_t count = frames < space ? frames : space;
	uint32_t start = (uint32_t)(write % ring->capacityFrames);
	uint32_t first = ring->capacityFrames - start;
	if (first > count) {
		first = count;
	}
	memcpy(ring->samples + (size_t)start * ring->channels, interleaved, (size_t)first * ring->channels * sizeof(float));
	if (count > first) {
		memcpy(ring->samples, interleaved + (size_t)first * ring->channels, (size_t)(count - first) * ring->channels * sizeof(float));
	}
	__atomic_store_n(&ring->writeIndex, write + count, __ATOMIC_RELEASE);
	return count;
}

uint32_t SRAudioRingBufferRead(SRAudioRingBuffer *ring, float *const *channelBuffers, uint32_t frames) {
	uint64_t read = __atomic_load_n(&ring->readIndex, __ATOMIC_RELAXED);
	uint64_t write = __atomic_load_n(&ring->writeIndex, __ATOMIC_ACQUIRE);
	uint32_t available = (uint32_t)(write - read);
	uint32_t count = frames < available ? frames : available;
	uint32_t channels = ring->channels;
	for (uint32_t i = 0; i < count; i++) {
		const float *frame = ring->samples + (size_t)((read + i) % ring->capacityFrames) * channels;
		for (uint32_t c = 0; c < channels; c++) {
			channelBuffers[c][i] = frame[c];
		}
	}
	__atomic_store_n(&ring->readIndex, read + count, __ATOMIC_RELEASE);
	return count;
}
