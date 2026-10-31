//
//  SRVLCEngine.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SRPlaybackEngine.h"

// Plays progressive streams with MobileVLCKit until the FFmpeg engine replaces it.
@interface SRVLCEngine : NSObject <SRPlaybackEngine>

@end
