//
//  SRAppearance.h
//  SloRadio
//
//  Created by Jernej Fijačko on 29. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SRAppearance : NSObject

+ (UIColor *)mainColor;

// Settings style icon: a white symbol on a rounded, colored square
+ (UIImage *)iconWithSymbolName:(NSString *)symbolName backgroundColor:(UIColor *)backgroundColor;

// Whether the app runs with the Mac interface ("Optimize for Mac"), where controls and lists are more compact.
+ (BOOL)isMacInterface;

// On the Mac, sizes the sheet a table view controller is shown in to fit the table (call from -viewDidLayoutSubviews).
+ (void)fitSheetToTableViewController:(UITableViewController *)controller;

// On the Mac, gives list rows with an icon (iconWithSymbolName:) room around it; list margins are very small there.
+ (void)adjustListContentForMac:(UIListContentConfiguration *)content;

// Keeps the iPad look and feel of a button or slider in the Mac app (which otherwise shows native Mac controls).
+ (void)usePadStyleForControl:(UIControl *)control;

@end
