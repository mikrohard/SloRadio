//
//  SRFavoritesPickerViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRFavoritesPickerViewController.h"
#import "SRStationTableViewCell.h"
#import "SRDataManager.h"
#import "SRRadioStation.h"

static NSString * const SRStationCellIdentifier = @"StationCell";

@interface SRFavoritesPickerViewController () <UISearchResultsUpdating>

@property (nonatomic, strong) NSArray *allStations;
@property (nonatomic, strong) NSArray *filteredStations;
@property (nonatomic, strong) NSMutableOrderedSet *selectedStationIds;

@end

@implementation SRFavoritesPickerViewController

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super initWithStyle:UITableViewStylePlain];
	if (self) {
		self.title = NSLocalizedString(@"ChooseFavorites", @"Choose favorites");
		SRDataManager *dataManager = [SRDataManager sharedManager];
		self.allStations = dataManager.stations;
		self.filteredStations = self.allStations;
		self.selectedStationIds = [NSMutableOrderedSet orderedSet];
		for (SRRadioStation *station in dataManager.favoriteStations) {
			[self.selectedStationIds addObject:@(station.stationId)];
		}
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.tableView registerClass:[SRStationTableViewCell class] forCellReuseIdentifier:SRStationCellIdentifier];
	self.tableView.separatorInset = UIEdgeInsetsMake(0, [SRStationTableViewCell separatorInsetLeft], 0, 0);
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
																						   target:self
																						   action:@selector(cancelButtonPressed:)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
																							target:self
																							action:@selector(doneButtonPressed:)];
	
	UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	searchController.searchResultsUpdater = self;
	searchController.obscuresBackgroundDuringPresentation = NO;
	self.navigationItem.searchController = searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;
	
	// a pending selection should not be lost by accidentally swiping the sheet away
	self.modalInPresentation = YES;
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (query.length == 0) {
		self.filteredStations = self.allStations;
	} else {
		NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(SRRadioStation *station, NSDictionary *bindings) {
			return [station.name rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
		}];
		self.filteredStations = [self.allStations filteredArrayUsingPredicate:predicate];
	}
	[self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.filteredStations.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SRStationTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SRStationCellIdentifier forIndexPath:indexPath];
	SRRadioStation *station = self.filteredStations[indexPath.row];
	[cell configureWithStation:station];
	cell.checked = [self.selectedStationIds containsObject:@(station.stationId)];
	return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	SRRadioStation *station = self.filteredStations[indexPath.row];
	NSNumber *stationId = @(station.stationId);
	if ([self.selectedStationIds containsObject:stationId]) {
		[self.selectedStationIds removeObject:stationId];
	} else {
		[self.selectedStationIds addObject:stationId];
	}
	SRStationTableViewCell *cell = (SRStationTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
	cell.checked = [self.selectedStationIds containsObject:stationId];
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Actions

- (void)cancelButtonPressed:(id)sender {
	[self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)doneButtonPressed:(id)sender {
	// keep the order of existing favorites and append new ones in station list order
	SRDataManager *dataManager = [SRDataManager sharedManager];
	NSMutableArray *favorites = [NSMutableArray array];
	NSMutableSet *addedStationIds = [NSMutableSet set];
	NSArray *candidates = [dataManager.favoriteStations arrayByAddingObjectsFromArray:self.allStations];
	for (SRRadioStation *station in candidates) {
		NSNumber *stationId = @(station.stationId);
		if ([self.selectedStationIds containsObject:stationId] && ![addedStationIds containsObject:stationId]) {
			[favorites addObject:station];
			[addedStationIds addObject:stationId];
		}
	}
	[dataManager setFavoriteRadioStations:favorites];
	[self dismissViewControllerAnimated:YES completion:NULL];
}

@end
