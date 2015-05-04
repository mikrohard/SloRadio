//
//  SRDataManager.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRDataManager.h"
#import "MBRequest.h"
#import "SRRadioStation.h"

NSString * const SRDataManagerDidLoadStations = @"SRDataManagerDidLoadStations";
NSString * const SRDataManagerDidChangeStations = @"SRDataManagerDidChangeStations";
NSString * const SRDataManagerDidChangeSleepTimerSettings = @"SRDataManagerDidChangeSleepTimerSettings";

static NSInteger const SRDataManagerCustomStationIdOffset = 1000000;
static BOOL const SRDataManagerSleepTimerDefaultEnabled = NO; // disabled by default
static NSTimeInterval const SRDataManagerSleepTimerDefaultInterval = 60*60.0; // 1 hour
static NSTimeInterval const SRDataManagerSleepTimerIntervalStep = 5*60.0; // 5 minutes
static NSTimeInterval const SRDataManagerSleepTimerMaximumInterval = 3*60*60.0; // 3 hours

static NSString * const SRDataManagerStationsApiUrl = @"http://iphone.jernej.org/sloradio/stations.php";
static NSString * const SRDataManagerStationsKey = @"stations";
static NSString * const SRDataManagerStationsIdKey = @"id";
static NSString * const SRDataManagerStationsNameKey = @"name";
static NSString * const SRDataManagerStationsUrlKey = @"url";
static NSString * const SRDataManagerStationsHiddenKey = @"hidden";
static NSString * const SRDataManagerStationsCustomizedKey = @"stations_customized";
static NSString * const SRDataManagerStationsSelectedIdKey = @"selected_station_id";
static NSString * const SRDataManagerSleepTimerIntervalKey = @"SRSleepTimerInterval";
static NSString * const SRDataManagerSleepTimerEnabledKey = @"SRSleepTimerEnabled";

static NSString * const SRLegacyStationPlaylistUrl = @"http://iphone.jernej.org/sloradio/playlist.php";
static NSString * const SRLegacyStationsDictionaryKey = @"postaje";
static NSString * const SRLegacyStationUrlKey = @"naslov";
static NSString * const SRLegacyStationNameKey = @"ime";
static NSString * const SRLegacySleepTimerMinutesKey = @"SleepTime";
static NSString * const SRLegacySleepTimerEnabledKey = @"sleepSwitch";

@interface SRDataManager ()

@property (nonatomic, strong) NSMutableArray *allStations;

@end

@implementation SRDataManager

@synthesize allStations = _allStations;
@synthesize stations = _stations;
@synthesize selectedRadioStation = _selectedRadioStation;
@synthesize sleepTimerInterval = _sleepTimerInterval;
@synthesize selectableSleepTimerIntervals = _selectableSleepTimerIntervals;
@synthesize sleepTimerEnabledByDefault = _sleepTimerEnabledByDefault;

#pragma mark - Singleton

+ (SRDataManager *)sharedManager {
    static SRDataManager *sharedDataManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDataManager = [[self alloc] init];
        [sharedDataManager loadInitialData];
    });
    return sharedDataManager;
}

#pragma mark - Initial load

- (void)loadInitialData {
    [self loadInitialSleepTimerSettings];
    [self loadLocalStations];
}

#pragma mark - Network

- (void)loadStationsWithCompletionHandler:(SRDataManagerCompletionHandler)completion {
    NSURL *url = [NSURL URLWithString:SRDataManagerStationsApiUrl];
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:url];
    MBJSONRequest *jsonRequest = [[MBJSONRequest alloc] init];
    [jsonRequest performJSONRequest:urlRequest completionHandler:^(id responseJSON, NSError *error) {
        if (error != nil) {
            NSLog(@"Error requesting radio stations: %@", error);
        } else {
            NSArray *stations = [responseJSON objectForKey:SRDataManagerStationsKey];
            NSMutableArray *array = [self stationsForArray:stations];
            if (self.allStations.count > 0) {
                [self updateStations:array];
            }
            else {
                [self setupStations:array];
            }
        }
        if (completion) {
            completion(error);
        }
    }];
}

- (void)updateStations:(NSMutableArray *)stations {
    if ([self areStationsCustomized]) {
        // stations are already customized
        NSMutableArray *stationsToRemove = [NSMutableArray array];
        NSMutableArray *allStations = [NSMutableArray arrayWithArray:self.allStations];
        for (SRRadioStation *station in allStations) {
            // leave custom stations as they are
            BOOL isCustomStation = [self isCustomRadioStation:station];
            // leave hidden stations hidden (even if removed)
            BOOL remove = !station.hidden && !isCustomStation;
            for (SRRadioStation *existingStation in stations) {
                if (station.stationId == existingStation.stationId) {
                    // station found... don't remove
                    remove = NO;
                    // update url & name
                    station.name = existingStation.name;
                    station.url = existingStation.url;
                    break;
                }
            }
            if (remove) {
                // if non-hidden (& non custom) stations are removed on remote, remove them locally
                [stationsToRemove addObject:station];
            }
        }
        [allStations removeObjectsInArray:stationsToRemove];
        // add new stations at the end of the list
        NSMutableArray *stationsToAdd = [NSMutableArray array];
        for (SRRadioStation *station in stations) {
            BOOL addStation = YES;
            for (SRRadioStation *existingStation in allStations) {
                if (existingStation.stationId == station.stationId) {
                    // station already in list
                    addStation = NO;
                    break;
                }
            }
            if (addStation) {
                [stationsToAdd addObject:station];
            }
        }
        [allStations addObjectsFromArray:stationsToAdd];
        // set stations
        self.allStations = allStations;
    }
    else {
        // just set new stations array
        self.allStations = stations;
    }
    [self selectInitialRadioStation];
    [[NSNotificationCenter defaultCenter] postNotificationName:SRDataManagerDidLoadStations object:self];
}

- (void)setupStations:(NSMutableArray *)stations {
    self.allStations = stations;
    [self migrateLegacyDataIfNeeded];
    [self selectInitialRadioStation];
    [[NSNotificationCenter defaultCenter] postNotificationName:SRDataManagerDidLoadStations object:self];
}

#pragma mark - Parsing

- (NSMutableArray *)stationsForArray:(NSArray *)stations {
    NSMutableArray *array = [NSMutableArray array];
    for (NSDictionary *stationDict in stations) {
        SRRadioStation *station = [[SRRadioStation alloc] init];
        station.stationId = [[stationDict objectForKey:SRDataManagerStationsIdKey] integerValue];
        station.name = [stationDict objectForKey:SRDataManagerStationsNameKey];
        station.url = [NSURL URLWithString:[stationDict objectForKey:SRDataManagerStationsUrlKey]];
        station.hidden = [[stationDict objectForKey:SRDataManagerStationsHiddenKey] boolValue];
        [array addObject:station];
    }
    return array;
}

- (NSMutableArray *)arrayForStations:(NSArray *)stations {
    NSMutableArray *array = [NSMutableArray array];
    for (SRRadioStation *station in stations) {
        NSMutableDictionary *stationDict = [NSMutableDictionary dictionary];
        [stationDict setObject:@(station.stationId) forKey:SRDataManagerStationsIdKey];
        [stationDict setObject:station.name forKey:SRDataManagerStationsNameKey];
        [stationDict setObject:[station.url absoluteString] forKey:SRDataManagerStationsUrlKey];
        [stationDict setObject:@(station.hidden) forKey:SRDataManagerStationsHiddenKey];
        [array addObject:stationDict];
    }
    return array;
}

#pragma mark - Stations accessors & setters

- (NSMutableArray *)allStations {
    if (!_allStations) {
        _allStations = [NSMutableArray array];
    }
    return _allStations;
}

- (void)setAllStations:(NSMutableArray *)allStations {
    [self.allStations setArray:allStations];
    NSMutableArray *stations = [NSMutableArray array];
    for (SRRadioStation *station in self.allStations) {
        if (!station.hidden) {
            [stations addObject:station];
        }
    }
    _stations = [NSArray arrayWithArray:stations];
    [self saveLocalStations];
}

#pragma mark - Local stations storage

- (void)loadLocalStations {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *localStations = [defaults objectForKey:SRDataManagerStationsKey];
    if (localStations) {
        self.allStations = [self stationsForArray:localStations];
    }
}

- (void)saveLocalStations {
    if (self.allStations.count > 0) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray *localStations = [self arrayForStations:self.allStations];
        [defaults setObject:localStations forKey:SRDataManagerStationsKey];
        [defaults synchronize];
    }
}

- (void)addRadioStation:(SRRadioStation *)station {
    station.stationId = [self nextCustomRadioStationId];
    NSMutableArray *array = [NSMutableArray arrayWithArray:self.allStations];
    [array addObject:station];
    self.allStations = array;
    [self setStationsCustomized:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:SRDataManagerDidChangeStations object:self];
}

- (void)deleteRadioStation:(SRRadioStation *)station {
    BOOL isCustomStation = [self isCustomRadioStation:station];
    NSMutableArray *array = [NSMutableArray arrayWithArray:self.allStations];
    SRRadioStation *stationToDelete = nil;
    for (SRRadioStation *existingStation in array) {
        if (existingStation.stationId == station.stationId) {
            stationToDelete = existingStation;
            break;
        }
    }
    if (isCustomStation) {
        // delete it
        [array removeObject:stationToDelete];
    }
    else {
        // hide it
        stationToDelete.hidden = YES;
    }
    self.allStations = array;
    if (self.selectedRadioStation.stationId == station.stationId) {
        [self selectInitialRadioStation];
    }
    [self setStationsCustomized:YES];
}

- (void)moveRadioStation:(SRRadioStation *)station atIndex:(NSInteger)index {
    NSMutableArray *array = [NSMutableArray arrayWithArray:self.stations];
    SRRadioStation *stationToMove = nil;
    for (SRRadioStation *existingStation in array) {
        if (existingStation.stationId == station.stationId) {
            stationToMove = existingStation;
            break;
        }
    }
    if (stationToMove) {
        [array removeObject:stationToMove];
        [array insertObject:stationToMove atIndex:index];
    }
    // don't forget about hidden stations otherwise they'll get visible again
    NSArray *allStations = [self.allStations copy];
    for (SRRadioStation *hiddenStation in allStations) {
        if (hiddenStation.hidden) {
            [array insertObject:hiddenStation atIndex:[allStations indexOfObject:hiddenStation]];
        }
    }
    self.allStations = array;
    [self setStationsCustomized:YES];
}

- (void)updateRadioStation:(SRRadioStation *)station {
    if ([self isCustomRadioStation:station]) {
        NSMutableArray *array = [NSMutableArray arrayWithArray:self.allStations];
        SRRadioStation *stationToUpdate = nil;
        for (SRRadioStation *existingStation in array) {
            if (existingStation.stationId == station.stationId) {
                stationToUpdate = existingStation;
                break;
            }
        }
        stationToUpdate.name = station.name;
        stationToUpdate.url = station.url;
        self.allStations = array;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRDataManagerDidChangeStations object:self];
    }
}

- (void)setStationsCustomized:(BOOL)customized {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:customized forKey:SRDataManagerStationsCustomizedKey];
    [defaults synchronize];
}

- (BOOL)areStationsCustomized {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:SRDataManagerStationsCustomizedKey];
}

#pragma mark - Custom radio stations

- (NSInteger)nextCustomRadioStationId {
    NSInteger stationId = SRDataManagerCustomStationIdOffset;
    for (SRRadioStation *station in self.allStations) {
        if ([self isCustomRadioStation:station]) {
            stationId = MAX(station.stationId + 1, stationId);
        }
    }
    return stationId;
}

- (BOOL)isCustomRadioStation:(SRRadioStation *)station {
    return station.stationId >= SRDataManagerCustomStationIdOffset;
}

#pragma mark - Selected station

- (void)selectRadioStation:(SRRadioStation *)station {
    _selectedRadioStation = station;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(station.stationId) forKey:SRDataManagerStationsSelectedIdKey];
    [defaults synchronize];
}

- (void)selectInitialRadioStation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger selectedStationId = [[defaults objectForKey:SRDataManagerStationsSelectedIdKey] integerValue];
    SRRadioStation *selectedStation = nil;
    for (SRRadioStation *station in self.stations) {
        if (station.stationId == selectedStationId) {
            selectedStation = station;
            break;
        }
    }
    if (!selectedStation && self.stations.count > 0) {
        selectedStation = self.stations[0];
    }
    [self selectRadioStation:selectedStation];
}

#pragma mark - Sleep timer

- (void)loadInitialSleepTimerSettings {
    if (![self migrateSleepTimerSettingsIfNeeded]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:SRDataManagerSleepTimerEnabledKey]) {
            _sleepTimerEnabledByDefault = [defaults boolForKey:SRDataManagerSleepTimerEnabledKey];
        }
        else {
            _sleepTimerEnabledByDefault = SRDataManagerSleepTimerDefaultEnabled;
        }
        if ([defaults objectForKey:SRDataManagerSleepTimerIntervalKey]) {
            _sleepTimerInterval = [defaults doubleForKey:SRDataManagerSleepTimerIntervalKey];
        }
        else {
            _sleepTimerInterval = SRDataManagerSleepTimerDefaultInterval;
        }
    }
}

- (NSArray *)selectableSleepTimerIntervals {
    if (!_selectableSleepTimerIntervals) {
        NSMutableArray *array = [NSMutableArray array];
        NSTimeInterval intervalStep = SRDataManagerSleepTimerIntervalStep;
        NSTimeInterval maximumInterval = SRDataManagerSleepTimerMaximumInterval;
        NSTimeInterval interval = 0;
        while (interval < maximumInterval) {
            interval += intervalStep;
            [array addObject:@(interval)];
        }
        _selectableSleepTimerIntervals = [NSArray arrayWithArray:array];
    }
    return _selectableSleepTimerIntervals;
}

- (NSUInteger)selectedSleepTimerIntervalIndex {
    return [self.selectableSleepTimerIntervals indexOfObject:@(self.sleepTimerInterval)];
}

- (void)setSleepTimerEnabledByDefault:(BOOL)sleepTimerEnabledByDefault {
    if (sleepTimerEnabledByDefault != _sleepTimerEnabledByDefault) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _sleepTimerEnabledByDefault = sleepTimerEnabledByDefault;
        [defaults setBool:_sleepTimerEnabledByDefault forKey:SRDataManagerSleepTimerEnabledKey];
        [defaults synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:SRDataManagerDidChangeSleepTimerSettings object:nil];
    }
}

- (void)setSleepTimerInterval:(NSTimeInterval)sleepTimerInterval {
    if (sleepTimerInterval != _sleepTimerInterval) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _sleepTimerInterval = sleepTimerInterval;
        [defaults setDouble:_sleepTimerInterval forKey:SRDataManagerSleepTimerIntervalKey];
        [defaults synchronize];
    }
}

#pragma mark - Data migration from old version

- (NSString *)migrationDataPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *plist = [SRLegacyStationsDictionaryKey stringByAppendingPathExtension:@"plist"];
    NSString *bundlePath = [documentsDirectory stringByAppendingPathComponent:plist];
    return bundlePath;
}

- (NSArray *)migrationRadioStations {
    NSString *bundlePath = [self migrationDataPath];
    if([[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        NSDictionary *dict = [[NSDictionary alloc] initWithContentsOfFile:bundlePath];
        return [dict objectForKey:SRLegacyStationsDictionaryKey];
    }
    return nil;
}

- (NSString *)migrationSelectedRadioStationUrl {
    return [[NSUserDefaults standardUserDefaults] objectForKey:SRLegacyStationUrlKey];
}

- (BOOL)shouldStartDataMigration {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self migrationDataPath]];
}

- (void)migrateLegacyDataIfNeeded {
    if ([self shouldStartDataMigration]) {
        NSArray *legacyStations = [self migrationRadioStations];
        NSString *selectedLegacyStationUrl = [self migrationSelectedRadioStationUrl];
        NSString *selectedLegacyStationName = nil;
        SRRadioStation *selectedRadioStation = nil;
        NSMutableArray *stationsToMigrate = [NSMutableArray array];
        for (NSDictionary *stationDict in legacyStations) {
            // get station data
            NSString *stationUrl = [stationDict objectForKey:SRLegacyStationUrlKey];
            NSString *stationName = [stationDict objectForKey:SRLegacyStationNameKey];
            // find selected station name
            if ([selectedLegacyStationUrl isEqualToString:stationUrl]) {
                selectedLegacyStationName = stationName;
            }
            // find stations to migrate (discard all preset stations)
            if (![stationUrl hasPrefix:SRLegacyStationPlaylistUrl]) {
                // custom added radio station... migrate
                SRRadioStation *station = [[SRRadioStation alloc] init];
                station.stationId = SRDataManagerCustomStationIdOffset + stationsToMigrate.count;
                station.name = stationName;
                station.url = [NSURL URLWithString:stationUrl];
                [stationsToMigrate addObject:station];
                if ([selectedLegacyStationUrl isEqualToString:stationUrl]) {
                    // we already have our selected station
                    selectedRadioStation = station;
                }
            }
        }
        if (!selectedRadioStation) {
            // find selected radio station on name basis
            for (SRRadioStation *station in self.stations) {
                if ([selectedLegacyStationName caseInsensitiveCompare:station.name] == NSOrderedSame) {
                    selectedRadioStation = station;
                    break;
                }
            }
        }
        if (stationsToMigrate.count > 0) {
            NSMutableArray *stations = [NSMutableArray arrayWithArray:self.stations];
            [stations insertObjects:stationsToMigrate atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, stationsToMigrate.count)]];
            self.allStations = stations;
            [self setStationsCustomized:YES];
        }
        if (selectedRadioStation) {
            [self selectRadioStation:selectedRadioStation];
        }
        [self finishDataMigration];
    }
}

- (void)finishDataMigration {
    // remove legacy stations file
    NSString *bundlePath = [self migrationDataPath];
    if([[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:bundlePath error:nil];
    }
}

- (BOOL)migrateSleepTimerSettingsIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:SRLegacySleepTimerEnabledKey] ||
        [defaults objectForKey:SRLegacySleepTimerMinutesKey]) {
        double minuteStep = SRDataManagerSleepTimerIntervalStep / 60.0;
        double minutes = minuteStep*round([defaults doubleForKey:SRLegacySleepTimerMinutesKey]/minuteStep);
        BOOL enabled = [defaults boolForKey:SRLegacySleepTimerEnabledKey];
        self.sleepTimerEnabledByDefault = enabled;
        self.sleepTimerInterval = minutes * 60.0;
        [defaults removeObjectForKey:SRLegacySleepTimerEnabledKey];
        [defaults removeObjectForKey:SRLegacySleepTimerMinutesKey];
        [defaults synchronize];
        return YES;
    }
    return NO;
}

@end
