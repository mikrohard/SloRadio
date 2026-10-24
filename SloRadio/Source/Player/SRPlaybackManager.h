//
//  SRPlaybackManager.h
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const SRPlaybackManagerDidChangeSleepTimer;
extern NSString * const SRPlaybackManagerDidFailPlayback;

@class SRRadioStation;

@interface SRPlaybackManager : NSObject

@property (nonatomic, readonly) BOOL sleepTimerActive;
@property (nonatomic, readonly) NSTimeInterval sleepTimerTimeRemaining;
@property (nonatomic, readonly) NSString *nowPlayingText;

+ (SRPlaybackManager *)sharedManager;

- (void)playRadioStation:(SRRadioStation *)station;
- (void)playRadioStation:(SRRadioStation *)station withSleepTimer:(BOOL)sleepTimer;
- (void)play;
- (void)stop;
- (void)togglePlayPause;
- (void)playNextStation;
- (void)playPreviousStation;
- (void)cancelSleepTimer;

@end
