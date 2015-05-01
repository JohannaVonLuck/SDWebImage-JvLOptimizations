//
//  UIImageView+SmoothTransition.h
//  SDWebImage-JvLOptimizations
//
//  Created by JohannaVL on 6/4/14.
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so.
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "SDWebImageCompat.h"
#import "SDWebImageManager.h"

@protocol SDWebImageSmoothTransitionOptionsDelegate <NSObject>
@optional

// Default: 0.15
- (CGFloat)smoothImageTransitionDurationForImageView:(UIImageView *)imageView toImage:(UIImage *)image;

// Default: kCAMediaTimingFunctionEaseInEaseOut
- (CAMediaTimingFunction *)smoothImageTransitionMediaTimingFunctionForImageView:(UIImageView *)imageView toImage:(UIImage *)image;

// Default: YES
- (BOOL)smoothImageTransitionShouldIgnoreHightlightedStatusForImageView:(UIImageView *)imageView toImage:(UIImage *)image;


// Default: 0.15
- (CGFloat)smoothHighlightedImageTransitionDurationForImageView:(UIImageView *)imageView toImage:(UIImage *)image;

// Default: kCAMediaTimingFunctionEaseInEaseOut
- (CAMediaTimingFunction *)smoothHighlightedImageTransitionMediaTimingFunctionForImageView:(UIImageView *)imageView toImage:(UIImage *)image;

@end

@interface UIImageView (SmoothImageTransition)

- (void)cancelSmoothImageTransitionAnimation;

- (void)setImageWithSmoothTransition:(UIImage *)image;

- (void)setImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration;

- (void)setImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration mediaTimingFunction:(CAMediaTimingFunction *)timingFunction;

- (void)setImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration mediaTimingFunction:(CAMediaTimingFunction *)timingFunction shouldIgnoreHighlightedStatus:(BOOL)ignoreHighlighted;

- (void)setImageWithSmoothTransition:(UIImage *)image optionsDelegate:(id<SDWebImageSmoothTransitionOptionsDelegate>)optionsDelegate;


- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image;

- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration;

- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration mediaTimingFunction:(CAMediaTimingFunction *)timingFunction;

- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image optionsDelegate:(id<SDWebImageSmoothTransitionOptionsDelegate>)optionsDelegate;

@end
