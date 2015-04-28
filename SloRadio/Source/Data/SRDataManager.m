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

@implementation SRDataManager

@synthesize stations = _stations;

#pragma mark - Singleton

+ (SRDataManager *)sharedManager {
    static SRDataManager *sharedDataManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDataManager = [[self alloc] init];
    });
    return sharedDataManager;
}

#pragma mark - Network

- (void)loadStations {
    NSURL *url = [NSURL URLWithString:@"http://iphone.jernej.org/sloradio/stations.php"];
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:url];
    MBJSONRequest *jsonRequest = [[MBJSONRequest alloc] init];
    [jsonRequest performJSONRequest:urlRequest completionHandler:^(id responseJSON, NSError *error) {
        if (error != nil) {
            NSLog(@"Error requesting radio stations: %@", error);
        } else {
            NSArray *stations = [responseJSON objectForKey:@"stations"];
            NSMutableArray *array = [NSMutableArray array];
            for (NSDictionary *stationDict in stations) {
                SRRadioStation *station = [[SRRadioStation alloc] init];
                station.stationId = [[stationDict objectForKey:@"id"] integerValue];
                station.name = [stationDict objectForKey:@"name"];
                station.url = [NSURL URLWithString:[stationDict objectForKey:@"url"]];
                [array addObject:station];
            }
            _stations = [NSArray arrayWithArray:array];
            [[NSNotificationCenter defaultCenter] postNotificationName:SRDataManagerDidLoadStations object:self];
        }
    }];
}

@end
