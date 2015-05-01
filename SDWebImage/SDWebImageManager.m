/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import "SDWebImageDownloaderOperation.h"
#import <objc/message.h>

@interface SDWebImageManager ()

@property (strong, nonatomic, readwrite) SDImageCache *imageCache;
@property (strong, nonatomic, readwrite) SDWebImageDownloader *imageDownloader;
@property (strong, nonatomic) NSMutableArray *failedURLs;
@property (strong, nonatomic) NSMutableArray *runningOperations;

@end

@implementation SDWebImageManager

+ (id)sharedManager {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _imageCache = [self createCache];
        _imageDownloader = [SDWebImageDownloader sharedDownloader];
        _failedURLs = [NSMutableArray new];
        _runningOperations = [NSMutableArray new];
    }
    return self;
}

- (SDImageCache *)createCache {
    return [SDImageCache sharedImageCache];
}

- (NSString *)cacheKeyForURL:(NSURL *)url {
    if (self.cacheKeyFilter) {
        return self.cacheKeyFilter(url);
    }
    else {
        return [url absoluteString];
    }
}

- (BOOL)imageFromCacheExistsForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    
    return [self.imageCache imageFromCacheExistsForKey:key];
}

- (void)imageFromCacheExistsForURL:(NSURL *)url completion:(SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    [self.imageCache imageFromCacheExistsForKey:key completion:completionBlock];
}

- (BOOL)imageFromMemoryCacheExistsForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    
    return [self.imageCache imageFromMemoryCacheExistsForKey:key];
}

- (BOOL)imageFromDiskCacheExistsForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    
    return [self.imageCache imageFromDiskCacheExistsForKey:key];
}

- (void)imageFromDiskCacheExistsForURL:(NSURL *)url completion:(SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    [self.imageCache imageFromDiskCacheExistsForKey:key completion:completionBlock];
}

- (NSData *)imageDataFromDiskCacheForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    
    return [self.imageCache imageDataFromDiskCacheForKey:key];
}

- (void)imageDataFromDiskCacheForURL:(NSURL *)url completion:(SDWebImageImageDataCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    [self.imageCache imageDataFromDiskCacheForKey:key completion:completionBlock];
}

- (UIImage *)imageFromCacheForURL:(NSURL *)url options:(SDWebImageScaledOptions)options {
    NSString *key = [self cacheKeyForURL:url];
    
    return [self.imageCache imageFromCacheForKey:key options:options];
}

- (UIImage *)imageFromMemoryCacheForURL:(NSURL *)url options:(SDWebImageScaledOptions)options {
    NSString *key = [self cacheKeyForURL:url];
    
    return [self.imageCache imageFromMemoryCacheForKey:key options:options];
}

- (NSArray *)downloadOperationsForURL:(NSURL *)url {
    NSMutableArray *operations = nil;
    
    @synchronized (self.runningOperations) {
        for (SDWebImageCombinedOperation *operation in self.runningOperations) {
            if ([operation.url isEqual:url]) {
                if (!operations)
                    operations = [NSMutableArray new];
                
                [operations addObject:operation];
            }
        }
    }
    
    return operations;
}

- (SDWebImageCombinedOperation *)downloadWithURL:(NSURL *)url options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletedWithFinishedBlock)completedBlock {
    // Invoking this method without a completedBlock is pointless
    NSParameterAssert(completedBlock);
    
    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, XCode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    if ([url isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)url];
    }
    
    // Prevents app crashing on argument type error like sending NSNull instead of NSURL
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }
    
    __block SDWebImageCombinedOperation *operation = [[SDWebImageCombinedOperation alloc] initWithOptions:options URL:url];
    __weak SDWebImageCombinedOperation *weakOperation = operation;
    
    BOOL isFailedUrl = NO;
    @synchronized (self.failedURLs) {
        isFailedUrl = [self.failedURLs containsObject:url];
    }
    
    if (!url || (!(operation.options & SDWebImageRetryFailed) && isFailedUrl)) {
        dispatch_sync_main_queue_safe(^{
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil];
            completedBlock(nil, error, SDImageCacheTypeNone, YES);
        });
        return operation;
    }
    
    @synchronized (self.runningOperations) {
        [self.runningOperations addObject:operation];
    }
    NSString *key = [self cacheKeyForURL:url];
    
    operation.cacheOperation = [self.imageCache queryCacheForKey:key options:(weakOperation.options & SDWebImageLoadAsRetinaImage) done:^(UIImage *image, SDImageCacheType cacheType) {
        if (operation.isCancelled) {
            @synchronized (self.runningOperations) {
                [self.runningOperations removeObject:weakOperation];
            }
            return;
        }
        
        if ((!image || weakOperation.options & SDWebImageRefreshCached) && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url])) {
            if (image && weakOperation.options & SDWebImageRefreshCached) {
                dispatch_sync_main_queue_safe(^{
                    // If image was found in the cache bug SDWebImageRefreshCached is provided, notify about the cached image
                    // AND try to re-download it in order to let a chance to NSURLCache to refresh it from server.
                    completedBlock(image, nil, cacheType, NO);
                });
            }
            
            SDWebImageDownloaderOptions downloaderOptions = 0;
            if (weakOperation.options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
            if (weakOperation.options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
            if (weakOperation.options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
            if (weakOperation.options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
            if (weakOperation.options & SDWebImageContinueInBackground) downloaderOptions |= SDWebImageDownloaderContinueInBackground;
            if (weakOperation.options & SDWebImageHandleCookies) downloaderOptions |= SDWebImageDownloaderHandleCookies;
            if (weakOperation.options & SDWebImageAllowInvalidSSLCertificates) downloaderOptions |= SDWebImageDownloaderAllowInvalidSSLCertificates;
            if (image && weakOperation.options & SDWebImageRefreshCached) {
                // force progressive off if image already cached but forced refreshing
                //downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
                // ignore image read from NSURLCache if image if cached but force refreshing
                downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
            }
            
            if (weakOperation.options & SDWebImageLoadAsRetinaImage) downloaderOptions |= SDWebImageDownloaderLoadAsRetinaImage;
            if (weakOperation.options & SDWebImageUsePrefetcherSizeLimit) downloaderOptions |= SDWebImageDownloaderUsePrefetcherSizeLimit;
            if (weakOperation.options & SDWebImageIgnoreAllSizeLimits) downloaderOptions |= SDWebImageDownloaderIgnoreAllSizeLimits;
            
            operation.downloadOperation = [self.imageDownloader downloadImageWithURL:url options:downloaderOptions progress:progressBlock completed:^(UIImage *downloadedImage, NSData *data, NSError *error, BOOL finished) {
                if (weakOperation.isCancelled) {
                    // Do nothing if the operation was cancelled
                    // See #699 for more details
                    // if we would call the completedBlock, there could be a race condition between this block and another completedBlock for the same object, so if this one is called second, we will overwrite the new data
                }
                else if (error) {
                    dispatch_sync_main_queue_safe(^{
                        if (!weakOperation.isCancelled) {
                            completedBlock(nil, error, SDImageCacheTypeNone, finished);
                        }
                    });
                    
                    if (error.code != NSURLErrorNotConnectedToInternet && error.code != NSURLErrorCancelled && error.code != NSURLErrorTimedOut && error.code != NSURLErrorDataLengthExceedsMaximum) {
                        @synchronized (self.failedURLs) {
                            [self.failedURLs addObject:url];
                        }
                    }
                }
                else {
                    BOOL cacheOnDisk = !(weakOperation.options & SDWebImageCacheMemoryOnly);
                    
                    if (finished && isFailedUrl) {
                        @synchronized (self.failedURLs) {
                            [self.failedURLs removeObject:url];
                        }
                    }
                    
                    if (image && weakOperation.options & SDWebImageRefreshCached && !downloadedImage) {
                        if (finished) {
                            dispatch_sync_main_queue_safe(^{
                                completedBlock(image, nil, cacheType, YES);
                            });
                        }
                    }
                    else if (downloadedImage && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]) {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];
                            
                            if (transformedImage && finished) {
                                BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                                [self.imageCache storeImage:transformedImage recalculateFromImage:imageWasTransformed imageData:data forKey:key toDisk:cacheOnDisk];
                                
                                transformedImage = SDScaledImageForOptions((weakOperation.options & SDWebImageLoadAsRetinaImage), transformedImage);
                            }
                            
                            dispatch_sync_main_queue_safe(^{
                                if (!weakOperation.isCancelled) {
	                                completedBlock(transformedImage, nil, SDImageCacheTypeNone, finished);
                                }
                            });
                        });
                    }
                    else {
                        if (downloadedImage && finished) {
                            [self.imageCache storeImage:downloadedImage recalculateFromImage:NO imageData:data forKey:key toDisk:cacheOnDisk];
                            
                            downloadedImage = SDScaledImageForOptions((weakOperation.options & SDWebImageLoadAsRetinaImage), downloadedImage);
                        }
                        
                        dispatch_sync_main_queue_safe(^{
                            if (!weakOperation.isCancelled) {
                            	completedBlock(downloadedImage, nil, SDImageCacheTypeNone, finished);
                            }
                        });
                    }
                }
                
                if (finished) {
                    @synchronized (self.runningOperations) {
                        [self.runningOperations removeObject:weakOperation];
                    }
                }
            }];
            
            operation.cancelBlock = ^{
                [weakOperation.downloadOperation cancel];
                
                @synchronized (self.runningOperations) {
                    [self.runningOperations removeObject:weakOperation];
                }
            };
        }
        else if (image) {
            dispatch_sync_main_queue_safe(^{
                if (!weakOperation.isCancelled) {
                    completedBlock(image, nil, cacheType, YES);
                }
            });
            @synchronized (self.runningOperations) {
                [self.runningOperations removeObject:weakOperation];
            }
        }
        else {
            // Image not in cache and download disallowed by delegate
            dispatch_sync_main_queue_safe(^{
                if (!weakOperation.isCancelled) {
                    completedBlock(nil, nil, SDImageCacheTypeNone, YES);
                }
            });
            @synchronized (self.runningOperations) {
                [self.runningOperations removeObject:weakOperation];
            }
        }
    }];
    
    return operation;
}

- (void)saveImageToCache:(UIImage *)image forURL:(NSURL *)url {
    if (image && url) {
        NSString *key = [self cacheKeyForURL:url];
        [self.imageCache storeImage:image forKey:key toDisk:YES];
    }
}

- (void)cancelAll {
    @synchronized (self.runningOperations) {
        NSArray *copiedOperations = [self.runningOperations copy];
        [copiedOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeObjectsInArray:copiedOperations];
    }
}

- (BOOL)isRunning {
    return self.runningOperations.count > 0;
}

@end

@implementation SDWebImageCombinedOperation

- (instancetype)initWithOptions:(SDWebImageOptions)options URL:(NSURL *)url {
    if ((self = [super init])) {
        _options = options;
        _url = url;
    }
    
    return self;
}

- (void)setCancelBlock:(void (^)())cancelBlock {
    // check if the operation is already cancelled, then we just call the cancelBlock
    if (self.isCancelled) {
        if (cancelBlock) cancelBlock();
	_cancelBlock = nil; // don't forget to nil the cancelBlock, otherwise we will get crashes
    }
    else {
        _cancelBlock = [cancelBlock copy];
    }
}

- (void)cancel {
    self.cancelled = YES;
    if (self.cacheOperation) {
        [self.cacheOperation cancel];
        self.cacheOperation = nil;
    }
    if (self.downloadOperation) {
        [self.downloadOperation cancel];
        self.downloadOperation = nil;
    }
    if (self.cancelBlock) {
        self.cancelBlock();
        // TODO: this is a temporary fix to #809.
        // Until we can figure the exact cause of the crash, going with the ivar instead of the setter
        self.cancelBlock = nil;
        _cancelBlock = nil;
    }
}

- (void)changePriorityOption:(SDWebImageOptions)priorityOption {
    _options &= ~(SDWebImageLowPriority | SDWebImageHighPriority);
    _options |= (priorityOption & (SDWebImageLowPriority | SDWebImageHighPriority));
    
    if (self.downloadOperation) {
        SDWebImageDownloaderOptions downloaderPriorityOption = 0;
        
        if (_options & SDWebImageLowPriority) downloaderPriorityOption |= SDWebImageDownloaderLowPriority;
        if (_options & SDWebImageHighPriority) downloaderPriorityOption |= SDWebImageDownloaderHighPriority;
        
        [self.downloadOperation changeDownloaderPriorityOption:downloaderPriorityOption];
    }
}

- (void)changeSizeLimitOptions:(SDWebImageOptions)limitOptions {
    _options &= ~(SDWebImageUsePrefetcherSizeLimit | SDWebImageIgnoreAllSizeLimits);
    _options |= (limitOptions & (SDWebImageUsePrefetcherSizeLimit | SDWebImageIgnoreAllSizeLimits));
    
    if (self.downloadOperation) {
        SDWebImageDownloaderOptions downloaderSizeLimitOptions = 0;
        
        if (_options & SDWebImageUsePrefetcherSizeLimit) downloaderSizeLimitOptions |= SDWebImageDownloaderUsePrefetcherSizeLimit;
        if (_options & SDWebImageIgnoreAllSizeLimits) downloaderSizeLimitOptions |= SDWebImageDownloaderIgnoreAllSizeLimits;
        
        [self.downloadOperation changeDownloaderSizeLimitOptions:downloaderSizeLimitOptions];
    }
}

- (void)changePriorityAndSizeLimitOptions:(SDWebImageOptions)options {
    _options &= ~(SDWebImageLowPriority | SDWebImageHighPriority | SDWebImageUsePrefetcherSizeLimit | SDWebImageIgnoreAllSizeLimits);
    _options |= (options & (SDWebImageLowPriority | SDWebImageHighPriority | SDWebImageUsePrefetcherSizeLimit | SDWebImageIgnoreAllSizeLimits));
    
    if (self.downloadOperation) {
        SDWebImageDownloaderOptions downloaderOptions = 0;
        
        if (_options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
        if (_options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
        if (_options & SDWebImageUsePrefetcherSizeLimit) downloaderOptions |= SDWebImageDownloaderUsePrefetcherSizeLimit;
        if (_options & SDWebImageIgnoreAllSizeLimits) downloaderOptions |= SDWebImageDownloaderIgnoreAllSizeLimits;
        
        [self.downloadOperation changeDownloaderPriorityAndSizeLimitOptions:downloaderOptions];
    }
}

@end
