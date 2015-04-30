//
//  SRVolumeView.m
//  SloRadio
//
//  Created by Jernej Fijačko on 30. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRVolumeView.h"

@implementation SRVolumeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIImage *routeIcon = [UIImage imageNamed:@"AirPlayIcon"];
        [self setRouteButtonImage:routeIcon forState:UIControlStateNormal];
        UIImage *routeSelected = [routeIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self setRouteButtonImage:routeSelected forState:UIControlStateSelected];
    }
    return self;
}

- (CGRect)volumeSliderRectForBounds:(CGRect)bounds {
    CGRect newBounds = [super volumeSliderRectForBounds:bounds];
    newBounds.origin.y = bounds.origin.y;
    newBounds.size.height = bounds.size.height;
    return newBounds;
}

- (CGRect)routeButtonRectForBounds:(CGRect)bounds {
    CGRect newBounds = [super routeButtonRectForBounds:bounds];
    newBounds.origin.y = bounds.origin.y;
    newBounds.size.height = bounds.size.height;
    return newBounds;
}

@end
