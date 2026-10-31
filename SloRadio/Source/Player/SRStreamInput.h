//
//  SRStreamInput.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SRByteQueue;
@class SRICYMetadataBlock;
@protocol SRStreamInputDelegate;

extern NSString * const SRStreamInputErrorDomain;

// Downloads a progressive stream with URLSession into a byte queue, with ICY metadata separated from the audio.
// Pauses the download while the queue is full.
@interface SRStreamInput : NSObject

- (instancetype)initWithURL:(NSURL *)url queue:(SRByteQueue *)queue;

// Delegate callbacks arrive on the main queue.
@property (nonatomic, weak) id<SRStreamInputDelegate> delegate;

- (void)start;
// Cancels the download and finishes the queue. No delegate callbacks are sent after this.
- (void)cancel;

@end

@protocol SRStreamInputDelegate <NSObject>

// The response headers (lower case keys, including in-body ICY headers) arrived, audio data follows.
- (void)streamInput:(SRStreamInput *)input didReceiveHeaders:(NSDictionary<NSString *, NSString *> *)headers;
- (void)streamInput:(SRStreamInput *)input didReceiveMetadataBlock:(SRICYMetadataBlock *)block;
// The download failed (HTTP errors included) or ended. A nil error means the server closed the stream.
- (void)streamInput:(SRStreamInput *)input didFinishWithError:(NSError *)error;

@end
