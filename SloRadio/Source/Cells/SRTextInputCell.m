//
//  SRTextInputCell.m
//  SloRadio
//
//  Created by Jernej Fijačko on 30. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRTextInputCell.h"

@implementation SRTextInputCell

@synthesize textInputField = _textInputField;

#pragma mark - Lifecycle

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		UITextField *textField = [[UITextField alloc] init];
		[self.contentView addSubview:textField];
		_textInputField = textField;
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.contentView.bounds;
	CGFloat horizontalPadding = self.separatorInset.left;
	_textInputField.frame = CGRectMake(horizontalPadding, 0, CGRectGetWidth(bounds) - horizontalPadding, CGRectGetHeight(bounds));
}

- (UIEdgeInsets)layoutMargins {
	return UIEdgeInsetsZero;
}

- (NSDirectionalEdgeInsets)directionalLayoutMargins {
	return NSDirectionalEdgeInsetsZero;
}

@end
