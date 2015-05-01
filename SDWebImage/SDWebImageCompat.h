/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Jamie Pinkham
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <TargetConditionals.h>

#ifdef __OBJC_GC__
#error SDWebImage does not support Objective-C Garbage Collection
#endif

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_5_0
#error SDWebImage doesn't support Deployement Target version < 5.0
#endif

#if !TARGET_OS_IPHONE
#import <AppKit/AppKit.h>
#ifndef UIImage
#define UIImage NSImage
#endif
#ifndef UIImageView
#define UIImageView NSImageView
#endif
#else

#import <UIKit/UIKit.h>

#endif

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#ifndef NS_OPTIONS
#define NS_OPTIONS(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#if OS_OBJECT_USE_OBJC
    #undef SDDispatchQueueRelease
    #undef SDDispatchQueueSetterSementics
    #define SDDispatchQueueRelease(q)
    #define SDDispatchQueueSetterSementics strong
#else
#undef SDDispatchQueueRelease
#undef SDDispatchQueueSetterSementics
#define SDDispatchQueueRelease(q) (dispatch_release(q))
#define SDDispatchQueueSetterSementics assign
#endif

extern dispatch_queue_t dispatch_get_ht_shared_queue();

inline static void dispatch_async_main_queue(dispatch_block_t block) { dispatch_async(dispatch_get_main_queue(), block); }
inline static void dispatch_async_main_queue_after(double delayInSeconds, dispatch_block_t block) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block); }
inline static void dispatch_async_main_queue_ifnotmain(dispatch_block_t block) { if ([NSThread isMainThread]) block(); else dispatch_async(dispatch_get_main_queue(), block); }
inline static void dispatch_sync_main_queue_safe(dispatch_block_t block) { if ([NSThread isMainThread]) block(); else dispatch_sync(dispatch_get_main_queue(), block); }

extern void _HTLog(const char *file, int lineNumber, const char func[], NSString *format, ...);
extern void _HTNoEchoLog(const char *file, int lineNumber, const char func[], NSString *format, ...);

typedef NS_OPTIONS(NSUInteger, SDWebImageScaledOptions) {
    /**
     * By default, only images with @2x in their actual filename are considered @2x assets.
     * This setting treats the file as @2x regardless, and will appropriately set to scale=2
     * in cases which it is not already.
     */
    SDWebImageScaledLoadAsRetinaImage = 1 << 16,
};

extern UIImage *SDScaledImageForKey(NSString *key, UIImage *image);
extern UIImage *SDScaledImageForOptions(SDWebImageScaledOptions options, UIImage *image);
