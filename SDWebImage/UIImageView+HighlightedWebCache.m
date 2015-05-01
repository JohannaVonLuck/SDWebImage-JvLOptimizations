/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIImageView+HighlightedWebCache.h"
#import "UIImageView+SmoothTransition.h"
#import "UIView+WebCacheOperation.h"
#import <objc/runtime.h>

static char imageURLKey;

@implementation UIImageView (HighlightedWebCache)

@dynamic sd_highlightedImageLoadCycle;

- (id)sd_highlightedImageLoadCycle {
    return objc_getAssociatedObject(self, @selector(sd_highlightedImageLoadCycle));
}

- (void)setSd_highlightedImageLoadCycle:(id)sd_highlightedImageLoadCycle {
    objc_setAssociatedObject(self, @selector(sd_highlightedImageLoadCycle), sd_highlightedImageLoadCycle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setHighlightedImageWithURL:(NSURL *)url {
    [self setHighlightedImageWithURL:url placeholderImage:nil options:0 progress:nil completed:nil];
}

- (void)setHighlightedImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder {
    [self setHighlightedImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:nil];
}

- (void)setHighlightedImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options {
    [self setHighlightedImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:nil];
}

- (void)setHighlightedImageWithURL:(NSURL *)url completed:(SDWebImageCompletedBlock)completedBlock {
    [self setHighlightedImageWithURL:url placeholderImage:nil options:0 progress:nil completed:completedBlock];
}

- (void)setHighlightedImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder completed:(SDWebImageCompletedBlock)completedBlock {
    [self setHighlightedImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:completedBlock];
}

- (void)setHighlightedImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options completed:(SDWebImageCompletedBlock)completedBlock {
    [self setHighlightedImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:completedBlock];
}

- (void)setHighlightedImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletedBlock)completedBlock {
    __block NSInteger loadCycle = NSNotFound;
    
    dispatch_sync_main_queue_safe(^{
        [self cancelCurrentImageLoad];
        
        objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        loadCycle = [self.sd_highlightedImageLoadCycle integerValue] + 1;
        self.sd_highlightedImageLoadCycle = [NSNumber numberWithInteger:loadCycle];
        
        if (placeholder)
            self.highlightedImage = placeholder;
    });
    
    if (url) {
        __weak UIImageView *wself = self;
        __block UIImage *cachedImage = nil;
        
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadWithURL:url options:options progress:progressBlock completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
            if (!wself || [wself.sd_highlightedImageLoadCycle integerValue] != loadCycle) return;
            dispatch_sync_main_queue_safe(^{
                __strong UIImageView *sself = wself;
                if (!sself) return;
                
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
                    
                    if (imageToSet.isReady && sself.highlightedImage != imageToSet) {
                        if (!error && cacheType == SDImageCacheTypeNone && (options & SDWebImageSmoothPlaceholderTransition) && ((placeholder && sself.highlightedImage == placeholder) || (cachedImage && sself.highlightedImage == cachedImage))) {
                            [sself setHighlightedImageWithSmoothTransition:imageToSet optionsDelegate:([sself conformsToProtocol:@protocol(SDWebImageSmoothTransitionOptionsDelegate)] ? (id<SDWebImageSmoothTransitionOptionsDelegate>)sself : nil)];
                            [UIView performWithoutAnimation:^{
                                [sself layoutIfNeeded];
                            }];
                        } else {
                            if ((options & SDWebImageSmoothPlaceholderTransition))
                                [self cancelSmoothImageTransitionAnimation];
                            [UIView performWithoutAnimation:^{
                                sself.highlightedImage = imageToSet;
                                [sself layoutIfNeeded];
                            }];
                        }
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
        
        [self sd_setImageLoadOperation:operation forKey:@"UIImageViewHighlightedImageLoad"];
    } else {
        dispatch_async_main_queue(^{
            NSError *error = [NSError errorWithDomain:@"SDWebImageErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Trying to load a nil url"}];
            if (completedBlock) {
                completedBlock(nil, error, SDImageCacheTypeNone);
            }
        });
    }
}

- (void)cancelCurrentHighlightedImageLoad {
    [self sd_cancelImageLoadOperationWithKey:@"UIImageViewHighlightedImageLoad"];
    
    NSInteger loadCycle = [self.sd_highlightedImageLoadCycle integerValue] + 1;
    self.sd_highlightedImageLoadCycle = [NSNumber numberWithInteger:loadCycle];
}

@end
