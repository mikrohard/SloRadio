//
//  SRAddRadioViewController.h
//  SloRadio
//
//  Created by Jernej Fijačko on 30. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SRRadioStation;

@interface SRAddRadioViewController : UITableViewController

- (instancetype)initEmpty;
- (instancetype)initWithRadioStation:(SRRadioStation *)station;

@end
