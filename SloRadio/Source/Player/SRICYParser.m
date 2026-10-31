//
//  SRICYParser.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRICYParser.h"

@implementation SRICYMetadataBlock

- (instancetype)initWithData:(NSData *)data audioOffset:(uint64_t)audioOffset {
	self = [super init];
	if (self) {
		_data = [data copy];
		_audioOffset = audioOffset;
	}
	return self;
}

@end

typedef NS_ENUM(NSInteger, SRICYParserState) {
	SRICYParserStateAudio,		// copying audio bytes until the next length byte
	SRICYParserStateLength,		// the next byte is the metadata length / 16
	SRICYParserStateMetadata,	// collecting metadata bytes
};

@interface SRICYParser ()

@property (nonatomic, assign) NSUInteger metaInterval;
@property (nonatomic, assign) SRICYParserState state;
@property (nonatomic, assign) NSUInteger audioRemaining;
@property (nonatomic, assign) NSUInteger metadataRemaining;
@property (nonatomic, strong) NSMutableData *metadata;

@end

@implementation SRICYParser

- (instancetype)initWithMetaInterval:(NSUInteger)metaInterval {
	self = [super init];
	if (self) {
		_metaInterval = metaInterval;
		_state = SRICYParserStateAudio;
		_audioRemaining = metaInterval;
		_metadata = [NSMutableData data];
	}
	return self;
}

- (NSData *)audioDataByParsingData:(NSData *)data metadataBlocks:(NSMutableArray<SRICYMetadataBlock *> *)blocks {
	if (self.metaInterval == 0) {
		_audioOffset += data.length;
		return data;
	}
	NSMutableData *audio = [NSMutableData dataWithCapacity:data.length];
	const uint8_t *bytes = data.bytes;
	NSUInteger length = data.length;
	NSUInteger position = 0;
	while (position < length) {
		switch (self.state) {
			case SRICYParserStateAudio: {
				NSUInteger count = MIN(self.audioRemaining, length - position);
				[audio appendBytes:bytes + position length:count];
				position += count;
				_audioOffset += count;
				self.audioRemaining -= count;
				if (self.audioRemaining == 0) {
					self.state = SRICYParserStateLength;
				}
				break;
			}
			case SRICYParserStateLength:
				self.metadataRemaining = bytes[position] * 16;
				position++;
				[self.metadata setLength:0];
				if (self.metadataRemaining == 0) {
					[self startAudio];
				} else {
					self.state = SRICYParserStateMetadata;
				}
				break;
			case SRICYParserStateMetadata: {
				NSUInteger count = MIN(self.metadataRemaining, length - position);
				[self.metadata appendBytes:bytes + position length:count];
				position += count;
				self.metadataRemaining -= count;
				if (self.metadataRemaining == 0) {
					NSData *block = [SRICYParser dataByTrimmingPadding:self.metadata];
					if (block.length > 0) {
						[blocks addObject:[[SRICYMetadataBlock alloc] initWithData:block audioOffset:self.audioOffset]];
					}
					[self startAudio];
				}
				break;
			}
		}
	}
	return audio;
}

- (void)startAudio {
	self.state = SRICYParserStateAudio;
	self.audioRemaining = self.metaInterval;
}

+ (NSData *)dataByTrimmingPadding:(NSData *)data {
	const uint8_t *bytes = data.bytes;
	NSUInteger length = data.length;
	while (length > 0 && (bytes[length - 1] == 0 || bytes[length - 1] == ' ' || bytes[length - 1] == '\r' || bytes[length - 1] == '\n')) {
		length--;
	}
	return [data subdataWithRange:NSMakeRange(0, length)];
}

#pragma mark - ICY responses

+ (BOOL)isICYResponseData:(NSData *)data {
	return data.length >= 4 && memcmp(data.bytes, "ICY ", 4) == 0;
}

+ (NSDictionary<NSString *, NSString *> *)headersFromICYResponseData:(NSData *)data headerLength:(NSUInteger *)headerLength statusCode:(NSInteger *)statusCode {
	if (![self isICYResponseData:data]) {
		return nil;
	}
	// the block ends with an empty line, some servers use bare line feeds
	NSRange end = NSMakeRange(NSNotFound, 0);
	for (NSString *separator in @[@"\r\n\r\n", @"\n\n"]) {
		NSData *separatorData = [separator dataUsingEncoding:NSASCIIStringEncoding];
		NSRange range = [data rangeOfData:separatorData options:0 range:NSMakeRange(0, MIN(data.length, 16384))];
		if (range.location != NSNotFound && (end.location == NSNotFound || range.location < end.location)) {
			end = range;
		}
	}
	if (end.location == NSNotFound) {
		return nil;
	}
	NSString *head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, end.location)] encoding:NSISOLatin1StringEncoding];
	NSArray<NSString *> *lines = [head componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSArray<NSString *> *status = [lines.firstObject componentsSeparatedByString:@" "];
	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	for (NSString *line in [lines subarrayWithRange:NSMakeRange(1, lines.count - 1)]) {
		NSRange colon = [line rangeOfString:@":"];
		if (colon.location != NSNotFound) {
			NSString *key = [[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
			NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (key.length > 0) {
				headers[key] = value;
			}
		}
	}
	if (headerLength) {
		*headerLength = end.location + end.length;
	}
	if (statusCode) {
		*statusCode = status.count > 1 ? status[1].integerValue : 0;
	}
	return headers;
}

@end
