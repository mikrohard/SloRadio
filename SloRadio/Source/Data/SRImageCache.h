//
//  SRImageCache.h
//  SloRadio
//
//  Created by Jernej Fijačko on 27/08/2021.
//  Copyright © 2021 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SRImageCache : NSObject

+ (SRImageCache *)sharedCache;

+ (NSString *)keyForUrl:(NSURL *)url;

- (void)cacheImage:(UIImage *)image forKey:(NSString *)key;
- (UIImage *)imageForKey:(NSString *)key;

@end
