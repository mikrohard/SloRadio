//
//  SRRadioPlayer.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioPlayer.h"
#import "SRRadioStation.h"
#import "SRDataManager.h"
#import <MobileVLCKit/MobileVLCKit.h>

NSString * const SRRadioPlayerMetaDataArtistKey = @"SRRadioPlayerMetaDataArtistKey";
NSString * const SRRadioPlayerMetaDataTitleKey = @"SRRadioPlayerMetaDataTitleKey";
NSString * const SRRadioPlayerMetaDataGenreKey = @"SRRadioPlayerMetaDataGenreKey";
NSString * const SRRadioPlayerMetaDataNowPlayingKey = @"SRRadioPlayerMetaDataNowPlayingKey";

@interface SRRadioPlayer () <VLCMediaDelegate, VLCMediaPlayerDelegate>

@property (nonatomic, strong) VLCMediaListPlayer *listPlayer;
@property (nonatomic, strong) VLCMediaPlayer *player;
@property (nonatomic, strong) VLCMedia *media;

@end

@implementation SRRadioPlayer

@synthesize state = _state;
@synthesize currentRadioStation = _currentRadioStation;
@synthesize metaData = _metaData;
@synthesize timePlaying = _timePlaying;
@synthesize delegate = _delegate;

#pragma mark - Singleton

+ (SRRadioPlayer *)sharedPlayer {
    static SRRadioPlayer *sharedRadioPlayer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedRadioPlayer = [[self alloc] init];
    });
    return sharedRadioPlayer;
}

#pragma mark - Playback control

- (void)playRadioStation:(SRRadioStation *)station {
    _currentRadioStation = station;
    [self stopIfPlayingAndClearStation:NO];
    [self playStreamAtUrl:station.url];
}

- (void)playStreamAtUrl:(NSURL *)url {
    [self stopIfPlayingAndClearStation:YES];
    self.listPlayer = [[VLCMediaListPlayer alloc] initWithOptions:[self playbackOptions]];
    self.player = self.listPlayer.mediaPlayer;
    self.player.delegate = self;
    VLCMedia *media = [VLCMedia mediaWithURL:url];
    [self registerMedia:media];
    [self.listPlayer setRootMedia:media];
    [self.listPlayer playMedia:media];
    [self updatePlayerState];
}

- (void)stopIfPlayingAndClearStation:(BOOL)clearStation {
    if (self.player) {
        [self.player stop];
        self.player = nil;
        self.listPlayer = nil;
        [self registerMedia:nil];
        [self updatePlayerState];
        if (clearStation) {
            _currentRadioStation = nil;
        }
        _timePlaying = 0.0;
        [self updateMetaData];
    }
}

- (void)stop {
    [self.player stop];
    self.player = nil;
    self.listPlayer = nil;
    [self registerMedia:nil];
    [self updatePlayerState];
    _currentRadioStation = nil;
    _timePlaying = 0.0;
    [self updateMetaData];
}

- (void)setVolume:(int)volume {
    self.player.audio.volume = volume;
}

#pragma mark - Playback options

- (NSArray *)playbackOptions {
    SRDataManager *dataManager = [SRDataManager sharedManager];
    if (dataManager.playerCachingEnabled) {
        NSString *cachingOption = [NSString stringWithFormat:@"--network-caching=%.0f", dataManager.playerCacheSize * 1000];
        return @[cachingOption];
    }
    return nil;
}

#pragma mark - Meta data

- (void)updateMetaData {
	[self updateMetaDataPreserveNowPlaying:NO];
}

- (void)updateMetaDataPreserveNowPlaying:(BOOL)preserve {
    NSDictionary *mediaMetaData = self.media.metaDictionary;
    NSString *genre = [mediaMetaData objectForKey:VLCMetaInformationGenre];
    NSString *title = [mediaMetaData objectForKey:VLCMetaInformationTitle];
    NSString *artist = [mediaMetaData objectForKey:VLCMetaInformationArtist];
    NSString *nowPlaying = [mediaMetaData objectForKey:VLCMetaInformationNowPlaying];
	if (preserve && !nowPlaying) {
		nowPlaying = [_metaData objectForKey:SRRadioPlayerMetaDataNowPlayingKey];
	}
    NSMutableDictionary *metaData = [NSMutableDictionary dictionary];
    if (genre) {
        [metaData setObject:genre forKey:SRRadioPlayerMetaDataGenreKey];
    }
    if (title) {
        [metaData setObject:title forKey:SRRadioPlayerMetaDataTitleKey];
    }
    if (artist) {
        [metaData setObject:artist forKey:SRRadioPlayerMetaDataArtistKey];
    }
    if (nowPlaying) {
        [metaData setObject:nowPlaying forKey:SRRadioPlayerMetaDataNowPlayingKey];
	}
    _metaData = [NSDictionary dictionaryWithDictionary:metaData];
    if ([self.delegate respondsToSelector:@selector(radioPlayer:didChangeMetaData:)]) {
        [self.delegate radioPlayer:self didChangeMetaData:self.metaData];
    }
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
        if (oldMediaState != newMediaState) {
            [self updatePlayerState];
        }
    }
}

#pragma mark - VLCMediaPlayerDelegate

- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification {
    _timePlaying = self.player.time.value.doubleValue / 1000.0;
    if (self.state != SRRadioPlayerStatePlaying && self.timePlaying > 0) {
        [self updatePlayerState];
    }
}

- (void)mediaPlayerStateChanged:(NSNotification *)aNotification {
    [self registerMedia:self.player.media];
    [self updatePlayerState];
}

#pragma mark - VLCMediaDelegate

- (void)mediaMetaDataDidChange:(VLCMedia *)aMedia {
    [self updateMetaDataPreserveNowPlaying:YES];
}

- (void)mediaDidFinishParsing:(VLCMedia *)aMedia {
    [self updateMetaDataPreserveNowPlaying:YES];
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
                state = self.timePlaying > 0 ? SRRadioPlayerStatePlaying : SRRadioPlayerStateBuffering;
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
                state = self.timePlaying > 0 ? SRRadioPlayerStatePlaying : SRRadioPlayerStateBuffering;
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
            [self.media parseWithOptions:VLCMediaParseNetwork];
        }
        if ([self.delegate respondsToSelector:@selector(radioPlayer:didChangeState:)]) {
            [self.delegate radioPlayer:self didChangeState:_state];
        }
    }
}

@end
