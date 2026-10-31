//
//  SRAudioOutput.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SRAudioBuffer;

// Plays the audio of a ring buffer with AVAudioEngine.
@interface SRAudioOutput : NSObject

- (instancetype)initWithBuffer:(SRAudioBuffer *)buffer sampleRate:(double)sampleRate;

- (BOOL)start:(NSError **)error;
- (void)stop;

// While NO the output plays silence and leaves the buffer alone, so it can fill up (pre-roll / rebuffering).
// Set to YES once enough audio is buffered.
@property (atomic, assign) BOOL playing;
// Set by the render thread when it ran out of audio while playing. Cleared by setting `playing`.
@property (atomic, readonly) BOOL underrun;

// 0.0 - 1.0
@property (nonatomic, assign) float volume;

// Frames of buffered audio played so far (silence not counted).
@property (atomic, readonly) uint64_t renderedFrames;
// Frames from the moment a frame is rendered until it is heard (the output and device latency).
@property (nonatomic, readonly) uint64_t latencyFrames;

@end
