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
// lookup key -> @[first, second, artwork url] (NSNull for missing values)
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
		completion([self valueOrNil:cached[0]], [self valueOrNil:cached[1]], [self valueOrNil:cached[2]]);
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
	NSArray *result = match ?: @[[NSNull null], [NSNull null], [NSNull null]];
	// network errors and rate limiting are not cached, so the lookup is retried for the next metadata update
	if (cacheable) {
		[self.cache setObject:result forKey:key];
	}
	NSArray *completions = self.pendingCompletions[key];
	[self.pendingCompletions removeObjectForKey:key];
	for (SRTrackLookupCompletion completion in completions) {
		completion([self valueOrNil:result[0]], [self valueOrNil:result[1]], [self valueOrNil:result[2]]);
	}
}

- (id)valueOrNil:(id)value {
	return value == [NSNull null] ? nil : value;
}

#pragma mark - Matching

- (NSArray *)matchForFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart inResults:(NSArray *)results {
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
		// stations use both "artist - title" and "title - artist"
		NSArray *match = [self matchArtist:firstPart title:secondPart artistName:artistName trackName:trackName];
		if (match) {
			return @[match[0], match[1], artworkURL];
		}
		match = [self matchArtist:secondPart title:firstPart artistName:artistName trackName:trackName];
		if (match) {
			return @[match[1], match[0], artworkURL];
		}
	}
	return nil;
}

// returns @[artist, title] with the corrected spelling (NSNull for parts that can't be corrected), nil if not a match
- (NSArray *)matchArtist:(NSString *)artist title:(NSString *)title artistName:(NSString *)artistName trackName:(NSString *)trackName {
	NSString *comparableArtist = [SRMetadataFormatter comparableText:artist];
	NSString *comparableArtistName = [SRMetadataFormatter comparableText:artistName];
	if (comparableArtist.length == 0 || comparableArtistName.length == 0) {
		return nil;
	}
	// the catalog lists collaborations as one artist ("Artist & Other"), so a prefix match is enough to identify the song
	BOOL artistMatches = [comparableArtist isEqualToString:comparableArtistName];
	if (!artistMatches && MIN(comparableArtist.length, comparableArtistName.length) >= 3) {
		artistMatches = [comparableArtistName hasPrefix:comparableArtist] || [comparableArtist hasPrefix:comparableArtistName];
	}
	if (!artistMatches) {
		return nil;
	}
	id correctedArtist = [comparableArtist isEqualToString:comparableArtistName] ? artistName : [NSNull null];

	id correctedTitle = nil;
	if ([[SRMetadataFormatter comparableText:title] isEqualToString:[SRMetadataFormatter comparableText:trackName]]) {
		correctedTitle = trackName;
	} else {
		// compare without version suffixes, e.g. "Title (Radio Edit)" or "Title - Remastered 2011"
		NSString *titleBase = [self baseOfTitle:title];
		NSString *trackBase = [self baseOfTitle:trackName];
		NSString *comparableTitleBase = [SRMetadataFormatter comparableText:titleBase];
		if (comparableTitleBase.length == 0 || ![comparableTitleBase isEqualToString:[SRMetadataFormatter comparableText:trackBase]]) {
			return nil;
		}
		// keep our version suffix (with its leading separator), only fix its letter case
		NSString *titleSuffix = [title substringFromIndex:titleBase.length];
		NSString *trimmedSuffix = [titleSuffix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *separator = trimmedSuffix.length ? [titleSuffix substringToIndex:[titleSuffix rangeOfString:trimmedSuffix].location] : @"";
		correctedTitle = [NSString stringWithFormat:@"%@%@%@", trackBase, separator, [SRMetadataFormatter formattedText:trimmedSuffix]];
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
