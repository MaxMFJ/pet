#import "PETHitboxOverlayView.h"

#import "PETSpineLayoutHelper.h"
#import "../../UI/PETSpineMetalView.h"

@interface PETHitboxOverlayView ()

@property (nonatomic, assign) NSInteger draggingHitboxIndex;
@property (nonatomic, assign) NSPoint dragStartPoint;

@end

@implementation PETHitboxOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = NO;
        _facingRight = YES;
        _activeHitboxes = @[];
        _draggingHitboxIndex = NSNotFound;
    }
    return self;
}

- (NSInteger)hitboxIndexAtPoint:(NSPoint)point {
    for (NSInteger index = 0; index < (NSInteger)self.activeHitboxes.count; index++) {
        NSDictionary *hitbox = self.activeHitboxes[(NSUInteger)index];
        NSPoint center = [self contentPointForHitbox:hitbox];
        CGFloat width = [hitbox[@"width"] respondsToSelector:@selector(doubleValue)] ? [hitbox[@"width"] doubleValue] : 80.0;
        CGFloat height = [hitbox[@"height"] respondsToSelector:@selector(doubleValue)] ? [hitbox[@"height"] doubleValue] : 40.0;
        NSRect rect = NSMakeRect(center.x - width * 0.5, center.y - height * 0.5, width, height);
        if (NSPointInRect(point, rect)) {
            return index;
        }
    }
    return NSNotFound;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.draggingHitboxIndex = [self hitboxIndexAtPoint:point];
    self.dragStartPoint = point;
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.draggingHitboxIndex == NSNotFound || self.onPayloadDragged == nil) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint delta = NSMakePoint(point.x - self.dragStartPoint.x, point.y - self.dragStartPoint.y);
    self.dragStartPoint = point;
    NSDictionary *payload = self.activeHitboxes[(NSUInteger)self.draggingHitboxIndex];
    NSDictionary *updated = [PETSpineLayoutHelper payloadByApplyingViewDelta:delta
                                                                     toPayload:payload
                                                                     spineView:self.spineView
                                                                   facingRight:self.facingRight
                                                                    offsetKeys:@[@"x", @"y"]];
    self.onPayloadDragged(updated);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    self.draggingHitboxIndex = NSNotFound;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSPoint)contentPointForHitbox:(NSDictionary<NSString *, id> *)hitbox {
    return [PETSpineLayoutHelper viewPointForPayload:hitbox spineView:self.spineView facingRight:self.facingRight];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    for (NSDictionary<NSString *, id> *hitbox in self.activeHitboxes) {
        NSPoint center = [self contentPointForHitbox:hitbox];
        NSString *shape = [hitbox[@"shape"] isKindOfClass:NSString.class] ? hitbox[@"shape"] : @"rect";
        [[NSColor colorWithCalibratedRed:1.0 green:0.2 blue:0.2 alpha:0.35] setFill];
        [[NSColor systemRedColor] setStroke];

        if ([shape isEqualToString:@"circle"]) {
            CGFloat radius = [hitbox[@"radius"] respondsToSelector:@selector(doubleValue)] ? [hitbox[@"radius"] doubleValue] : 30.0;
            NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0)];
            [path fill];
            [path stroke];
        } else {
            CGFloat width = [hitbox[@"width"] respondsToSelector:@selector(doubleValue)] ? [hitbox[@"width"] doubleValue] : 80.0;
            CGFloat height = [hitbox[@"height"] respondsToSelector:@selector(doubleValue)] ? [hitbox[@"height"] doubleValue] : 40.0;
            NSRect rect = NSMakeRect(center.x - width * 0.5, center.y - height * 0.5, width, height);
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:rect];
            [path fill];
            [path stroke];
        }
    }
}

@end
