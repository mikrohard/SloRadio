//
//  SRLeftMenuViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRLeftMenuViewController.h"
#import "SRRadioViewController.h"
#import "AMSlideMenuMainViewController.h"

@interface SRLeftMenuViewController ()

@end

@implementation SRLeftMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"LeftMenuCellIdentifier";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    cell.textLabel.text = @"Radio";
    return cell;
}

#pragma mark - TableView Delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.mainVC.currentActiveNVC) {
        [self.mainVC closeLeftMenu];
    }
    else {
        SRRadioViewController *radioController = [[SRRadioViewController alloc] initWithStyle:UITableViewStylePlain];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:radioController];
        
        [self openContentNavigationController:navigation];
    }
}

@end
