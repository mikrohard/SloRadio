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
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		UITextField *textField = [[UITextField alloc] init];
		textField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		textField.adjustsFontForContentSizeCategory = YES;
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
		textField.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:textField];
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[textField.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[textField.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[textField.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[textField.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			[textField.heightAnchor constraintGreaterThanOrEqualToConstant:44.f],
		]];
		_textInputField = textField;
	}
	return self;
}

@end
