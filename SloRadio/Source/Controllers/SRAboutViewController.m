//
//  SRAboutViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 5. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAboutViewController.h"
#import "SRAcknowledgementsViewController.h"
#import "SRTableViewCell.h"

@import MessageUI;

static NSString * const SRCopyrightText = @"© 2024 Jernej Fijačko";
static NSString * const SRContactEmail = @"sloradio@jernej.org";

@interface SRAboutViewController () <MFMailComposeViewControllerDelegate>

@end

@implementation SRAboutViewController

#pragma mark - Lifecycle

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = NSLocalizedString(@"About", @"About");
	}
	return self;
}

- (void)loadView {
	[super loadView];
	[self setupHeaderView];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view from its nib.
	self.tableView.separatorInset = UIEdgeInsetsMake(0.f, 15.f, 0.f, 0.f);
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

#pragma mark - Setup

- (void)setupHeaderView {
	CGFloat margin = 10.f;
	
	UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 0.f)];
	CGRect headerFrame = headerView.frame;
	headerView.backgroundColor = [UIColor clearColor];
	headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	
	UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AboutIcon"]];
	logo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[logo sizeToFit];
	CGRect logoFrame = logo.frame;
	logoFrame.origin.x = roundf((CGRectGetWidth(headerFrame) - CGRectGetWidth(logoFrame))/2);
	logoFrame.origin.y = 3*margin;
	logo.frame = logoFrame;
	[headerView addSubview:logo];
	
	NSString *name = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
	NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	NSString *build = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	NSString *versionString = [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), version, build];
	
	UILabel *nameLabel = [[UILabel alloc] init];
	nameLabel.backgroundColor = [UIColor clearColor];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	nameLabel.font = [SRAppearance mediumApplicationFontWithSize:20];
	nameLabel.text = name;
	[nameLabel sizeToFit];
	CGRect nameFrame = nameLabel.frame;
	nameFrame.origin.y = CGRectGetMaxY(logoFrame) + margin;
	nameFrame.origin.x = roundf((CGRectGetWidth(headerFrame) - CGRectGetWidth(nameFrame))/2);
	nameLabel.frame = nameFrame;
	[headerView addSubview:nameLabel];
	
	UILabel *versionLabel = [[UILabel alloc] init];
	versionLabel.backgroundColor = [UIColor clearColor];
	versionLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	versionLabel.font = [SRAppearance applicationFontWithSize:14];
	versionLabel.text = versionString;
	[versionLabel sizeToFit];
	CGRect versionFrame = versionLabel.frame;
	versionFrame.origin.y = CGRectGetMaxY(nameFrame);
	versionFrame.origin.x = roundf((CGRectGetWidth(headerFrame) - CGRectGetWidth(versionFrame))/2);
	versionLabel.frame = versionFrame;
	[headerView addSubview:versionLabel];
	
	headerFrame.size.height = CGRectGetMaxY(versionFrame) + 3*margin;
	headerView.frame = headerFrame;
	
	self.tableView.tableHeaderView = headerView;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	// Return the number of sections.
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	// Return the number of rows in the section.
	return section == 0 ? 2 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		static NSString *aboutCellIdentifier = @"AboutCellIdentifier";
		UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:aboutCellIdentifier];
		if (!cell) {
			cell = [[SRTableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:aboutCellIdentifier];
		}
		cell.textLabel.textColor = [SRAppearance mainColor];
		cell.textLabel.font = [SRAppearance applicationFontWithSize:17.f];
		cell.textLabel.textAlignment = NSTextAlignmentLeft;
		cell.detailTextLabel.textColor = [SRAppearance textColor];
		cell.detailTextLabel.font = [SRAppearance applicationFontWithSize:17.f];
		if (indexPath.row == 0) {
			// copyright
			cell.textLabel.text = NSLocalizedString(@"Copyright", nil);
			cell.detailTextLabel.text = SRCopyrightText;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		else {
			// contact
			cell.textLabel.text = NSLocalizedString(@"Contact", nil);
			cell.detailTextLabel.text = SRContactEmail;
			cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		}
		return cell;
	}
	else {
		// Acknowledgements
		static NSString *cellIdentifier = @"AcknowledgementsCellIdentifier";
		UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
		if (!cell) {
			cell = [[SRTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
		}
		cell.textLabel.textColor = [SRAppearance textColor];
		cell.textLabel.text = NSLocalizedString(@"Acknowledgements", nil);
		cell.textLabel.font = [SRAppearance applicationFontWithSize:17.f];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
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
		[mailController setToRecipients:@[@"sloradio@jernej.org"]];
		[self presentViewController:mailController animated:YES completion:NULL];
	}
}

- (void)presentAcknowledgements {
	SRAcknowledgementsViewController *controller = [[SRAcknowledgementsViewController alloc] init];
	[self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
	[self dismissViewControllerAnimated:YES completion:NULL];
}

@end
