//
//  SRSliderTableViewCell.h
//  SloRadio
//
//  Created by Jernej Fijačko on 8. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol SRSliderTableViewCellProtocol;

@interface SRSliderTableViewCell : UITableViewCell

@property (nonatomic, weak) id<SRSliderTableViewCellProtocol> delegate;
@property (nonatomic, assign) float minimumSliderValue;
@property (nonatomic, assign) float maximumSliderValue;
@property (nonatomic, assign) float sliderValue;

@end

@protocol SRSliderTableViewCellProtocol <NSObject>

@required
- (void)cell:(SRSliderTableViewCell *)cell didChangeSliderValue:(float)sliderValue;

@end