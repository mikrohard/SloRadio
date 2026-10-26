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
NSString * const SRRadioStationDidPreloadArtwork = @"SRRadioStationDidPreloadArtwork";

@import MediaPlayer;

@implementation SRRadioStation

@synthesize stationId = _stationId;
@synthesize name = _name;
@synthesize url = _url;
@synthesize lastModified = _lastModified;
@synthesize hidden = _hidden;

- (MPMediaItemArtwork *)preloadedArtworkForWidth:(CGFloat)width {
    UIImage *image = nil;
	NSURL *iconUrl = [self iconUrlForWidth:width];
	if (iconUrl != nil) {
		if (iconUrl != nil) {
			image = [SRRadioStation cachedArtworkForKey:[SRImageCache keyForUrl:iconUrl]];
			if (!image) {
				[self preloadArtworkForUrl:iconUrl];
			}
		}
	}
    if (!image) {
        image = [UIImage imageNamed:@"PlaceholderArtwork"];
    }
    return [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(width, width) requestHandler:^UIImage * _Nonnull(CGSize size) {
        return image;
    }];
}

- (NSURL *)iconUrlForWidth:(CGFloat)width {
	if (![[SRDataManager sharedManager] isCustomRadioStation:self]) {
		NSString *iconUrl = [NSString stringWithFormat:@"%@?station_id=%ld&width=%.0f&lastModified=%.0f",
							 SRRadioStationIconBaseUrl,
							 (long)self.stationId,
							 width,
							 self.lastModified];
		return [NSURL URLWithString:iconUrl];
	}
	return nil;
}

#pragma mark - Artwork images

- (UIImage *)cachedArtworkImageForWidth:(CGFloat)width {
	NSURL *iconUrl = [self iconUrlForWidth:width];
	if (iconUrl != nil) {
		return [SRRadioStation cachedArtworkForKey:[SRImageCache keyForUrl:iconUrl]];
	}
	return nil;
}

- (void)loadArtworkImageForWidth:(CGFloat)width completion:(void (^)(UIImage *image))completion {
	NSURL *iconUrl = [self iconUrlForWidth:width];
	if (iconUrl == nil) {
		completion(nil);
		return;
	}
	UIImage *cachedImage = [self cachedArtworkImageForWidth:width];
	if (cachedImage != nil) {
		completion(cachedImage);
		return;
	}
	dispatch_async([SRRadioStation preloadQueue], ^{
		NSString *cacheKey = [SRImageCache keyForUrl:iconUrl];
		UIImage *image = [SRRadioStation cachedArtworkForKey:cacheKey];
		if (!image) {
			image = [SRRadioStation squareArtworkForImage:[UIImage imageWithData:[NSData dataWithContentsOfURL:iconUrl]]];
			[[SRImageCache sharedCache] cacheImage:image forKey:cacheKey];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(image);
		});
	});
}

#pragma mark - Square artwork

+ (UIImage *)cachedArtworkForKey:(NSString *)cacheKey {
	UIImage *image = [[SRImageCache sharedCache] imageForKey:cacheKey];
	UIImage *squareImage = [self squareArtworkForImage:image];
	if (squareImage != image) {
		// logos cached by earlier versions weren't square yet
		[[SRImageCache sharedCache] cacheImage:squareImage forKey:cacheKey];
	}
	return squareImage;
}

// Logos that aren't square are scaled to fit a square (artwork is always shown and cropped as a square). The space
// around the logo is filled with the color of the logo's edge, so logos on a solid background look like they were
// made square, and with white when the edge is transparent or not a single color.
+ (UIImage *)squareArtworkForImage:(UIImage *)image {
	CGSize size = image.size;
	if (!image || size.width <= 0 || size.height <= 0 || fabs(size.width - size.height) <= MAX(size.width, size.height) * 0.02) {
		return image;
	}
	CGFloat side = MAX(size.width, size.height);
	UIColor *backgroundColor = [self edgeColorOfImage:image] ?: [UIColor whiteColor];
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.scale = image.scale;
	format.opaque = YES;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[backgroundColor setFill];
		[context fillRect:CGRectMake(0, 0, side, side)];
		[image drawInRect:CGRectMake((side - size.width) / 2, (side - size.height) / 2, size.width, size.height)];
	}];
}

// The average color of the image's outermost pixels, nil if they are mostly transparent or not (nearly) a single color.
+ (UIColor *)edgeColorOfImage:(UIImage *)image {
	CGImageRef cgImage = image.CGImage;
	if (!cgImage) {
		return nil;
	}
	// a small copy is enough to sample the edges
	CGFloat scale = MIN(1.0, 64.0 / MAX(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)));
	size_t width = MAX((size_t)1, (size_t)round(CGImageGetWidth(cgImage) * scale));
	size_t height = MAX((size_t)1, (size_t)round(CGImageGetHeight(cgImage) * scale));
	NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(colorSpace);
	if (!context) {
		return nil;
	}
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
	CGContextRelease(context);

	const uint8_t *bytes = pixels.bytes;
	NSUInteger total = 0;
	NSUInteger opaque = 0;
	double sums[3] = {0, 0, 0};
	double squares[3] = {0, 0, 0};
	for (size_t y = 0; y < height; y++) {
		for (size_t x = 0; x < width; x++) {
			if (x != 0 && y != 0 && x != width - 1 && y != height - 1) {
				continue;
			}
			const uint8_t *pixel = bytes + (y * width + x) * 4;
			total++;
			if (pixel[3] < 200) {
				continue;
			}
			opaque++;
			for (int channel = 0; channel < 3; channel++) {
				// undo the (small) premultiplication of nearly opaque pixels
				double value = pixel[channel] * 255.0 / pixel[3];
				sums[channel] += value;
				squares[channel] += value * value;
			}
		}
	}
	if (opaque == 0 || opaque < total * 0.6) {
		return nil;
	}
	double variance = 0;
	double means[3];
	for (int channel = 0; channel < 3; channel++) {
		means[channel] = sums[channel] / opaque;
		variance += squares[channel] / opaque - means[channel] * means[channel];
	}
	if (variance > 600) {
		return nil;
	}
	return [UIColor colorWithRed:means[0] / 255.0 green:means[1] / 255.0 blue:means[2] / 255.0 alpha:1.0];
}

#pragma mark - Artwork preload

+ (dispatch_queue_t)preloadQueue {
	static dispatch_queue_t preloadQueue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		preloadQueue = dispatch_queue_create("org.jernej.sloradio.artworkPreload", NULL);
	});
	return preloadQueue;
}

- (void)preloadArtworkForUrl:(NSURL *)iconUrl {
	if (iconUrl != nil) {
		dispatch_async([SRRadioStation preloadQueue], ^{
			NSString *cacheKey = [SRImageCache keyForUrl:iconUrl];
			UIImage *image = [SRRadioStation cachedArtworkForKey:cacheKey];
			if (!image) {
				image = [SRRadioStation squareArtworkForImage:[UIImage imageWithData:[NSData dataWithContentsOfURL:iconUrl]]];
				[[SRImageCache sharedCache] cacheImage:image forKey:cacheKey];
			}
			[[NSNotificationCenter defaultCenter] postNotificationName:SRRadioStationDidPreloadArtwork object:self];
		});
	}
}


@end
