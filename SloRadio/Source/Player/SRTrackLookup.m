//
//  SRTrackLookup.m
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRTrackLookup.h"
#import "SRMetadataFormatter.h"

static NSString * const SRTrackLookupUrl = @"https://itunes.apple.com/search";
static NSString * const SRTrackLookupDefaultCountry = @"SI";
static NSTimeInterval const SRTrackLookupTimeout = 6.0;
static NSUInteger const SRTrackLookupResultLimit = 10;
static NSString * const SRTrackLookupArtworkSize = @"600x600bb";

@interface SRTrackLookup ()

@property (nonatomic, strong) NSURLSession *session;
// lookup key -> @[first, second, artwork url, track url] (NSNull for missing values)
@property (nonatomic, strong) NSCache *cache;
// lookup key -> pending completion handlers
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<SRTrackLookupCompletion> *> *pendingCompletions;

@end

@implementation SRTrackLookup

#pragma mark - Singleton

+ (SRTrackLookup *)sharedLookup {
	static SRTrackLookup *sharedLookup;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedLookup = [[self alloc] init];
	});
	return sharedLookup;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
		configuration.timeoutIntervalForRequest = SRTrackLookupTimeout;
		configuration.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
		self.session = [NSURLSession sessionWithConfiguration:configuration];
		self.cache = [[NSCache alloc] init];
		self.cache.countLimit = 200;
		self.pendingCompletions = [NSMutableDictionary dictionary];
	}
	return self;
}

#pragma mark - Lookup

- (void)lookupFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart completion:(SRTrackLookupCompletion)completion {
	NSString *key = [NSString stringWithFormat:@"%@|%@", [SRMetadataFormatter comparableText:firstPart], [SRMetadataFormatter comparableText:secondPart]];
	NSArray *cached = [self.cache objectForKey:key];
	if (cached) {
		completion([self valueOrNil:cached[0]], [self valueOrNil:cached[1]], [self valueOrNil:cached[2]], [self valueOrNil:cached[3]]);
		return;
	}
	NSMutableArray *completions = self.pendingCompletions[key];
	if (completions) {
		// the same lookup is already running
		[completions addObject:[completion copy]];
		return;
	}
	self.pendingCompletions[key] = [NSMutableArray arrayWithObject:[completion copy]];

	NSURLComponents *components = [NSURLComponents componentsWithString:SRTrackLookupUrl];
	NSString *country = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode] ?: SRTrackLookupDefaultCountry;
	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"term" value:[NSString stringWithFormat:@"%@ %@", firstPart, secondPart]],
		[NSURLQueryItem queryItemWithName:@"media" value:@"music"],
		[NSURLQueryItem queryItemWithName:@"entity" value:@"song"],
		[NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)SRTrackLookupResultLimit]],
		[NSURLQueryItem queryItemWithName:@"country" value:country],
	];
	__weak SRTrackLookup *weakSelf = self;
	[[self.session dataTaskWithURL:components.URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSArray *match = nil;
		BOOL cacheable = NO;
		NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
		if (!error && statusCode == 200 && data) {
			NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if ([json isKindOfClass:[NSDictionary class]]) {
				NSArray *results = json[@"results"];
				match = [weakSelf matchForFirstPart:firstPart secondPart:secondPart inResults:[results isKindOfClass:[NSArray class]] ? results : @[]];
				cacheable = YES;
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf finishLookupWithKey:key match:match cacheable:cacheable];
		});
	}] resume];
}

- (void)finishLookupWithKey:(NSString *)key match:(NSArray *)match cacheable:(BOOL)cacheable {
	NSArray *result = match ?: @[[NSNull null], [NSNull null], [NSNull null], [NSNull null]];
	// network errors and rate limiting are not cached, so the lookup is retried for the next metadata update
	if (cacheable) {
		[self.cache setObject:result forKey:key];
	}
	NSArray *completions = self.pendingCompletions[key];
	[self.pendingCompletions removeObjectForKey:key];
	for (SRTrackLookupCompletion completion in completions) {
		completion([self valueOrNil:result[0]], [self valueOrNil:result[1]], [self valueOrNil:result[2]], [self valueOrNil:result[3]]);
	}
}

- (id)valueOrNil:(id)value {
	return value == [NSNull null] ? nil : value;
}

#pragma mark - Matching

- (NSArray *)matchForFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart inResults:(NSArray *)results {
	// prefer songs by exactly the same artists and then songs with exactly the same title,
	// so a different version (e.g. a remix or a collaboration) doesn't take over the original song
	for (NSNumber *allowMoreArtists in @[@NO, @YES]) {
		for (NSNumber *allowVersionSuffix in @[@NO, @YES]) {
			NSArray *match = [self matchForFirstPart:firstPart secondPart:secondPart inResults:results
									allowMoreArtists:allowMoreArtists.boolValue allowVersionSuffix:allowVersionSuffix.boolValue];
			if (match) {
				return match;
			}
		}
	}
	return nil;
}

- (NSArray *)matchForFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart inResults:(NSArray *)results
			  allowMoreArtists:(BOOL)allowMoreArtists allowVersionSuffix:(BOOL)allowVersionSuffix {
	for (NSDictionary *result in results) {
		if (![result isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NSString *artistName = result[@"artistName"];
		NSString *trackName = result[@"trackName"];
		if (![artistName isKindOfClass:[NSString class]] || ![trackName isKindOfClass:[NSString class]]) {
			continue;
		}
		id artworkURL = [self artworkURLForResult:result] ?: [NSNull null];
		id trackURL = [self trackURLForResult:result] ?: [NSNull null];
		// stations use both "artist - title" and "title - artist"
		NSArray *match = [self matchArtist:firstPart title:secondPart artistName:artistName trackName:trackName
						  allowMoreArtists:allowMoreArtists allowVersionSuffix:allowVersionSuffix];
		if (match) {
			return @[match[0], match[1], artworkURL, trackURL];
		}
		match = [self matchArtist:secondPart title:firstPart artistName:artistName trackName:trackName
				 allowMoreArtists:allowMoreArtists allowVersionSuffix:allowVersionSuffix];
		if (match) {
			return @[match[1], match[0], artworkURL, trackURL];
		}
	}
	return nil;
}

// returns @[artist, title] with the corrected spelling (NSNull for parts that can't be corrected), nil if not a match;
// allowMoreArtists also matches catalog songs with additional artists ("A" vs. "A & B"),
// allowVersionSuffix also matches titles that differ only in a version suffix ("Title" vs. "Title (Remix)")
- (NSArray *)matchArtist:(NSString *)artist title:(NSString *)title artistName:(NSString *)artistName trackName:(NSString *)trackName
		allowMoreArtists:(BOOL)allowMoreArtists allowVersionSuffix:(BOOL)allowVersionSuffix {
	NSString *comparableArtist = [SRMetadataFormatter comparableText:artist];
	NSString *comparableArtistName = [SRMetadataFormatter comparableText:artistName];
	if (comparableArtist.length == 0 || comparableArtistName.length == 0) {
		return nil;
	}
	// collaborations are joined differently ("A & B & C" vs. "A, B & C"), so compare the individual artists
	NSSet *fieldArtists = [self artistsOfText:artist];
	NSSet *catalogFieldArtists = [self artistsOfText:artistName];
	BOOL fieldArtistsEqual = [comparableArtist isEqualToString:comparableArtistName] || [fieldArtists isEqualToSet:catalogFieldArtists];
	if (fieldArtistsEqual) {
		// e.g. "Earth, Wind & Fire" vs. "Earth Wind and Fire"
		fieldArtists = catalogFieldArtists;
	}
	// the catalog lists featured artists in the title ("Title (feat. B)"), stations often in the artist ("A feat. B")
	NSString *featuring = nil;
	NSString *catalogFeaturing = nil;
	NSString *catalogFeaturingSegment = nil;
	NSString *songTitle = [self titleWithoutFeaturing:title featuring:&featuring segment:NULL];
	NSString *catalogTitle = [self titleWithoutFeaturing:trackName featuring:&catalogFeaturing segment:&catalogFeaturingSegment];
	NSSet *catalogFeaturedArtists = catalogFeaturing ? [self artistsOfText:catalogFeaturing] : [NSSet set];
	NSMutableSet *artists = [fieldArtists mutableCopy];
	if (featuring) {
		[artists unionSet:[self artistsOfText:featuring]];
	}
	NSMutableSet *catalogArtists = [catalogFieldArtists mutableCopy];
	[catalogArtists unionSet:catalogFeaturedArtists];
	if (artists.count == 0 || catalogArtists.count == 0) {
		return nil;
	}
	// the catalog lists collaborations as one artist, so the station may leave out featured artists ("A" vs. "A & B"),
	// but a station listing artists the catalog song doesn't have ("A & B" vs. "A") is a different song (e.g. a remix)
	BOOL artistMatches = [artists isEqualToSet:catalogArtists] || (allowMoreArtists && [artists isSubsetOfSet:catalogArtists]);
	if (!artistMatches) {
		return nil;
	}
	id correctedArtist = fieldArtistsEqual ? artistName : [NSNull null];
	// keep the catalog's featured artists in the title, unless the station already shows them in the artist
	BOOL showCatalogFeaturing = catalogFeaturingSegment != nil && ![catalogFeaturedArtists isSubsetOfSet:fieldArtists];

	id correctedTitle = nil;
	if ([[SRMetadataFormatter comparableText:songTitle] isEqualToString:[SRMetadataFormatter comparableText:catalogTitle]]) {
		correctedTitle = showCatalogFeaturing ? trackName : catalogTitle;
	} else if (allowVersionSuffix) {
		// compare without version suffixes, e.g. "Title (Radio Edit)" or "Title - Remastered 2011"
		NSString *titleBase = [self baseOfTitle:songTitle];
		NSString *trackBase = [self baseOfTitle:catalogTitle];
		NSString *comparableTitleBase = [SRMetadataFormatter comparableText:titleBase];
		if (comparableTitleBase.length == 0 || ![comparableTitleBase isEqualToString:[SRMetadataFormatter comparableText:trackBase]]) {
			return nil;
		}
		// keep our version suffix (with its leading separator), only fix its letter case
		NSString *titleSuffix = [songTitle substringFromIndex:titleBase.length];
		NSString *trimmedSuffix = [titleSuffix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *separator = trimmedSuffix.length ? [titleSuffix substringToIndex:[titleSuffix rangeOfString:trimmedSuffix].location] : @"";
		NSString *featuringText = showCatalogFeaturing ? [@" " stringByAppendingString:catalogFeaturingSegment] : @"";
		correctedTitle = [NSString stringWithFormat:@"%@%@%@%@", trackBase, featuringText, separator, [SRMetadataFormatter formattedText:trimmedSuffix]];
	} else {
		return nil;
	}
	return @[correctedArtist, correctedTitle];
}

- (NSURL *)artworkURLForResult:(NSDictionary *)result {
	NSString *artworkUrl = result[@"artworkUrl100"];
	if (![artworkUrl isKindOfClass:[NSString class]] || artworkUrl.length == 0) {
		return nil;
	}
	// the catalog serves other sizes by changing the size in the file name ("100x100bb.jpg")
	NSRegularExpression *sizeExpression = [NSRegularExpression regularExpressionWithPattern:@"\\d+x\\d+bb" options:0 error:nil];
	artworkUrl = [sizeExpression stringByReplacingMatchesInString:artworkUrl options:0 range:NSMakeRange(0, artworkUrl.length) withTemplate:SRTrackLookupArtworkSize];
	return [NSURL URLWithString:artworkUrl];
}

- (NSURL *)trackURLForResult:(NSDictionary *)result {
	NSString *trackUrl = result[@"trackViewUrl"];
	if (![trackUrl isKindOfClass:[NSString class]] || trackUrl.length == 0) {
		return nil;
	}
	return [NSURL URLWithString:trackUrl];
}

// returns the comparable names of the individual artists, e.g. "A, B feat. C" -> {a, b, c}
- (NSSet<NSString *> *)artistsOfText:(NSString *)text {
	static NSRegularExpression *separatorExpression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		separatorExpression = [NSRegularExpression regularExpressionWithPattern:@"\\s*[,&+;/]\\s*|\\s+(?:and|x|with|featuring|feat\\.?|ft\\.?|vs\\.?)\\s+"
																		options:NSRegularExpressionCaseInsensitive
																		  error:nil];
	});
	NSMutableSet *artists = [NSMutableSet set];
	NSUInteger start = 0;
	NSArray<NSTextCheckingResult *> *separators = [separatorExpression matchesInString:text options:0 range:NSMakeRange(0, text.length)];
	for (NSUInteger index = 0; index <= separators.count; index++) {
		NSUInteger end = index < separators.count ? separators[index].range.location : text.length;
		NSString *comparableArtist = [SRMetadataFormatter comparableText:[text substringWithRange:NSMakeRange(start, end - start)]];
		if (comparableArtist.length > 0) {
			[artists addObject:comparableArtist];
		}
		if (index < separators.count) {
			start = NSMaxRange(separators[index].range);
		}
	}
	return artists;
}

// removes the featured artists from a title ("Title (feat. B) [Remix]" -> "Title [Remix]");
// featuring is set to the featured artists ("B") and segment to the removed text ("(feat. B)"), both nil if there are none
- (NSString *)titleWithoutFeaturing:(NSString *)title featuring:(NSString **)featuring segment:(NSString **)segment {
	static NSRegularExpression *featuringExpression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		featuringExpression = [NSRegularExpression regularExpressionWithPattern:@"\\s*[(\\[](?:feat\\.?|ft\\.?|featuring|with)\\s+([^)\\]]+)[)\\]]|\\s+(?:feat\\.|ft\\.|featuring)\\s+(.+?)(?=\\s*[(\\[]|\\s+-\\s|$)"
																		  options:NSRegularExpressionCaseInsensitive
																			error:nil];
	});
	if (featuring) {
		*featuring = nil;
	}
	if (segment) {
		*segment = nil;
	}
	NSTextCheckingResult *result = [featuringExpression firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
	if (!result || result.range.location == 0) {
		return title;
	}
	NSRange artistsRange = [result rangeAtIndex:1].location != NSNotFound ? [result rangeAtIndex:1] : [result rangeAtIndex:2];
	if (featuring) {
		*featuring = [title substringWithRange:artistsRange];
	}
	if (segment) {
		*segment = [[title substringWithRange:result.range] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	}
	return [title stringByReplacingCharactersInRange:result.range withString:@""];
}

- (NSString *)baseOfTitle:(NSString *)title {
	NSUInteger end = title.length;
	for (NSString *separator in @[@" (", @" [", @" - "]) {
		NSRange range = [title rangeOfString:separator];
		if (range.location != NSNotFound && range.location > 0) {
			end = MIN(end, range.location);
		}
	}
	return [title substringToIndex:end];
}

@end
