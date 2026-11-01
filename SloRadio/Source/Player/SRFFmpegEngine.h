//
//  SRFFmpegEngine.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SRPlaybackEngine.h"

// Plays progressive streams (Icecast, Shoutcast, plain files): URLSession input with ICY metadata,
// FFmpeg demuxing and decoding, AVAudioEngine output. Metadata changes are reported when the audio they belong to is heard.
@interface SRFFmpegEngine : NSObject <SRPlaybackEngine>

// The stream is reconnected (-playbackEngineDidStall:) only when that's needed:
// - when nothing is left to play and no data arrived for networkStallTimeout (3 s by default),
//   while buffered audio plays or data keeps arriving the stream is never interrupted
// - as a fallback when no audio was played for stallTimeout (10 s by default), also while opening the stream
// Set both before -start.
@property (nonatomic, assign) NSTimeInterval networkStallTimeout;
@property (nonatomic, assign) NSTimeInterval stallTimeout;

@end
