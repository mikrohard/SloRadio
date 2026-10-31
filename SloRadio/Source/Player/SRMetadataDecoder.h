//
//  SRMetadataDecoder.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

// Turns raw stream metadata bytes into text.
@interface SRMetadataDecoder : NSObject

// Decodes text of unknown encoding: UTF-8 when the bytes are valid UTF-8, otherwise the 8-bit encoding that best fits
// Slovenian and neighbouring languages (Windows-1250, ISO-8859-2 or Windows-1252).
+ (NSString *)stringFromData:(NSData *)data;

// The fields of an ICY metadata block, e.g. "StreamTitle='Artist - Title';StreamUrl='';" gives
// @{@"StreamTitle": @"Artist - Title", @"StreamUrl": @""}. Values may contain apostrophes.
+ (NSDictionary<NSString *, NSString *> *)fieldsFromICYMetadata:(NSData *)data;

@end
