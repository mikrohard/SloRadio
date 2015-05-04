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
extern NSString * const SRDataManagerDidChangeSleepTimerSettings;

typedef void (^SRDataManagerCompletionHandler)(NSError *error);

@class SRRadioStation;

@interface SRDataManager : NSObject

@property (nonatomic, readonly) NSArray *stations;
@property (nonatomic, readonly) SRRadioStation *selectedRadioStation;
@property (nonatomic, readonly) NSArray *selectableSleepTimerIntervals;
@property (nonatomic, readonly) NSUInteger selectedSleepTimerIntervalIndex;
@property (nonatomic, assign) NSTimeInterval sleepTimerInterval;
@property (nonatomic, assign) BOOL sleepTimerEnabledByDefault;

+ (SRDataManager *)sharedManager;

- (void)loadStationsWithCompletionHandler:(SRDataManagerCompletionHandler)completion;

- (void)addRadioStation:(SRRadioStation *)station;
- (void)deleteRadioStation:(SRRadioStation *)station;
- (void)moveRadioStation:(SRRadioStation *)station atIndex:(NSInteger)index;
- (void)updateRadioStation:(SRRadioStation *)station;
- (void)selectRadioStation:(SRRadioStation *)station;

- (BOOL)isCustomRadioStation:(SRRadioStation *)station;

@end
