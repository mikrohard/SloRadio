//
//  SRSettingsViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 4. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRSettingsViewController.h"
#import "SRSettingsPickerCell.h"
#import "SRDataManager.h"
#import "UIAlertView+Blocks.h"
#import "MBProgressHUD.h"

@interface SRSettingsViewController () <UIPickerViewDataSource, UIPickerViewDelegate>

@property (nonatomic, strong) UISwitch *sleepTimerSwitch;

@end

@implementation SRSettingsViewController

@synthesize sleepTimerSwitch = _sleepTimerSwitch;

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = @"Settings";
    }
    return self;
}

- (void)loadView {
    [super loadView];
    [self setupSleepTimerSwitch];
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Setup

- (void)setupSleepTimerSwitch {
    UISwitch *settingsSwitch = [[UISwitch alloc] init];
    settingsSwitch.onTintColor = [SRAppearance mainColor];
    [settingsSwitch addTarget:self action:@selector(sleepTimerEnabledChanged:) forControlEvents:UIControlEventValueChanged];
    self.sleepTimerSwitch = settingsSwitch;
}

#pragma mark - Section handling

- (NSInteger)sectionForSleepTimer {
    return 0;
}

- (NSInteger)sectionForReset {
    return 1;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    if (section == [self sectionForSleepTimer]) {
        return 2;
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
    else {
        static NSString *cellIdentifier = @"SettingsCell";
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        }
        if (indexPath.section == [self sectionForReset]) {
            // reset cell
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.textColor = [SRAppearance mainColor];
            cell.textLabel.text = @"Reset";
            cell.accessoryView = nil;
        }
        else {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.textColor = [SRAppearance textColor];
            cell.textLabel.text = @"Enabled";
            cell.accessoryView = indexPath.row == 0 ? self.sleepTimerSwitch : nil;
            self.sleepTimerSwitch.on = [[SRDataManager sharedManager] sleepTimerEnabledByDefault];
        }
        return cell;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == [self sectionForSleepTimer]) {
        return @"Sleep timer";
    }
    else if (section == [self sectionForReset]) {
        return NSLocalizedString(@"RadioStations", @"Radio Stations");
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
    NSString *title = [NSString stringWithFormat:@"%.0f minutes", interval/60.0];
    return title;
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    SRDataManager *dataManager = [SRDataManager sharedManager];
    NSTimeInterval interval = [[dataManager.selectableSleepTimerIntervals objectAtIndex:row] doubleValue];
    dataManager.sleepTimerInterval = interval;
}

#pragma mark - Settings actions

- (void)sleepTimerEnabledChanged:(UISwitch *)settingsSwitch {
    SRDataManager *dataManager = [SRDataManager sharedManager];
    dataManager.sleepTimerEnabledByDefault = settingsSwitch.on;
}

- (void)presentResetAction {
    __weak SRSettingsViewController *weakSelf = self;
    [UIAlertView showWithTitle:@"Warning"
                       message:@"This action is going to remove all custom radio stations."
             cancelButtonTitle:@"Cancel"
             otherButtonTitles:@[NSLocalizedString(@"Retry", @"Retry")]
                      tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                          if (alertView.cancelButtonIndex != buttonIndex) {
                              [weakSelf performResetAction];
                          }
                      }];
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
    [UIAlertView showWithTitle:NSLocalizedString(@"Oops", @"Oops!")
                       message:@"Could not reset radio stations."
             cancelButtonTitle:NSLocalizedString(@"Ok", @"Ok")
             otherButtonTitles:@[NSLocalizedString(@"Retry", @"Retry")]
                      tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                          if (alertView.cancelButtonIndex != buttonIndex) {
                              [weakSelf performResetAction];
                          }
                      }];
}

@end
