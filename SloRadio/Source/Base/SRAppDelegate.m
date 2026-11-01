//
//  SRAppDelegate.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAppDelegate.h"
#import "SRMainViewController.h"
#import "SRPlaybackManager.h"
#import "SRRadioViewController.h"
#import "SRRadioPlayer.h"
#import "SRDataManager.h"
#import "Firebase.h"
#import <CarPlay/CarPlay.h>

@interface SRAppDelegate ()

@end

@implementation SRAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	// sets up the audio session & remote commands (also needed when launched from CarPlay)
	[SRPlaybackManager sharedManager];
	self.mainController = [[SRMainViewController alloc] init];
	[FIRApp configure];
	[FIRAnalytics setAnalyticsCollectionEnabled:YES];
	return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
	// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
	// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
	// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark - Menu bar

// The menu bar on the Mac (and on iPad with a keyboard): the usual app items plus the station list and playback controls.
- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder {
	[super buildMenuWithBuilder:builder];
	if (builder.system != [UIMenuSystem mainSystem]) {
		return;
	}
	// nothing to format (AppKit adds its own disabled document and toolbar items, they can't be removed here)
	[builder removeMenuForIdentifier:UIMenuFormat];

	// SloRadio: our own About screen (it also shows the acknowledgements) and Settings
	UICommand *aboutCommand = [UICommand commandWithTitle:NSLocalizedString(@"MenuAbout", @"About SloRadio")
													image:nil
												   action:@selector(showAbout:)
											 propertyList:nil];
	[builder replaceMenuForIdentifier:UIMenuAbout withMenu:[UIMenu menuWithTitle:@"" image:nil identifier:UIMenuAbout
																		 options:UIMenuOptionsDisplayInline
																		children:@[aboutCommand]]];
	UIKeyCommand *settingsCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"MenuSettings", @"Settings…")
															 image:nil
															action:@selector(showSettings:)
															 input:@","
													 modifierFlags:UIKeyModifierCommand
													  propertyList:nil];
	[builder replaceChildrenOfMenuForIdentifier:UIMenuPreferences fromChildrenBlock:^NSArray<UIMenuElement *> *(NSArray<UIMenuElement *> *children) {
		return @[settingsCommand];
	}];

	// File
	UIKeyCommand *addStationCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"MenuAddStation", @"Add Station…")
															   image:nil
															  action:@selector(addStation:)
															   input:@"n"
													   modifierFlags:UIKeyModifierCommand
														propertyList:nil];
	[builder insertChildMenu:[UIMenu menuWithTitle:@"" image:nil identifier:@"org.jernej.sloradio.menu.station"
										   options:UIMenuOptionsDisplayInline children:@[addStationCommand]]
		atStartOfMenuForIdentifier:UIMenuFile];

	// View: the station lists
	UIKeyCommand *allStationsCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"AllStations", @"All")
																image:nil
															   action:@selector(showStationList:)
																input:@"1"
														modifierFlags:UIKeyModifierCommand
														 propertyList:@(SRStationListAll)];
	UIKeyCommand *favoritesCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"Favorites", @"Favorites")
															  image:nil
															 action:@selector(showStationList:)
															  input:@"2"
													  modifierFlags:UIKeyModifierCommand
													   propertyList:@(SRStationListFavorites)];
	[builder insertChildMenu:[UIMenu menuWithTitle:@"" image:nil identifier:@"org.jernej.sloradio.menu.lists"
										   options:UIMenuOptionsDisplayInline children:@[allStationsCommand, favoritesCommand]]
		atStartOfMenuForIdentifier:UIMenuView];

	// Controls
	UIKeyCommand *playCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"Play", @"Play")
														 image:nil
														action:@selector(togglePlayback:)
														 input:@" "
												 modifierFlags:0
												  propertyList:nil];
	UIKeyCommand *nextCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"NextStation", @"Next Station")
														 image:nil
														action:@selector(playNextStation:)
														 input:UIKeyInputRightArrow
												 modifierFlags:UIKeyModifierCommand
												  propertyList:nil];
	UIKeyCommand *previousCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"PreviousStation", @"Previous Station")
															 image:nil
															action:@selector(playPreviousStation:)
															 input:UIKeyInputLeftArrow
													 modifierFlags:UIKeyModifierCommand
													  propertyList:nil];
	UIMenu *playbackMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"org.jernej.sloradio.menu.playback"
										 options:UIMenuOptionsDisplayInline children:@[playCommand, nextCommand, previousCommand]];
	UIKeyCommand *favoriteCommand = [UIKeyCommand commandWithTitle:NSLocalizedString(@"AddToFavorites", @"Add to favorites")
															 image:nil
															action:@selector(toggleFavorite:)
															 input:@"d"
													 modifierFlags:UIKeyModifierCommand
													  propertyList:nil];
	UIMenu *favoriteMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"org.jernej.sloradio.menu.favorite"
										 options:UIMenuOptionsDisplayInline children:@[favoriteCommand]];
	UICommand *sleepTimerCommand = [UICommand commandWithTitle:NSLocalizedString(@"PlayWithSleepTimer", @"Play with sleep timer")
														 image:nil
														action:@selector(toggleSleepTimer:)
												  propertyList:nil];
	UIMenu *sleepTimerMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"org.jernej.sloradio.menu.sleeptimer"
										   options:UIMenuOptionsDisplayInline children:@[sleepTimerCommand]];
	UIMenu *controlsMenu = [UIMenu menuWithTitle:NSLocalizedString(@"MenuControls", @"Controls") image:nil
									  identifier:@"org.jernej.sloradio.menu.controls" options:0
										children:@[playbackMenu, favoriteMenu, sleepTimerMenu]];
	[builder insertSiblingMenu:controlsMenu afterMenuForIdentifier:UIMenuView];

	// Help: there's no help book, so offer to get in touch instead
	UICommand *feedbackCommand = [UICommand commandWithTitle:NSLocalizedString(@"MenuSendFeedback", @"Send Feedback…")
													   image:nil
													  action:@selector(sendFeedback:)
												propertyList:nil];
	[builder replaceChildrenOfMenuForIdentifier:UIMenuHelp fromChildrenBlock:^NSArray<UIMenuElement *> *(NSArray<UIMenuElement *> *children) {
		return @[feedbackCommand];
	}];
}

- (SRRadioViewController *)radioController {
	return [self.mainController isKindOfClass:[SRMainViewController class]] ? ((SRMainViewController *)self.mainController).radioController : nil;
}

- (BOOL)isPlaying {
	switch ([[SRRadioPlayer sharedPlayer] state]) {
		case SRRadioPlayerStateOpening:
		case SRRadioPlayerStateBuffering:
		case SRRadioPlayerStatePlaying:
			return YES;
		default:
			return NO;
	}
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
	SRRadioViewController *radioController = [self radioController];
	if (action == @selector(showAbout:) || action == @selector(showSettings:) || action == @selector(addStation:)) {
		// one sheet at a time
		return radioController != nil && ![radioController isPresentingSheet];
	}
	if (action == @selector(showStationList:)) {
		return radioController != nil && ![radioController isPresentingSheet] && !radioController.tableView.editing;
	}
	if (action == @selector(togglePlayback:) || action == @selector(playNextStation:) || action == @selector(playPreviousStation:) ||
		action == @selector(toggleFavorite:) || action == @selector(toggleSleepTimer:)) {
		return [SRDataManager sharedManager].selectedRadioStation != nil;
	}
	if (action == @selector(sendFeedback:)) {
		return YES;
	}
	return [super canPerformAction:action withSender:sender];
}

- (void)validateCommand:(UICommand *)command {
	[super validateCommand:command];
	SRDataManager *dataManager = [SRDataManager sharedManager];
	if (command.action == @selector(togglePlayback:)) {
		command.title = [self isPlaying] ? NSLocalizedString(@"Pause", @"Pause") : NSLocalizedString(@"Play", @"Play");
	} else if (command.action == @selector(toggleFavorite:)) {
		BOOL favorite = [dataManager isFavoriteRadioStation:dataManager.selectedRadioStation];
		command.title = favorite ? NSLocalizedString(@"RemoveFromFavorites", nil) : NSLocalizedString(@"AddToFavorites", nil);
	} else if (command.action == @selector(toggleSleepTimer:)) {
		command.title = [SRPlaybackManager sharedManager].sleepTimerActive ? NSLocalizedString(@"CancelSleepTimer", nil) : NSLocalizedString(@"PlayWithSleepTimer", nil);
	} else if (command.action == @selector(showStationList:)) {
		command.state = [command.propertyList integerValue] == dataManager.selectedStationList ? UIMenuElementStateOn : UIMenuElementStateOff;
	}
}

- (void)showAbout:(id)sender {
	[[self radioController] presentAbout];
}

- (void)showSettings:(id)sender {
	[[self radioController] presentSettings];
}

- (void)addStation:(id)sender {
	// added stations go to the list of all stations
	[SRDataManager sharedManager].selectedStationList = SRStationListAll;
	[[self radioController] presentAddRadioController];
}

- (void)showStationList:(UICommand *)sender {
	[SRDataManager sharedManager].selectedStationList = [sender.propertyList integerValue];
}

- (void)togglePlayback:(id)sender {
	[[SRPlaybackManager sharedManager] togglePlayPause];
}

- (void)playNextStation:(id)sender {
	[[SRPlaybackManager sharedManager] playNextStation];
}

- (void)playPreviousStation:(id)sender {
	[[SRPlaybackManager sharedManager] playPreviousStation];
}

- (void)toggleFavorite:(id)sender {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	SRRadioStation *station = dataManager.selectedRadioStation;
	if ([dataManager isFavoriteRadioStation:station]) {
		[dataManager removeFavoriteRadioStation:station];
	} else {
		[dataManager addFavoriteRadioStation:station];
	}
}

- (void)toggleSleepTimer:(id)sender {
	SRPlaybackManager *playbackManager = [SRPlaybackManager sharedManager];
	if (playbackManager.sleepTimerActive) {
		[playbackManager cancelSleepTimer];
	} else {
		[playbackManager playRadioStation:[SRDataManager sharedManager].selectedRadioStation withSleepTimer:YES];
	}
}

- (void)sendFeedback:(id)sender {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"mailto:sloradio@jernej.org?subject=SloRadio"] options:@{} completionHandler:nil];
}

#pragma mark - Scenes


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
	if (connectingSceneSession.role == CPTemplateApplicationSceneSessionRoleApplication) {
		return [UISceneConfiguration configurationWithName:@"CarPlay" sessionRole:connectingSceneSession.role];
	} else {
		return [UISceneConfiguration configurationWithName:@"AppConfiguration" sessionRole:connectingSceneSession.role];
	}
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
	
}

@end
