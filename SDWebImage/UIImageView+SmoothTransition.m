//
//  UIImageView+SmoothTransition.m
//  SDWebImage-JvLOptimizations
//
//  Created by JohannaVL on 6/4/14.
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so.
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "UIImageView+SmoothTransition.h"
#import "CAAnimation+Blocks.h"

@implementation UIImageView (SmoothImageTransition)

- (void)cancelSmoothImageTransitionAnimation {
    [self.layer removeAnimationForKey:@"animateContents"];
}

- (void)setImageWithSmoothTransition:(UIImage *)image {
    [self setImageWithSmoothTransition:image duration:0.15 mediaTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut] shouldIgnoreHighlightedStatus:YES];
}

- (void)setImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration {
    [self setImageWithSmoothTransition:image duration:duration mediaTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut] shouldIgnoreHighlightedStatus:YES];
}

- (void)setImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration mediaTimingFunction:(CAMediaTimingFunction *)timingFunction {
    [self setImageWithSmoothTransition:image duration:duration mediaTimingFunction:timingFunction shouldIgnoreHighlightedStatus:YES];
}

- (void)setImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration mediaTimingFunction:(CAMediaTimingFunction *)timingFunction shouldIgnoreHighlightedStatus:(BOOL)ignoreHighlighted {
    if (ignoreHighlighted || !self.isHighlighted) {
        if (self.window && self.image) {
            [self.layer removeAnimationForKey:@"animateContents"];
            
            CABasicAnimation *crossFade = [CABasicAnimation animationWithKeyPath:@"contents"];
            crossFade.duration = duration;
            crossFade.timingFunction = timingFunction;
            
            crossFade.fromValue = (__bridge id)(self.image.CGImage);
            crossFade.toValue = (__bridge id)(image.CGImage);
            
            crossFade.removedOnCompletion = YES;
            
            [self.layer addAnimation:crossFade forKey:@"animateContents"];
        }
        
        self.image = image;
    }
}

- (void)setImageWithSmoothTransition:(UIImage *)image optionsDelegate:(id<SDWebImageSmoothTransitionOptionsDelegate>)optionsDelegate {
    [self setImageWithSmoothTransition:image
                              duration:([optionsDelegate respondsToSelector:@selector(smoothImageTransitionDurationForImageView:toImage:)] ? [optionsDelegate smoothImageTransitionDurationForImageView:self toImage:image] : 0.15)
                   mediaTimingFunction:([optionsDelegate respondsToSelector:@selector(smoothImageTransitionMediaTimingFunctionForImageView:toImage:)] ? [optionsDelegate smoothImageTransitionMediaTimingFunctionForImageView:self toImage:image] : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut])
         shouldIgnoreHighlightedStatus:([optionsDelegate respondsToSelector:@selector(smoothImageTransitionShouldIgnoreHightlightedStatusForImageView:toImage:)] ? [optionsDelegate smoothImageTransitionShouldIgnoreHightlightedStatusForImageView:self toImage:image] : YES)];
}

- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image {
    [self setHighlightedImageWithSmoothTransition:image duration:0.15 mediaTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
}

- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration {
    [self setHighlightedImageWithSmoothTransition:image duration:duration mediaTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
}

- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image duration:(CGFloat)duration mediaTimingFunction:(CAMediaTimingFunction *)timingFunction {
    if (self.isHighlighted) {
        if (self.window && self.image) {
            [self.layer removeAnimationForKey:@"animateContents"];
            
            CABasicAnimation *crossFade = [CABasicAnimation animationWithKeyPath:@"contents"];
            crossFade.duration = duration;
            crossFade.timingFunction = timingFunction;
            
            crossFade.fromValue = (__bridge id)(self.highlightedImage.CGImage);
            crossFade.toValue = (__bridge id)(image.CGImage);
            
            crossFade.removedOnCompletion = YES;
            
            [self.layer addAnimation:crossFade forKey:@"animateContents"];
        }
        
        self.highlightedImage = image;
    }
}

- (void)setHighlightedImageWithSmoothTransition:(UIImage *)image optionsDelegate:(id<SDWebImageSmoothTransitionOptionsDelegate>)optionsDelegate {
    [self setHighlightedImageWithSmoothTransition:image
                                         duration:([optionsDelegate respondsToSelector:@selector(smoothHighlightedImageTransitionDurationForImageView:toImage:)] ? [optionsDelegate smoothHighlightedImageTransitionDurationForImageView:self toImage:image] : 0.15)
                              mediaTimingFunction:([optionsDelegate respondsToSelector:@selector(smoothImageTransitionMediaTimingFunctionForImageView:toImage:)] ? [optionsDelegate smoothImageTransitionMediaTimingFunctionForImageView:self toImage:image] : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut])];
}

@end
