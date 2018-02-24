//
//  SRNowPlayingView.m
//  SloRadio
//
//  Created by Jernej Fijačko on 2. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRNowPlayingView.h"
#import "CBAutoScrollLabel.h"

static NSTimeInterval const kNowPlayingPauseInterval = 3.0;
static CGFloat const kNowPlayingLabelSpacing = 15.f;

static CGFloat const kTitleFontSize = 17.f;
static CGFloat const kSubtitleFontSize = 14.f;
static CGFloat const kSingleLineFontSize = 16.f;

@interface SRNowPlayingView () {
	BOOL _singleLineMode;
}

@property (nonatomic, strong) CBAutoScrollLabel *titleLabel;
@property (nonatomic, strong) CBAutoScrollLabel *subtitleLabel;

@end

@implementation SRNowPlayingView

@synthesize titleString = _titleString;
@synthesize subtitleString = _subtitleString;

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super init];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (void)commonInit {
	// background
	self.backgroundColor = [UIColor clearColor];
	
	// title label
	CBAutoScrollLabel *titleLabel = [[CBAutoScrollLabel alloc] init];
	titleLabel.font = [SRAppearance mediumApplicationFontWithSize:kTitleFontSize];
	titleLabel.textColor = [SRAppearance navigationBarContentColor];
	titleLabel.labelSpacing = kNowPlayingLabelSpacing;
	titleLabel.pauseInterval = kNowPlayingPauseInterval;
	titleLabel.textAlignment = NSTextAlignmentCenter;
	[self addSubview:titleLabel];
	self.titleLabel = titleLabel;
	
	// subtitle label
	CBAutoScrollLabel *subtitleLabel = [[CBAutoScrollLabel alloc] init];
	subtitleLabel.font = [SRAppearance lightApplicationFontWithSize:kSubtitleFontSize];
	subtitleLabel.textColor = [SRAppearance navigationBarContentColor];
	subtitleLabel.labelSpacing = kNowPlayingLabelSpacing;
	subtitleLabel.pauseInterval = kNowPlayingPauseInterval;
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	[self addSubview:subtitleLabel];
	self.subtitleLabel = subtitleLabel;
	
	_singleLineMode = NO;
}

#pragma mark - Layout

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.bounds;
	CGSize titleSize = [self.titleLabel.text sizeWithAttributes:@{NSFontAttributeName:self.titleLabel.font}];
	CGSize subtitleSize = [self.subtitleLabel.text sizeWithAttributes:@{NSFontAttributeName:self.subtitleLabel.font}];
	CGFloat heightNeeded = titleSize.height + subtitleSize.height;
	BOOL requiresSingleLineMode = heightNeeded > CGRectGetHeight(bounds);
	if (requiresSingleLineMode != _singleLineMode) {
		if (requiresSingleLineMode) {
			_singleLineMode = YES;
			self.titleLabel.attributedText = [self singleLineText];
			self.subtitleLabel.hidden = YES;
		}
		else {
			_singleLineMode = NO;
			self.titleLabel.text = self.titleString;
			self.subtitleLabel.hidden = NO;
		}
	}
	if (_singleLineMode) {
		heightNeeded = titleSize.height;
		subtitleSize.height = 0.f;
	}
	self.titleLabel.frame = CGRectMake(0,
									   roundf((CGRectGetHeight(bounds) - heightNeeded)/2),
									   CGRectGetWidth(bounds),
									   titleSize.height);
	self.subtitleLabel.frame = CGRectMake(0,
										  CGRectGetMaxY(self.titleLabel.frame),
										  CGRectGetWidth(bounds),
										  subtitleSize.height);
}

#pragma mark - Setters

- (void)setTitleString:(NSString *)titleString {
	_titleString = [titleString copy];
	self.titleLabel.text = _titleString;
	_singleLineMode = NO;
	[self setNeedsLayout];
}

- (void)setSubtitleString:(NSString *)subtitleString {
	_subtitleString = [subtitleString copy];
	self.subtitleLabel.text = _subtitleString;
	self.subtitleLabel.hidden = NO;
	_singleLineMode = NO;
	[self setNeedsLayout];
}

#pragma mark - Getters

- (NSAttributedString *)singleLineText {
	NSDictionary *titleAttributes = @{NSFontAttributeName:[SRAppearance mediumApplicationFontWithSize:kSingleLineFontSize]};
	NSDictionary *subtitleAttributes = @{NSFontAttributeName:[SRAppearance lightApplicationFontWithSize:kSingleLineFontSize]};
	NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:self.titleString
																			 attributes:titleAttributes];
	if (self.subtitleString.length) {
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:@" "
																	 attributes:titleAttributes]];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:self.subtitleString
																	 attributes:subtitleAttributes]];
	}
	return text;
}

#pragma mark - Size

- (CGSize)sizeThatFits:(CGSize)size {
	return size;
}

@end
