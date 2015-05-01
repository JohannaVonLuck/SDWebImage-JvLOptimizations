/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloaderOperation.h"
#import "SDWebImageDecoder.h"
#import "UIImage+MultiFormat.h"
#import "NSData+ImageContentType.h"
#import <ImageIO/ImageIO.h>

@interface SDWebImageDownloaderOperation () {
    BOOL _ready;
    BOOL _executing;
    BOOL _finished;
    
    NSString *_imgContentType;
    OLImage *_incrementalImage;
}

@property (copy, nonatomic) SDWebImageDownloaderProgressBlock progressBlock;
@property (copy, nonatomic) SDWebImageDownloaderCompletedBlock completedBlock;
@property (copy, nonatomic) void (^cancelBlock)();

@property (assign, nonatomic, getter = isReady) BOOL ready;
@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;
@property (assign, nonatomic) NSInteger expectedSize;
@property (strong, nonatomic) NSMutableData *imageData;
@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, atomic) NSThread *thread;

#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;
#endif

@end

@implementation SDWebImageDownloaderOperation {
    size_t width, height;
    UIImageOrientation orientation;
    BOOL _responseFromCached;
}

- (id)initWithRequest:(NSURLRequest *)request options:(SDWebImageDownloaderOptions)options progress:(void (^)(NSInteger, NSInteger))progressBlock completed:(void (^)(UIImage *, NSData *, NSError *, BOOL))completedBlock cancelled:(void (^)())cancelBlock {
    if ((self = [super init])) {
        _request = request;
        _shouldUseCredentialStorage = YES;
        _options = options;
        _progressBlock = [progressBlock copy];
        _completedBlock = [completedBlock copy];
        _cancelBlock = [cancelBlock copy];
        _ready = NO;
        _executing = NO;
        _finished = NO;
        _expectedSize = 0;
        _responseFromCached = YES; // Initially wrong until `connection:willCacheResponse:` is called or not called
    }
    
    return self;
}

- (void)changeDownloaderPriorityOption:(SDWebImageDownloaderOptions)priorityOption {
    _options &= ~(SDWebImageDownloaderLowPriority | SDWebImageDownloaderHighPriority);
    _options |= (priorityOption & (SDWebImageDownloaderLowPriority | SDWebImageDownloaderHighPriority));
    
    if (self.parentImageDownloader.executionOrder != SDWebImageDownloaderLIFOExecutionOrder)
        [self.parentImageDownloader recalculateReadyStatuses];
}

- (void)changeDownloaderSizeLimitOptions:(SDWebImageDownloaderOptions)limitOptions {
    _options &= ~(SDWebImageDownloaderUsePrefetcherSizeLimit | SDWebImageDownloaderIgnoreAllSizeLimits);
    _options |= (limitOptions & (SDWebImageDownloaderUsePrefetcherSizeLimit | SDWebImageDownloaderIgnoreAllSizeLimits));
}

- (void)changeDownloaderPriorityAndSizeLimitOptions:(SDWebImageDownloaderOptions)downloadOptions {
    [self _changeDownloaderPriorityAndSizeLimitOptions:downloadOptions];
    
    if (self.parentImageDownloader.executionOrder != SDWebImageDownloaderLIFOExecutionOrder)
        [self.parentImageDownloader recalculateReadyStatuses];
}

- (void)_changeDownloaderPriorityAndSizeLimitOptions:(SDWebImageDownloaderOptions)downloadOptions {
    _options &= ~(SDWebImageDownloaderLowPriority | SDWebImageDownloaderHighPriority | SDWebImageDownloaderUsePrefetcherSizeLimit | SDWebImageDownloaderIgnoreAllSizeLimits);
    _options |= (downloadOptions & (SDWebImageDownloaderLowPriority | SDWebImageDownloaderHighPriority | SDWebImageDownloaderUsePrefetcherSizeLimit | SDWebImageDownloaderIgnoreAllSizeLimits));
}

- (void)recalculateReadyStatus {
    if (self.parentImageDownloader.executionOrder != SDWebImageDownloaderLIFOExecutionOrder) {
        if (_options & SDWebImageDownloaderHighPriority) {
            self.ready = YES;
        } else if (!(_options & SDWebImageDownloaderLowPriority)) {
            self.ready = self.parentImageDownloader.highPriorityOperations == 0;
        } else {
            self.ready = self.parentImageDownloader.medPriorityOperations == 0 && self.parentImageDownloader.highPriorityOperations == 0;
        }
    } else {
        if (!_ready)
            self.ready = YES;
    }
}

- (void)start {
    @synchronized (self) {
        if (self.isCancelled) {
            self.finished = YES;
            [self reset];
            return;
        }
        
        self.ready = YES; // Safety
        
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
        if ([self shouldContinueWhenAppEntersBackground]) {
            __weak __typeof__ (self) wself = self;
            self.backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                __strong __typeof (wself) sself = wself;
                
                if (sself) {
                    [sself cancel];
                    
                    [[UIApplication sharedApplication] endBackgroundTask:sself.backgroundTaskId];
                    sself.backgroundTaskId = UIBackgroundTaskInvalid;
                }
            }];
        }
#endif

        self.executing = YES;
        self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
        self.thread = [NSThread currentThread];
    }
    
    if (self.connection) {
        [self.connection start];
        
        if (self.progressBlock) {
            dispatch_sync_main_queue_safe(^{
                self.progressBlock(0, NSURLResponseUnknownLength);
            });
        }
        
        dispatch_sync_main_queue_safe(^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStartNotification object:self];
        });
        
        CFRunLoopRun();
        
        if (!self.isFinished) {
            [self.connection cancel];
            
            [self connection:self.connection didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:@{NSURLErrorFailingURLErrorKey : self.request.URL}]];
        }
    }
    else {
        SDWebImageDownloaderCompletedBlock completionBlock = self.completedBlock;
        
        if (completionBlock) {
            dispatch_async_main_queue_ifnotmain(^{
                completionBlock(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Connection can't be initialized"}], YES);
            });
        }
    }

#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
    if (self.backgroundTaskId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskId];
        self.backgroundTaskId = UIBackgroundTaskInvalid;
    }
#endif
}

- (void)cancel {
    @synchronized (self) {
        if (self.thread) {
            [self performSelector:@selector(cancelInternalAndStop) onThread:self.thread withObject:nil waitUntilDone:NO];
        }
        else {
            [self cancelInternal];
        }
    }
}

- (void)cancelInternalAndStop {
    if (self.isFinished) return;
    [self cancelInternal];
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)cancelInternal {
    if (self.isFinished) return;
    [super cancel];
    if (self.cancelBlock) self.cancelBlock();

    if (self.connection) {
        [self.connection cancel];
        
        dispatch_async_main_queue_ifnotmain(^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil
             ];
        });
        
        // As we cancelled the connection, its callback won't be called and thus won't
        // maintain the isFinished and isExecuting flags.
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }
    
    [self reset];
}

- (void)done {
    self.finished = YES;
    self.executing = NO;
    [self reset];
}

- (void)reset {
    self.cancelBlock = nil;
    self.completedBlock = nil;
    self.progressBlock = nil;
    self.connection = nil;
    self.imageData = nil;
    self.thread = nil;
    
    _imgContentType = nil;
    _incrementalImage = nil;
}

- (BOOL)isReady {
    return _ready;
}

- (void)setReady:(BOOL)ready {
    if (_executing || _finished)
        ready = YES;
    
    if (_ready != ready) {
        [self willChangeValueForKey:@"isReady"];
        _ready = ready;
        [self didChangeValueForKey:@"isReady"];
    }
}

- (BOOL)isExecuting {
    return _executing;
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isFinished {
    return _finished;
}

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isAsynchronous {
    return YES;
}

#pragma mark NSURLConnection (delegate)

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSInteger errorCode = 0;
    
    if ([response respondsToSelector:@selector(statusCode)])
        errorCode = [((NSHTTPURLResponse *)response) statusCode];
    
    if (!errorCode || errorCode < 400) {
        NSInteger expected = response.expectedContentLength > 0 ? (NSInteger)response.expectedContentLength : 0;
        self.expectedSize = expected;
        
        NSUInteger maxImageDownloadSize = (self.options & SDWebImageDownloaderIgnoreAllSizeLimits) ? 0 : ((self.options & SDWebImageDownloaderUsePrefetcherSizeLimit) ? self.maxPrefetchedImageDownloadSize : self.maxImageDownloadSize);
        
        if (!maxImageDownloadSize || self.expectedSize <= maxImageDownloadSize) {
            if (self.progressBlock) {
                dispatch_sync_main_queue_safe(^{
                    self.progressBlock(0, expected);
                });
            }
            
            self.imageData = [[NSMutableData alloc] initWithCapacity:expected];
            
            return;
        } else
            errorCode = NSURLErrorDataLengthExceedsMaximum;
    }
    
    [self.connection cancel];
    
    dispatch_async_main_queue_ifnotmain(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil];
    });
    
    SDWebImageDownloaderCompletedBlock completionBlock = self.completedBlock;
    
    if (completionBlock) {
        dispatch_async_main_queue_ifnotmain(^{
            completionBlock(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:errorCode userInfo:nil], YES);
        });
    }
    
    CFRunLoopStop(CFRunLoopGetCurrent());
    [self done];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.imageData appendData:data];
    
    BOOL contentTypeDiscovered = NO;
    if (_imgContentType.length <= 3) {
        _imgContentType = [NSData contentTypeForImageData:self.imageData];
        contentTypeDiscovered = _imgContentType.length > 3;
    }
    
    // NOTE: If the image we're trying to download is an animated GIF and it's over a certain size, unpacking that GIF is going to be very problematic, so error out instead of unpacking. --Johanna
    if (_imgContentType.length > 3 && !(self.options & SDWebImageIgnoreAllSizeLimits)) {
        NSUInteger maxImageDownloadSize = 0;
        
        if ([_imgContentType isEqualToString:@"image/gif"])
            maxImageDownloadSize = (self.options & SDWebImageDownloaderUsePrefetcherSizeLimit) ? self.maxPrefetchedGifImageDownloadSize : self.maxGifImageDownloadSize;
        else
            maxImageDownloadSize = (self.options & SDWebImageDownloaderUsePrefetcherSizeLimit) ? self.maxPrefetchedImageDownloadSize : self.maxImageDownloadSize;
        
        if (maxImageDownloadSize && (self.expectedSize > maxImageDownloadSize || self.imageData.length > maxImageDownloadSize)) {
            [self.connection cancel];
            
            dispatch_async_main_queue_ifnotmain(^{
                [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil];
            });
            
            SDWebImageDownloaderCompletedBlock completionBlock = self.completedBlock;
            
            if (completionBlock) {
                dispatch_async_main_queue_ifnotmain(^{
                    completionBlock(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil], YES);
                });
            }
            
            CFRunLoopStop(CFRunLoopGetCurrent());
            
            [self done];
            
            return;
        }
    }
    
    if ((self.options & SDWebImageDownloaderProgressiveDownload)) {
        if (contentTypeDiscovered) {
            if ([_imgContentType isEqualToString:@"image/gif"] || [_imgContentType isEqualToString:@"image/apng"]) {
                CGFloat scale = [self.request.URL.absoluteString rangeOfString:@"@3x" options:NSCaseInsensitiveSearch].location != NSNotFound ? 3 : (([self.request.URL.absoluteString rangeOfString:@"@2x" options:NSCaseInsensitiveSearch].location != NSNotFound || (self.options & SDWebImageDownloaderLoadAsRetinaImage)) ? 2 : 1);
                
                if (self.imageData.length >= self.expectedSize)
                    _incrementalImage = (OLImage *)[OLImage imageWithData:self.imageData scale:scale];
                else
                    _incrementalImage = (OLImage *)[OLImage imageWithIncrementalData:self.imageData scale:scale];
                
                if (![_incrementalImage isKindOfClass:[OLImage class]])
                    _incrementalImage = nil;
                
                if (_incrementalImage.isReady && (self.progressBlock || self.completedBlock)) {
                    dispatch_sync_main_queue_safe(^{
                        if (self.progressBlock) {
                            self.progressBlock(self.imageData.length, self.expectedSize);
                        }
                        if (self.completedBlock) {
                            self.completedBlock(_incrementalImage, self.imageData, nil, NO);
                        }
                    });
                }
            }
        } else if (_incrementalImage) {
            [_incrementalImage updateWithData:self.imageData final:(self.imageData.length >= self.expectedSize)];
            
            if (_incrementalImage.isReady && (self.progressBlock || self.completedBlock)) {
                dispatch_sync_main_queue_safe(^{
                    if (self.progressBlock) {
                        self.progressBlock(self.imageData.length, self.expectedSize);
                    }
                    if (self.completedBlock) {
                        self.completedBlock(_incrementalImage, self.imageData, nil, NO);
                    }
                });
            }
        }
        
        if ((!_incrementalImage || !_incrementalImage.isReady) && self.expectedSize > 0 && (self.progressBlock || self.completedBlock) && (self.options & SDWebImageDownloaderHighPriority)) {
            @autoreleasepool {
                // The following code is from http://www.cocoaintheshell.com/2011/05/progressive-images-download-imageio/
                // Thanks to the author @Nyx0uf
                
                // Get the total bytes downloaded
                const NSInteger totalSize = self.imageData.length;
                
                // Update the data source, we must pass ALL the data, not just the new bytes
                CGImageSourceRef imageSource = CGImageSourceCreateIncremental(NULL);
                CGImageSourceUpdateData(imageSource, (__bridge CFDataRef)self.imageData, totalSize == self.expectedSize);
                
                if (width + height == 0) {
                    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
                    if (properties) {
                        NSInteger orientationValue = -1;
                        CFTypeRef val = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
                        if (val) CFNumberGetValue(val, kCFNumberLongType, &height);
                        val = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
                        if (val) CFNumberGetValue(val, kCFNumberLongType, &width);
                        val = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
                        if (val) CFNumberGetValue(val, kCFNumberNSIntegerType, &orientationValue);
                        CFRelease(properties);

                        // When we draw to Core Graphics, we lose orientation information,
                        // which means the image below born of initWithCGIImage will be
                        // oriented incorrectly sometimes. (Unlike the image born of initWithData
                        // in connectionDidFinishLoading.) So save it here and pass it on later.
                        orientation = [[self class] orientationFromPropertyValue:(orientationValue == -1 ? 1 : orientationValue)];
                    }

                }
                
                if (width + height > 0 && totalSize < self.expectedSize) {
                    // Create the image
                    CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
                    
                    #ifdef TARGET_OS_IPHONE
                        // Workaround for iOS anamorphic image
                        if (partialImageRef) {
                            const size_t partialHeight = CGImageGetHeight(partialImageRef);
                            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                            CGContextRef bmContext = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
                            CGColorSpaceRelease(colorSpace);
                            if (bmContext) {
                                CGContextDrawImage(bmContext, (CGRect) {.origin.x = 0.0f, .origin.y = 0.0f, .size.width = width, .size.height = partialHeight}, partialImageRef);
                                CGImageRelease(partialImageRef);
                                partialImageRef = CGBitmapContextCreateImage(bmContext);
                                CGContextRelease(bmContext);
                            }
                            else {
                                CGImageRelease(partialImageRef);
                                partialImageRef = nil;
                            }
                        }
                    #endif
                    
                    if (partialImageRef) {
                        CGFloat scale = [self.request.URL.absoluteString rangeOfString:@"@3x" options:NSCaseInsensitiveSearch].location != NSNotFound ? 3 : (([self.request.URL.absoluteString rangeOfString:@"@2x" options:NSCaseInsensitiveSearch].location != NSNotFound || (self.options & SDWebImageDownloaderLoadAsRetinaImage)) ? 2 : 1);
                        
                        UIImage *image = [UIImage imageWithCGImage:partialImageRef scale:scale orientation:orientation];
                        
                        NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:self.request.URL];
                        
                        image = [self scaledImageForKey:key options:(self.options & SDWebImageDownloaderLoadAsRetinaImage) image:image];
                        image = [UIImage decodedImageWithImage:image];
                        
                        CGImageRelease(partialImageRef);
                        
                        dispatch_sync_main_queue_safe(^{
                            if (self.progressBlock) {
                                self.progressBlock(self.imageData.length, self.expectedSize);
                            }
                            if (self.completedBlock) {
                                self.completedBlock(image, self.imageData, nil, NO);
                            }
                        });
                    }
                }
                
                CFRelease(imageSource);
            }
        }
    } else if (self.progressBlock) {
        dispatch_sync_main_queue_safe(^{
            if (self.progressBlock) {
                self.progressBlock(self.imageData.length, self.expectedSize);
            }
        });
    }
}

+ (UIImageOrientation)orientationFromPropertyValue:(NSInteger)value {
    switch (value) {
        case 1:
            return UIImageOrientationUp;
        case 3:
            return UIImageOrientationDown;
        case 8:
            return UIImageOrientationLeft;
        case 6:
            return UIImageOrientationRight;
        case 2:
            return UIImageOrientationUpMirrored;
        case 4:
            return UIImageOrientationDownMirrored;
        case 5:
            return UIImageOrientationLeftMirrored;
        case 7:
            return UIImageOrientationRightMirrored;
        default:
            return UIImageOrientationUp;
    }
}

- (UIImage *)scaledImageForKey:(NSString *)key options:(SDWebImageScaledOptions)options image:(UIImage *)image {
    return SDScaledImageForOptions(options, SDScaledImageForKey(key, image));
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection {
    SDWebImageDownloaderCompletedBlock completionBlock = self.completedBlock;
    
    @synchronized(self) {
        CFRunLoopStop(CFRunLoopGetCurrent());
        self.thread = nil;
        self.connection = nil;
        
        dispatch_async_main_queue_ifnotmain(^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil];
        });
    }
    
    if (![[NSURLCache sharedURLCache] cachedResponseForRequest:_request]) {
        _responseFromCached = NO;
    }
    
    if (completionBlock) {
        if (self.options & SDWebImageDownloaderIgnoreCachedResponse && _responseFromCached) {
            dispatch_async_main_queue_ifnotmain(^{
                completionBlock(nil, nil, nil, YES);
            });
        }
        else {
            UIImage *image = _incrementalImage;
            NSData *imageData = _imageData;
            
            if (!image) {
                NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:self.request.URL];
                
                image = [UIImage sd_imageWithData:self.imageData scale:[self.request.URL.absoluteString rangeOfString:@"@3x" options:NSCaseInsensitiveSearch].location != NSNotFound ? 3 : (([self.request.URL.absoluteString rangeOfString:@"@2x" options:NSCaseInsensitiveSearch].location != NSNotFound || (self.options & SDWebImageDownloaderLoadAsRetinaImage)) ? 2 : 1)];
                
                image = [self scaledImageForKey:key options:(self.options & SDWebImageDownloaderLoadAsRetinaImage) image:image];
                image = [UIImage decodedImageWithImage:image];
            }
            
            if (CGSizeEqualToSize(image.size, CGSizeZero)) {
                dispatch_async_main_queue_ifnotmain(^{
                    completionBlock(nil, nil, [NSError errorWithDomain:@"SDWebImageErrorDomain" code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image has 0 pixels"}], YES);
                });
            } else {
                dispatch_async_main_queue_ifnotmain(^{
                    completionBlock(image, imageData, nil, YES);
                });
            }
        }
    }
    
    self.completionBlock = nil;
    [self done];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    CFRunLoopStop(CFRunLoopGetCurrent());
    
    dispatch_async_main_queue_ifnotmain(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil];
    });
    
    SDWebImageDownloaderCompletedBlock completionBlock = self.completedBlock;
    
    if (completionBlock) {
        dispatch_async_main_queue_ifnotmain(^{
            completionBlock(nil, nil, error, YES);
        });
    }
    
    [self done];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    _responseFromCached = NO; // If this method is called, it means the response wasn't read from cache
    if (self.request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData) {
        // Prevents caching of responses
        return nil;
    }
    else {
        return cachedResponse;
    }
}

- (BOOL)shouldContinueWhenAppEntersBackground {
    return self.options & SDWebImageDownloaderContinueInBackground;
}

- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection __unused *)connection {
    return self.shouldUseCredentialStorage;
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge{
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
    } else {
        if ([challenge previousFailureCount] == 0) {
            if (self.credential) {
                [[challenge sender] useCredential:self.credential forAuthenticationChallenge:challenge];
            } else {
                [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
            }
        } else {
            [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
        }
    }
}

@end
