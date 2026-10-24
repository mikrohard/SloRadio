//
//  SRMetadataFormatter.h
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

// Cleans up the letter case of stream metadata (artist / song titles)
@interface SRMetadataFormatter : NSObject

// Returns a title cased version of all caps or all lowercase text. Mixed case text is returned unchanged.
+ (NSString *)formattedText:(NSString *)text;

// Whether the text carries no real information (e.g. "(null)" or a truncated "(n" sent by some streaming servers).
+ (BOOL)isPlaceholderText:(NSString *)text;

// Normalized form used to compare titles regardless of case, accents and punctuation.
+ (NSString *)comparableText:(NSString *)text;

@end
