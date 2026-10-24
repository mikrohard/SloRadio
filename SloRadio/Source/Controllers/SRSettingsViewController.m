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

typedef NS_ENUM(NSInteger, SRSettingsSection) {
	SRSettingsSectionSleepTimer,
	SRSettingsSectionPlayer,
	SRSettingsSectionStations,
	SRSettingsSectionCount,
};

static NSInteger const SRSleepTimerEnabledRow = 0;
static NSInteger const SRSleepTimerDurationRow = 1;
static NSInteger const SRSleepTimerPickerRow = 2;

static NSString * const SRSettingsCellIdentifier = @"SettingsCell";
static NSString * const SRPickerCellIdentifier = @"SettingsPickerCell";
static NSString * const SRSliderCellIdentifier = @"SliderCell";

@interface SRSettingsViewController () <UIPickerViewDataSource, UIPickerViewDelegate, SRSliderTableViewCellProtocol>

@property (nonatomic, assign) BOOL durationPickerVisible;

@end

@implementation SRSettingsViewController

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		self.title = NSLocalizedString(@"Settings", @"Settings");
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:SRSettingsCellIdentifier];
	[self.tableView registerClass:[SRSettingsPickerCell class] forCellReuseIdentifier:SRPickerCellIdentifier];
	[self.tableView registerClass:[SRSliderTableViewCell class] forCellReuseIdentifier:SRSliderCellIdentifier];
}

#pragma mark - Settings switches

- (UISwitch *)switchWithValue:(BOOL)value action:(SEL)action {
	UISwitch *settingsSwitch = [[UISwitch alloc] init];
	settingsSwitch.onTintColor = [SRAppearance mainColor];
	settingsSwitch.on = value;
	[settingsSwitch addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	return settingsSwitch;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return SRSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case SRSettingsSectionSleepTimer:
			return self.durationPickerVisible ? 3 : 2;
		case SRSettingsSectionPlayer:
			return [SRDataManager sharedManager].playerCachingEnabled ? 2 : 1;
		case SRSettingsSectionStations:
			return 1;
		default:
			return 0;
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	if (indexPath.section == SRSettingsSectionSleepTimer && indexPath.row == SRSleepTimerPickerRow) {
		SRSettingsPickerCell *cell = [tableView dequeueReusableCellWithIdentifier:SRPickerCellIdentifier forIndexPath:indexPath];
		cell.pickerView.dataSource = self;
		cell.pickerView.delegate = self;
		[cell.pickerView reloadAllComponents];
		NSUInteger selectedRow = dataManager.selectedSleepTimerIntervalIndex;
		if (selectedRow != NSNotFound) {
			[cell.pickerView selectRow:selectedRow inComponent:0 animated:NO];
		}
		return cell;
	}
	if (indexPath.section == SRSettingsSectionPlayer && indexPath.row == 1) {
		SRSliderTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SRSliderCellIdentifier forIndexPath:indexPath];
		cell.delegate = self;
		cell.minimumSliderValue = 0.f;
		cell.maximumSliderValue = 60.f;
		cell.sliderValue = dataManager.playerCacheSize;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SRSettingsCellIdentifier forIndexPath:indexPath];
	UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
	cell.accessoryView = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	if (indexPath.section == SRSettingsSectionSleepTimer && indexPath.row == SRSleepTimerEnabledRow) {
		content.text = NSLocalizedString(@"AlwaysOn", @"Always on");
		content.image = [SRAppearance iconWithSymbolName:@"moon.zzz.fill" backgroundColor:[UIColor systemIndigoColor]];
		cell.accessoryView = [self switchWithValue:dataManager.sleepTimerEnabledByDefault action:@selector(sleepTimerEnabledChanged:)];
	}
	else if (indexPath.section == SRSettingsSectionSleepTimer && indexPath.row == SRSleepTimerDurationRow) {
		content.text = NSLocalizedString(@"Duration", @"Duration");
		content.secondaryText = [self titleForSleepTimerInterval:dataManager.sleepTimerInterval];
		content.secondaryTextProperties.color = self.durationPickerVisible ? [SRAppearance mainColor] : [UIColor secondaryLabelColor];
		content.image = [SRAppearance iconWithSymbolName:@"timer" backgroundColor:[UIColor systemIndigoColor]];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	}
	else if (indexPath.section == SRSettingsSectionPlayer) {
		content.text = NSLocalizedString(@"AdditionalCaching", nil);
		content.image = [SRAppearance iconWithSymbolName:@"externaldrive.fill" backgroundColor:[UIColor systemBlueColor]];
		cell.accessoryView = [self switchWithValue:dataManager.playerCachingEnabled action:@selector(playerCachingEnabledChanged:)];
	}
	else if (indexPath.section == SRSettingsSectionStations) {
		content = [UIListContentConfiguration cellConfiguration];
		content.text = NSLocalizedString(@"ResetList", @"Reset list");
		content.textProperties.color = [UIColor systemRedColor];
		content.image = [SRAppearance iconWithSymbolName:@"arrow.counterclockwise" backgroundColor:[UIColor systemRedColor]];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	}
	cell.contentConfiguration = content;
	return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case SRSettingsSectionSleepTimer:
			return NSLocalizedString(@"SleepTimer", @"Sleep timer");
		case SRSettingsSectionPlayer:
			return NSLocalizedString(@"Player", @"Player");
		case SRSettingsSectionStations:
			return NSLocalizedString(@"RadioStations", @"Radio Stations");
		default:
			return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	switch (section) {
		case SRSettingsSectionSleepTimer:
			return NSLocalizedString(@"SleepTimerFooter", nil);
		case SRSettingsSectionPlayer:
			return [SRDataManager sharedManager].playerCachingEnabled ? NSLocalizedString(@"CacheWarning", nil) : nil;
		case SRSettingsSectionStations:
			return NSLocalizedString(@"StationsResetMessage", nil);
		default:
			return nil;
	}
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == SRSettingsSectionSleepTimer && indexPath.row == SRSleepTimerDurationRow) {
		[self toggleDurationPicker];
	}
	else if (indexPath.section == SRSettingsSectionStations) {
		[self presentResetAction];
	}
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)toggleDurationPicker {
	self.durationPickerVisible = !self.durationPickerVisible;
	NSIndexPath *pickerIndexPath = [NSIndexPath indexPathForRow:SRSleepTimerPickerRow inSection:SRSettingsSectionSleepTimer];
	NSIndexPath *durationIndexPath = [NSIndexPath indexPathForRow:SRSleepTimerDurationRow inSection:SRSettingsSectionSleepTimer];
	[self.tableView performBatchUpdates:^{
		if (self.durationPickerVisible) {
			[self.tableView insertRowsAtIndexPaths:@[pickerIndexPath] withRowAnimation:UITableViewRowAnimationFade];
		} else {
			[self.tableView deleteRowsAtIndexPaths:@[pickerIndexPath] withRowAnimation:UITableViewRowAnimationFade];
		}
		[self.tableView reconfigureRowsAtIndexPaths:@[durationIndexPath]];
	} completion:nil];
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
			[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SRSettingsSectionPlayer]
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
												   style:UIAlertActionStyleDestructive
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

#pragma mark - Sleep timer interval

- (NSString *)titleForSleepTimerInterval:(NSTimeInterval)interval {
	return [NSString stringWithFormat:NSLocalizedString(@"NumberOfMinutes", nil), (int)(interval/60.0)];
}

#pragma mark - UIPickerViewDataSource

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
	return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
	return [SRDataManager sharedManager].selectableSleepTimerIntervals.count;
}

#pragma mark - UIPickerViewDelegate

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
	NSTimeInterval interval = [[[SRDataManager sharedManager].selectableSleepTimerIntervals objectAtIndex:row] doubleValue];
	return [self titleForSleepTimerInterval:interval];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	dataManager.sleepTimerInterval = [[dataManager.selectableSleepTimerIntervals objectAtIndex:row] doubleValue];
	NSIndexPath *durationIndexPath = [NSIndexPath indexPathForRow:SRSleepTimerDurationRow inSection:SRSettingsSectionSleepTimer];
	[self.tableView reconfigureRowsAtIndexPaths:@[durationIndexPath]];
}

#pragma mark - SRSliderTableViewCellProtocol

- (void)cell:(SRSliderTableViewCell *)cell didChangeSliderValue:(float)sliderValue {
	[SRDataManager sharedManager].playerCacheSize = sliderValue;
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
