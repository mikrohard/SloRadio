//
//  SRPlayerViewController.h
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SRPlayerStyle) {
	SRPlayerStyleCompact,	// floating card at the bottom of the station list (iPhone)
	SRPlayerStyleExpanded,	// full panel with large artwork (iPad)
};

@interface SRPlayerViewController : UIViewController

@property (nonatomic, readonly) SRPlayerStyle style;
@property (nonatomic, readonly) UIView *platterView;
@property (nonatomic, readonly, getter=isCollapsed) BOOL collapsed;
@property (nonatomic, copy) void (^nowPlayingTapHandler)(void);
@property (nonatomic, copy) void (^layoutChangeHandler)(void);

- (instancetype)initWithStyle:(SRPlayerStyle)style;

// only supported by the compact style: collapses the card to a single row
- (void)setCollapsed:(BOOL)collapsed animated:(BOOL)animated;

@end
