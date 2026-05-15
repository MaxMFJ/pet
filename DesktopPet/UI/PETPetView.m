#import "PETPetView.h"

#import "../Models/PETAnimationFrame.h"
#import "../Models/PETPetProfile.h"

@interface PETPetView ()

@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, copy, readwrite) NSString *currentState;
@property (nonatomic, copy) NSArray<PETAnimationFrame *> *currentFrames;
@property (nonatomic, assign) NSUInteger currentFrameIndex;
@property (nonatomic, strong, nullable) NSTimer *frameTimer;
@property (nonatomic, assign) NSPoint dragStartPoint;
@property (nonatomic, assign) BOOL didDragDuringMouseSession;
@property (nonatomic, assign) BOOL dragEligibleForCurrentMouseSession;

@end

@implementation PETPetView

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

- (instancetype)initWithProfile:(PETPetProfile *)profile {
    self = [super initWithFrame:NSMakeRect(0, 0, profile.canvasSize.width, profile.canvasSize.height)];
    if (self) {
        _profile = profile;
        _currentState = [profile.defaultState copy];
        _currentFrames = [profile framesForState:_currentState];
        _facingRight = YES;
        self.wantsLayer = YES;
    }
    return self;
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
    [self scheduleNextFrame];
}

- (void)playState:(NSString *)state {
    NSArray<PETAnimationFrame *> *frames = [self.profile framesForState:state];
    if (frames.count == 0) {
        return;
    }

    self.currentState = [state copy];
    self.currentFrames = frames;
    self.currentFrameIndex = 0;
    [self scheduleNextFrame];
}

- (void)pauseAnimation {
    [self.frameTimer invalidate];
    self.frameTimer = nil;
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

- (void)scheduleNextFrame {
    [self.frameTimer invalidate];

    if (self.currentFrames.count == 0) {
        return;
    }

    PETAnimationFrame *frame = self.currentFrames[self.currentFrameIndex];
    __weak typeof(self) weakSelf = self;
    self.frameTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(frame.duration, 0.02)
                                                      repeats:NO
                                                        block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        [weakSelf advanceFrame];
    }];
    [self setNeedsDisplay:YES];
}

- (void)advanceFrame {
    if (self.currentFrames.count == 0) {
        return;
    }

    self.currentFrameIndex = (self.currentFrameIndex + 1) % self.currentFrames.count;
    [self scheduleNextFrame];
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

@end
