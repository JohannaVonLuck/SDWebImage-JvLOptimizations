/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImagePrefetcher.h"
#import "SDWebImageManager.h"

#if !defined(DEBUG) && !defined (SD_VERBOSE)
#define NSLog(...)
#endif

@interface SDWebImagePrefetchItem : NSObject
@property (nonatomic, strong) SDWebImageCombinedOperation *operation;
@property (nonatomic, strong) NSMutableSet *batchIndicies;
@property (nonatomic, strong) NSURL *url;
- (void)cancelOperation;
@end
@implementation SDWebImagePrefetchItem
- (instancetype)initWithBatchIndex:(NSNumber *)batchIndex URL:(NSURL *)url {
    if ((self = [super init])) {
        _batchIndicies = [NSMutableSet setWithObject:batchIndex];
        _url = url;
    }
    return self;
}
- (void)cancelOperation {
    [_operation cancel];
}
@end

@interface SDWebImageBatchItem : NSObject
@property (nonatomic, strong) NSMutableArray *prefetchItemsLeft;
@property (nonatomic, strong) NSArray *URLs;
@property (nonatomic, strong) NSArray *URLOptions;
@property (nonatomic, assign) NSUInteger skippedCount;
@property (nonatomic, assign) NSUInteger finishedCount;
@property (nonatomic, assign) NSTimeInterval startedTime;
@property (nonatomic, copy) SDWebImagePrefetchStartedBlock startedBlock;
@property (nonatomic, copy) SDWebImagePrefetchProgressBlock progressBlock;
@property (nonatomic, copy) SDWebImagePrefetchCompletionBlock completionBlock;
@property (nonatomic, assign) BOOL canceled;
@end
@implementation SDWebImageBatchItem
- (instancetype)initWithURLs:(NSArray *)urls URLOptions:(NSArray*)urlOptions startedBlock:(SDWebImagePrefetchStartedBlock)startedBlock progressBlock:(SDWebImagePrefetchProgressBlock)progressBlock completionBlock:(SDWebImagePrefetchCompletionBlock)completionBlock {
    if ((self = [super init])) {
        _prefetchItemsLeft = [[NSMutableArray alloc] initWithCapacity:urls.count];
        self.URLs = urls;
        self.URLOptions = urlOptions;
        _skippedCount = _finishedCount = 0;
        _startedTime = CFAbsoluteTimeGetCurrent();
        self.startedBlock = startedBlock;
        self.progressBlock = progressBlock;
        self.completionBlock = completionBlock;
    }
    return self;
}
@end

@interface SDWebImagePrefetcher ()

@property (nonatomic, strong) SDWebImageManager *manager;

@property (nonatomic, assign) NSUInteger nextBatchIndex;
@property (nonatomic, strong) NSMutableDictionary *prefetchItems; // URL->SDWebImagePrefetchItem
@property (nonatomic, strong) NSMutableDictionary *batchItems; // batchIndex->SDWebImageBatchItem

@end

@implementation SDWebImagePrefetcher

+ (SDWebImagePrefetcher *)sharedImagePrefetcher {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [[self alloc] initWithManager:[SDWebImageManager sharedManager]];
    });
    return instance;
}

- (instancetype)init {
    return [self initWithManager:[SDWebImageManager new]];
}

- (instancetype)initWithManager:(SDWebImageManager *)manager {
    if ((self = [super init])) {
        _manager = manager;
        _options = SDWebImageProgressiveDownload | (([[UIScreen mainScreen] respondsToSelector:@selector(scale)] && (int)[[UIScreen mainScreen] scale] >= 2) ? SDWebImageLoadAsRetinaImage : 0) | SDWebImageLowPriority | SDWebImageUsePrefetcherSizeLimit;
        
        _prefetchItems = [NSMutableDictionary new];
        _batchItems = [NSMutableDictionary new];
    }
    return self;
}

- (NSUInteger)prefetchURLsCount {
    return _prefetchItems.count;
}

- (void)startPrefetchForBatchIndex:(NSNumber *)sourceBatchIndex {
    @synchronized(self) {
        SDWebImageBatchItem *sourceBatchItem = [_batchItems objectForKey:sourceBatchIndex];
        
        if (sourceBatchItem.canceled)
            return;
        
        for (NSUInteger urlIndex = 0; urlIndex < sourceBatchItem.URLs.count; ++urlIndex) {
            NSURL *url = [sourceBatchItem.URLs objectAtIndex:urlIndex];
            SDWebImageOptions options = (urlIndex < sourceBatchItem.URLOptions.count && (id)[sourceBatchItem.URLOptions objectAtIndex:urlIndex] != (id)[NSNull null] ? [[sourceBatchItem.URLOptions  objectAtIndex:urlIndex] unsignedIntegerValue] : self.options);
            
            #ifdef DEBUG
                if (1)
                    NSLog(@"Prefetching: %@", url);
            #endif
            
            if (options & SDWebImageUsePrefetcherOptionsExceptPriority)
                options = (self.options & ~(SDWebImageLowPriority | SDWebImageHighPriority)) | (options & (SDWebImageLowPriority | SDWebImageHighPriority));
            else if (options & SDWebImageUsePrefetcherOptions)
                options = self.options;
            
            BOOL startOperation = NO;
            SDWebImagePrefetchItem *prefetchItem = [_prefetchItems objectForKey:url];
            
            if (!prefetchItem) {
                prefetchItem = [[SDWebImagePrefetchItem alloc] initWithBatchIndex:sourceBatchIndex URL:url];
                startOperation = YES;
            } else
                [prefetchItem.batchIndicies addObject:sourceBatchIndex];
            if (prefetchItem)
                [sourceBatchItem.prefetchItemsLeft addObject:prefetchItem];
            
            if (prefetchItem && startOperation) {
                SDWebImageCompletedWithFinishedBlock completionBlock = ^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
                    if (!(finished || error))
                        return;
                    
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        @synchronized(self) {
                            if ([prefetchItem.operation respondsToSelector:@selector(isCancelled)] && [(id)prefetchItem.operation isCancelled])
                                return;
                            
                            [_prefetchItems removeObjectForKey:prefetchItem.url];
                            
                            for (NSNumber *batchIndex in prefetchItem.batchIndicies) {
                                SDWebImageBatchItem *batchItem = [_batchItems objectForKey:batchIndex];
                                
                                [batchItem.prefetchItemsLeft removeObject:prefetchItem];
                                
                                if (image) {
                                    batchItem.finishedCount++;
                                    
                                    NSUInteger finishedCount = batchItem.finishedCount;
                                    NSUInteger skippedCount = batchItem.skippedCount;
                                    
                                    dispatch_async_main_queue(^{
                                        if (batchItem.progressBlock)
                                            batchItem.progressBlock(url, YES, finishedCount, skippedCount);
                                        
                                        if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didPrefetchURL:forBatchIndex:withFinishedCount:skippedCount:)])
                                            [self.delegate imagePrefetcher:self
                                                            didPrefetchURL:url
                                                             forBatchIndex:batchIndex
                                                         withFinishedCount:finishedCount
                                                              skippedCount:skippedCount];
                                    });
                                }
                                else {
                                    batchItem.skippedCount++;
                                    
                                    NSUInteger finishedCount = batchItem.finishedCount;
                                    NSUInteger skippedCount = batchItem.skippedCount;
                                    
                                    dispatch_async_main_queue(^{
                                        if (batchItem.progressBlock) {
                                            batchItem.progressBlock(url, NO, finishedCount, skippedCount);
                                        }
                                        
                                        if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didFailPrefetchingURL:error:forBatchIndex:withFinishedCount:skippedCount:)]) {
                                            [self.delegate imagePrefetcher:self
                                                     didFailPrefetchingURL:url
                                                                     error:error
                                                             forBatchIndex:batchIndex
                                                         withFinishedCount:finishedCount
                                                              skippedCount:skippedCount];
                                        }
                                    });
                                }
                                
                                if (!batchItem.prefetchItemsLeft.count) {
                                    batchItem.skippedCount = batchItem.URLs.count - batchItem.finishedCount; // Safety
                                    
                                    #ifdef DEBUG
                                        if (1)
                                            NSLog(@"Finished prefetching (%@ successful, %@ skipped, timeElasped %.2f)", @(batchItem.finishedCount), @(batchItem.skippedCount), CFAbsoluteTimeGetCurrent() - batchItem.startedTime);
                                    #endif
                                    
                                    NSUInteger finishedCount = batchItem.finishedCount;
                                    NSUInteger skippedCount = batchItem.skippedCount;
                                    
                                    dispatch_async_main_queue(^{
                                        if (batchItem.completionBlock)
                                            batchItem.completionBlock(finishedCount, skippedCount);
                                        
                                        if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didFinishForBatchIndex:withFinishedCount:skippedCount:)])
                                            [self.delegate imagePrefetcher:self
                                                    didFinishForBatchIndex:batchIndex
                                                         withFinishedCount:finishedCount
                                                              skippedCount:skippedCount];
                                    });
                                    
                                    [_batchItems removeObjectForKey:batchIndex];
                                }
                            }
                        }
                    });
                };
                
                // NOTE: I would like to keep this off the main thread, but we're having race conditions that I don't care to spend a lot of time fixing. --Johanna
                //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                dispatch_async_main_queue(^{
                    if (sourceBatchItem.canceled)
                        return;
                    
                    if (!(options & SDWebImageNoPrefetching) && ![self.manager downloadOperationsForURL:url].count) {
                        prefetchItem.operation = [self.manager downloadWithURL:url options:options progress:nil completed:[completionBlock copy]];
                    } else if (completionBlock)
                        completionBlock(nil, nil, SDImageCacheTypeNone, YES);
                });
            }
        }
        
        dispatch_async_main_queue(^{
            if (sourceBatchItem.canceled)
                return;
            
            if (sourceBatchItem.startedBlock)
                sourceBatchItem.startedBlock(sourceBatchIndex);
        });
    }
}

- (NSNumber *)prefetchURLs:(NSArray *)urls {
    return [self prefetchURLs:urls URLOptions:nil started:nil progress:nil completed:nil];
}

- (NSNumber *)prefetchURLs:(NSArray *)urls URLOptions:(NSArray *)urlOptions {
    return [self prefetchURLs:urls URLOptions:urlOptions started:nil progress:nil completed:nil];
}

- (NSNumber *)prefetchURLs:(NSArray *)urls progress:(SDWebImagePrefetchProgressBlock)progressBlock completed:(SDWebImagePrefetchCompletionBlock)completionBlock {
    return [self prefetchURLs:urls URLOptions:nil started:nil progress:progressBlock completed:completionBlock];
}

- (NSNumber *)prefetchURLs:(NSArray *)urls URLOptions:(NSArray *)urlOptions progress:(SDWebImagePrefetchProgressBlock)progressBlock completed:(SDWebImagePrefetchCompletionBlock)completionBlock {
    return [self prefetchURLs:urls URLOptions:urlOptions started:nil progress:progressBlock completed:completionBlock];
}

- (NSNumber *)prefetchURLs:(NSArray *)urls URLOptions:(NSArray *)urlOptions started:(SDWebImagePrefetchStartedBlock)startedBlock progress:(SDWebImagePrefetchProgressBlock)progressBlock completed:(SDWebImagePrefetchCompletionBlock)completionBlock {
    NSNumber *batchIndex = nil;
    
    if (urls.count) {
        @synchronized(self) {
            batchIndex = @(_nextBatchIndex++);
            SDWebImageBatchItem *batchItem = [[SDWebImageBatchItem alloc] initWithURLs:urls URLOptions:(urlOptions.count == urls.count ? urlOptions : nil) startedBlock:startedBlock progressBlock:progressBlock completionBlock:completionBlock];
            
            [_batchItems setObject:batchItem forKey:batchIndex];
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //dispatch_async_main_queue_ifnotmain(^{
            [self startPrefetchForBatchIndex:batchIndex];
        });
    }
    
    return batchIndex;
}

- (SDWebImageCombinedOperation *)operationForURL:(NSURL *)url {
    return [[_prefetchItems objectForKey:url] operation];
}

- (void)cancelAllPrefetching {
    @synchronized(self) {
        for (NSNumber *batchIndex in _batchItems.allKeys) {
            [self _cancelPrefetchingForBatchIndex:batchIndex];
        }
    }
}

- (void)cancelPrefetchingForBatchIndex:(NSNumber *)batchIndex {
    if (batchIndex) {
        @synchronized(self) {
            [self _cancelPrefetchingForBatchIndex:batchIndex];
        }
    }
}

- (void)_cancelPrefetchingForBatchIndex:(NSNumber *)batchIndex {
    SDWebImageBatchItem *batchItem = [_batchItems objectForKey:batchIndex];
    batchItem.canceled = YES;
    
    if (batchItem) {
        BOOL werePrefetchItemsLeft = batchItem.prefetchItemsLeft.count;
        
        for (SDWebImagePrefetchItem *prefetchItem in batchItem.prefetchItemsLeft) {
            [prefetchItem cancelOperation];
            
            batchItem.skippedCount++;
            
            NSURL *url = prefetchItem.url;
            NSUInteger finishedCount = batchItem.finishedCount;
            NSUInteger skippedCount = batchItem.skippedCount;
            
            dispatch_async_main_queue(^{
                if (batchItem.progressBlock) {
                    batchItem.progressBlock(url, NO, finishedCount, skippedCount);
                }
                
                if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didCancelPrefetchingURL:forBatchIndex:withFinishedCount:skippedCount:)]) {
                    [self.delegate imagePrefetcher:self
                           didCancelPrefetchingURL:url
                                     forBatchIndex:batchIndex
                                 withFinishedCount:finishedCount
                                      skippedCount:skippedCount];
                }
            });
        }
        
        [batchItem.prefetchItemsLeft removeAllObjects];
        batchItem.skippedCount = batchItem.URLs.count - batchItem.finishedCount; // Safety
        
        if (werePrefetchItemsLeft) {
            NSUInteger finishedCount = batchItem.finishedCount;
            NSUInteger skippedCount = batchItem.skippedCount;
            
            dispatch_async_main_queue(^{
                if (batchItem.completionBlock)
                    batchItem.completionBlock(finishedCount, skippedCount);
                
                if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didCancelForBatchIndex:withFinishedCount:skippedCount:)])
                    [self.delegate imagePrefetcher:self
                            didCancelForBatchIndex:batchIndex
                                 withFinishedCount:finishedCount
                                      skippedCount:skippedCount];
            });
        }
        
        [_batchItems removeObjectForKey:batchIndex];
    }
}

@end
