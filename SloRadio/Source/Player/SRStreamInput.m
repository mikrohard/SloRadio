//
//  SRStreamInput.m
//  SloRadio
//
//  Created by Jernej Fijačko on 31. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRStreamInput.h"
#import "SRByteQueue.h"
#import "SRICYParser.h"

NSString * const SRStreamInputErrorDomain = @"SRStreamInputErrorDomain";

// No data for this long fails the download. The timer keeps running while the download is paused (suspended)
// because the queue is full, so it must be longer than a pause can take: the queue resumes after playing a
// quarter of its capacity (128 KB, about 32 s at 32 kbit/s). Dead connections are detected sooner by the
// engine, which reconnects when it has to wait 10 s for data.
static NSTimeInterval const SRStreamInputTimeout = 60.0;

@interface SRStreamInput () <NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) SRByteQueue *queue;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSOperationQueue *sessionQueue;
@property (nonatomic, strong) NSURLSessionDataTask *task;
// accessed on the session queue only
@property (nonatomic, strong) SRICYParser *parser;
@property (nonatomic, strong) NSMutableData *pendingICYResponse;
@property (nonatomic, strong) NSDictionary *responseHeaders;
@property (nonatomic, assign) BOOL suspended;
// accessed on the main queue only
@property (nonatomic, assign) BOOL cancelled;

@end

@implementation SRStreamInput

- (instancetype)initWithURL:(NSURL *)url queue:(SRByteQueue *)queue {
	self = [super init];
	if (self) {
		_url = url;
		_queue = queue;
	}
	return self;
}

- (void)dealloc {
	[_session invalidateAndCancel];
}

- (void)start {
	self.sessionQueue = [[NSOperationQueue alloc] init];
	self.sessionQueue.maxConcurrentOperationCount = 1;
	self.sessionQueue.name = @"SRStreamInput";
	NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	configuration.timeoutIntervalForRequest = SRStreamInputTimeout;
	configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
	self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:self.sessionQueue];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url];
	[request setValue:@"1" forHTTPHeaderField:@"Icy-MetaData"];
	[request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
	self.task = [self.session dataTaskWithRequest:request];

	// resume the download once the decoder made room in the queue
	__weak SRStreamInput *weakSelf = self;
	self.queue.spaceAvailableHandler = ^{
		SRStreamInput *input = weakSelf;
		[input.sessionQueue addOperationWithBlock:^{
			if (input.suspended) {
				NSLog(@"Resuming the download of %@", input.url);
				input.suspended = NO;
				[input.task resume];
			}
		}];
	};
	[self.task resume];
}

- (void)cancel {
	self.cancelled = YES;
	self.queue.spaceAvailableHandler = nil;
	[self.session invalidateAndCancel];
	self.session = nil;
	[self.queue finishWithError:nil];
}

#pragma mark - Delegate (main queue)

- (void)notify:(void (^)(SRStreamInput *input, id<SRStreamInputDelegate> delegate))block {
	__weak SRStreamInput *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		SRStreamInput *input = weakSelf;
		if (input && !input.cancelled) {
			block(input, input.delegate);
		}
	});
}

#pragma mark - Data (session queue)

- (void)startWithHeaders:(NSDictionary<NSString *, NSString *> *)headers {
	self.responseHeaders = headers;
	self.parser = [[SRICYParser alloc] initWithMetaInterval:(NSUInteger)MAX([headers[@"icy-metaint"] integerValue], 0)];
	[self notify:^(SRStreamInput *input, id<SRStreamInputDelegate> delegate) {
		[delegate streamInput:input didReceiveHeaders:headers];
	}];
}

- (void)handleAudioData:(NSData *)data {
	NSMutableArray<SRICYMetadataBlock *> *blocks = [NSMutableArray array];
	NSData *audio = [self.parser audioDataByParsingData:data metadataBlocks:blocks];
	[self.queue appendData:audio];
	for (SRICYMetadataBlock *block in blocks) {
		[self notify:^(SRStreamInput *input, id<SRStreamInputDelegate> delegate) {
			[delegate streamInput:input didReceiveMetadataBlock:block];
		}];
	}
	if (self.queue.isFull && !self.suspended) {
		NSLog(@"Pausing the download of %@, %lu KB queued", self.url, (unsigned long)(self.queue.length / 1024));
		self.suspended = YES;
		[self.task suspend];
	}
}

- (void)failWithError:(NSError *)error {
	[self.queue finishWithError:error];
	[self notify:^(SRStreamInput *input, id<SRStreamInputDelegate> delegate) {
		[delegate streamInput:input didFinishWithError:error];
	}];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
	NSHTTPURLResponse *httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
	if (httpResponse.statusCode >= 400) {
		completionHandler(NSURLSessionResponseCancel);
		[self failWithError:[NSError errorWithDomain:SRStreamInputErrorDomain code:httpResponse.statusCode
											userInfo:@{NSLocalizedDescriptionKey: [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode]}]];
		return;
	}
	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	[httpResponse.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
		if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
			headers[[key lowercaseString]] = value;
		}
	}];
	self.responseHeaders = headers;
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
	if (self.parser) {
		[self handleAudioData:data];
		return;
	}
	// first data: a Shoutcast v1 "ICY 200 OK" response carries its headers in the body
	if (self.pendingICYResponse || [SRICYParser isICYResponseData:data]) {
		if (!self.pendingICYResponse) {
			self.pendingICYResponse = [NSMutableData data];
		}
		[self.pendingICYResponse appendData:data];
		NSUInteger headerLength = 0;
		NSInteger statusCode = 0;
		NSDictionary *headers = [SRICYParser headersFromICYResponseData:self.pendingICYResponse headerLength:&headerLength statusCode:&statusCode];
		if (!headers) {
			if (self.pendingICYResponse.length > 16384) {
				[dataTask cancel];
				[self failWithError:[NSError errorWithDomain:SRStreamInputErrorDomain code:NSURLErrorBadServerResponse userInfo:nil]];
			}
			return;
		}
		if (statusCode >= 400) {
			[dataTask cancel];
			[self failWithError:[NSError errorWithDomain:SRStreamInputErrorDomain code:statusCode userInfo:nil]];
			return;
		}
		NSData *rest = [self.pendingICYResponse subdataWithRange:NSMakeRange(headerLength, self.pendingICYResponse.length - headerLength)];
		self.pendingICYResponse = nil;
		[self startWithHeaders:headers];
		[self handleAudioData:rest];
		return;
	}
	[self startWithHeaders:self.responseHeaders ?: @{}];
	[self handleAudioData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
	if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
		return;
	}
	[self failWithError:error];
}

@end
