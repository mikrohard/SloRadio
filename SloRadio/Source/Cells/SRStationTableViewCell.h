//
//  SRStationTableViewCell.h
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SRRadioStation;

// Station row with artwork thumbnail and an optional checkmark
@interface SRStationTableViewCell : UITableViewCell

@property (nonatomic, assign, getter=isChecked) BOOL checked;

+ (CGFloat)separatorInsetLeft;

- (void)configureWithStation:(SRRadioStation *)station;

@end
