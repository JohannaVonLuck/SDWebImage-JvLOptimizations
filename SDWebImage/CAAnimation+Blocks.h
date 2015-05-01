//
//  CAAnimation+Blocks.h
//  CAAnimationBlocks
//
//  Created by xissburg on 7/7/11.
//  Copyright 2011 xissburg. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

@interface CAAnimation (BlocksAddition)

@property (nonatomic, copy) void (^startBlock)(void);
@property (nonatomic, copy) void (^completionBlock)(BOOL finished);

- (void)setStartBlock:(void (^)(void))startBlock;
- (void)setCompletionBlock:(void (^)(BOOL finished))completionBlock;

@end
