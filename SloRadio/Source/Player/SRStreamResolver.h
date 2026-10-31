//
//  SRStreamResolver.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SRStreamFormat) {
	SRStreamFormatAudio,	// a progressive audio stream (Icecast, Shoutcast, plain files) or anything not recognized
	SRStreamFormatHLS,
	SRStreamFormatPLS,
	SRStreamFormatM3U,		// a plain (non HLS) M3U playlist or a bare list of URLs
	SRStreamFormatASX,
	SRStreamFormatXSPF,
	SRStreamFormatHTML,
};

// url is the stream to play, format is SRStreamFormatAudio or SRStreamFormatHLS.
typedef void (^SRStreamResolverCompletion)(NSURL *url, SRStreamFormat format);

// Finds out what a station URL points to: station playlists (PLS, M3U, ASX, XSPF) are unwrapped to the stream
// they contain and the stream is classified as HLS or progressive audio by sniffing its first bytes.
// Resolution never fails: when the URL can't be loaded or isn't recognized it is returned as SRStreamFormatAudio
// and the playback engine reports the error.
@interface SRStreamResolver : NSObject

- (instancetype)initWithURL:(NSURL *)url;
// The completion handler is called once on the main queue, unless the resolver is cancelled first.
- (void)resolveWithCompletion:(SRStreamResolverCompletion)completion;
- (void)cancel;

// Classifies the first bytes of a response. Exposed for tests.
+ (SRStreamFormat)formatForData:(NSData *)data mimeType:(NSString *)mimeType;
// Whether the format can be decided from the response headers alone.
+ (BOOL)isAudioMimeType:(NSString *)mimeType;
// Stream URLs listed in a station playlist, in playlist order. Exposed for tests.
+ (NSArray<NSURL *> *)entriesInPlaylistData:(NSData *)data format:(SRStreamFormat)format baseURL:(NSURL *)baseURL;

@end
