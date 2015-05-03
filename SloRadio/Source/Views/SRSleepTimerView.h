//
//  SRSleepTimerView.h
//  SloRadio
//
//  Created by Jernej Fijačko on 3. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol SRSleepTimerViewDelegate;

@interface SRSleepTimerView : UIView

@property (nonatomic, weak) id<SRSleepTimerViewDelegate> delegate;
@property (nonatomic, assign) NSTimeInterval timeRemaining;
@property (nonatomic, assign) CGFloat horizontalPadding;

@end

@protocol SRSleepTimerViewDelegate <NSObject>

@optional
- (void)sleepTimerViewCancelButtonPressed:(SRSleepTimerView *)view;

@end