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
	// #ff9600
	return [UIColor colorWithRed:255.0/255.0 green:150.0/255.0 blue:0.0/255.0 alpha:1.0];
}

+ (UIColor *)navigationBarContentColor {
	if (@available(iOS 13, *)) {
		return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
			if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
				return [UIColor whiteColor];
			} else {
				return [UIColor blackColor];
			}
		}];
	}
	return [UIColor blackColor];
}

+ (UIColor *)menuBackgroundColor {
	return [UIColor blackColor];
}

+ (UIColor *)menuContentColor {
	return [UIColor colorWithWhite:1.f alpha:0.6f];
}

+ (UIColor *)menuSeparatorColor {
	return [UIColor colorWithWhite:1.f alpha:0.2f];
}

+ (UIColor *)cellBackgroundColor {
	if (@available(iOS 13, *)) {
		return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
			if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
				return [UIColor colorWithRed:55.0/255.0 green:55.0/255.0 blue:55.0/255.0 alpha:1.0];
			} else {
				return [UIColor colorWithRed:210.0/255.0 green:210.0/255.0 blue:210.0/255.0 alpha:1.0];
			}
		}];
	}
	return [UIColor colorWithRed:210.0/255.0 green:210.0/255.0 blue:210.0/255.0 alpha:1.0];
}

+ (UIColor *)cellActionColor {
	return [self mainColor];
}

+ (UIColor *)cellReportColor {
	return [UIColor redColor];
}

+ (UIColor *)textColor {
	if (@available(iOS 13, *)) {
		return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
			if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
				return [UIColor whiteColor];
			} else {
				return [UIColor blackColor];
			}
		}];
	}
	return [UIColor blackColor];
}

+ (UIColor *)disabledTextColor {
	return [UIColor colorWithWhite:0.f alpha:0.4f];
}

+ (UIFont *)applicationFontWithSize:(CGFloat)size {
	return [UIFont fontWithName:@"HelveticaNeue" size:size];
}

+ (UIFont *)boldApplicationFontWithSize:(CGFloat)size {
	return [UIFont fontWithName:@"HelveticaNeue-Bold" size:size];
}

+ (UIFont *)mediumApplicationFontWithSize:(CGFloat)size {
	return [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
}

+ (UIFont *)lightApplicationFontWithSize:(CGFloat)size {
	return [UIFont fontWithName:@"HelveticaNeue-Light" size:size];
}

@end
