//
//  UIImage+MultiFormat.h
//  SDWebImage
//
//  Created by Olivier Poitrey on 07/06/13.
//  Copyright (c) 2013 Dailymotion. All rights reserved.
//

#import "SDWebImageCompat.h"
#import "SDWebImageManager.h"

@interface UIImage (MultiFormat)

+ (instancetype)sd_imageWithData:(NSData *)data;

+ (instancetype)sd_imageWithData:(NSData *)data scale:(CGFloat)scale;

@end
