//
//  UIImage+GIF.h
//  LBGIFImage
//
//  Created by Laurin Brandner on 06.01.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "SDWebImageCompat.h"
#import "SDWebImageManager.h"

@interface UIImage (GIF)

+ (UIImage *)sd_animatedGIFNamed:(NSString *)name;

+ (UIImage *)sd_animatedGIFWithData:(NSData *)data;

+ (UIImage *)sd_animatedGIFWithData:(NSData *)data scale:(CGFloat)scale;

- (UIImage *)sd_animatedImageByScalingAndCroppingToSize:(CGSize)size;

@end
