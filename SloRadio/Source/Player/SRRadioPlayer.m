//
//  SRRadioPlayer.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioPlayer.h"
#import <MobileVLCKit/MobileVLCKit.h>

@interface SRRadioPlayer () <VLCMediaDelegate, VLCMediaPlayerDelegate>

@property (nonatomic, strong) VLCMediaListPlayer *listPlayer;
@property (nonatomic, strong) VLCMediaPlayer *player;
@property (nonatomic, strong) VLCMedia *media;

@end

@implementation SRRadioPlayer

@synthesize state = _state;
@synthesize delegate = _delegate;

#pragma mark - Playback control

- (void)playStreamAtUrl:(NSURL *)url {
    self.listPlayer = [[VLCMediaListPlayer alloc] init];
    self.player = self.listPlayer.mediaPlayer;
    self.player.delegate = self;
    VLCMedia *media = [VLCMedia mediaWithURL:url];
    [self registerMedia:media];
    [self.listPlayer setRootMedia:media];
    [self.listPlayer playMedia:media];
}

- (void)stop {
    [self.player stop];
    self.player = nil;
    self.listPlayer = nil;
    [self registerMedia:nil];
}

#pragma mark - Register media

- (void)registerMedia:(VLCMedia *)media {
    if (self.media != media) {
        [self unregisterMediaKVO];
        self.media.delegate = nil;
        self.media = nil;
        self.media = media;
        self.media.delegate = self;
        [self registerMediaKVO];
    }
}

- (void)registerMediaKVO {
    if (self.media) {
        [self.media addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:nil];
    }
}

- (void)unregisterMediaKVO {
    if (self.media) {
        [self.media removeObserver:self forKeyPath:@"state"];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.media && [keyPath isEqualToString:@"state"]) {
        VLCMediaState oldMediaState = [[change objectForKey:NSKeyValueChangeOldKey] integerValue];
        VLCMediaState newMediaState = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        NSLog(@"Media state changed from %ld to %ld", oldMediaState, newMediaState);
        [self updatePlayerState];
    }
}

#pragma mark - VLCMediaPlayerDelegate

- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification {
    NSLog(@"time changed %.2f", self.player.time.numberValue.doubleValue);
}

- (void)mediaPlayerStateChanged:(NSNotification *)aNotification {
    [self registerMedia:self.player.media];
    [self updatePlayerState];
}

#pragma mark - VLCMediaDelegate

- (void)media:(VLCMedia *)aMedia metaValueChangedFrom:(id)oldValue forKey:(NSString *)key {
    NSLog(@"metadata changed %@", [aMedia.metaDictionary objectForKey:key]);
}

- (void)mediaDidFinishParsing:(VLCMedia *)aMedia {
    NSLog(@"finished parsing media");
    NSLog(@"metadata dict %@", self.player.media.metaDictionary);
}

#pragma mark - Player state handling

- (void)updatePlayerState {
    SRRadioPlayerState state = SRRadioPlayerStateStopped;
    if (self.player) {
        switch (self.player.state) {
            case VLCMediaPlayerStateBuffering:
                state = SRRadioPlayerStateBuffering;
                break;
            case VLCMediaPlayerStatePlaying:
                state = SRRadioPlayerStatePlaying;
                break;
            case VLCMediaPlayerStatePaused:
                state = SRRadioPlayerStatePaused;
                break;
            case VLCMediaPlayerStateError:
                state = SRRadioPlayerStateError;
                break;
            case VLCMediaPlayerStateStopped:
            case VLCMediaPlayerStateEnded:
            default:
                break;
        }
    }
    if (self.media && self.media.state != VLCMediaStateNothingSpecial) {
        switch (self.media.state) {
            case VLCMediaStateBuffering:
                state = SRRadioPlayerStateBuffering;
                break;
            case VLCMediaStatePlaying:
                state = SRRadioPlayerStatePlaying;
                break;
            case VLCMediaStateError:
                state = SRRadioPlayerStateError;
                break;
            default:
                break;
        }
    }
    if (state != _state) {
        _state = state;
        if (_state == SRRadioPlayerStatePlaying) {
            [self.media parse];
        }
        if ([self.delegate respondsToSelector:@selector(radioPlayer:didChangeState:)]) {
            [self.delegate radioPlayer:self didChangeState:_state];
        }
    }
}

@end
