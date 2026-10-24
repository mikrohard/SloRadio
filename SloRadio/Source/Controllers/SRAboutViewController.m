//
//  SRAboutViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 5. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAboutViewController.h"
#import "SRAcknowledgementsViewController.h"

@import MessageUI;

static NSString * const SRCopyrightText = @"© 2024 Jernej Fijačko";
static NSString * const SRContactEmail = @"sloradio@jernej.org";
static NSString * const SRAboutCellIdentifier = @"AboutCell";

@interface SRAboutViewController () <MFMailComposeViewControllerDelegate>

@end

@implementation SRAboutViewController

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		self.title = NSLocalizedString(@"About", @"About");
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:SRAboutCellIdentifier];
	[self setupHeaderView];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	// size the header to fit its content
	UIView *headerView = self.tableView.tableHeaderView;
	CGFloat width = CGRectGetWidth(self.tableView.bounds);
	CGFloat height = [headerView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
								 withHorizontalFittingPriority:UILayoutPriorityRequired
									   verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
	if (CGRectGetHeight(headerView.frame) != height || CGRectGetWidth(headerView.frame) != width) {
		headerView.frame = CGRectMake(0, 0, width, height);
		self.tableView.tableHeaderView = headerView;
	}
}

#pragma mark - Setup

- (void)setupHeaderView {
	UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AboutIcon"]];
	iconView.contentMode = UIViewContentModeScaleAspectFit;
	iconView.layer.shadowColor = [UIColor blackColor].CGColor;
	iconView.layer.shadowOpacity = 0.15f;
	iconView.layer.shadowRadius = 12.f;
	iconView.layer.shadowOffset = CGSizeMake(0, 4.f);
	[iconView.widthAnchor constraintEqualToConstant:96.f].active = YES;
	[iconView.heightAnchor constraintEqualToConstant:96.f].active = YES;

	NSString *name = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
	NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	NSString *build = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];

	UILabel *nameLabel = [[UILabel alloc] init];
	nameLabel.font = [UIFont systemFontOfSize:24.f weight:UIFontWeightBold];
	nameLabel.text = name;

	UILabel *versionLabel = [[UILabel alloc] init];
	versionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	versionLabel.adjustsFontForContentSizeCategory = YES;
	versionLabel.textColor = [UIColor secondaryLabelColor];
	versionLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), version, build];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, nameLabel, versionLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 4.f;
	[stack setCustomSpacing:16.f afterView:iconView];
	stack.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *headerView = [[UIView alloc] init];
	[headerView addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:headerView.topAnchor constant:24.f],
		[stack.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-16.f],
		[stack.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor],
	]];
	self.tableView.tableHeaderView = headerView;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 2 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SRAboutCellIdentifier forIndexPath:indexPath];
	UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	if (indexPath.section == 0 && indexPath.row == 0) {
		content.text = NSLocalizedString(@"Copyright", nil);
		content.secondaryText = SRCopyrightText;
		content.image = [SRAppearance iconWithSymbolName:@"c.circle.fill" backgroundColor:[UIColor systemGrayColor]];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	else if (indexPath.section == 0) {
		content.text = NSLocalizedString(@"Contact", nil);
		content.secondaryText = SRContactEmail;
		content.image = [SRAppearance iconWithSymbolName:@"envelope.fill" backgroundColor:[UIColor systemBlueColor]];
	}
	else {
		content.text = NSLocalizedString(@"Acknowledgements", nil);
		content.image = [SRAppearance iconWithSymbolName:@"heart.fill" backgroundColor:[UIColor systemPinkColor]];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	cell.contentConfiguration = content;
	return cell;
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.section == 0 && indexPath.row == 1) {
		// contact
		[self presentContactController];
	}
	else if (indexPath.section == 1) {
		// acknowledgements
		[self presentAcknowledgements];
	}
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Actions

- (void)presentContactController {
	if ([MFMailComposeViewController canSendMail]) {
		MFMailComposeViewController *mailController = [[MFMailComposeViewController alloc] init];
		mailController.modalPresentationStyle = UIModalPresentationFormSheet;
		mailController.mailComposeDelegate = self;
		[mailController setSubject:@"SloRadio"];
		[mailController setToRecipients:@[SRContactEmail]];
		[self presentViewController:mailController animated:YES completion:NULL];
	}
	else {
		NSURL *url = [NSURL URLWithString:[@"mailto:" stringByAppendingString:SRContactEmail]];
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	}
}

- (void)presentAcknowledgements {
	SRAcknowledgementsViewController *controller = [[SRAcknowledgementsViewController alloc] init];
	[self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
	[controller dismissViewControllerAnimated:YES completion:NULL];
}

@end
