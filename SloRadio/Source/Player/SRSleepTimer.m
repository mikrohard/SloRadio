//
//  SRSleepTimer.m
//  SloRadio
//
//  Created by Jernej Fijačko on 3. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRSleepTimer.h"

@interface SRSleepTimer () {
	NSTimeInterval _interval;
}

@property (nonatomic, weak) id<SRSleepTimerDelegate> delegate;
@property (nonatomic, strong) NSTimer *secondsTimer;
@property (nonatomic, strong) NSTimer *endTimer;

@end

@implementation SRSleepTimer

@synthesize delegate = _delegate;
@synthesize timeRemaining = _timeRemaining;

#pragma mark - Lifecycle

- (instancetype)initWithInterval:(NSTimeInterval)interval delegate:(id<SRSleepTimerDelegate>)delegate {
	self = [super init];
	if (self) {
		self.delegate = delegate;
		_interval = interval;
		_timeRemaining = interval;
	}
	return self;
}

#pragma mark - Timers

- (void)startTimerWithInterval:(NSTimeInterval)interval {
	_interval = interval;
	_timeRemaining = interval;
	[self startTimer];
}

- (void)startTimer {
	NSTimeInterval interval = _interval;
	self.endTimer = [NSTimer timerWithTimeInterval:interval target:self selector:@selector(endTimerDidFire:) userInfo:nil repeats:NO];
	self.secondsTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(secondsTimerDidFire:) userInfo:nil repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:self.endTimer forMode:NSRunLoopCommonModes];
	[[NSRunLoop currentRunLoop] addTimer:self.secondsTimer forMode:NSRunLoopCommonModes];
	
	// manually fire seconds timer at start
	[self.secondsTimer fire];
}

- (void)secondsTimerDidFire:(NSTimer *)timer {
	NSTimeInterval currentInterval = MAX(0, round([self.endTimer.fireDate timeIntervalSince1970] - [[NSDate date] timeIntervalSince1970]));
	_timeRemaining = currentInterval;
	[self.delegate sleepTimer:self timeRemaining:currentInterval];
	[self calculateCurrentVolume];
}

- (void)endTimerDidFire:(NSTimer *)timer {
	[self invalidate];
	_timeRemaining = 0;
	[self.delegate sleepTimerDidEnd:self];
}

- (void)invalidate {
	[self.secondsTimer invalidate];
	[self.endTimer invalidate];
	self.secondsTimer = nil;
	self.endTimer = nil;
}

- (BOOL)isRunning {
	return self.endTimer.isValid;
}

#pragma mark - Volume

- (void)calculateCurrentVolume {
	// calculate volume
	NSTimeInterval fadeOutInterval = 5*60; // last 5 mintues
	NSTimeInterval timeToEnd = MAX(0, [self.endTimer.fireDate timeIntervalSince1970] - [[NSDate date] timeIntervalSince1970]);
	float currentVolume = 1.f;
	if (timeToEnd < fadeOutInterval) {
		currentVolume = timeToEnd / fadeOutInterval;
	}
	[self.delegate sleepTimer:self changeVolumeLevel:currentVolume];
}

@end
