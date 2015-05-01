/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloader.h"
#import "SDWebImageDownloaderOperation.h"
#import <ImageIO/ImageIO.h>

NSString *const SDWebImageDownloadStartNotification = @"SDWebImageDownloadStartNotification";
NSString *const SDWebImageDownloadStopNotification = @"SDWebImageDownloadStopNotification";

static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

@interface SDWebImageDownloader ()

@property (strong, nonatomic) NSOperationQueue *downloadQueue;
@property (weak, nonatomic) NSOperation *lastAddedOperation;
@property (strong, nonatomic) NSMutableDictionary *URLCallbacks;
@property (strong, nonatomic) NSMutableDictionary *downloadOperations;
@property (strong, nonatomic) NSMutableDictionary *HTTPHeaders;
// This queue is used to serialize the handling of the network responses of all the download operation in a single queue
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t barrierQueue;

@end

@implementation SDWebImageDownloader

+ (void)initialize {
    // Bind SDNetworkActivityIndicator if available (download it here: http://github.com/rs/SDNetworkActivityIndicator )
    // To use it, just add #import "SDNetworkActivityIndicator.h" in addition to the SDWebImage import
    if (NSClassFromString(@"SDNetworkActivityIndicator")) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];
#pragma clang diagnostic pop

        // Remove observer in case it was previously added.
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"startActivity")
                                                     name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"stopActivity")
                                                     name:SDWebImageDownloadStopNotification object:nil];
    }
}

+ (SDWebImageDownloader *)sharedDownloader {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _executionOrder = SDWebImageDownloaderFIFOExecutionOrder;
        _downloadQueue = [NSOperationQueue new];
        _downloadQueue.maxConcurrentOperationCount = 2;
        if ([_downloadQueue respondsToSelector:@selector(setQualityOfService:)])
            _downloadQueue.qualityOfService = NSQualityOfServiceUtility;
        _downloadOperations = [NSMutableDictionary new];
        _URLCallbacks = [NSMutableDictionary new];
        _HTTPHeaders = [NSMutableDictionary dictionaryWithObject:@"image/webp,image/*;q=0.8" forKey:@"Accept"];
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        _downloadTimeout = 30.0;
    }
    return self;
}

- (void)dealloc {
    [self.downloadQueue cancelAllOperations];
    SDDispatchQueueRelease(_barrierQueue);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (value) {
        self.HTTPHeaders[field] = value;
    }
    else {
        [self.HTTPHeaders removeObjectForKey:field];
    }
}

- (NSString *)valueForHTTPHeaderField:(NSString *)field {
    return self.HTTPHeaders[field];
}

- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    _downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
}

- (NSUInteger)currentDownloadCount {
    return _downloadQueue.operationCount;
}

- (NSInteger)maxConcurrentDownloads {
    return _downloadQueue.maxConcurrentOperationCount;
}

- (SDWebImageDownloaderOperation *)downloadImageWithURL:(NSURL *)url options:(SDWebImageDownloaderOptions)options progress:(void (^)(NSInteger, NSInteger))progressBlock completed:(void (^)(UIImage *, NSData *, NSError *, BOOL))completedBlock {
    __block SDWebImageDownloaderOperation *operation = nil;
    __weak SDWebImageDownloader *wself = self;
    
    [self addProgressCallback:progressBlock andCompletedBlock:completedBlock forURL:url createCallback:^{
        NSTimeInterval timeoutInterval = wself.downloadTimeout;
        if (timeoutInterval <= FLT_EPSILON)
            timeoutInterval = 30.0;
        
        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        
        if (wself.headersFilter)
            request.allHTTPHeaderFields = wself.headersFilter(url, [wself.HTTPHeaders copy]);
        else
            request.allHTTPHeaderFields = wself.HTTPHeaders;
        
        operation = [[SDWebImageDownloaderOperation alloc] initWithRequest:request options:options progress:^(NSInteger receivedSize, NSInteger expectedSize) {
            __strong SDWebImageDownloader *sself = wself;
            if (!sself) return;
            
            NSArray *callbacksForURL = [sself callbacksForURL:url];
            
            for (NSDictionary *callbacks in callbacksForURL) {
                SDWebImageDownloaderProgressBlock callback = callbacks[kProgressCallbackKey];
                if (callback) callback(receivedSize, expectedSize);
            }
        } completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
            __strong SDWebImageDownloader *sself = wself;
            if (!sself) return;
            
            NSArray *callbacksForURL = [sself callbacksForURL:url];
            
            if (finished)
                [sself removeOperationAndCallbacksForURL:url];
            
            for (NSDictionary *callbacks in callbacksForURL) {
                SDWebImageDownloaderCompletedBlock callback = callbacks[kCompletedCallbackKey];
                if (callback) callback(image, data, error, finished);
            }
        } cancelled:^{
            __strong SDWebImageDownloader *sself = wself;
            if (!sself) return;
            
            [sself removeOperationAndCallbacksForURL:url];
        }];
        
        wself.downloadOperations[url] = operation;
        operation.parentImageDownloader = wself;
        
        operation.maxImageDownloadSize = wself.maxImageDownloadSize;
        operation.maxGifImageDownloadSize = wself.maxGifImageDownloadSize;
        operation.maxPrefetchedImageDownloadSize = wself.maxPrefetchedImageDownloadSize;
        operation.maxPrefetchedGifImageDownloadSize = wself.maxPrefetchedGifImageDownloadSize;
        
        if (wself.username && wself.password) {
            operation.credential = [NSURLCredential credentialWithUser:wself.username password:wself.password persistence:NSURLCredentialPersistenceForSession];
        }
        
        if (wself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            // Emulate LIFO execution order by systematically adding new operations as last operation's dependency
            [wself.lastAddedOperation addDependency:operation];
            wself.lastAddedOperation = operation;
        }
        
        [wself _recalculateReadyStatuses];
        
        // NOTE: The queue priority here is meaningless. The actual item ordering performed depends upon the dynamically set isReady flag, which depends on what items are in the system and what their priority setting is. --Johanna
        operation.queuePriority = NSOperationQueuePriorityNormal;
        [wself.downloadQueue addOperation:operation];
    } didNotCreateCallback:^{
        operation = [wself.downloadOperations objectForKey:url];
        
        [operation _changeDownloaderPriorityAndSizeLimitOptions:options];
        [wself _recalculateReadyStatuses];
    }];
    
    return operation;
}

- (void)addProgressCallback:(void (^)(NSInteger, NSInteger))progressBlock andCompletedBlock:(void (^)(UIImage *, NSData *data, NSError *, BOOL))completedBlock forURL:(NSURL *)url createCallback:(void (^)())createCallback didNotCreateCallback:(void (^)())didNotCreateCallback {
    // The URL will be used as the key to the callbacks dictionary so it cannot be nil. If it is nil immediately call the completed block with no image or data.
    if (url == nil) {
        if (completedBlock != nil) {
            completedBlock(nil, nil, nil, NO);
        }
        return;
    }
    
    dispatch_barrier_sync(self.barrierQueue, ^{
        BOOL first = NO;
        if (!self.URLCallbacks[url]) {
            self.URLCallbacks[url] = [NSMutableArray new];
            first = YES;
        }
        
        // Handle single download of simultaneous download request for the same URL
        NSMutableDictionary *callbacks = [NSMutableDictionary new];
        if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
        if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
        
        NSMutableArray *callbacksForURL = self.URLCallbacks[url];
        [callbacksForURL addObject:callbacks];
        
        if (first) {
            if (createCallback)
                createCallback();
        } else {
            if (didNotCreateCallback)
                didNotCreateCallback();
        }
    });
}

- (SDWebImageDownloaderOperation *)downloaderOperationForURL:(NSURL *)url {
    __block SDWebImageDownloaderOperation *operation = nil;
    
    dispatch_sync(self.barrierQueue, ^{
        operation = [self.downloadOperations objectForKey:url];
    });
    
    return operation;
}

- (NSArray *)callbacksForURL:(NSURL *)url {
    __block NSArray *callbacksForURL;
    
    dispatch_sync(self.barrierQueue, ^{
        callbacksForURL = self.URLCallbacks[url];
    });
    
    return [callbacksForURL copy];
}

- (void)removeOperationAndCallbacksForURL:(NSURL *)url {
    __block NSArray *callbacksForURL = nil;
    __block SDWebImageDownloaderOperation *operation = nil;
    
    dispatch_barrier_async(self.barrierQueue, ^{
        callbacksForURL = self.URLCallbacks[url];
        operation = self.downloadOperations[url];
        
        [self.URLCallbacks removeObjectForKey:url];
        [self.downloadOperations removeObjectForKey:url];
        
        // NOTE: Removing these objects on main thread prevents this barrierQueue from having issues with deallocs that need to dispatch sync onto main thread, which can cause deadlock situations. --Johanna
        dispatch_async_main_queue(^{
            callbacksForURL = nil;
            operation = nil;
        });
        
        [self _recalculateReadyStatuses];
    });
}

- (void)setSuspended:(BOOL)suspended {
    [self.downloadQueue setSuspended:suspended];
}

- (void)recalculateReadyStatuses {
    dispatch_barrier_async(self.barrierQueue, ^{
        [self _recalculateReadyStatuses];
    });
}

- (void)_recalculateReadyStatuses {
    NSArray *downloadOperations = self.downloadOperations.allValues;
    
    _highPriorityOperations = _medPriorityOperations = 0;
    
    for (SDWebImageDownloaderOperation *operation in downloadOperations) {
        if (!operation.isFinished && !operation.isCancelled) {
            SDWebImageDownloaderOptions options = operation.options;
            
            if (options & SDWebImageDownloaderHighPriority)
                ++_highPriorityOperations;
            else if (!(options & SDWebImageDownloaderLowPriority))
                ++_medPriorityOperations;
        }
    }
    
    for (SDWebImageDownloaderOperation *operation in downloadOperations)
        [operation recalculateReadyStatus];
}

@end
