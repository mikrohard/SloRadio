//
//  SRAppearance.m
//  SloRadio
//
//  Created by Jernej Fijačko on 29. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAppearance.h"

@implementation SRAppearance

+ (UIColor *)mainColor {
    return [UIColor orangeColor];
}

+ (UIColor *)navigationBarContentColor {
    return [UIColor whiteColor];
}

+ (UIColor *)menuBackgroundColor {
    return [UIColor blackColor];
}

+ (UIColor *)menuContentColor {
    return [UIColor colorWithWhite:1.f alpha:0.6f];
}

@end
