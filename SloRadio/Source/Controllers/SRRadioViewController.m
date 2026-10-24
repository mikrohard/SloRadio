//
//  SRRadioViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioViewController.h"
#import "SRDataManager.h"
#import "SRPlaybackManager.h"
#import "SRRadioPlayer.h"
#import "SRRadioStation.h"
#import "SRAddRadioViewController.h"
#import "SRSettingsViewController.h"
#import "SRAboutViewController.h"
#import "SRFavoritesPickerViewController.h"
#import "SRStationTableViewCell.h"
#import "MBProgressHUD.h"
#import "Reachability.h"

static NSTimeInterval const SRRadioStationsUpdateInterval = 60*60; // 1 hour

@interface SRRadioViewController () <UITableViewDataSource, UITableViewDelegate> {
	NSTimeInterval _stationsLoadedTimestamp;
}

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *listControl;
@property (nonatomic, strong) NSLayoutConstraint *listControlSidebarHeight;
@property (nonatomic, strong) UIView *emptyFavoritesView;
@property (nonatomic, assign) BOOL ignoreFavoritesChange;
// UITableView reports editing == YES while a swipe action is shown, so track the edit mode separately
@property (nonatomic, assign) BOOL editingList;

@end

@implementation SRRadioViewController

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super init];
	if (self) {
		[self registerForNotifications];
		self.title = NSLocalizedString(@"RadioStations", @"Radio Stations");
	}
	return self;
}

- (void)loadView {
	[super loadView];
	[self setupTableView];
	[self setupListControl];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self loadRadioStations];
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	[self updateListControlHeight];
}

- (void)updateListControlHeight {
	// The floating sidebar of iPadOS 26 has a shorter navigation bar than the segmented control's default height
	// (fixed in iPadOS 27), so the control would touch the top edge of the sidebar.
	BOOL limitHeight = NO;
	if (@available(iOS 27, *)) {
		limitHeight = NO;
	} else if (@available(iOS 26, *)) {
		UISplitViewController *splitViewController = self.splitViewController;
		limitHeight = splitViewController != nil && !splitViewController.isCollapsed;
	}
	if (self.listControlSidebarHeight.active != limitHeight) {
		self.listControlSidebarHeight.active = limitHeight;
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updateNavigationButtons];
	[self updateEmptyState];
}

- (void)dealloc {
	[self unregisterFromNotifications];
}

#pragma mark - Setup

- (void)setupTableView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	tableView.allowsSelectionDuringEditing = YES;
	tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	tableView.dataSource = self;
	tableView.delegate = self;
	tableView.alwaysBounceVertical = YES;
	tableView.separatorInset = UIEdgeInsetsMake(0, [SRStationTableViewCell separatorInsetLeft], 0, 0);
	tableView.cellLayoutMarginsFollowReadableWidth = NO;
	[tableView registerClass:[SRStationTableViewCell class] forCellReuseIdentifier:@"RadioStationCell"];
	[self.view addSubview:tableView];
	self.tableView = tableView;
}

- (void)setupListControl {
	UISegmentedControl *listControl = [[UISegmentedControl alloc] initWithItems:@[NSLocalizedString(@"AllStations", @"All"),
																				  NSLocalizedString(@"Favorites", @"Favorites")]];
	listControl.selectedSegmentIndex = [SRDataManager sharedManager].selectedStationList;
	[listControl addTarget:self action:@selector(listControlChanged:) forControlEvents:UIControlEventValueChanged];
	[listControl setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
	[listControl.widthAnchor constraintGreaterThanOrEqualToConstant:200.f].active = YES;
	self.listControlSidebarHeight = [listControl.heightAnchor constraintEqualToConstant:32.f];
	self.navigationItem.titleView = listControl;
	self.listControl = listControl;
}

#pragma mark - Navigation items

- (void)updateNavigationButtons {
	BOOL editing = self.editingList;
	BOOL allStations = [self currentList] == SRStationListAll;
	if (editing) {
		UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
																				  target:self
																				  action:@selector(doneButtonPressed:)];
		self.navigationItem.rightBarButtonItem = doneItem;
		if (allStations) {
			UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
																					 target:self
																					 action:@selector(addButtonPressed:)];
			self.navigationItem.leftBarButtonItem = addItem;
		} else {
			self.navigationItem.leftBarButtonItem = nil;
		}
	}
	else {
		NSString *imageName = @"ellipsis.circle";
		if (@available(iOS 26, *)) {
			imageName = @"ellipsis";
		}
		UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:imageName]
																	  menu:[self moreMenu]];
		moreItem.accessibilityLabel = NSLocalizedString(@"More", @"More");
		self.navigationItem.rightBarButtonItem = moreItem;
		if (allStations) {
			self.navigationItem.leftBarButtonItem = nil;
		} else {
			UIBarButtonItem *addFavoritesItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
																							  target:self
																							  action:@selector(addFavoritesButtonPressed:)];
			addFavoritesItem.accessibilityLabel = NSLocalizedString(@"AddFavorites", @"Add favorites");
			self.navigationItem.leftBarButtonItem = addFavoritesItem;
		}
	}
	self.listControl.enabled = !editing;
}

- (UIMenu *)moreMenu {
	__weak SRRadioViewController *weakSelf = self;
	NSMutableArray *listActions = [NSMutableArray array];
	NSString *editTitle = [self currentList] == SRStationListFavorites ? NSLocalizedString(@"EditFavorites", @"Edit favorites") : NSLocalizedString(@"EditList", @"Edit list");
	[listActions addObject:[UIAction actionWithTitle:editTitle
											   image:[UIImage systemImageNamed:@"pencil"]
										  identifier:nil
											 handler:^(__kindof UIAction *action) {
		[weakSelf editButtonPressed:nil];
	}]];
	if ([self currentList] == SRStationListAll) {
		[listActions addObject:[UIAction actionWithTitle:NSLocalizedString(@"AddStation", @"Add station")
												   image:[UIImage systemImageNamed:@"plus"]
											  identifier:nil
												 handler:^(__kindof UIAction *action) {
			[weakSelf presentAddRadioController];
		}]];
	}
	UIMenu *listMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:listActions];
	UIAction *settingsAction = [UIAction actionWithTitle:NSLocalizedString(@"Settings", @"Settings")
												   image:[UIImage systemImageNamed:@"gearshape"]
											  identifier:nil
												 handler:^(__kindof UIAction *action) {
		[weakSelf presentSheetWithController:[[SRSettingsViewController alloc] init]];
	}];
	UIAction *aboutAction = [UIAction actionWithTitle:NSLocalizedString(@"About", @"About")
												image:[UIImage systemImageNamed:@"info.circle"]
										   identifier:nil
											  handler:^(__kindof UIAction *action) {
		[weakSelf presentSheetWithController:[[SRAboutViewController alloc] init]];
	}];
	UIMenu *appMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[settingsAction, aboutAction]];
	return [UIMenu menuWithChildren:@[listMenu, appMenu]];
}

#pragma mark - Notifications

- (void)registerForNotifications {
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(stationsLoaded:) name:SRDataManagerDidLoadStations object:nil];
	[nc addObserver:self selector:@selector(stationsChanged:) name:SRDataManagerDidChangeStations object:nil];
	[nc addObserver:self selector:@selector(sleepTimerSettingsChanged:) name:SRDataManagerDidChangeSleepTimerSettings object:nil];
	[nc addObserver:self selector:@selector(selectedStationChanged:) name:SRDataManagerDidSelectStation object:nil];
	[nc addObserver:self selector:@selector(favoritesChanged:) name:SRDataManagerDidChangeFavorites object:nil];
	[nc addObserver:self selector:@selector(stationListChanged:) name:SRDataManagerDidChangeStationList object:nil];
	[nc addObserver:self selector:@selector(playbackFailed:) name:SRPlaybackManagerDidFailPlayback object:nil];
	[nc addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)unregisterFromNotifications {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stationsLoaded:(NSNotification *)notification {
	[self reloadData];
}

- (void)stationsChanged:(NSNotification *)notification {
	[self reloadData];
}

- (void)sleepTimerSettingsChanged:(NSNotification *)notification {
	[self.tableView reloadData];
}

- (void)selectedStationChanged:(NSNotification *)notification {
	[self reconfigureVisibleRows];
}

- (void)favoritesChanged:(NSNotification *)notification {
	if (self.ignoreFavoritesChange) {
		return;
	}
	if ([self currentList] == SRStationListFavorites) {
		[self reloadData];
	}
}

- (void)stationListChanged:(NSNotification *)notification {
	SRStationList list = [SRDataManager sharedManager].selectedStationList;
	if (self.listControl.selectedSegmentIndex != list) {
		if (self.editingList) {
			[self doneButtonPressed:nil];
		}
		self.listControl.selectedSegmentIndex = list;
		[self updateNavigationButtons];
		[self reloadData];
	}
}

- (void)playbackFailed:(NSNotification *)notification {
	SRRadioStation *station = notification.object;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self handlePlaybackErrorForStation:station];
	});
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	[self updateRadioStations];
}

#pragma mark - Network

- (void)loadRadioStations {
	_stationsLoadedTimestamp = [[NSDate date] timeIntervalSince1970];
	if ([SRDataManager sharedManager].stations.count == 0) {
		[MBProgressHUD showHUDAddedTo:self.view animated:YES];
	}
	__weak SRRadioViewController *weakSelf = self;
	[[SRDataManager sharedManager] loadStationsWithCompletionHandler:^(NSError *error) {
		[MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
		if (error && [SRDataManager sharedManager].stations.count == 0) {
			// could not load radio stations
			[weakSelf handleStationsLoadError];
		}
	}];
}

- (void)updateRadioStations {
	// update radio stations if last load is more than one hour ago
	if ([[NSDate date] timeIntervalSince1970] - _stationsLoadedTimestamp > SRRadioStationsUpdateInterval) {
		[self loadRadioStations];
	}
}

#pragma mark - Stations

- (SRStationList)currentList {
	return self.listControl.selectedSegmentIndex == SRStationListFavorites ? SRStationListFavorites : SRStationListAll;
}

- (NSArray *)stations {
	return [[SRDataManager sharedManager] stationsForList:[self currentList]];
}

- (void)reloadData {
	[self.tableView reloadData];
	[self updateEmptyState];
}

- (void)reconfigureVisibleRows {
	NSArray *indexPaths = [self.tableView indexPathsForVisibleRows];
	NSInteger count = [self stations].count;
	for (NSIndexPath *indexPath in indexPaths) {
		if (indexPath.row >= count) {
			// data is out of sync with the table view
			[self reloadData];
			return;
		}
	}
	if (indexPaths.count > 0) {
		[self.tableView reconfigureRowsAtIndexPaths:indexPaths];
	}
}

- (NSIndexPath *)indexPathForStation:(SRRadioStation *)station {
	NSArray *stations = [self stations];
	for (NSInteger i = 0; i < stations.count; i++) {
		if ([stations[i] stationId] == station.stationId) {
			return [NSIndexPath indexPathForRow:i inSection:0];
		}
	}
	return nil;
}

- (void)scrollToSelectedStationAnimated:(BOOL)animated {
	NSIndexPath *indexPath = [self indexPathForStation:[SRDataManager sharedManager].selectedRadioStation];
	if (indexPath) {
		[self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:animated];
	}
}

- (void)toggleFavoriteForStation:(SRRadioStation *)station {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	if (![dataManager isFavoriteRadioStation:station]) {
		[dataManager addFavoriteRadioStation:station];
		return;
	}
	NSIndexPath *indexPath = [self indexPathForStation:station];
	if ([self currentList] == SRStationListFavorites && indexPath) {
		self.ignoreFavoritesChange = YES;
		[dataManager removeFavoriteRadioStation:station];
		self.ignoreFavoritesChange = NO;
		[self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
		[self updateEmptyState];
	} else {
		[dataManager removeFavoriteRadioStation:station];
	}
}

#pragma mark - Empty state

- (void)updateEmptyState {
	BOOL showEmptyState = [self currentList] == SRStationListFavorites && [self stations].count == 0;
	if (showEmptyState && !self.emptyFavoritesView) {
		self.emptyFavoritesView = [self createEmptyFavoritesView];
	}
	self.tableView.backgroundView = showEmptyState ? self.emptyFavoritesView : nil;
}

- (UIView *)createEmptyFavoritesView {
	UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star"
																		withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44.f weight:UIImageSymbolWeightRegular]]];
	imageView.tintColor = [UIColor tertiaryLabelColor];
	imageView.contentMode = UIViewContentModeCenter;

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.text = NSLocalizedString(@"NoFavorites", @"No favorites");
	titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
	titleLabel.adjustsFontForContentSizeCategory = YES;
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.numberOfLines = 0;

	UILabel *messageLabel = [[UILabel alloc] init];
	messageLabel.text = NSLocalizedString(@"NoFavoritesMessage", @"How to add favorites");
	messageLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	messageLabel.adjustsFontForContentSizeCategory = YES;
	messageLabel.textColor = [UIColor secondaryLabelColor];
	messageLabel.textAlignment = NSTextAlignmentCenter;
	messageLabel.numberOfLines = 0;

	UIButtonConfiguration *buttonConfiguration = [UIButtonConfiguration filledButtonConfiguration];
	buttonConfiguration.title = NSLocalizedString(@"AddFavorites", @"Add favorites");
	buttonConfiguration.image = [UIImage systemImageNamed:@"plus"];
	buttonConfiguration.imagePadding = 6.f;
	buttonConfiguration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	buttonConfiguration.baseBackgroundColor = [SRAppearance mainColor];
	buttonConfiguration.baseForegroundColor = [UIColor whiteColor];
	buttonConfiguration.contentInsets = NSDirectionalEdgeInsetsMake(10.f, 18.f, 10.f, 18.f);
	UIButton *addButton = [UIButton buttonWithConfiguration:buttonConfiguration primaryAction:nil];
	[addButton addTarget:self action:@selector(addFavoritesButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
	
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[imageView, titleLabel, messageLabel, addButton]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 8.f;
	[stack setCustomSpacing:16.f afterView:imageView];
	[stack setCustomSpacing:24.f afterView:messageLabel];
	stack.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *container = [[UIView alloc] init];
	[container addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.centerXAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.centerXAnchor],
		[stack.centerYAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.centerYAnchor],
		[stack.widthAnchor constraintLessThanOrEqualToAnchor:container.safeAreaLayoutGuide.widthAnchor constant:-64.f],
		[stack.widthAnchor constraintLessThanOrEqualToConstant:320.f],
	]];
	return container;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [[self stations] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SRStationTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RadioStationCell" forIndexPath:indexPath];
	SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
	[cell configureWithStation:station];
	cell.checked = station.stationId == [SRDataManager sharedManager].selectedRadioStation.stationId;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	// deleting is only possible in edit mode, swiping shows the station actions instead
	return self.editingList ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
	SRRadioStation *station = [[self stations] objectAtIndex:sourceIndexPath.row];
	if ([self currentList] == SRStationListFavorites) {
		self.ignoreFavoritesChange = YES;
		[[SRDataManager sharedManager] moveFavoriteRadioStation:station atIndex:destinationIndexPath.row];
		self.ignoreFavoritesChange = NO;
	} else {
		[[SRDataManager sharedManager] moveRadioStation:station atIndex:destinationIndexPath.row];
	}
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		@synchronized(self) {
			SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
			if ([self currentList] == SRStationListFavorites) {
				[self toggleFavoriteForStation:station];
				return;
			}
			self.ignoreFavoritesChange = YES;
			[[SRDataManager sharedManager] deleteRadioStation:station];
			self.ignoreFavoritesChange = NO;
			[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
			if (station.stationId == [[SRRadioPlayer sharedPlayer] currentRadioStation].stationId) {
				// deleted station currently playing... stop it
				[[SRPlaybackManager sharedManager] stop];
			}
		}
	}
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
	if (self.editingList) {
		[self presentEditRadioControllerForStation:station];
	}
	else {
		[[SRDataManager sharedManager] selectRadioStation:station];
		if ([[SRRadioPlayer sharedPlayer] currentRadioStation] != nil) {
			[[SRPlaybackManager sharedManager] play];
		}
	}
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self currentList] == SRStationListFavorites) {
		return NSLocalizedString(@"Remove", @"Remove");
	}
	return NSLocalizedString(@"Delete", nil);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.editingList) {
		return nil;
	}
	SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
	__weak SRRadioViewController *weakSelf = self;
	BOOL sleepTimerByDefault = [SRDataManager sharedManager].sleepTimerEnabledByDefault;
	UIContextualAction *playAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
																			 title:sleepTimerByDefault ? NSLocalizedString(@"Play", @"Play") : NSLocalizedString(@"SleepTimer", @"Sleep timer")
																		   handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
		completionHandler(YES);
		[weakSelf performAfterSwipe:^{
			[[SRPlaybackManager sharedManager] playRadioStation:station withSleepTimer:!sleepTimerByDefault];
		}];
	}];
	playAction.image = [UIImage systemImageNamed:sleepTimerByDefault ? @"play.fill" : @"moon.zzz.fill"];
	playAction.backgroundColor = [UIColor systemIndigoColor];
	UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[playAction]];
	configuration.performsFirstActionWithFullSwipe = YES;
	return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.editingList) {
		// default delete action
		return nil;
	}
	SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
	__weak SRRadioViewController *weakSelf = self;
	NSMutableArray *actions = [NSMutableArray array];

	BOOL favorite = [[SRDataManager sharedManager] isFavoriteRadioStation:station];
	UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
																				 title:favorite ? NSLocalizedString(@"Unfavorite", @"Unfavorite") : NSLocalizedString(@"Favorite", @"Favorite")
																			   handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
		completionHandler(YES);
		[weakSelf performAfterSwipe:^{
			[weakSelf toggleFavoriteForStation:station];
		}];
	}];
	favoriteAction.image = [UIImage systemImageNamed:favorite ? @"star.slash.fill" : @"star.fill"];
	favoriteAction.backgroundColor = favorite ? [UIColor systemGrayColor] : [UIColor systemOrangeColor];
	[actions addObject:favoriteAction];

	UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:actions];
	configuration.performsFirstActionWithFullSwipe = YES;
	return configuration;
}

- (void)performAfterSwipe:(dispatch_block_t)block {
	// let the swipe actions close before the rows are updated, otherwise the row stays highlighted
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		block();
		for (UITableViewCell *cell in self.tableView.visibleCells) {
			[cell setHighlighted:NO animated:YES];
		}
	});
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
	if (self.editingList) {
		return nil;
	}
	SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
	__weak SRRadioViewController *weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
		UIAction *playAction = [UIAction actionWithTitle:NSLocalizedString(@"Play", @"Play")
												   image:[UIImage systemImageNamed:@"play.fill"]
											  identifier:nil
												 handler:^(__kindof UIAction *action) {
			[[SRPlaybackManager sharedManager] playRadioStation:station withSleepTimer:NO];
		}];
		UIAction *sleepTimerAction = [UIAction actionWithTitle:NSLocalizedString(@"PlayWithSleepTimer", @"Play with sleep timer")
														 image:[UIImage systemImageNamed:@"moon.zzz.fill"]
													identifier:nil
													   handler:^(__kindof UIAction *action) {
			[[SRPlaybackManager sharedManager] playRadioStation:station withSleepTimer:YES];
		}];
		UIMenu *playMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[playAction, sleepTimerAction]];

		BOOL favorite = [[SRDataManager sharedManager] isFavoriteRadioStation:station];
		UIAction *favoriteAction = [UIAction actionWithTitle:favorite ? NSLocalizedString(@"RemoveFromFavorites", nil) : NSLocalizedString(@"AddToFavorites", nil)
													   image:[UIImage systemImageNamed:favorite ? @"star.slash" : @"star"]
												  identifier:nil
													 handler:^(__kindof UIAction *action) {
			[weakSelf toggleFavoriteForStation:station];
		}];
		NSMutableArray *otherActions = [NSMutableArray arrayWithObject:favoriteAction];
		if ([[SRDataManager sharedManager] isCustomRadioStation:station]) {
			[otherActions addObject:[UIAction actionWithTitle:NSLocalizedString(@"EditStation", @"Edit station")
														image:[UIImage systemImageNamed:@"pencil"]
												   identifier:nil
													  handler:^(__kindof UIAction *action) {
				[weakSelf presentEditRadioControllerForStation:station];
			}]];
		}
		UIMenu *otherMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:otherActions];
		return [UIMenu menuWithTitle:station.name children:@[playMenu, otherMenu]];
	}];
}

#pragma mark - Button actions

- (void)listControlChanged:(UISegmentedControl *)sender {
	[SRDataManager sharedManager].selectedStationList = [self currentList];
	[self updateNavigationButtons];
	[self reloadData];
	[self.tableView setContentOffset:CGPointMake(0, -self.tableView.adjustedContentInset.top) animated:NO];
}

- (void)editButtonPressed:(id)sender {
	self.editingList = YES;
	[self.tableView setEditing:NO animated:NO];
	[self.tableView setEditing:YES animated:YES];
	[self updateNavigationButtons];
}

- (void)doneButtonPressed:(id)sender {
	self.editingList = NO;
	if (self.tableView.editing) {
		[self.tableView setEditing:NO animated:YES];
	}
	[self updateNavigationButtons];
	// stations order or favorites may have changed while editing
	[[NSNotificationCenter defaultCenter] postNotificationName:SRDataManagerDidChangeStations object:[SRDataManager sharedManager]];
}

- (void)addButtonPressed:(id)sender {
	[self presentAddRadioController];
}

- (void)addFavoritesButtonPressed:(id)sender {
	SRFavoritesPickerViewController *controller = [[SRFavoritesPickerViewController alloc] init];
	UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
	navigation.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigation animated:YES completion:NULL];
}

#pragma mark - Presentation

- (void)presentAddRadioController {
	SRAddRadioViewController *controller = [[SRAddRadioViewController alloc] initEmpty];
	UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
	navigation.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigation animated:YES completion:NULL];
}

- (void)presentEditRadioControllerForStation:(SRRadioStation *)station {
	SRAddRadioViewController *controller = [[SRAddRadioViewController alloc] initWithRadioStation:station];
	UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
	navigation.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigation animated:YES completion:NULL];
}

- (void)presentSheetWithController:(UIViewController *)controller {
	controller.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
																								  target:self
																								  action:@selector(dismissSheet:)];
	UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
	navigation.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigation animated:YES completion:NULL];
}

- (void)dismissSheet:(id)sender {
	[self dismissViewControllerAnimated:YES completion:NULL];
}

#pragma mark - Error handling

- (void)handleStationsLoadError {
	__weak SRRadioViewController *weakSelf = self;
	UIAlertController *controller = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Oops", @"Oops!")
																		message:NSLocalizedString(@"StationsLoadFailed", @"Error message")
																 preferredStyle:UIAlertControllerStyleAlert];
	[controller addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Retry", @"Retry")
													style:UIAlertActionStyleCancel
												  handler:^(UIAlertAction * _Nonnull action) {
		[weakSelf loadRadioStations];
	}]];
	[self presentOnTop:controller];
}

- (void)handlePlaybackErrorForStation:(SRRadioStation *)station {
	if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
		return;
	}
	NSString *message = nil;
	if ([self isInternetReachable]) {
		message = [NSString stringWithFormat:NSLocalizedString(@"PlaybackErrorStation", @""), station.name];
	}
	else {
		message = [NSString stringWithFormat:NSLocalizedString(@"PlaybackErrorInternet", @""), station.name];
	}
	UIAlertController *controller = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Oops", @"Oops!")
																		message:message
																 preferredStyle:UIAlertControllerStyleAlert];
	[controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Ok")
												   style:UIAlertActionStyleCancel
												 handler:nil]];
	[self presentOnTop:controller];
}

- (void)presentOnTop:(UIViewController *)controller {
	// present on top of any sheet that might be visible
	UIViewController *presenter = self;
	while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
		presenter = presenter.presentedViewController;
	}
	[presenter presentViewController:controller animated:YES completion:nil];
}

#pragma mark - Utils

- (BOOL)isInternetReachable {
	return [[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable;
}

@end
