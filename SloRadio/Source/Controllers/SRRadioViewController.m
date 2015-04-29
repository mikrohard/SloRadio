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

@interface SRRadioViewController () <SRRadioPlayerDelegate> {
    SRRadioPlayer *_player;
}

@end

@implementation SRRadioViewController

#pragma mark - Lifecycle

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self) {
        [self registerForNotifications];
    }
    return self;
}

- (void)loadView {
    [super loadView];
    [self setupNavigationBar];
    [self setupToolbar];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[SRDataManager sharedManager] loadStations];
    [[SRRadioPlayer sharedPlayer] setDelegate:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[SRRadioPlayer sharedPlayer] stop];
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
    [self.navigationController.navigationBar setBarTintColor:[SRAppearance mainColor]];
    [self.navigationController.navigationBar setTintColor:[SRAppearance navigationBarContentColor]];
}

#pragma mark - Toolbar

- (void)updateToolbarItems {
    UIBarButtonItem *middleItem = nil;
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
    UIBarButtonItem *flexibleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    NSArray *items = @[flexibleItem, middleItem, flexibleItem];
    [self setToolbarItems:items];
}

#pragma mark - Notifications

- (void)registerForNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stationsLoaded:) name:SRDataManagerDidLoadStations object:nil];
}

- (void)unregisterFromNotifications {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stationsLoaded:(NSNotification *)notification {
    [self.tableView reloadData];
}

#pragma mark - Stations

- (NSArray *)stations {
    return [[SRDataManager sharedManager] stations];
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
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    SRRadioStation *station = [[self stations] objectAtIndex:indexPath.row];
    SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
    cell.textLabel.text = station.name;
    cell.accessoryType = station.stationId == selectedStation.stationId ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
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

#pragma mark - Button actions

- (void)playButtonPressed:(id)sender {
    SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
    [[SRRadioPlayer sharedPlayer] playRadioStation:selectedStation];
}

- (void)pauseButtonPressed:(id)sender {
    [[SRRadioPlayer sharedPlayer] stop];
}

#pragma mark - SRRadioPlayerDelegate

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state {
    [self updateToolbarItems];
}

@end
