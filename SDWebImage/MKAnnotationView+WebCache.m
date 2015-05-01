//
//  MKAnnotationView+WebCache.m
//  SDWebImage
//
//  Created by Olivier Poitrey on 14/03/12.
//  Copyright (c) 2012 Dailymotion. All rights reserved.
//

#import "MKAnnotationView+WebCache.h"
#import "UIView+WebCacheOperation.h"
#import <objc/runtime.h>

static char imageURLKey;

@implementation MKAnnotationView (WebCache)

@dynamic sd_imageLoadCycle;

- (id)sd_imageLoadCycle {
    return objc_getAssociatedObject(self, @selector(sd_imageLoadCycle));
}

- (void)setSd_imageLoadCycle:(id)sd_imageLoadCycle {
    objc_setAssociatedObject(self, @selector(sd_imageLoadCycle), sd_imageLoadCycle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setImageWithURL:(NSURL *)url {
    [self setImageWithURL:url placeholderImage:nil options:0 completed:nil];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder {
    [self setImageWithURL:url placeholderImage:placeholder options:0 completed:nil];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options {
    [self setImageWithURL:url placeholderImage:placeholder options:options completed:nil];
}

- (void)setImageWithURL:(NSURL *)url completed:(SDWebImageCompletedBlock)completedBlock {
    [self setImageWithURL:url placeholderImage:nil options:0 completed:completedBlock];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder completed:(SDWebImageCompletedBlock)completedBlock {
    [self setImageWithURL:url placeholderImage:placeholder options:0 completed:completedBlock];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options completed:(SDWebImageCompletedBlock)completedBlock {
    __block NSInteger loadCycle = NSNotFound;
    
    dispatch_sync_main_queue_safe(^{
        [self cancelCurrentImageLoad];
        
        objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
        
        if (placeholder) {
            self.image = placeholder;
            self.backgroundColor = [UIColor colorWithPatternImage:placeholder];
        }
    });
    
    if (url) {
        __weak MKAnnotationView *wself = self;
        __block UIImage *cachedImage = nil;
        
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadWithURL:url options:options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
            if (!wself) return;
            dispatch_sync_main_queue_safe(^{
                __strong MKAnnotationView *sself = wself;
                if (!sself || [sself.sd_imageLoadCycle integerValue] != loadCycle) return;
                
                if (image) {
                    UIImage *imageToSet = nil;
                    
                    if (!finished && !cachedImage && (options & SDWebImageRefreshCached) && cacheType != SDImageCacheTypeNone) {
                        cachedImage = image;
                        
                        if (!(options & SDWebImageWaitOnCacheResponseBeforeSet))
                            imageToSet = cachedImage;
                    } else if (!finished && cachedImage && (options & SDWebImageUseCachedImageOverProgressive)) {
                        imageToSet = cachedImage;
                    } else
                        imageToSet = image;
                    
                    if (imageToSet.isReady && sself.image != imageToSet) {
                        [UIView performWithoutAnimation:^{
                            sself.image = image;
                            [sself layoutIfNeeded];
                        }];
                    }
                }
                
                if (error || finished) {
                    cachedImage = nil;
                    
                    if (completedBlock) {
                        completedBlock(image, error, cacheType);
                    }
                }
            });
        }];
        
        [self sd_setImageLoadOperation:operation forKey:@"MKAnnotationViewImageLoad"];
    } else {
        dispatch_async_main_queue(^{
            NSError *error = [NSError errorWithDomain:@"SDWebImageErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Trying to load a nil url"}];
            if (completedBlock) {
                completedBlock(nil, error, SDImageCacheTypeNone);
            }
        });
    }
}

- (void)cancelCurrentImageLoad {
    dispatch_sync_main_queue_safe(^{
        [self sd_cancelImageLoadOperationWithKey:@"MKAnnotationViewImageLoad"];
        
        NSInteger loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
    });
}

@end
