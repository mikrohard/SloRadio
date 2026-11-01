//
//  SRRadioViewController.h
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SRRadioViewController : UIViewController

@property (nonatomic, readonly) UITableView *tableView;

- (void)scrollToSelectedStationAnimated:(BOOL)animated;

// Screens also opened from the menu bar. Only one sheet can be shown at a time, see -isPresentingSheet.
- (void)presentSettings;
- (void)presentAbout;
- (void)presentAddRadioController;
- (BOOL)isPresentingSheet;

@end
