//
//  SRRadioStation.h
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SRRadioStation : NSObject

@property (nonatomic, assign) NSInteger stationId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSURL *iconUrl;
@property (nonatomic, assign) BOOL hidden;

@end
