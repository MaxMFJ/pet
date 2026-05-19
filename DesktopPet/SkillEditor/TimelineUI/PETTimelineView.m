#import "PETTimelineView.h"

#import "../Model/PETSkillTimelineDocument.h"
#import "../Model/PETSkillTimelineEnums.h"
#import "PETTimelineLayoutEngine.h"

typedef NS_ENUM(NSInteger, PETTimelineDragMode) {
    PETTimelineDragModeNone = 0,
    PETTimelineDragModeMoveClip,
    PETTimelineDragModeResizeStart,
    PETTimelineDragModeResizeEnd,
    PETTimelineDragModeScrubPlayhead,
};

static const CGFloat PETTimelineResizeHandleWidth = 8.0;

@interface PETTimelineView ()

@property (nonatomic, strong) PETTimelineLayoutMetrics *layoutMetrics;
@property (nonatomic, strong) PETTimelineLayoutEngine *layoutEngine;
@property (nonatomic, assign) PETTimelineDragMode dragMode;
@property (nonatomic, strong, nullable) PETSkillTimelineClip *draggingClip;
@property (nonatomic, assign) NSTimeInterval dragAnchorTime;
@property (nonatomic, assign) NSTimeInterval dragOriginalStart;
@property (nonatomic, assign) NSTimeInterval dragOriginalEnd;

@end

@implementation PETTimelineView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _layoutMetrics = [PETTimelineLayoutMetrics defaultMetrics];
        _layoutEngine = [[PETTimelineLayoutEngine alloc] init];
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setDocument:(PETSkillTimelineDocument *)document {
    _document = document;
    [self reloadData];
}

- (void)reloadData {
    [self setNeedsDisplay:YES];
}

- (NSColor *)colorForTrackType:(PETSkillTimelineTrackType)trackType {
    switch (trackType) {
        case PETSkillTimelineTrackTypeFX:
            return NSColor.systemOrangeColor;
        case PETSkillTimelineTrackTypeHitbox:
            return NSColor.systemRedColor;
        case PETSkillTimelineTrackTypeShader:
            return NSColor.systemPurpleColor;
        case PETSkillTimelineTrackTypeEvent:
            return NSColor.systemGreenColor;
        case PETSkillTimelineTrackTypeCharacter:
        default:
            return NSColor.systemBlueColor;
    }
}

- (CGRect)frameForClip:(PETSkillTimelineClip *)clip rowIndex:(NSInteger)rowIndex {
    return [self.layoutEngine frameForClip:clip
                                  rowIndex:rowIndex
                                   metrics:self.layoutMetrics
                              contentWidth:self.bounds.size.width
                             contentHeight:self.bounds.size.height];
}

- (NSInteger)rowIndexForClip:(PETSkillTimelineClip *)clip {
    NSInteger row = 0;
    for (PETSkillTimelineTrack *track in self.document.tracks) {
        for (PETSkillTimelineClip *candidate in track.clips) {
            if (candidate == clip) {
                return row;
            }
        }
        row += 1;
    }
    return NSNotFound;
}

- (nullable PETSkillTimelineClip *)clipAtPoint:(NSPoint)point dragMode:(PETTimelineDragMode *)dragMode {
    NSInteger row = 0;
    for (PETSkillTimelineTrack *track in self.document.tracks) {
        for (PETSkillTimelineClip *clip in track.clips) {
            CGRect frame = [self frameForClip:clip rowIndex:row];
            if (!CGRectContainsPoint(frame, CGPointMake(point.x, point.y))) {
                continue;
            }
            if (dragMode != NULL) {
                CGFloat startX = [self.layoutEngine xForTime:clip.startTime metrics:self.layoutMetrics];
                CGFloat endX = [self.layoutEngine xForTime:clip.endTime metrics:self.layoutMetrics];
                if (fabs(point.x - startX) <= PETTimelineResizeHandleWidth) {
                    *dragMode = PETTimelineDragModeResizeStart;
                } else if (fabs(point.x - endX) <= PETTimelineResizeHandleWidth) {
                    *dragMode = PETTimelineDragModeResizeEnd;
                } else {
                    *dragMode = PETTimelineDragModeMoveClip;
                }
            }
            return clip;
        }
        row += 1;
    }
    return nil;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    return [super becomeFirstResponder];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (self.document == nil) {
        return;
    }

    NSRect rulerRect = NSMakeRect(0, 0, self.bounds.size.width, self.layoutMetrics.rulerHeight);
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(rulerRect);

    NSDictionary *labelAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor
    };
    for (NSInteger second = 0; second <= (NSInteger)ceil(self.document.duration); second += 1) {
        CGFloat x = [self.layoutEngine xForTime:second metrics:self.layoutMetrics];
        [[NSColor separatorColor] set];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(x, 0)];
        [line lineToPoint:NSMakePoint(x, self.bounds.size.height)];
        [line stroke];
        [[NSString stringWithFormat:@"%.1fs", (double)second] drawAtPoint:NSMakePoint(x + 2, 4) withAttributes:labelAttributes];
    }

    NSInteger row = 0;
    for (PETSkillTimelineTrack *track in self.document.tracks) {
        CGFloat y = self.bounds.size.height - self.layoutMetrics.rulerHeight - ((row + 1) * self.layoutMetrics.trackHeight);
        NSRect rowRect = NSMakeRect(0, y, self.bounds.size.width, self.layoutMetrics.trackHeight);
        if ((row % 2) == 0) {
            [[NSColor quaternaryLabelColor] setFill];
            NSRectFillUsingOperation(rowRect, NSCompositingOperationSourceOver);
        }

        NSString *trackLabel = track.displayName ?: @"Track";
        [trackLabel drawInRect:NSMakeRect(6, y + 6, 120, 16) withAttributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: NSColor.labelColor
        }];

        for (PETSkillTimelineClip *clip in track.clips) {
            CGRect clipFrame = [self.layoutEngine frameForClip:clip
                                                      rowIndex:row
                                                       metrics:self.layoutMetrics
                                                  contentWidth:self.bounds.size.width
                                                 contentHeight:self.bounds.size.height];
            if (!NSIntersectsRect(dirtyRect, NSRectFromCGRect(clipFrame))) {
                continue;
            }
            NSColor *fillColor = [self colorForTrackType:track.trackType];
            if (clip == self.selectedClip) {
                fillColor = [fillColor colorWithAlphaComponent:0.95];
            } else {
                fillColor = [fillColor colorWithAlphaComponent:0.72];
            }
            [fillColor setFill];
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(clipFrame) xRadius:4 yRadius:4];
            [path fill];

            NSString *label = clip.payload[@"asset"] ?: clip.payload[@"shader"] ?: clip.payload[@"eventType"] ?: clip.payload[@"animation"] ?: clip.clipIdentifier;
            [label drawInRect:NSInsetRect(NSRectFromCGRect(clipFrame), 4, 4) withAttributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:10],
                NSForegroundColorAttributeName: NSColor.whiteColor
            }];
        }
        row += 1;
    }

    CGFloat playheadX = [self.layoutEngine xForTime:self.document.playheadTime metrics:self.layoutMetrics];
    [[NSColor systemRedColor] setFill];
    NSRectFill(NSMakeRect(playheadX, 0, 2, self.bounds.size.height));
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    PETTimelineDragMode hitMode = PETTimelineDragModeNone;
    PETSkillTimelineClip *clip = [self clipAtPoint:point dragMode:&hitMode];
    if (clip != nil) {
        self.selectedClip = clip;
        self.draggingClip = clip;
        self.dragMode = hitMode;
        self.dragAnchorTime = [self.layoutEngine snapTime:[self.layoutEngine timeForX:point.x metrics:self.layoutMetrics]
                                                  metrics:self.layoutMetrics];
        self.dragOriginalStart = clip.startTime;
        self.dragOriginalEnd = clip.endTime;
        if ([self.delegate respondsToSelector:@selector(timelineViewDidSelectClip:)]) {
            [self.delegate timelineViewDidSelectClip:clip];
        }
        if ([self.delegate respondsToSelector:@selector(timelineViewWillBeginEditingClip:)]) {
            [self.delegate timelineViewWillBeginEditingClip:clip];
        }
    } else {
        self.dragMode = PETTimelineDragModeScrubPlayhead;
        self.document.playheadTime = [self.layoutEngine snapTime:[self.layoutEngine timeForX:point.x metrics:self.layoutMetrics]
                                                         metrics:self.layoutMetrics];
        if ([self.delegate respondsToSelector:@selector(timelineViewDidChangePlayhead:)]) {
            [self.delegate timelineViewDidChangePlayhead:self.document.playheadTime];
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSTimeInterval time = [self.layoutEngine snapTime:[self.layoutEngine timeForX:point.x metrics:self.layoutMetrics]
                                              metrics:self.layoutMetrics];

    switch (self.dragMode) {
        case PETTimelineDragModeMoveClip: {
            if (self.draggingClip == nil) {
                return;
            }
            NSTimeInterval delta = time - self.dragAnchorTime;
            self.draggingClip.startTime = MAX(0.0, self.dragOriginalStart + delta);
            self.draggingClip.endTime = MAX(self.draggingClip.startTime + (1.0 / 60.0), self.dragOriginalEnd + delta);
            if ([self.delegate respondsToSelector:@selector(timelineViewDidUpdateClip:)]) {
                [self.delegate timelineViewDidUpdateClip:self.draggingClip];
            }
            break;
        }
        case PETTimelineDragModeResizeStart:
            if (self.draggingClip != nil) {
                self.draggingClip.startTime = MIN(time, self.draggingClip.endTime - (1.0 / 60.0));
                if ([self.delegate respondsToSelector:@selector(timelineViewDidUpdateClip:)]) {
                    [self.delegate timelineViewDidUpdateClip:self.draggingClip];
                }
            }
            break;
        case PETTimelineDragModeResizeEnd:
            if (self.draggingClip != nil) {
                self.draggingClip.endTime = MAX(self.draggingClip.startTime + (1.0 / 60.0), time);
                if ([self.delegate respondsToSelector:@selector(timelineViewDidUpdateClip:)]) {
                    [self.delegate timelineViewDidUpdateClip:self.draggingClip];
                }
            }
            break;
        case PETTimelineDragModeScrubPlayhead:
            self.document.playheadTime = MIN(MAX(0.0, time), self.document.duration);
            if ([self.delegate respondsToSelector:@selector(timelineViewDidChangePlayhead:)]) {
                [self.delegate timelineViewDidChangePlayhead:self.document.playheadTime];
            }
            break;
        default:
            break;
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (self.draggingClip != nil) {
        [self.document notifyChanged];
        if ([self.delegate respondsToSelector:@selector(timelineViewDidUpdateClip:)]) {
            [self.delegate timelineViewDidUpdateClip:self.draggingClip];
        }
    }
    self.dragMode = PETTimelineDragModeNone;
    self.draggingClip = nil;
}

- (void)keyDown:(NSEvent *)event {
    BOOL commandKey = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (commandKey && [event.charactersIgnoringModifiers isEqualToString:@"c"]) {
        if (self.selectedClip != nil && [self.delegate respondsToSelector:@selector(timelineViewDidRequestCopyClip:)]) {
            [self.delegate timelineViewDidRequestCopyClip:self.selectedClip];
        }
        return;
    }
    if (commandKey && [event.charactersIgnoringModifiers isEqualToString:@"v"]) {
        if ([self.delegate respondsToSelector:@selector(timelineViewDidRequestPasteClip)]) {
            [self.delegate timelineViewDidRequestPasteClip];
        }
        return;
    }
    if (event.keyCode == 51 || event.keyCode == 117) {
        if (self.selectedClip != nil && [self.delegate respondsToSelector:@selector(timelineViewDidDeleteClip:)]) {
            [self.delegate timelineViewDidDeleteClip:self.selectedClip];
            self.selectedClip = nil;
        }
        return;
    }
    [super keyDown:event];
}

- (void)scrollWheel:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        CGFloat zoomFactor = event.deltaY > 0 ? 0.9 : 1.1;
        self.layoutMetrics.pixelsPerSecond = MAX(40.0, MIN(400.0, self.layoutMetrics.pixelsPerSecond * zoomFactor));
        [self setNeedsDisplay:YES];
        return;
    }
    [super scrollWheel:event];
}

@end
