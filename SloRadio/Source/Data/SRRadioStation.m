//
//  SRRadioStation.m
//  SloRadio
//
//  Created by Jernej Fijačko on 28. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRRadioStation.h"
#import "SRImageCache.h"

@import MediaPlayer;

@implementation SRRadioStation

@synthesize stationId = _stationId;
@synthesize name = _name;
@synthesize url = _url;
@synthesize iconUrl = _iconUrl;
@synthesize hidden = _hidden;
@synthesize artwork = _artwork;

- (MPMediaItemArtwork *)artwork {
	if (@available(iOS 10, *)) {
		if (_artwork == nil) {
			NSURL *iconUrl = self.iconUrl;
			_artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(1024, 1024)
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
	return _artwork;
}

@end
