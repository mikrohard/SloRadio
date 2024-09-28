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

extern NSString * const SRRadioPlayerStateDidChangeNotification;
extern NSString * const SRRadioPlayerMetaDataDidChangeNotification;
extern NSString * const SRRadioPlayerMetaDataArtistKey;
extern NSString * const SRRadioPlayerMetaDataTitleKey;
extern NSString * const SRRadioPlayerMetaDataGenreKey;
extern NSString * const SRRadioPlayerMetaDataNowPlayingKey;

@protocol SRRadioPlayerDelegate;

@class SRRadioStation;

@interface SRRadioPlayer : NSObject

@property (nonatomic, readonly) SRRadioPlayerState state;
@property (nonatomic, readonly) SRRadioStation *currentRadioStation;
@property (nonatomic, readonly) NSDictionary *metaData;
@property (nonatomic, readonly) NSTimeInterval timePlaying;
@property (nonatomic, weak) id <SRRadioPlayerDelegate> delegate;

+ (SRRadioPlayer *)sharedPlayer;
- (void)playRadioStation:(SRRadioStation *)station;
- (void)playStreamAtUrl:(NSURL *)url;
- (void)stop;

- (void)setVolume:(int)volume;

@end

@protocol SRRadioPlayerDelegate <NSObject>

@optional

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state;
- (void)radioPlayer:(SRRadioPlayer *)player didChangeMetaData:(NSDictionary *)metadata;

@end
