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
extern NSString * const SRDataManagerDidSelectStation;
extern NSString * const SRDataManagerDidChangeFavorites;
extern NSString * const SRDataManagerDidChangeStationList;

typedef NS_ENUM(NSInteger, SRStationList) {
	SRStationListAll = 0,
	SRStationListFavorites = 1,
};

typedef void (^SRDataManagerCompletionHandler)(NSError *error);

@class SRRadioStation;

@interface SRDataManager : NSObject

@property (nonatomic, readonly) NSArray *stations;
@property (nonatomic, readonly) NSArray *favoriteStations;
@property (nonatomic, readonly) SRRadioStation *selectedRadioStation;
@property (nonatomic, assign) SRStationList selectedStationList;
@property (nonatomic, readonly) NSArray *selectableSleepTimerIntervals;
@property (nonatomic, readonly) NSUInteger selectedSleepTimerIntervalIndex;
@property (nonatomic, assign) NSTimeInterval sleepTimerInterval;
@property (nonatomic, assign) BOOL sleepTimerEnabledByDefault;
@property (nonatomic, assign) NSTimeInterval playerCacheSize;
@property (nonatomic, assign) BOOL playerCachingEnabled;
// app volume (0 - 1), used on the Mac where apps have their own volume
@property (nonatomic, assign) float playerVolume;

+ (SRDataManager *)sharedManager;

- (void)loadStationsWithCompletionHandler:(SRDataManagerCompletionHandler)completion;
- (void)resetStationsWithCompletionHandler:(SRDataManagerCompletionHandler)completion;

- (void)addRadioStation:(SRRadioStation *)station;
- (void)deleteRadioStation:(SRRadioStation *)station;
- (void)moveRadioStation:(SRRadioStation *)station atIndex:(NSInteger)index;
- (void)updateRadioStation:(SRRadioStation *)station;
- (void)selectRadioStation:(SRRadioStation *)station;

- (BOOL)isCustomRadioStation:(SRRadioStation *)station;

- (NSArray *)stationsForList:(SRStationList)list;
- (BOOL)isFavoriteRadioStation:(SRRadioStation *)station;
- (void)addFavoriteRadioStation:(SRRadioStation *)station;
- (void)removeFavoriteRadioStation:(SRRadioStation *)station;
- (void)moveFavoriteRadioStation:(SRRadioStation *)station atIndex:(NSInteger)index;
- (void)setFavoriteRadioStations:(NSArray *)stations;

@end
