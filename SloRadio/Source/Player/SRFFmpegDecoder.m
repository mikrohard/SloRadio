//
//  SRFFmpegDecoder.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRFFmpegDecoder.h"
#import "SRByteQueue.h"
#import "SRAudioRingBuffer.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>

NSString * const SRFFmpegDecoderErrorDomain = @"SRFFmpegDecoderErrorDomain";
double const SRFFmpegDecoderOutputSampleRate = 48000.0;
uint32_t const SRFFmpegDecoderOutputChannels = 2;

static int const SRFFmpegDecoderIOBufferSize = 16 * 1024;
// enough to recognize every supported format, small enough to start quickly
static int64_t const SRFFmpegDecoderProbeSize = 64 * 1024;
static int64_t const SRFFmpegDecoderMaxAnalyzeDuration = AV_TIME_BASE / 2;
// this many packets in a row that fail to decode end the stream (it gets reconnected)
static int const SRFFmpegDecoderMaxDecodeErrors = 100;

@interface SRPendingMetadata : NSObject
@property (nonatomic, strong) NSDictionary *metadata;
@property (nonatomic, assign) uint64_t offset;
@end

@implementation SRPendingMetadata
@end

@interface SRFFmpegDecoder () {
	// read by the C callbacks below
	@public
	int32_t _stopped;
	uint64_t _decodedFrames;
}

@property (nonatomic, strong) SRByteQueue *input;
@property (nonatomic, strong) SRAudioBuffer *output;
@property (nonatomic, strong) NSMutableArray<SRPendingMetadata *> *pendingMetadata;

@end

static int SRFFmpegDecoderReadPacket(void *opaque, uint8_t *buffer, int size) {
	SRFFmpegDecoder *decoder = (__bridge SRFFmpegDecoder *)opaque;
	NSInteger count = [decoder.input readBytes:buffer maxLength:(NSUInteger)size];
	if (count > 0) {
		return (int)count;
	}
	if (count == 0) {
		return AVERROR_EOF;
	}
	return decoder.input.isAborted ? AVERROR_EXIT : AVERROR(EIO);
}

static int SRFFmpegDecoderInterrupt(void *opaque) {
	SRFFmpegDecoder *decoder = (__bridge SRFFmpegDecoder *)opaque;
	return __atomic_load_n(&decoder->_stopped, __ATOMIC_ACQUIRE) ? 1 : 0;
}

static NSDictionary<NSString *, NSString *> *SRDictionaryFromAVDictionary(const AVDictionary *dictionary) {
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	const AVDictionaryEntry *entry = NULL;
	while ((entry = av_dict_iterate(dictionary, entry))) {
		NSString *key = [NSString stringWithUTF8String:entry->key].lowercaseString;
		NSString *value = [NSString stringWithUTF8String:entry->value];
		if (key && value) {
			result[key] = value;
		}
	}
	return result;
}

static NSError *SRFFmpegError(int code, NSString *description) {
	char message[AV_ERROR_MAX_STRING_SIZE] = {0};
	av_strerror(code, message, sizeof(message));
	NSString *reason = [NSString stringWithFormat:@"%@: %s", description, message];
	return [NSError errorWithDomain:SRFFmpegDecoderErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: reason}];
}

@implementation SRFFmpegDecoder

+ (void)initialize {
	if (self == [SRFFmpegDecoder class]) {
		av_log_set_level(AV_LOG_ERROR);
	}
}

+ (NSString *)libraryVersion {
	return [NSString stringWithUTF8String:av_version_info()];
}

- (instancetype)initWithInput:(SRByteQueue *)input output:(SRAudioBuffer *)output {
	self = [super init];
	if (self) {
		_input = input;
		_output = output;
		_pendingMetadata = [NSMutableArray array];
	}
	return self;
}

- (void)start {
	// the thread keeps the decoder alive until it is done
	NSThread *thread = [[NSThread alloc] initWithBlock:^{
		[self run];
	}];
	thread.name = @"SRFFmpegDecoder";
	thread.qualityOfService = NSQualityOfServiceUserInitiated;
	[thread start];
}

- (void)stop {
	__atomic_store_n(&_stopped, 1, __ATOMIC_RELEASE);
	self.delegate = nil;
	[self.input abort];
}

- (BOOL)isStopped {
	return __atomic_load_n(&_stopped, __ATOMIC_ACQUIRE) != 0;
}

- (uint64_t)decodedFrames {
	return __atomic_load_n(&_decodedFrames, __ATOMIC_ACQUIRE);
}

- (void)addMetadata:(NSDictionary<NSString *, NSString *> *)metadata atStreamOffset:(uint64_t)offset {
	SRPendingMetadata *pending = [[SRPendingMetadata alloc] init];
	pending.metadata = metadata;
	pending.offset = offset;
	@synchronized (self.pendingMetadata) {
		[self.pendingMetadata addObject:pending];
	}
}

#pragma mark - Decoder thread

typedef struct {
	AVIOContext *io;
	AVFormatContext *format;
	AVCodecContext *codec;
	AVStream *stream;
	int streamIndex;
	SwrContext *resampler;
	int resamplerRate;
	int resamplerFormat;
	AVChannelLayout resamplerLayout;
	AVPacket *packet;
	AVFrame *frame;
	float *converted;
	int convertedCapacity;
} SRDecoderState;

static void SRDecoderStateFree(SRDecoderState *state) {
	// the custom IO context isn't freed by avformat_close_input
	avformat_close_input(&state->format);
	if (state->io) {
		av_freep(&state->io->buffer);
		avio_context_free(&state->io);
	}
	avcodec_free_context(&state->codec);
	swr_free(&state->resampler);
	av_channel_layout_uninit(&state->resamplerLayout);
	av_packet_free(&state->packet);
	av_frame_free(&state->frame);
	av_freep(&state->converted);
}

- (void)run {
	SRDecoderState state = {0};
	state.resamplerFormat = -1;
	@autoreleasepool {
		if ([self openStream:&state]) {
			[self decodeStream:&state];
			if (![self isStopped]) {
				[self.delegate decoderDidReachEnd:self];
			}
		}
	}
	SRDecoderStateFree(&state);
}

- (BOOL)openStream:(SRDecoderState *)state {
	uint8_t *ioBuffer = av_malloc(SRFFmpegDecoderIOBufferSize);
	state->io = avio_alloc_context(ioBuffer, SRFFmpegDecoderIOBufferSize, 0, (__bridge void *)self, SRFFmpegDecoderReadPacket, NULL, NULL);
	state->io->seekable = 0;
	state->format = avformat_alloc_context();
	state->format->pb = state->io;
	state->format->flags |= AVFMT_FLAG_CUSTOM_IO;
	state->format->probesize = SRFFmpegDecoderProbeSize;
	state->format->max_analyze_duration = SRFFmpegDecoderMaxAnalyzeDuration;
	state->format->interrupt_callback.callback = SRFFmpegDecoderInterrupt;
	state->format->interrupt_callback.opaque = (__bridge void *)self;

	// frees the format context on failure
	int result = avformat_open_input(&state->format, NULL, NULL, NULL);
	if (result < 0) {
		[self failWithError:SRFFmpegError(result, @"Unknown stream format")];
		return NO;
	}
	result = avformat_find_stream_info(state->format, NULL);
	if (result < 0) {
		[self failWithError:SRFFmpegError(result, @"Couldn't read the stream")];
		return NO;
	}
	const AVCodec *decoder = NULL;
	state->streamIndex = av_find_best_stream(state->format, AVMEDIA_TYPE_AUDIO, -1, -1, &decoder, 0);
	if (state->streamIndex < 0 || !decoder) {
		[self failWithError:SRFFmpegError(state->streamIndex < 0 ? state->streamIndex : AVERROR_DECODER_NOT_FOUND, @"No playable audio")];
		return NO;
	}
	for (unsigned int i = 0; i < state->format->nb_streams; i++) {
		if ((int)i != state->streamIndex) {
			// e.g. the video of an MPEG-TS stream
			state->format->streams[i]->discard = AVDISCARD_ALL;
		}
	}
	state->stream = state->format->streams[state->streamIndex];
	state->codec = avcodec_alloc_context3(decoder);
	avcodec_parameters_to_context(state->codec, state->stream->codecpar);
	result = avcodec_open2(state->codec, decoder, NULL);
	if (result < 0) {
		[self failWithError:SRFFmpegError(result, @"Couldn't open the decoder")];
		return NO;
	}
	state->packet = av_packet_alloc();
	state->frame = av_frame_alloc();

	const char *profile = avcodec_profile_name(state->codec->codec_id, state->codec->profile);
	NSString *description = [NSString stringWithFormat:@"%s, %s%s%s, %d Hz, %d ch",
							 state->format->iformat->name, decoder->name,
							 profile ? " " : "", profile ?: "",
							 state->codec->sample_rate, state->codec->ch_layout.nb_channels];
	if ([self isStopped]) {
		return NO;
	}
	[self.delegate decoder:self didOpenStreamWithDescription:description];
	// tags at the start of the stream (ID3, Vorbis comments)
	[self reportUpdatedTagsOfStream:state force:YES];
	return YES;
}

- (void)reportUpdatedTagsOfStream:(SRDecoderState *)state force:(BOOL)force {
	BOOL updated = (state->format->event_flags & AVFMT_EVENT_FLAG_METADATA_UPDATED) ||
				   (state->stream->event_flags & AVSTREAM_EVENT_FLAG_METADATA_UPDATED);
	state->format->event_flags &= ~AVFMT_EVENT_FLAG_METADATA_UPDATED;
	state->stream->event_flags &= ~AVSTREAM_EVENT_FLAG_METADATA_UPDATED;
	if (updated || force) {
		// e.g. the next song of a chained Ogg stream
		NSMutableDictionary *tags = [SRDictionaryFromAVDictionary(state->format->metadata) mutableCopy];
		[tags addEntriesFromDictionary:SRDictionaryFromAVDictionary(state->stream->metadata)];
		if (tags.count > 0) {
			[self.delegate decoder:self didReachMetadata:tags atFrame:self.decodedFrames];
		}
	}
}

- (void)decodeStream:(SRDecoderState *)state {
	int decodeErrors = 0;
	while (![self isStopped]) {
		@autoreleasepool {
			int result = av_read_frame(state->format, state->packet);
			if (result == AVERROR(EAGAIN)) {
				continue;
			}
			if (result < 0) {
				// end of the input, or it failed
				return;
			}
			[self reportUpdatedTagsOfStream:state force:NO];
			if (state->packet->stream_index != state->streamIndex) {
				av_packet_unref(state->packet);
				continue;
			}
			uint64_t packetEnd = state->packet->pos >= 0 ? (uint64_t)(state->packet->pos + state->packet->size) : (uint64_t)avio_tell(state->format->pb);
			[self reportMetadataBeforeStreamOffset:packetEnd];

			result = avcodec_send_packet(state->codec, state->packet);
			av_packet_unref(state->packet);
			if (result < 0 && result != AVERROR(EAGAIN)) {
				// a corrupt packet, e.g. the partial first frame of a live stream
				if (++decodeErrors >= SRFFmpegDecoderMaxDecodeErrors) {
					return;
				}
				continue;
			}
			while (avcodec_receive_frame(state->codec, state->frame) == 0) {
				decodeErrors = 0;
				[self convertFrame:state];
				av_frame_unref(state->frame);
			}
		}
	}
}

- (void)convertFrame:(SRDecoderState *)state {
	AVFrame *frame = state->frame;
	if (!state->resampler || frame->sample_rate != state->resamplerRate || frame->format != state->resamplerFormat ||
		av_channel_layout_compare(&frame->ch_layout, &state->resamplerLayout) != 0) {
		// first frame, or the stream changed (e.g. SBR kicked in or the next chained Ogg stream)
		swr_free(&state->resampler);
		AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
		if (swr_alloc_set_opts2(&state->resampler, &stereo, AV_SAMPLE_FMT_FLT, (int)SRFFmpegDecoderOutputSampleRate,
								&frame->ch_layout, frame->format, frame->sample_rate, 0, NULL) < 0 ||
			swr_init(state->resampler) < 0) {
			swr_free(&state->resampler);
			return;
		}
		state->resamplerRate = frame->sample_rate;
		state->resamplerFormat = frame->format;
		av_channel_layout_uninit(&state->resamplerLayout);
		av_channel_layout_copy(&state->resamplerLayout, &frame->ch_layout);
	}
	int capacity = swr_get_out_samples(state->resampler, frame->nb_samples);
	if (capacity > state->convertedCapacity) {
		av_freep(&state->converted);
		state->converted = av_malloc_array((size_t)capacity * SRFFmpegDecoderOutputChannels, sizeof(float));
		state->convertedCapacity = capacity;
	}
	uint8_t *output = (uint8_t *)state->converted;
	int count = swr_convert(state->resampler, &output, capacity, (const uint8_t **)frame->extended_data, frame->nb_samples);
	if (count > 0) {
		[self writeFrames:state->converted count:(uint32_t)count];
	}
}

- (void)failWithError:(NSError *)error {
	if (![self isStopped]) {
		[self.delegate decoder:self didFailWithError:error];
	}
}

// Writes all frames, waiting for the audio output to make room. Gives up when stopped.
- (void)writeFrames:(const float *)frames count:(uint32_t)count {
	SRAudioRingBuffer *ring = self.output.ring;
	uint32_t written = 0;
	while (written < count && ![self isStopped]) {
		uint32_t n = SRAudioRingBufferWrite(ring, frames + (size_t)written * SRFFmpegDecoderOutputChannels, count - written);
		written += n;
		__atomic_add_fetch(&_decodedFrames, n, __ATOMIC_RELEASE);
		if (written < count) {
			usleep(10000);
		}
	}
}

// Reports pending metadata whose stream offset lies before `offset`: it applies from the next decoded frame on.
- (void)reportMetadataBeforeStreamOffset:(uint64_t)offset {
	NSMutableArray *due = nil;
	@synchronized (self.pendingMetadata) {
		for (SRPendingMetadata *pending in self.pendingMetadata) {
			if (pending.offset < offset) {
				if (!due) {
					due = [NSMutableArray array];
				}
				[due addObject:pending];
			}
		}
		if (due) {
			[self.pendingMetadata removeObjectsInArray:due];
		}
	}
	for (SRPendingMetadata *pending in due) {
		[self.delegate decoder:self didReachMetadata:pending.metadata atFrame:self.decodedFrames];
	}
}

@end
