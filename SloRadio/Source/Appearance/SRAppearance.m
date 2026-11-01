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
// list rows are lower on the Mac, smaller icons leave room around them (like in System Settings)
static CGFloat const SRMacIconSize = 22.f;
static CGFloat const SRMacIconCornerRadius = 5.f;
static CGFloat const SRMacIconSymbolPointSize = 11.f;

@implementation SRAppearance

+ (UIColor *)mainColor {
	// #ff9600
	return [UIColor colorWithRed:255.0/255.0 green:150.0/255.0 blue:0.0/255.0 alpha:1.0];
}

+ (UIImage *)iconWithSymbolName:(NSString *)symbolName backgroundColor:(UIColor *)backgroundColor {
	BOOL mac = [self isMacInterface];
	CGFloat iconSize = mac ? SRMacIconSize : SRIconSize;
	CGFloat cornerRadius = mac ? SRMacIconCornerRadius : SRIconCornerRadius;
	CGFloat pointSize = mac ? SRMacIconSymbolPointSize : SRIconSymbolPointSize;
	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
	UIImage *symbol = [[UIImage systemImageNamed:symbolName withConfiguration:configuration] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
	CGRect bounds = CGRectMake(0, 0, iconSize, iconSize);
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:bounds.size];
	UIImage *icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[backgroundColor setFill];
		[[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:cornerRadius] fill];
		CGSize symbolSize = symbol.size;
		[symbol drawInRect:CGRectMake((iconSize - symbolSize.width) / 2,
									  (iconSize - symbolSize.height) / 2,
									  symbolSize.width,
									  symbolSize.height)];
	}];
	return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (BOOL)isMacInterface {
	return [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomMac;
}

+ (void)fitSheetToTableViewController:(UITableViewController *)controller {
	if (![self isMacInterface]) {
		return;
	}
	// sheets are full sized by default, which leaves most of a short list empty
	UIViewController *sheet = controller.navigationController ?: controller;
	UITableView *tableView = controller.tableView;
	CGFloat height = tableView.contentSize.height + tableView.adjustedContentInset.top + tableView.adjustedContentInset.bottom;
	CGSize size = CGSizeMake(480.f, ceil(height));
	if (height > 0 && !CGSizeEqualToSize(sheet.preferredContentSize, size)) {
		sheet.preferredContentSize = size;
	}
}

+ (void)adjustListContentForMac:(UIListContentConfiguration *)content {
	if (![self isMacInterface]) {
		return;
	}
	content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(7.f, 12.f, 7.f, 12.f);
	content.imageToTextPadding = 10.f;
}

+ (void)usePadStyleForControl:(UIControl *)control {
	if ([control isKindOfClass:[UIButton class]]) {
		((UIButton *)control).preferredBehavioralStyle = UIBehavioralStylePad;
	} else if ([control isKindOfClass:[UISlider class]]) {
		((UISlider *)control).preferredBehavioralStyle = UIBehavioralStylePad;
	}
}

@end
