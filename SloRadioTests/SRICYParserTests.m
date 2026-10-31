//
//  SRICYParserTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SRICYParser.h"

@interface SRICYParserTests : XCTestCase

@end

@implementation SRICYParserTests

// Audio bytes 0, 1, 2, ... with a metadata block after every `metaInt` bytes, like an Icecast server sends them.
// Every second block is empty (length byte 0), the others carry "StreamTitle='Song N';" padded to 16 bytes.
- (NSData *)streamWithAudioLength:(NSUInteger)audioLength metaInt:(NSUInteger)metaInt audio:(NSData **)audioOut titles:(NSArray **)titlesOut {
	NSMutableData *stream = [NSMutableData data];
	NSMutableData *audio = [NSMutableData data];
	NSMutableArray *titles = [NSMutableArray array];
	NSUInteger block = 0;
	for (NSUInteger i = 0; i < audioLength; i++) {
		uint8_t byte = (uint8_t)(i * 7);
		[stream appendBytes:&byte length:1];
		[audio appendBytes:&byte length:1];
		if ((i + 1) % metaInt == 0) {
			if (block % 2 == 0) {
				NSString *text = [NSString stringWithFormat:@"StreamTitle='Song %lu';", (unsigned long)block];
				NSMutableData *metadata = [[text dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
				metadata.length = (metadata.length + 15) / 16 * 16;
				uint8_t length = (uint8_t)(metadata.length / 16);
				[stream appendBytes:&length length:1];
				[stream appendData:metadata];
				[titles addObject:@[text, @(i + 1)]];
			} else {
				uint8_t zero = 0;
				[stream appendBytes:&zero length:1];
			}
			block++;
		}
	}
	*audioOut = audio;
	*titlesOut = titles;
	return stream;
}

- (void)assertParsingStream:(NSData *)stream inChunksOf:(NSUInteger)chunkSize metaInt:(NSUInteger)metaInt audio:(NSData *)expectedAudio titles:(NSArray *)expectedTitles {
	SRICYParser *parser = [[SRICYParser alloc] initWithMetaInterval:metaInt];
	NSMutableData *audio = [NSMutableData data];
	NSMutableArray<SRICYMetadataBlock *> *blocks = [NSMutableArray array];
	for (NSUInteger position = 0; position < stream.length; position += chunkSize) {
		NSData *chunk = [stream subdataWithRange:NSMakeRange(position, MIN(chunkSize, stream.length - position))];
		[audio appendData:[parser audioDataByParsingData:chunk metadataBlocks:blocks]];
	}
	XCTAssertEqualObjects(audio, expectedAudio, @"chunk size %lu", (unsigned long)chunkSize);
	XCTAssertEqual(parser.audioOffset, expectedAudio.length);
	XCTAssertEqual(blocks.count, expectedTitles.count, @"chunk size %lu", (unsigned long)chunkSize);
	for (NSUInteger i = 0; i < MIN(blocks.count, expectedTitles.count); i++) {
		NSString *text = [[NSString alloc] initWithData:blocks[i].data encoding:NSASCIIStringEncoding];
		XCTAssertEqualObjects(text, expectedTitles[i][0], @"padding is removed");
		XCTAssertEqual(blocks[i].audioOffset, [expectedTitles[i][1] unsignedLongLongValue]);
	}
}

- (void)testEveryChunkSize {
	NSData *audio = nil;
	NSArray *titles = nil;
	NSData *stream = [self streamWithAudioLength:1000 metaInt:64 audio:&audio titles:&titles];
	XCTAssertEqual(titles.count, 8u);
	// blocks and length bytes split at every possible position
	for (NSUInteger chunkSize = 1; chunkSize <= 150; chunkSize++) {
		[self assertParsingStream:stream inChunksOf:chunkSize metaInt:64 audio:audio titles:titles];
	}
	[self assertParsingStream:stream inChunksOf:stream.length metaInt:64 audio:audio titles:titles];
}

- (void)testRealMetaIntervals {
	for (NSNumber *metaInt in @[@8192, @16000, @16384, @32768]) {
		NSData *audio = nil;
		NSArray *titles = nil;
		NSData *stream = [self streamWithAudioLength:100000 metaInt:metaInt.unsignedIntegerValue audio:&audio titles:&titles];
		[self assertParsingStream:stream inChunksOf:1460 metaInt:metaInt.unsignedIntegerValue audio:audio titles:titles];
	}
}

- (void)testNoMetadata {
	SRICYParser *parser = [[SRICYParser alloc] initWithMetaInterval:0];
	NSMutableArray *blocks = [NSMutableArray array];
	NSData *data = [@"just audio" dataUsingEncoding:NSASCIIStringEncoding];
	XCTAssertEqualObjects([parser audioDataByParsingData:data metadataBlocks:blocks], data);
	XCTAssertEqual(blocks.count, 0u);
	XCTAssertEqual(parser.audioOffset, data.length);
}

#pragma mark - ICY responses

- (void)testICYResponseHeaders {
	// STUDIO-S (Shoutcast v1.9.8)
	NSString *head = @"ICY 200 OK\r\nicy-notice1:<BR>This stream requires <a href=\"http://www.winamp.com/\">Winamp</a><BR>\r\nicy-name:STUDIO-S\r\nicy-genre:Pop\r\ncontent-type:audio/mpeg\r\nicy-pub:1\r\nicy-metaint:8192\r\nicy-br:320\r\n\r\n";
	NSMutableData *data = [[head dataUsingEncoding:NSISOLatin1StringEncoding] mutableCopy];
	[data appendBytes:"\xFF\xFB\x90" length:3];
	XCTAssertTrue([SRICYParser isICYResponseData:data]);
	NSUInteger length = 0;
	NSInteger status = 0;
	NSDictionary *headers = [SRICYParser headersFromICYResponseData:data headerLength:&length statusCode:&status];
	XCTAssertEqual(status, 200);
	XCTAssertEqual(length, head.length);
	XCTAssertEqualObjects(headers[@"icy-metaint"], @"8192");
	XCTAssertEqualObjects(headers[@"icy-name"], @"STUDIO-S");
	XCTAssertEqualObjects(headers[@"content-type"], @"audio/mpeg");
	XCTAssertEqualObjects(headers[@"icy-notice1"], @"<BR>This stream requires <a href=\"http://www.winamp.com/\">Winamp</a><BR>");
}

- (void)testICYResponseWithLineFeedsAndErrors {
	NSData *data = [@"ICY 401 Service Unavailable\nicy-notice1:full\n\n" dataUsingEncoding:NSASCIIStringEncoding];
	NSInteger status = 0;
	NSUInteger length = 0;
	NSDictionary *headers = [SRICYParser headersFromICYResponseData:data headerLength:&length statusCode:&status];
	XCTAssertEqual(status, 401);
	XCTAssertEqual(length, data.length);
	XCTAssertEqualObjects(headers[@"icy-notice1"], @"full");
}

- (void)testIncompleteICYResponse {
	NSData *data = [@"ICY 200 OK\r\nicy-metaint:8192\r\n" dataUsingEncoding:NSASCIIStringEncoding];
	XCTAssertNil([SRICYParser headersFromICYResponseData:data headerLength:NULL statusCode:NULL]);
	XCTAssertFalse([SRICYParser isICYResponseData:[@"HTTP/1.0 200 OK\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding]]);
	XCTAssertFalse([SRICYParser isICYResponseData:[NSData dataWithBytes:"\xFF\xFB" length:2]]);
}

@end
