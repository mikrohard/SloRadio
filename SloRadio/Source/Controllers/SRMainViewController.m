//
//  SRMainViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 27. 04. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRMainViewController.h"
#import "SRRadioViewController.h"
#import "SRPlayerViewController.h"

static CGFloat const SRPlayerCardMargin = 12.f;
static CGFloat const SRPlayerCardMinimumBottomMargin = 16.f;
static CGFloat const SRPlayerCardCollapseScrollDistance = 24.f;

static void *SRTableViewContentOffsetContext = &SRTableViewContentOffsetContext;

@interface SRMainViewController () <UISplitViewControllerDelegate>

@property (nonatomic, strong) UISplitViewController *splitController;
@property (nonatomic, strong) SRRadioViewController *radioController;
@property (nonatomic, strong) UINavigationController *radioNavigationController;
@property (nonatomic, strong) SRPlayerViewController *playerPanelController;
@property (nonatomic, strong) SRPlayerViewController *playerCardController;
@property (nonatomic, assign) CGFloat scrollDistance;
@property (nonatomic, assign) CGFloat expandedCardInset;

@end

@implementation SRMainViewController

#pragma mark - Lifecycle

- (void)dealloc {
	if (self.radioController.isViewLoaded) {
		[self.radioController.tableView removeObserver:self forKeyPath:@"contentOffset" context:SRTableViewContentOffsetContext];
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor systemBackgroundColor];
	[self setupSplitController];
	// the split view controller loads its children lazily, but the player card needs the station list's table view
	[self.radioController loadViewIfNeeded];
	[self setupPlayerCard];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self updatePlayerCardVisibility];
}

#pragma mark - Setup

- (void)setupSplitController {
	self.radioController = [[SRRadioViewController alloc] init];
	self.radioNavigationController = [[UINavigationController alloc] initWithRootViewController:self.radioController];
	self.playerPanelController = [[SRPlayerViewController alloc] initWithStyle:SRPlayerStyleExpanded];

	UISplitViewController *splitController = [[UISplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
	[splitController setViewController:self.radioNavigationController forColumn:UISplitViewControllerColumnPrimary];
	[splitController setViewController:self.playerPanelController forColumn:UISplitViewControllerColumnSecondary];
	splitController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
	splitController.preferredSplitBehavior = UISplitViewControllerSplitBehaviorTile;
	splitController.presentsWithGesture = NO;
	splitController.displayModeButtonVisibility = UISplitViewControllerDisplayModeButtonVisibilityNever;
	splitController.preferredPrimaryColumnWidthFraction = 0.4;
	splitController.minimumPrimaryColumnWidth = 320.f;
	splitController.maximumPrimaryColumnWidth = 420.f;
	splitController.delegate = self;

	[self addChildViewController:splitController];
	splitController.view.frame = self.view.bounds;
	splitController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:splitController.view];
	[splitController didMoveToParentViewController:self];
	self.splitController = splitController;
}

- (void)setupPlayerCard {
	SRPlayerViewController *cardController = [[SRPlayerViewController alloc] initWithStyle:SRPlayerStyleCompact];
	__weak SRMainViewController *weakSelf = self;
	cardController.nowPlayingTapHandler = ^{
		[weakSelf.radioController scrollToSelectedStationAnimated:YES];
	};
	cardController.layoutChangeHandler = ^{
		[weakSelf.view setNeedsLayout];
	};
	[self addChildViewController:cardController];
	UIView *cardView = cardController.view;
	cardView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:cardView];
	[cardController didMoveToParentViewController:self];
	self.playerCardController = cardController;

	// keep the card above the home indicator, but never glued to the bottom edge
	UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
	NSLayoutConstraint *bottomPull = [cardView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
	bottomPull.priority = UILayoutPriorityDefaultLow;
	NSLayoutConstraint *preferredWidth = [cardView.widthAnchor constraintEqualToConstant:600.f];
	preferredWidth.priority = UILayoutPriorityDefaultHigh;
	[NSLayoutConstraint activateConstraints:@[
		[cardView.centerXAnchor constraintEqualToAnchor:safeArea.centerXAnchor],
		[cardView.widthAnchor constraintLessThanOrEqualToAnchor:safeArea.widthAnchor constant:-2*SRPlayerCardMargin],
		preferredWidth,
		[cardView.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea.bottomAnchor],
		[cardView.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor constant:-SRPlayerCardMinimumBottomMargin],
		bottomPull,
	]];

	if (@available(iOS 26, *)) {
		// let the station list fade out underneath the floating card
		UIScrollEdgeElementContainerInteraction *interaction = [[UIScrollEdgeElementContainerInteraction alloc] init];
		interaction.scrollView = self.radioController.tableView;
		interaction.edge = UIRectEdgeBottom;
		[cardController.platterView addInteraction:interaction];
	}
	
	// collapse the card while scrolling through the list
	[self.radioController.tableView addObserver:self
									 forKeyPath:@"contentOffset"
										options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
										context:SRTableViewContentOffsetContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != SRTableViewContentOffsetContext) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	UITableView *tableView = self.radioController.tableView;
	if (self.playerCardController.view.hidden || tableView.editing) {
		return;
	}
	CGFloat offset = tableView.contentOffset.y + tableView.adjustedContentInset.top;
	if (offset <= 1.f) {
		// always show the full card at the top of the list
		self.scrollDistance = 0.f;
		[self.playerCardController setCollapsed:NO animated:YES];
		return;
	}
	if (!tableView.isTracking && !tableView.isDragging && !tableView.isDecelerating) {
		// ignore programmatic offset changes (e.g. inset adjustments)
		return;
	}
	CGFloat maximumOffset = tableView.contentSize.height + tableView.adjustedContentInset.bottom - CGRectGetHeight(tableView.bounds);
	if (tableView.contentOffset.y > maximumOffset) {
		// ignore rubber banding at the end of the list
		self.scrollDistance = 0.f;
		return;
	}
	CGFloat delta = [change[NSKeyValueChangeNewKey] CGPointValue].y - [change[NSKeyValueChangeOldKey] CGPointValue].y;
	if ((delta > 0) != (self.scrollDistance > 0)) {
		// direction changed
		self.scrollDistance = 0.f;
	}
	self.scrollDistance += delta;
	if (self.scrollDistance > SRPlayerCardCollapseScrollDistance) {
		[self.playerCardController setCollapsed:YES animated:YES];
	} else if (self.scrollDistance < -SRPlayerCardCollapseScrollDistance) {
		[self.playerCardController setCollapsed:NO animated:YES];
	}
}

#pragma mark - Player card

- (void)updatePlayerCardVisibility {
	BOOL showCard = self.splitController.isCollapsed;
	UIView *cardView = self.playerCardController.view;
	cardView.hidden = !showCard;
	CGFloat bottomInset = 0.f;
	if (showCard) {
		// Always reserve space for the full card in the station list. If the inset followed the collapsed card,
		// the scrollable area would change while scrolling and make the card flip between its states.
		if (!self.playerCardController.isCollapsed) {
			CGFloat cardTop = CGRectGetMinY(cardView.frame);
			CGFloat safeAreaBottom = CGRectGetHeight(self.view.bounds) - self.view.safeAreaInsets.bottom;
			self.expandedCardInset = MAX(0.f, safeAreaBottom - cardTop + 8.f);
		}
		bottomInset = self.expandedCardInset;
	}
	UIEdgeInsets insets = self.radioNavigationController.additionalSafeAreaInsets;
	if (insets.bottom != bottomInset) {
		insets.bottom = bottomInset;
		self.radioNavigationController.additionalSafeAreaInsets = insets;
	}
}

#pragma mark - UISplitViewControllerDelegate

- (UISplitViewControllerColumn)splitViewController:(UISplitViewController *)svc topColumnForCollapsingToProposedTopColumn:(UISplitViewControllerColumn)proposedTopColumn {
	return UISplitViewControllerColumnPrimary;
}

- (void)splitViewControllerDidCollapse:(UISplitViewController *)svc {
	[self.view setNeedsLayout];
}

- (void)splitViewControllerDidExpand:(UISplitViewController *)svc {
	[self.view setNeedsLayout];
}

@end
