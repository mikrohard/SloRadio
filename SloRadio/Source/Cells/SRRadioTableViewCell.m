//
//  SRRadioTableViewCell.m
//  SloRadio
//
//  Created by Jernej Fijačko on 2. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioTableViewCell.h"

@implementation SRRadioTableViewCell

#pragma mark - Lifecycle

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.shouldIgnoreTouchesAtLeftScreenEdge = YES;
    }
    return self;
}

@end
