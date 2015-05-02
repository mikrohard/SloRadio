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
+ (UIColor *)navigationBarContentColor;
+ (UIColor *)menuBackgroundColor;
+ (UIColor *)menuContentColor;

+ (UIFont *)applicationFontWithSize:(CGFloat)size;
+ (UIFont *)boldApplicationFontWithSize:(CGFloat)size;
+ (UIFont *)mediumApplicationFontWithSize:(CGFloat)size;
+ (UIFont *)lightApplicationFontWithSize:(CGFloat)size;

@end
