/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageManager.h"

@class SDWebImagePrefetcher;
typedef void(^SDWebImagePrefetchStartedBlock)(NSNumber *batchIndex);
typedef void(^SDWebImagePrefetchProgressBlock)(NSURL *imageURL, BOOL success, NSUInteger finishedCount, NSUInteger skippedCount);
typedef void(^SDWebImagePrefetchCompletionBlock)(NSUInteger finishedCount, NSUInteger skippedCount);

@protocol SDWebImagePrefetcherDelegate <NSObject>

@optional

/**
 * Called when an image was prefetched.
 *
 * @param imagePrefetcher The current image prefetcher
 * @param imageURL The image url that was prefetched
 * @param batchIndex The batch index responsible for prefetch
 * @param finishedCount The total number of images that were prefetched
 * @param totalCount The total number of images that need to be prefetched
 */
- (void)imagePrefetcher:(SDWebImagePrefetcher *)imagePrefetcher didPrefetchURL:(NSURL *)imageURL forBatchIndex:(NSNumber *)batchIndex withFinishedCount:(NSUInteger)finishedCount skippedCount:(NSUInteger)totalCount;

/**
 * Called when an image was not prefetched due to error.
 *
 * @param imagePrefetcher The current image prefetcher
 * @param imageURL The image url that was not prefetched
 * @param error Error associated for failure (if available)
 * @param batchIndex The batch index responsible for prefetch
 * @param finishedCount The total number of images that were prefetched
 * @param totalCount The total number of images that need to be prefetched
 */
- (void)imagePrefetcher:(SDWebImagePrefetcher *)imagePrefetcher didFailPrefetchingURL:(NSURL *)imageURL error:(NSError *)error forBatchIndex:(NSNumber *)batchIndex withFinishedCount:(NSUInteger)finishedCount skippedCount:(NSUInteger)totalCount;

/**
 * Called when an image was not prefetched due to cancellation.
 *
 * @param imagePrefetcher The current image prefetcher
 * @param imageURL The image url that was not prefetched
 * @param batchIndex The batch index responsible for prefetch
 * @param finishedCount The total number of images that were prefetched
 * @param totalCount The total number of images that need to be prefetched
 */
- (void)imagePrefetcher:(SDWebImagePrefetcher *)imagePrefetcher didCancelPrefetchingURL:(NSURL *)imageURL forBatchIndex:(NSNumber *)batchIndex withFinishedCount:(NSUInteger)finishedCount skippedCount:(NSUInteger)totalCount;

/**
 * Called when images are done prefetching.
 * @param imagePrefetcher The current image prefetcher
 * @param batchIndex The batch index responsible for prefetch
 * @param totalCount The total number of images that need to be prefetched
 * @param skippedCount The total number of images that were skipped
 */
- (void)imagePrefetcher:(SDWebImagePrefetcher *)imagePrefetcher didFinishForBatchIndex:(NSNumber *)batchIndex withFinishedCount:(NSUInteger)finishedCount skippedCount:(NSUInteger)skippedCount;

/**
 * Called when remaining images have been canceled from prefetching.
 * @param imagePrefetcher The current image prefetcher
 * @param batchIndex The batch index responsible for prefetch
 * @param totalCount The total number of images that need to be prefetched
 * @param skippedCount The total number of images that were skipped
 */
- (void)imagePrefetcher:(SDWebImagePrefetcher *)imagePrefetcher didCancelForBatchIndex:(NSNumber *)batchIndex withFinishedCount:(NSUInteger)finishedCount skippedCount:(NSUInteger)skippedCount;

@end


/**
 * Prefetch some URLs in the cache for future use. Images are downloaded in low priority.
 */
@interface SDWebImagePrefetcher : NSObject

@property (nonatomic, readonly) NSUInteger prefetchURLsCount;

/**
 * SDWebImageOptions for prefetcher. Defaults to SDWebImageLowPriority.
 */
@property (nonatomic, assign) SDWebImageOptions options;

@property (weak, nonatomic) id <SDWebImagePrefetcherDelegate> delegate;

/**
 * Return the global image prefetcher instance.
 */
+ (SDWebImagePrefetcher *)sharedImagePrefetcher;

/**
 * Assign list of URLs to let SDWebImagePrefetcher to queue the prefetching,
 * currently one image is downloaded at a time,
 * and skips images for failed downloads and proceed to the next image in the list
 *
 * @param urls list of URLs to prefetch
 * @return batchIndex number to reference prefetch from.
 */
- (NSNumber *)prefetchURLs:(NSArray *)urls;
- (NSNumber *)prefetchURLs:(NSArray *)urls URLOptions:(NSArray *)urlOptions;

/**
 * Assign list of URLs to let SDWebImagePrefetcher to queue the prefetching,
 * currently one image is downloaded at a time,
 * and skips images for failed downloads and proceed to the next image in the list
 *
 * @param urls list of URLs to prefetch
 * @param progressBlock block to be called when progress updates
 * @param completionBlock block to be called when prefetching is completed
 * @return batchIndex number to reference prefetch from.
 */
- (NSNumber *)prefetchURLs:(NSArray *)urls progress:(SDWebImagePrefetchProgressBlock)progressBlock completed:(SDWebImagePrefetchCompletionBlock)completionBlock;
- (NSNumber *)prefetchURLs:(NSArray *)urls URLOptions:(NSArray *)urlOptions progress:(SDWebImagePrefetchProgressBlock)progressBlock completed:(SDWebImagePrefetchCompletionBlock)completionBlock;
- (NSNumber *)prefetchURLs:(NSArray *)urls URLOptions:(NSArray *)urlOptions started:(SDWebImagePrefetchStartedBlock)startedBlock progress:(SDWebImagePrefetchProgressBlock)progressBlock completed:(SDWebImagePrefetchCompletionBlock)completionBlock;

- (SDWebImageCombinedOperation *)operationForURL:(NSURL *)url;

/**
 * Remove and cancel queued list
 */
- (void)cancelAllPrefetching;
- (void)cancelPrefetchingForBatchIndex:(NSNumber *)batchIndex;


@end
