//
//  UIImage+MultiFormat.m
//  SDWebImage
//
//  Created by Olivier Poitrey on 07/06/13.
//  Copyright (c) 2013 Dailymotion. All rights reserved.
//

#import "UIImage+MultiFormat.h"
#import "UIImage+GIF.h"
#import "NSData+ImageContentType.h"
#import "OLImage.h"

#ifdef SD_WEBP
#import "UIImage+WebP.h"
#endif

@implementation UIImage (MultiFormat)

+ (instancetype)sd_imageWithData:(NSData *)data {
    return [UIImage sd_imageWithData:data scale:1];
}

+ (instancetype)sd_imageWithData:(NSData *)data scale:(CGFloat)scale {
    UIImage *image;
    NSString *contentType = [NSData contentTypeForImageData:data];
    
    if ([contentType isEqualToString:@"image/gif"]) {
        image = [OLImage imageWithData:data scale:scale];
        
        if (!image) {
            image = [UIImage sd_animatedGIFWithData:data scale:scale]; // Fallback
            
            if (!image)
                image = [[UIImage alloc] initWithData:data scale:scale];
        }
    } else if ([contentType isEqualToString:@"image/apng"]) {
        image = [OLImage imageWithData:data scale:scale];
        
        if (!image)
            image = [[UIImage alloc] initWithData:data scale:scale];
    }
#ifdef SD_WEBP
    else if ([contentType isEqualToString:@"image/webp"])
    {
        image = [UIImage sd_imageWithWebPData:data];
        
        if (!image)
            image = [[UIImage alloc] initWithData:data scale:scale];
    }
#endif
    else {
        image = [[UIImage alloc] initWithData:data scale:scale];
    }

    return image;
}

@end
