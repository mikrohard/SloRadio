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
		UIPickerView *pickerView = [[UIPickerView alloc] init];
		[self.contentView addSubview:pickerView];
		_pickerView = pickerView;
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.contentView.bounds;
	self.pickerView.frame = CGRectMake(0, 0, CGRectGetWidth(bounds), 162.f);
}

- (UIEdgeInsets)layoutMargins {
	return UIEdgeInsetsZero;
}

- (NSDirectionalEdgeInsets)directionalLayoutMargins {
	return NSDirectionalEdgeInsetsZero;
}

@end
