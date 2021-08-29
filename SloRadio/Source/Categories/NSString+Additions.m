//
//  NSString+Additions.m
//  SloRadio
//
//  Created by Jernej Fijačko on 29/08/2021.
//  Copyright © 2021 Jernej Fijačko. All rights reserved.
//

#import "NSString+Additions.h"

@implementation NSString (Additions)

- (NSString *)stringByStrippingHTML {
	NSRange r;
	NSString *s = [self copy];
	while ((r = [s rangeOfString:@"<[^>]+>" options:NSRegularExpressionSearch]).location != NSNotFound)
		s = [s stringByReplacingCharactersInRange:r withString:@""];
	return s;
}

@end
