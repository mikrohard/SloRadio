//
//  SRRadioPlayer.h
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum : NSUInteger {
    SRRadioPlayerStateStopped,
    SRRadioPlayerStateOpening,
    SRRadioPlayerStateBuffering,
    SRRadioPlayerStatePlaying,
    SRRadioPlayerStatePaused,
    SRRadioPlayerStateError,
} SRRadioPlayerState;

@protocol SRRadioPlayerDelegate;

@interface SRRadioPlayer : NSObject

@property (nonatomic, readonly) SRRadioPlayerState state;
@property (nonatomic, weak) id <SRRadioPlayerDelegate> delegate;

+ (SRRadioPlayer *)sharedPlayer;
- (void)playStreamAtUrl:(NSURL *)url;
- (void)stop;

@end

@protocol SRRadioPlayerDelegate <NSObject>

@optional

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state;

@end