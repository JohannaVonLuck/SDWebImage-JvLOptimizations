//
//  CAAnimation+Blocks.m
//  CAAnimationBlocks
//
//  Created by xissburg on 7/7/11.
//  Copyright 2011 xissburg. All rights reserved.
//

#import "CAAnimation+Blocks.h"

@interface CAAnimationDelegate : NSObject

@property (nonatomic, copy) void (^startBlock)(void);
@property (nonatomic, copy) void (^completionBlock)(BOOL);

- (void)animationDidStart:(CAAnimation *)anim;
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;

@end

@implementation CAAnimationDelegate

- (void)animationDidStart:(CAAnimation *)anim {
    if (self.startBlock) {
        self.startBlock();
    }
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag {
    if (self.completionBlock) {
        self.completionBlock(flag);
    }
}

@end

@implementation CAAnimation (BlocksAddition)

- (void)setCompletionBlock:(void (^)(BOOL))completionBlock {
    if ([self.delegate isKindOfClass:[CAAnimationDelegate class]]) {
        ((CAAnimationDelegate *)self.delegate).completionBlock = completionBlock;
    }
    else {
        CAAnimationDelegate *delegate = [[CAAnimationDelegate alloc] init];
        delegate.completionBlock = completionBlock;
        self.delegate = delegate;
    }
}

- (void (^)(BOOL))completionBlock {
    return [self.delegate isKindOfClass:[CAAnimationDelegate class]] ? ((CAAnimationDelegate *)self.delegate).completionBlock : nil;
}

- (void)setStartBlock:(void (^)(void))startBlock {
    if ([self.delegate isKindOfClass:[CAAnimationDelegate class]]) {
        ((CAAnimationDelegate *)self.delegate).startBlock = startBlock;
    }
    else {
        CAAnimationDelegate *delegate = [[CAAnimationDelegate alloc] init];
        delegate.startBlock = startBlock;
        self.delegate = delegate;
    }
}

- (void (^)(void))startBlock {
    return [self.delegate isKindOfClass:[CAAnimationDelegate class]] ? ((CAAnimationDelegate *)self.delegate).startBlock : nil;
}

@end
