//
//  SRAppDelegate.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAppDelegate.h"
#import "SRMainViewController.h"
#import "Firebase.h"
#import <CarPlay/CarPlay.h>

@interface SRAppDelegate ()

@end

@implementation SRAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	if (@available(iOS 13, *)) {
		self.mainController = [[SRMainViewController alloc] init];
	} else {
		self.mainController = [[SRMainViewController alloc] init];
		self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
		self.window.tintColor = [SRAppearance mainColor];
		self.window.rootViewController = self.mainController;
		[self.window makeKeyAndVisible];
	}
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

#pragma mark - Scenes


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)) {
	if (connectingSceneSession.role == CPTemplateApplicationSceneSessionRoleApplication) {
		UIView *view = self.mainController.view;
		[view layoutIfNeeded];
		return [UISceneConfiguration configurationWithName:@"CarPlay" sessionRole:connectingSceneSession.role];
	} else {
		return [UISceneConfiguration configurationWithName:@"AppConfiguration" sessionRole:connectingSceneSession.role];
	}
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions API_AVAILABLE(ios(13.0)) {
	
}

@end
