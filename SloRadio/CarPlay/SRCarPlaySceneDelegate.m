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
#import "SRPlaybackManager.h"
#import <CarPlay/CarPlay.h>
#import <MediaPlayer/MediaPlayer.h>

static CGFloat const SRCarPlayArtworkWidth = 256;

@interface SRCarPlaySceneDelegate () <CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate, CPTabBarTemplateDelegate>

@property (nonatomic, strong) CPInterfaceController *interfaceController;
@property (nonatomic, strong) CPNowPlayingTemplate *nowPlayingTemplate;
@property (nonatomic, strong) CPTabBarTemplate *tabBarTemplate;
@property (nonatomic, strong) CPListTemplate *stationsTemplate;
@property (nonatomic, strong) CPListTemplate *favoritesTemplate;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL nowPlayingTemplateIsBeingPresented;
@property (nonatomic, strong) dispatch_block_t handlerCompletion;

@end

@implementation SRCarPlaySceneDelegate

#pragma mark - Scene delegate

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didConnectInterfaceController:(CPInterfaceController *)interfaceController {
	self.interfaceController = interfaceController;
	self.interfaceController.delegate = self;
	[self setRootTemplate];
	[self registerForNotifications];
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
	[nc addObserver:self selector:@selector(stationsChanged:) name:SRDataManagerDidLoadStations object:nil];
	[nc addObserver:self selector:@selector(stationsChanged:) name:SRDataManagerDidChangeStations object:nil];
	[nc addObserver:self selector:@selector(stationsChanged:) name:SRDataManagerDidChangeFavorites object:nil];
	[nc addObserver:self selector:@selector(selectedStationChanged:) name:SRDataManagerDidSelectStation object:nil];
	[nc addObserver:self selector:@selector(stationListChanged:) name:SRDataManagerDidChangeStationList object:nil];
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

- (void)stationsChanged:(NSNotification *)notification {
	[self reloadStationTemplates];
	[self updateNowPlayingButtons];
}

- (void)selectedStationChanged:(NSNotification *)notification {
	[self updateNowPlayingButtons];
}

- (void)stationListChanged:(NSNotification *)notification {
	[self selectCurrentStationList];
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

#pragma mark - Tab bar template delegate

- (void)tabBarTemplate:(CPTabBarTemplate *)tabBarTemplate didSelectTemplate:(__kindof CPTemplate *)selectedTemplate {
	// remember the last used list (it is also used as the playback queue)
	SRStationList list = selectedTemplate == self.favoritesTemplate ? SRStationListFavorites : SRStationListAll;
	[SRDataManager sharedManager].selectedStationList = list;
}

#pragma mark - Templates

- (void)setRootTemplate {
	self.stationsTemplate = [[CPListTemplate alloc] initWithTitle:NSLocalizedString(@"RadioStations", @"Radio Stations")
														 sections:@[]];
	self.stationsTemplate.tabTitle = NSLocalizedString(@"AllStations", @"All");
	self.stationsTemplate.tabImage = [UIImage systemImageNamed:@"dot.radiowaves.left.and.right"];
	self.stationsTemplate.emptyViewTitleVariants = @[NSLocalizedString(@"Loading", @"Loading")];

	self.favoritesTemplate = [[CPListTemplate alloc] initWithTitle:NSLocalizedString(@"Favorites", @"Favorites")
														  sections:@[]];
	self.favoritesTemplate.tabTitle = NSLocalizedString(@"Favorites", @"Favorites");
	self.favoritesTemplate.tabImage = [UIImage systemImageNamed:@"star.fill"];
	self.favoritesTemplate.emptyViewTitleVariants = @[NSLocalizedString(@"NoFavorites", @"No favorites")];
	self.favoritesTemplate.emptyViewSubtitleVariants = @[NSLocalizedString(@"NoFavoritesCarPlayMessage", @"How to add favorites")];

	self.tabBarTemplate = [[CPTabBarTemplate alloc] initWithTemplates:@[self.stationsTemplate, self.favoritesTemplate]];
	self.tabBarTemplate.delegate = self;
	[self.interfaceController setRootTemplate:self.tabBarTemplate animated:NO completion:nil];
	[self selectCurrentStationList];
	[self setupNowPlayingTemplate];

	if ([SRDataManager sharedManager].stations.count > 0) {
		[self reloadStationTemplates];
	} else {
		__weak SRCarPlaySceneDelegate *weakSelf = self;
		[[SRDataManager sharedManager] loadStationsWithCompletionHandler:^(NSError *error) {
			__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
			if (strongSelf != nil) {
				if (error) {
					[strongSelf handleStationsLoadError:error];
				} else {
					[strongSelf reloadStationTemplates];
				}
			}
		}];
	}
}

- (void)selectCurrentStationList {
	if (@available(iOS 17, *)) {
		CPListTemplate *template = [SRDataManager sharedManager].selectedStationList == SRStationListFavorites ? self.favoritesTemplate : self.stationsTemplate;
		if (self.tabBarTemplate.selectedTemplate != template) {
			[self.tabBarTemplate selectTemplate:template];
		}
	}
}

- (void)reloadStationTemplates {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	[self.stationsTemplate updateSections:@[[self sectionForStations:dataManager.stations list:SRStationListAll]]];
	[self.favoritesTemplate updateSections:@[[self sectionForStations:dataManager.favoriteStations list:SRStationListFavorites]]];
}

- (CPListSection *)sectionForStations:(NSArray *)stations list:(SRStationList)list {
	NSMutableArray *stationItems = [[NSMutableArray alloc] init];
	for (SRRadioStation *station in stations) {
		CPListItem *item = [[CPListItem alloc] initWithText:[station name] detailText:nil];
		item.image = [station cachedArtworkImageForWidth:SRCarPlayArtworkWidth] ?: [UIImage imageNamed:@"PlaceholderArtwork"];
		item.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
		item.playing = [self isStationPlaying:station];
		item.userInfo = station;
		__weak SRCarPlaySceneDelegate *weakSelf = self;
		item.handler = ^(id <CPSelectableListItem> item, dispatch_block_t completionBlock) {
			__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
			if (strongSelf != nil) {
				SRRadioStation *station = item.userInfo;
				[SRDataManager sharedManager].selectedStationList = list;
				[[SRPlaybackManager sharedManager] playRadioStation:station];
				if (strongSelf.handlerCompletion != NULL) {
					strongSelf.handlerCompletion();
				}
				strongSelf.handlerCompletion = completionBlock;
			}
		};
		if ([station cachedArtworkImageForWidth:SRCarPlayArtworkWidth] == nil) {
			[station loadArtworkImageForWidth:SRCarPlayArtworkWidth completion:^(UIImage *image) {
				if (image) {
					[item setImage:image];
				}
			}];
		}
		[stationItems addObject:item];
	}
	return [[CPListSection alloc] initWithItems:stationItems];
}

- (BOOL)isStationPlaying:(SRRadioStation *)station {
	SRRadioPlayer *player = [SRRadioPlayer sharedPlayer];
	if ([player currentRadioStation].stationId == station.stationId &&
		([player state] == SRRadioPlayerStateBuffering ||
		 [player state] == SRRadioPlayerStatePlaying)) {
		// this radio station is playing
		return YES;
	}
	return NO;
}

#pragma mark - Now playing info

- (void)setupNowPlayingTemplate {
	self.nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
	[self updateNowPlayingButtons];
}

- (void)updateNowPlayingButtons {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	SRRadioStation *station = dataManager.selectedRadioStation;
	if (station == nil || self.nowPlayingTemplate == nil) {
		return;
	}
	BOOL favorite = [dataManager isFavoriteRadioStation:station];
	UIImage *image = [UIImage systemImageNamed:favorite ? @"star.fill" : @"star"];
	CPNowPlayingImageButton *favoriteButton = [[CPNowPlayingImageButton alloc] initWithImage:image handler:^(__kindof CPNowPlayingButton *button) {
		SRDataManager *dataManager = [SRDataManager sharedManager];
		SRRadioStation *station = dataManager.selectedRadioStation;
		if ([dataManager isFavoriteRadioStation:station]) {
			[dataManager removeFavoriteRadioStation:station];
		} else {
			[dataManager addFavoriteRadioStation:station];
		}
	}];
	[self.nowPlayingTemplate updateNowPlayingButtons:@[favoriteButton]];
}

- (void)presentNowPlayingTemplate {
	if (!self.nowPlayingTemplate) {
		self.nowPlayingTemplate = [CPNowPlayingTemplate sharedTemplate];
	}
	if (self.interfaceController.topTemplate != self.nowPlayingTemplate && !self.nowPlayingTemplateIsBeingPresented) {
		[self.interfaceController pushTemplate:self.nowPlayingTemplate animated:YES completion:nil];
	}
}

- (void)updateNowPlayingStationIndicator {
	for (CPListTemplate *template in @[self.stationsTemplate, self.favoritesTemplate]) {
		for (CPListItem *item in template.sections.firstObject.items) {
			SRRadioStation *station = [item userInfo];
			item.playing = [self isStationPlaying:station];
		}
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
			[strongSelf.interfaceController dismissTemplateAnimated:YES completion:nil];
			[strongSelf setRootTemplate];
		}
	}]];

	CPAlertTemplate *alert = [[CPAlertTemplate alloc] initWithTitleVariants:@[NSLocalizedString(@"StationsLoadFailed", @"Error message")]
																	actions:actions];
	[self presentAlertTemplate:alert];
}

- (void)handlePlaybackErrorForStation:(SRRadioStation *)station {
	NSMutableArray *actions = [[NSMutableArray alloc] init];
	__weak SRCarPlaySceneDelegate *weakSelf = self;
	[actions addObject:[[CPAlertAction alloc] initWithTitle:NSLocalizedString(@"Retry", @"Retry")
													  style:CPAlertActionStyleDefault
													handler:^(CPAlertAction *action) {
		[[SRPlaybackManager sharedManager] playRadioStation:station];
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
	[self presentAlertTemplate:alert];
}

- (void)presentAlertTemplate:(CPAlertTemplate *)alert {
	__weak SRCarPlaySceneDelegate *weakSelf = self;
	if (self.interfaceController.presentedTemplate != nil) {
		[self.interfaceController dismissTemplateAnimated:NO
											   completion:^(BOOL success, NSError * _Nullable error) {
			__strong SRCarPlaySceneDelegate *strongSelf = weakSelf;
			if (strongSelf != nil) {
				[strongSelf.interfaceController presentTemplate:alert animated:YES completion:nil];
			}
		}];
	} else {
		[self.interfaceController presentTemplate:alert animated:YES completion:nil];
	}
}

- (void)dismissError {
	if (self.interfaceController.presentedTemplate != nil) {
		[self.interfaceController dismissTemplateAnimated:YES completion:nil];
	}
}

@end
