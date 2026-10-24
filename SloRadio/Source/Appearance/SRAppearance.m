//
//  SRAppearance.m
//  SloRadio
//
//  Created by Jernej Fijačko on 29. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAppearance.h"

static CGFloat const SRIconSize = 30.f;
static CGFloat const SRIconCornerRadius = 7.f;
static CGFloat const SRIconSymbolPointSize = 15.f;

@implementation SRAppearance

+ (UIColor *)mainColor {
	// #ff9600
	return [UIColor colorWithRed:255.0/255.0 green:150.0/255.0 blue:0.0/255.0 alpha:1.0];
}

+ (UIImage *)iconWithSymbolName:(NSString *)symbolName backgroundColor:(UIColor *)backgroundColor {
	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:SRIconSymbolPointSize weight:UIImageSymbolWeightSemibold];
	UIImage *symbol = [[UIImage systemImageNamed:symbolName withConfiguration:configuration] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
	CGRect bounds = CGRectMake(0, 0, SRIconSize, SRIconSize);
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:bounds.size];
	UIImage *icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[backgroundColor setFill];
		[[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:SRIconCornerRadius] fill];
		CGSize symbolSize = symbol.size;
		[symbol drawInRect:CGRectMake((SRIconSize - symbolSize.width) / 2,
									  (SRIconSize - symbolSize.height) / 2,
									  symbolSize.width,
									  symbolSize.height)];
	}];
	return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@end
