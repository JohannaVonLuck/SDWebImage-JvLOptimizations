/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIButton+WebCache.h"
#import "UIView+WebCacheOperation.h"
#import <objc/runtime.h>

static char imageURLKey;

@implementation UIButton (WebCache)

@dynamic sd_imageLoadCycle;

- (id)sd_imageLoadCycle {
    return objc_getAssociatedObject(self, @selector(sd_imageLoadCycle));
}

- (void)setSd_imageLoadCycle:(id)sd_imageLoadCycle {
    objc_setAssociatedObject(self, @selector(sd_imageLoadCycle), sd_imageLoadCycle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@dynamic sd_backgroundImageLoadCycle;

- (id)sd_backgroundImageLoadCycle {
    return objc_getAssociatedObject(self, @selector(sd_backgroundImageLoadCycle));
}

- (void)setSd_backgroundImageLoadCycle:(id)sd_backgroundImageLoadCycle {
    objc_setAssociatedObject(self, @selector(sd_backgroundImageLoadCycle), sd_backgroundImageLoadCycle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setImageWithURL:(NSURL *)url forState:(UIControlState)state {
    [self setImageWithURL:url forState:state placeholderImage:nil options:0 completed:nil];
}

- (void)setImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder {
    [self setImageWithURL:url forState:state placeholderImage:placeholder options:0 completed:nil];
}

- (void)setImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options {
    [self setImageWithURL:url forState:state placeholderImage:placeholder options:options completed:nil];
}

- (void)setImageWithURL:(NSURL *)url forState:(UIControlState)state completed:(SDWebImageCompletedBlock)completedBlock {
    [self setImageWithURL:url forState:state placeholderImage:nil options:0 completed:completedBlock];
}

- (void)setImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder completed:(SDWebImageCompletedBlock)completedBlock {
    [self setImageWithURL:url forState:state placeholderImage:placeholder options:0 completed:completedBlock];
}

- (void)setImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options completed:(SDWebImageCompletedBlock)completedBlock {
    __block NSInteger loadCycle = NSNotFound;
    
    dispatch_sync_main_queue_safe(^{
        [self cancelCurrentImageLoad];
        
        objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
        
        if (placeholder)
            [self setImage:placeholder forState:state];
    });
    
    if (url) {
        __weak UIButton *wself = self;
        __block UIImage *cachedImage = nil;
        
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadWithURL:url options:options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
            if (!wself) return;
            dispatch_sync_main_queue_safe(^{
                __strong UIButton *sself = wself;
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
                    
                    if (imageToSet.isReady && [sself imageForState:state] != imageToSet) {
                        [UIView performWithoutAnimation:^{
                            [sself setImage:image forState:state];
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
        
        [self sd_setImageLoadOperation:operation forKey:@"UIButtonImageLoad"];
    } else {
        dispatch_async_main_queue(^{
            NSError *error = [NSError errorWithDomain:@"SDWebImageErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Trying to load a nil url"}];
            if (completedBlock) {
                completedBlock(nil, error, SDImageCacheTypeNone);
            }
        });
    }
}

- (void)setBackgroundImageWithURL:(NSURL *)url forState:(UIControlState)state {
    [self setBackgroundImageWithURL:url forState:state placeholderImage:nil options:0 completed:nil];
}

- (void)setBackgroundImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder {
    [self setBackgroundImageWithURL:url forState:state placeholderImage:placeholder options:0 completed:nil];
}

- (void)setBackgroundImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options {
    [self setBackgroundImageWithURL:url forState:state placeholderImage:placeholder options:options completed:nil];
}

- (void)setBackgroundImageWithURL:(NSURL *)url forState:(UIControlState)state completed:(SDWebImageCompletedBlock)completedBlock {
    [self setBackgroundImageWithURL:url forState:state placeholderImage:nil options:0 completed:completedBlock];
}

- (void)setBackgroundImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder completed:(SDWebImageCompletedBlock)completedBlock {
    [self setBackgroundImageWithURL:url forState:state placeholderImage:placeholder options:0 completed:completedBlock];
}

- (void)setBackgroundImageWithURL:(NSURL *)url forState:(UIControlState)state placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options completed:(SDWebImageCompletedBlock)completedBlock {
    __block NSInteger loadCycle = NSNotFound;
    
    dispatch_sync_main_queue_safe(^{
        [self cancelCurrentImageLoad];
        
        objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        loadCycle = [self.sd_backgroundImageLoadCycle integerValue] + 1;
        self.sd_backgroundImageLoadCycle = [NSNumber numberWithInteger:loadCycle];
        
        if (placeholder)
            [self setBackgroundImage:placeholder forState:state];
    });
    
    if (url) {
        __weak UIButton *wself = self;
        __block UIImage *cachedImage = nil;
        
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadWithURL:url options:options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
            if (!wself) return;
            dispatch_sync_main_queue_safe(^{
                __strong UIButton *sself = wself;
                if (!sself || [sself.sd_backgroundImageLoadCycle integerValue] != loadCycle) return;
                
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
                    
                    if (imageToSet.isReady && [sself backgroundImageForState:state] != imageToSet) {
                        [UIView performWithoutAnimation:^{
                            [sself setBackgroundImage:imageToSet forState:state];
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
        
        [self sd_setImageLoadOperation:operation forKey:@"UIButtonImageLoad"];
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
        [self sd_cancelImageLoadOperationWithKey:@"UIButtonImageLoad"];
        
        NSInteger loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
        
        loadCycle = [self.sd_backgroundImageLoadCycle integerValue] + 1;
        self.sd_backgroundImageLoadCycle = [NSNumber numberWithInteger:loadCycle];
    });
}

@end
