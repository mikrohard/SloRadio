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

// The stream is reconnected (-playbackEngineDidStall:) when no audio was played for this long, 10 s by default.
// Network silence alone doesn't count: buffered audio keeps playing. Set before -start.
@property (nonatomic, assign) NSTimeInterval stallTimeout;

@end
