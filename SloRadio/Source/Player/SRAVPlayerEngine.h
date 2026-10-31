//
//  SRAVPlayerEngine.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SRPlaybackEngine.h"

// Plays HLS streams with AVPlayer. Video tracks are disabled, only the audio is played.
@interface SRAVPlayerEngine : NSObject <SRPlaybackEngine>

@end
