//
//  SRDataManager.h
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const SRDataManagerDidLoadStations;
extern NSString * const SRDataManagerDidChangeStations;

@class SRRadioStation;

@interface SRDataManager : NSObject

@property (nonatomic, readonly) NSArray *stations;
@property (nonatomic, readonly) SRRadioStation *selectedRadioStation;

+ (SRDataManager *)sharedManager;

- (void)addRadioStation:(SRRadioStation *)station;
- (void)deleteRadioStation:(SRRadioStation *)station;
- (void)moveRadioStation:(SRRadioStation *)station atIndex:(NSInteger)index;
- (void)selectRadioStation:(SRRadioStation *)station;
- (void)loadStations;
- (BOOL)isCustomRadioStation:(SRRadioStation *)station;

@end
