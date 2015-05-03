//
//  SRMainViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRMainViewController.h"
#import "SRLeftMenuViewController.h"

@interface SRMainViewController ()

@end

@implementation SRMainViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [self setupMenus];
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Setup

- (void)setupMenus {
    self.leftMenu = [[SRLeftMenuViewController alloc] initWithStyle:UITableViewStylePlain];
}

- (void)configureLeftMenuButton:(UIButton *)button {
    UIImage *menuIcon = [[UIImage imageNamed:@"MenuIcon"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    CGRect frame = button.frame;
    frame.origin = CGPointMake(0, 0);
    frame.size = menuIcon.size;
    button.frame = frame;
    [button setImage:menuIcon forState:UIControlStateNormal];
}

- (BOOL)deepnessForLeftMenu {
    return YES;
}

#pragma mark - Status bar

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

@end
