//
//  SRMetadataFormatter.m
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRMetadataFormatter.h"

@implementation SRMetadataFormatter

#pragma mark - Word lists

// words written in lowercase unless they start the text or a part of it (English, Slovenian, Croatian/Serbian)
+ (NSSet *)smallWords {
	static NSSet *smallWords;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		smallWords = [NSSet setWithArray:@[@"a", @"an", @"the", @"and", @"but", @"or", @"nor", @"for", @"of", @"on", @"at", @"to",
										   @"by", @"in", @"from", @"with", @"as", @"into", @"via",
										   @"na", @"v", @"z", @"s", @"za", @"od", @"do", @"pri", @"po", @"ob", @"iz", @"k", @"h",
										   @"ki", @"ko", @"da", @"je", @"se", @"ter", @"pa", @"u", @"o", @"sa", @"uz"]];
	});
	return smallWords;
}

// words with a fixed spelling
+ (NSDictionary *)fixedWords {
	static NSDictionary *fixedWords;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		fixedWords = @{
			@"feat": @"feat", @"feat.": @"feat.", @"ft": @"ft", @"ft.": @"ft.", @"vs": @"vs", @"vs.": @"vs.", @"x": @"x",
			@"dj": @"DJ", @"mc": @"MC", @"ac/dc": @"AC/DC", @"abba": @"ABBA", @"ub40": @"UB40", @"r&b": @"R&B",
			@"rnb": @"RnB", @"edm": @"EDM", @"usa": @"USA", @"uk": @"UK", @"tv": @"TV", @"fm": @"FM", @"ok": @"OK",
			@"lsd": @"LSD", @"inxs": @"INXS", @"r.e.m.": @"R.E.M.", @"nsync": @"NSYNC", @"bts": @"BTS", @"ii": @"II",
			@"iii": @"III", @"iv": @"IV", @"vi": @"VI", @"vii": @"VII", @"viii": @"VIII", @"ix": @"IX", @"xx": @"XX",
			@"i": @"I", @"i'm": @"I'm", @"i'll": @"I'll", @"i've": @"I've", @"i'd": @"I'd",
		};
	});
	return fixedWords;
}

#pragma mark - Formatting

+ (NSString *)formattedText:(NSString *)text {
	if (text.length == 0) {
		return text;
	}
	BOOL hasUppercase = [text rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]].location != NSNotFound;
	BOOL hasLowercase = [text rangeOfCharacterFromSet:[NSCharacterSet lowercaseLetterCharacterSet]].location != NSNotFound;
	if (hasUppercase && hasLowercase) {
		// mixed case is (almost always) intentional
		return text;
	}

	NSArray *words = [[text lowercaseString] componentsSeparatedByString:@" "];
	NSMutableArray *formattedWords = [NSMutableArray arrayWithCapacity:words.count];
	BOOL startOfPart = YES;
	for (NSUInteger index = 0; index < words.count; index++) {
		NSString *word = words[index];
		if (word.length == 0) {
			continue;
		}
		BOOL lastWord = index == words.count - 1;
		NSString *formattedWord = [self formattedWord:word capitalizeSmallWords:startOfPart || lastWord];
		[formattedWords addObject:formattedWord];
		// separators and opening brackets start a new part (e.g. "Artist - Title", "Title (Radio Edit)")
		startOfPart = [@[@"-", @"–", @"—", @"/", @"|", @":"] containsObject:word] || [word hasSuffix:@":"];
		if (index + 1 < words.count && [words[index + 1] hasPrefix:@"("]) {
			startOfPart = YES;
		}
	}
	return [formattedWords componentsJoinedByString:@" "];
}

+ (NSString *)formattedWord:(NSString *)word capitalizeSmallWords:(BOOL)capitalizeSmallWords {
	// split leading and trailing punctuation, e.g. "(radio" or "edit)"
	NSCharacterSet *wrapping = [NSCharacterSet characterSetWithCharactersInString:@"([{\"'«»“”‘’,;!?)]}"];
	NSUInteger start = 0;
	NSUInteger end = word.length;
	while (start < end && [wrapping characterIsMember:[word characterAtIndex:start]]) {
		start++;
	}
	while (end > start && [wrapping characterIsMember:[word characterAtIndex:end - 1]]) {
		end--;
	}
	NSString *prefix = [word substringToIndex:start];
	NSString *core = [word substringWithRange:NSMakeRange(start, end - start)];
	NSString *suffix = [word substringFromIndex:end];
	if (core.length == 0) {
		return word;
	}

	NSString *fixedWord = [self fixedWords][core];
	if (fixedWord) {
		return [NSString stringWithFormat:@"%@%@%@", prefix, fixedWord, suffix];
	}
	if (!capitalizeSmallWords && prefix.length == 0 && [[self smallWords] containsObject:core]) {
		return word;
	}
	return [NSString stringWithFormat:@"%@%@%@", prefix, [self capitalizedCore:core], suffix];
}

+ (NSString *)capitalizedCore:(NSString *)core {
	// capitalize every part of hyphenated or slashed words ("hip-hop", "love/hate")
	for (NSString *separator in @[@"-", @"/"]) {
		NSArray *parts = [core componentsSeparatedByString:separator];
		if (parts.count > 1) {
			NSMutableArray *capitalizedParts = [NSMutableArray arrayWithCapacity:parts.count];
			for (NSString *part in parts) {
				[capitalizedParts addObject:[self capitalizedCore:part]];
			}
			return [capitalizedParts componentsJoinedByString:separator];
		}
	}
	if (core.length == 0) {
		return core;
	}
	NSString *capitalized = [[[core substringToIndex:1] uppercaseString] stringByAppendingString:[core substringFromIndex:1]];
	// "o'connor" -> "O'Connor", "mccartney" -> "McCartney"
	if (core.length > 2 && [core hasPrefix:@"o'"]) {
		capitalized = [NSString stringWithFormat:@"O'%@", [self capitalizedCore:[core substringFromIndex:2]]];
	} else if (core.length > 3 && [core hasPrefix:@"mc"]) {
		capitalized = [NSString stringWithFormat:@"Mc%@", [self capitalizedCore:[core substringFromIndex:2]]];
	}
	return capitalized;
}

#pragma mark - Parts

+ (BOOL)splitText:(NSString *)text firstPart:(NSString **)firstPart secondPart:(NSString **)secondPart {
	// most stations use "artist - title", a few "artist / title"
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	for (NSString *separator in @[@" - ", @" / "]) {
		NSRange range = [text rangeOfString:separator];
		if (range.location == NSNotFound) {
			continue;
		}
		NSString *first = [[text substringToIndex:range.location] stringByTrimmingCharactersInSet:whitespace];
		NSString *second = [[text substringFromIndex:NSMaxRange(range)] stringByTrimmingCharactersInSet:whitespace];
		if (first.length == 0 || second.length == 0) {
			continue;
		}
		*firstPart = first;
		*secondPart = second;
		return YES;
	}
	return NO;
}

#pragma mark - Placeholders

+ (BOOL)isPlaceholderText:(NSString *)text {
	NSString *trimmed = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
	// text without at least two letters or digits (e.g. "-", "...", "?")
	if ([self comparableText:trimmed].length < 2) {
		return YES;
	}
	for (NSString *placeholder in @[@"(null)", @"null", @"(none)", @"none", @"unknown", @"n/a", @"undefined"]) {
		if ([trimmed isEqualToString:placeholder]) {
			return YES;
		}
	}
	// servers that truncate a "(null)" title (e.g. "(n" or "(nul")
	if (trimmed.length < @"(null)".length && [@"(null)" hasPrefix:trimmed]) {
		return YES;
	}
	return NO;
}

#pragma mark - Comparing

+ (NSString *)comparableText:(NSString *)text {
	if (text.length == 0) {
		return @"";
	}
	static NSRegularExpression *exclamationExpression;
	static NSRegularExpression *dollarExpression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		exclamationExpression = [NSRegularExpression regularExpressionWithPattern:@"(?<=\\p{L})!(?=\\p{L})" options:0 error:nil];
		dollarExpression = [NSRegularExpression regularExpressionWithPattern:@"(?<=\\p{L})\\$(?=\\p{L})" options:0 error:nil];
	});
	// stylized letters inside names ("P!nk", "Ke$ha")
	text = [exclamationExpression stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"i"];
	text = [dollarExpression stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"s"];
	NSString *folded = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
												 locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	folded = [folded stringByReplacingOccurrencesOfString:@"&" withString:@" and "];
	NSMutableString *result = [NSMutableString stringWithCapacity:folded.length];
	NSCharacterSet *alphanumerics = [NSCharacterSet alphanumericCharacterSet];
	for (NSUInteger index = 0; index < folded.length; index++) {
		unichar character = [folded characterAtIndex:index];
		if ([alphanumerics characterIsMember:character]) {
			[result appendFormat:@"%C", character];
		}
	}
	return [result lowercaseString];
}

@end
