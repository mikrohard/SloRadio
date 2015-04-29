//
//  VLCDialogDisplayer+Suppress.m
//  SloRadio
//
//  Created by Jernej Fijačko on 29. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "VLCDialogDisplayer+Suppress.h"
#import <objc/runtime.h>

@implementation VLCDialogDisplayer (Supress)

+ (void)load {
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(displayError:)), class_getInstanceMethod(self, @selector(displayErrorSuppressed:)));
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(displayCritical:)), class_getInstanceMethod(self, @selector(displayCriticalSuppressed:)));
}

- (void)displayCriticalSuppressed:(NSDictionary *)dialog {
    // prevent VLC lib from displaying error popups
}

- (void)displayErrorSuppressed:(NSDictionary *)dialog {
    // prevent VLC lib from displaying error popups
}

@end
