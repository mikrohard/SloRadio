//
//  SRStationTableViewCell.m
//  SloRadio
//
//  Created by Jernej Fijačko on 24. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import "SRStationTableViewCell.h"
#import "SRRadioStation.h"

static CGFloat const SRStationArtworkWidth = 256;
static CGFloat const SRStationArtworkSize = 40.f;
static CGFloat const SRStationImageToTextPadding = 12.f;

@interface SRStationTableViewCell ()

@property (nonatomic, assign) NSInteger stationId;

@end

@implementation SRStationTableViewCell

+ (CGFloat)separatorInsetLeft {
	return 16.f + SRStationArtworkSize + SRStationImageToTextPadding;
}

+ (UIImage *)thumbnailForImage:(UIImage *)image {
	// list content configurations only scale images down, so render every icon at the exact thumbnail size
	CGSize size = CGSizeMake(SRStationArtworkSize, SRStationArtworkSize);
	if (!image || CGSizeEqualToSize(image.size, size)) {
		return image;
	}
	static NSMapTable<UIImage *, UIImage *> *thumbnails;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		thumbnails = [NSMapTable weakToStrongObjectsMapTable];
	});
	UIImage *thumbnail = [thumbnails objectForKey:image];
	if (thumbnail) {
		return thumbnail;
	}
	CGFloat scale = MAX(size.width / image.size.width, size.height / image.size.height);
	CGSize scaledSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
	thumbnail = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[image drawInRect:CGRectMake((size.width - scaledSize.width) / 2, (size.height - scaledSize.height) / 2, scaledSize.width, scaledSize.height)];
	}];
	[thumbnails setObject:thumbnail forKey:image];
	return thumbnail;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.stationId = NSNotFound;
	self.checked = NO;
}

- (void)configureWithStation:(SRRadioStation *)station {
	self.stationId = station.stationId;
	
	UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
	content.text = station.name;
	content.image = [SRStationTableViewCell thumbnailForImage:[station cachedArtworkImageForWidth:SRStationArtworkWidth] ?: [UIImage imageNamed:@"PlaceholderArtwork"]];
	content.imageProperties.maximumSize = CGSizeMake(SRStationArtworkSize, SRStationArtworkSize);
	content.imageProperties.reservedLayoutSize = CGSizeMake(SRStationArtworkSize, SRStationArtworkSize);
	content.imageProperties.cornerRadius = 8.f;
	content.imageToTextPadding = SRStationImageToTextPadding;
	// the cell margins are preserved when larger; the minimum keeps distance from the editing controls
	content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(6.f, 12.f, 6.f, 0);
	self.contentConfiguration = content;
	
	if ([station cachedArtworkImageForWidth:SRStationArtworkWidth] == nil && [station iconUrlForWidth:SRStationArtworkWidth] != nil) {
		NSInteger stationId = station.stationId;
		__weak SRStationTableViewCell *weakSelf = self;
		[station loadArtworkImageForWidth:SRStationArtworkWidth completion:^(UIImage *image) {
			SRStationTableViewCell *strongSelf = weakSelf;
			// the cell may have been reused for another station in the meantime
			if (image && strongSelf.stationId == stationId) {
				UIListContentConfiguration *updatedContent = (UIListContentConfiguration *)strongSelf.contentConfiguration;
				updatedContent.image = [SRStationTableViewCell thumbnailForImage:image];
				strongSelf.contentConfiguration = updatedContent;
			}
		}];
	}
}

- (void)setChecked:(BOOL)checked {
	_checked = checked;
	if (checked) {
		UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:15.f weight:UIImageSymbolWeightSemibold];
		UIImageView *checkmark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:configuration]];
		checkmark.tintColor = [SRAppearance mainColor];
		self.accessoryView = checkmark;
	} else {
		self.accessoryView = nil;
	}
	self.accessibilityTraits = checked ? UIAccessibilityTraitSelected : UIAccessibilityTraitNone;
}

@end
