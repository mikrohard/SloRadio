//
//  SRSliderTableViewCell.m
//  SloRadio
//
//  Created by Jernej Fijačko on 8. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRSliderTableViewCell.h"

@interface SRSliderTableViewCell ()

@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;

@end

@implementation SRSliderTableViewCell

@synthesize slider = _slider;
@synthesize delegate = _delegate;

#pragma mark - Lifecycle

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		
		UILabel *titleLabel = [[UILabel alloc] init];
		titleLabel.text = NSLocalizedString(@"CacheSize", nil);
		titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		titleLabel.adjustsFontForContentSizeCategory = YES;
		self.titleLabel = titleLabel;
		
		UILabel *valueLabel = [[UILabel alloc] init];
		valueLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		valueLabel.adjustsFontForContentSizeCategory = YES;
		valueLabel.textColor = [UIColor secondaryLabelColor];
		valueLabel.textAlignment = NSTextAlignmentRight;
		[valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
		self.valueLabel = valueLabel;
		
		UISlider *slider = [[UISlider alloc] init];
		slider.minimumTrackTintColor = [SRAppearance mainColor];
		[slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
		self.slider = slider;
		
		UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, valueLabel]];
		labels.axis = UILayoutConstraintAxisHorizontal;
		labels.spacing = 8.f;
		UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[labels, slider]];
		stack.axis = UILayoutConstraintAxisVertical;
		stack.spacing = 8.f;
		stack.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:stack];
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[stack.topAnchor constraintEqualToAnchor:margins.topAnchor],
			[stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
			[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		]];
	}
	return self;
}

#pragma mark - Slider setters/accessors

- (void)setSliderValue:(float)sliderValue {
	self.slider.value = sliderValue;
	[self updateLabels];
}

- (float)sliderValue {
	return self.slider.value;
}

- (void)setMinimumSliderValue:(float)minimumSliderValue {
	self.slider.minimumValue = minimumSliderValue;
}

- (float)minimumSliderValue {
	return self.slider.minimumValue;
}

- (void)setMaximumSliderValue:(float)maximumSliderValue {
	self.slider.maximumValue = maximumSliderValue;
}

- (float)maximumSliderValue {
	return self.slider.maximumValue;
}

- (void)sliderValueChanged:(UISlider *)slider {
	[self updateLabels];
	[self.delegate cell:self didChangeSliderValue:self.sliderValue];
}

#pragma mark - Update labels

- (void)updateLabels {
	NSString *value = [NSString stringWithFormat:NSLocalizedString(@"NumberOfSeconds", nil), self.sliderValue];
	self.valueLabel.text = value;
	self.slider.accessibilityLabel = self.titleLabel.text;
	self.slider.accessibilityValue = value;
}

@end
