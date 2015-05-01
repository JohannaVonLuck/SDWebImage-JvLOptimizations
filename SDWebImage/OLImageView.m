//
//  OLImageView.m
//  OLImageViewDemo
//
//  Created by Diego Torres on 9/5/12.
//  Copyright (c) 2012 Onda Labs. All rights reserved.
//

#import "OLImageView.h"
#import "OLImage.h"
#import <QuartzCore/QuartzCore.h>

@interface OLImageView ()

@property (nonatomic, strong) OLImage *animatedImage;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic) NSTimeInterval accumulator;
@property (nonatomic) NSUInteger currentFrameIndex;
@property (nonatomic) NSInteger loopCountdown;

@property (nonatomic, strong) UITapGestureRecognizer *playRecognizer;

@end

@implementation OLImageView

const NSTimeInterval kMaxTimeStep = 1; // note: To avoid spiral-o-death

@synthesize runLoopMode = _runLoopMode;
@synthesize displayLink = _displayLink;

- (id)init {
    if ((self = [super init])) {
        self = [self initCommon];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        self = [self initCommon];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self = [self initCommon];
    }
    return self;
}

- (id)initWithImage:(UIImage *)image {
    if ((self = [super initWithImage:image])) {
        self = [self initCommon];
    }
    return self;
}

- (id)initWithImage:(UIImage *)image highlightedImage:(UIImage *)highlightedImage {
    if ((self = [super initWithImage:image highlightedImage:highlightedImage])) {
        self = [self initCommon];
    }
    return self;
}

- (id)initCommon {
    self.currentFrameIndex = 0;
    self.loopCountdown = 0;
    self.accumulator = 0;
    _isAnimationBeyondFirstFrame = NO;
    
    return self;
}

- (CADisplayLink *)displayLink
{
    if (self.window && self.superview) {
        if (!_displayLink && self.animatedImage) {
            _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(changeKeyframe:)];
            [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:self.runLoopMode];
            _displayLink.paused = YES;
        }
    } else {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    return _displayLink;
}

- (NSString *)runLoopMode
{
    return _runLoopMode ?: NSRunLoopCommonModes; //NSDefaultRunLoopMode;
}

- (void)setRunLoopMode:(NSString *)runLoopMode
{
    if (runLoopMode != _runLoopMode) {
        BOOL wasAnimating = self.isAnimating;
        
        if (wasAnimating)
            [self stopAnimating];
        
        NSRunLoop *runloop = [NSRunLoop mainRunLoop];
        [self.displayLink removeFromRunLoop:runloop forMode:_runLoopMode];
        [self.displayLink addToRunLoop:runloop forMode:runLoopMode];
        
        _runLoopMode = runLoopMode;
        
        if (wasAnimating)
            [self startAnimating];
    }
}

- (void)setImage:(UIImage *)image
{
    if (image == self.image) {
        return;
    }
    
    if ([image isKindOfClass:[OLImage class]]) {
        if ([(OLImage *)image isReady]) {
            [self stopAnimating];
            
            self.currentFrameIndex = 0;
            self.loopCountdown = 0;
            self.accumulator = 0;
            _isAnimationBeyondFirstFrame = NO;
            
            [super setImage:nil];
            
            self.animatedImage = (OLImage *)image;
            
            [self startAnimating];
        }
    } else {
        [self stopAnimating];
        
        self.currentFrameIndex = 0;
        self.loopCountdown = 0;
        self.accumulator = 0;
        _isAnimationBeyondFirstFrame = NO;
        
        self.animatedImage = nil;
        
        [super setImage:image];
    }
    
    [self.layer setNeedsDisplay];
}

- (void)setAnimatedImage:(OLImage *)animatedImage
{
    _animatedImage = animatedImage;
    if (animatedImage == nil)
        self.layer.contents = nil;
}

- (BOOL)isAnimating
{
    return [super isAnimating] || (self.displayLink && !self.displayLink.isPaused);
}

- (void)stopAnimating
{
    if (!_animatedImage) {
        if (self.animationImages)
            [super stopAnimating];
        return;
    }
    
    self.displayLink.paused = YES;
}

- (void)startAnimating
{
    if (!_animatedImage) {
        if (self.animationImages)
            [super startAnimating];
        return;
    }
    
    if (self.isAnimating) {
        return;
    }
    
    if (!self.loopCountdown)
        self.loopCountdown = self.animatedImage.loopCount ?: NSIntegerMax;
    
    self.displayLink.paused = NO;
}

- (NSTimeInterval)timeOffset {
    NSTimeInterval timeOffset = 0;
    
    if (_animatedImage) {
        for (int frameIndex = 0; frameIndex < self.currentFrameIndex; ++frameIndex)
            timeOffset += self.animatedImage.frameDurations[frameIndex];
        timeOffset += self.accumulator;
    }
    
    return timeOffset;
}

- (void)setTimeOffset:(NSTimeInterval)timeOffset {
    if (_animatedImage) {
        self.currentFrameIndex = 0;
        self.accumulator = timeOffset;
        [self changeKeyframe:nil];
    }
}

- (void)changeKeyframe:(CADisplayLink *)displayLink {
    if (_animatedImage) {
        if (_currentFrameIndex >= [_animatedImage.images count]) {
            if ([_animatedImage isPartial])
                return;
            else {
                if (--self.loopCountdown <= 0) {
                    self.currentFrameIndex = 0;
                    [self stopAnimating];
                    return;
                }
                self.currentFrameIndex = 0;
            }
        }
        
        if (!self.isHalted)
            self.accumulator += fmin(displayLink.duration, kMaxTimeStep);
        
        while (self.currentFrameIndex < [self.animatedImage.images count] &&
               self.accumulator >= self.animatedImage.frameDurations[self.currentFrameIndex]) {
            self.accumulator -= self.animatedImage.frameDurations[self.currentFrameIndex];
            
            if (!_isAnimationBeyondFirstFrame && _onAnimationBeyondFirstFrameBlock)
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (_onAnimationBeyondFirstFrameBlock)
                        _onAnimationBeyondFirstFrameBlock(self);
                });
            _isAnimationBeyondFirstFrame = YES;
            
            if (++self.currentFrameIndex >= [self.animatedImage.images count] && ![self.animatedImage isPartial]) {
                self.currentFrameIndex = 0;
                
                if (--self.loopCountdown <= 0) {
                    [self stopAnimating];
                    return;
                }
                self.currentFrameIndex = 0;
            }
            
            [self.layer setNeedsDisplay];
        }
    }
}

- (void)displayLayer:(CALayer *)layer {
    UIImage *image = nil;
    
    if (_animatedImage) {
        if ([_animatedImage isReady])
            image = [_animatedImage.images objectAtIndex:MIN(self.currentFrameIndex, _animatedImage.images.count-1)];
    } else
        image = self.image;
    
    if (image) {
        CGImageRef imageRef = image.CGImage;
        
        if (imageRef) {
            CFRetain(imageRef);
            
            layer.contents = (__bridge_transfer id)imageRef;
            layer.contentsScale = image.scale;
        }
    }
}

- (BOOL)waitForFullLoad {
    if (_waitForFullLoad && (!_animatedImage || ![_animatedImage isPartial]))
        _waitForFullLoad = NO;
    return _waitForFullLoad;
}

- (void)setWaitForFullLoad:(BOOL)waitForFullLoad {
    if (waitForFullLoad) {
        if (!self.playRecognizer) {
            self.playRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedOverrideWaitForFullLoad:)];
            [self addGestureRecognizer:self.playRecognizer];
            self.userInteractionEnabled = YES;
        }
    } else {
        if (self.playRecognizer) {
            self.userInteractionEnabled = NO;
            [self removeGestureRecognizer:self.playRecognizer];
            self.playRecognizer = nil;
        }
    }
    
    _waitForFullLoad = waitForFullLoad;
}

- (BOOL)isHalted {
    BOOL isHalted = _halt;
    
    if (self.waitForFullLoad) {
        if (![_animatedImage isPartial])
            self.waitForFullLoad = NO;
        else
            isHalted = YES;
    }
    
    return isHalted;
}

- (IBAction)tappedOverrideWaitForFullLoad:(id)sender {
    self.waitForFullLoad = NO;
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window) {
        [self startAnimating];
    } else {
       dispatch_async(dispatch_get_main_queue(), ^{
           if (!self.window) {
               [self stopAnimating];
           }
       });
    }
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    if (self.superview) {
        //Has a superview, make sure it has a displayLink
        [self displayLink];
    } else {
        //Doesn't have superview, let's check later if we need to remove the displayLink
        dispatch_async(dispatch_get_main_queue(), ^{
            [self displayLink];
        });
    }
}

- (void)setHighlighted:(BOOL)highlighted
{
    if (!self.animatedImage) {
        [super setHighlighted:highlighted];
    }
}

- (UIImage *)image
{
    return self.animatedImage ?: [super image];
}

- (CGSize)sizeThatFits:(CGSize)size
{
    return self.image.size;
}

@end
