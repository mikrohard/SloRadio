//
//  SRStreamResolverTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SRStreamResolver.h"

@interface SRStreamResolverTests : XCTestCase

@end

@implementation SRStreamResolverTests

- (NSData *)data:(NSString *)string {
	return [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)bytes:(const uint8_t *)bytes length:(NSUInteger)length {
	return [NSData dataWithBytes:bytes length:length];
}

#pragma mark - Format detection

- (void)testHLS {
	// Radio KAOS master playlist
	NSString *master = @"#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=961288,RESOLUTION=852x480,CODECS=\"avc1.64001f,mp4a.40.2\"\n1_0/index.m3u8?sessId=25807\n";
	XCTAssertEqual([SRStreamResolver formatForData:[self data:master] mimeType:@"application/vnd.apple.mpegurl"], SRStreamFormatHLS);
	NSString *media = @"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:9\n#EXTINF:8.32,\nsegment1.ts\n";
	XCTAssertEqual([SRStreamResolver formatForData:[self data:media] mimeType:nil], SRStreamFormatHLS);
	// header missing, but served as HLS
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"#EXT-X-VERSION:3\n#EXTINF:8,\na.ts\n"] mimeType:@"application/x-mpegURL"], SRStreamFormatHLS);
}

- (void)testM3U {
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"#EXTM3U\n#EXTINF:-1,Radio\nhttp://example.com/stream\n"] mimeType:nil], SRStreamFormatM3U);
	// Radio Študent: a bare URL
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"http://kruljo.radiostudent.si:8000/hiq\n"] mimeType:@"audio/x-mpegurl"], SRStreamFormatM3U);
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"\uFEFFhttp://example.com/a\r\nhttp://example.com/b\r\n"] mimeType:nil], SRStreamFormatM3U);
}

- (void)testPLS {
	// Radio M
	NSString *pls = @"[playlist]\nNumberOfEntries=1\nFile1=http://team-data.ba:8030/;\nTitle1=RADIOM\nLength1=-1\nVersion=2\n";
	XCTAssertEqual([SRStreamResolver formatForData:[self data:pls] mimeType:@"audio/x-scpls"], SRStreamFormatPLS);
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"\n[Playlist]\r\nFile1=http://a/b\r\n"] mimeType:nil], SRStreamFormatPLS);
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"NumberOfEntries=1\nFile1=http://a/b\n"] mimeType:nil], SRStreamFormatPLS);
}

- (void)testASXAndXSPF {
	NSString *asx = @"<ASX version=\"3.0\"><Entry><Ref href=\"http://example.com/stream\" /></Entry></ASX>";
	XCTAssertEqual([SRStreamResolver formatForData:[self data:asx] mimeType:@"video/x-ms-asf"], SRStreamFormatASX);
	NSString *xspf = @"<?xml version=\"1.0\"?><playlist version=\"1\" xmlns=\"http://xspf.org/ns/0/\"><trackList><track><location>http://example.com/stream</location></track></trackList></playlist>";
	XCTAssertEqual([SRStreamResolver formatForData:[self data:xspf] mimeType:@"application/xspf+xml"], SRStreamFormatXSPF);
}

- (void)testHTML {
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"<!DOCTYPE html><html><body>Not found</body></html>"] mimeType:@"text/html"], SRStreamFormatHTML);
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"<html><head></head></html>"] mimeType:nil], SRStreamFormatHTML);
}

- (void)testAudio {
	// STUDIO-S (Shoutcast v1): URLSession passes the ICY header block on as data
	NSString *icy = @"ICY 200 OK\r\nicy-notice1:<BR>This stream requires <a href=\"http://www.winamp.com/\">Winamp</a><BR>\r\nicy-name:STUDIO-S\r\ncontent-type:audio/mpeg\r\nicy-metaint:8192\r\n\r\n";
	XCTAssertEqual([SRStreamResolver formatForData:[self data:icy] mimeType:nil], SRStreamFormatAudio);
	const uint8_t adts[] = {0xFF, 0xF1, 0x4C, 0x80, 0x2E, 0x7F, 0xFC, 0x21, 0x1A, 0x00};
	XCTAssertEqual([SRStreamResolver formatForData:[self bytes:adts length:sizeof(adts)] mimeType:@"application/octet-stream"], SRStreamFormatAudio);
	const uint8_t id3[] = {'I', 'D', '3', 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x23, 0xFF, 0xFB};
	XCTAssertEqual([SRStreamResolver formatForData:[self bytes:id3 length:sizeof(id3)] mimeType:nil], SRStreamFormatAudio);
	XCTAssertEqual([SRStreamResolver formatForData:[self data:@"OggS"] mimeType:nil], SRStreamFormatAudio);
	XCTAssertEqual([SRStreamResolver formatForData:[NSData data] mimeType:nil], SRStreamFormatAudio);
}

- (void)testAudioMimeTypes {
	for (NSString *type in @[@"audio/mpeg", @"audio/aac", @"audio/aacp", @"audio/ogg", @"application/ogg", @"AUDIO/MPEG", @"video/mp2t"]) {
		XCTAssertTrue([SRStreamResolver isAudioMimeType:type], @"%@", type);
	}
	for (NSString *type in @[@"audio/x-mpegurl", @"audio/mpegurl", @"application/vnd.apple.mpegurl", @"audio/x-scpls",
							 @"audio/x-ms-wax", @"text/html", @"application/octet-stream", @""]) {
		XCTAssertFalse([SRStreamResolver isAudioMimeType:type], @"%@", type);
	}
	XCTAssertFalse([SRStreamResolver isAudioMimeType:nil]);
}

#pragma mark - Playlist entries

- (void)assertEntries:(NSString *)playlist format:(SRStreamFormat)format base:(NSString *)base expected:(NSArray<NSString *> *)expected {
	NSArray<NSURL *> *entries = [SRStreamResolver entriesInPlaylistData:[self data:playlist] format:format baseURL:[NSURL URLWithString:base]];
	XCTAssertEqualObjects([entries valueForKey:@"absoluteString"], expected, @"%@", playlist);
}

- (void)testPLSEntries {
	[self assertEntries:@"[playlist]\nNumberOfEntries=1\nFile1=http://team-data.ba:8030/;\nTitle1=RADIOM\nLength1=-1\nVersion=2\n"
				 format:SRStreamFormatPLS base:@"http://team-data.ba:8030/listen.pls?sid=1"
			   expected:@[@"http://team-data.ba:8030/;"]];
	// entries are ordered by their number, whitespace and case vary
	[self assertEntries:@"[playlist]\r\nfile2 = http://backup.example.com/live \r\nFile1=http://main.example.com/live\r\nFILE10=http://ten.example.com/\r\n"
				 format:SRStreamFormatPLS base:@"http://example.com/a.pls"
			   expected:@[@"http://main.example.com/live", @"http://backup.example.com/live", @"http://ten.example.com/"]];
}

- (void)testM3UEntries {
	[self assertEntries:@"http://kruljo.radiostudent.si:8000/hiq\n" format:SRStreamFormatM3U base:@"http://kruljo.radiostudent.si:8000/hiq.m3u"
			   expected:@[@"http://kruljo.radiostudent.si:8000/hiq"]];
	// comments are skipped, relative entries resolved against the playlist
	[self assertEntries:@"#EXTM3U\r\n#EXTINF:-1,Radio\r\n  live.mp3  \r\n\r\nhttps://other.example.com/x\r\n" format:SRStreamFormatM3U base:@"http://example.com/dir/list.m3u"
			   expected:@[@"http://example.com/dir/live.mp3", @"https://other.example.com/x"]];
}

- (void)testXMLEntries {
	[self assertEntries:@"<asx version=\"3.0\"><entry><ref href='http://example.com/a?x=1&amp;y=2'/></entry><entry><REF HREF=\"mms://example.com/b\"/></entry></asx>"
				 format:SRStreamFormatASX base:@"http://example.com/list.asx"
			   expected:@[@"http://example.com/a?x=1&y=2", @"mms://example.com/b"]];
	[self assertEntries:@"<playlist><trackList><track><location> http://example.com/stream?a=1&amp;b=2 </location></track></trackList></playlist>"
				 format:SRStreamFormatXSPF base:@"http://example.com/list.xspf"
			   expected:@[@"http://example.com/stream?a=1&b=2"]];
}

- (void)testEmptyPlaylist {
	[self assertEntries:@"[playlist]\nNumberOfEntries=0\n" format:SRStreamFormatPLS base:@"http://example.com/" expected:@[]];
	[self assertEntries:@"#EXTM3U\n#EXTINF:-1,Nothing\n" format:SRStreamFormatM3U base:@"http://example.com/" expected:@[]];
}

#pragma mark - Resolving without network

- (void)testHLSURLResolvesWithoutNetwork {
	NSURL *url = [NSURL URLWithString:@"https://stream.radiokaos.info:4433/hls/radiokaos/index.m3u8"];
	XCTestExpectation *expectation = [self expectationWithDescription:@"resolved"];
	SRStreamResolver *resolver = [[SRStreamResolver alloc] initWithURL:url];
	[resolver resolveWithCompletion:^(NSURL *resolvedURL, SRStreamFormat format) {
		XCTAssertEqualObjects(resolvedURL, url);
		XCTAssertEqual(format, SRStreamFormatHLS);
		[expectation fulfill];
	}];
	[self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testOtherSchemesAreLeftToTheEngine {
	NSURL *url = [NSURL URLWithString:@"mms://example.com/stream"];
	XCTestExpectation *expectation = [self expectationWithDescription:@"resolved"];
	SRStreamResolver *resolver = [[SRStreamResolver alloc] initWithURL:url];
	[resolver resolveWithCompletion:^(NSURL *resolvedURL, SRStreamFormat format) {
		XCTAssertEqualObjects(resolvedURL, url);
		XCTAssertEqual(format, SRStreamFormatAudio);
		[expectation fulfill];
	}];
	[self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testCancelledResolverNeverCompletes {
	SRStreamResolver *resolver = [[SRStreamResolver alloc] initWithURL:[NSURL URLWithString:@"https://example.com/live.m3u8"]];
	[resolver resolveWithCompletion:^(NSURL *resolvedURL, SRStreamFormat format) {
		XCTFail(@"completion called after cancel");
	}];
	[resolver cancel];
	// the completion is dispatched asynchronously, give it a chance to (wrongly) run
	[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
}

@end
