//
//  SRMetadataDecoderTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SRMetadataDecoder.h"
#import "SRICYParser.h"

@interface SRMetadataDecoderTests : XCTestCase

@end

@implementation SRMetadataDecoderTests

- (NSData *)hex:(NSString *)hex {
	NSMutableData *data = [NSMutableData data];
	for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
		uint8_t byte = (uint8_t)strtoul([[hex substringWithRange:NSMakeRange(i, 2)] UTF8String], NULL, 16);
		[data appendBytes:&byte length:1];
	}
	return data;
}

- (NSData *)bytes:(const char *)bytes {
	return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

#pragma mark - Charsets

- (void)testRealWindows1250Titles {
	// bytes sent by the stations during the station inventory
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self hex:@"4d6f6472696a616e69202d20537265e861206a652076206e616a75"]],
						  @"Modrijani - Sreča je v naju");	// Radio Tomi
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self hex:@"416c656b73616e646572204a659e202d208a74616a6572736b69206d6978"]],
						  @"Aleksander Jež - Štajerski mix");	// Radio Sloven'c
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self hex:@"564c41444f204b5245534c494e202d2044616e206e65736b6f6ee86e69682073616e6a"]],
						  @"VLADO KRESLIN - Dan neskončnih sanj");	// Retro Radio
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self hex:@"4d61726a616e61204465729e616a202d204272657a61206d6f6a65206d6c61646f737469"]],
						  @"Marjana Deržaj - Breza moje mladosti");	// Retro Radio
}

- (void)testUTF8 {
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[@"Ivica Šerfezi - Marija Elena" dataUsingEncoding:NSUTF8StringEncoding]], @"Ivica Šerfezi - Marija Elena");
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[@"ELEVEN HOLD - NŐ MEG A BOR" dataUsingEncoding:NSUTF8StringEncoding]], @"ELEVEN HOLD - NŐ MEG A BOR");
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self bytes:"ABBA - HASTA MANANA"]], @"ABBA - HASTA MANANA");
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[NSData data]], @"");
}

- (void)testISOLatin2 {
	// š and ž have different codes in ISO-8859-2 than in Windows-1250
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self bytes:"Ko\xB9ir - \xBEivljenje"]], @"Košir - življenje");
}

- (void)testWesternEuropean {
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self bytes:"El Ni\xF1o - Se\xF1ora"]], @"El Niño - Señora");
	XCTAssertEqualObjects([SRMetadataDecoder stringFromData:[self bytes:"Beyonc\xE9 - Halo"]], @"Beyoncé - Halo");
}

#pragma mark - ICY fields

- (void)assertFields:(const char *)block expected:(NSDictionary *)expected {
	XCTAssertEqualObjects([SRMetadataDecoder fieldsFromICYMetadata:[self bytes:block]], expected, @"%s", block);
}

- (void)testICYFields {
	[self assertFields:"StreamTitle='Shania Twain - When you kiss me';" expected:@{@"StreamTitle": @"Shania Twain - When you kiss me"}];
	[self assertFields:"StreamTitle='EDITORS - SERIOUSLY';StreamUrl='';" expected:@{@"StreamTitle": @"EDITORS - SERIOUSLY", @"StreamUrl": @""}];
	[self assertFields:"StreamTitle='';" expected:@{@"StreamTitle": @""}];
	[self assertFields:"  StreamTitle='X';  " expected:@{@"StreamTitle": @"X"}];
	[self assertFields:"" expected:@{}];
}

- (void)testICYFieldsWithApostrophes {
	[self assertFields:"StreamTitle='SALT'N'PEPA - LET'S TALK ABOUT SEX';" expected:@{@"StreamTitle": @"SALT'N'PEPA - LET'S TALK ABOUT SEX"}];
	[self assertFields:"StreamTitle='Gary GLITTER - I'm The Leader';StreamUrl='http://x/';"
			  expected:@{@"StreamTitle": @"Gary GLITTER - I'm The Leader", @"StreamUrl": @"http://x/"}];
	// "';" inside the value but not followed by another field
	[self assertFields:"StreamTitle='a';b';" expected:@{@"StreamTitle": @"a';b"}];
}

- (void)testTruncatedICYField {
	[self assertFields:"StreamTitle='Truncated title" expected:@{@"StreamTitle": @"Truncated title"}];
	[self assertFields:"StreamTitle='(n" expected:@{@"StreamTitle": @"(n"}];
}

- (void)testICYFieldCharsets {
	// the value is decoded on its own
	NSMutableData *block = [[self bytes:"StreamTitle='"] mutableCopy];
	[block appendData:[self hex:@"416c656b73616e646572204a659e202d208a74616a6572736b69206d6978"]];
	[block appendData:[self bytes:"';"]];
	XCTAssertEqualObjects([SRMetadataDecoder fieldsFromICYMetadata:block][@"StreamTitle"], @"Aleksander Jež - Štajerski mix");
	NSData *utf8 = [@"StreamTitle='Črna mačka - Zorica';" dataUsingEncoding:NSUTF8StringEncoding];
	XCTAssertEqualObjects([SRMetadataDecoder fieldsFromICYMetadata:utf8][@"StreamTitle"], @"Črna mačka - Zorica");
}

@end
