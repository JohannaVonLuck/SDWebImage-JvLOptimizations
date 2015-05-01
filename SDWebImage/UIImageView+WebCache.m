/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIImageView+WebCache.h"
#import "UIImageView+SmoothTransition.h"
#import "UIView+WebCacheOperation.h"
#import <objc/runtime.h>

static char imageURLKey;

@implementation UIImageView (WebCache)

@dynamic sd_imageLoadCycle;

- (id)sd_imageLoadCycle {
    return objc_getAssociatedObject(self, @selector(sd_imageLoadCycle));
}

- (void)setSd_imageLoadCycle:(id)sd_imageLoadCycle {
    objc_setAssociatedObject(self, @selector(sd_imageLoadCycle), sd_imageLoadCycle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setImageWithURL:(NSURL *)url {
    [self setImageWithURL:url placeholderImage:nil options:0 progress:nil completed:nil];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder {
    [self setImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:nil];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options {
    [self setImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:nil];
}

- (void)setImageWithURL:(NSURL *)url completed:(SDWebImageCompletedBlock)completedBlock {
    [self setImageWithURL:url placeholderImage:nil options:0 progress:nil completed:completedBlock];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder completed:(SDWebImageCompletedBlock)completedBlock {
    [self setImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:completedBlock];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options completed:(SDWebImageCompletedBlock)completedBlock {
    [self setImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:completedBlock];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletedBlock)completedBlock {
    __block NSInteger loadCycle = NSNotFound;
    
    dispatch_sync_main_queue_safe(^{
        [self cancelCurrentImageLoad];
        
        objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
        
        if (placeholder) {
            self.image = placeholder;
            
            if (options & SDWebImageProgressiveDownload)
                self.backgroundColor = [UIColor colorWithPatternImage:placeholder];
            else
                self.backgroundColor = [UIColor clearColor];
        } else
            self.backgroundColor = [UIColor clearColor];
    });
    
    if (url) {
        __weak UIImageView *wself = self;
        __block UIImage *cachedImage = nil;
        
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadWithURL:url options:options progress:progressBlock completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
            if (!wself) return;
            dispatch_sync_main_queue_safe(^{
                __strong UIImageView *sself = wself;
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
                        if (!error && cacheType == SDImageCacheTypeNone && (options & SDWebImageSmoothPlaceholderTransition) && ((placeholder && sself.image == placeholder) || (cachedImage && sself.image == cachedImage))) {
                            [sself setImageWithSmoothTransition:imageToSet optionsDelegate:([sself conformsToProtocol:@protocol(SDWebImageSmoothTransitionOptionsDelegate)] ? (id<SDWebImageSmoothTransitionOptionsDelegate>)sself : nil)];
                            [UIView performWithoutAnimation:^{
                                [sself layoutIfNeeded];
                            }];
                        } else {
                            if ((options & SDWebImageSmoothPlaceholderTransition))
                                [self cancelSmoothImageTransitionAnimation];
                            [UIView performWithoutAnimation:^{
                                sself.image = imageToSet;
                                [sself layoutIfNeeded];
                            }];
                        }
                    }
                }
                
                if (error || finished) {
                    cachedImage = nil;
                    
                    self.backgroundColor = [UIColor clearColor];
                    
                    if (completedBlock) {
                        completedBlock(image, error, cacheType);
                    }
                }
            });
        }];
        
        [self sd_setImageLoadOperation:operation forKey:@"UIImageViewImageLoad"];
    } else {
        dispatch_async_main_queue(^{
            NSError *error = [NSError errorWithDomain:@"SDWebImageErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Trying to load a nil url"}];
            if (completedBlock) {
                completedBlock(nil, error, SDImageCacheTypeNone);
            }
        });
    }
}

- (void)setAnimationImagesWithURLs:(NSArray *)arrayOfURLs {
    __block NSInteger loadCycle = NSNotFound;
    
    dispatch_sync_main_queue_safe(^{
        [self cancelCurrentArrayLoad];
        
        loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
    });
    
    if (arrayOfURLs.count) {
        __weak UIImageView *wself = self;
        
        NSMutableArray *operationsArray = [[NSMutableArray alloc] init];
        
        for (NSURL *logoImageURL in arrayOfURLs) {
            id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadWithURL:logoImageURL options:0 progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
                if (!wself || [wself.sd_imageLoadCycle integerValue] != loadCycle) return;
                dispatch_sync_main_queue_safe(^{
                    __strong UIImageView *sself = wself;
                    if (!sself) return;
                    
                    [sself stopAnimating];
                    
                    if (sself && image) {
                        NSMutableArray *currentImages = [[sself animationImages] mutableCopy];
                        if (!currentImages) {
                            currentImages = [[NSMutableArray alloc] init];
                        }
                        [currentImages addObject:image];

                        sself.animationImages = currentImages;
                        [sself setNeedsLayout];
                    }
                    
                    [sself startAnimating];
                });
            }];
            [operationsArray addObject:operation];
        }
        
        [self sd_setImageLoadOperation:[NSArray arrayWithArray:operationsArray] forKey:@"UIImageViewAnimationImages"];
    }
}

- (void)cancelCurrentImageLoad {
    dispatch_sync_main_queue_safe(^{
        [self sd_cancelImageLoadOperationWithKey:@"UIImageViewImageLoad"];
        
        NSInteger loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
    });
}

- (void)cancelCurrentArrayLoad {
    dispatch_sync_main_queue_safe(^{
        [self sd_cancelImageLoadOperationWithKey:@"UIImageViewAnimationImages"];
        
        NSInteger loadCycle = [self.sd_imageLoadCycle integerValue] + 1;
        self.sd_imageLoadCycle = [NSNumber numberWithInteger:loadCycle];
    });
}

@end
