//
//  SRSettingsPickerCell.m
//  SloRadio
//
//  Created by Jernej Fijačko on 4. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRSettingsPickerCell.h"

@implementation SRSettingsPickerCell

@synthesize pickerView = _pickerView;

#pragma mark - Lifecycle

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		UIPickerView *pickerView = [[UIPickerView alloc] init];
		pickerView.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:pickerView];
		NSLayoutConstraint *height = [pickerView.heightAnchor constraintEqualToConstant:180.f];
		height.priority = UILayoutPriorityRequired - 1;
		[NSLayoutConstraint activateConstraints:@[
			[pickerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[pickerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[pickerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[pickerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			height,
		]];
		_pickerView = pickerView;
	}
	return self;
}

@end
