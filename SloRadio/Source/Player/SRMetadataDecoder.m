//
//  SRMetadataDecoder.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRMetadataDecoder.h"

@implementation SRMetadataDecoder

+ (NSString *)stringFromData:(NSData *)data {
	if (data.length == 0) {
		return @"";
	}
	NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (utf8) {
		return utf8;
	}
	// Score the candidate 8-bit encodings by the letters they produce. Slovenian stations mostly use Windows-1250,
	// so it wins ties (č in Windows-1250 is è in Windows-1252, for example).
	NSCharacterSet *centralEuropean = [NSCharacterSet characterSetWithCharactersInString:@"čšžćđČŠŽĆĐ"];
	NSCharacterSet *western = [NSCharacterSet characterSetWithCharactersInString:@"àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝß"];
	NSString *best = nil;
	NSInteger bestScore = NSIntegerMin;
	NSArray *encodings = @[@(NSWindowsCP1250StringEncoding), @(NSISOLatin2StringEncoding), @(NSWindowsCP1252StringEncoding), @(NSISOLatin1StringEncoding)];
	for (NSNumber *encoding in encodings) {
		NSString *string = [[NSString alloc] initWithData:data encoding:encoding.unsignedIntegerValue];
		if (!string) {
			continue;
		}
		NSInteger score = 0;
		BOOL isWestern = encoding.unsignedIntegerValue == NSWindowsCP1252StringEncoding || encoding.unsignedIntegerValue == NSISOLatin1StringEncoding;
		for (NSUInteger i = 0; i < string.length; i++) {
			unichar c = [string characterAtIndex:i];
			if ([centralEuropean characterIsMember:c] && !isWestern) {
				score += 2;
			} else if ([western characterIsMember:c]) {
				score += 1;
			} else if (c < 0x20 || (c >= 0x7F && c < 0xA0)) {
				// control characters mean the encoding is wrong
				score -= 3;
			}
		}
		if (score > bestScore) {
			best = string;
			bestScore = score;
		}
	}
	return best ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

+ (NSDictionary<NSString *, NSString *> *)fieldsFromICYMetadata:(NSData *)data {
	// work on a Latin-1 view of the bytes (one character per byte) so value bytes can be decoded on their own
	NSString *text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	if (text.length == 0) {
		return @{};
	}
	NSRegularExpression *keyExpr = [NSRegularExpression regularExpressionWithPattern:@"([A-Za-z_][A-Za-z0-9_]*)='" options:0 error:nil];
	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	NSUInteger position = 0;
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	while (position < text.length) {
		while (position < text.length && [whitespace characterIsMember:[text characterAtIndex:position]]) {
			position++;
		}
		if (position >= text.length) {
			break;
		}
		NSTextCheckingResult *key = [keyExpr firstMatchInString:text options:NSMatchingAnchored range:NSMakeRange(position, text.length - position)];
		if (!key) {
			break;
		}
		NSString *name = [text substringWithRange:[key rangeAtIndex:1]];
		NSUInteger valueStart = NSMaxRange(key.range);
		// the value ends at the first "';" followed by the next key or the end, so apostrophes inside values are kept
		NSUInteger valueEnd = NSNotFound;
		NSUInteger nextPosition = text.length;
		NSUInteger searchFrom = valueStart;
		while (searchFrom < text.length) {
			NSRange terminator = [text rangeOfString:@"';" options:0 range:NSMakeRange(searchFrom, text.length - searchFrom)];
			if (terminator.location == NSNotFound) {
				break;
			}
			NSUInteger after = NSMaxRange(terminator);
			NSString *rest = [[text substringFromIndex:after] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if (rest.length == 0 || [keyExpr firstMatchInString:text options:NSMatchingAnchored range:NSMakeRange(after, text.length - after)]) {
				valueEnd = terminator.location;
				nextPosition = after;
				break;
			}
			searchFrom = terminator.location + 1;
		}
		if (valueEnd == NSNotFound) {
			// unterminated (truncated) value: take the rest without a trailing quote
			valueEnd = text.length;
			while (valueEnd > valueStart && ([text characterAtIndex:valueEnd - 1] == '\'' || [text characterAtIndex:valueEnd - 1] == ';')) {
				valueEnd--;
			}
		}
		NSData *valueData = [data subdataWithRange:NSMakeRange(valueStart, valueEnd - valueStart)];
		fields[name] = [self stringFromData:valueData];
		position = nextPosition;
	}
	return fields;
}

@end
