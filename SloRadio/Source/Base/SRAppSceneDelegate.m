//
//  SRAppSceneDelegate.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 9. 24.
//  Copyright © 2024 Jernej Fijačko. All rights reserved.
//

#import "SRAppSceneDelegate.h"
#import "SRAppDelegate.h"

@implementation SRAppSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
	if ([scene isKindOfClass:[UIWindowScene class]]) {
		SRAppDelegate *appDelegate = (SRAppDelegate *)[[UIApplication sharedApplication] delegate];
		UIWindowScene *windowScene = (UIWindowScene *)scene;
		self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
		self.window.tintColor = [SRAppearance mainColor];
		self.window.rootViewController = appDelegate.mainController;
		[self.window makeKeyAndVisible];
	}
}

@end
