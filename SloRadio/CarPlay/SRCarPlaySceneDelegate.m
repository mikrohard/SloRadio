//
//  SRCarPlaySceneDelegate.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 9. 24.
//  Copyright © 2024 Jernej Fijačko. All rights reserved.
//

#import "SRCarPlaySceneDelegate.h"
#import "SRDataManager.h"
#import "SRRadioStation.h"
#import "SRRadioPlayer.h"
#import "SRImageCache.h"
#import "SRRadioViewController.h"
#import <CarPlay/CarPlay.h>
#import <MediaPlayer/MediaPlayer.h>

static CGFloat const SRCarPlayArtworkWidth = 256;

@interface SRCarPlaySceneDelegate () <CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate>

@property (nonatomic, strong) CPInterfaceController *interfaceController;
@property (nonatomic, strong) CPNowPlayingTemplate *nowPlayingTemplate;
@property (nonatomic, strong) CPListTemplate *listTemplate;
@property (nonatomic, strong) dispatch_queue_t imageLoadQueue;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL nowPlayingTemplateIsBeingPresented;
@property (nonatomic, strong) dispatch_block_t handlerCompletion;
@property (nonatomic, strong) SRRadioViewController *radioController;

@end

@implementation SRCarPlaySceneDelegate

#pragma mark - Scene delegate

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didConnectInterfaceController:(CPInterfaceController *)interfaceController {
	self.interfaceController = interfaceController;
	self.interfaceController.delegate = self;
	[self setRootTemplate];
	[self registerForNotifications];
	self.radioController = (SRRadioViewController *)[[SRRadioPlayer sharedPlayer] delegate];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didDisconnectInterfaceController:(CPInterfaceController *)interfaceController {
	self.interfaceController = nil;
	[self unregisterFromNotifications];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
	self.isActive = YES;
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
	self.isActive = NO;
}

#pragma mark - Notifications

- (void)registerForNotifications {
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(playerStateDidChange:) name:SRRadioPlayerStateDidChangeNotification object:nil];
	[nc addObserver:self selector:@selector(playerMetaDataDidChange:) name:SRRadioPlayerMetaDataDidChangeNotification object:nil];
	[nc addObserver:self selector:@selector(stationsChanged:) name:SRDataManagerDidChangeStations object:nil];
}

- (void)unregisterFromNotifications {
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc removeObserver:self];
}

- (void)playerStateDidChange:(NSNotification *)notification {
	SRRadioPlayerState state = [[SRRadioPlayer sharedPlayer] state];
	BOOL handleCompletion = NO;
	if (state == SRRadioPlayerStateError && self.isActive) {
		[self handlePlaybackErrorForStation:[[SRDataManager sharedManager] selectedRadioStation]];
	}
	if (state == SRRadioPlayerStateError ||
		state == SRRadioPlayerStatePlaying ||
		state == SRRadioPlayerStateStopped) {
		handleCompletion = YES;
	}
	if (state == SRRadioPlayerStatePlaying) {
		[self dismissError];
	}
	if (state == SRRadioPlayerStatePlaying && self.handlerCompletion != NULL) {
		[self presentNowPlayingTemplate];
	}
	if (handleCompletion && self.handlerCompletion != NULL) {
		dispatch_block_t completion = self.handlerCompletion;
		self.handlerCompletion = NULL;
		completion();
	}
	[self updateNowPlayingStationIndicator];
}

- (void)playerMetaDataDidChange:(NSNotification *)notification {

}

- (void)stationsChanged:(NSNotification *)notification {
	[self showRadioStationsTemplate];
}

#pragma mark - Interface controller delegate

- (void)templateWillAppear:(CPTemplate *)aTemplate animated:(BOOL)animated {
	if (aTemplate == self.nowPlayingTemplate) {
		self.nowPlayingTemplateIsBeingPresented = YES;
	}
}

- (void)templateDidAppear:(CPTemplate *)aTemplate animated:(BOOL)animated {
	if (aTemplate == self.nowPlayingTemplate) {
		self.nowPlayingTemplateIsBeingPresented = NO;
	}
}

- (void)templateWillDisappear:(CPTemplate *)aTemplate animated:(BOOL)animated {
	
}

- (void)templateDidDisappear:(CPTemplate *)aTemplate animated:(BOOL)animated {
	
}

#pragma mark - Templates

- (void)setRootTemplate {
	self.listTemplate = [[CPListTemplate alloc] initWithTitle:nil
													 sections:@[]];
	self.listTemplate.emptyViewSubtitleVariants = @[NSLocalizedString(@"PleaseWait", @"Please wait")];
	self.listTemplate.emptyViewSubtitleVariants = @[NSLocalizedString(@"Loading", @"Loading")];
	[self.interfaceController setRootTemplate:self.listTemplate animated:NO];
	if ([SRDataManager sharedManager].stations.count > 0) {
		[self showRadioStationsTemplate];
	} else {
		__weak SRCarPlaySceneDelegate *weakSelf = self;
		[[SRDataManager sharedManager] loadStationsWithCompletionHandler:^(NSError *error) {
			__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
			if (strongSelf != nil) {
				if (error) {
					[strongSelf handleStationsLoadError:error];
				} else {
					[strongSelf showRadioStationsTemplate];
				}
			}
		}];
	}
}

- (void)showRadioStationsTemplate {
	if (!self.imageLoadQueue) {
		self.imageLoadQueue = dispatch_queue_create("org.jernej.sloradio.carPlayImageDownloader", NULL);
	}
	NSMutableArray *stationItems = [[NSMutableArray alloc] init];
	for (SRRadioStation *station in [[SRDataManager sharedManager] stations]) {
		CPListItem *item = [[CPListItem alloc] initWithText:[station name] detailText:nil];
		item.image = [UIImage imageNamed:@"PlaceholderArtwork"];
		item.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
		item.playing = [self isStationPlaying:station];
		item.userInfo = station;
		__weak SRCarPlaySceneDelegate *weakSelf = self;
		item.handler = ^(id <CPSelectableListItem> item, dispatch_block_t completionBlock) {
			__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
			if (strongSelf != nil) {
				SRRadioStation *station = item.userInfo;
				[strongSelf.radioController playRadioStation:station];
				if (strongSelf.handlerCompletion != NULL) {
					strongSelf.handlerCompletion();
				}
				strongSelf.handlerCompletion = completionBlock;
			}
		};
		NSURL *iconUrl = [station iconUrlForWidth:SRCarPlayArtworkWidth];
		if (iconUrl) {
			dispatch_async(self.imageLoadQueue, ^{
				NSString *cacheKey = [SRImageCache keyForUrl:iconUrl];
				UIImage *image = [[SRImageCache sharedCache] imageForKey:cacheKey];
				if (!image) {
					image = [UIImage imageWithData:[NSData dataWithContentsOfURL:iconUrl]];
					[[SRImageCache sharedCache] cacheImage:image forKey:cacheKey];
				}
				item.image = image;
			});
		}
		[stationItems addObject:item];
	}
	CPListSection *section = [[CPListSection alloc] initWithItems:stationItems];
	
	self.listTemplate = [[CPListTemplate alloc] initWithTitle:NSLocalizedString(@"RadioStations", @"Radio Stations")
													 sections:@[section]];
	[self.interfaceController setRootTemplate:self.listTemplate animated:YES];
}

- (BOOL)isStationPlaying:(SRRadioStation *)station {
	SRRadioPlayer *player = [SRRadioPlayer sharedPlayer];
	if ([[player currentRadioStation] isEqual:station] &&
		([player state] == SRRadioPlayerStateBuffering ||
		 [player state] == SRRadioPlayerStatePlaying)) {
		// this radio station is playing
		return YES;
	}
	return NO;
}

#pragma mark - Now playing info

- (void)presentNowPlayingTemplate {
	if (!self.nowPlayingTemplate) {
		self.nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
	}
	if (self.interfaceController.topTemplate != self.nowPlayingTemplate && !self.nowPlayingTemplateIsBeingPresented) {
		[self.interfaceController pushTemplate:self.nowPlayingTemplate animated:YES];
	}
}

- (void)updateNowPlayingStationIndicator {
	for (CPListItem *item in self.listTemplate.sections.firstObject.items) {
		SRRadioStation *station = [item userInfo];
		item.playing = [self isStationPlaying:station];
	}
}

#pragma mark - Error handling

- (void)handleStationsLoadError:(NSError *)error {
	NSMutableArray *actions = [[NSMutableArray alloc] init];
	__weak SRCarPlaySceneDelegate *weakSelf = self;
	[actions addObject:[[CPAlertAction alloc] initWithTitle:NSLocalizedString(@"Retry", @"Retry")
													  style:CPAlertActionStyleDefault
													handler:^(CPAlertAction *action) {
		__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
		if (strongSelf != nil) {
			[strongSelf setRootTemplate];
		}
	}]];
	
	CPAlertTemplate *alert = [[CPAlertTemplate alloc] initWithTitleVariants:@[NSLocalizedString(@"StationsLoadFailed", @"Error message")]
																	actions:actions];
	
	if (self.interfaceController.presentedTemplate != nil) {
		[self.interfaceController dismissTemplateAnimated:NO
											   completion:^(BOOL success, NSError * _Nullable error) {
			__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
			if (strongSelf != nil) {
				[strongSelf.interfaceController presentTemplate:alert animated:YES];
			}
		}];
	} else {
		[self.interfaceController presentTemplate:alert animated:YES];
	}
}

- (void)handlePlaybackErrorForStation:(SRRadioStation *)station {
	NSMutableArray *actions = [[NSMutableArray alloc] init];
	__weak SRCarPlaySceneDelegate *weakSelf = self;
	[actions addObject:[[CPAlertAction alloc] initWithTitle:NSLocalizedString(@"Retry", @"Retry")
													  style:CPAlertActionStyleDefault
													handler:^(CPAlertAction *action) {
		__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
		if (strongSelf != nil) {
			[strongSelf.radioController playRadioStation:station];
		}
	}]];
	[actions addObject:[[CPAlertAction alloc] initWithTitle:NSLocalizedString(@"Ok", @"Ok")
													  style:CPAlertActionStyleCancel
													handler:^(CPAlertAction *action) {
		__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
		if (strongSelf != nil) {
			[strongSelf dismissError];
		}
	}]];
	
	NSString *message = [NSString stringWithFormat:NSLocalizedString(@"PlaybackErrorStation", @""), station.name];
	
	CPAlertTemplate *alert = [[CPAlertTemplate alloc] initWithTitleVariants:@[message]
																	actions:actions];
	
	if (self.interfaceController.presentedTemplate != nil) {
		[self.interfaceController dismissTemplateAnimated:NO
											   completion:^(BOOL success, NSError * _Nullable error) {
			__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
			if (strongSelf != nil) {
				[strongSelf.interfaceController presentTemplate:alert animated:YES];
			}
		}];
	} else {
		[self.interfaceController presentTemplate:alert animated:YES];
	}
}

- (void)dismissError {
	if (self.interfaceController.presentedTemplate != nil) {
		[self.interfaceController dismissTemplateAnimated:YES];
	}
}

@end
