//
//  SRSleepTimerView.m
//  SloRadio
//
//  Created by Jernej Fijačko on 3. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRSleepTimerView.h"

static CGFloat const kButtonSize = 44.f;
static CGFloat const kDefaultHorizontalPadding = 15.f;

static NSString *formatHHmmss;

@interface SRSleepTimerView ()

@property (nonatomic, strong) UINavigationBar *backgroundView;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UILabel *timeLabel;

@end

@implementation SRSleepTimerView

@synthesize delegate = _delegate;
@synthesize timeRemaining = _timeRemaining;
@synthesize backgroundView = _backgroundView;
@synthesize cancelButton = _cancelButton;
@synthesize timeLabel = _timeLabel;
@synthesize horizontalPadding = _horizontalPadding;

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    // setup background
    self.backgroundColor = [UIColor clearColor];
    UINavigationBar *bar = [[UINavigationBar alloc] initWithFrame:self.bounds];
    bar.barStyle = UIBarStyleDefault;
    [self addSubview:bar];
    self.backgroundView = bar;
    
    // setup button
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *buttonImage = [UIImage imageNamed:@"Cancel"];
    [cancelButton setImage:buttonImage forState:UIControlStateNormal];
    [cancelButton addTarget:self action:@selector(cancelButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:cancelButton];
    self.cancelButton = cancelButton;
    
    // setup time label
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = [SRAppearance lightApplicationFontWithSize:17.f];
    [self addSubview:label];
    self.timeLabel = label;
    
    // format for HH:mm:ss
    formatHHmmss = [[[[NSDateFormatter dateFormatFromTemplate:@"HH mm ss" options:0 locale:[NSLocale currentLocale]]
                      stringByReplacingOccurrencesOfString:@"HH" withString:@"%02d"]
                     stringByReplacingOccurrencesOfString:@"mm" withString:@"%02d"]
                    stringByReplacingOccurrencesOfString:@"ss" withString:@"%02d"];
    
    _horizontalPadding = kDefaultHorizontalPadding;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    self.backgroundView.frame = bounds;
    CGFloat horizontalPadding = self.horizontalPadding;
    CGFloat labelWidth = CGRectGetWidth(bounds) - kButtonSize - 2*horizontalPadding;
    self.timeLabel.frame = CGRectMake(horizontalPadding,
                                      0,
                                      labelWidth,
                                      CGRectGetHeight(bounds));
    self.cancelButton.frame = CGRectMake(CGRectGetMaxX(self.timeLabel.frame) + horizontalPadding,
                                         0,
                                         kButtonSize,
                                         CGRectGetHeight(bounds));
}

- (void)setHorizontalPadding:(CGFloat)horizontalPadding {
    if (_horizontalPadding != horizontalPadding) {
        _horizontalPadding = horizontalPadding;
        [self setNeedsLayout];
    }
}

#pragma mark - Cancel button

- (void)cancelButtonPressed:(id)sender {
    if ([self.delegate respondsToSelector:@selector(sleepTimerViewCancelButtonPressed:)]) {
        [self.delegate sleepTimerViewCancelButtonPressed:self];
    }
}

#pragma mark - Set time remaining

- (void)setTimeRemaining:(NSTimeInterval)timeRemaining {
    if (_timeRemaining != timeRemaining) {
        _timeRemaining = timeRemaining;
        [self updateTimeLabel];
    }
}

- (void)updateTimeLabel {
    NSTimeInterval value = self.timeRemaining;
    int durationHours = (int)floor(value / 60 / 60);
    int durationMins = ((int)(floor(value / 60) - durationHours * 60)) % 60;
    int durationSeconds = ((int)(value - durationMins * 60 - durationHours * 60 * 60)) % 60;
    self.timeLabel.text = [NSString stringWithFormat:formatHHmmss, durationHours, durationMins, durationSeconds];
}

@end
