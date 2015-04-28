//
//  SRDataManager.h
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const SRDataManagerDidLoadStations;

@interface SRDataManager : NSObject

@property (nonatomic, readonly) NSArray *stations;

+ (SRDataManager *)sharedManager;
- (void)loadStations;

@end
