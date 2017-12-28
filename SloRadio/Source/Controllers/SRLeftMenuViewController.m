//
//  SRLeftMenuViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRLeftMenuViewController.h"
#import "SRRadioViewController.h"
#import "SRSettingsViewController.h"
#import "SRAboutViewController.h"
#import "AMSlideMenuMainViewController.h"
#import "UITableView+Separators.h"
#import "UIImage+Color.h"

static NSString * const SRMenuControllersTitleKey = @"SRMenuControllersTitleKey";
static NSString * const SRMenuControllersIconKey = @"SRMenuControllersIconKey";
static NSString * const SRMenuControllersClassKey = @"SRMenuControllersClassKey";
static NSString * const SRMenuControllersCachedKey = @"SRMenuControllersCachedKey";

@interface SRLeftMenuViewController ()

@property (nonatomic, strong) NSArray *controllers;
@property (nonatomic, strong) NSIndexPath *selectedControllerIndexPath;

@end

@implementation SRLeftMenuViewController

@synthesize controllers = _controllers;
@synthesize selectedControllerIndexPath = _selectedControllerIndexPath;

#pragma mark - Lifecycle

- (void)loadView {
    [super loadView];
	CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    self.tableView.backgroundColor = [SRAppearance menuBackgroundColor];
    self.tableView.separatorColor = [SRAppearance menuSeparatorColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1.f, statusBarHeight)];
	self.tableView.tableHeaderView.backgroundColor = [UIColor clearColor];
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1.f, 44.f)];
    self.tableView.tableFooterView.backgroundColor = [UIColor clearColor];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupMenuData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self highlightSelectedController];
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Menu data

- (void)setupMenuData {
    // radio controller
    NSString *radioStations = NSLocalizedString(@"RadioStations", @"Radio Stations");
    NSMutableDictionary *radioController = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                            radioStations, SRMenuControllersTitleKey,
                                            [UIImage imageNamed:@"Radio"], SRMenuControllersIconKey,
                                            [SRRadioViewController class], SRMenuControllersClassKey, nil];
    // settings controller
    NSString *settings = NSLocalizedString(@"Settings", @"Settings");
    NSMutableDictionary *settingsController = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                               settings, SRMenuControllersTitleKey,
                                               [UIImage imageNamed:@"Settings"], SRMenuControllersIconKey,
                                               [SRSettingsViewController class], SRMenuControllersClassKey, nil];
    // about controller
    NSString *about = NSLocalizedString(@"About", @"About");
    NSMutableDictionary *aboutController = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                            about, SRMenuControllersTitleKey,
                                            [UIImage imageNamed:@"Info"], SRMenuControllersIconKey,
                                            [SRAboutViewController class], SRMenuControllersClassKey, nil];
    self.controllers = @[radioController, settingsController, aboutController];
}

- (UIViewController *)controllerForIndexPath:(NSIndexPath *)indexPath {
    NSMutableDictionary *controllerDict = [self.controllers objectAtIndex:indexPath.row];
    UIViewController *controller = [controllerDict objectForKey:SRMenuControllersCachedKey];
    if (!controller) {
        Class controllerClass = [controllerDict objectForKey:SRMenuControllersClassKey];
        controller = [[controllerClass alloc] init];
        [controllerDict setObject:controller forKey:SRMenuControllersCachedKey];
    }
    return controller;
}

- (void)highlightSelectedController {
    [self.tableView selectRowAtIndexPath:self.selectedControllerIndexPath
                                animated:NO
                          scrollPosition:UITableViewScrollPositionNone];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    return self.controllers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"LeftMenuCellIdentifier";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
        cell.selectedBackgroundView.backgroundColor = [UIColor clearColor];
    }
    cell.textLabel.textColor = [SRAppearance menuContentColor];
    cell.textLabel.highlightedTextColor = [SRAppearance mainColor];
    UIImage *icon = [[self.controllers objectAtIndex:indexPath.row] objectForKey:SRMenuControllersIconKey];
    cell.imageView.image = [icon imageWithColor:[SRAppearance menuContentColor]];
    cell.imageView.highlightedImage = [icon imageWithColor:[SRAppearance mainColor]];
    cell.textLabel.text = [[self.controllers objectAtIndex:indexPath.row] objectForKey:SRMenuControllersTitleKey];
    return cell;
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath *selectedPath = [self selectedControllerIndexPath];
    if (selectedPath && selectedPath.row == indexPath.row) {
        [self.mainVC closeLeftMenu];
    }
    else {
        UIViewController *controller = [self controllerForIndexPath:indexPath];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
        [navigation.navigationBar setBarTintColor:[SRAppearance mainColor]];
        [navigation.navigationBar setTintColor:[SRAppearance navigationBarContentColor]];
        [navigation.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName: [SRAppearance navigationBarContentColor]}];
        [self openContentNavigationController:navigation];
        self.selectedControllerIndexPath = indexPath;
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView configureSeparatorForCell:cell];
}

@end
