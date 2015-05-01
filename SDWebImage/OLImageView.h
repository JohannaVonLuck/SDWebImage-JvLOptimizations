//
//  OLImageView.h
//  OLImageViewDemo
//
//  Created by Diego Torres on 9/5/12.
//  Copyright (c) 2012 Onda Labs. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OLImageView;

typedef void (^OLImageViewSelfBlock)(OLImageView *imageView);

@interface OLImageView : UIImageView {
    BOOL _waitForFullLoad;
    BOOL _isAnimationBeyondFirstFrame;
}

/**
 The animation runloop mode.
 
 The default mode (NSDefaultRunLoopMode), causes the animation to pauses while it is contained in an actively scrolling `UIScrollView`. Use NSRunLoopCommonModes if you don't want this behavior.
 */
@property (nonatomic, copy) NSString *runLoopMode;

@property (nonatomic, readwrite) NSTimeInterval timeOffset;

@property (nonatomic, assign) BOOL waitForFullLoad;
@property (nonatomic, assign) BOOL halt;

@property (nonatomic, readonly) BOOL isHalted;
@property (nonatomic, readonly) BOOL isAnimationBeyondFirstFrame;

@property (nonatomic, copy) OLImageViewSelfBlock onAnimationBeyondFirstFrameBlock;

@end
