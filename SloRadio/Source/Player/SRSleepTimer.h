//
//  SRSleepTimer.h
//  SloRadio
//
//  Created by Jernej Fijačko on 3. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SRSleepTimerDelegate;

@interface SRSleepTimer : NSObject

@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSTimeInterval timeRemaining;

- (instancetype)initWithInterval:(NSTimeInterval)interval delegate:(id<SRSleepTimerDelegate>)delegate;
- (void)startTimerWithInterval:(NSTimeInterval)interval;
- (void)startTimer;
- (void)invalidate;

@end

@protocol SRSleepTimerDelegate <NSObject>

@required

- (void)sleepTimer:(SRSleepTimer *)timer changeVolumeLevel:(float)volume;
- (void)sleepTimer:(SRSleepTimer *)timer timeRemaining:(NSTimeInterval)timeRemaining;
- (void)sleepTimerDidEnd:(SRSleepTimer *)timer;

@end