//
//  SRFFmpegDecoder.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SRByteQueue;
@class SRAudioBuffer;
@protocol SRFFmpegDecoderDelegate;

extern NSString * const SRFFmpegDecoderErrorDomain;
// all output is converted to this format: interleaved stereo float
extern double const SRFFmpegDecoderOutputSampleRate;
extern uint32_t const SRFFmpegDecoderOutputChannels;

// Demuxes and decodes a stream read from a byte queue on its own thread and writes the audio into a ring buffer.
// Metadata found in the stream (Ogg comments, ID3) and metadata added with -addMetadata:atStreamOffset: is reported
// together with the output frame from which on it applies.
@interface SRFFmpegDecoder : NSObject

- (instancetype)initWithInput:(SRByteQueue *)input output:(SRAudioBuffer *)output;

// The version of the FFmpeg libraries the app is linked against, e.g. "9.0.2".
// MobileVLCKit contains its own FFmpeg: this must not be its version (FFmpeg has to come first in the link order).
+ (NSString *)libraryVersion;

// Delegate callbacks are made on the decoder thread.
@property (atomic, weak) id<SRFFmpegDecoderDelegate> delegate;

- (void)start;
// Stops the decoder thread soon. Also aborts the input queue. No delegate callbacks are sent after this.
- (void)stop;

// Metadata that applies from the given position in the input byte stream on (e.g. an ICY metadata block).
// Can be called from any thread.
- (void)addMetadata:(NSDictionary<NSString *, NSString *> *)metadata atStreamOffset:(uint64_t)offset;

// Frames written to the output so far.
@property (atomic, readonly) uint64_t decodedFrames;

@end

@protocol SRFFmpegDecoderDelegate <NSObject>

// The stream was recognized and decoding starts. description is e.g. "mp3, 44100 Hz, stereo".
- (void)decoder:(SRFFmpegDecoder *)decoder didOpenStreamWithDescription:(NSString *)description;
// The stream couldn't be opened (unknown format, no audio, unsupported codec).
- (void)decoder:(SRFFmpegDecoder *)decoder didFailWithError:(NSError *)error;
// The input ended or failed after the stream was opened, or the stream can't be decoded any more.
- (void)decoderDidReachEnd:(SRFFmpegDecoder *)decoder;
// Metadata that applies from output frame `frame` on.
- (void)decoder:(SRFFmpegDecoder *)decoder didReachMetadata:(NSDictionary<NSString *, NSString *> *)metadata atFrame:(uint64_t)frame;

@end
