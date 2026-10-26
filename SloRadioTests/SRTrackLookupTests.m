//
//  SRTrackLookupTests.m
//  SloRadioTests
//
//  Created by Jernej Fijačko on 26. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SRTrackLookup.h"

@interface SRTrackLookup (Testing)

// returns @[artist, title, artwork url, track url] (NSNull for missing values), nil if no result matches
- (NSArray *)matchForFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart inResults:(NSArray *)results;
- (NSString *)searchTermForFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart;
- (NSString *)fallbackSearchTermForFirstPart:(NSString *)firstPart secondPart:(NSString *)secondPart;

@end

// Matching of station metadata against iTunes Search API results. The results are (shortened) real catalog
// responses for titles stations sent, in the order the catalog returned them.
@interface SRTrackLookupTests : XCTestCase

@end

@implementation SRTrackLookupTests

#pragma mark - Helpers

// catalog results ("artist | track"); each result's track url identifies its index
- (NSArray *)resultsWithSongs:(NSArray<NSString *> *)songs {
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:songs.count];
	[songs enumerateObjectsUsingBlock:^(NSString *song, NSUInteger index, BOOL *stop) {
		NSArray *parts = [song componentsSeparatedByString:@" | "];
		[results addObject:@{
			@"artistName": parts[0],
			@"trackName": parts[1],
			@"artworkUrl100": [NSString stringWithFormat:@"https://is1-ssl.mzstatic.com/image/thumb/%lu/100x100bb.jpg", (unsigned long)index],
			@"trackViewUrl": [NSString stringWithFormat:@"https://music.apple.com/si/song/%lu", (unsigned long)index],
		}];
	}];
	return results;
}

- (NSArray *)matchForText:(NSString *)text songs:(NSArray<NSString *> *)songs {
	NSRange separator = [text rangeOfString:@" - "];
	return [[SRTrackLookup sharedLookup] matchForFirstPart:[text substringToIndex:separator.location]
												secondPart:[text substringFromIndex:NSMaxRange(separator)]
												 inResults:[self resultsWithSongs:songs]];
}

// asserts the matched result (by index) and the corrected spelling of both parts in the station's order
// (nil when the station's spelling is kept)
- (void)assertMatch:(NSArray *)match index:(NSUInteger)index first:(NSString *)first second:(NSString *)second {
	XCTAssertNotNil(match);
	XCTAssertEqualObjects([match[3] absoluteString], ([NSString stringWithFormat:@"https://music.apple.com/si/song/%lu", (unsigned long)index]));
	XCTAssertEqualObjects([match[2] absoluteString], ([NSString stringWithFormat:@"https://is1-ssl.mzstatic.com/image/thumb/%lu/600x600bb.jpg", (unsigned long)index]));
	XCTAssertEqualObjects(match[0], first ?: [NSNull null]);
	XCTAssertEqualObjects(match[1], second ?: [NSNull null]);
}

#pragma mark - Exact matches

- (void)testExactSongIsPreferredOverOtherVersions {
	NSArray *match = [self matchForText:@"ED SHEERAN - SAPPHIRE" songs:@[
		@"Ed Sheeran | Sapphire (feat. Arijit Singh)",
		@"Ed Sheeran | Sapphire (Unplugged)",
		@"Ed Sheeran | Sapphire",
	]];
	[self assertMatch:match index:2 first:@"Ed Sheeran" second:@"Sapphire"];
}

- (void)testTitleArtistOrder {
	NSArray *match = [self matchForText:@"A KIND OF MAGIC - QUEEN" songs:@[
		@"Queen | A Kind Of Magic",
	]];
	[self assertMatch:match index:0 first:@"A Kind Of Magic" second:@"Queen"];
}

- (void)testDifferentSongDoesNotMatch {
	NSArray *match = [self matchForText:@"QUEEN - BOHEMIAN RHAPSODY" songs:@[
		@"Queen | A Kind Of Magic",
		@"Queen | Who Wants to Live Forever",
	]];
	XCTAssertNil(match);
	match = [self matchForText:@"NEKI NEOBSTOJEČ IZVAJALEC - PESEM" songs:@[]];
	XCTAssertNil(match);
}

- (void)testLeadingTheIsIgnored {
	NSArray *match = [self matchForText:@"BEATLES - You Can't Do That" songs:@[
		@"The Beatles | You Can't Do That",
		@"The Beatles | You Can't Do That (Live) [Bonus Track]",
	]];
	[self assertMatch:match index:0 first:@"The Beatles" second:@"You Can't Do That"];

	match = [self matchForText:@"B.B.& Q BAND - ON THE BEAT" songs:@[
		@"The B. B. & Q. Band | On the Beat",
		@"The B. B. & Q. Band | On the Beat (87 Bronx Remix)",
	]];
	[self assertMatch:match index:0 first:@"The B. B. & Q. Band" second:@"On the Beat"];

	match = [self matchForText:@"DISTURBED - SOUND OF SILENCE (CYRIL REMIX)" songs:@[
		@"Disturbed | The Sound of Silence (CYRIL Remix)",
		@"Disturbed | The Sound of Silence",
		@"Simon & Garfunkel | The Sound of Silence",
	]];
	[self assertMatch:match index:0 first:@"Disturbed" second:@"The Sound of Silence (CYRIL Remix)"];
}

- (void)testStylizedArtistName {
	NSArray *match = [self matchForText:@"PINK FT. WILLOW SAGE HART - COVER ME IN SUNSHINE" songs:@[
		@"P!nk & Willow Sage Hart | Cover Me In Sunshine",
		@"Tiffany Mason | Cover Me in Sunshine (feat. Pamela Pink)",
	]];
	[self assertMatch:match index:0 first:@"P!nk & Willow Sage Hart" second:@"Cover Me In Sunshine"];
}

- (void)testShortTitleOfTitleWithEllipsis {
	// the station leaves out the second part of the title, the artist's own song is preferred over a cover featuring them
	NSArray *match = [self matchForText:@"IRENE CARA - FLASHDANCE" songs:@[
		@"Ginny Vee | Flashdance (What A Feeling) [feat. Irene Cara]",
		@"Irene Cara | Flashdance...What a Feeling",
		@"Irene Cara | Flashdance...What a Feeling (Extended Remix)",
	]];
	[self assertMatch:match index:1 first:@"Irene Cara" second:@"Flashdance"];
}

- (void)testStationTitleWithoutVersionSuffix {
	NSArray *match = [self matchForText:@"THE FRANK POPP ENSEMBLE - HIP TEENS (DON T WEAR BLUE JEANS)" songs:@[
		@"The Frank Popp Ensemble | Hip Teens Don't Wear Blue Jeans (Original Version)",
		@"The Frank Popp Ensemble | Hip Teens Don't Wear Blue Jeans (Malente's Electroorganic Remix)",
	]];
	[self assertMatch:match index:0 first:@"The Frank Popp Ensemble" second:@"Hip Teens Don't Wear Blue Jeans"];
}

- (void)testArtistSpelledAsOneWord {
	// found by the second search (title and the artist's first word)
	NSArray *match = [self matchForText:@"Fabrizio deAndre - Franziska" songs:@[
		@"Fabrizio De André | Franziska",
		@"Tomislav Ivčić | Franziska",
	]];
	[self assertMatch:match index:0 first:@"Fabrizio De André" second:@"Franziska"];
}

#pragma mark - Collaborations

- (void)testFeaturingWithoutSpace {
	NSArray *match = [self matchForText:@"SANTANA FT.MANA - CORAZON ESPINADO" songs:@[
		@"Santana | Corazón Espinado (feat. Maná)",
	]];
	[self assertMatch:match index:0 first:nil second:@"Corazón Espinado"];
}

- (void)testSpanishAndBetweenArtists {
	NSArray *match = [self matchForText:@"CHINO Y NACHO - MI NINA BONITA" songs:@[
		@"Chino & Nacho | Niña Bonita",
		@"Chino & Nacho | Mi Niña Bonita (En Vivo Desde El Anfiteatro El Hatillo, Caracas-Venezuela/2014)",
	]];
	[self assertMatch:match index:1 first:@"Chino & Nacho" second:@"Mi Niña Bonita"];
}

- (void)testArtistsJoinedWithX {
	NSArray *match = [self matchForText:@"SAMSTONE x AKTIVE - MY FAVOURITE GAME (FT. THE CARDIGANS)" songs:@[
		@"Samstone & Aktive | My Favourite Game (feat. The Cardigans)",
		@"Samstone & Aktive | My Favourite Game (feat. The Cardigans & P Money) [P Money Remix]",
	]];
	[self assertMatch:match index:0 first:@"Samstone & Aktive" second:@"My Favourite Game (feat. The Cardigans)"];
}

- (void)testFeaturedArtistInStationArtist {
	NSArray *match = [self matchForText:@"THE CHAINSMOKERS FT. COLDPLAY - SOMETHING JUST LIKE THIS" songs:@[
		@"The Chainsmokers & Coldplay | Something Just Like This (Alesso Remix)",
		@"Coldplay & The Chainsmokers | Something Just Like This (Tokyo Remix)",
		@"Coldplay | Something Just Like This (Live In Buenos Aires)",
		@"The Chainsmokers | Roses (feat. ROZES)",
	]];
	[self assertMatch:match index:0 first:@"The Chainsmokers & Coldplay" second:@"Something Just Like This"];
}

- (void)testFeaturedArtistJoinedDifferently {
	NSArray *match = [self matchForText:@"Laibach feat. Senidah - Love Machine" songs:@[
		@"Laibach & SENIDAH | Love Machine",
		@"Laibach | Love Machine (feat. Senidah) [PUNCHBAG remix]",
	]];
	[self assertMatch:match index:0 first:@"Laibach & SENIDAH" second:@"Love Machine"];

	match = [self matchForText:@"GORAN KARAN FEAT. SEVERINA - ŠTA' JE SVIT" songs:@[
		@"Severina & Goran Karan | Sta je svit",
		@"Goran Karan | Sta je svit (feat. Severina)",
	]];
	[self assertMatch:match index:0 first:@"Severina & Goran Karan" second:@"Sta je svit"];
}

- (void)testCollaborationPrefersTheCollaborationVersion {
	NSArray *match = [self matchForText:@"ED SHEERAN & ARIJIT SINGH - SAPPHIRE" songs:@[
		@"Ed Sheeran | Sapphire",
		@"Ed Sheeran | Sapphire (feat. Arijit Singh)",
	]];
	[self assertMatch:match index:1 first:nil second:@"Sapphire"];
}

- (void)testSlovenianAndBetweenArtists {
	// "in" is Slovenian for "and"; the catalog lists the second artist in the title
	NSArray *match = [self matchForText:@"GRUPA VIVA IN DORIS DRAGOVIC - DVA SMO ZIVOTA" songs:@[
		@"Grupa Viva | Dva Smo Života (with Doris Dragović)",
		@"Oliver Dragojević | Trag U Beskraju",
	]];
	[self assertMatch:match index:0 first:nil second:@"Dva Smo Života"];
}

#pragma mark - Loose matches (only used when nothing better matches)

- (void)testStationListsArtistsTheCatalogDoesNotHave {
	NSArray *match = [self matchForText:@"QUEEN/FREDDIE MERCURY - A KIND OF MAGIC" songs:@[
		@"Queen | A Kind Of Magic (Highlander Version)",
		@"Queen | A Kind Of Magic",
		@"Queen | A Kind Of Magic (Live)",
		@"Queen | Who Wants to Live Forever",
	]];
	[self assertMatch:match index:1 first:nil second:@"A Kind Of Magic"];
}

- (void)testBandNamedDifferently {
	// the station and the catalog only share one artist, so the title has to be the same
	NSArray *match = [self matchForText:@"Spike Jones & His City Slickers - Carmen Murdered" songs:@[
		@"Spike Jones & The City Slickers | Carmen Murdered",
	]];
	[self assertMatch:match index:0 first:nil second:@"Carmen Murdered"];

	match = [self matchForText:@"PETER LOVSIN & VITEZI O'BLOZENE MIZE - NAJBOLJSI PAR" songs:@[
		@"Bohem | Najboljši Par",
		@"Peter Lovšin & Vitezi Om'a | Najboljši Par",
	]];
	[self assertMatch:match index:1 first:nil second:@"Najboljši Par"];

	match = [self matchForText:@"Spike Jones & His City Slickers - Carmen" songs:@[
		@"Spike Jones & The City Slickers | Carmen (Live)",
	]];
	XCTAssertNil(match);
}

- (void)testLongerArtistName {
	NSArray *match = [self matchForText:@"Charlie Daniels Band - The Devil Went Down To Georgia" songs:@[
		@"Home Free | The Devil Went Down to Georgia (feat. Charlie Daniels & Taylor Davis)",
		@"Charlie Daniels | The Devil Went Down to Georgia",
	]];
	[self assertMatch:match index:1 first:nil second:@"The Devil Went Down to Georgia"];
}

- (void)testArtistNameWithoutLeadingThe {
	NSArray *match = [self matchForText:@"Charlie Daniels Band - The Devil Went Down To Georgia" songs:@[
		@"Home Free | The Devil Went Down to Georgia (feat. Charlie Daniels & Taylor Davis)",
		@"Charlie Daniels | The Devil Went Down to Georgia",
		@"The Charlie Daniels Band | The Devil Went Down to Georgia",
	]];
	// the band's full name without the leading "The" is a better match than the shorter name
	[self assertMatch:match index:2 first:@"The Charlie Daniels Band" second:@"The Devil Went Down to Georgia"];
}

#pragma mark - Search term

- (void)testSearchTermLeavesOutJoiners {
	// the catalog search only finds songs containing every word, and the catalog joins artists with "&"
	SRTrackLookup *lookup = [SRTrackLookup sharedLookup];
	XCTAssertEqualObjects([lookup searchTermForFirstPart:@"SAMSTONE x AKTIVE" secondPart:@"MY FAVOURITE GAME (FT. THE CARDIGANS)"],
						  @"SAMSTONE AKTIVE MY FAVOURITE GAME (FT. THE CARDIGANS)");
	XCTAssertEqualObjects([lookup searchTermForFirstPart:@"Armin van Buuren vs. Vini Vici" secondPart:@"Great Spirit"],
						  @"Armin van Buuren Vini Vici Great Spirit");
	XCTAssertEqualObjects([lookup searchTermForFirstPart:@"Coldplay" secondPart:@"Xanadu Box"], @"Coldplay Xanadu Box");
}

- (void)testFallbackSearchTermUsesTitleAndFirstArtistWord {
	SRTrackLookup *lookup = [SRTrackLookup sharedLookup];
	XCTAssertEqualObjects([lookup fallbackSearchTermForFirstPart:@"Fabrizio deAndre" secondPart:@"Franziska"], @"Fabrizio Franziska");
	XCTAssertEqualObjects([lookup fallbackSearchTermForFirstPart:@"PETER LOVSIN & VITEZI O'BLOZENE MIZE" secondPart:@"NAJBOLJSI PAR"],
						  @"PETER NAJBOLJSI PAR");
}

@end
