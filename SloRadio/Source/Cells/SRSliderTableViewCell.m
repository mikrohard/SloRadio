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

@end

@implementation SRSliderTableViewCell

@synthesize slider = _slider;
@synthesize delegate = _delegate;

#pragma mark - Lifecycle

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UISlider *slider = [[UISlider alloc] init];
        slider.backgroundColor = [UIColor clearColor];
        [slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:slider];
        _slider = slider;
        
        self.textLabel.text = NSLocalizedString(@"CacheSize", nil);
        self.textLabel.font = [SRAppearance applicationFontWithSize:17.f];
        self.textLabel.textAlignment = NSTextAlignmentLeft;
        self.textLabel.textColor = [SRAppearance textColor];
        
        self.detailTextLabel.font = [SRAppearance applicationFontWithSize:17.f];
        self.detailTextLabel.textAlignment = NSTextAlignmentRight;
        self.detailTextLabel.textColor = [[SRAppearance textColor] colorWithAlphaComponent:0.4f];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [self.textLabel sizeToFit];
    [self.detailTextLabel sizeToFit];
    CGFloat horizongalPadding = self.separatorInset.left;
    CGFloat margin = 10.f;
    CGFloat sliderHeight = 54.f;
    CGFloat labelHeight = CGRectGetHeight(bounds) - sliderHeight + margin;
    
    CGRect detailLabelFrame = self.detailTextLabel.frame;
    detailLabelFrame.origin.x = CGRectGetWidth(bounds) - CGRectGetWidth(detailLabelFrame) - horizongalPadding;
    detailLabelFrame.origin.y = 0.f;
    detailLabelFrame.size.height = labelHeight;
    self.detailTextLabel.frame = detailLabelFrame;

    CGFloat availableWidth = CGRectGetWidth(bounds) - CGRectGetWidth(detailLabelFrame) - margin - 2*horizongalPadding;
    CGRect textLabelFrame = self.textLabel.frame;
    textLabelFrame.origin.x = horizongalPadding;
    textLabelFrame.origin.y = 0.f;
    textLabelFrame.size.height = labelHeight;
    textLabelFrame.size.width = MIN(CGRectGetWidth(self.textLabel.frame), availableWidth);
    self.textLabel.frame = textLabelFrame;
    
    self.slider.frame = CGRectMake(horizongalPadding,
                                   CGRectGetHeight(bounds) - sliderHeight,
                                   CGRectGetWidth(bounds) - 2*horizongalPadding,
                                   sliderHeight);
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
    self.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"NumberOfSeconds", nil), self.sliderValue];
    [self setNeedsLayout];
}

#pragma mark - Layout margins

- (UIEdgeInsets)layoutMargins {
	return UIEdgeInsetsZero;
}

- (NSDirectionalEdgeInsets)directionalLayoutMargins {
	return NSDirectionalEdgeInsetsZero;
}

@end
