//
//  SRPlaybackManager.m
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRPlaybackManager.h"
#import "SRDataManager.h"
#import "SRRadioPlayer.h"
#import "SRRadioStation.h"
#import "SRSleepTimer.h"
#import "SRMetadataFormatter.h"
#import "SRTrackLookup.h"
#import "SRImageCache.h"
#import "Reachability.h"
#import "Firebase.h"

@import AVFoundation;
@import MediaPlayer;
@import UIKit;

NSString * const SRPlaybackManagerDidChangeSleepTimer = @"SRPlaybackManagerDidChangeSleepTimer";
NSString * const SRPlaybackManagerDidFailPlayback = @"SRPlaybackManagerDidFailPlayback";
NSString * const SRPlaybackManagerDidUpdateNowPlayingText = @"SRPlaybackManagerDidUpdateNowPlayingText";

static CGFloat const SRNowPlayingArtworkWidth = 1024;

static NSTimeInterval const SRRadioBufferingTimeoutInterval = 10; // wait max 15 seconds for buffering

@interface SRPlaybackManager () <SRRadioPlayerDelegate, SRSleepTimerDelegate> {
	BOOL _playbackInterrupted;
	BOOL _audioSessionInterrupted;
}

@property (nonatomic, strong) SRSleepTimer *sleepTimer;

// background task
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;

@property (nonatomic, strong) NSTimer *bufferingTimeoutTimer;

// last station published to the now playing info center
// (reading MPNowPlayingInfoCenter.nowPlayingInfo back blocks the main thread on MediaPlayer's queue)
@property (nonatomic, copy) NSString *nowPlayingStationName;

// metadata spelling corrected by the catalog lookup (for the raw metadata text it was looked up for)
@property (nonatomic, copy) NSString *lookupRawText;
@property (nonatomic, copy) NSString *lookupResultText;
// album art of the song found by the lookup (only valid while lookupRawText is the current metadata)
@property (nonatomic, strong) UIImage *lookupArtworkImage;

@end

@implementation SRPlaybackManager

#pragma mark - Singleton

+ (SRPlaybackManager *)sharedManager {
	static SRPlaybackManager *sharedManager;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedManager = [[self alloc] init];
	});
	return sharedManager;
}

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super init];
	if (self) {
		_bgTask = UIBackgroundTaskInvalid;
		[self registerForNotifications];
		[self setupAudioSession];
		[[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:@{}];
		[[SRRadioPlayer sharedPlayer] setDelegate:self];
		[self startRemoteControlTracking];
	}
	return self;
}

#pragma mark - Audio session

- (void)setupAudioSession
{
	NSError *error = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	BOOL ok = [session setCategory:AVAudioSessionCategoryPlayback error:&error];
	if (!ok) {
		NSLog(@"Could not set audiosession category. Error: %@", error);
	}
	ok = [session setActive:YES error:&error];
	if (!ok) {
		NSLog(@"Could not set audiosession active. Error: %@", error);
	}
}

#pragma mark - Notifications

- (void)registerForNotifications {
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(audioSessionInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
	[nc addObserver:self selector:@selector(audioSessionRouteChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
	[nc addObserver:self selector:@selector(artworkPreloadFinished:) name:SRRadioStationDidPreloadArtwork object:nil];
	[nc addObserver:self selector:@selector(nowPlayingContextChanged:) name:SRDataManagerDidSelectStation object:nil];
	[nc addObserver:self selector:@selector(nowPlayingContextChanged:) name:SRDataManagerDidChangeStationList object:nil];
}

- (void)audioSessionInterruption:(NSNotification *)notification {
	AVAudioSessionInterruptionType interruptionType = [[notification.userInfo objectForKey:AVAudioSessionInterruptionTypeKey] integerValue];
	if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
		_audioSessionInterrupted = YES;
		[self audioSessionInterrupted];
	} else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
		AVAudioSessionInterruptionOptions interruptionOption = [[notification.userInfo objectForKey:AVAudioSessionInterruptionOptionKey] integerValue];
		if (_audioSessionInterrupted && interruptionOption == AVAudioSessionInterruptionOptionShouldResume) {
			_audioSessionInterrupted = NO;
			[self audioSessionResume];
		}
	}
}

- (void)audioSessionRouteChanged:(NSNotification *)notification {
	AVAudioSessionRouteChangeReason reason = [[notification.userInfo objectForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
	if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self stop];
		});
	}
}

- (void)artworkPreloadFinished:(NSNotification *)notification {
	SRRadioStation *station = notification.object;
	if ([station isKindOfClass:[SRRadioStation class]]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			// only refresh when the artwork was actually loaded, otherwise a failed download would loop
			if (station.stationId == [[SRDataManager sharedManager] selectedRadioStation].stationId &&
				[station cachedArtworkImageForWidth:SRNowPlayingArtworkWidth] != nil) {
				[self updateNowPlayingInfo];
			}
		});
	}
}

- (void)nowPlayingContextChanged:(NSNotification *)notification {
	[self updateNowPlayingInfo];
}

#pragma mark - Playback interruption

- (void)audioSessionInterrupted {
	if ([[SRRadioPlayer sharedPlayer] state] != SRRadioPlayerStateStopped) {
		_playbackInterrupted = YES;
		[self performSelectorOnMainThread:@selector(stop) withObject:nil waitUntilDone:YES];
	}
}

- (void)audioSessionResume {
	if ([[SRRadioPlayer sharedPlayer] state] == SRRadioPlayerStateStopped && _playbackInterrupted && !_audioSessionInterrupted) {
		// resume playback
		[self startBackgroundTask];
		[self performSelectorOnMainThread:@selector(play) withObject:nil waitUntilDone:YES];
	}
}

#pragma mark - Stations

- (NSArray *)stations {
	// the currently selected list acts as the playback queue
	SRDataManager *dataManager = [SRDataManager sharedManager];
	NSArray *stations = [dataManager stationsForList:dataManager.selectedStationList];
	if (stations.count == 0) {
		stations = dataManager.stations;
	}
	return stations;
}

- (void)selectStationWithOffset:(NSInteger)offset {
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	NSInteger currentIndex = NSNotFound;
	NSArray *stations = [self stations];
	for (SRRadioStation *station in stations) {
		if (station.stationId == selectedStation.stationId) {
			currentIndex = [stations indexOfObject:station];
			break;
		}
	}
	SRRadioStation *nextStation = nil;
	if (currentIndex != NSNotFound) {
		NSInteger nextIndex = currentIndex + offset;
		if (nextIndex < 0) {
			nextIndex += stations.count;
		}
		else if (nextIndex >= stations.count) {
			nextIndex -= stations.count;
		}
		nextStation = stations[nextIndex];
	}
	else if (stations.count > 0) {
		nextStation = stations[0];
	}
	[[SRDataManager sharedManager] selectRadioStation:nextStation];
}

#pragma mark - Background task

- (void)startBackgroundTask {
	UIApplication *application = [UIApplication sharedApplication];
	if (_bgTask != UIBackgroundTaskInvalid) {
		[application endBackgroundTask:_bgTask];
		_bgTask = UIBackgroundTaskInvalid;
	}
	__weak SRPlaybackManager *weakSelf = self;
	_bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
		[application endBackgroundTask:weakSelf.bgTask];
		weakSelf.bgTask = UIBackgroundTaskInvalid;
	}];
}

- (void)endBackgroundTask {
	if (_bgTask != UIBackgroundTaskInvalid) {
		[[UIApplication sharedApplication] endBackgroundTask:_bgTask];
		_bgTask = UIBackgroundTaskInvalid;
	}
}

#pragma mark - Common actions

- (void)playRadioStation:(SRRadioStation *)station {
	[self playRadioStation:station withSleepTimer:NO];
}

- (void)playRadioStation:(SRRadioStation *)station withSleepTimer:(BOOL)sleepTimer {
	[[SRDataManager sharedManager] selectRadioStation:station];
	[self playWithSleepTimer:sleepTimer];
}

- (void)play {
	BOOL sleepTimer = [SRDataManager sharedManager].sleepTimerEnabledByDefault;
	[self playWithSleepTimer:sleepTimer];
}

- (void)playWithSleepTimer:(BOOL)sleepTimer {
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	if (!selectedStation) {
		// radio stations not yet loaded
		// ignore this playback request
		return;
	}
	SRRadioPlayer *player = [SRRadioPlayer sharedPlayer];
	if ([[player currentRadioStation] isEqual:selectedStation] &&
		([player state] == SRRadioPlayerStateBuffering ||
		 [player state] == SRRadioPlayerStatePlaying)) {
		// this radio station is already playing
		// ignore this playback request
		return;
	}
	[self setupAudioSession];
	[self startBackgroundTask];
	if (sleepTimer) {
		[self setupSleepTimer];
	}
	else {
		[self clearSleepTimer];
	}
	_playbackInterrupted = NO;
	_audioSessionInterrupted = NO;
	[player playRadioStation:selectedStation];
	[self setupBufferingTimeoutTimer];
}

- (void)stop {
	[[SRRadioPlayer sharedPlayer] stop];
	[self clearSleepTimer];
}

- (void)togglePlayPause {
	switch ([[SRRadioPlayer sharedPlayer] state]) {
		case SRRadioPlayerStateOpening:
		case SRRadioPlayerStateBuffering:
		case SRRadioPlayerStatePlaying:
			[self stop];
			break;
		default:
			[self play];
			break;
	}
}

- (void)playNextStation {
	[self selectStationWithOffset:1];
	[self play];
}

- (void)playPreviousStation {
	[self selectStationWithOffset:-1];
	[self play];
}

#pragma mark - Now playing info

// Raw "now playing" metadata of the current station and its "artist - title" parts (when it has them).
- (NSString *)currentMetadataTextFirstPart:(NSString **)firstPart secondPart:(NSString **)secondPart {
	SRRadioPlayer *player = [SRRadioPlayer sharedPlayer];
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	if (player.currentRadioStation == nil || player.currentRadioStation.stationId != selectedStation.stationId) {
		return nil;
	}
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString *nowPlaying = [[player.metaData objectForKey:SRRadioPlayerMetaDataNowPlayingKey] stringByTrimmingCharactersInSet:whitespace];
	NSString *title = [[player.metaData objectForKey:SRRadioPlayerMetaDataTitleKey] stringByTrimmingCharactersInSet:whitespace];
	NSString *artist = [[player.metaData objectForKey:SRRadioPlayerMetaDataArtistKey] stringByTrimmingCharactersInSet:whitespace];
	
	// stations mostly send a single "now playing" text
	if (nowPlaying.length) {
		NSRange separator = [nowPlaying rangeOfString:@" - "];
		if (separator.location != NSNotFound) {
			*firstPart = [[nowPlaying substringToIndex:separator.location] stringByTrimmingCharactersInSet:whitespace];
			*secondPart = [[nowPlaying substringFromIndex:NSMaxRange(separator)] stringByTrimmingCharactersInSet:whitespace];
		}
	} else if (title.length && artist.length) {
		*firstPart = artist;
		*secondPart = title;
		nowPlaying = [NSString stringWithFormat:@"%@ - %@", artist, title];
	}
	if (!nowPlaying.length || [SRMetadataFormatter isPlaceholderText:nowPlaying]) {
		return nil;
	}
	// some stations only send their own name, which is already shown
	NSString *comparableNowPlaying = [SRMetadataFormatter comparableText:nowPlaying];
	if ([comparableNowPlaying isEqualToString:[SRMetadataFormatter comparableText:selectedStation.name]]) {
		return nil;
	}
	return nowPlaying;
}

- (NSString *)nowPlayingText {
	NSString *firstPart = nil;
	NSString *secondPart = nil;
	NSString *nowPlaying = [self currentMetadataTextFirstPart:&firstPart secondPart:&secondPart];
	if (!nowPlaying) {
		return nil;
	}
	if ([nowPlaying isEqualToString:self.lookupRawText] && self.lookupResultText) {
		return self.lookupResultText;
	}
	NSString *formattedText = nil;
	if (firstPart.length && secondPart.length) {
		formattedText = [NSString stringWithFormat:@"%@ - %@", [SRMetadataFormatter formattedText:firstPart], [SRMetadataFormatter formattedText:secondPart]];
		[self lookupNowPlayingText:nowPlaying firstPart:firstPart secondPart:secondPart];
	} else {
		formattedText = [SRMetadataFormatter formattedText:nowPlaying];
	}
	return formattedText;
}

- (UIImage *)songArtworkImage {
	// only valid for the song it was found for, otherwise the station artwork is shown
	NSString *firstPart = nil;
	NSString *secondPart = nil;
	NSString *nowPlaying = [self currentMetadataTextFirstPart:&firstPart secondPart:&secondPart];
	if (nowPlaying && [nowPlaying isEqualToString:self.lookupRawText]) {
		return self.lookupArtworkImage;
	}
	return nil;
}

- (void)lookupNowPlayingText:(NSString *)nowPlaying firstPart:(NSString *)firstPart secondPart:(NSString *)secondPart {
	if ([nowPlaying isEqualToString:self.lookupRawText]) {
		// already looked up (or in progress)
		return;
	}
	self.lookupRawText = nowPlaying;
	self.lookupResultText = nil;
	self.lookupArtworkImage = nil;
	__weak SRPlaybackManager *weakSelf = self;
	[[SRTrackLookup sharedLookup] lookupFirstPart:firstPart secondPart:secondPart completion:^(NSString *correctedFirst, NSString *correctedSecond, NSURL *artworkURL) {
		SRPlaybackManager *strongSelf = weakSelf;
		if (!strongSelf || ![strongSelf.lookupRawText isEqualToString:nowPlaying]) {
			// metadata changed in the meantime
			return;
		}
		if (correctedFirst || correctedSecond) {
			strongSelf.lookupResultText = [NSString stringWithFormat:@"%@ - %@",
										   correctedFirst ?: [SRMetadataFormatter formattedText:firstPart],
										   correctedSecond ?: [SRMetadataFormatter formattedText:secondPart]];
			[strongSelf nowPlayingTextDidUpdate];
		}
		if (artworkURL) {
			[strongSelf loadSongArtworkFromURL:artworkURL forNowPlayingText:nowPlaying];
		}
	}];
}

- (void)loadSongArtworkFromURL:(NSURL *)artworkURL forNowPlayingText:(NSString *)nowPlaying {
	NSString *cacheKey = [SRImageCache keyForUrl:artworkURL];
	__weak SRPlaybackManager *weakSelf = self;
	void (^applyImage)(UIImage *) = ^(UIImage *image) {
		SRPlaybackManager *strongSelf = weakSelf;
		if (image && [strongSelf.lookupRawText isEqualToString:nowPlaying]) {
			strongSelf.lookupArtworkImage = image;
			[strongSelf nowPlayingTextDidUpdate];
		}
	};
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		UIImage *image = [[SRImageCache sharedCache] imageForKey:cacheKey];
		if (image) {
			dispatch_async(dispatch_get_main_queue(), ^{
				applyImage(image);
			});
			return;
		}
		[[[NSURLSession sharedSession] dataTaskWithURL:artworkURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
			UIImage *downloadedImage = data ? [UIImage imageWithData:data] : nil;
			if (downloadedImage) {
				[[SRImageCache sharedCache] cacheImage:downloadedImage forKey:cacheKey];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				applyImage(downloadedImage);
			});
		}] resume];
	});
}

- (void)nowPlayingTextDidUpdate {
	[self updateNowPlayingInfo];
	[[NSNotificationCenter defaultCenter] postNotificationName:SRPlaybackManagerDidUpdateNowPlayingText object:self];
}

- (void)updateNowPlayingInfo {
	MPNowPlayingInfoCenter *infoCenter = [MPNowPlayingInfoCenter defaultCenter];
	NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
	SRRadioStation *selectedStation = [[SRDataManager sharedManager] selectedRadioStation];
	if (selectedStation.name) {
		[nowPlayingInfo setObject:selectedStation.name forKey:MPMediaItemPropertyArtist];
	}
	SRRadioPlayer *player = [SRRadioPlayer sharedPlayer];
	float playRate = player.state == SRRadioPlayerStatePlaying ? 1.0 : 0.0;
	[nowPlayingInfo setObject:@(playRate) forKey:MPNowPlayingInfoPropertyPlaybackRate];
	[nowPlayingInfo setObject:@(YES) forKey:MPNowPlayingInfoPropertyIsLiveStream];
	// never load artwork inside the artwork request handler: MediaPlayer calls it on a queue the main thread
	// may synchronously wait on. Use the cached image (or the placeholder) and refresh once it's downloaded.
	MPMediaItemArtwork *artwork = [selectedStation preloadedArtworkForWidth:SRNowPlayingArtworkWidth];
	UIImage *songArtwork = [self songArtworkImage];
	if (songArtwork) {
		// album art of the current song (falls back to the station artwork for the next song)
		artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:songArtwork.size requestHandler:^UIImage *(CGSize size) {
			return songArtwork;
		}];
	}
	if (artwork != nil) {
		[nowPlayingInfo setObject:artwork forKey:MPMediaItemPropertyArtwork];
	}

	NSString *nowPlaying = [self nowPlayingText];
	[nowPlayingInfo setObject:nowPlaying ?: @"" forKey:MPMediaItemPropertyTitle];
	NSInteger currentIndex = 0;
	NSArray *stations = [self stations];
	for (SRRadioStation *station in stations) {
		if (station.stationId == selectedStation.stationId) {
			currentIndex = [stations indexOfObject:station];
			break;
		}
	}
	[nowPlayingInfo setObject:@(currentIndex) forKey:MPNowPlayingInfoPropertyPlaybackQueueIndex];
	[nowPlayingInfo setObject:@(stations.count) forKey:MPNowPlayingInfoPropertyPlaybackQueueCount];

	BOOL stationChange = ![selectedStation.name ?: @"" isEqualToString:self.nowPlayingStationName ?: @""];
	self.nowPlayingStationName = selectedStation.name;
	if (stationChange) {
		NSMutableDictionary *nowPlayingWithoutTitle = [nowPlayingInfo mutableCopy];
		[nowPlayingWithoutTitle removeObjectForKey:MPMediaItemPropertyTitle];
		[infoCenter setNowPlayingInfo:nowPlayingWithoutTitle];
		dispatch_async(dispatch_get_main_queue(), ^{
			[infoCenter setNowPlayingInfo:nowPlayingInfo];
		});
	} else {
		[infoCenter setNowPlayingInfo:nowPlayingInfo];
	}
}

- (void)updateNowPlayingState {
	MPNowPlayingInfoCenter *infoCenter = [MPNowPlayingInfoCenter defaultCenter];
	if ([[SRRadioPlayer sharedPlayer] state] == SRRadioPlayerStateBuffering ||
		[[SRRadioPlayer sharedPlayer] state] == SRRadioPlayerStatePlaying) {
		infoCenter.playbackState = MPNowPlayingPlaybackStatePlaying;
	} else {
		infoCenter.playbackState = MPNowPlayingPlaybackStateStopped;
	}
}

#pragma mark - Buffering timeout

- (void)setupBufferingTimeoutTimer {
	[self invalidateBufferingTimeoutTimer];
	NSTimeInterval timeout = SRRadioBufferingTimeoutInterval + [[SRDataManager sharedManager] playerCacheSize];
	self.bufferingTimeoutTimer = [NSTimer timerWithTimeInterval:timeout target:self selector:@selector(bufferingTimeout:) userInfo:nil repeats:NO];
	[[NSRunLoop currentRunLoop] addTimer:self.bufferingTimeoutTimer forMode:NSRunLoopCommonModes];
}

- (void)invalidateBufferingTimeoutTimer {
	[self.bufferingTimeoutTimer invalidate];
	self.bufferingTimeoutTimer = nil;
}

- (void)bufferingTimeout:(NSTimer *)timer {
	// invalidate timer
	[self invalidateBufferingTimeoutTimer];

	// retry playback
	if ([[SRRadioPlayer sharedPlayer] state] == SRRadioPlayerStateBuffering) {
		[self stop];
		[self play];
	}
}

#pragma mark - SRRadioPlayerDelegate

- (void)radioPlayer:(SRRadioPlayer *)player didChangeState:(SRRadioPlayerState)state {
	[self updateNowPlayingInfo];
	[self updateNowPlayingState];
	if (state == SRRadioPlayerStateError) {
		[self handlePlaybackError];
		[self stop];
	}
	if (state == SRRadioPlayerStatePlaying &&
		self.sleepTimer && !self.sleepTimer.isRunning) {
		[self startSleepTimer];
	}
	if (state == SRRadioPlayerStateOpening ||
		state == SRRadioPlayerStateBuffering) {
		[self startBackgroundTask];
	}
	if (state == SRRadioPlayerStateError ||
		state == SRRadioPlayerStatePlaying ||
		state == SRRadioPlayerStateStopped) {
		[self endBackgroundTask];
	}
	if (state != SRRadioPlayerStateOpening &&
		state != SRRadioPlayerStateBuffering) {
		[self invalidateBufferingTimeoutTimer];
	}
}

- (void)radioPlayer:(SRRadioPlayer *)player didChangeMetaData:(NSDictionary *)metadata {
	[self updateNowPlayingInfo];
}

#pragma mark - Error handling

- (void)handlePlaybackError {
	SRRadioStation *station = [[SRRadioPlayer sharedPlayer] currentRadioStation];
	if (station == nil) {
		return;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:SRPlaybackManagerDidFailPlayback object:station];

	// Report error to Crashlytics
	BOOL internetReachable = [[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable;
	if (internetReachable &&
		![[SRDataManager sharedManager] isCustomRadioStation:station] &&
		station.url != nil) {
		NSString *message = [NSString stringWithFormat:NSLocalizedString(@"PlaybackErrorStation", @""), station.name];
		NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : message, NSURLErrorKey: station.url}];
		[[FIRCrashlytics crashlytics] recordError:error];
	}
}

#pragma mark - Sleep timer

- (BOOL)sleepTimerActive {
	return self.sleepTimer != nil;
}

- (NSTimeInterval)sleepTimerTimeRemaining {
	return self.sleepTimer.timeRemaining;
}

- (void)setupSleepTimer {
	[self.sleepTimer invalidate];
	NSTimeInterval interval = [SRDataManager sharedManager].sleepTimerInterval;
	self.sleepTimer = [[SRSleepTimer alloc] initWithInterval:interval delegate:self];
	[self notifySleepTimerChange];
}

- (void)startSleepTimer {
	[self.sleepTimer startTimer];
}

- (void)clearSleepTimer {
	if (self.sleepTimer) {
		[self.sleepTimer invalidate];
		self.sleepTimer = nil;
		[self notifySleepTimerChange];
	}
}

- (void)cancelSleepTimer {
	[self clearSleepTimer];
	[[SRRadioPlayer sharedPlayer] setVolume:100];
}

- (void)notifySleepTimerChange {
	[[NSNotificationCenter defaultCenter] postNotificationName:SRPlaybackManagerDidChangeSleepTimer object:self];
}

#pragma mark - SRSleepTimerDelegate

- (void)sleepTimer:(SRSleepTimer *)timer changeVolumeLevel:(float)volume {
	int playerVolume = (int)(volume * 100.0);
	[[SRRadioPlayer sharedPlayer] setVolume:playerVolume];
}

- (void)sleepTimer:(SRSleepTimer *)timer timeRemaining:(NSTimeInterval)timeRemaining {
	[self notifySleepTimerChange];
}

- (void)sleepTimerDidEnd:(SRSleepTimer *)timer {
	[self stop];
}

#pragma mark - Remote control events

- (void)startRemoteControlTracking {
	MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

	MPRemoteCommand *nextTrackCommand = [commandCenter nextTrackCommand];
	[nextTrackCommand setEnabled:YES];
	[nextTrackCommand addTarget:self action:@selector(remotePlayNext)];

	MPRemoteCommand *previousTrackCommand = [commandCenter previousTrackCommand];
	[previousTrackCommand setEnabled:YES];
	[previousTrackCommand addTarget:self action:@selector(remotePlayPrevious)];

	MPRemoteCommand *pauseCommand = [commandCenter pauseCommand];
	[pauseCommand setEnabled:YES];
	[pauseCommand addTarget:self action:@selector(remoteStop)];

	MPRemoteCommand *playCommand = [commandCenter playCommand];
	[playCommand setEnabled:YES];
	[playCommand addTarget:self action:@selector(remotePlay)];

	MPRemoteCommand *togglePlayPauseCommand = [commandCenter togglePlayPauseCommand];
	[togglePlayPauseCommand setEnabled:YES];
	[togglePlayPauseCommand addTarget:self action:@selector(remoteTogglePlayPause)];
}

- (MPRemoteCommandHandlerStatus)remotePlay {
	[self play];
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remoteStop {
	[self stop];
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remoteTogglePlayPause {
	SRRadioPlayerState state = [[SRRadioPlayer sharedPlayer] state];
	if (state == SRRadioPlayerStatePlaying &&
		[[SRRadioPlayer sharedPlayer] timePlaying] > 1.0) {
		[self stop];
	} else {
		[self play];
	}
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remotePlayNext {
	[self playNextStation];
	return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)remotePlayPrevious {
	[self playPreviousStation];
	return MPRemoteCommandHandlerStatusSuccess;
}

@end
