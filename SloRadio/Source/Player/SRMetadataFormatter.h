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

// Removes invisible characters some stations send (byte order marks, zero width spaces).
+ (NSString *)cleanedText:(NSString *)text;

// Splits "artist - title" (or "title - artist") text into its two parts. Returns NO when the text has no separator.
// A hyphen without spaces ("TITLE-ARTIST") only separates when it's the only one and both sides have several words,
// so hyphenated names ("Jay-Z", "Spider-Man Theme") aren't split.
+ (BOOL)splitText:(NSString *)text firstPart:(NSString **)firstPart secondPart:(NSString **)secondPart;

// All ways to split text at a hyphen without spaces, as @[first, second] pairs (empty when there's no such hyphen).
// Only safe to use when one of them is confirmed, e.g. by a catalog lookup.
+ (NSArray<NSArray<NSString *> *> *)hyphenSplitsOfText:(NSString *)text;

// Whether the text carries no real information (e.g. "(null)" or a truncated "(n" sent by some streaming servers).
+ (BOOL)isPlaceholderText:(NSString *)text;

// Normalized form used to compare titles regardless of case, accents and punctuation.
+ (NSString *)comparableText:(NSString *)text;

@end
