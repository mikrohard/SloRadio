//
//  SRAddRadioViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 30. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAddRadioViewController.h"
#import "SRTextInputCell.h"
#import "SRRadioPlayer.h"
#import "SRDataManager.h"
#import "SRRadioStation.h"
#import "MBProgressHUD.h"
#import "UIAlertView+Blocks.h"

@interface SRAddRadioViewController () <UITextFieldDelegate, SRRadioPlayerDelegate>

@property (nonatomic, strong) SRRadioPlayer *player;
@property (nonatomic, strong) SRRadioStation *station;

@end

@implementation SRAddRadioViewController

@synthesize player = _player;

#pragma mark - Lifecycle

- (instancetype)initEmpty {
    SRRadioStation *station = [[SRRadioStation alloc] init];
    return [self initWithRadioStation:station];
}

- (instancetype)initWithRadioStation:(SRRadioStation *)station {
    self = [self initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.station = station;
        self.title = station.stationId > 0 ? @"Edit station" : @"Add station";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigationButtons];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPlaying];
}

#pragma mark - Setup

- (void)setupNavigationButtons {
    BOOL canEdit = [self canEditStationName] || [self canEditStationUrl];
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:canEdit ? @"Cancel" : @"Close"
                                                                   style:UIBarButtonItemStyleBordered
                                                                  target:self
                                                                  action:@selector(cancelButtonPressed:)];
    self.navigationItem.leftBarButtonItem = cancelItem;
    if (canEdit) {
        UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                                                     style:UIBarButtonItemStyleDone
                                                                    target:self
                                                                    action:@selector(saveButtonPressed:)];
        self.navigationItem.rightBarButtonItem = saveItem;
        [self updateNavigationButtonsEnabledStatus];
    }
}

- (void)updateNavigationButtonsEnabledStatus {
    if ([self canEditStationName] || [self canEditStationUrl]) {
        self.navigationItem.rightBarButtonItem.enabled = [self canTryToSaveRadioStation];
    }
}

#pragma mark - Editing & saving

- (BOOL)canTryToSaveRadioStation {
    return self.station.name.length > 0 && self.station.url.absoluteString.length > 0;
}

- (BOOL)canEditStationName {
    return self.station.stationId == 0 || [[SRDataManager sharedManager] isCustomRadioStation:self.station];
}

- (BOOL)canEditStationUrl {
    return self.station.stationId == 0;
}

#pragma mark - Rows

- (NSIndexPath *)indexPathForRadioName {
    return [NSIndexPath indexPathForRow:0 inSection:0];
}

- (NSIndexPath *)indexPathForRadioUrl {
    return [NSIndexPath indexPathForRow:0 inSection:1];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    return 1;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"TextInputCell";
    SRTextInputCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[SRTextInputCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textInputField.delegate = self;
    }
    if (indexPath.row == [self indexPathForRadioName].row &&
        indexPath.section == [self indexPathForRadioName].section) {
        cell.textInputField.text = self.station.name;
        cell.textInputField.placeholder = @"Insert name";
        cell.textInputField.keyboardType = UIKeyboardTypeDefault;
        cell.textInputField.returnKeyType = [self canEditStationUrl] ? UIReturnKeyNext : UIReturnKeyDone;
        cell.textInputField.autocapitalizationType = UITextAutocapitalizationTypeWords;
        cell.textInputField.enabled = [self canEditStationName];
        cell.textInputField.textColor = [self canEditStationName] ? [SRAppearance textColor] : [SRAppearance disabledTextColor];
    }
    else if (indexPath.row == [self indexPathForRadioUrl].row &&
             indexPath.section == [self indexPathForRadioUrl].section) {
        cell.textInputField.text = self.station.url.absoluteString;
        cell.textInputField.placeholder = @"http://example.com";
        cell.textInputField.keyboardType = UIKeyboardTypeURL;
        cell.textInputField.returnKeyType = UIReturnKeyDone;
        cell.textInputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        cell.textInputField.enabled = [self canEditStationUrl];
        cell.textInputField.textColor = [self canEditStationUrl] ? [SRAppearance textColor] : [SRAppearance disabledTextColor];
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == [self indexPathForRadioName].section) {
        return @"Station name";
    }
    else if (section == [self indexPathForRadioUrl].section) {
        return @"Station address";
    }
    return nil;
}

#pragma mark - Button actions

- (void)cancelButtonPressed:(id)sender {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:NULL];
}

- (void)saveButtonPressed:(id)sender {
    if ([self canEditStationUrl]) {
        SRTextInputCell *urlCell = (SRTextInputCell *)[self.tableView cellForRowAtIndexPath:[self indexPathForRadioUrl]];
        NSString *urlString = urlCell.textInputField.text;
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [self playStreamAtUrl:url];
        }
    }
    else {
        [[SRDataManager sharedManager] updateRadioStation:self.station];
        [self cancelButtonPressed:nil];
    }
}

#pragma mark - Player

- (void)playStreamAtUrl:(NSURL *)url {
    if (!self.player) {
        self.player = [[SRRadioPlayer alloc] init];
    }
    self.player.delegate = self;
    [self.player playStreamAtUrl:url];
    [self showProgressHUD];
}

- (void)stopPlaying {
    self.player.delegate = nil;
    [self.player stop];
    self.player = nil;
}

#pragma mark - Progress HUD

- (void)showProgressHUD {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    hud.dimBackground = YES;
}

- (void)hideProgressHUD {
    [MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    SRTextInputCell *nameCell = (SRTextInputCell *)[self.tableView cellForRowAtIndexPath:[self indexPathForRadioName]];
    SRTextInputCell *urlCell = (SRTextInputCell *)[self.tableView cellForRowAtIndexPath:[self indexPathForRadioUrl]];
    NSString *changedString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    if (textField == nameCell.textInputField) {
        self.station.name = changedString;
    }
    else if (textField == urlCell.textInputField) {
        self.station.url = [NSURL URLWithString:changedString];
    }
    [self updateNavigationButtonsEnabledStatus];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    SRTextInputCell *nameCell = (SRTextInputCell *)[self.tableView cellForRowAtIndexPath:[self indexPathForRadioName]];
    SRTextInputCell *urlCell = (SRTextInputCell *)[self.tableView cellForRowAtIndexPath:[self indexPathForRadioUrl]];
    if (textField == nameCell.textInputField) {
        // name cell returned... go to next cell
        if ([self canEditStationUrl]) {
            [urlCell.textInputField becomeFirstResponder];
        }
        else if ([self canTryToSaveRadioStation]) {
            [self saveButtonPressed:nil];
        }
        [textField resignFirstResponder];
    }
    else if (textField == urlCell.textInputField) {
        if ([self canTryToSaveRadioStation]) {
            [self saveButtonPressed:nil];
        }
        [textField resignFirstResponder];
    }
    return YES;
}

#pragma mark - SRRadioPlayerDelegate

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state {
    if (state == SRRadioPlayerStatePlaying) {
        [[SRDataManager sharedManager] addRadioStation:self.station];
        [self hideProgressHUD];
        __weak SRAddRadioViewController *weakSelf = self;
        [self showAlertWithTitle:@"Success"
                         message:@"Station successfully added"
                 dismissCallback:^{
                     [weakSelf.presentingViewController dismissViewControllerAnimated:YES completion:NULL];
                 }];
    }
    else if (state == SRRadioPlayerStateError || state == SRRadioPlayerStateStopped) {
        [self stopPlaying];
        [self hideProgressHUD];
        [self showAlertWithTitle:@"Oops!"
                         message:@"Could not add station"
                 dismissCallback:NULL];
    }
}

#pragma mark - Alert

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message dismissCallback:(dispatch_block_t)callback {
    [UIAlertView showWithTitle:title
                       message:message
             cancelButtonTitle:@"OK"
             otherButtonTitles:nil
                      tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                          if (callback) {
                              callback();
                          }
                      }];
}

@end
