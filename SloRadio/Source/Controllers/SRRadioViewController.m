//
//  SRRadioViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioViewController.h"
#import "SRDataManager.h"
#import "SRRadioPlayer.h"
#import "SRRadioStation.h"
#import "SRAddRadioViewController.h"
#import "MBProgressHUD.h"
#import "UIAlertView+Blocks.h"
#import "UITableView+Separators.h"
#import "SRNowPlayingView.h"
#import "SRRadioTableViewCell.h"
#import "UIImage+Color.h"

@import AVFoundation;
@import MediaPlayer;

@interface SRRadioViewController () <SRRadioPlayerDelegate> {
    BOOL _playbackInterrupted;
}

@property (nonatomic, strong) SRNowPlayingView *nowPlayingTitleView;

@end

@implementation SRRadioViewController

@synthesize nowPlayingTitleView = _nowPlayingTitleView;

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        [self registerForNotifications];
        self.title = @"Radio stations";
    }
    return self;
}

- (void)loadView {
    [super loadView];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 15.f, 0, 0);
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1.f, 44.f)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadRadioStations];
    [[SRRadioPlayer sharedPlayer] setDelegate:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupNavigationBar];
    [self setupToolbar];
    [self setupAudioSession];
    [self startRemoteControlTracking];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[SRRadioPlayer sharedPlayer] stop];
    [self endRemoteControlTracking];
    [self endAudioSession];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    [self unregisterFromNotifications];
}

#pragma mark - Setup

- (void)setupToolbar {
    self.navigationController.toolbarHidden = NO;
    [self updateToolbarItems];
}

- (void)setupNavigationBar {
    [self updateNavigationButtons];
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
    [self setToolbarItems:items];
}

- (void)updateNavigationButtons {
    if (self.tableView.editing) {
        UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(doneButtonPressed:)];
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
    [nc addObserver:self selector:@selector(audioSessionInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
}

- (void)unregisterFromNotifications {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stationsLoaded:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)stationsChanged:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)audioSessionInterruption:(NSNotification *)notification {
    AVAudioSessionInterruptionType interruptionType = [[notification.userInfo objectForKey:AVAudioSessionInterruptionTypeKey] integerValue];
    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        if ([[SRRadioPlayer sharedPlayer] state] != SRRadioPlayerStateStopped) {
            _playbackInterrupted = YES;
            [self performSelectorOnMainThread:@selector(stopAction) withObject:nil waitUntilDone:NO];
        }
    }
    else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        AVAudioSessionInterruptionOptions interruptionOption = [[notification.userInfo objectForKey:AVAudioSessionInterruptionOptionKey] integerValue];
        if (_playbackInterrupted && interruptionOption == AVAudioSessionInterruptionOptionShouldResume) {
            // resume playback
            [self performSelectorOnMainThread:@selector(playAction) withObject:nil waitUntilDone:NO];
        }
    }
}

#pragma mark - Network

- (void)loadRadioStations {
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
    UIView *clockView = [self viewWithImageName:@"Clock"];
    UIColor *clockColor = [SRAppearance cellActionColor];
    [cell setSwipeGestureWithView:clockView color:clockColor mode:MCSwipeTableViewCellModeSwitch state:MCSwipeTableViewCellState1 completionBlock:^(MCSwipeTableViewCell *cell, MCSwipeTableViewCellState state, MCSwipeTableViewCellMode mode) {
        NSLog(@"Did swipe \"Clock\" cell");
    }];
    
    UIView *reportView = [self viewWithImageName:@"Warning"];
    UIColor *reportColor = [SRAppearance cellReportColor];
    [cell setSwipeGestureWithView:reportView color:reportColor mode:MCSwipeTableViewCellModeSwitch state:MCSwipeTableViewCellState2 completionBlock:^(MCSwipeTableViewCell *cell, MCSwipeTableViewCellState state, MCSwipeTableViewCellMode mode) {
        NSLog(@"Did swipe \"Report\" cell");
    }];
    
    SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
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
                        for (UITableViewCell *cell in tableView.visibleCells) {
                            cell.accessoryType = [tableView indexPathForCell:cell].row == selectedIndexPath.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
                        }
                    }
                }
            }
        }
    }
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    for (UITableViewCell *cell in tableView.visibleCells) {
        cell.accessoryType = [tableView indexPathForCell:cell].row == indexPath.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
    [[SRDataManager sharedManager] selectRadioStation:station];
    if ([[SRRadioPlayer sharedPlayer] currentRadioStation] != nil) {
        [[SRRadioPlayer sharedPlayer] playRadioStation:station];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
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

#pragma mark - Common actions

- (void)playAction {
    _playbackInterrupted = NO;
    SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
    [[SRRadioPlayer sharedPlayer] playRadioStation:selectedStation];
}

- (void)stopAction {
    [[SRRadioPlayer sharedPlayer] stop];
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
    if (nowPlaying.length) {
        [nowPlayingInfo setObject:[nowPlaying capitalizedString] forKey:MPMediaItemPropertyTitle];
    }
    [infoCenter setNowPlayingInfo:nowPlayingInfo];
    
    // update title view
    if ([[SRRadioPlayer sharedPlayer] currentRadioStation]) {
        if (!self.nowPlayingTitleView) {
            self.nowPlayingTitleView = [[SRNowPlayingView alloc] initWithFrame:CGRectMake(0, 0, 240.f, 44.f)];
            self.nowPlayingTitleView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        }
        self.nowPlayingTitleView.titleString = selectedStation.name;
        self.nowPlayingTitleView.subtitleString = [nowPlaying capitalizedString];
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

#pragma mark - SRRadioPlayerDelegate

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state {
    [self updateToolbarItems];
    if (state == SRRadioPlayerStateError) {
        [self handlePlaybackError];
        [self stopAction];
    }
}

- (void)radioPlayer:(SRRadioPlayer *)player didChangeMetaData:(NSDictionary *)metadata {
    [self updateNowPlayingInfo];
}

#pragma mark - Remote control events

- (void)startRemoteControlTracking {
    [self becomeFirstResponder];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
}

- (void)endRemoteControlTracking {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self resignFirstResponder];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type == UIEventTypeRemoteControl) {
        switch (event.subtype) {
            case UIEventSubtypeRemoteControlPlay:
                [self remotePlay];
                break;
            case UIEventSubtypeRemoteControlPause:
            case UIEventSubtypeRemoteControlStop:
                [self remoteStop];
                break;
            case UIEventSubtypeRemoteControlTogglePlayPause:
                [self remoteTogglePlayPause];
                break;
            case UIEventSubtypeRemoteControlNextTrack:
                [self remotePlayNext];
                break;
            case UIEventSubtypeRemoteControlPreviousTrack:
                [self remotePlayPrevious];
                break;
            default:
                break;
        }
    }
}

- (void)remotePlay {
    [self playAction];
}

- (void)remoteStop {
    [self stopAction];
}

- (void)remoteTogglePlayPause {
    SRRadioPlayerState state = [[SRRadioPlayer sharedPlayer] state];
    if (state == SRRadioPlayerStateBuffering ||
        state == SRRadioPlayerStateOpening ||
        state == SRRadioPlayerStatePlaying) {
        [self stopAction];
    }
    else {
        [self playAction];
    }
}

- (void)remotePlayNext {
    [self selectNextStation];
    [self playAction];
}

- (void)remotePlayPrevious {
    [self selectPreviousStation];
    [self playAction];
}

#pragma mark - Error handling

- (void)handleStationsLoadError {
    __weak SRRadioViewController *weakSelf = self;
    [UIAlertView showWithTitle:@"Oops!"
                       message:@"Could not load radio stations."
             cancelButtonTitle:@"Retry"
             otherButtonTitles:nil
                      tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                          [weakSelf loadRadioStations];
                      }];
}

- (void)handlePlaybackError {
    if ([self showErrorPopup]) {
        // display error
        NSString *message = [NSString stringWithFormat:@"Unable to play \"%@\"", [[[SRRadioPlayer sharedPlayer] currentRadioStation] name]];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Oops!"
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    }
}

- (BOOL)showErrorPopup {
    return [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
}

#pragma mark - Utils

- (UIView *)viewWithImageName:(NSString *)imageName {
    UIImage *image = [[UIImage imageNamed:imageName] imageWithColor:[UIColor whiteColor]];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.contentMode = UIViewContentModeCenter;
    return imageView;
}

@end
