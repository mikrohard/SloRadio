//
//  SRICYParser.h
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <Foundation/Foundation.h>

// One ICY metadata block (e.g. "StreamTitle='Artist - Title';") without its zero padding.
@interface SRICYMetadataBlock : NSObject

@property (nonatomic, readonly) NSData *data;
// Position in the audio byte stream (metadata removed) from which on the metadata applies.
@property (nonatomic, readonly) uint64_t audioOffset;

- (instancetype)initWithData:(NSData *)data audioOffset:(uint64_t)audioOffset;

@end

// Separates the metadata blocks Icecast/Shoutcast interleave into the audio data every `icy-metaint` bytes.
// Chunks may be split anywhere, the parser keeps its state between them.
@interface SRICYParser : NSObject

// metaInterval: the icy-metaint header value, 0 when the stream has no interleaved metadata.
- (instancetype)initWithMetaInterval:(NSUInteger)metaInterval;

// Returns the audio bytes of the chunk and adds the metadata blocks it completes (empty blocks are skipped).
- (NSData *)audioDataByParsingData:(NSData *)data metadataBlocks:(NSMutableArray<SRICYMetadataBlock *> *)blocks;

// Total audio bytes returned so far.
@property (nonatomic, readonly) uint64_t audioOffset;

// Shoutcast v1 servers answer "ICY 200 OK" instead of HTTP and URLSession passes their header block on as data.
// Returns YES when the data starts with such a response.
+ (BOOL)isICYResponseData:(NSData *)data;
// Parses the header block of an ICY response. Returns nil until the whole block (up to the empty line) is in data.
// headerLength receives the length of the block including the empty line, statusCode the response status.
+ (NSDictionary<NSString *, NSString *> *)headersFromICYResponseData:(NSData *)data headerLength:(NSUInteger *)headerLength statusCode:(NSInteger *)statusCode;

@end
