//
//  SRStreamResolver.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRStreamResolver.h"

static NSTimeInterval const SRStreamResolverTimeout = 10.0;
// enough to recognize any format, audio streams are cut off here
static NSUInteger const SRStreamResolverSniffLength = 4096;
// station playlists are tiny, anything bigger is cut off
static NSUInteger const SRStreamResolverMaxPlaylistLength = 256 * 1024;
// playlist in playlist in playlist
static NSUInteger const SRStreamResolverMaxDepth = 3;

@interface SRStreamResolver () <NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) SRStreamResolverCompletion completion;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSURL *taskURL;
@property (nonatomic, assign) NSUInteger depth;
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL cancelled;

@end

@implementation SRStreamResolver

- (instancetype)initWithURL:(NSURL *)url {
	self = [super init];
	if (self) {
		_url = url;
	}
	return self;
}

- (void)resolveWithCompletion:(SRStreamResolverCompletion)completion {
	self.completion = completion;
	[self resolveURL:self.url depth:0];
}

- (void)cancel {
	self.cancelled = YES;
	self.finished = YES;
	self.completion = nil;
	[self.session invalidateAndCancel];
	self.session = nil;
	self.task = nil;
}

#pragma mark - Resolving

- (void)resolveURL:(NSURL *)url depth:(NSUInteger)depth {
	NSString *scheme = url.scheme.lowercaseString;
	if (depth > SRStreamResolverMaxDepth || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
		// other protocols are left to the playback engine
		[self finishWithURL:url format:SRStreamFormatAudio];
		return;
	}
	if ([url.path.pathExtension.lowercaseString isEqualToString:@"m3u8"]) {
		// no need to download anything
		[self finishWithURL:url format:SRStreamFormatHLS];
		return;
	}
	if (!self.session) {
		NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
		configuration.timeoutIntervalForRequest = SRStreamResolverTimeout;
		self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[NSOperationQueue mainQueue]];
	}
	self.taskURL = url;
	self.depth = depth;
	self.data = [NSMutableData data];
	self.mimeType = nil;
	self.task = [self.session dataTaskWithURL:url];
	[self.task resume];
}

- (void)finishWithURL:(NSURL *)url format:(SRStreamFormat)format {
	if (self.finished) {
		return;
	}
	self.finished = YES;
	[self.task cancel];
	self.task = nil;
	[self.session invalidateAndCancel];
	self.session = nil;
	SRStreamResolverCompletion completion = self.completion;
	self.completion = nil;
	if (completion) {
		// always asynchronous, the caller may still be setting up
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!self.cancelled) {
				completion(url, format);
			}
		});
	}
}

- (void)handleData:(BOOL)complete {
	SRStreamFormat format = [SRStreamResolver formatForData:self.data mimeType:self.mimeType];
	switch (format) {
		case SRStreamFormatAudio:
		case SRStreamFormatHLS:
			[self finishWithURL:self.taskURL format:format];
			break;
		case SRStreamFormatHTML:
			// probably an error page, let the playback engine try and report it
			[self finishWithURL:self.taskURL format:SRStreamFormatAudio];
			break;
		case SRStreamFormatPLS:
		case SRStreamFormatM3U:
		case SRStreamFormatASX:
		case SRStreamFormatXSPF:
			if (complete || self.data.length >= SRStreamResolverMaxPlaylistLength) {
				NSURL *baseURL = self.task.response.URL ?: self.taskURL;
				NSURL *entry = [SRStreamResolver entriesInPlaylistData:self.data format:format baseURL:baseURL].firstObject;
				if (entry) {
					[self.task cancel];
					[self resolveURL:entry depth:self.depth + 1];
				} else {
					[self finishWithURL:self.taskURL format:SRStreamFormatAudio];
				}
			}
			break;
	}
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
	if (dataTask != self.task || self.finished) {
		completionHandler(NSURLSessionResponseCancel);
		return;
	}
	NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 200;
	if (statusCode >= 400 || [SRStreamResolver isAudioMimeType:response.MIMEType]) {
		// errors are reported by the playback engine
		completionHandler(NSURLSessionResponseCancel);
		[self finishWithURL:self.taskURL format:SRStreamFormatAudio];
		return;
	}
	self.mimeType = response.MIMEType;
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
	if (dataTask != self.task || self.finished) {
		return;
	}
	[self.data appendData:data];
	if (self.data.length >= SRStreamResolverSniffLength) {
		[self handleData:NO];
	}
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
	if (task != self.task || self.finished) {
		return;
	}
	if (error && self.data.length == 0) {
		[self finishWithURL:self.taskURL format:SRStreamFormatAudio];
		return;
	}
	[self handleData:YES];
}

#pragma mark - Classification

+ (BOOL)isAudioMimeType:(NSString *)mimeType {
	NSString *type = mimeType.lowercaseString;
	if (type.length == 0) {
		return NO;
	}
	for (NSString *playlistMarker in @[@"mpegurl", @"scpls", @"x-ms-wax", @"x-ms-asx", @"xspf"]) {
		if ([type containsString:playlistMarker]) {
			return NO;
		}
	}
	return [type hasPrefix:@"audio/"] || [type isEqualToString:@"application/ogg"] || [type isEqualToString:@"video/mp2t"];
}

+ (SRStreamFormat)formatForData:(NSData *)data mimeType:(NSString *)mimeType {
	NSUInteger length = MIN(data.length, SRStreamResolverSniffLength);
	// Latin-1 maps every byte to a character, so binary data never fails to decode
	NSString *text = [[NSString alloc] initWithBytes:data.bytes length:length encoding:NSISOLatin1StringEncoding] ?: @"";
	NSString *bom = @"\u00EF\u00BB\u00BF";
	if ([text hasPrefix:bom]) {
		text = [text substringFromIndex:bom.length];
	}
	text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *lower = text.lowercaseString;
	NSString *head = lower.length > 1024 ? [lower substringToIndex:1024] : lower;

	if ([text hasPrefix:@"ICY "]) {
		// Shoutcast v1 response, URLSession passes its header block on as data
		return SRStreamFormatAudio;
	}
	if ([text hasPrefix:@"#EXTM3U"]) {
		return [text containsString:@"#EXT-X-"] ? SRStreamFormatHLS : SRStreamFormatM3U;
	}
	if ([lower hasPrefix:@"[playlist]"] || [lower hasPrefix:@"file1="] || [head containsString:@"\nfile1="]) {
		return SRStreamFormatPLS;
	}
	if ([head containsString:@"<asx"]) {
		return SRStreamFormatASX;
	}
	if ([head containsString:@"<playlist"] && [head containsString:@"xspf"]) {
		return SRStreamFormatXSPF;
	}
	if ([lower hasPrefix:@"<!doctype html"] || [lower hasPrefix:@"<html"]) {
		return SRStreamFormatHTML;
	}
	if ([text hasPrefix:@"#EXT-X-"] && [mimeType.lowercaseString containsString:@"mpegurl"]) {
		// HLS playlist without the #EXTM3U header
		return SRStreamFormatHLS;
	}
	NSRegularExpression *urlLine = [NSRegularExpression regularExpressionWithPattern:@"^(https?|mms|mmsh|rtsp|rtmp)://\\S+\\s*($|\\n|\\r)"
																			 options:NSRegularExpressionCaseInsensitive
																			   error:nil];
	if ([urlLine firstMatchInString:text options:0 range:NSMakeRange(0, MIN(text.length, 2048))]) {
		// bare list of stream URLs
		return SRStreamFormatM3U;
	}
	return SRStreamFormatAudio;
}

+ (NSArray<NSURL *> *)entriesInPlaylistData:(NSData *)data format:(SRStreamFormat)format baseURL:(NSURL *)baseURL {
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text) {
		text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] ?: @"";
	}
	NSMutableArray<NSString *> *strings = [NSMutableArray array];
	switch (format) {
		case SRStreamFormatPLS: {
			NSRegularExpression *expr = [NSRegularExpression regularExpressionWithPattern:@"^\\s*file(\\d+)\\s*=\\s*(\\S.*?)\\s*$"
																				  options:NSRegularExpressionCaseInsensitive | NSRegularExpressionAnchorsMatchLines
																					error:nil];
			NSMutableArray *numbered = [NSMutableArray array];
			for (NSTextCheckingResult *match in [expr matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
				[numbered addObject:@[@([[text substringWithRange:[match rangeAtIndex:1]] integerValue]),
									  [text substringWithRange:[match rangeAtIndex:2]]]];
			}
			[numbered sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
				return [a.firstObject compare:b.firstObject];
			}];
			for (NSArray *entry in numbered) {
				[strings addObject:entry.lastObject];
			}
			break;
		}
		case SRStreamFormatM3U:
			for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
				NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				if (trimmed.length > 0 && ![trimmed hasPrefix:@"#"]) {
					[strings addObject:trimmed];
				}
			}
			break;
		case SRStreamFormatASX:
		case SRStreamFormatXSPF: {
			NSString *pattern = format == SRStreamFormatASX ?
				@"<ref\\s+href\\s*=\\s*[\"']([^\"']+)[\"']" :
				@"<location>\\s*([^<]+?)\\s*</location>";
			NSRegularExpression *expr = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
			for (NSTextCheckingResult *match in [expr matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
				[strings addObject:[self stringByDecodingXMLEntities:[text substringWithRange:[match rangeAtIndex:1]]]];
			}
			break;
		}
		default:
			break;
	}
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	for (NSString *string in strings) {
		NSURL *url = [NSURL URLWithString:string relativeToURL:baseURL];
		if (!url) {
			NSString *escaped = [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
			url = escaped ? [NSURL URLWithString:escaped relativeToURL:baseURL] : nil;
		}
		if (url.absoluteURL.scheme.length > 0) {
			[urls addObject:url.absoluteURL];
		}
	}
	return urls;
}

+ (NSString *)stringByDecodingXMLEntities:(NSString *)string {
	NSDictionary *entities = @{@"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&apos;": @"'"};
	for (NSString *entity in entities) {
		string = [string stringByReplacingOccurrencesOfString:entity withString:entities[entity]];
	}
	// last, so "&amp;lt;" becomes "&lt;"
	return [string stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

@end
