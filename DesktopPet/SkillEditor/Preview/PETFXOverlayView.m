#import "PETFXOverlayView.h"

#import "PETFXPreviewInstance.h"
#import "PETSpineLayoutHelper.h"
#import "../../UI/PETSpineMetalView.h"

@interface PETFXOverlayView ()

@property (nonatomic, assign) NSInteger draggingInstanceIndex;
@property (nonatomic, assign) NSPoint dragStartPoint;

@end

@implementation PETFXOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _facingRight = YES;
        _activeInstances = @[];
        _draggingInstanceIndex = NSNotFound;
    }
    return self;
}

- (NSInteger)instanceIndexAtPoint:(NSPoint)point {
    for (NSInteger index = 0; index < (NSInteger)self.activeInstances.count; index++) {
        PETFXPreviewInstance *instance = self.activeInstances[(NSUInteger)index];
        NSPoint center = [PETSpineLayoutHelper viewPointForPayload:instance.payload spineView:self.spineView facingRight:self.facingRight];
        NSRect rect = NSMakeRect(center.x - 36, center.y - 24, 72, 48);
        if (NSPointInRect(point, rect)) {
            return index;
        }
    }
    return NSNotFound;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.draggingInstanceIndex = [self instanceIndexAtPoint:point];
    self.dragStartPoint = point;
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.draggingInstanceIndex == NSNotFound || self.onPayloadDragged == nil) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint delta = NSMakePoint(point.x - self.dragStartPoint.x, point.y - self.dragStartPoint.y);
    self.dragStartPoint = point;
    PETFXPreviewInstance *instance = self.activeInstances[(NSUInteger)self.draggingInstanceIndex];
    NSDictionary *updated = [PETSpineLayoutHelper payloadByApplyingViewDelta:delta
                                                                     toPayload:instance.payload
                                                                     spineView:self.spineView
                                                                   facingRight:self.facingRight
                                                                    offsetKeys:@[@"offsetX", @"offsetY"]];
    self.onPayloadDragged(updated, instance);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    self.draggingInstanceIndex = NSNotFound;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.spineView == nil) {
        return;
    }

    for (PETFXPreviewInstance *instance in self.activeInstances) {
        NSDictionary *payload = instance.payload ?: @{};
        NSPoint center = [PETSpineLayoutHelper viewPointForPayload:payload
                                                         spineView:self.spineView
                                                       facingRight:self.facingRight];
        CGFloat scale = [payload[@"scale"] respondsToSelector:@selector(doubleValue)] ? [payload[@"scale"] doubleValue] : 1.0;
        if (scale <= 0.01) {
            scale = 1.0;
        }
        float rotation = [payload[@"rotation"] respondsToSelector:@selector(floatValue)] ? (float)[payload[@"rotation"] doubleValue] : 0.0f;
        NSString *blendMode = [payload[@"blendMode"] isKindOfClass:NSString.class] ? payload[@"blendMode"] : @"alpha";
        BOOL flipX = [payload[@"flipX"] boolValue];

        NSGraphicsContext *context = NSGraphicsContext.currentContext;
        [context saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:center.x yBy:center.y];
        [transform rotateByDegrees:rotation];
        if (flipX) {
            [transform scaleXBy:-1.0 yBy:1.0];
        }
        [transform concat];

        if (instance.currentFrame != nil) {
            NSSize imageSize = instance.currentFrame.size;
            NSRect drawRect = NSMakeRect(-imageSize.width * 0.5 * scale,
                                         -imageSize.height * 0.5 * scale,
                                         imageSize.width * scale,
                                         imageSize.height * scale);
            if ([blendMode isEqualToString:@"additive"]) {
                [context setCompositingOperation:NSCompositingOperationPlusLighter];
            } else if ([blendMode isEqualToString:@"multiply"]) {
                [context setCompositingOperation:NSCompositingOperationMultiply];
            }
            [instance.currentFrame drawInRect:drawRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.92 respectFlipped:YES hints:nil];
        } else {
            NSString *label = [payload[@"asset"] isKindOfClass:NSString.class] ? payload[@"asset"] : @"fx";
            CGFloat width = 72.0 * scale;
            CGFloat height = 48.0 * scale;
            NSColor *fill = [[NSColor systemOrangeColor] colorWithAlphaComponent:0.45];
            [fill setFill];
            NSBezierPath *diamond = [NSBezierPath bezierPath];
            [diamond moveToPoint:NSMakePoint(0, height * 0.5)];
            [diamond lineToPoint:NSMakePoint(width * 0.5, 0)];
            [diamond lineToPoint:NSMakePoint(0, -height * 0.5)];
            [diamond lineToPoint:NSMakePoint(-width * 0.5, 0)];
            [diamond closePath];
            [diamond fill];
            [[NSColor systemOrangeColor] setStroke];
            [diamond stroke];
            NSDictionary *attrs = @{
                NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
                NSForegroundColorAttributeName: NSColor.whiteColor
            };
            NSSize textSize = [label sizeWithAttributes:attrs];
            [label drawAtPoint:NSMakePoint(-textSize.width * 0.5, -textSize.height * 0.5) withAttributes:attrs];
        }
        [context restoreGraphicsState];
    }
}

@end
