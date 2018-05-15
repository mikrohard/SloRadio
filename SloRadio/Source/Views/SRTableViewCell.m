//
//  SRTableViewCell.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 12. 17.
//  Copyright © 2017 Jernej Fijačko. All rights reserved.
//

#import "SRTableViewCell.h"

@implementation SRTableViewCell {
	UITableViewCellStyle _cellStyle;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		_cellStyle = style;
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_cellStyle == UITableViewCellStyleValue2) {
		self.textLabel.textAlignment = NSTextAlignmentLeft;
	}
}

- (UIEdgeInsets)layoutMargins {
	return UIEdgeInsetsZero;
}

- (NSDirectionalEdgeInsets)directionalLayoutMargins {
	return NSDirectionalEdgeInsetsZero;
}

@end
