//
//  SRSeparatorView.m
//  SloRadio
//
//  Created by Jernej Fijačko on 2. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRSeparatorView.h"

@implementation SRSeparatorView

@synthesize separatorColor = _separatorColor;

#pragma mark - Separator color

- (void)setSeparatorColor:(UIColor *)separatorColor {
	_separatorColor = separatorColor;
	[self setBackgroundColor:separatorColor];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
	[super setBackgroundColor:self.separatorColor];
}

@end
