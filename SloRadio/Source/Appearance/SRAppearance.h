//
//  SRAppearance.h
//  SloRadio
//
//  Created by Jernej Fijačko on 29. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SRAppearance : NSObject

+ (UIColor *)mainColor;

// Settings style icon: a white symbol on a rounded, colored square
+ (UIImage *)iconWithSymbolName:(NSString *)symbolName backgroundColor:(UIColor *)backgroundColor;

// Keeps the iPad look and feel of a button or slider in the Mac app (which otherwise shows native Mac controls).
+ (void)usePadStyleForControl:(UIControl *)control;

@end
