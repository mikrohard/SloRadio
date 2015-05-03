//
//  UIImage+Color.m
//  SloRadio
//
//  Created by Jernej Fijačko on 3. 05. 15.
//  Copyright (c) 2015 Jernej Fijačko. All rights reserved.
//

#import "UIImage+Color.h"

@implementation UIImage (Color)

- (UIImage *)imageWithColor:(UIColor *)color {
    // Begin drawing
    CGRect rect = CGRectMake(0.f, 0.f, self.size.width, self.size.height);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, self.scale);
    
    // Get the graphic context
    CGContextRef c = UIGraphicsGetCurrentContext();
    
    // Converting a UIImage to a CGImage flips the image,
    // so apply a upside-down translation
    CGContextTranslateCTM(c, 0, self.size.height);
    CGContextScaleCTM(c, 1.0, -1.0);
    
    // Set the fill color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextSetFillColorSpace(c, colorSpace);
    
    // Set the mask to only tint non-transparent pixels
    CGContextClipToMask(c, rect, self.CGImage);
    
    // Set the fill color
    CGContextSetFillColorWithColor(c, color.CGColor);
    
    UIRectFillUsingBlendMode(rect, kCGBlendModeColor);
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // Release memory
    CGColorSpaceRelease(colorSpace);
    
    return img;
}

@end
