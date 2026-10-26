//
//  SRMetadataFormatterTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 26. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SRMetadataFormatter.h"

@interface SRMetadataFormatterTests : XCTestCase

@end

@implementation SRMetadataFormatterTests

- (void)assertText:(NSString *)text first:(NSString *)expectedFirst second:(NSString *)expectedSecond {
	NSString *first = nil;
	NSString *second = nil;
	BOOL split = [SRMetadataFormatter splitText:text firstPart:&first secondPart:&second];
	XCTAssertEqual(split, expectedFirst != nil, @"%@", text);
	XCTAssertEqualObjects(first, expectedFirst);
	XCTAssertEqualObjects(second, expectedSecond);
}

- (void)testSplitText {
	[self assertText:@"ED SHEERAN - SAPPHIRE" first:@"ED SHEERAN" second:@"SAPPHIRE"];
	[self assertText:@"B.B.& Q BAND  - ON THE BEAT" first:@"B.B.& Q BAND" second:@"ON THE BEAT"];
	// some stations separate the parts with a slash
	[self assertText:@"MORCHEEBA / ROME WASN'T BUILT IN A DAY" first:@"MORCHEEBA" second:@"ROME WASN'T BUILT IN A DAY"];
	// a slash inside the artist or the title isn't a separator
	[self assertText:@"QUEEN/FREDDIE MERCURY - A KIND OF MAGIC" first:@"QUEEN/FREDDIE MERCURY" second:@"A KIND OF MAGIC"];
	[self assertText:@"Queen - We Will Rock You / We Are the Champions" first:@"Queen" second:@"We Will Rock You / We Are the Champions"];
	[self assertText:@"Slovenska oddaja Radia Vatikan" first:nil second:nil];
	[self assertText:@"zz" first:nil second:nil];
}

- (void)testComparableText {
	XCTAssertEqualObjects([SRMetadataFormatter comparableText:@"Tinkara Kovač"], @"tinkarakovac");
	XCTAssertEqualObjects([SRMetadataFormatter comparableText:@"Simon & Garfunkel"], @"simonandgarfunkel");
	// stylized letters inside names
	XCTAssertEqualObjects([SRMetadataFormatter comparableText:@"P!nk"], [SRMetadataFormatter comparableText:@"PINK"]);
	XCTAssertEqualObjects([SRMetadataFormatter comparableText:@"Ke$ha"], @"kesha");
	XCTAssertEqualObjects([SRMetadataFormatter comparableText:@"Wham!"], @"wham");
	XCTAssertEqualObjects([SRMetadataFormatter comparableText:nil], @"");
}

@end
