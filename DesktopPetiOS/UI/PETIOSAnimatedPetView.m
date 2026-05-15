#import "PETIOSAnimatedPetView.h"

#import "PETIOSSpineMetalView.h"
#import "../../DesktopPet/Models/PETAnimationFrame.h"
#import "../../DesktopPet/Models/PETPetProfile.h"

@interface PETIOSAnimatedPetView () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong, nullable) PETIOSSpineMetalView *spineView;
@property (nonatomic, strong, nullable) PETPetProfile *profile;
@property (nonatomic, copy, readwrite) NSString *currentState;
@property (nonatomic, copy) NSArray<PETAnimationFrame *> *frames;
@property (nonatomic, strong, nullable) NSTimer *frameTimer;
@property (nonatomic, assign) NSUInteger frameIndex;
@property (nonatomic, assign, readwrite) CGFloat petScale;
@property (nonatomic, assign, readwrite) CGPoint petOffset;
@property (nonatomic, assign) CGPoint panStartOffset;
@property (nonatomic, assign) CGPoint panStartPoint;
@property (nonatomic, assign) BOOL panEligible;
@property (nonatomic, assign) BOOL didBeginDragSession;
@property (nonatomic, assign) BOOL tapFallbackTriggered;

@end

@implementation PETIOSAnimatedPetView

- (CGPoint)spinePointForViewPoint:(CGPoint)point {
    if (self.spineView == nil) {
        return point;
    }
    return [self convertPoint:point toView:self.spineView];
}

- (NSString *)resolvedDisplayStateForProfile:(PETPetProfile *)profile requestedState:(NSString *)state {
    if (profile == nil) {
        return @"idle";
    }
    if (state.length > 0 && [profile.supportedStates containsObject:state]) {
        return state;
    }

    NSString *behaviorResolvedState = [profile resolvedAnimationStateForBehaviorState:state];
    if (behaviorResolvedState.length > 0) {
        return behaviorResolvedState;
    }

    if (profile.defaultState.length > 0 && [profile.supportedStates containsObject:profile.defaultState]) {
        return profile.defaultState;
    }

    return profile.supportedStates.firstObject ?: state ?: @"idle";
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        _petScale = 1.0;
        _dragActivationThreshold = 6.0f;
        _frameRateCooldownDuration = 1.2;

        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_imageView];

        [NSLayoutConstraint activateConstraints:@[
            [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];

        UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tapRecognizer.delegate = self;
        [self addGestureRecognizer:tapRecognizer];

        UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        panRecognizer.maximumNumberOfTouches = 1;
        panRecognizer.delegate = self;
        [self addGestureRecognizer:panRecognizer];
        [tapRecognizer requireGestureRecognizerToFail:panRecognizer];

        [self updateImageTransformAnimated:NO];
    }
    return self;
}

- (void)dealloc {
    [self.frameTimer invalidate];
}

- (void)displayProfile:(PETPetProfile *)profile preferredState:(NSString *)state {
    self.profile = profile;
    if (profile == nil) {
        [self.frameTimer invalidate];
        self.frameTimer = nil;
        [self.spineView removeFromSuperview];
        self.spineView = nil;
        self.imageView.hidden = NO;
        self.imageView.image = nil;
        self.currentState = @"idle";
        self.frames = @[];
        self.frameIndex = 0;
        return;
    }

    if (profile.usesSpineRuntime) {
        [self displaySpineProfile:profile preferredState:state];
        return;
    }

    [self.spineView removeFromSuperview];
    self.spineView = nil;
    self.imageView.hidden = NO;

    NSString *resolvedState = [self resolvedDisplayStateForProfile:profile requestedState:(state.length > 0 ? state : profile.defaultState)];
    NSArray<PETAnimationFrame *> *resolvedFrames = [profile framesForState:resolvedState];
    if (resolvedFrames.count == 0) {
        resolvedState = profile.defaultState;
        resolvedFrames = [profile framesForState:resolvedState];
    }

    self.currentState = resolvedState ?: @"idle";
    self.frames = resolvedFrames ?: @[];
    self.frameIndex = 0;
    [self scheduleNextFrame];
}

- (void)displaySpineProfile:(PETPetProfile *)profile preferredState:(NSString *)state {
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    self.frames = @[];
    self.frameIndex = 0;
    self.imageView.hidden = YES;
    self.imageView.image = nil;

    BOOL didCreateNewSpineView = NO;
    if (self.spineView == nil || self.spineView.profile != profile) {
        [self.spineView removeFromSuperview];
        NSError *error = nil;
        PETIOSSpineMetalView *spineView = [[PETIOSSpineMetalView alloc] initWithProfile:profile error:&error];
        if (spineView == nil) {
            NSLog(@"[DesktopPet] Failed to create iOS Spine view: %@", error.localizedDescription ?: @"unknown error");
            self.currentState = @"idle";
            return;
        }
        spineView.translatesAutoresizingMaskIntoConstraints = NO;
        [self insertSubview:spineView belowSubview:self.imageView];
        [NSLayoutConstraint activateConstraints:@[
            [spineView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [spineView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [spineView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [spineView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
        self.spineView = spineView;
        self.spineView.frameRateCooldownDuration = self.frameRateCooldownDuration;
        didCreateNewSpineView = YES;
    }

    NSString *resolvedState = [self resolvedDisplayStateForProfile:profile requestedState:(state.length > 0 ? state : profile.defaultState)];
    if (didCreateNewSpineView || ![self.spineView.currentState isEqualToString:resolvedState]) {
        [self.spineView playState:resolvedState loop:YES];
    }
    [self.spineView startAnimating];
    self.currentState = self.spineView.currentState ?: resolvedState ?: @"idle";
    [self updateImageTransformAnimated:NO];
}

- (void)setPetScale:(CGFloat)petScale {
    _petScale = MIN(MAX(petScale, 0.6), 2.4);
    [self updateImageTransformAnimated:NO];
}

- (void)setPetOffset:(CGPoint)petOffset animated:(BOOL)animated {
    _petOffset = petOffset;
    [self updateImageTransformAnimated:animated];
}

- (void)setDragActivationThreshold:(CGFloat)dragActivationThreshold {
    _dragActivationThreshold = MIN(MAX(dragActivationThreshold, 2.0), 24.0);
}

- (void)setFrameRateCooldownDuration:(NSTimeInterval)frameRateCooldownDuration {
    _frameRateCooldownDuration = MAX(0.2, frameRateCooldownDuration);
    self.spineView.frameRateCooldownDuration = _frameRateCooldownDuration;
}

- (void)scheduleNextFrame {
    [self.frameTimer invalidate];
    self.frameTimer = nil;

    if (self.frames.count == 0) {
        self.imageView.image = nil;
        return;
    }

    PETAnimationFrame *frame = self.frames[self.frameIndex];
    self.imageView.image = frame.image;

    __weak typeof(self) weakSelf = self;
    self.frameTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(frame.duration, 0.04)
                                                      repeats:NO
                                                        block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        [weakSelf advanceFrame];
    }];
}

- (void)advanceFrame {
    if (self.frames.count == 0) {
        return;
    }

    self.frameIndex = (self.frameIndex + 1) % self.frames.count;
    [self scheduleNextFrame];
}

- (void)updateImageTransformAnimated:(BOOL)animated {
    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformTranslate(transform, self.petOffset.x, self.petOffset.y);
    transform = CGAffineTransformScale(transform, self.petScale, self.petScale);

    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            self.imageView.transform = transform;
            self.spineView.transform = transform;
        }];
        return;
    }
    self.imageView.transform = transform;
    self.spineView.transform = transform;
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) {
        return;
    }
    if (self.tapFallbackTriggered) {
        self.tapFallbackTriggered = NO;
        return;
    }
    CGPoint point = [recognizer locationInView:self];
    [self emitPrimaryTapAtViewPoint:point];
}

- (void)emitPrimaryTapAtViewPoint:(CGPoint)point {
    CGPoint spinePoint = [self spinePointForViewPoint:point];
    if (self.spineView != nil && ![self.spineView containsInteractiveContentAtPoint:spinePoint]) {
        return;
    }
    NSString *partIdentifier = self.spineView != nil ? [self.spineView interactivePartIdentifierAtPoint:spinePoint] : nil;
    [self.delegate animatedPetViewDidReceivePrimaryTap:self atPoint:point partIdentifier:partIdentifier];
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint translation = [recognizer translationInView:self];
    CGPoint velocity = [recognizer velocityInView:self];
    CGFloat movementDistance = hypot(translation.x, translation.y);

    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            self.panStartOffset = self.petOffset;
            CGPoint point = [recognizer locationInView:self];
            self.panStartPoint = point;
            self.didBeginDragSession = NO;
            self.tapFallbackTriggered = NO;
            CGPoint spinePoint = [self spinePointForViewPoint:point];
            self.panEligible = (self.spineView == nil) || [self.spineView containsDraggableContentAtPoint:spinePoint];
            if (!self.panEligible) {
                recognizer.enabled = NO;
                recognizer.enabled = YES;
                return;
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!self.panEligible) {
                return;
            }
            if (!self.didBeginDragSession) {
                if (movementDistance < self.dragActivationThreshold) {
                    return;
                }
                self.didBeginDragSession = YES;
                [self.spineView setInteractionBoosted:YES];
                [self.delegate animatedPetViewDidBeginDrag:self atPoint:self.panStartPoint];
            }
            CGPoint offset = CGPointMake(self.panStartOffset.x + translation.x, self.panStartOffset.y + translation.y);
            [self setPetOffset:offset animated:NO];
            [self.delegate animatedPetViewDidDrag:self translation:translation velocity:velocity];
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded: {
            [self.spineView setInteractionBoosted:NO];
            if (self.didBeginDragSession) {
                [self.delegate animatedPetViewDidEndDrag:self velocity:velocity];
            } else if (self.panEligible && recognizer.state == UIGestureRecognizerStateEnded && movementDistance < self.dragActivationThreshold) {
                self.tapFallbackTriggered = YES;
                [self emitPrimaryTapAtViewPoint:self.panStartPoint];
            }
            self.panEligible = NO;
            self.didBeginDragSession = NO;
            break;
        }
        default:
            break;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    (void)gestureRecognizer;
    return touch.view == self || touch.view == self.imageView;
}

@end
