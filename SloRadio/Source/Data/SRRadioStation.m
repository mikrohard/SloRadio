//
//  SRRadioStation.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioStation.h"
#import "SRImageCache.h"
#import "SRDataManager.h"

static NSString * const SRRadioStationIconBaseUrl = @"https://iphone.jernej.org/sloradio/icon.php";

@import MediaPlayer;

@implementation SRRadioStation

@synthesize stationId = _stationId;
@synthesize name = _name;
@synthesize url = _url;
@synthesize lastModified = _lastModified;
@synthesize hidden = _hidden;

- (MPMediaItemArtwork *)artworkForWidth:(CGFloat)width {
	if (@available(iOS 10, *)) {
		NSURL *iconUrl = [self iconUrlForWidth:width];
		if (iconUrl != nil) {
			return [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(width, width)
												   requestHandler:^UIImage * _Nonnull(CGSize size) {
				UIImage *image = nil;
				if (iconUrl != nil) {
					NSString *cacheKey = [SRImageCache keyForUrl:iconUrl];
					image = [[SRImageCache sharedCache] imageForKey:cacheKey];
					if (!image) {
						image = [UIImage imageWithData:[NSData dataWithContentsOfURL:iconUrl]];
						[[SRImageCache sharedCache] cacheImage:image forKey:cacheKey];
					}
				}
				if (!image) {
					image = [UIImage imageNamed:@"PlaceholderArtwork"];
				}
				return image;
			}];
		}
	}
	return nil;
}

- (MPMediaItemArtwork *)preloadedArtworkForWidth:(CGFloat)width {
	NSURL *iconUrl = [self iconUrlForWidth:width];
	if (iconUrl != nil) {
		UIImage *image = nil;
		if (iconUrl != nil) {
			NSString *cacheKey = [SRImageCache keyForUrl:iconUrl];
			image = [[SRImageCache sharedCache] imageForKey:cacheKey];
		}
		if (!image) {
			image = [UIImage imageNamed:@"PlaceholderArtwork"];
		}
		return [[MPMediaItemArtwork alloc] initWithImage:image];
	}
	return nil;
}

- (NSURL *)iconUrlForWidth:(CGFloat)width {
	if (![[SRDataManager sharedManager] isCustomRadioStation:self]) {
		NSString *iconUrl = [NSString stringWithFormat:@"%@?station_id=%ld&width=%.0f&lastModified=%.0f",
							 SRRadioStationIconBaseUrl,
							 self.stationId,
							 width,
							 self.lastModified];
		return [NSURL URLWithString:iconUrl];
	}
	return nil;
}

@end
