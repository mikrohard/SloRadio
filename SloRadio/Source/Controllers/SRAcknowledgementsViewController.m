//
//  SRAcknowledgementsViewController.m
//  SloRadio
//
//  Created by Jernej Fijačko on 5. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "SRAcknowledgementsViewController.h"

@interface SRAcknowledgementsViewController ()

@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, assign) BOOL initialScroll;

@end

@implementation SRAcknowledgementsViewController

- (instancetype)init {
	self = [super init];
	if (self) {
		self.title = NSLocalizedString(@"Acknowledgements", nil);
	}
	return self;
}

- (void)loadView {
	[super loadView];
	UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
	textView.editable = NO;
	textView.dataDetectorTypes = UIDataDetectorTypeLink;
	textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	NSString *path = [[NSBundle mainBundle] pathForResource:@"acknowledgements" ofType:@"txt"];
	NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	textView.text = text;
	[self.view addSubview:textView];
	self.textView = textView;
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	if (!self.initialScroll) {
		self.initialScroll = YES;
		[self.textView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

@end
