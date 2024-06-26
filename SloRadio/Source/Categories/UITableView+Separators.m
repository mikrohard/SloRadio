//
//  UITableView+Separators.m
//  SloRadio
//
//  Created by Jernej Fijačko on 2. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "UITableView+Separators.h"
#import "SRSeparatorView.h"

static NSInteger SRSeparatorViewTag = 100010001;

@implementation UITableView (Separators)

- (void)configureSeparatorForCell:(UITableViewCell *)cell {
	SRSeparatorView *separatorView = (SRSeparatorView *)[cell viewWithTag:SRSeparatorViewTag];
	if (!separatorView) {
		separatorView = [[SRSeparatorView alloc] init];
		separatorView.separatorColor = self.separatorColor;
		separatorView.tag = SRSeparatorViewTag;
	}
	CGRect separatorFrame = separatorView.frame;
	separatorFrame.origin.x = cell.separatorInset.left;
	separatorFrame.size.width = CGRectGetWidth(cell.bounds) - separatorFrame.origin.x;
	separatorFrame.size.height = 1.f / [[UIScreen mainScreen] scale];
	separatorFrame.origin.y = CGRectGetHeight(cell.bounds) - separatorFrame.size.height;
	separatorView.frame = separatorFrame;
	separatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[cell addSubview:separatorView];
}

- (UIEdgeInsets)layoutMargins {
	return UIEdgeInsetsZero;
}

- (NSDirectionalEdgeInsets)directionalLayoutMargins {
	return NSDirectionalEdgeInsetsZero;
}

@end
