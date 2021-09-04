//
//  SRRadioStation.h
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MPMediaItemArtwork;

extern NSString * const SRRadioStationDidPreloadArtwork;

@interface SRRadioStation : NSObject

@property (nonatomic, assign) NSInteger stationId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSTimeInterval lastModified;
@property (nonatomic, assign) BOOL hidden;

- (MPMediaItemArtwork *)artworkForWidth:(CGFloat)width;
- (MPMediaItemArtwork *)preloadedArtworkForWidth:(CGFloat)width;
- (NSURL *)iconUrlForWidth:(CGFloat)width;

@end
