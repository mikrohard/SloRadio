//
//  SRRadioViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>

#import "SRRadioViewController.h"
#import "SRDataManager.h"
#import "SRRadioPlayer.h"
#import "SRRadioStation.h"
#import "SRSleepTimer.h"
#import "SRSleepTimerView.h"
#import "SRAddRadioViewController.h"
#import "MBProgressHUD.h"
#import "UIAlertView+Blocks.h"
#import "UITableView+Separators.h"
#import "SRNowPlayingView.h"
#import "SRRadioTableViewCell.h"
#import "UIImage+Color.h"
#import "Reachability.h"

@import AVFoundation;
@import MediaPlayer;
@import MessageUI;

static NSTimeInterval const SRRadioStationsUpdateInterval = 60*60; // 1 hour

@interface SRRadioViewController () <SRRadioPlayerDelegate, SRSleepTimerDelegate, SRSleepTimerViewDelegate, MFMailComposeViewControllerDelegate, UITableViewDataSource, UITableViewDelegate> {
	BOOL _playbackInterrupted;
	BOOL _audioSessionInterrupted;
	NSTimeInterval _stationsLoadedTimestamp;
}

@property (nonatomic, strong) SRNowPlayingView *nowPlayingTitleView;
@property (nonatomic, strong) SRSleepTimer *sleepTimer;
@property (nonatomic, strong) SRSleepTimerView *sleepTimerView;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) UITableView *tableView;

// call interruption handling
@property (nonatomic, strong) CTCallCenter *callCenter;
@property (nonatomic, assign) BOOL callInProgress;

// background task
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;

@end

@implementation SRRadioViewController

@synthesize nowPlayingTitleView = _nowPlayingTitleView;
@synthesize sleepTimer = _sleepTimer;
@synthesize sleepTimerView = _sleepTimerView;
@synthesize toolbar = _toolbar;
@synthesize tableView = _tableView;
@synthesize callInProgress = _callInProgress;
@synthesize bgTask = _bgTask;

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super init];
	if (self) {
		[self registerForNotifications];
		self.title = NSLocalizedString(@"RadioStations", @"Radio Stations");
		self.automaticallyAdjustsScrollViewInsets = NO;
	}
	return self;
}

- (void)loadView {
	[super loadView];
	[self setupTableView];
	[self setupToolbar];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self loadRadioStations];
	[[SRRadioPlayer sharedPlayer] setDelegate:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updateNavigationButtons];
	[self updateToolbarItems];
	[self setupAudioSession];
	[self startRemoteControlTracking];
	[self layoutViews];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopAction];
	[self endRemoteControlTracking];
	[self endAudioSession];
}

- (void)viewSafeAreaInsetsDidChange {
	[super viewSafeAreaInsetsDidChange];
	[self layoutToolbar];
	[self setupTableViewInsets];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

- (void)dealloc {
	[self unregisterFromNotifications];
}

#pragma mark - Setup

- (void)setupTableView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	tableView.allowsSelectionDuringEditing = YES;
	tableView.separatorInset = UIEdgeInsetsMake(0, 15.f, 0, 0);
	tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	tableView.dataSource = self;
	tableView.delegate = self;
	tableView.alwaysBounceVertical = YES;
	tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1.f, 44.f)];
	if (@available(iOS 11, *)) {
		tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	}
	[self.view addSubview:tableView];
	self.tableView = tableView;
}


- (void)setupToolbar {
	UIToolbar *toolbar = [[UIToolbar alloc] init];
	toolbar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
	toolbar.barStyle = UIBarStyleDefault;
	[self.view addSubview:toolbar];
	self.toolbar = toolbar;
	[self layoutToolbar];
}

- (void)setupTableViewInsets {
	CGFloat topInset = 0.f;
	CGFloat bottomInset = 0.f;
	CGFloat previousTopInset = self.tableView.contentInset.top;
	CGFloat previousTopOffset = self.tableView.contentOffset.y;
	if (self.sleepTimerView) {
		topInset = CGRectGetMaxY(self.sleepTimerView.frame);
	}
	else {
		UINavigationBar *bar = self.navigationController.navigationBar;
		topInset = CGRectGetMaxY(bar.frame);
	}
	if (self.toolbar) {
		UIToolbar *toolbar = self.toolbar;
		bottomInset = CGRectGetMaxY(self.view.frame) - CGRectGetMinY(toolbar.frame);
	}
	self.tableView.contentInset = UIEdgeInsetsMake(topInset, 0, bottomInset, 0);
	if (@available(iOS 13, *)) {
		self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);;
	} else {
		self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
	}
	CGFloat newTopOffset = previousTopOffset + previousTopInset - topInset;
	CGPoint contentOffset = self.tableView.contentOffset;
	contentOffset.y = MAX(-topInset, MIN(newTopOffset, self.tableView.contentSize.height - CGRectGetHeight(self.tableView.frame) + bottomInset));
	self.tableView.contentOffset = contentOffset;
}

#pragma mark - Layout

- (void)layoutViews {
	[self layoutSleepTimerView];
	[self layoutToolbar];
	[self setupTableViewInsets];
}

- (void)layoutToolbar {
	UINavigationBar *bar = self.navigationController.navigationBar;
	CGFloat height = CGRectGetHeight(bar.frame);
	CGFloat safeAreaBottom = 0.f;
	if (@available(iOS 11, *)) {
		safeAreaBottom = self.view.safeAreaInsets.bottom;
	}
	self.toolbar.frame = CGRectMake(0,
									CGRectGetHeight(self.view.frame) - height - safeAreaBottom,
									CGRectGetWidth(self.view.frame),
									height);
}


- (void)layoutSleepTimerView {
	if (self.sleepTimerView) {
		UINavigationBar *bar = self.navigationController.navigationBar;
		CGRect navigationBarFrame = [bar.superview convertRect:bar.frame toView:self.view];
		CGFloat height = CGRectGetHeight(navigationBarFrame);
		self.sleepTimerView.frame = CGRectMake(0,
											   CGRectGetMaxY(navigationBarFrame),
											   CGRectGetWidth(self.view.frame),
											   height);
		self.sleepTimerView.horizontalPadding = self.tableView.separatorInset.left;
	}
}

#pragma mark - Audio session

- (void)setupAudioSession
{
	NSError *error = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	BOOL ok = [session setCategory:AVAudioSessionCategoryPlayback error:&error];
	if (!ok) {
		NSLog(@"Could not set audiosession category. Error: %@", error);
	}
	ok = [session setActive:YES error:&error];
	if (!ok) {
		NSLog(@"Could not set audiosession active. Error: %@", error);
	}
}

- (void)endAudioSession
{
	NSError *error = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	BOOL ok = [session setCategory:AVAudioSessionCategoryAmbient error:&error];
	if (!ok) {
		NSLog(@"Could not set audiosession category. Error: %@", error);
	}
	ok = [session setActive:YES error:&error];
	if (!ok) {
		NSLog(@"Could not set audiosession active. Error: %@", error);
	}
}

#pragma mark - Toolbar & navigation items

- (void)updateToolbarItems {
	UIBarButtonItem *middleItem = nil;
	if (self.tableView.editing) {
		middleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonPressed:)];
	}
	else {
		switch ([[SRRadioPlayer sharedPlayer] state]) {
			case SRRadioPlayerStateStopped:
			case SRRadioPlayerStateError:
			case SRRadioPlayerStatePaused:
			{
				// play button
				middleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(playButtonPressed:)];
				break;
			}
			case SRRadioPlayerStateOpening:
			case SRRadioPlayerStateBuffering:
			{
				// loading indicator
				UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
				[loadingIndicator setColor:[SRAppearance mainColor]];
				[loadingIndicator startAnimating];
				middleItem = [[UIBarButtonItem alloc] initWithCustomView:loadingIndicator];
				break;
			}
			case SRRadioPlayerStatePlaying:
			{
				// pause button
				middleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPause target:self action:@selector(pauseButtonPressed:)];
				break;
			}
			default:
				break;
		}
	}
	UIBarButtonItem *flexibleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	NSArray *items = @[flexibleItem, middleItem, flexibleItem];
	[self.toolbar setItems:items];
}

- (void)updateNavigationButtons {
	if (self.tableView.editing) {
		UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Done", @"Done")
																	 style:UIBarButtonItemStyleDone
																	target:self
																	action:@selector(doneButtonPressed:)];
		self.navigationItem.rightBarButtonItem = doneItem;
	}
	else {
		UIImage *editIcon = [[UIImage imageNamed:@"EditIcon"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		UIButton *editButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[editButton setImage:editIcon forState:UIControlStateNormal];
		[editButton addTarget:self action:@selector(editButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
		editButton.frame = CGRectMake(0, 0, editIcon.size.width, editIcon.size.height);
		UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:editButton];
		self.navigationItem.rightBarButtonItem = item;
	}
}

#pragma mark - Notifications

- (void)registerForNotifications {
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(stationsLoaded:) name:SRDataManagerDidLoadStations object:nil];
	[nc addObserver:self selector:@selector(stationsChanged:) name:SRDataManagerDidChangeStations object:nil];
	[nc addObserver:self selector:@selector(sleepTimerSettingsChanged:) name:SRDataManagerDidChangeSleepTimerSettings object:nil];
	[nc addObserver:self selector:@selector(audioSessionInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
	[nc addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
	
	__weak SRRadioViewController *weakSelf = self;
	self.callCenter = [[CTCallCenter alloc] init];
	self.callCenter.callEventHandler = ^(CTCall *call) {
		__strong SRRadioViewController *strongSelf = weakSelf;
		if (strongSelf) {
			if (call.callState == CTCallStateIncoming || call.callState == CTCallStateDialing) {
				[strongSelf audioSessionInterruptedByCall:YES];
				[strongSelf startBackgroundTask];
			} else if (call.callState == CTCallStateDisconnected && strongSelf.callInProgress) {
				[strongSelf audioSessionResumeByCall:YES];
			}
		}
	};
}

- (void)unregisterFromNotifications {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.callCenter.callEventHandler = nil;
	self.callCenter = nil;
}

- (void)stationsLoaded:(NSNotification *)notification {
	[self.tableView reloadData];
}

- (void)stationsChanged:(NSNotification *)notification {
	[self.tableView reloadData];
}

- (void)sleepTimerSettingsChanged:(NSNotification *)notification {
	[self.tableView reloadData];
}

- (void)audioSessionInterruption:(NSNotification *)notification {
	AVAudioSessionInterruptionType interruptionType = [[notification.userInfo objectForKey:AVAudioSessionInterruptionTypeKey] integerValue];
	if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
		[self audioSessionInterruptedByCall:NO];
	}
	else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
		AVAudioSessionInterruptionOptions interruptionOption = [[notification.userInfo objectForKey:AVAudioSessionInterruptionOptionKey] integerValue];
		if (_audioSessionInterrupted && interruptionOption == AVAudioSessionInterruptionOptionShouldResume) {
			[self audioSessionResumeByCall:NO];
		}
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	[self updateRadioStations];
}

#pragma mark - Playback interruption

- (void)audioSessionInterruptedByCall:(BOOL)call {
	if (call) {
		_callInProgress = YES;
	} else {
		_audioSessionInterrupted = YES;
	}
	if ([[SRRadioPlayer sharedPlayer] state] != SRRadioPlayerStateStopped) {
		_playbackInterrupted = YES;
		[self performSelectorOnMainThread:@selector(stopAction) withObject:nil waitUntilDone:YES];
	}
}

- (void)audioSessionResumeByCall:(BOOL)call {
	if (call) {
		_callInProgress = NO;
	} else {
		_audioSessionInterrupted = NO;
	}
	if ([[SRRadioPlayer sharedPlayer] state] == SRRadioPlayerStateStopped && _playbackInterrupted && !_callInProgress && !_audioSessionInterrupted) {
		// resume playback
		[self performSelectorOnMainThread:@selector(playAction) withObject:nil waitUntilDone:YES];
	}
}

#pragma mark - Network

- (void)loadRadioStations {
	_stationsLoadedTimestamp = [[NSDate date] timeIntervalSince1970];
	if ([self stations].count == 0) {
		[MBProgressHUD showHUDAddedTo:self.view animated:YES];
	}
	__weak SRRadioViewController *weakSelf = self;
	[[SRDataManager sharedManager] loadStationsWithCompletionHandler:^(NSError *error) {
		[MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
		if (error && [weakSelf stations].count == 0) {
			// could not load radio stations
			[self handleStationsLoadError];
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

- (NSArray *)stations {
	return [[SRDataManager sharedManager] stations];
}

- (void)selectStationWithOffset:(NSInteger)offset {
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	NSInteger currentIndex = NSNotFound;
	NSArray *stations = [self stations];
	for (SRRadioStation *station in stations) {
		if (station.stationId == selectedStation.stationId) {
			currentIndex = [stations indexOfObject:station];
			break;
		}
	}
	SRRadioStation *nextStation = nil;
	if (currentIndex != NSNotFound) {
		NSInteger nextIndex = currentIndex + offset;
		if (nextIndex < 0) {
			nextIndex += stations.count;
		}
		else if (nextIndex >= stations.count) {
			nextIndex -= stations.count;
		}
		nextStation = stations[nextIndex];
	}
	else if (stations.count > 0) {
		nextStation = stations[0];
	}
	[[SRDataManager sharedManager] selectRadioStation:nextStation];
	[self.tableView reloadData];
}

- (void)selectNextStation {
	[self selectStationWithOffset:1];
}

- (void)selectPreviousStation {
	[self selectStationWithOffset:-1];
}

- (void)markSelectedRadioStation {
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	if (selectedStation) {
		NSIndexPath *selectedIndexPath = nil;
		NSArray *stations = [self stations];
		for (SRRadioStation *existingStation in stations) {
			if (existingStation.stationId == selectedStation.stationId) {
				selectedIndexPath = [NSIndexPath indexPathForRow:[stations indexOfObject:existingStation] inSection:0];
				break;
			}
		}
		if (selectedIndexPath) {
			UITableView *tableView = self.tableView;
			for (UITableViewCell *cell in tableView.visibleCells) {
				cell.accessoryType = [tableView indexPathForCell:cell].row == selectedIndexPath.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
			}
		}
	}
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	// Return the number of sections.
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	// Return the number of rows in the section.
	return [[self stations] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *cellIdentifier = @"RadioStationCell";
	SRRadioTableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
	if (!cell) {
		cell = [[SRRadioTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
	}
	SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
	__weak SRRadioViewController *weakSelf = self;
	
	cell.defaultColor = [SRAppearance cellBackgroundColor];
	
	BOOL sleepTimerByDefault = [SRDataManager sharedManager].sleepTimerEnabledByDefault;
	UIView *iconView = sleepTimerByDefault ? [self viewWithImageName:@"Play"] : [self viewWithImageName:@"Clock"];
	UIColor *clockColor = [SRAppearance cellActionColor];
	[cell setSwipeGestureWithView:iconView color:clockColor mode:MCSwipeTableViewCellModeSwitch state:MCSwipeTableViewCellState1 completionBlock:^(MCSwipeTableViewCell *cell, MCSwipeTableViewCellState state, MCSwipeTableViewCellMode mode) {
		[[SRDataManager sharedManager] selectRadioStation:station];
		[weakSelf markSelectedRadioStation];
		[weakSelf playActionWithSleepTimer:!sleepTimerByDefault];
	}];
	
	if ([self canReportProblemForRadioStation:station]) {
		UIView *reportView = [self viewWithImageName:@"Warning"];
		UIColor *reportColor = [SRAppearance cellReportColor];
		[cell setSwipeGestureWithView:reportView color:reportColor mode:MCSwipeTableViewCellModeSwitch state:MCSwipeTableViewCellState2 completionBlock:^(MCSwipeTableViewCell *cell, MCSwipeTableViewCellState state, MCSwipeTableViewCellMode mode) {
			[weakSelf reportProblemWithRadioStation:station];
		}];
	}
	
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	cell.textLabel.text = station.name;
	cell.accessoryType = station.stationId == selectedStation.stationId ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
	SRRadioStation *station = [[self stations] objectAtIndex:sourceIndexPath.row];
	[[SRDataManager sharedManager] moveRadioStation:station atIndex:destinationIndexPath.row];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		@synchronized(self) {
			SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
			BOOL stationWasSelected = station.stationId == [[SRDataManager sharedManager] selectedRadioStation].stationId;
			[[SRDataManager sharedManager] deleteRadioStation:station];
			[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
			if (station.stationId == [[SRRadioPlayer sharedPlayer] currentRadioStation].stationId) {
				// deleted station currently playing... stop it
				[self stopAction];
			}
			if (stationWasSelected) {
				[self markSelectedRadioStation];
			}
		}
	}
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
	if (tableView.editing) {
		[self presentEditRadioControllerForStation:station];
	}
	else {
		for (UITableViewCell *cell in tableView.visibleCells) {
			cell.accessoryType = [tableView indexPathForCell:cell].row == indexPath.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		}
		[[SRDataManager sharedManager] selectRadioStation:station];
		if ([[SRRadioPlayer sharedPlayer] currentRadioStation] != nil) {
			[self playAction];
		}
	}
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return NSLocalizedString(@"Delete", nil);
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView configureSeparatorForCell:cell];
}

#pragma mark - Button actions

- (void)playButtonPressed:(id)sender {
	[self playAction];
}

- (void)pauseButtonPressed:(id)sender {
	[self stopAction];
}

- (void)editButtonPressed:(id)sender {
	if (!self.tableView.editing) {
		[self.tableView setEditing:YES animated:YES];
	}
	[self stopAction];
	[self updateNavigationButtons];
	[self updateToolbarItems];
}

- (void)doneButtonPressed:(id)sender {
	if (self.tableView.editing) {
		[self.tableView setEditing:NO animated:YES];
	}
	[self updateNavigationButtons];
	[self updateToolbarItems];
}

- (void)addButtonPressed:(id)sender {
	[self presentAddRadioController];
}

#pragma mark - Background task

- (void)startBackgroundTask {
	UIApplication *application = [UIApplication sharedApplication];
	if (_bgTask != UIBackgroundTaskInvalid) {
		[application endBackgroundTask:_bgTask];
		_bgTask = UIBackgroundTaskInvalid;
	}
	__weak SRRadioViewController *weakSelf = self;
	_bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
		[application endBackgroundTask:weakSelf.bgTask];
		weakSelf.bgTask = UIBackgroundTaskInvalid;
	}];
}

- (void)endBackgroundTask {
	if (_bgTask != UIBackgroundTaskInvalid) {
		[[UIApplication sharedApplication] endBackgroundTask:_bgTask];
		_bgTask = UIBackgroundTaskInvalid;
	}
}


#pragma mark - Common actions

- (void)playAction {
	BOOL sleepTimer = [SRDataManager sharedManager].sleepTimerEnabledByDefault;
	[self playActionWithSleepTimer:sleepTimer];
}

- (void)playActionWithSleepTimer:(BOOL)sleepTimer {
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	if (!selectedStation) {
		// radio stations not yet loaded
		// ignore this playback request
		return;
	}
	[self startBackgroundTask];
	if (sleepTimer) {
		[self setupSleepTimer];
	}
	else {
		[self clearSleepTimer];
	}
	_playbackInterrupted = NO;
	_audioSessionInterrupted = NO;
	_callInProgress = NO;
	[[SRRadioPlayer sharedPlayer] playRadioStation:selectedStation];
}

- (void)stopAction {
	[[SRRadioPlayer sharedPlayer] stop];
	[self clearSleepTimer];
}

- (void)updateNowPlayingInfo {
	MPNowPlayingInfoCenter *infoCenter = [MPNowPlayingInfoCenter defaultCenter];
	NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	if (selectedStation.name) {
		[nowPlayingInfo setObject:selectedStation.name forKey:MPMediaItemPropertyArtist];
	}
	SRRadioPlayer *player = [SRRadioPlayer sharedPlayer];
	NSString *nowPlaying = [player.metaData objectForKey:SRRadioPlayerMetaDataNowPlayingKey];
	NSString *title = [player.metaData objectForKey:SRRadioPlayerMetaDataTitleKey];
	NSString *artist = [player.metaData objectForKey:SRRadioPlayerMetaDataArtistKey];
	if (!nowPlaying.length && title.length && artist.length) {
		nowPlaying = [NSString stringWithFormat:@"%@ - %@", [artist capitalizedString], [title capitalizedString]];
	}
	nowPlaying = [nowPlaying stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (nowPlaying.length) {
		[nowPlayingInfo setObject:[nowPlaying capitalizedString] forKey:MPMediaItemPropertyTitle];
	}
	NSInteger currentIndex = 0;
	NSArray *stations = [self stations];
	for (SRRadioStation *station in stations) {
		if (station.stationId == selectedStation.stationId) {
			currentIndex = [stations indexOfObject:station];
			break;
		}
	}
	[nowPlayingInfo setObject:@(currentIndex) forKey:MPNowPlayingInfoPropertyPlaybackQueueIndex];
	[nowPlayingInfo setObject:@([self stations].count) forKey:MPNowPlayingInfoPropertyPlaybackQueueCount];
	[infoCenter setNowPlayingInfo:nowPlayingInfo];
	
	// update title view
	if ([[SRRadioPlayer sharedPlayer] currentRadioStation]) {
		CGSize nowPlayingSize = CGSizeMake(240.f, CGRectGetHeight(self.navigationController.navigationBar.frame));
		if (!self.nowPlayingTitleView) {
			self.nowPlayingTitleView = [[SRNowPlayingView alloc] initWithFrame:CGRectMake(0, 0, nowPlayingSize.width, nowPlayingSize.height)];
			self.nowPlayingTitleView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		}
		self.nowPlayingTitleView.titleString = selectedStation.name;
		self.nowPlayingTitleView.subtitleString = nowPlaying.length ? [nowPlaying capitalizedString] : nil;
		CGSize size = [self.nowPlayingTitleView sizeThatFits:nowPlayingSize];
		self.nowPlayingTitleView.frame = CGRectMake(0, 0, size.width, size.height);
		self.navigationItem.titleView = self.nowPlayingTitleView;
	}
	else {
		self.navigationItem.titleView = nil;
	}
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

#pragma mark - SRRadioPlayerDelegate

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state {
	[self updateToolbarItems];
	if (state == SRRadioPlayerStateError) {
		[self handlePlaybackError];
		[self stopAction];
	}
	if (state == SRRadioPlayerStatePlaying &&
		self.sleepTimer && !self.sleepTimer.isRunning) {
		[self startSleepTimer];
	}
	if (state == SRRadioPlayerStateError ||
		state == SRRadioPlayerStatePlaying ||
		state == SRRadioPlayerStateStopped) {
		[self endBackgroundTask];
	}
}

- (void)radioPlayer:(SRRadioPlayer *)player didChangeMetaData:(NSDictionary *)metadata {
	[self updateNowPlayingInfo];
}

#pragma mark - SRSleepTimerDelegate

- (void)sleepTimer:(SRSleepTimer *)timer changeVolumeLevel:(float)volume {
	int playerVolume = (int)(volume * 100.0);
	[[SRRadioPlayer sharedPlayer] setVolume:playerVolume];
}

- (void)sleepTimer:(SRSleepTimer *)timer timeRemaining:(NSTimeInterval)timeRemaining {
	self.sleepTimerView.timeRemaining = timeRemaining;
}

- (void)sleepTimerDidEnd:(SRSleepTimer *)timer {
	[self stopAction];
}

#pragma mark - SRSleepTimerViewDelegate

- (void)sleepTimerViewCancelButtonPressed:(SRSleepTimerView *)view {
	[self clearSleepTimer];
	[[SRRadioPlayer sharedPlayer] setVolume:100];
}

#pragma mark - Remote control events

- (void)startRemoteControlTracking {
	MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
	
	MPRemoteCommand *nextTrackCommand = [commandCenter nextTrackCommand];
	[nextTrackCommand setEnabled:YES];
	[nextTrackCommand addTarget:self action:@selector(remotePlayNext)];
	
	MPRemoteCommand *previousTrackCommand = [commandCenter previousTrackCommand];
	[previousTrackCommand setEnabled:YES];
	[previousTrackCommand addTarget:self action:@selector(remotePlayPrevious)];
	
	MPRemoteCommand *pauseCommand = [commandCenter pauseCommand];
	[pauseCommand setEnabled:YES];
	[pauseCommand addTarget:self action:@selector(remoteStop)];
	
	MPRemoteCommand *playCommand = [commandCenter playCommand];
	[playCommand setEnabled:YES];
	[playCommand addTarget:self action:@selector(remotePlay)];
	
	MPRemoteCommand *togglePlayPauseCommand = [commandCenter togglePlayPauseCommand];
	[togglePlayPauseCommand setEnabled:YES];
	[togglePlayPauseCommand addTarget:self action:@selector(remoteTogglePlayPause)];
}

- (void)endRemoteControlTracking {
	MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
	
	MPRemoteCommand *nextTrackCommand = [commandCenter nextTrackCommand];
	[nextTrackCommand setEnabled:NO];
	[nextTrackCommand removeTarget:self];
	
	MPRemoteCommand *previousTrackCommand = [commandCenter previousTrackCommand];
	[previousTrackCommand setEnabled:NO];
	[previousTrackCommand removeTarget:self];
	
	MPRemoteCommand *pauseCommand = [commandCenter pauseCommand];
	[pauseCommand setEnabled:NO];
	[pauseCommand removeTarget:self];
	
	MPRemoteCommand *playCommand = [commandCenter playCommand];
	[playCommand setEnabled:NO];
	[playCommand removeTarget:self];
	
	MPRemoteCommand *togglePlayPauseCommand = [commandCenter togglePlayPauseCommand];
	[togglePlayPauseCommand setEnabled:NO];
	[togglePlayPauseCommand removeTarget:self];
}

- (MPRemoteCommandHandlerStatus)remotePlay {
	[self playAction];
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remoteStop {
	[self stopAction];
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remoteTogglePlayPause {
	SRRadioPlayerState state = [[SRRadioPlayer sharedPlayer] state];
	if (state == SRRadioPlayerStateBuffering ||
		state == SRRadioPlayerStateOpening ||
		state == SRRadioPlayerStatePlaying) {
		[self stopAction];
	}
	else {
		[self playAction];
	}
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remotePlayNext {
	[self selectNextStation];
	[self playAction];
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remotePlayPrevious {
	[self selectPreviousStation];
	[self playAction];
	return MPRemoteCommandHandlerStatusSuccess;
}

#pragma mark - Error handling

- (void)handleStationsLoadError {
	__weak SRRadioViewController *weakSelf = self;
	[UIAlertView showWithTitle:NSLocalizedString(@"Oops", @"Oops!")
					   message:NSLocalizedString(@"StationsLoadFailed", @"Error message")
			 cancelButtonTitle:NSLocalizedString(@"Retry", @"Retry")
			 otherButtonTitles:nil
					  tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
						  [weakSelf loadRadioStations];
					  }];
}

- (void)handlePlaybackError {
	if ([self showErrorPopup]) {
		// display error
		SRRadioStation *station = [[SRRadioPlayer sharedPlayer] currentRadioStation];
		BOOL canReportProblem = [self isInternetReachable] && [self canReportProblemForRadioStation:station];
		NSString *message = nil;
		if ([self isInternetReachable]) {
			message = [NSString stringWithFormat:NSLocalizedString(@"PlaybackErrorStation", @""), station.name];
		}
		else {
			message = [NSString stringWithFormat:NSLocalizedString(@"PlaybackErrorInternet", @""), station.name];
		}
		__weak SRRadioViewController *weakSelf = self;
		[UIAlertView showWithTitle:NSLocalizedString(@"Oops", @"Oops!")
						   message:message
				 cancelButtonTitle:NSLocalizedString(@"Ok", @"Ok")
				 otherButtonTitles:canReportProblem ? @[NSLocalizedString(@"Report", @"Report")] : nil
						  tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
							  if (buttonIndex != alertView.cancelButtonIndex) {
								  [weakSelf reportProblemWithRadioStation:station];
							  }
						  }];
	}
}

- (BOOL)showErrorPopup {
	return [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
}

#pragma mark - Sleep timer

- (void)setupSleepTimer {
	[self.sleepTimer invalidate];
	NSTimeInterval interval = [SRDataManager sharedManager].sleepTimerInterval;
	self.sleepTimer = [[SRSleepTimer alloc] initWithInterval:interval delegate:self];
	[self showSleepTimerViewAnimated:YES];
}

- (void)startSleepTimer {
	[self.sleepTimer startTimer];
}

- (void)clearSleepTimer {
	[self.sleepTimer invalidate];
	self.sleepTimer = nil;
	[self hideSleepTimerViewAnimated:YES];
}

- (void)showSleepTimerViewAnimated:(BOOL)animated {
	if (!self.sleepTimerView) {
		self.sleepTimerView = [[SRSleepTimerView alloc] init];
		self.sleepTimerView.timeRemaining = self.sleepTimer.timeRemaining;
		self.sleepTimerView.delegate = self;
		self.sleepTimerView.alpha = 0.f;
		[self layoutSleepTimerView];
		CGRect sleepTimerViewFrame = self.sleepTimerView.frame;
		sleepTimerViewFrame.size.height = 0.f;
		self.sleepTimerView.frame = sleepTimerViewFrame;
		[self.view addSubview:self.sleepTimerView];
	}
	
	[UIView animateWithDuration:animated ? 0.3f : 0.f animations:^{
		self.sleepTimerView.alpha = 1.f;
		[self layoutSleepTimerView];
		[self setupTableViewInsets];
	}];
}

- (void)hideSleepTimerViewAnimated:(BOOL)animated {
	if (self.sleepTimerView) {
		UIView *sleepTimerView = self.sleepTimerView;
		self.sleepTimerView = nil;
		[UIView animateWithDuration:animated ? 0.3f : 0.f
						 animations:^{
							 sleepTimerView.alpha = 0.f;
							 [self setupTableViewInsets];
						 }
						 completion:^(BOOL finished) {
							 [sleepTimerView removeFromSuperview];
						 }];
	}
}

#pragma mark - Report problem

- (BOOL)canReportProblemForRadioStation:(SRRadioStation *)station {
	return [MFMailComposeViewController canSendMail] && ![[SRDataManager sharedManager] isCustomRadioStation:station];
}

- (void)reportProblemWithRadioStation:(SRRadioStation *)station {
	MFMailComposeViewController *mailController = [[MFMailComposeViewController alloc] init];
	mailController.modalPresentationStyle = UIModalPresentationFormSheet;
	mailController.mailComposeDelegate = self;
	[mailController setSubject:[NSString stringWithFormat:@"Report problem [%@]", station.name]];
	[mailController setToRecipients:@[@"sloradio@jernej.org"]];
	NSString *message = [NSString stringWithFormat:@"There is a problem with the following radio station.\n\nID: %ld\nName: %@\nURL: %@", (long)station.stationId, station.name, station.url];
	[mailController setMessageBody:message isHTML:NO];
	[self presentViewController:mailController animated:YES completion:NULL];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
	[self dismissViewControllerAnimated:YES completion:NULL];
}

#pragma mark - Screen rotation

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
	[coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
		[self layoutViews];
	} completion:nil];
}

#pragma mark - Utils

- (UIView *)viewWithImageName:(NSString *)imageName {
	UIImage *image = [[UIImage imageNamed:imageName] imageWithColor:[UIColor whiteColor]];
	UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
	imageView.contentMode = UIViewContentModeCenter;
	return imageView;
}

- (BOOL)isInternetReachable {
	return [[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable;
}

@end
