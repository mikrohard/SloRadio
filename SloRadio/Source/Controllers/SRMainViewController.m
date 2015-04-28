//
//  SRMainViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRMainViewController.h"
#import "SRRadioPlayer.h"

@interface SRMainViewController () {
    SRRadioPlayer *_player;
}

@end

@implementation SRMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    NSURL *url = [NSURL URLWithString:@"http://iphone.jernej.org/sloradio/playlist.php?radio=radio_student"];
    _player = [[SRRadioPlayer alloc] init];
    [_player playStreamAtUrl:url];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
