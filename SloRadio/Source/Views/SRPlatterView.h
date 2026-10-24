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

@end
