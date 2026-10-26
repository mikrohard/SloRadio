//
//  SRPlatterView.h
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

// Floating platter: Liquid Glass on iOS 26+, blurred material with a shadow on older systems.
@interface SRPlatterView : UIView

@property (nonatomic, readonly) UIView *contentView;

- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius;

// Shows or hides the platter material and its content (animatable). Liquid Glass doesn't fade well with alpha,
// so platters that appear or disappear should use this instead.
- (void)setMaterialized:(BOOL)materialized;

@end
