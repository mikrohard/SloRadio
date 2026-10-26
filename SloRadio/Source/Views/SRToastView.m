//
//  SRToastView.m
//  SloRadio
//
//  Created by Jernej Fijačko on 26. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRToastView.h"
#import "SRPlatterView.h"

static NSTimeInterval const SRToastMinimumDuration = 3.0;
static NSTimeInterval const SRToastMaximumDuration = 5.0;
static CGFloat const SRToastMaximumWidth = 480.f;
static CGFloat const SRToastHiddenScale = 0.8f;

@interface SRToastView ()

@property (nonatomic, strong) SRPlatterView *platter;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSTimer *hideTimer;
@property (nonatomic, assign) BOOL hiding;

@end

@implementation SRToastView

// the toast that is currently visible
static __weak SRToastView *currentToast;

+ (void)showMessage:(NSString *)message inView:(UIView *)view {
	UIView *container = view.window ?: view;
	if (!container || message.length == 0) {
		return;
	}
	[currentToast hideAnimated:YES];

	SRToastView *toast = [[SRToastView alloc] initWithMessage:message];
	[container addSubview:toast];
	UILayoutGuide *safeArea = container.safeAreaLayoutGuide;
	NSLayoutConstraint *preferredWidth = [toast.widthAnchor constraintEqualToConstant:SRToastMaximumWidth];
	preferredWidth.priority = UILayoutPriorityDefaultHigh;
	[NSLayoutConstraint activateConstraints:@[
		[toast.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:8.f],
		[toast.centerXAnchor constraintEqualToAnchor:safeArea.centerXAnchor],
		[toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:safeArea.leadingAnchor constant:16.f],
		[toast.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-16.f],
		preferredWidth,
	]];
	[container layoutIfNeeded];
	currentToast = toast;

	// grow in while the platter materializes
	[toast.platter setMaterialized:NO];
	toast.transform = CGAffineTransformMakeScale(SRToastHiddenScale, SRToastHiddenScale);
	[UIView animateWithDuration:0.5
						  delay:0
		 usingSpringWithDamping:0.7f
		  initialSpringVelocity:0
						options:UIViewAnimationOptionAllowUserInteraction
					 animations:^{
		[toast.platter setMaterialized:YES];
		toast.transform = CGAffineTransformIdentity;
	} completion:nil];
	UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);

	// longer messages stay visible longer
	NSTimeInterval duration = MIN(MAX(SRToastMinimumDuration, message.length / 20.0), SRToastMaximumDuration);
	__weak SRToastView *weakToast = toast;
	toast.hideTimer = [NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(NSTimer *timer) {
		[weakToast hideAnimated:YES];
	}];
}

+ (void)hideCurrentToast {
	[currentToast hideAnimated:YES];
}

- (instancetype)initWithMessage:(NSString *)message {
	self = [super initWithFrame:CGRectZero];
	if (self) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		self.isAccessibilityElement = YES;
		self.accessibilityLabel = message;
		self.accessibilityTraits = UIAccessibilityTraitStaticText;

		SRPlatterView *platter = [[SRPlatterView alloc] initWithCornerRadius:24.f];
		platter.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:platter];
		self.platter = platter;

		UILabel *label = [[UILabel alloc] init];
		label.text = message;
		label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
		label.adjustsFontForContentSizeCategory = YES;
		label.textColor = [UIColor labelColor];
		label.textAlignment = NSTextAlignmentCenter;
		label.numberOfLines = 4;
		label.translatesAutoresizingMaskIntoConstraints = NO;
		[platter.contentView addSubview:label];
		self.label = label;

		[NSLayoutConstraint activateConstraints:@[
			[platter.topAnchor constraintEqualToAnchor:self.topAnchor],
			[platter.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[platter.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[platter.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[label.topAnchor constraintEqualToAnchor:platter.contentView.topAnchor constant:14.f],
			[label.bottomAnchor constraintEqualToAnchor:platter.contentView.bottomAnchor constant:-14.f],
			[label.leadingAnchor constraintEqualToAnchor:platter.contentView.leadingAnchor constant:20.f],
			[label.trailingAnchor constraintEqualToAnchor:platter.contentView.trailingAnchor constant:-20.f],
		]];

		[self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss:)]];
		UISwipeGestureRecognizer *swipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss:)];
		swipeRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
		[self addGestureRecognizer:swipeRecognizer];
	}
	return self;
}

- (void)dismiss:(UIGestureRecognizer *)recognizer {
	[self hideAnimated:YES];
}

- (BOOL)accessibilityPerformEscape {
	[self hideAnimated:YES];
	return YES;
}

- (void)hideAnimated:(BOOL)animated {
	if (self.hiding) {
		return;
	}
	self.hiding = YES;
	[self.hideTimer invalidate];
	self.hideTimer = nil;
	self.userInteractionEnabled = NO;
	// the glass dematerializes quickly, so the text fades out first (it would otherwise linger without a background)
	[UIView animateWithDuration:animated ? 0.1 : 0.0 animations:^{
		self.label.alpha = 0.f;
	}];
	// shrink while the platter dematerializes
	[UIView animateWithDuration:animated ? 0.3 : 0.0
						  delay:0
						options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
					 animations:^{
		[self.platter setMaterialized:NO];
		self.transform = CGAffineTransformMakeScale(SRToastHiddenScale, SRToastHiddenScale);
	} completion:^(BOOL finished) {
		[self removeFromSuperview];
	}];
}

@end
