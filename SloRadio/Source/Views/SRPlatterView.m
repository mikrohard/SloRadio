//
//  SRPlatterView.m
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRPlatterView.h"

@interface SRPlatterView ()

@property (nonatomic, strong) UIVisualEffectView *effectView;
@property (nonatomic, strong) UIVisualEffect *effect;
@property (nonatomic, assign) float shadowOpacity;
@property (nonatomic, strong) UIView *clippingView;

@end

@implementation SRPlatterView

- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius {
	self = [super initWithFrame:CGRectZero];
	if (self) {
		UIVisualEffectView *effectView = nil;
		if (@available(iOS 26, *)) {
			UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
			effectView = [[UIVisualEffectView alloc] initWithEffect:glass];
			effectView.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:cornerRadius]];
		} else {
			UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
			effectView = [[UIVisualEffectView alloc] initWithEffect:blur];
			effectView.layer.cornerRadius = cornerRadius;
			effectView.layer.cornerCurve = kCACornerCurveContinuous;
			effectView.layer.borderWidth = 1.f / [UIScreen mainScreen].scale;
			effectView.layer.borderColor = [UIColor separatorColor].CGColor;
			effectView.clipsToBounds = YES;
			self.layer.shadowColor = [UIColor blackColor].CGColor;
			self.layer.shadowOpacity = 0.15f;
			self.layer.shadowRadius = 16.f;
			self.layer.shadowOffset = CGSizeMake(0, 4.f);
		}
		effectView.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:effectView];
		self.effectView = effectView;
		self.effect = effectView.effect;
		self.shadowOpacity = self.layer.shadowOpacity;
		
		// content is clipped to the platter shape (e.g. while the platter animates its size)
		UIView *clippingView = [[UIView alloc] init];
		clippingView.clipsToBounds = YES;
		clippingView.layer.cornerRadius = cornerRadius;
		clippingView.layer.cornerCurve = kCACornerCurveContinuous;
		clippingView.translatesAutoresizingMaskIntoConstraints = NO;
		[effectView.contentView addSubview:clippingView];
		self.clippingView = clippingView;
		
		[NSLayoutConstraint activateConstraints:@[
			[effectView.topAnchor constraintEqualToAnchor:self.topAnchor],
			[effectView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[effectView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[effectView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[clippingView.topAnchor constraintEqualToAnchor:effectView.contentView.topAnchor],
			[clippingView.bottomAnchor constraintEqualToAnchor:effectView.contentView.bottomAnchor],
			[clippingView.leadingAnchor constraintEqualToAnchor:effectView.contentView.leadingAnchor],
			[clippingView.trailingAnchor constraintEqualToAnchor:effectView.contentView.trailingAnchor],
		]];
	}
	return self;
}

- (void)setMaterialized:(BOOL)materialized {
	self.effectView.effect = materialized ? self.effect : nil;
	self.clippingView.alpha = materialized ? 1.f : 0.f;
	self.layer.shadowOpacity = materialized ? self.shadowOpacity : 0.f;
	if (self.effectView.layer.borderWidth > 0) {
		self.effectView.layer.borderColor = materialized ? [UIColor separatorColor].CGColor : [UIColor clearColor].CGColor;
	}
}

- (UIView *)contentView {
	return self.clippingView;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	if (self.effectView.layer.borderWidth > 0) {
		self.effectView.layer.borderColor = [UIColor separatorColor].CGColor;
	}
}

@end
