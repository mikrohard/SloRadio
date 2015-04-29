//
//  SRDataManager.h
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const SRDataManagerDidLoadStations;

@class SRRadioStation;

@interface SRDataManager : NSObject

@property (nonatomic, readonly) NSArray *stations;
@property (nonatomic, readonly) SRRadioStation *selectedRadioStation;

+ (SRDataManager *)sharedManager;

- (void)selectRadioStation:(SRRadioStation *)station;
- (void)loadStations;

@end
