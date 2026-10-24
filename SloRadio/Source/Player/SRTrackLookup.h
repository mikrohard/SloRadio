//
//  SRTrackLookup.h
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

// Corrected spelling of the two parts of an "artist - title" (or "title - artist") pair, in the order they were given.
// A part is nil when no better spelling was found. The artwork URL points to the matched song's album art
// (nil when the song wasn't found).
typedef void (^SRTrackLookupCompletion)(NSString *firstPart, NSString *secondPart, NSURL *artworkURL);

// Looks up the canonical spelling of a song in the iTunes catalog (iTunes Search API).
@interface SRTrackLookup : NSObject

+ (SRTrackLookup *)sharedLookup;

// The completion handler is always called on the main queue. Only exact matches (ignoring case, accents and
// punctuation) are used, so a lookup never replaces a song with a different one.
- (void)lookupFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart completion:(SRTrackLookupCompletion)completion;

@end
