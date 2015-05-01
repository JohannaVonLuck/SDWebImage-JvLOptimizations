//
//  OLImage.m
//  MMT
//
//  Created by Diego Torres on 9/1/12.
//  Copyright (c) 2012 Onda. All rights reserved.
//

#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "OLImage.h"
#import "SDImageCache.h"
#import "HTCachePair.h"

//Define FLT_EPSILON because, reasons.
//Actually, I don't know why but it seems under certain circumstances it is not defined
#ifndef FLT_EPSILON
#define FLT_EPSILON __FLT_EPSILON__
#endif

// Stolen from iOS 8 for Animated PNGs
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 80000
#define kCGImagePropertyAPNGLoopCount           kCGImagePropertyGIFLoopCount
#define kCGImagePropertyAPNGDelayTime           kCGImagePropertyGIFDelayTime
#define kCGImagePropertyAPNGUnclampedDelayTime  kCGImagePropertyGIFUnclampedDelayTime
#else // Just for iOS 8 beta, in which these are link time undefined
const CFStringRef kCGImagePropertyAPNGLoopCount = CFSTR("LoopCount");
const CFStringRef kCGImagePropertyAPNGDelayTime = CFSTR("DelayTime");
const CFStringRef kCGImagePropertyAPNGUnclampedDelayTime = CFSTR("UnclampedDelayTime");
#endif

inline static BOOL CGImageSourceContainsAnimatedGif (CGImageSourceRef imageSource)
{
    return imageSource && UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypeGIF) && CGImageSourceGetCount(imageSource) > 1;
}

inline static BOOL CGImageSourceContainsAnimatedPng(CGImageSourceRef imageSource)
{
    return imageSource && UTTypeConformsTo(CGImageSourceGetType(imageSource), kUTTypePNG) && CGImageSourceGetCount(imageSource) > 1;
}

inline static BOOL isHDRetinaFilePath(NSString *path)
{
    NSRange retinaSuffixRange = [[path lastPathComponent] rangeOfString:@"@3x" options:NSCaseInsensitiveSearch];
    return retinaSuffixRange.length && retinaSuffixRange.location != NSNotFound;
}

inline static BOOL isRetinaFilePath(NSString *path)
{
    NSRange retinaSuffixRange = [[path lastPathComponent] rangeOfString:@"@2x" options:NSCaseInsensitiveSearch];
    return retinaSuffixRange.length && retinaSuffixRange.location != NSNotFound;
}

@interface OLImageSourceArray : NSArray {
    NSUInteger _count;
    
    CGSize _size;
    BOOL _hasComputedSize;  // size is a nasty one requested at odd intervals, so special handling is done
}

@property (nonatomic, readonly) CGImageSourceRef imageSource;
@property (nonatomic, assign) CFDataRef imageData;

@property (nonatomic, readonly) CGFloat scale;
@property (nonatomic, readonly) CGSize size;
@property (nonatomic, readonly) CGImageRef CGImage;

@property (nonatomic, readonly) NSLock *mutexLock;

@property (nonatomic, strong) NSDictionary *globalProperties;   // Parental ref, for ro-access
@property (nonatomic, strong) NSArray *imagesProperties;        // Parental ref, for ro-access

- (void)updateCount;

+ (instancetype)arrayWithImageSource:(CGImageSourceRef)imageSource imageData:(CFDataRef)imageData scale:(CGFloat)scale;

@end

@interface OLImage () {
    CFDataRef _incrementalData;
    CGImageSourceRef _incrementalSource;
    
    NSDictionary *_globalProperties;
    NSMutableArray *_imagesProperties;
}

@property (nonatomic, readwrite) NSTimeInterval *frameDurations;
@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) NSUInteger loopCount;
@property (nonatomic, readwrite) OLImageSourceArray *imageSourceArray;

@end

@implementation OLImage

@synthesize images;

#pragma mark - Class Methods

+ (instancetype)imageNamed:(NSString *)name
{
    NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:name];
    
    return (OLImage *)(([[NSFileManager defaultManager] fileExistsAtPath:path]) ? [self imageWithContentsOfFile:path] : nil);
}

+ (instancetype)imageWithContentsOfFile:(NSString *)path
{
    return (OLImage *)[self imageWithData:[NSData dataWithContentsOfFile:path]
                                    scale:isHDRetinaFilePath(path) ? 3.0 : (isRetinaFilePath(path) ? 2.0f : 1.0f)];
}

+ (instancetype)imageWithData:(NSData *)data
{
    return (OLImage *)[self imageWithData:data scale:1.0f];
}

+ (instancetype)imageWithData:(NSData *)data scale:(CGFloat)scale
{
    if (!data.length)
        return nil;
    
    CFDataRef imageData = CFDataCreateCopy(kCFAllocatorDefault, (__bridge CFDataRef)data);
    CGImageSourceRef imageSource = CGImageSourceCreateWithData(imageData, NULL);
    
    UIImage *image = nil;
    if (CGImageSourceContainsAnimatedGif (imageSource) || CGImageSourceContainsAnimatedPng(imageSource)) {
        image = [[self alloc] initWithImageSource:imageSource imageData:imageData scale:scale];
    } else {
        image = [super imageWithData:data scale:scale];
    }
    
    if (imageSource) {
        CFRelease(imageSource); imageSource = NULL;
    }
    if (imageData) {
        CFRelease(imageData); imageData = NULL;
    }
    
    return (OLImage *)image;
}

#pragma mark - Initialization methods

- (instancetype)initWithContentsOfFile:(NSString *)path
{
    return [self initWithData:[NSData dataWithContentsOfFile:path]
                        scale:isHDRetinaFilePath(path) ? 3.0 : (isRetinaFilePath(path) ? 2.0f : 1.0f)];
}

- (instancetype)initWithData:(NSData *)data
{
    return [self initWithData:data scale:1.0f];
}

- (instancetype)initWithData:(NSData *)data scale:(CGFloat)scale
{
    if (!data.length)
        return nil;
    
    CFDataRef imageData = CFDataCreateCopy(kCFAllocatorDefault, (__bridge CFDataRef)data);
    CGImageSourceRef imageSource = CGImageSourceCreateWithData(imageData, NULL);
    
    if (CGImageSourceContainsAnimatedGif(imageSource) || CGImageSourceContainsAnimatedPng(imageSource)) {
        self = [self initWithImageSource:imageSource imageData:imageData scale:scale];
    } else {
        self = [super initWithData:data scale:scale];
    }
    
    if (imageSource) {
        CFRelease(imageSource); imageSource = NULL;
    }
    if (imageData) {
        CFRelease(imageData); imageData = NULL;
    }
    
    return self;
}

- (instancetype)initWithImageSource:(CGImageSourceRef)imageSource imageData:(CFDataRef)imageData scale:(CGFloat)scale {
    return [self initWithImageSource:imageSource imageData:imageData scale:scale asIncremental:NO asFinal:YES];
}

- (instancetype)initWithImageSource:(CGImageSourceRef)imageSource imageData:(CFDataRef)imageData scale:(CGFloat)scale asIncremental:(BOOL)isIncremental asFinal:(BOOL)isFinal {
    if ((self = [super init])) {
        if (!imageSource)
            return self = nil;
        
        _imageSourceArray = [OLImageSourceArray arrayWithImageSource:imageSource imageData:imageData scale:scale];
        
        [_imageSourceArray.mutexLock lock];
        
        if (isIncremental) {
            if (imageData) {
                CFRetain(imageData);
                _incrementalData = imageData;
            }
            CFRetain(imageSource);
            _incrementalSource = imageSource;
        }
        
        if (isIncremental && _incrementalData && CFDataGetLength(_incrementalData) > 0)
            CGImageSourceUpdateData(_incrementalSource, _incrementalData, isFinal);
        
        [self updateGlobalProperties];
        [self updateImagesProperties];
        [self.imageSourceArray updateCount];
        
        if (isFinal) {
            if (_incrementalSource) {
                CFRelease(_incrementalSource); _incrementalSource = NULL;
            }
            if (_incrementalData) {
                CFRelease(_incrementalData); _incrementalData = NULL;
            }
        }
        
        [_imageSourceArray.mutexLock unlock];
    }
    
    return self;
}

- (void)dealloc {
    if (_frameDurations) {
        free(_frameDurations); _frameDurations = NULL;
    }
    if (_incrementalSource) {
        CFRelease(_incrementalSource); _incrementalSource = NULL;
    }
    if (_incrementalData) {
        CFRelease(_incrementalData); _incrementalData = NULL;
    }
}

#pragma mark - Compatibility methods

- (NSArray *)images {
    return self.imageSourceArray;
}

- (CGSize)size {
    if (self.imageSourceArray.count)
        return self.imageSourceArray.size;
    
    return [super size];
}

- (CGImageRef)CGImage {
    if (self.imageSourceArray.count)
        return self.imageSourceArray.CGImage;
    
    return [super CGImage];
}

- (UIImageOrientation)imageOrientation {
    if (self.imageSourceArray.count)
        return UIImageOrientationUp;
    
    return [super imageOrientation];
}

- (CGFloat)scale {
    if (self.imageSourceArray)
        return self.imageSourceArray.scale;
    
    return [super scale];
}

- (NSTimeInterval)duration {
    return self.images ? self.totalDuration : [super duration];
}

#pragma mark - Methods

- (void)updateGlobalProperties {
    if (!_globalProperties) {
        CGImageSourceRef imageSource = self.imageSourceArray.imageSource;
        NSMutableDictionary *sourceProperties = [((__bridge_transfer NSDictionary *)(CGImageSourceCopyProperties(imageSource, NULL))) mutableCopy];
        
        if (sourceProperties) {
            NSDictionary *formatProperties = nil;
            
            if (CGImageSourceContainsAnimatedPng(imageSource))
                formatProperties = [sourceProperties objectForKey:(NSString *)kCGImagePropertyPNGDictionary];
            else
                formatProperties = [sourceProperties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
            
            if (formatProperties) {
                [sourceProperties addEntriesFromDictionary:formatProperties];
                
                size_t imageCount = CGImageSourceGetCount(imageSource);
                NSMutableArray *imagesProperties = [[NSMutableArray alloc] initWithCapacity:imageCount];
                
                _globalProperties = sourceProperties;
                _imagesProperties = imagesProperties;
                
                self.imageSourceArray.globalProperties = _globalProperties;
                self.imageSourceArray.imagesProperties = _imagesProperties;
                
                if (CGImageSourceContainsAnimatedPng(imageSource))
                    self.loopCount = [formatProperties[(__bridge NSString *)kCGImagePropertyAPNGLoopCount] unsignedIntegerValue];
                else
                    self.loopCount = [formatProperties[(__bridge NSString *)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
            }
        }
    }
}

- (void)updateImagesProperties {
    if (_globalProperties) {
        CGImageSourceRef imageSource = self.imageSourceArray.imageSource;
        NSUInteger imageCount = CGImageSourceGetCount(imageSource);
        NSTimeInterval totalDuration = 0;
        
        if (imageCount > _imagesProperties.count) {
            NSTimeInterval *frameDurations = calloc(imageCount, sizeof(NSTimeInterval));
            if (_frameDurations) {
                if (_imagesProperties.count)
                    memcpy(frameDurations, _frameDurations, sizeof(NSTimeInterval) * _imagesProperties.count);
                free(_frameDurations);
            }
            _frameDurations = frameDurations;
            
            for (NSUInteger imageIndex = _imagesProperties.count; imageIndex < imageCount; ++imageIndex) {
                [_imagesProperties addObject:[NSMutableDictionary new]];
                _frameDurations[imageIndex] = 0.1;
            }
        }
        
        imageCount = self.imageSourceArray.count;
        
        for (NSUInteger imageIndex = 0; imageIndex < imageCount; ++imageIndex) {
            NSMutableDictionary *imageProperties = nil;
            if (imageIndex < _imagesProperties.count)
                imageProperties = [_imagesProperties objectAtIndex:imageIndex];
            
            if (imageProperties.count) {
                totalDuration += [[imageProperties valueForKey:@"_duration"] doubleValue];
            } else {
                NSMutableDictionary *sourceProperties = [((__bridge_transfer NSDictionary *)(CGImageSourceCopyPropertiesAtIndex(imageSource, imageIndex, NULL))) mutableCopy];
                
                if (sourceProperties) {
                    NSDictionary *formatProperties = nil;
                    
                    if (CGImageSourceContainsAnimatedPng(imageSource))
                        formatProperties = [sourceProperties objectForKey:(NSString *)kCGImagePropertyPNGDictionary];
                    else
                        formatProperties = [sourceProperties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
                    
                    if (formatProperties) {
                        [sourceProperties addEntriesFromDictionary:formatProperties];
                        
                        id unclampedDelayTime = nil;
                        id delayTime = nil;
                        
                        if (CGImageSourceContainsAnimatedPng(imageSource)) {
                            unclampedDelayTime = [formatProperties objectForKey:(__bridge NSString *)kCGImagePropertyAPNGUnclampedDelayTime];
                            delayTime = [formatProperties objectForKey:(__bridge NSString *)kCGImagePropertyAPNGDelayTime];
                        } else {
                            unclampedDelayTime = [formatProperties objectForKey:(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime];
                            delayTime = [formatProperties objectForKey:(__bridge NSString *)kCGImagePropertyGIFDelayTime];
                        }
                        
                        NSTimeInterval frameDuration = [unclampedDelayTime doubleValue];
                        if (frameDuration <= DBL_EPSILON)
                            frameDuration = [delayTime doubleValue];
                        
                        #ifndef OLExactDelayRepresentation
                            //Implement as Browsers do.
                            //See:  http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility
                            //Also: http://blogs.msdn.com/b/ieinternals/archive/2010/06/08/animated-gifs-slow-down-to-under-20-frames-per-second.aspx
                            if (!(frameDuration >= 0.02 - DBL_EPSILON))
                                frameDuration = 0.1;
                        #endif
                        
                        [sourceProperties setValue:@(imageIndex) forKey:@"_index"];
                        [sourceProperties setValue:@(frameDuration) forKey:@"_duration"];
                        [sourceProperties setValue:@(self.scale) forKey:@"_scale"];
                        [imageProperties addEntriesFromDictionary:sourceProperties];
                        
                        _frameDurations[imageIndex] = frameDuration;
                        totalDuration += frameDuration;
                    }
                }
            }
        }
        
        _totalDuration = totalDuration;
    }
}

@end

@implementation OLImage (IncrementalData)

//Snippet from AFNetworking
CGImageRef OLCreateDecodedCGImageFromCGImage(CGImageRef imageRef, NSDictionary *imageProperties) {
    CGSize imageSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
    CGRect imageRect = (CGRect) {.origin = CGPointZero, .size = imageSize};
    
    NSUInteger imageSizeBytes = imageSize.width * imageSize.height * (CGImageGetBitsPerPixel(imageRef) / 8);
    if (imageSizeBytes >= 33554432)
        return imageRef;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);
    
    int infoMask = (bitmapInfo & kCGBitmapAlphaInfoMask);
    BOOL anyNonAlpha = (infoMask == kCGImageAlphaNone ||
                        infoMask == kCGImageAlphaNoneSkipFirst ||
                        infoMask == kCGImageAlphaNoneSkipLast);
    
    // CGBitmapContextCreate doesn't support kCGImageAlphaNone with RGB.
    // https://developer.apple.com/library/mac/#qa/qa1037/_index.html
    if (infoMask == kCGImageAlphaNone && CGColorSpaceGetNumberOfComponents(colorSpace) > 1) {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
        
        // Set noneSkipFirst.
        bitmapInfo |= kCGImageAlphaNoneSkipFirst;
    }
    // Some PNGs tell us they have alpha but only 3 components. Odd.
    else if (!anyNonAlpha && CGColorSpaceGetNumberOfComponents(colorSpace) == 3) {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
        bitmapInfo |= kCGImageAlphaPremultipliedFirst;
    }
    
    // It calculates the bytes-per-row based on the bitsPerComponent and width arguments.
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 imageSize.width,
                                                 imageSize.height,
                                                 CGImageGetBitsPerComponent(imageRef),
                                                 0,
                                                 colorSpace,
                                                 bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    
    // If failed, return undecompressed image
    if (!context) return imageRef;
    
    CGContextDrawImage(context, imageRect, imageRef);
    
    CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
    
    CGContextRelease(context);
    
    return decompressedImageRef;
}

+ (instancetype)imageWithIncrementalData:(NSData *)data {
    return [OLImage imageWithIncrementalData:data scale:1.0f];
}

+ (instancetype)imageWithIncrementalData:(NSData *)data scale:(CGFloat)scale {
    CGImageSourceRef incrementalSource = CGImageSourceCreateIncremental(NULL);
    
    OLImage *image = [[OLImage alloc] initWithImageSource:incrementalSource imageData:(__bridge CFDataRef)data scale:scale asIncremental:YES asFinal:NO];
    
    if (incrementalSource) {
        CFRelease(incrementalSource); incrementalSource = NULL;
    }
    
    return image;
}

- (void)updateWithData:(NSData *)data {
    [self updateWithData:data final:NO];
}

- (void)updateWithData:(NSData *)data final:(BOOL)final {
    if (![self isPartial] || !data.length)
        return;
    
    [_imageSourceArray.mutexLock lock];
    
    CFDataRef incrementalData = CFDataCreateCopy(kCFAllocatorDefault, (__bridge CFDataRef)data);
    
    CGImageSourceUpdateData(_incrementalSource, incrementalData, final);
    
    if (_incrementalData)
        CFRelease(_incrementalData);
    _incrementalData = incrementalData;
    
    [self.imageSourceArray setImageData:incrementalData];
    
    [self updateGlobalProperties];
    [self updateImagesProperties];
    [self.imageSourceArray updateCount];
    
    if (final) {
        if (_incrementalSource) {
            CFRelease(_incrementalSource); _incrementalSource = NULL;
        }
        if (_incrementalData) {
            CFRelease(_incrementalData); _incrementalData = NULL;
        }
    }
    
    [_imageSourceArray.mutexLock unlock];
}

- (BOOL)isPartial {
    return _incrementalSource != NULL;
}

- (BOOL)isReady {
    return [self.imageSourceArray count] && _globalProperties && _frameDurations;
}

@end

@implementation UIImage (IncrementalData)

- (BOOL)isReady {
    return YES;
}

@end

@interface OLImageSourceArray ()

@property (nonatomic, readonly) NSString *cacheReference;
@property (nonatomic, readonly) NSCache *frameCache;

@end

@implementation OLImageSourceArray

+ (instancetype)arrayWithImageSource:(CGImageSourceRef)imageSource imageData:(CFDataRef)imageData scale:(CGFloat)scale {
    if (!imageSource)
        return nil;
    
    return [[self alloc] initWithImageSource:imageSource imageData:imageData scale:scale];
}

- (instancetype)initWithImageSource:(CGImageSourceRef)imageSource imageData:(CFDataRef)imageData scale:(CGFloat)scale {
    if ((self = [super init])) {
        if (!imageSource)
            return self = nil;
        
        CFRetain(imageSource);
        _imageSource = imageSource;
        
        if (imageData) {
            CFRetain(imageData);
            _imageData = imageData;
        }
        
        _scale = scale;
        
        _mutexLock = [NSLock new];
        
        CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
        _cacheReference = (__bridge_transfer NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
        CFRelease(uuidRef);
    }
    
    return self;
}

- (void)dealloc {
    if (_imageSource) {
        CFRelease(_imageSource); _imageSource = NULL;
    }
    if (_imageData) {
        CFRelease(_imageData); _imageData = NULL;
    }
}

- (NSCache *)frameCache {
    return [SDImageCache sharedImageCache].memCache;
}

- (NSString *)cachePairKeyForIndex:(NSUInteger)idx {
    return [_cacheReference stringByAppendingFormat:@".%lu", (unsigned long)idx];
}

- (id)objectAtIndex:(NSUInteger)idx {
    [_mutexLock lock];
    
    id object = [self.frameCache objectForCachePairKey:[self cachePairKeyForIndex:idx]];
    
    if (!object)
        object = [self _objectAtIndex:idx];
    
    [_mutexLock unlock];
    
    return object;
}

- (BOOL)containsObject:(id)anObject {
    return [[(id)self.frameCache allObjects] containsObject:anObject];
}

- (id)_objectAtIndex:(NSUInteger)idx { // Already inside lock section
    __block UIImage *image = nil;
    
    if (idx < _count) {
        dispatch_sync_main_queue_safe(^{
            @try {
                CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(self.imageSource, idx, NULL);
                
                if (frameImageRef) {
                    if (!_hasComputedSize) {
                        _size = CGSizeMake(CGImageGetWidth(frameImageRef) / _scale, CGImageGetHeight(frameImageRef) / _scale);
                        _hasComputedSize = _size.width > FLT_EPSILON && _size.height > FLT_EPSILON;
                    }
                    
                    CGImageRef decodedImageRef = OLCreateDecodedCGImageFromCGImage(frameImageRef, [_imagesProperties objectAtIndex:idx]);
                    
                    CGImageRelease(frameImageRef);
                    
                    if (decodedImageRef) {
                        image = [[UIImage alloc] initWithCGImage:decodedImageRef scale:_scale orientation:UIImageOrientationUp];
                        
                        CGImageRelease(decodedImageRef);
                        
                        if (image) {
                            CGFloat cost = image.size.height * image.size.width * image.scale;
                            [self.frameCache setObject:image forCachePairKey:[self cachePairKeyForIndex:idx] cost:cost];
                        }
                    }
                }
            } @catch (NSException * __unused exception) { ; }
        });
    }
    
    return image;
}

- (NSUInteger)count {
    return _count;
}

- (void)updateCount {
    for (NSInteger frameIndex = 0; frameIndex < _count; ++frameIndex)
        [self.frameCache removeObjectForCachePairKey:[self cachePairKeyForIndex:frameIndex]];
    
    NSInteger count = CGImageSourceGetCount(self.imageSource);
    CGImageSourceStatus overallStatus = CGImageSourceGetStatus(self.imageSource);
    
    if (overallStatus == kCGImageStatusComplete) {
        _count = count;
    } else {
        for (NSInteger statusIndex = _count; statusIndex < count; ++statusIndex) {
            CGImageSourceStatus statusAtIndex = CGImageSourceGetStatusAtIndex(self.imageSource, statusIndex);
            
            if (statusAtIndex == kCGImageStatusComplete || (statusAtIndex == kCGImageStatusUnknownType && statusIndex < count - 2))
                _count = statusIndex;
            else
                break;
        }
    }
}

- (void)setImageData:(CFDataRef)imageData {
    if (imageData)
        CFRetain(imageData);
    if (_imageData)
        CFRelease(_imageData);
    _imageData = imageData;
}

- (CGSize)size {
    if (!_hasComputedSize && _count > 0) {
        [_mutexLock lock];
        
        id object = [self.frameCache objectForCachePairKey:[self cachePairKeyForIndex:0]];
        
        if (object)
            _size = [(UIImage *)object size];
        else {
            @try {
                CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(self.imageSource, 0, NULL);
                
                _size = CGSizeMake(CGImageGetWidth(frameImageRef) / _scale, CGImageGetHeight(frameImageRef) / _scale);
                
                CGImageRelease(frameImageRef);
            } @catch (NSException * __unused exception) { ; }
        }
        
        _hasComputedSize = _size.width > FLT_EPSILON && _size.height > FLT_EPSILON;
        
        [_mutexLock unlock];
    }
    
    return _size;
}

- (CGImageRef)CGImage {
    __block CGImageRef imageRef = NULL;
    
    if (_count > 0) {
        [_mutexLock lock];
        
        id object = [self.frameCache objectForCachePairKey:[self cachePairKeyForIndex:0]];
        
        if (object) {
            imageRef = [(UIImage *)object CGImage];
        } else {
            dispatch_sync_main_queue_safe(^{
                @try {
                    CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(self.imageSource, 0, NULL);
                    
                    if (frameImageRef) {
                        imageRef = OLCreateDecodedCGImageFromCGImage(frameImageRef, [_imagesProperties objectAtIndex:0]);
                        
                        CGImageRelease(frameImageRef);
                        
                        if (imageRef)
                            CFAutorelease(imageRef);
                    }
                } @catch (NSException * __unused exception) { ; }
            });
        }
        
        [_mutexLock unlock];
    }
    
    return imageRef;
}

@end
