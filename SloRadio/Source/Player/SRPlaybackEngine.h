//
//  SRPlaybackEngine.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SRRadioPlayer.h"

@protocol SRPlaybackEngineDelegate;

// A playback backend driven by SRRadioPlayer: AVPlayer for HLS, a native engine for everything else.
// An engine plays one URL once. SRRadioPlayer creates a new engine for every (re)start.
// All methods must be called on the main thread and all delegate callbacks arrive on the main thread.
@protocol SRPlaybackEngine <NSObject>

@property (nonatomic, weak) id<SRPlaybackEngineDelegate> delegate;
// Seconds of audio played since playback started (0 while opening or buffering for the first time).
@property (nonatomic, readonly) NSTimeInterval playbackTime;

// bufferDuration: seconds of audio to buffer before playback starts, 0 for the engine's default.
- (instancetype)initWithURL:(NSURL *)url bufferDuration:(NSTimeInterval)bufferDuration;
- (void)start;
// Stops playback and releases all resources. No delegate callbacks are sent after this.
- (void)stop;
// 0.0 - 1.0
- (void)setVolume:(float)volume;

@end

@protocol SRPlaybackEngineDelegate <NSObject>

// Opening, Buffering, Playing, Paused or Error. Playing means audio is audible.
// After Error the engine is finished and only -stop may be called.
- (void)playbackEngine:(id<SRPlaybackEngine>)engine didChangeState:(SRRadioPlayerState)state;
// A full snapshot of the stream metadata keyed by the SRRadioPlayerMetaData*Key constants.
// Values are raw strings as found in the stream, SRRadioPlayer cleans them up.
- (void)playbackEngine:(id<SRPlaybackEngine>)engine didChangeMetaData:(NSDictionary<NSString *, NSString *> *)metaData;
// The stream stopped delivering audio (stalled or ended) after it was opened. SRRadioPlayer reconnects.
- (void)playbackEngineDidStall:(id<SRPlaybackEngine>)engine;

@end
