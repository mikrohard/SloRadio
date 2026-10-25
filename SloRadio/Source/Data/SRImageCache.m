//
//  SRImageCache.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27/08/2021.
//  Copyright © 2021 Jernej Fijačko. All rights reserved.
//

#import "SRImageCache.h"
#import "SRRadioStation.h"
#import "SRDataManager.h"

@interface SRImageCache ()

@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSCache *imageCache;

@end

@implementation SRImageCache

#pragma mark - Singleton

+ (SRImageCache *)sharedCache {
	static SRImageCache *sharedCache;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedCache = [[self alloc] init];
	});
	return sharedCache;
}

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super init];
	if (self) {
		self.imageCache = [[NSCache alloc] init];
		self.fileManager = [[NSFileManager alloc] init];
	}
	return self;
}

#pragma mark - Cache interface

- (void)cacheImage:(UIImage *)image forKey:(NSString *)key {
	if (image && key) {
		[self.imageCache setObject:image forKey:key];
		NSURL *cacheUrl = [[self.fileManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject];
		NSURL *fileUrl = [cacheUrl URLByAppendingPathComponent:key];
		NSString *path = [fileUrl path];
		[self.fileManager createFileAtPath:path contents:UIImagePNGRepresentation(image) attributes:nil];
	}
}

- (UIImage *)imageForKey:(NSString *)key {
	// Try memory cache
	UIImage *image = [self.imageCache objectForKey:key];
	// Try disk cache
	if (!image) {
		NSURL *cacheUrl = [[self.fileManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject];
		NSURL *fileUrl = [cacheUrl URLByAppendingPathComponent:key];
		NSString *path = [fileUrl path];
		if ([self.fileManager fileExistsAtPath:path]) {
			image = [UIImage imageWithContentsOfFile:path];
			if (image) {
				[self.imageCache setObject:image forKey:key];
			}
		}
	}
	return image;
}

- (void)removeImagesFromDiskWithKeysContaining:(NSString *)text {
	NSURL *cacheUrl = [[self.fileManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject];
	NSArray *fileUrls = [self.fileManager contentsOfDirectoryAtURL:cacheUrl includingPropertiesForKeys:nil options:0 error:nil];
	for (NSURL *fileUrl in fileUrls) {
		if ([fileUrl.lastPathComponent containsString:text]) {
			[self.fileManager removeItemAtURL:fileUrl error:nil];
		}
	}
}

+ (NSString *)keyForUrl:(NSURL *)url {
	NSMutableCharacterSet *set = [[NSMutableCharacterSet URLPathAllowedCharacterSet] mutableCopy];
	[set removeCharactersInString:@"/\\;:."];
	return [[url absoluteString] stringByAddingPercentEncodingWithAllowedCharacters:set];
}

@end
