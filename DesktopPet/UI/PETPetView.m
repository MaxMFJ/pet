#import "PETPetView.h"

#import <QuartzCore/QuartzCore.h>

#import "../Models/PETAnimationFrame.h"
#import "../Models/PETPetProfile.h"

@interface PETPetView ()

@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, copy, readwrite) NSString *currentState;
@property (nonatomic, copy) NSArray<PETAnimationFrame *> *currentFrames;
@property (nonatomic, assign) NSUInteger currentFrameIndex;
@property (nonatomic, assign) CFTimeInterval accumulatedFrameTime;
@property (nonatomic, assign) CFTimeInterval lastAnimationTickTimestamp;
@property (nonatomic, assign, getter=isAnimationActive) BOOL animationActive;
@property (nonatomic, assign) NSUInteger profilingFrameAdvanceCount;
@property (nonatomic, assign) NSUInteger profilingDrawCount;
@property (nonatomic, assign) NSUInteger profilingWindowEventCount;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *profilingWindowEventBreakdown;
@property (nonatomic, assign) CFTimeInterval profilingLastReportTimestamp;
@property (nonatomic, assign) NSPoint dragStartPoint;
@property (nonatomic, assign) BOOL didDragDuringMouseSession;
@property (nonatomic, assign) BOOL dragEligibleForCurrentMouseSession;

@end

@implementation PETPetView

static NSTimer *PETPetViewSharedDisplayTimer = nil;
static NSHashTable<PETPetView *> *PETPetViewRegisteredViews = nil;

static void PETPetViewRegisterForSharedAnimationTick(PETPetView *view) {
    if (view == nil) {
        return;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PETPetViewRegisteredViews = [NSHashTable weakObjectsHashTable];
    });

    [PETPetViewRegisteredViews addObject:view];
    if (PETPetViewSharedDisplayTimer != nil) {
        return;
    }

    PETPetViewSharedDisplayTimer = [NSTimer timerWithTimeInterval:(1.0 / 60.0)
                                                          repeats:YES
                                                            block:^(__unused NSTimer *timer) {
        NSArray<PETPetView *> *views = PETPetViewRegisteredViews.allObjects;
        BOOL hasActiveViews = NO;
        for (PETPetView *registeredView in views) {
            if (registeredView == nil || !registeredView.isAnimationActive) {
                continue;
            }
            hasActiveViews = YES;
            [registeredView handleSharedAnimationTick];
        }

        if (hasActiveViews) {
            return;
        }

        [PETPetViewSharedDisplayTimer invalidate];
        PETPetViewSharedDisplayTimer = nil;
    }];
    PETPetViewSharedDisplayTimer.tolerance = 1.0 / 120.0;
    [[NSRunLoop mainRunLoop] addTimer:PETPetViewSharedDisplayTimer forMode:NSRunLoopCommonModes];
}

static void PETPetViewUnregisterFromSharedAnimationTick(PETPetView *view) {
    if (view == nil || PETPetViewRegisteredViews == nil) {
        return;
    }
    [PETPetViewRegisteredViews removeObject:view];
    if (PETPetViewRegisteredViews.allObjects.count > 0 || PETPetViewSharedDisplayTimer == nil) {
        return;
    }
    [PETPetViewSharedDisplayTimer invalidate];
    PETPetViewSharedDisplayTimer = nil;
}

static BOOL PETBitmapRepHasVisibleAlphaAtPoint(NSBitmapImageRep *bitmap, NSInteger pixelX, NSInteger pixelY) {
    if (bitmap == nil) {
        return NO;
    }
    if (pixelX < 0 || pixelY < 0 || pixelX >= bitmap.pixelsWide || pixelY >= bitmap.pixelsHigh) {
        return NO;
    }

    NSColor *color = [bitmap colorAtX:pixelX y:pixelY];
    return color != nil && color.alphaComponent > (12.0 / 255.0);
}

static BOOL PETImageHasVisibleAlphaAtPoint(NSImage *image, NSPoint imagePoint) {
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cgImage == NULL) {
        return NO;
    }

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) {
        return NO;
    }

    NSInteger pixelX = (NSInteger)floor(imagePoint.x);
    NSInteger pixelY = (NSInteger)floor(imagePoint.y);
    if (pixelX < 0 || pixelY < 0 || pixelX >= (NSInteger)width || pixelY >= (NSInteger)height) {
        return NO;
    }

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    if (bitmap == nil) {
        return NO;
    }

    if (PETBitmapRepHasVisibleAlphaAtPoint(bitmap, pixelX, pixelY)) {
        return YES;
    }

    NSInteger flippedY = (NSInteger)height - 1 - pixelY;
    return PETBitmapRepHasVisibleAlphaAtPoint(bitmap, pixelX, flippedY);
}

static CGRect PETVisibleAlphaBoundsForImage(NSImage *image) {
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cgImage == NULL) {
        return CGRectZero;
    }

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    if (bitmap == nil) {
        return CGRectZero;
    }

    NSInteger minX = bitmap.pixelsWide;
    NSInteger minY = bitmap.pixelsHigh;
    NSInteger maxX = -1;
    NSInteger maxY = -1;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y += 1) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x += 1) {
            if (!PETBitmapRepHasVisibleAlphaAtPoint(bitmap, x, y)) {
                continue;
            }
            minX = MIN(minX, x);
            minY = MIN(minY, y);
            maxX = MAX(maxX, x);
            maxY = MAX(maxY, y);
        }
    }

    if (maxX < minX || maxY < minY) {
        return CGRectZero;
    }
    return CGRectMake(minX, minY, (maxX - minX) + 1.0, (maxY - minY) + 1.0);
}

- (instancetype)initWithProfile:(PETPetProfile *)profile {
    self = [super initWithFrame:NSMakeRect(0, 0, profile.canvasSize.width, profile.canvasSize.height)];
    if (self) {
        _profile = profile;
        _currentState = [profile.defaultState copy];
        _currentFrames = [profile framesForState:_currentState];
        _facingRight = YES;
        _profilingWindowEventBreakdown = [NSMutableDictionary dictionary];
        self.wantsLayer = YES;
    }
    return self;
}

- (void)dealloc {
    [self pauseAnimation];
}

- (BOOL)isFlipped {
    return YES;
}

- (nullable NSView *)hitTest:(NSPoint)point {
    if (![self containsInteractiveContentAtPoint:point]) {
        return nil;
    }
    return [super hitTest:point];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    self.profilingDrawCount += 1;
    [self maybeEmitProfilingReport];
    [[NSColor clearColor] setFill];
    NSRectFill(dirtyRect);

    if (self.currentFrames.count == 0) {
        return;
    }

    PETAnimationFrame *frame = self.currentFrames[self.currentFrameIndex];
    if (self.facingRight) {
        [frame.image drawInRect:self.bounds];
        return;
    }

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSWidth(self.bounds) yBy:0.0];
    [transform scaleXBy:-1.0 yBy:1.0];
    [transform concat];
    [frame.image drawInRect:self.bounds];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)startAnimating {
    [self restartAnimationTick];
}

- (void)playState:(NSString *)state {
    NSArray<PETAnimationFrame *> *frames = [self.profile framesForState:state];
    if (frames.count == 0) {
        return;
    }

    BOOL stateChanged = ![self.currentState isEqualToString:state] || self.currentFrames != frames;
    self.currentState = [state copy];
    self.currentFrames = frames;
    if (stateChanged || self.currentFrameIndex >= frames.count) {
        self.currentFrameIndex = 0;
        self.accumulatedFrameTime = 0.0;
    }
    [self restartAnimationTick];
    [self setNeedsDisplay:YES];
}

- (void)pauseAnimation {
    self.animationActive = NO;
    self.lastAnimationTickTimestamp = 0.0;
    PETPetViewUnregisterFromSharedAnimationTick(self);
}

- (void)resumeDefaultAnimation {
    [self playState:self.profile.defaultState];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragStartPoint = event.locationInWindow;
    self.didDragDuringMouseSession = NO;
    NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];
    self.dragEligibleForCurrentMouseSession = [self containsDraggableContentAtPoint:localPoint];
    if (self.dragStateChangeHandler != nil) {
        self.dragStateChangeHandler(NO);
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSWindow *window = self.window;
    if (window == nil || !self.dragEligibleForCurrentMouseSession) {
        return;
    }

    NSPoint currentPoint = event.locationInWindow;
    NSPoint origin = window.frame.origin;
    CGFloat deltaX = currentPoint.x - self.dragStartPoint.x;
    origin.x += deltaX;
    origin.y += currentPoint.y - self.dragStartPoint.y;
    [window setFrameOrigin:origin];
    self.didDragDuringMouseSession = YES;
    if (self.dragStateChangeHandler != nil) {
        self.dragStateChangeHandler(YES);
    }
    if (self.dragMovementHandler != nil) {
        self.dragMovementHandler(deltaX);
    }
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (!self.didDragDuringMouseSession && self.interactionHandler != nil) {
        self.interactionHandler();
    }
    if (self.dragStateChangeHandler != nil) {
        self.dragStateChangeHandler(NO);
    }
}

- (void)rightMouseUp:(NSEvent *)event {
    (void)event;
    if (self.secondaryInteractionHandler != nil) {
        self.secondaryInteractionHandler();
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;

    if (!self.profile.usesCodexSpriteAtlas) {
        return nil;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Pet Actions"];
    NSArray<NSString *> *preferredStates = @[@"idle", @"waving", @"waiting", @"review", @"jumping", @"failed"];
    for (NSString *state in preferredStates) {
        if (![self.profile.supportedStates containsObject:state]) {
            continue;
        }

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self titleForState:state]
                                                      action:@selector(handleMenuAction:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = state;
        [menu addItem:item];
    }
    return menu;
}

- (void)handleMenuAction:(NSMenuItem *)sender {
    NSString *state = [sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : nil;
    if (state.length == 0) {
        return;
    }
    if (self.menuActionHandler != nil) {
        self.menuActionHandler(state);
    }
}

- (void)restartAnimationTick {
    if (self.currentFrames.count == 0) {
        [self pauseAnimation];
        return;
    }
    self.animationActive = YES;
    self.lastAnimationTickTimestamp = 0.0;
    PETPetViewRegisterForSharedAnimationTick(self);
}

- (void)handleSharedAnimationTick {
    if (!self.isAnimationActive || self.currentFrames.count == 0) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (self.lastAnimationTickTimestamp <= 0.0) {
        self.lastAnimationTickTimestamp = now;
        return;
    }

    CFTimeInterval deltaTime = MAX(0.0, now - self.lastAnimationTickTimestamp);
    self.lastAnimationTickTimestamp = now;
    self.accumulatedFrameTime += deltaTime;

    BOOL didAdvanceFrame = NO;
    NSUInteger safetyCounter = 0;
    while (self.currentFrames.count > 0 && safetyCounter < self.currentFrames.count) {
        PETAnimationFrame *frame = self.currentFrames[self.currentFrameIndex];
        NSTimeInterval frameDuration = MAX(frame.duration, 0.02);
        if (self.accumulatedFrameTime + 0.0001 < frameDuration) {
            break;
        }
        self.accumulatedFrameTime -= frameDuration;
        self.currentFrameIndex = (self.currentFrameIndex + 1) % self.currentFrames.count;
        didAdvanceFrame = YES;
        safetyCounter += 1;
    }

    if (didAdvanceFrame) {
        self.profilingFrameAdvanceCount += 1;
        [self setNeedsDisplay:YES];
    }
    [self maybeEmitProfilingReport];
}

- (void)recordProfilingWindowEventWithName:(NSString *)eventName {
    NSString *resolvedEventName = eventName.length > 0 ? eventName : @"unknown";
    self.profilingWindowEventCount += 1;
    NSUInteger existingCount = [self.profilingWindowEventBreakdown[resolvedEventName] unsignedIntegerValue];
    self.profilingWindowEventBreakdown[resolvedEventName] = @(existingCount + 1);
    [self maybeEmitProfilingReport];
}

- (void)maybeEmitProfilingReport {
    CFTimeInterval now = CACurrentMediaTime();
    if (self.profilingLastReportTimestamp <= 0.0) {
        self.profilingLastReportTimestamp = now;
        return;
    }

    CFTimeInterval interval = now - self.profilingLastReportTimestamp;
    if (interval < 1.0) {
        return;
    }

    NSMutableArray<NSString *> *eventParts = [NSMutableArray array];
    NSArray<NSString *> *sortedKeys = [[self.profilingWindowEventBreakdown allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *key in sortedKeys) {
        [eventParts addObject:[NSString stringWithFormat:@"%@=%lu", key, (unsigned long)[self.profilingWindowEventBreakdown[key] unsignedIntegerValue]]];
    }

    NSLog(@"[DesktopPet][PETPetViewProfile] pet=%@ name=%@ state=%@ interval=%.2fs frameAdvances=%lu draws=%lu windowEvents=%lu breakdown={%@}",
          self.profile.identifier ?: @"",
          self.profile.displayName ?: @"",
          self.currentState ?: @"",
          interval,
          (unsigned long)self.profilingFrameAdvanceCount,
          (unsigned long)self.profilingDrawCount,
          (unsigned long)self.profilingWindowEventCount,
          [eventParts componentsJoinedByString:@", "]);

    self.profilingLastReportTimestamp = now;
    self.profilingFrameAdvanceCount = 0;
    self.profilingDrawCount = 0;
    self.profilingWindowEventCount = 0;
    [self.profilingWindowEventBreakdown removeAllObjects];
}

- (NSString *)titleForState:(NSString *)state {
    NSDictionary<NSString *, NSString *> *titles = @{
        @"idle": @"待机",
        @"waving": @"挥手",
        @"waiting": @"等待",
        @"review": @"审阅",
        @"jumping": @"跳跃",
        @"failed": @"失败",
        @"running": @"跑动",
        @"running-left": @"左跑",
        @"running-right": @"右跑"
    };
    return titles[state] ?: state.capitalizedString;
}

- (BOOL)containsInteractiveContentAtPoint:(NSPoint)point {
    return [self containsOpaqueRenderedContentAtPoint:point];
}

- (BOOL)containsOpaqueRenderedContentAtPoint:(NSPoint)point {
    if (!NSPointInRect(point, self.bounds) || self.currentFrames.count == 0) {
        return NO;
    }

    PETAnimationFrame *frame = self.currentFrames[self.currentFrameIndex];
    NSImage *image = frame.image;
    if (image == nil) {
        return NO;
    }

    NSSize imageSize = image.size;
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0 || self.bounds.size.width <= 0.0 || self.bounds.size.height <= 0.0) {
        return NO;
    }

    NSPoint samplePoint = point;
    if (!self.facingRight) {
        samplePoint.x = self.bounds.size.width - samplePoint.x;
    }

    CGFloat scaleX = imageSize.width / self.bounds.size.width;
    CGFloat scaleY = imageSize.height / self.bounds.size.height;
    NSPoint imagePoint = NSMakePoint(samplePoint.x * scaleX, samplePoint.y * scaleY);
    return PETImageHasVisibleAlphaAtPoint(image, imagePoint);
}

- (BOOL)containsDraggableContentAtPoint:(NSPoint)point {
    if (![self containsInteractiveContentAtPoint:point]) {
        return NO;
    }

    NSRect dragZone = NSInsetRect(self.bounds, self.bounds.size.width * 0.18, self.bounds.size.height * 0.14);
    return NSPointInRect(point, dragZone);
}

- (NSRect)visibleRenderedContentRect {
    if (self.currentFrames.count == 0 || self.bounds.size.width <= 0.0 || self.bounds.size.height <= 0.0) {
        return NSZeroRect;
    }

    PETAnimationFrame *frame = self.currentFrames[self.currentFrameIndex];
    NSImage *image = frame.image;
    if (image == nil || image.size.width <= 0.0 || image.size.height <= 0.0) {
        return NSZeroRect;
    }

    CGRect imageBounds = PETVisibleAlphaBoundsForImage(image);
    if (CGRectIsEmpty(imageBounds)) {
        return self.bounds;
    }

    CGFloat scaleX = self.bounds.size.width / image.size.width;
    CGFloat scaleY = self.bounds.size.height / image.size.height;
    CGFloat minX = CGRectGetMinX(imageBounds) * scaleX;
    CGFloat maxX = CGRectGetMaxX(imageBounds) * scaleX;
    CGFloat minY = CGRectGetMinY(imageBounds) * scaleY;
    CGFloat maxY = CGRectGetMaxY(imageBounds) * scaleY;

    if (!self.facingRight) {
        CGFloat flippedMinX = self.bounds.size.width - maxX;
        CGFloat flippedMaxX = self.bounds.size.width - minX;
        minX = flippedMinX;
        maxX = flippedMaxX;
    }

    return NSIntersectionRect(NSMakeRect(minX, minY, MAX(0.0, maxX - minX), MAX(0.0, maxY - minY)), self.bounds);
}

@end
