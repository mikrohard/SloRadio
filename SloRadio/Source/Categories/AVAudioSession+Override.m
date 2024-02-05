//
//  AVAudioSession+Override.m
//  SloRadio
//
//  Created by Jernej Fijačko on 5. 02. 24.
//  Copyright © 2024 Jernej Fijačko. All rights reserved.
//

#import "AVAudioSession+Override.h"
#import <objc/runtime.h>

@implementation AVAudioSession (Override)

+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(setActive:withOptions:error:)), class_getInstanceMethod(self, @selector(originalSetActive:withOptions:error:)));
}

- (BOOL)originalSetActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError *__autoreleasing  _Nullable *)outError {
    if (active) {
        return [self originalSetActive:active withOptions:options error:outError];
    }
    return YES;
}

@end
