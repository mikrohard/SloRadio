//
//  SRPlayerViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRPlayerViewController.h"
#import "SRPlaybackManager.h"
#import "SRDataManager.h"
#import "SRRadioPlayer.h"
#import "SRRadioStation.h"
#import "SRPlatterView.h"
#import "CBAutoScrollLabel.h"

@import AVKit;

static CGFloat const SRCompactArtworkSize = 48.f;
static CGFloat const SRCompactArtworkWidth = 256;
static CGFloat const SRExpandedArtworkWidth = 1024;
static CGFloat const SRExpandedMaximumWidth = 440.f;
static CGFloat const SRCompactAppleMusicIconSize = 13.f;
static CGFloat const SRExpandedAppleMusicIconSize = 24.f;
static NSTimeInterval const SRNowPlayingPauseInterval = 3.0;

@interface SRPlayerViewController () <UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate>

@property (nonatomic, assign) SRPlayerStyle style;
@property (nonatomic, assign) BOOL collapsed;
@property (nonatomic, strong) SRPlatterView *platter;
@property (nonatomic, strong) UIImageView *backdropView;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UIImageView *appleMusicIconView;
@property (nonatomic, strong) CBAutoScrollLabel *titleLabel;
@property (nonatomic, strong) CBAutoScrollLabel *subtitleLabel;
@property (nonatomic, strong) UIButton *sleepTimerButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *inlinePlayButton;
@property (nonatomic, strong) UIButton *inlineNextButton;
@property (nonatomic, strong) AVRoutePickerView *routePickerView;
@property (nonatomic, strong) UIButton *routeButton;
@property (nonatomic, strong) NSMapTable<UIButton *, UIActivityIndicatorView *> *loadingIndicators;
@property (nonatomic, strong) UIView *routeContainer;
@property (nonatomic, strong) UIView *transportRow;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic, copy) NSString *artworkKey;
@property (nonatomic, assign) BOOL refreshScheduled;

@end

@implementation SRPlayerViewController

#pragma mark - Lifecycle

- (instancetype)initWithStyle:(SRPlayerStyle)style {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_style = style;
		[self registerForNotifications];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setupCommonViews];
	if (self.style == SRPlayerStyleCompact) {
		[self setupCompactLayout];
	} else {
		[self setupExpandedLayout];
	}
	[self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.style == SRPlayerStyleExpanded) {
		[self.navigationController setNavigationBarHidden:YES animated:NO];
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self observeRoutePickerHighlight];
}

- (UIView *)platterView {
	[self loadViewIfNeeded];
	return self.platter;
}

#pragma mark - Setup

- (void)setupCommonViews {
	BOOL compact = self.style == SRPlayerStyleCompact;

	UIImageView *artworkView = [[UIImageView alloc] init];
	artworkView.contentMode = UIViewContentModeScaleAspectFill;
	artworkView.clipsToBounds = YES;
	artworkView.backgroundColor = [UIColor secondarySystemFillColor];
	artworkView.layer.cornerRadius = compact ? 10.f : 16.f;
	artworkView.layer.cornerCurve = kCACornerCurveContinuous;
	artworkView.image = [UIImage imageNamed:@"PlaceholderArtwork"];
	artworkView.translatesAutoresizingMaskIntoConstraints = NO;
	// the artwork size is defined by the layout, never by the image (small images are scaled up)
	for (NSNumber *axis in @[@(UILayoutConstraintAxisHorizontal), @(UILayoutConstraintAxisVertical)]) {
		[artworkView setContentHuggingPriority:1 forAxis:axis.integerValue];
		[artworkView setContentCompressionResistancePriority:1 forAxis:axis.integerValue];
	}
	// the album art links to the song in Apple Music
	artworkView.userInteractionEnabled = YES;
	[artworkView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(artworkTapped:)]];
	self.artworkView = artworkView;

	// Apple Music icon in the corner of the album art, marking it as a link
	CGFloat iconSize = compact ? SRCompactAppleMusicIconSize : SRExpandedAppleMusicIconSize;
	CGFloat iconInset = compact ? 3.f : 12.f;
	UIImageView *appleMusicIconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppleMusicIcon"]];
	appleMusicIconView.alpha = 0.f;
	appleMusicIconView.layer.shadowColor = [UIColor blackColor].CGColor;
	appleMusicIconView.layer.shadowOpacity = 0.3f;
	appleMusicIconView.layer.shadowRadius = compact ? 2.f : 4.f;
	appleMusicIconView.layer.shadowOffset = CGSizeZero;
	appleMusicIconView.translatesAutoresizingMaskIntoConstraints = NO;
	[artworkView addSubview:appleMusicIconView];
	[NSLayoutConstraint activateConstraints:@[
		[appleMusicIconView.widthAnchor constraintEqualToConstant:iconSize],
		[appleMusicIconView.heightAnchor constraintEqualToConstant:iconSize],
		[appleMusicIconView.trailingAnchor constraintEqualToAnchor:artworkView.trailingAnchor constant:-iconInset],
		[appleMusicIconView.bottomAnchor constraintEqualToAnchor:artworkView.bottomAnchor constant:-iconInset],
	]];
	self.appleMusicIconView = appleMusicIconView;

	CBAutoScrollLabel *titleLabel = [[CBAutoScrollLabel alloc] init];
	titleLabel.font = compact ? [UIFont systemFontOfSize:16.f weight:UIFontWeightSemibold] : [UIFont systemFontOfSize:24.f weight:UIFontWeightBold];
	titleLabel.textColor = [UIColor labelColor];
	titleLabel.textAlignment = compact ? NSTextAlignmentLeft : NSTextAlignmentCenter;
	titleLabel.labelSpacing = 30;
	titleLabel.pauseInterval = SRNowPlayingPauseInterval;
	titleLabel.fadeLength = 8.f;
	self.titleLabel = titleLabel;

	CBAutoScrollLabel *subtitleLabel = [[CBAutoScrollLabel alloc] init];
	subtitleLabel.font = compact ? [UIFont systemFontOfSize:14.f] : [UIFont systemFontOfSize:17.f];
	subtitleLabel.textColor = [UIColor secondaryLabelColor];
	subtitleLabel.textAlignment = compact ? NSTextAlignmentLeft : NSTextAlignmentCenter;
	subtitleLabel.labelSpacing = 30;
	subtitleLabel.pauseInterval = SRNowPlayingPauseInterval;
	subtitleLabel.fadeLength = 8.f;
	// the expanded layout always reserves space for the subtitle, so the artwork and controls don't move
	subtitleLabel.hidden = compact;
	subtitleLabel.text = @" ";
	self.subtitleLabel = subtitleLabel;

	CGFloat playSize = compact ? 30.f : 32.f;
	CGFloat skipSize = compact ? 22.f : 24.f;
	self.previousButton = [self transportButtonWithSymbol:@"backward.fill" pointSize:skipSize action:@selector(previousButtonPressed:)];
	self.previousButton.accessibilityLabel = NSLocalizedString(@"Previous", @"Previous");
	self.playButton = [self transportButtonWithSymbol:@"play.fill" pointSize:playSize action:@selector(playButtonPressed:)];
	[self addLoadingIndicatorToButton:self.playButton style:UIActivityIndicatorViewStyleLarge scale:0.75f];
	self.nextButton = [self transportButtonWithSymbol:@"forward.fill" pointSize:skipSize action:@selector(nextButtonPressed:)];
	self.nextButton.accessibilityLabel = NSLocalizedString(@"Next", @"Next");
	// secondary buttons on both sides of the transport controls share one style
	CGFloat secondarySize = compact ? 19.f : 21.f;
	self.favoriteButton = [self secondaryButtonWithSymbol:@"star" pointSize:secondarySize action:@selector(favoriteButtonPressed:)];
	self.routeButton = [self secondaryButtonWithSymbol:@"airplay.audio" pointSize:secondarySize action:nil];
	if (compact) {
		self.inlinePlayButton = [self transportButtonWithSymbol:@"play.fill" pointSize:22.f action:@selector(playButtonPressed:)];
		[self addLoadingIndicatorToButton:self.inlinePlayButton style:UIActivityIndicatorViewStyleMedium scale:1.f];
		self.inlineNextButton = [self transportButtonWithSymbol:@"forward.fill" pointSize:18.f action:@selector(nextButtonPressed:)];
		self.inlineNextButton.accessibilityLabel = NSLocalizedString(@"Next", @"Next");
		self.inlinePlayButton.hidden = YES;
		self.inlineNextButton.hidden = YES;
		self.inlinePlayButton.alpha = 0.f;
		self.inlineNextButton.alpha = 0.f;
	}

	UIButtonConfiguration *sleepConfiguration = [UIButtonConfiguration tintedButtonConfiguration];
	sleepConfiguration.image = [UIImage systemImageNamed:@"moon.zzz.fill"];
	sleepConfiguration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:11.f weight:UIImageSymbolWeightSemibold];
	sleepConfiguration.imagePadding = 4.f;
	sleepConfiguration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	sleepConfiguration.contentInsets = NSDirectionalEdgeInsetsMake(4.f, 8.f, 4.f, 8.f);
	sleepConfiguration.baseForegroundColor = [SRAppearance mainColor];
	sleepConfiguration.baseBackgroundColor = [SRAppearance mainColor];
	sleepConfiguration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
		NSMutableDictionary *result = [attributes mutableCopy];
		result[NSFontAttributeName] = [UIFont monospacedDigitSystemFontOfSize:12.f weight:UIFontWeightSemibold];
		return result;
	};
	UIButton *sleepTimerButton = [UIButton buttonWithConfiguration:sleepConfiguration primaryAction:nil];
	sleepTimerButton.showsMenuAsPrimaryAction = YES;
	sleepTimerButton.menu = [UIMenu menuWithTitle:NSLocalizedString(@"SleepTimer", @"Sleep timer") children:@[
		[UIAction actionWithTitle:NSLocalizedString(@"CancelSleepTimer", @"Cancel sleep timer")
							image:[UIImage systemImageNamed:@"xmark"]
					   identifier:nil
						  handler:^(__kindof UIAction *action) {
			[[SRPlaybackManager sharedManager] cancelSleepTimer];
		}],
	]];
	sleepTimerButton.hidden = YES;
	[sleepTimerButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[sleepTimerButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	self.sleepTimerButton = sleepTimerButton;

	// The route picker's own glyph can't be styled, so a matching (purely visual) button is shown instead.
	// The real picker sits on top of it, almost fully transparent, and handles the touches itself.
	self.routeButton.userInteractionEnabled = NO;
	self.routeButton.isAccessibilityElement = NO;
	self.routeButton.translatesAutoresizingMaskIntoConstraints = NO;
	AVRoutePickerView *routePickerView = [[AVRoutePickerView alloc] init];
	routePickerView.prioritizesVideoDevices = NO;
	routePickerView.alpha = 0.02f; // views below 0.01 alpha don't receive touches
	routePickerView.accessibilityLabel = NSLocalizedString(@"AudioOutput", @"Audio output");
	routePickerView.translatesAutoresizingMaskIntoConstraints = NO;
	UIView *routeContainer = [[UIView alloc] init];
	routeContainer.translatesAutoresizingMaskIntoConstraints = NO;
	[routeContainer addSubview:self.routeButton];
	[routeContainer addSubview:routePickerView];
	for (UIView *view in @[self.routeButton, routePickerView]) {
		[NSLayoutConstraint activateConstraints:@[
			[view.topAnchor constraintEqualToAnchor:routeContainer.topAnchor],
			[view.bottomAnchor constraintEqualToAnchor:routeContainer.bottomAnchor],
			[view.leadingAnchor constraintEqualToAnchor:routeContainer.leadingAnchor],
			[view.trailingAnchor constraintEqualToAnchor:routeContainer.trailingAnchor],
		]];
	}
	self.routePickerView = routePickerView;
	self.routeContainer = routeContainer;

	self.transportRow = [self createTransportRow];
}

- (UIView *)createTransportRow {
	// [favorite]  ...  [previous] [play] [next]  ...  [route picker]
	UIView *leadingSpacer = [[UIView alloc] init];
	UIView *trailingSpacer = [[UIView alloc] init];
	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.favoriteButton, leadingSpacer, self.previousButton, self.playButton, self.nextButton, trailingSpacer, self.routeContainer]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = self.style == SRPlayerStyleCompact ? 8.f : 16.f;
	[leadingSpacer.widthAnchor constraintEqualToAnchor:trailingSpacer.widthAnchor].active = YES;
	CGFloat size = self.style == SRPlayerStyleCompact ? 52.f : 56.f;
	for (UIButton *button in @[self.previousButton, self.playButton, self.nextButton]) {
		[button.widthAnchor constraintEqualToConstant:size].active = YES;
		[button.heightAnchor constraintEqualToConstant:size].active = YES;
	}
	for (UIView *view in @[self.favoriteButton, self.routeContainer]) {
		[view.widthAnchor constraintEqualToConstant:44.f].active = YES;
		[view.heightAnchor constraintEqualToConstant:44.f].active = YES;
	}
	return row;
}

- (void)setupCompactLayout {
	self.view.backgroundColor = [UIColor clearColor];

	SRPlatterView *platter = [[SRPlatterView alloc] initWithCornerRadius:28.f];
	platter.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:platter];
	self.platter = platter;

	[self.artworkView.widthAnchor constraintEqualToConstant:SRCompactArtworkSize].active = YES;
	[self.artworkView.heightAnchor constraintEqualToConstant:SRCompactArtworkSize].active = YES;

	UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel]];
	labels.axis = UILayoutConstraintAxisVertical;
	labels.spacing = 2.f;

	for (UIButton *button in @[self.inlinePlayButton, self.inlineNextButton]) {
		[button.widthAnchor constraintEqualToConstant:44.f].active = YES;
		[button.heightAnchor constraintEqualToConstant:44.f].active = YES;
	}
	UIStackView *infoRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.artworkView, labels, self.sleepTimerButton, self.inlinePlayButton, self.inlineNextButton]];
	infoRow.axis = UILayoutConstraintAxisHorizontal;
	infoRow.alignment = UIStackViewAlignmentCenter;
	infoRow.spacing = 12.f;
	[infoRow setCustomSpacing:8.f afterView:self.sleepTimerButton];
	[infoRow setCustomSpacing:0.f afterView:self.inlinePlayButton];
	UITapGestureRecognizer *nowPlayingRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nowPlayingTapped:)];
	nowPlayingRecognizer.delegate = self;
	[infoRow addGestureRecognizer:nowPlayingRecognizer];
	[infoRow addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[infoRow, self.transportRow]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 8.f;
	stack.layoutMarginsRelativeArrangement = YES;
	stack.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(12.f, 12.f, 12.f, 12.f);
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[platter.contentView addSubview:stack];

	[NSLayoutConstraint activateConstraints:@[
		[platter.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[platter.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[platter.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[platter.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[stack.topAnchor constraintEqualToAnchor:platter.contentView.topAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:platter.contentView.bottomAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:platter.contentView.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:platter.contentView.trailingAnchor],
	]];
}

- (void)setupExpandedLayout {
	self.view.backgroundColor = [UIColor systemBackgroundColor];

	// blurred artwork backdrop
	UIImageView *backdropView = [[UIImageView alloc] init];
	backdropView.contentMode = UIViewContentModeScaleAspectFill;
	backdropView.clipsToBounds = YES;
	backdropView.alpha = 0.6f;
	backdropView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:backdropView];
	self.backdropView = backdropView;
	UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
	blurView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:blurView];

	// artwork
	UIView *artworkContainer = [[UIView alloc] init];
	artworkContainer.translatesAutoresizingMaskIntoConstraints = NO;
	artworkContainer.layer.shadowColor = [UIColor blackColor].CGColor;
	artworkContainer.layer.shadowOpacity = 0.2f;
	artworkContainer.layer.shadowRadius = 24.f;
	artworkContainer.layer.shadowOffset = CGSizeMake(0, 10.f);
	[artworkContainer addSubview:self.artworkView];
	[artworkContainer addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];

	UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel]];
	labels.axis = UILayoutConstraintAxisVertical;
	labels.spacing = 4.f;

	// controls platter
	SRPlatterView *platter = [[SRPlatterView alloc] initWithCornerRadius:32.f];
	platter.translatesAutoresizingMaskIntoConstraints = NO;
	self.platter = platter;

	UIStackView *platterStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.transportRow]];
	platterStack.axis = UILayoutConstraintAxisVertical;
	platterStack.spacing = 4.f;
	if ([NSProcessInfo processInfo].isiOSAppOnMac) {
		// desktop apps have their own volume, independent of the system volume
		[platterStack addArrangedSubview:[self createVolumeRow]];
	}
	platterStack.layoutMarginsRelativeArrangement = YES;
	platterStack.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(12.f, 16.f, 12.f, 16.f);
	platterStack.translatesAutoresizingMaskIntoConstraints = NO;
	[platter.contentView addSubview:platterStack];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[artworkContainer, labels, platter, self.sleepTimerButton]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 24.f;
	[stack setCustomSpacing:28.f afterView:labels];
	[stack setCustomSpacing:16.f afterView:platter];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:stack];

	UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
	NSLayoutConstraint *preferredWidth = [stack.widthAnchor constraintEqualToConstant:SRExpandedMaximumWidth];
	preferredWidth.priority = UILayoutPriorityDefaultHigh;
	NSLayoutConstraint *artworkFillWidth = [artworkContainer.widthAnchor constraintEqualToAnchor:stack.widthAnchor multiplier:0.8f];
	artworkFillWidth.priority = UILayoutPriorityDefaultHigh - 10;
	[artworkContainer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];

	[NSLayoutConstraint activateConstraints:@[
		[backdropView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[backdropView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[backdropView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[backdropView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[blurView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[blurView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[blurView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[blurView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

		[stack.centerXAnchor constraintEqualToAnchor:safeArea.centerXAnchor],
		[stack.centerYAnchor constraintEqualToAnchor:safeArea.centerYAnchor],
		[stack.widthAnchor constraintLessThanOrEqualToAnchor:safeArea.widthAnchor constant:-64.f],
		[stack.heightAnchor constraintLessThanOrEqualToAnchor:safeArea.heightAnchor constant:-48.f],
		preferredWidth,

		[artworkContainer.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor multiplier:0.8f],
		// leave room for the title and controls (especially in landscape)
		[artworkContainer.heightAnchor constraintLessThanOrEqualToAnchor:safeArea.heightAnchor multiplier:0.5f],
		[artworkContainer.heightAnchor constraintEqualToAnchor:artworkContainer.widthAnchor],
		artworkFillWidth,
		[self.artworkView.topAnchor constraintEqualToAnchor:artworkContainer.topAnchor],
		[self.artworkView.bottomAnchor constraintEqualToAnchor:artworkContainer.bottomAnchor],
		[self.artworkView.leadingAnchor constraintEqualToAnchor:artworkContainer.leadingAnchor],
		[self.artworkView.trailingAnchor constraintEqualToAnchor:artworkContainer.trailingAnchor],

		[labels.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[platter.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[platterStack.topAnchor constraintEqualToAnchor:platter.contentView.topAnchor],
		[platterStack.bottomAnchor constraintEqualToAnchor:platter.contentView.bottomAnchor],
		[platterStack.leadingAnchor constraintEqualToAnchor:platter.contentView.leadingAnchor],
		[platterStack.trailingAnchor constraintEqualToAnchor:platter.contentView.trailingAnchor],
	]];
}

- (UIView *)createVolumeRow {
	// [min] ---slider--- [max]
	UIButton *minimumButton = [self secondaryButtonWithSymbol:@"speaker.fill" pointSize:13.f action:@selector(minimumVolumeButtonPressed:)];
	minimumButton.accessibilityLabel = NSLocalizedString(@"Mute", @"Mute");
	UIButton *maximumButton = [self secondaryButtonWithSymbol:@"speaker.wave.3.fill" pointSize:13.f action:@selector(maximumVolumeButtonPressed:)];
	maximumButton.accessibilityLabel = NSLocalizedString(@"MaximumVolume", @"Maximum volume");
	for (UIButton *button in @[minimumButton, maximumButton]) {
		[button.widthAnchor constraintEqualToConstant:32.f].active = YES;
		[button.heightAnchor constraintEqualToConstant:32.f].active = YES;
	}

	UISlider *volumeSlider = [[UISlider alloc] init];
	volumeSlider.minimumValue = 0.f;
	volumeSlider.maximumValue = 1.f;
	volumeSlider.value = [SRDataManager sharedManager].playerVolume;
	volumeSlider.minimumTrackTintColor = [UIColor secondaryLabelColor];
	volumeSlider.accessibilityLabel = NSLocalizedString(@"Volume", @"Volume");
	[volumeSlider addTarget:self action:@selector(volumeSliderChanged:) forControlEvents:UIControlEventValueChanged];
	self.volumeSlider = volumeSlider;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[minimumButton, volumeSlider, maximumButton]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 8.f;
	return row;
}

- (UIButton *)transportButtonWithSymbol:(NSString *)name pointSize:(CGFloat)pointSize action:(SEL)action {
	UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
	configuration.image = [UIImage systemImageNamed:name];
	configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
	configuration.contentInsets = NSDirectionalEdgeInsetsZero;
	configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	configuration.baseForegroundColor = [UIColor labelColor];
	UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
	button.pointerInteractionEnabled = YES;
	// round highlight while the button is pressed
	button.configurationUpdateHandler = ^(__kindof UIButton *button) {
		UIButtonConfiguration *updatedConfiguration = button.configuration;
		UIBackgroundConfiguration *background = [UIBackgroundConfiguration clearConfiguration];
		background.backgroundColor = button.isHighlighted ? [[UIColor labelColor] colorWithAlphaComponent:0.12f] : [UIColor clearColor];
		updatedConfiguration.background = background;
		button.configuration = updatedConfiguration;
	};
	if (action) {
		[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	}
	[button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	return button;
}

- (UIButton *)secondaryButtonWithSymbol:(NSString *)name pointSize:(CGFloat)pointSize action:(SEL)action {
	UIButton *button = [self transportButtonWithSymbol:name pointSize:pointSize action:action];
	UIButtonConfiguration *configuration = button.configuration;
	configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium];
	configuration.baseForegroundColor = [UIColor secondaryLabelColor];
	button.configuration = configuration;
	return button;
}

- (void)addLoadingIndicatorToButton:(UIButton *)button style:(UIActivityIndicatorViewStyle)style scale:(CGFloat)scale {
	// the button configuration's built-in activity indicator is too small next to the transport symbols
	UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
	indicator.color = [UIColor labelColor];
	indicator.hidesWhenStopped = YES;
	indicator.userInteractionEnabled = NO;
	indicator.transform = CGAffineTransformMakeScale(scale, scale);
	indicator.translatesAutoresizingMaskIntoConstraints = NO;
	[button addSubview:indicator];
	[NSLayoutConstraint activateConstraints:@[
		[indicator.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
		[indicator.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
	]];
	if (!self.loadingIndicators) {
		self.loadingIndicators = [NSMapTable weakToWeakObjectsMapTable];
	}
	[self.loadingIndicators setObject:indicator forKey:button];
}

#pragma mark - Collapsing

- (void)setCollapsed:(BOOL)collapsed animated:(BOOL)animated {
	if (self.style != SRPlayerStyleCompact || _collapsed == collapsed) {
		return;
	}
	_collapsed = collapsed;
	[self loadViewIfNeeded];
	void (^changes)(void) = ^{
		[self applyRowVisibility];
		[self.view.superview layoutIfNeeded];
	};
	if (animated) {
		[UIView animateWithDuration:0.4
							  delay:0
			 usingSpringWithDamping:0.9f
			  initialSpringVelocity:0
							options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
						 animations:changes
						 completion:^(BOOL finished) {
			[self notifyLayoutChange];
		}];
	} else {
		changes();
		[self notifyLayoutChange];
	}
}

- (void)applyRowVisibility {
	BOOL collapsed = self.collapsed;
	// UIStackView misbehaves when hidden is set to the value it already has inside an animation
	if (self.transportRow.hidden != collapsed) {
		self.transportRow.hidden = collapsed;
		self.transportRow.alpha = collapsed ? 0.f : 1.f;
	}
	if (self.inlinePlayButton && self.inlinePlayButton.hidden != !collapsed) {
		self.inlinePlayButton.hidden = !collapsed;
		self.inlineNextButton.hidden = !collapsed;
	}
	// fade in addition to the stack view's size animation
	CGFloat inlineAlpha = collapsed ? 1.f : 0.f;
	self.inlinePlayButton.alpha = inlineAlpha;
	self.inlineNextButton.alpha = inlineAlpha;
}

- (void)notifyLayoutChange {
	if (self.layoutChangeHandler) {
		self.layoutChangeHandler();
	}
}

#pragma mark - Notifications

- (void)registerForNotifications {
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	for (NSString *name in @[SRRadioPlayerStateDidChangeNotification,
							 SRRadioPlayerMetaDataDidChangeNotification,
							 SRDataManagerDidSelectStation,
							 SRDataManagerDidLoadStations,
							 SRDataManagerDidChangeStations,
							 SRDataManagerDidChangeFavorites,
							 SRDataManagerDidChangeStationList,
							 SRPlaybackManagerDidChangeSleepTimer,
							 SRPlaybackManagerDidUpdateNowPlayingText]) {
		[nc addObserver:self selector:@selector(playbackChanged:) name:name object:nil];
	}
}

- (void)playbackChanged:(NSNotification *)notification {
	// coalesce bursts of notifications into a single refresh on the main queue
	if (!self.refreshScheduled) {
		self.refreshScheduled = YES;
		dispatch_async(dispatch_get_main_queue(), ^{
			self.refreshScheduled = NO;
			[self refresh];
		});
	}
}

#pragma mark - Refresh

- (void)refresh {
	if (!self.isViewLoaded) {
		return;
	}
	SRDataManager *dataManager = [SRDataManager sharedManager];
	SRPlaybackManager *playbackManager = [SRPlaybackManager sharedManager];
	SRRadioPlayer *player = [SRRadioPlayer sharedPlayer];
	SRRadioStation *station = dataManager.selectedRadioStation;

	BOOL isCurrentStation = station != nil && player.currentRadioStation.stationId == station.stationId;
	SRRadioPlayerState state = isCurrentStation ? player.state : SRRadioPlayerStateStopped;
	BOOL loading = state == SRRadioPlayerStateOpening || state == SRRadioPlayerStateBuffering;
	BOOL active = loading || state == SRRadioPlayerStatePlaying;

	// labels (the subtitle is only shown when the station provides now playing info)
	NSString *title = station.name ?: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	if (![self.titleLabel.text isEqualToString:title]) {
		self.titleLabel.text = title;
	}
	NSString *subtitle = playbackManager.nowPlayingText;
	BOOL hasSubtitle = subtitle.length > 0;
	if (self.style == SRPlayerStyleExpanded) {
		// keep the line (and its height) even without now playing info
		subtitle = hasSubtitle ? subtitle : @" ";
		if (![self.subtitleLabel.text isEqualToString:subtitle]) {
			self.subtitleLabel.text = subtitle;
		}
	} else {
		if (hasSubtitle && ![self.subtitleLabel.text isEqualToString:subtitle]) {
			self.subtitleLabel.text = subtitle;
		}
		if (self.subtitleLabel.hidden == hasSubtitle) {
			self.subtitleLabel.hidden = !hasSubtitle;
		}
	}

	// play buttons
	NSMutableArray *playButtons = [NSMutableArray arrayWithObject:self.playButton];
	if (self.inlinePlayButton) {
		[playButtons addObject:self.inlinePlayButton];
	}
	for (UIButton *button in playButtons) {
		// while loading, the symbol is replaced by a spinner (the button stays tappable to stop loading)
		UIButtonConfiguration *playConfiguration = button.configuration;
		playConfiguration.image = loading ? nil : [UIImage systemImageNamed:active ? @"pause.fill" : @"play.fill"];
		button.configuration = playConfiguration;
		UIActivityIndicatorView *indicator = [self.loadingIndicators objectForKey:button];
		if (loading && !indicator.isAnimating) {
			[indicator startAnimating];
		} else if (!loading && indicator.isAnimating) {
			[indicator stopAnimating];
		}
		button.enabled = station != nil;
		button.accessibilityLabel = active ? NSLocalizedString(@"Pause", @"Pause") : NSLocalizedString(@"Play", @"Play");
	}

	NSInteger stationCount = [dataManager stationsForList:dataManager.selectedStationList].count;
	if (stationCount == 0) {
		stationCount = dataManager.stations.count;
	}
	self.previousButton.enabled = stationCount > 1;
	self.nextButton.enabled = stationCount > 1;
	self.inlineNextButton.enabled = stationCount > 1;

	// favorite button (the filled symbol marks the active state)
	BOOL favorite = [dataManager isFavoriteRadioStation:station];
	UIButtonConfiguration *favoriteConfiguration = self.favoriteButton.configuration;
	favoriteConfiguration.image = [UIImage systemImageNamed:favorite ? @"star.fill" : @"star"];
	self.favoriteButton.configuration = favoriteConfiguration;
	self.favoriteButton.enabled = station != nil;
	self.favoriteButton.accessibilityLabel = favorite ? NSLocalizedString(@"RemoveFromFavorites", nil) : NSLocalizedString(@"AddToFavorites", nil);

	// sleep timer
	BOOL sleepTimerActive = playbackManager.sleepTimerActive;
	if (sleepTimerActive) {
		UIButtonConfiguration *sleepConfiguration = self.sleepTimerButton.configuration;
		sleepConfiguration.title = [self formattedTime:playbackManager.sleepTimerTimeRemaining];
		self.sleepTimerButton.configuration = sleepConfiguration;
		self.sleepTimerButton.accessibilityLabel = NSLocalizedString(@"SleepTimer", @"Sleep timer");
	}
	if (self.sleepTimerButton.hidden == sleepTimerActive) {
		self.sleepTimerButton.hidden = !sleepTimerActive;
	}

	// artwork
	[self updateArtworkForStation:station];
	[self updateAppleMusicLink];
}

- (void)updateAppleMusicLink {
	BOOL hasLink = [SRPlaybackManager sharedManager].songURL != nil;
	CGFloat alpha = hasLink ? 1.f : 0.f;
	if (self.appleMusicIconView.alpha != alpha) {
		// fade along with the album art
		[UIView animateWithDuration:0.25 animations:^{
			self.appleMusicIconView.alpha = alpha;
		}];
	}
	self.artworkView.isAccessibilityElement = hasLink;
	self.artworkView.accessibilityLabel = hasLink ? NSLocalizedString(@"OpenInAppleMusic", @"Open in Apple Music") : nil;
	self.artworkView.accessibilityTraits = hasLink ? UIAccessibilityTraitButton | UIAccessibilityTraitImage : UIAccessibilityTraitImage;
}

- (void)updateArtworkForStation:(SRRadioStation *)station {
	// album art of the current song, when the catalog lookup found one
	UIImage *songArtwork = [SRPlaybackManager sharedManager].songArtworkImage;
	if (songArtwork) {
		NSString *songArtworkKey = [NSString stringWithFormat:@"song|%p", songArtwork];
		if (![songArtworkKey isEqualToString:self.artworkKey]) {
			self.artworkKey = songArtworkKey;
			[self setArtworkImage:songArtwork animated:YES];
		}
		return;
	}
	BOOL showedSongArtwork = [self.artworkKey hasPrefix:@"song|"];
	
	CGFloat width = self.style == SRPlayerStyleCompact ? SRCompactArtworkWidth : SRExpandedArtworkWidth;
	// the icon url changes when the station artwork is updated on the server
	NSString *artworkKey = [NSString stringWithFormat:@"%ld|%@", (long)station.stationId, [station iconUrlForWidth:width].absoluteString];
	if ([artworkKey isEqualToString:self.artworkKey]) {
		return;
	}
	self.artworkKey = artworkKey;
	UIImage *placeholder = [UIImage imageNamed:@"PlaceholderArtwork"];
	UIImage *cachedImage = [station cachedArtworkImageForWidth:width];
	// cross-fade when going back from song artwork to the station artwork
	[self setArtworkImage:cachedImage ?: placeholder animated:showedSongArtwork];
	if (station && !cachedImage) {
		__weak SRPlayerViewController *weakSelf = self;
		[station loadArtworkImageForWidth:width completion:^(UIImage *image) {
			SRPlayerViewController *strongSelf = weakSelf;
			if (strongSelf && image && [strongSelf.artworkKey isEqualToString:artworkKey]) {
				[strongSelf setArtworkImage:image animated:YES];
			}
		}];
	}
}

- (void)setArtworkImage:(UIImage *)image animated:(BOOL)animated {
	NSTimeInterval duration = animated ? 0.25 : 0.0;
	NSMutableArray *imageViews = [NSMutableArray arrayWithObject:self.artworkView];
	if (self.backdropView) {
		[imageViews addObject:self.backdropView];
	}
	for (UIImageView *imageView in imageViews) {
		[UIView transitionWithView:imageView
						  duration:duration
						   options:UIViewAnimationOptionTransitionCrossDissolve
						animations:^{
			imageView.image = image;
		} completion:nil];
	}
}

- (NSString *)formattedTime:(NSTimeInterval)interval {
	NSInteger seconds = (NSInteger)ceil(MAX(interval, 0));
	NSInteger hours = seconds / 3600;
	NSInteger minutes = (seconds / 60) % 60;
	if (hours > 0) {
		return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)(seconds % 60)];
	}
	return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)(seconds % 60)];
}

#pragma mark - Actions

- (void)playButtonPressed:(id)sender {
	[[SRPlaybackManager sharedManager] togglePlayPause];
}

- (void)previousButtonPressed:(id)sender {
	[[SRPlaybackManager sharedManager] playPreviousStation];
}

- (void)nextButtonPressed:(id)sender {
	[[SRPlaybackManager sharedManager] playNextStation];
}

- (void)volumeSliderChanged:(UISlider *)sender {
	[self setPlayerVolume:sender.value];
}

- (void)minimumVolumeButtonPressed:(id)sender {
	[self setPlayerVolume:0.f];
}

- (void)maximumVolumeButtonPressed:(id)sender {
	[self setPlayerVolume:1.f];
}

- (void)setPlayerVolume:(float)volume {
	[SRDataManager sharedManager].playerVolume = volume;
	[[SRRadioPlayer sharedPlayer] updateVolume];
	if (self.volumeSlider.value != volume) {
		[self.volumeSlider setValue:volume animated:YES];
	}
}

#pragma mark - Route picker highlight

- (void)observeRoutePickerHighlight {
	// mirror the highlight of the (invisible) system route button on the visible one, when possible
	UIControl *control = [self controlInView:self.routePickerView];
	if (control && ![control.allTargets containsObject:self]) {
		[control addTarget:self action:@selector(routePickerTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
		[control addTarget:self action:@selector(routePickerTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
	}
}

- (UIControl *)controlInView:(UIView *)view {
	for (UIView *subview in view.subviews) {
		if ([subview isKindOfClass:[UIControl class]]) {
			return (UIControl *)subview;
		}
		UIControl *control = [self controlInView:subview];
		if (control) {
			return control;
		}
	}
	return nil;
}

- (void)routePickerTouchDown:(id)sender {
	self.routeButton.highlighted = YES;
}

- (void)routePickerTouchUp:(id)sender {
	self.routeButton.highlighted = NO;
}

- (void)favoriteButtonPressed:(id)sender {
	SRDataManager *dataManager = [SRDataManager sharedManager];
	SRRadioStation *station = dataManager.selectedRadioStation;
	if ([dataManager isFavoriteRadioStation:station]) {
		[dataManager removeFavoriteRadioStation:station];
	} else {
		[dataManager addFavoriteRadioStation:station];
	}
}

- (void)artworkTapped:(UITapGestureRecognizer *)recognizer {
	if ([SRPlaybackManager sharedManager].songURL) {
		[self openSongInAppleMusic];
	} else if (self.style == SRPlayerStyleCompact) {
		[self nowPlayingTapped:recognizer];
	}
}

- (void)openSongInAppleMusic {
	NSURL *songURL = [SRPlaybackManager sharedManager].songURL;
	if (songURL) {
		[[UIApplication sharedApplication] openURL:songURL options:@{} completionHandler:nil];
	}
}

- (void)nowPlayingTapped:(UITapGestureRecognizer *)recognizer {
	if (self.collapsed) {
		[self setCollapsed:NO animated:YES];
	} else if (self.nowPlayingTapHandler) {
		self.nowPlayingTapHandler();
	}
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
	// taps on the album art are handled by the artwork itself
	return ![touch.view isDescendantOfView:self.artworkView];
}

#pragma mark - UIContextMenuInteractionDelegate

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
	// buttons in the info row have their own actions
	UIView *hitView = [interaction.view hitTest:location withEvent:nil];
	if ([hitView isKindOfClass:[UIControl class]] || [hitView.superview isKindOfClass:[UIControl class]]) {
		return nil;
	}
	SRPlaybackManager *playbackManager = [SRPlaybackManager sharedManager];
	NSURL *songURL = playbackManager.songURL;
	NSString *nowPlayingText = playbackManager.nowPlayingText;
	if (!songURL && nowPlayingText.length == 0) {
		return nil;
	}
	__weak SRPlayerViewController *weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
		NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
		if (songURL) {
			[actions addObject:[UIAction actionWithTitle:NSLocalizedString(@"OpenInAppleMusic", @"Open in Apple Music")
												   image:[UIImage systemImageNamed:@"arrow.up.forward.app"]
											  identifier:nil
												 handler:^(__kindof UIAction *action) {
				[weakSelf openSongInAppleMusic];
			}]];
		}
		if (nowPlayingText.length > 0) {
			[actions addObject:[UIAction actionWithTitle:NSLocalizedString(@"CopySong", @"Copy song")
												   image:[UIImage systemImageNamed:@"doc.on.doc"]
											  identifier:nil
												 handler:^(__kindof UIAction *action) {
				[UIPasteboard generalPasteboard].string = nowPlayingText;
			}]];
		}
		return [UIMenu menuWithTitle:nowPlayingText ?: @"" children:actions];
	}];
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configuration:(UIContextMenuConfiguration *)configuration highlightPreviewForItemWithIdentifier:(id<NSCopying>)identifier {
	return [self artworkPreview];
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configuration:(UIContextMenuConfiguration *)configuration dismissalPreviewForItemWithIdentifier:(id<NSCopying>)identifier {
	return [self artworkPreview];
}

- (UITargetedPreview *)artworkPreview {
	// the menu lifts the album art (the info row itself is transparent)
	UIPreviewParameters *parameters = [[UIPreviewParameters alloc] init];
	parameters.visiblePath = [UIBezierPath bezierPathWithRoundedRect:self.artworkView.bounds cornerRadius:self.artworkView.layer.cornerRadius];
	return [[UITargetedPreview alloc] initWithView:self.artworkView parameters:parameters];
}

@end
