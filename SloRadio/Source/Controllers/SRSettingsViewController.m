//
//  SRSettingsViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 4. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRSettingsViewController.h"
#import "SRSettingsPickerCell.h"
#import "SRSliderTableViewCell.h"
#import "SRDataManager.h"
#import "MBProgressHUD.h"
#import "SRTableViewCell.h"

@interface SRSettingsViewController () <UIPickerViewDataSource, UIPickerViewDelegate, SRSliderTableViewCellProtocol>

@end

@implementation SRSettingsViewController

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = NSLocalizedString(@"Settings", @"Settings");
	}
	return self;
}

- (void)loadView {
	[super loadView];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.separatorInset = UIEdgeInsetsMake(0.f, 15.f, 0.f, 0.f);
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

#pragma mark - Settings switches

- (UISwitch *)sleepTimerSwitch {
	UISwitch *settingsSwitch = [[UISwitch alloc] init];
	settingsSwitch.onTintColor = [SRAppearance mainColor];
	[settingsSwitch addTarget:self action:@selector(sleepTimerEnabledChanged:) forControlEvents:UIControlEventValueChanged];
	return settingsSwitch;
}

- (UISwitch *)playerCachingSwitch {
	UISwitch *settingsSwitch = [[UISwitch alloc] init];
	settingsSwitch.onTintColor = [SRAppearance mainColor];
	[settingsSwitch addTarget:self action:@selector(playerCachingEnabledChanged:) forControlEvents:UIControlEventValueChanged];
	return settingsSwitch;
}

#pragma mark - Section handling

- (NSInteger)sectionForSleepTimer {
	return 0;
}

- (NSInteger)sectionForPlayer {
	return 1;
}

- (NSInteger)sectionForReset {
	return 2;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	// Return the number of sections.
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	// Return the number of rows in the section.
	if (section == [self sectionForSleepTimer]) {
		return 2;
	}
	else if (section == [self sectionForPlayer]) {
		return [SRDataManager sharedManager].playerCachingEnabled ? 2 : 1;
	}
	else if (section == [self sectionForReset]) {
		return 1;
	}
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == [self sectionForSleepTimer] && indexPath.row == 1) {
		// time picker cell
		static NSString *pickerCellIdentifier = @"SettingsPickerCell";
		SRSettingsPickerCell *cell = [self.tableView dequeueReusableCellWithIdentifier:pickerCellIdentifier];
		if (!cell) {
			cell = [[SRSettingsPickerCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:pickerCellIdentifier];
			cell.pickerView.dataSource = self;
			cell.pickerView.delegate = self;
		}
		return cell;
	}
	else if (indexPath.section == [self sectionForPlayer] && indexPath.row == 1) {
		// slider cell
		static NSString *sliderCellIdentifier = @"SliderCell";
		SRSliderTableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:sliderCellIdentifier];
		if (!cell) {
			cell = [[SRSliderTableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:sliderCellIdentifier];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.delegate = self;
			cell.minimumSliderValue = 0.f;
			cell.maximumSliderValue = 60.f;
		}
		cell.sliderValue = [SRDataManager sharedManager].playerCacheSize;
		return cell;
	}
	else {
		static NSString *cellIdentifier = @"SettingsCell";
		UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
		if (!cell) {
			cell = [[SRTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
		}
		if (indexPath.section == [self sectionForReset]) {
			// reset cell
			cell.selectionStyle = UITableViewCellSelectionStyleDefault;
			cell.textLabel.textColor = [SRAppearance mainColor];
			cell.textLabel.text = NSLocalizedString(@"ResetList", @"Reset list");
			cell.accessoryView = nil;
		}
		else if (indexPath.section == [self sectionForSleepTimer]) {
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.textLabel.textColor = [SRAppearance textColor];
			cell.textLabel.text = NSLocalizedString(@"AlwaysOn", @"Always on");
			UISwitch *settingsSwitch = [self sleepTimerSwitch];
			settingsSwitch.on = [[SRDataManager sharedManager] sleepTimerEnabledByDefault];
			cell.accessoryView = settingsSwitch;
		}
		else if (indexPath.section == [self sectionForPlayer]) {
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.textLabel.textColor = [SRAppearance textColor];
			cell.textLabel.text = NSLocalizedString(@"AdditionalCaching", nil);
			UISwitch *settingsSwitch = [self playerCachingSwitch];
			settingsSwitch.on = [[SRDataManager sharedManager] playerCachingEnabled];
			cell.accessoryView = settingsSwitch;
		}
		return cell;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == [self sectionForSleepTimer]) {
		return NSLocalizedString(@"SleepTimer", @"Sleep timer");
	}
	else if (section == [self sectionForReset]) {
		return NSLocalizedString(@"RadioStations", @"Radio Stations");
	}
	else if (section == [self sectionForPlayer]) {
		return NSLocalizedString(@"Player", @"Player");
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == [self sectionForPlayer] && [SRDataManager sharedManager].playerCachingEnabled) {
		return NSLocalizedString(@"CacheWarning", nil);
	}
	return nil;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == [self sectionForReset]) {
		[self presentResetAction];
	}
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == [self sectionForSleepTimer] && indexPath.row == 1) {
		return 162.f;
	}
	else if (indexPath.section == [self sectionForPlayer] && indexPath.row == 1) {
		return 84.f;
	}
	return 44.f;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == [self sectionForSleepTimer] && indexPath.row == 1) {
		SRSettingsPickerCell *pickerCell = (SRSettingsPickerCell *)cell;
		SRDataManager *dataManager = [SRDataManager sharedManager];
		NSUInteger selectedRow = dataManager.selectedSleepTimerIntervalIndex;
		if (selectedRow != NSNotFound) {
			[pickerCell.pickerView selectRow:selectedRow inComponent:0 animated:NO];
		}
	}
}

#pragma mark - UIPickerViewDataSource

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
	return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	return dataManager.selectableSleepTimerIntervals.count;
}

#pragma mark - UIPickerViewDelegate

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	NSTimeInterval interval = [[dataManager.selectableSleepTimerIntervals objectAtIndex:row] doubleValue];
	NSString *title = [NSString stringWithFormat:NSLocalizedString(@"NumberOfMinutes", nil), (int)(interval/60.0)];
	return title;
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	NSTimeInterval interval = [[dataManager.selectableSleepTimerIntervals objectAtIndex:row] doubleValue];
	dataManager.sleepTimerInterval = interval;
}

#pragma mark - SRSliderTableViewCellProtocol

- (void)cell:(SRSliderTableViewCell *)cell didChangeSliderValue:(float)sliderValue {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	dataManager.playerCacheSize = sliderValue;
}

#pragma mark - Settings actions

- (void)sleepTimerEnabledChanged:(UISwitch *)settingsSwitch {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	dataManager.sleepTimerEnabledByDefault = settingsSwitch.on;
}

- (void)playerCachingEnabledChanged:(UISwitch *)settingsSwitch {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	if (dataManager.playerCachingEnabled != settingsSwitch.on) {
		dataManager.playerCachingEnabled = settingsSwitch.on;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:[self sectionForPlayer]]
						  withRowAnimation:UITableViewRowAnimationFade];
		});
	}
}

- (void)presentResetAction {
	__weak SRSettingsViewController *weakSelf = self;
	UIAlertController *controller = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Reset", @"Reset")
																		message:NSLocalizedString(@"StationsResetMessage", nil)
																 preferredStyle:UIAlertControllerStyleAlert];
	[controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Reset", @"Reset")
												   style:UIAlertActionStyleDefault
												 handler:^(UIAlertAction * _Nonnull action) {
		[weakSelf performResetAction];
	}]];
	[controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
												   style:UIAlertActionStyleCancel
												 handler:nil]];
	[self presentViewController:controller animated:YES completion:nil];
}

- (void)performResetAction {
	[MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
	__weak SRSettingsViewController *weakSelf = self;
	[[SRDataManager sharedManager] resetStationsWithCompletionHandler:^(NSError *error) {
		[MBProgressHUD hideHUDForView:weakSelf.navigationController.view animated:YES];
		if (error) {
			[weakSelf handleResetError];
		}
	}];
}

#pragma mark - Error handling

- (void)handleResetError {
	__weak SRSettingsViewController *weakSelf = self;
	UIAlertController *controller = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Oops", @"Oops!")
																		message:NSLocalizedString(@"StationsResetFailed", nil)
																 preferredStyle:UIAlertControllerStyleAlert];
	[controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Retry", @"Retry")
												   style:UIAlertActionStyleDefault
												 handler:^(UIAlertAction * _Nonnull action) {
		[weakSelf performResetAction];
	}]];
	[controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Ok")
												   style:UIAlertActionStyleCancel
												 handler:nil]];
	[self presentViewController:controller animated:YES completion:nil];
}

@end
