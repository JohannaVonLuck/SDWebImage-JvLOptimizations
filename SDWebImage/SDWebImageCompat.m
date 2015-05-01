//
//  SDWebImageCompat.m
//  SDWebImage
//
//  Created by Olivier Poitrey on 11/12/12.
//  Copyright (c) 2012 Dailymotion. All rights reserved.
//

#import "SDWebImageCompat.h"
#import "SDWebImageManager.h"

#if !__has_feature(objc_arc)
#error SDWebImage is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif

inline UIImage *SDScaledImageForKey(NSString *key, UIImage *image) {
    if (!key.length || [image isKindOfClass:[OLImage class]])
        return image;
    
    if (image.images.count) {
        NSMutableArray *scaledImages = [NSMutableArray array];
        
        for (UIImage *tempImage in image.images) {
            [scaledImages addObject:SDScaledImageForKey(key, tempImage)];
        }
        
        return [UIImage animatedImageWithImages:scaledImages duration:image.duration];
    }
    else {
        if ([key rangeOfString:@"@3x"].location != NSNotFound && image.scale < 3.0) {
            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:3 orientation:image.imageOrientation];
            image = scaledImage;
        } else if ([key rangeOfString:@"@2x"].location != NSNotFound && image.scale < 2.0) {
            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:2 orientation:image.imageOrientation];
            image = scaledImage;
        }
        
        return image;
    }
}

inline UIImage *SDScaledImageForOptions(SDWebImageScaledOptions options, UIImage *image) {
    if (!options || [image isKindOfClass:[OLImage class]])
        return image;
    
    if (image.images.count) {
        NSMutableArray *scaledImages = [NSMutableArray array];
        
        for (UIImage *tempImage in image.images) {
            [scaledImages addObject:SDScaledImageForOptions(options, tempImage)];
        }
        
        return [UIImage animatedImageWithImages:scaledImages duration:image.duration];
    }
    else {
        if ((options & SDWebImageScaledLoadAsRetinaImage) && image.scale < 2.0) {
            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:2 orientation:image.imageOrientation];
            image = scaledImage;
        }
        
        return image;
    }
}
