//
//  SRRadioViewController.h
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SRRadioStation;

@interface SRRadioViewController : UIViewController

- (void)playRadioStation:(SRRadioStation *)station;

@end
