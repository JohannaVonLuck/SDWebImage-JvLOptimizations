/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDImageCache.h"
#import "SDWebImageDecoder.h"
#import "UIImage+MultiFormat.h"
#import "NSData+ImageContentType.h"
#import "OLImage.h"
#import <CommonCrypto/CommonDigest.h>
#import "HTCachePair.h"

static const NSInteger kDefaultCacheMaxCacheAge = 60 * 60 * 24 * 7; // 1 week
// PNG signature bytes and data (below)
static unsigned char kPNGSignatureBytes[8] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
static NSData *kPNGSignatureData = nil;

@interface SDImageCache ()

@property (strong, nonatomic) NSString *diskCachePath;
@property (strong, nonatomic) NSMutableArray *customPaths;
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t ioQueue;

@end


@implementation SDImageCache {
    NSFileManager *_fileManager;
}

+ (SDImageCache *)sharedImageCache {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
        kPNGSignatureData = [NSData dataWithBytes:kPNGSignatureBytes length:8];
    });
    return instance;
}

- (id)init {
    return [self initWithNamespace:@"default"];
}

- (id)initWithNamespace:(NSString *)ns {
    if ((self = [super init])) {
        NSString *fullNamespace = [@"com.hackemist.SDWebImageCache." stringByAppendingString:ns];
        
        // Create IO serial queue
        _ioQueue = dispatch_queue_create("com.hackemist.SDWebImageCache", DISPATCH_QUEUE_SERIAL);
        
        // Init default values
        _maxCacheAge = kDefaultCacheMaxCacheAge;
        
        // Init the memory cache
        _memCache = [[NSCache alloc] init];
        _memCache.name = fullNamespace;
        
        // Init the disk cache
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        _diskCachePath = [paths[0] stringByAppendingPathComponent:fullNamespace];

        dispatch_sync(_ioQueue, ^{
            _fileManager = [NSFileManager new];
        });

#if TARGET_OS_IPHONE
        // Subscribe to app events
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cleanDisk)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(backgroundCleanDisk)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
#endif
    }

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    SDDispatchQueueRelease(_ioQueue);
}

- (void)addReadOnlyCachePath:(NSString *)path {
    if (!self.customPaths) {
        self.customPaths = [NSMutableArray new];
    }

    if (![self.customPaths containsObject:path]) {
        [self.customPaths addObject:path];
    }
}

#pragma mark SDImageCache (private)

- (NSString *)cachePathForKey:(NSString *)key inPath:(NSString *)path {
    NSString *filename = [self cachedFileNameForKey:key];
    return [path stringByAppendingPathComponent:filename];
}

- (NSString *)defaultCachePathForKey:(NSString *)key {
    return [self cachePathForKey:key inPath:self.diskCachePath];
}

- (NSString *)cachedFileNameForKey:(NSString *)key {
    const char *str = [key UTF8String];
    if (str == NULL) {
        str = "";
    }
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                                                    r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15]];

    return filename;
}

#pragma mark ImageCache

- (void)storeImage:(UIImage *)image recalculateFromImage:(BOOL)recalculate imageData:(NSData *)imageData forKey:(NSString *)key toDisk:(BOOL)toDisk {
    if (!image || !key) {
        return;
    }
    
    CGFloat cost = image.size.height * image.size.width * image.scale;
    [self.memCache setObject:image forCachePairKey:key cost:cost];
    
    if (toDisk) {
        dispatch_async(_ioQueue, ^{
            NSData *data = imageData;
            
            if (image && (recalculate || !data)) {
                #if TARGET_OS_IPHONE
                    NSString *contentType = [NSData contentTypeForImageData:imageData];
                    
                    if ([contentType isEqualToString:@"image/png"] || [contentType isEqualToString:@"image/apng"] || [contentType isEqualToString:@"image/gif"])
                        data = UIImagePNGRepresentation(image);
                    else
                        data = UIImageJPEGRepresentation(image, 0.95f);
                #else
                    data = [NSBitmapImageRep representationOfImageRepsInArray:image.representations usingType: NSJPEGFileType properties:nil];
                #endif
            }
            
            if (data) {
                if (![_fileManager fileExistsAtPath:_diskCachePath]) {
                    [_fileManager createDirectoryAtPath:_diskCachePath withIntermediateDirectories:YES attributes:nil error:NULL];
                }

                [_fileManager createFileAtPath:[self defaultCachePathForKey:key] contents:data attributes:nil];
            }
        });
    }
}

- (void)storeImage:(UIImage *)image forKey:(NSString *)key {
    [self storeImage:image recalculateFromImage:YES imageData:nil forKey:key toDisk:YES];
}

- (void)storeImage:(UIImage *)image forKey:(NSString *)key toDisk:(BOOL)toDisk {
    [self storeImage:image recalculateFromImage:YES imageData:nil forKey:key toDisk:toDisk];
}

- (BOOL)imageFromCacheExistsForKey:(NSString *)key {
    return [self.memCache objectForCachePairKey:key] != nil || [self imageFromDiskCacheExistsForKey:key];
}

- (void)imageFromCacheExistsForKey:(NSString *)key completion:(SDWebImageCheckCacheCompletionBlock)completionBlock {
    if ([self.memCache objectForCachePairKey:key] != nil) {
        dispatch_async_main_queue(^{
            if (completionBlock)
                completionBlock(YES);
        });
    }
    
    [self imageFromDiskCacheExistsForKey:key completion:completionBlock];
}

- (BOOL)imageFromMemoryCacheExistsForKey:(NSString *)key {
    return [self.memCache objectForCachePairKey:key] != nil;
}

- (BOOL)imageFromDiskCacheExistsForKey:(NSString *)key {
    __block BOOL exists = NO;
    
    dispatch_sync(_ioQueue, ^{
        exists = [_fileManager fileExistsAtPath:[self defaultCachePathForKey:key]];
    });
    
    return exists;
}

- (void)imageFromDiskCacheExistsForKey:(NSString *)key completion:(SDWebImageCheckCacheCompletionBlock)completionBlock {
    dispatch_async(_ioQueue, ^{
        BOOL exists = [_fileManager fileExistsAtPath:[self defaultCachePathForKey:key]];
        
        dispatch_async_main_queue(^{
            if (completionBlock)
                completionBlock(exists);
        });
    });
}

- (UIImage *)imageFromCacheForKey:(NSString *)key options:(SDWebImageScaledOptions)options {
    UIImage *image = [self imageFromMemoryCacheForKey:key options:options];
    
    if (image) return image;
    
    __block UIImage *diskImage = nil;
    
    dispatch_sync(_ioQueue, ^{
        diskImage = [self _imageFromDiskCacheForKey:key options:(options & SDWebImageScaledLoadAsRetinaImage)];
        
        if (diskImage) {
            CGFloat cost = diskImage.size.height * diskImage.size.width * diskImage.scale;
            [self.memCache setObject:diskImage forCachePairKey:key cost:cost];
        }
    });
    
    return diskImage;
}

- (UIImage *)imageFromMemoryCacheForKey:(NSString *)key options:(SDWebImageScaledOptions)options {
    UIImage *image = [self.memCache objectForCachePairKey:key];
    
    if (image && options)
        image = [self scaledImageForKey:nil options:options image:image];
    
    return image;
}

- (UIImage *)_imageFromDiskCacheForKey:(NSString *)key options:(SDWebImageScaledOptions)options {
    NSData *data = [self imageDataFromDiskCacheBySearchingAllCachePathsForKey:key];
    
    if (data) {
        CGFloat scale = [key rangeOfString:@"@3x" options:NSCaseInsensitiveSearch].location != NSNotFound ? 3 : ((([key rangeOfString:@"@2x" options:NSCaseInsensitiveSearch].location != NSNotFound) || (options & SDWebImageScaledLoadAsRetinaImage)) ? 2 : 1);
        UIImage *image = [UIImage sd_imageWithData:data scale:scale];
        
        image = [self scaledImageForKey:key options:options image:image];
        image = [UIImage decodedImageWithImage:image];
        
        return image;
    } else {
        return nil;
    }
}

- (NSData *)imageDataFromDiskCacheForKey:(NSString *)key {
    __block NSData *data = nil;
    
    dispatch_sync(_ioQueue, ^{
        data = [self imageDataFromDiskCacheBySearchingAllCachePathsForKey:key];
    });
    
    return data;
}

- (void)imageDataFromDiskCacheForKey:(NSString *)key completion:(SDWebImageImageDataCompletionBlock)completionBlock {
    dispatch_async(_ioQueue, ^{
        NSData *data = [self imageDataFromDiskCacheBySearchingAllCachePathsForKey:key];
        
        dispatch_async_main_queue(^{
            if (completionBlock)
                completionBlock(data);
        });
    });
}

- (NSData *)imageDataFromDiskCacheBySearchingAllCachePathsForKey:(NSString *)key {
    NSString *defaultPath = [self defaultCachePathForKey:key];
    NSData *data = [NSData dataWithContentsOfFile:defaultPath];
    if (data) {
        return data;
    }
    
    for (NSString *path in self.customPaths) {
        NSString *filePath = [self cachePathForKey:key inPath:path];
        NSData *imageData = [NSData dataWithContentsOfFile:filePath];
        if (imageData) {
            return imageData;
        }
    }
    
    return nil;
}

- (UIImage *)scaledImageForKey:(NSString *)key options:(SDWebImageScaledOptions)options image:(UIImage *)image {
    return SDScaledImageForOptions(options, SDScaledImageForKey(key, image));
}

- (NSOperation *)queryCacheForKey:(NSString *)key options:(SDWebImageScaledOptions)options done:(void (^)(UIImage *image, SDImageCacheType cacheType))doneBlock {
    
    if (!doneBlock) return nil;
    
    if (!key) {
        doneBlock(nil, SDImageCacheTypeNone);
        return nil;
    }
    
    // First check the in-memory cache...
    UIImage *image = [self imageFromMemoryCacheForKey:key options:options];
    if (image) {
        doneBlock(image, SDImageCacheTypeMemory);
        return nil;
    }
    
    NSOperation *operation = [NSOperation new];
    dispatch_async(_ioQueue, ^{
        if (operation.isCancelled) {
            return;
        }
        
        UIImage *diskImage = nil;
        
        @autoreleasepool {
            diskImage = [self _imageFromDiskCacheForKey:key options:(options & SDWebImageScaledLoadAsRetinaImage)];
            if (diskImage) {
                CGFloat cost = diskImage.size.height * diskImage.size.width * diskImage.scale;
                [self.memCache setObject:diskImage forCachePairKey:key cost:cost];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            doneBlock(diskImage, SDImageCacheTypeDisk);
        });
    });
    
    return operation;
}

- (void)removeImageForKey:(NSString *)key {
    [self removeImageForKey:key withCompletion:nil];
}

- (void)removeImageForKey:(NSString *)key withCompletion:(void (^)())completion {
    [self removeImageForKey:key fromDisk:YES withCompletion:completion];
}

- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk {
    [self removeImageForKey:key fromDisk:fromDisk withCompletion:nil];
}

- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(void (^)())completion {
    if (key == nil) {
        return;
    }
    
    [self.memCache removeObjectForCachePairKey:key];
    
    if (fromDisk) {
        dispatch_async(self.ioQueue, ^{
            [_fileManager removeItemAtPath:[self defaultCachePathForKey:key] error:nil];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion();
                });
            }
        });
    } else if (completion) {
        completion();
    }
}

- (void)setMaxMemoryCost:(NSUInteger)maxMemoryCost {
    self.memCache.totalCostLimit = maxMemoryCost;
}

- (NSUInteger)maxMemoryCost {
    return self.memCache.totalCostLimit;
}

- (void)clearMemory {
    [_memCache removeAllObjects];
}

- (void)clearDisk {
    [self clearDiskOnCompletion:nil];
}

- (void)clearDiskOnCompletion:(void (^)())completion
{
    dispatch_async(_ioQueue, ^{
        [_fileManager removeItemAtPath:self.diskCachePath error:nil];
        [_fileManager createDirectoryAtPath:self.diskCachePath
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:NULL];

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

- (void)cleanDisk {
    [self cleanDiskWithCompletionBlock:nil];
}

- (void)cleanDiskWithCompletionBlock:(void (^)())completionBlock {
    dispatch_async(_ioQueue, ^{
        NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];
        NSArray *resourceKeys = @[NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];

        // This enumerator prefetches useful properties for our cache files.
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:resourceKeys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];

        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-self.maxCacheAge];
        NSMutableDictionary *cacheFiles = [NSMutableDictionary dictionary];
        NSUInteger currentCacheSize = 0;

        // Enumerate all of the files in the cache directory.  This loop has two purposes:
        //
        //  1. Removing files that are older than the expiration date.
        //  2. Storing file attributes for the size-based cleanup pass.
        NSMutableArray *urlsToDelete = [[NSMutableArray alloc] init];
        for (NSURL *fileURL in fileEnumerator) {
            NSDictionary *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:NULL];

            // Skip directories.
            if ([resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }

            // Remove files that are older than the expiration date;
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                [urlsToDelete addObject:fileURL];
                continue;
            }

            // Store a reference to this file and account for its total size.
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += [totalAllocatedSize unsignedIntegerValue];
            [cacheFiles setObject:resourceValues forKey:fileURL];
        }
        
        for (NSURL *fileURL in urlsToDelete) {
            [_fileManager removeItemAtURL:fileURL error:nil];
        }

        // If our remaining disk cache exceeds a configured maximum size, perform a second
        // size-based cleanup pass.  We delete the oldest files first.
        if (self.maxCacheSize > 0 && currentCacheSize > self.maxCacheSize) {
            // Target half of our maximum cache size for this cleanup pass.
            const NSUInteger desiredCacheSize = self.maxCacheSize / 2;

            // Sort the remaining cache files by their last modification time (oldest first).
            NSArray *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                            usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
                                                            }];

            // Delete files until we fall below our desired cache size.
            for (NSURL *fileURL in sortedFiles) {
                if ([_fileManager removeItemAtURL:fileURL error:nil]) {
                    NSDictionary *resourceValues = cacheFiles[fileURL];
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    currentCacheSize -= [totalAllocatedSize unsignedIntegerValue];

                    if (currentCacheSize < desiredCacheSize) {
                        break;
                    }
                }
            }
        }
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock();
            });
        }
    });
}

- (void)backgroundCleanDisk {
    UIApplication *application = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        // Clean up any unfinished task business by marking where you
        // stopped or ending the task outright.
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];

    // Start the long-running task and return immediately.
    [self cleanDiskWithCompletionBlock:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
}

- (NSUInteger)getSize {
    __block NSUInteger size = 0;
    dispatch_sync(_ioQueue, ^{
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtPath:self.diskCachePath];
        for (NSString *fileName in fileEnumerator) {
            NSString *filePath = [self.diskCachePath stringByAppendingPathComponent:fileName];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            size += [attrs fileSize];
        }
    });
    return size;
}

- (NSUInteger)getDiskCount {
    __block NSUInteger count = 0;
    dispatch_sync(_ioQueue, ^{
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtPath:self.diskCachePath];
        count = [[fileEnumerator allObjects] count];
    });
    return count;
}

- (void)calculateSizeWithCompletionBlock:(void (^)(NSUInteger fileCount, NSUInteger totalSize))completionBlock {
    NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];

    dispatch_async(_ioQueue, ^{
        NSUInteger fileCount = 0;
        NSUInteger totalSize = 0;

        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:@[NSFileSize]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];

        for (NSURL *fileURL in fileEnumerator) {
            NSNumber *fileSize;
            [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];
            totalSize += [fileSize unsignedIntegerValue];
            fileCount += 1;
        }

        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(fileCount, totalSize);
            });
        }
    });
}

@end
