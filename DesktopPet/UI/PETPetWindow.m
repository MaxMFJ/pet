#import "PETPetWindow.h"

#import "PETPetView.h"
#import "PETSpineMetalView.h"
#import "../Models/PETPetProfile.h"

static NSString * const PETActionAmbientIdle = @"ambient.idle";
static NSString * const PETActionTapPrimary = @"tap.primary";
static NSString * const PETActionTapSecondary = @"tap.secondary";
static NSString * const PETActionTapHead = @"tap.head";
static NSString * const PETActionTapTail = @"tap.tail";
static NSString * const PETActionTapBody = @"tap.body";
static NSString * const PETActionTapPartPrefix = @"tap.part.";
static NSString * const PETActionDragMoveLeft = @"drag.move.left";
static NSString * const PETActionDragMoveRight = @"drag.move.right";
static NSString * const PETActionDragIdle = @"drag.idle";
static NSString * const PETActionDragRelease = @"drag.release";
static CGFloat const PETPetWindowDragActivationThreshold = 6.0;
static CGFloat const PETPetWindowControlFocusCornerRadius = 16.0;
static CGFloat const PETPetWindowDefaultScale = 0.3;
static NSTimeInterval const PETPetWindowControlFocusBadgeDuration = 1.15;

NSNotificationName const PETPetWindowDidEmitRuntimeEventNotification = @"PETPetWindowDidEmitRuntimeEventNotification";
NSNotificationName const PETPetWindowDidActivateNotification = @"PETPetWindowDidActivateNotification";
NSString * const PETPetWindowProfileIdentifierUserInfoKey = @"PETPetWindowProfileIdentifierUserInfoKey";
NSString * const PETPetWindowActionKeyUserInfoKey = @"PETPetWindowActionKeyUserInfoKey";
NSString * const PETPetWindowFallbackBehaviorStateUserInfoKey = @"PETPetWindowFallbackBehaviorStateUserInfoKey";
NSString * const PETPetWindowResolvedAnimationStateUserInfoKey = @"PETPetWindowResolvedAnimationStateUserInfoKey";
NSString * const PETPetWindowRuntimeModeUserInfoKey = @"PETPetWindowRuntimeModeUserInfoKey";

@interface PETPetWindow ()

@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, strong, nullable) PETPetView *petView;
@property (nonatomic, strong, nullable) PETSpineMetalView *spinePetView;
@property (nonatomic, strong) NSView *contentHostView;
@property (nonatomic, strong) NSView *controlFocusBadgeView;
@property (nonatomic, strong) NSTextField *controlFocusBadgeLabel;
@property (nonatomic, assign) BOOL isDraggingPet;
@property (nonatomic, assign) BOOL isGameMovementActive;
@property (nonatomic, assign) BOOL combatTransientActive;
@property (nonatomic, assign) BOOL gameMovementFacingInverted;
@property (nonatomic, assign) BOOL hasLastGameMovementFacingRight;
@property (nonatomic, assign) BOOL lastGameMovementFacingRight;
@property (nonatomic, assign, readwrite) CGFloat petScale;
@property (nonatomic, assign, readwrite) BOOL facingRight;
@property (nonatomic, assign, readwrite, getter=isClickThroughEnabled) BOOL clickThroughEnabled;
@property (nonatomic, assign) NSPoint anchorOrigin;
@property (nonatomic, copy, readwrite) NSString *currentState;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *supportedStates;
@property (nonatomic, strong, nullable) NSTimer *ambientTimer;
@property (nonatomic, strong, nullable) NSTimer *transientTimer;
@property (nonatomic, strong, nullable) NSTimer *mousePassThroughTimer;
@property (nonatomic, assign) BOOL hasManualStateOverride;
@property (nonatomic, assign) NSPoint dragStartPointInWindow;
@property (nonatomic, assign) NSPoint dragStartPointOnScreen;
@property (nonatomic, assign) NSPoint dragStartWindowOrigin;
@property (nonatomic, assign) BOOL didDragDuringMouseSession;
@property (nonatomic, assign) BOOL dragEligibleForCurrentMouseSession;
@property (nonatomic, assign) NSSize baseNormalWindowSize;
@property (nonatomic, assign) NSSize normalWindowSize;
@property (nonatomic, assign) NSRect normalFrameBeforeTransientExpansion;
@property (nonatomic, assign) BOOL usingTransientExpandedWindow;
@property (nonatomic, assign) BOOL controlFocusActive;
@property (nonatomic, strong, nullable) NSTimer *controlFocusBadgeTimer;

@end

@implementation PETPetWindow

- (BOOL)usesSpineRuntimeView {
    return self.profile.usesSpineRuntime;
}

- (BOOL)supportsDesktopPetBehavior {
    return self.profile.supportsDesktopPetBehavior;
}

- (nullable NSString *)resolvedAnimationStateForBehaviorState:(NSString *)state {
    return [self.profile resolvedAnimationStateForBehaviorState:state];
}

- (nullable NSString *)resolvedAnimationStateForActionKey:(NSString *)actionKey fallbackBehaviorState:(nullable NSString *)fallbackBehaviorState {
    NSArray<NSString *> *candidateActionKeys = [self candidateActionKeysForActionKey:actionKey];

    for (NSString *candidateActionKey in candidateActionKeys) {
        NSString *userAlias = [self.profile userInteractionAnimationStateForActionKey:candidateActionKey];
        if (userAlias.length == 0) {
            continue;
        }
        NSString *baseAlias = [self.profile baseInteractionAnimationStateForActionKey:candidateActionKey];
        BOOL isExplicitOverride = (baseAlias.length == 0) || ![userAlias isEqualToString:baseAlias];
        if (isExplicitOverride) {
            return userAlias;
        }
    }

    for (NSString *candidateActionKey in candidateActionKeys) {
        NSString *alias = [self.profile userInteractionAnimationStateForActionKey:candidateActionKey];
        if (alias.length > 0) {
            return alias;
        }
    }

    for (NSString *candidateActionKey in candidateActionKeys) {
        NSString *alias = [self.profile baseInteractionAnimationStateForActionKey:candidateActionKey];
        if (alias.length > 0) {
            return alias;
        }
    }

    for (NSString *candidateActionKey in candidateActionKeys) {
        if ([self.supportedStates containsObject:candidateActionKey]) {
            return candidateActionKey;
        }
    }

    if (fallbackBehaviorState.length > 0) {
        NSString *resolvedState = [self resolvedAnimationStateForBehaviorState:fallbackBehaviorState];
        if (resolvedState.length > 0) {
            return resolvedState;
        }
        if ([self.supportedStates containsObject:fallbackBehaviorState]) {
            return fallbackBehaviorState;
        }
    }

    return nil;
}

- (NSArray<NSString *> *)candidateActionKeysForActionKey:(NSString *)actionKey {
    if (actionKey.length > 0) {
        NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithObject:actionKey];
        if ([actionKey hasPrefix:PETActionTapPartPrefix]) {
            NSString *semanticPart = [actionKey substringFromIndex:PETActionTapPartPrefix.length];
            if ([semanticPart isEqualToString:@"head"]) {
                [candidates addObject:PETActionTapHead];
                [candidates addObject:PETActionTapPrimary];
            } else if ([semanticPart isEqualToString:@"tail"]) {
                [candidates addObject:PETActionTapTail];
                [candidates addObject:PETActionTapPrimary];
            } else if ([semanticPart isEqualToString:@"body"]) {
                [candidates addObject:PETActionTapBody];
                [candidates addObject:PETActionTapPrimary];
            } else if ([semanticPart isEqualToString:@"ear"] || [semanticPart isEqualToString:@"hand"] || [semanticPart isEqualToString:@"paw"]) {
                [candidates addObject:PETActionTapPrimary];
            } else if ([semanticPart isEqualToString:@"wing"]) {
                [candidates addObject:PETActionTapTail];
                [candidates addObject:PETActionTapPrimary];
            } else if ([semanticPart isEqualToString:@"leg"] || [semanticPart isEqualToString:@"foot"]) {
                [candidates addObject:PETActionTapBody];
                [candidates addObject:PETActionTapPrimary];
            }
        } else if ([actionKey isEqualToString:PETActionTapHead]) {
            [candidates addObject:[PETActionTapPartPrefix stringByAppendingString:@"head"]];
            [candidates addObject:PETActionTapPrimary];
        } else if ([actionKey isEqualToString:PETActionTapTail]) {
            [candidates addObject:[PETActionTapPartPrefix stringByAppendingString:@"tail"]];
            [candidates addObject:PETActionTapPrimary];
        } else if ([actionKey isEqualToString:PETActionTapBody]) {
            [candidates addObject:[PETActionTapPartPrefix stringByAppendingString:@"body"]];
            [candidates addObject:PETActionTapPrimary];
        }
        return [NSOrderedSet orderedSetWithArray:candidates].array;
    }
    return @[];
}

- (NSView *)activePetRendererView {
    return self.spinePetView ?: self.petView;
}

- (BOOL)shouldUseVisibleBoundsInteractionFallback {
    return self.transientTimer != nil || self.usingTransientExpandedWindow || self.combatTransientActive;
}

- (BOOL)activeRendererContainsInteractivePixelsAtPoint:(NSPoint)point {
    if (self.spinePetView != nil) {
        return [self.spinePetView containsInteractiveContentAtPoint:point];
    }
    if (self.petView != nil) {
        return [self.petView containsInteractiveContentAtPoint:point];
    }
    return NO;
}

- (BOOL)activeRendererContainsInteractiveContentAtPoint:(NSPoint)point {
    if ([self activeRendererContainsInteractivePixelsAtPoint:point]) {
        return YES;
    }
    if (![self shouldUseVisibleBoundsInteractionFallback]) {
        return NO;
    }

    NSRect visibleRect = [self activeRendererVisibleRenderedRect];
    if (NSIsEmptyRect(visibleRect)) {
        visibleRect = self.contentView != nil ? self.contentView.bounds : NSZeroRect;
    }
    return NSPointInRect(point, visibleRect);
}

- (BOOL)activeRendererContainsDraggableContentAtPoint:(NSPoint)point {
    if (self.spinePetView != nil) {
        if ([self.spinePetView containsDraggableContentAtPoint:point]) {
            return YES;
        }
        if ([self shouldUseVisibleBoundsInteractionFallback]) {
            NSRect visibleRect = [self activeRendererVisibleRenderedRect];
            if (!NSIsEmptyRect(visibleRect) && NSPointInRect(point, visibleRect)) {
                return YES;
            }
        }
        return NO;
    }
    if (self.petView != nil) {
        if ([self.petView containsDraggableContentAtPoint:point]) {
            return YES;
        }
        if ([self shouldUseVisibleBoundsInteractionFallback]) {
            NSRect visibleRect = [self activeRendererVisibleRenderedRect];
            if (!NSIsEmptyRect(visibleRect) && NSPointInRect(point, visibleRect)) {
                return YES;
            }
        }
        return NO;
    }
    return NO;
}

- (nullable NSString *)activeRendererInteractivePartIdentifierAtPoint:(NSPoint)point {
    if (self.spinePetView != nil) {
        return [self.spinePetView interactivePartIdentifierAtPoint:point];
    }
    return nil;
}

- (BOOL)activeRendererContainsOpaqueRenderedContentAtPoint:(NSPoint)point {
    if (self.spinePetView != nil) {
        return [self.spinePetView containsOpaqueRenderedContentAtPoint:point];
    }
    if (self.petView != nil) {
        return [self.petView containsOpaqueRenderedContentAtPoint:point];
    }
    return NO;
}

- (NSRect)activeRendererVisibleRenderedRect {
    if (self.spinePetView != nil) {
        return [self.spinePetView visibleRenderedContentRect];
    }
    if (self.petView != nil) {
        return [self.petView visibleRenderedContentRect];
    }
    return self.contentView != nil ? self.contentView.bounds : NSZeroRect;
}

- (NSString *)semanticPartForIdentifier:(NSString *)identifier {
    NSString *normalized = identifier.lowercaseString ?: @"";
    if (normalized.length == 0) {
        return @"body";
    }

    NSArray<NSString *> *headKeywords = @[
        @"head", @"face", @"ear", @"eye", @"mouth", @"nose", @"horn",
        @"tou", @"lian", @"yan", @"jing", @"zui", @"zuiba", @"bi", @"nose",
        @"er", @"duo", @"mao", @"xiamao", @"shangmao"
    ];
    for (NSString *keyword in headKeywords) {
        if ([normalized containsString:keyword]) {
            return @"head";
        }
    }

    NSArray<NSString *> *tailKeywords = @[
        @"tail", @"weiba", @"wei", @"wing"
    ];
    for (NSString *keyword in tailKeywords) {
        if ([normalized containsString:keyword]) {
            return @"tail";
        }
    }

    NSArray<NSString *> *earKeywords = @[@"ear", @"duo", @"erduo"];
    for (NSString *keyword in earKeywords) {
        if ([normalized containsString:keyword]) {
            return @"ear";
        }
    }

    NSArray<NSString *> *handKeywords = @[@"hand", @"arm", @"shou", @"gebi", @"bizi"];
    for (NSString *keyword in handKeywords) {
        if ([normalized containsString:keyword]) {
            return @"hand";
        }
    }

    NSArray<NSString *> *pawKeywords = @[@"paw", @"claw", @"zhua", @"zhazi", @"shoumao"];
    for (NSString *keyword in pawKeywords) {
        if ([normalized containsString:keyword]) {
            return @"paw";
        }
    }

    NSArray<NSString *> *legKeywords = @[@"leg", @"tui", @"datui", @"xiaotui"];
    for (NSString *keyword in legKeywords) {
        if ([normalized containsString:keyword]) {
            return @"leg";
        }
    }

    NSArray<NSString *> *footKeywords = @[@"foot", @"feet", @"jiao", @"jiaozhang"];
    for (NSString *keyword in footKeywords) {
        if ([normalized containsString:keyword]) {
            return @"foot";
        }
    }

    NSArray<NSString *> *wingKeywords = @[@"wing", @"chi", @"chibang"];
    for (NSString *keyword in wingKeywords) {
        if ([normalized containsString:keyword]) {
            return @"wing";
        }
    }

    NSArray<NSString *> *bodyKeywords = @[
        @"body", @"belly", @"chest", @"back", @"hip",
        @"shen", @"duzi", @"xiong", @"yao", @"tun",
        @"shou", @"zhua", @"tui", @"datui", @"xiaotui", @"jiao"
    ];
    for (NSString *keyword in bodyKeywords) {
        if ([normalized containsString:keyword]) {
            return @"body";
        }
    }

    return @"body";
}

- (NSString *)actionKeyForSemanticPart:(NSString *)semanticPart {
    NSString *normalized = semanticPart.lowercaseString ?: @"body";
    if (normalized.length == 0) {
        normalized = @"body";
    }
    return [PETActionTapPartPrefix stringByAppendingString:normalized];
}

- (NSString *)fallbackBehaviorStateForSemanticPart:(NSString *)semanticPart {
    NSString *normalized = semanticPart.lowercaseString ?: @"body";
    if ([normalized isEqualToString:@"tail"] || [normalized isEqualToString:@"wing"]) {
        return @"review";
    }
    if ([normalized isEqualToString:@"leg"] || [normalized isEqualToString:@"foot"] || [normalized isEqualToString:@"body"]) {
        return @"jumping";
    }
    return @"waving";
}

- (NSTimeInterval)fallbackDurationForBehaviorState:(NSString *)behaviorState {
    if ([behaviorState isEqualToString:@"review"]) {
        return 1.1;
    }
    if ([behaviorState isEqualToString:@"jumping"]) {
        return 0.55;
    }
    if ([behaviorState isEqualToString:@"waiting"]) {
        return 1.6;
    }
    return 0.9;
}

- (NSTimeInterval)transientDurationForResolvedState:(NSString *)resolvedState
                              fallbackBehaviorState:(nullable NSString *)fallbackBehaviorState
                                    fallbackDuration:(NSTimeInterval)fallbackDuration {
    if (self.spinePetView != nil && resolvedState.length > 0) {
        NSTimeInterval runtimeDuration = [self.spinePetView durationForState:resolvedState];
        if (runtimeDuration > 0.0) {
            return runtimeDuration;
        }
    }

    if (fallbackDuration > 0.0) {
        return fallbackDuration;
    }

    return [self fallbackDurationForBehaviorState:fallbackBehaviorState ?: @""];
}

- (void)handlePrimaryInteractionForPoint:(NSPoint)localPoint {
    NSString *partIdentifier = [self activeRendererInteractivePartIdentifierAtPoint:localPoint];
    NSString *semanticPart = [self semanticPartForIdentifier:partIdentifier ?: @""];
    NSLog(@"[DesktopPet] Interaction hit part identifier=%@ semantic=%@", partIdentifier ?: @"<none>", semanticPart);

    if (!self.supportsDesktopPetBehavior) {
        return;
    }

    NSString *actionKey = [self actionKeyForSemanticPart:semanticPart];
    NSString *fallbackBehaviorState = [self fallbackBehaviorStateForSemanticPart:semanticPart];
    NSTimeInterval duration = [self fallbackDurationForBehaviorState:fallbackBehaviorState];
    [self playTransientActionKey:actionKey fallbackBehaviorState:fallbackBehaviorState duration:duration];
}

- (BOOL)containsOpaqueRenderedContentAtScreenPoint:(NSPoint)screenPoint {
    if (!NSPointInRect(screenPoint, self.frame) || self.contentView == nil) {
        return NO;
    }
    NSPoint windowPoint = [self convertPointFromScreen:screenPoint];
    NSPoint localPoint = [self.contentView convertPoint:windowPoint fromView:nil];
    return [self activeRendererContainsOpaqueRenderedContentAtPoint:localPoint];
}

- (BOOL)containsOpaqueRenderedContentAtScreenPoint:(NSPoint)screenPoint fromOrigin:(NSPoint)origin {
    NSRect assumedFrame = self.frame;
    assumedFrame.origin = origin;
    if (!NSPointInRect(screenPoint, assumedFrame) || self.contentView == nil) {
        return NO;
    }

    NSPoint localPoint = NSMakePoint(screenPoint.x - assumedFrame.origin.x,
                                     screenPoint.y - assumedFrame.origin.y);
    return [self activeRendererContainsOpaqueRenderedContentAtPoint:localPoint];
}

- (void)setFrameOrigin:(NSPoint)point {
    NSPoint previousOrigin = self.frame.origin;
    [super setFrameOrigin:point];

    NSPoint delta = NSMakePoint(point.x - previousOrigin.x, point.y - previousOrigin.y);
    if (self.usingTransientExpandedWindow) {
        NSRect normalFrame = self.normalFrameBeforeTransientExpansion;
        normalFrame.origin.x += delta.x;
        normalFrame.origin.y += delta.y;
        self.normalFrameBeforeTransientExpansion = normalFrame;
        self.anchorOrigin = normalFrame.origin;
        return;
    }

    self.anchorOrigin = point;
    NSRect normalFrame = self.normalFrameBeforeTransientExpansion;
    normalFrame.origin = point;
    if (normalFrame.size.width <= 0.0 || normalFrame.size.height <= 0.0) {
        normalFrame.size = self.normalWindowSize.width > 0.0 && self.normalWindowSize.height > 0.0 ? self.normalWindowSize : self.frame.size;
    }
    self.normalFrameBeforeTransientExpansion = normalFrame;
}

- (NSPoint)stableFrameOrigin {
    return self.usingTransientExpandedWindow ? self.normalFrameBeforeTransientExpansion.origin : self.frame.origin;
}

- (CGSize)stableFrameSize {
    if (self.usingTransientExpandedWindow) {
        return self.normalFrameBeforeTransientExpansion.size;
    }
    return self.frame.size;
}

- (NSPoint)presentedFrameOriginForStableOrigin:(NSPoint)origin {
    if (!self.usingTransientExpandedWindow) {
        return origin;
    }

    CGSize stableSize = [self stableFrameSize];
    CGFloat extraWidth = self.frame.size.width - stableSize.width;
    CGFloat extraHeight = self.frame.size.height - stableSize.height;
    return NSMakePoint(origin.x - (extraWidth * 0.5),
                       origin.y - (extraHeight * 0.5));
}

- (NSPoint)constrainedFrameOriginForVisibleContentFromOrigin:(NSPoint)origin {
    NSScreen *screen = NSScreen.mainScreen;
    NSRect screenFrame = screen.frame;
    NSRect visibleContentRect = [self activeRendererVisibleRenderedRect];
    if (NSIsEmptyRect(visibleContentRect) || self.contentView == nil) {
        visibleContentRect = self.contentView != nil ? self.contentView.bounds : NSMakeRect(0.0, 0.0, self.frame.size.width, self.frame.size.height);
    }

    CGFloat minVisibleX = origin.x + visibleContentRect.origin.x;
    CGFloat maxVisibleX = origin.x + NSMaxX(visibleContentRect);
    CGFloat minVisibleY = origin.y + visibleContentRect.origin.y;
    CGFloat maxVisibleY = origin.y + NSMaxY(visibleContentRect);

    if (minVisibleX < NSMinX(screenFrame)) {
        origin.x += (NSMinX(screenFrame) - minVisibleX);
    } else if (maxVisibleX > NSMaxX(screenFrame)) {
        origin.x -= (maxVisibleX - NSMaxX(screenFrame));
    }

    if (minVisibleY < NSMinY(screenFrame)) {
        origin.y += (NSMinY(screenFrame) - minVisibleY);
    } else if (maxVisibleY > NSMaxY(screenFrame)) {
        origin.y -= (maxVisibleY - NSMaxY(screenFrame));
    }

    return origin;
}

- (NSRect)visibleRenderedContentRectAtScreenOrigin:(NSPoint)origin {
    NSRect visibleContentRect = [self activeRendererVisibleRenderedRect];
    if (NSIsEmptyRect(visibleContentRect) || self.contentView == nil) {
        visibleContentRect = self.contentView != nil ? self.contentView.bounds : NSMakeRect(0.0, 0.0, self.frame.size.width, self.frame.size.height);
    }
    return NSOffsetRect(visibleContentRect, origin.x, origin.y);
}

- (BOOL)intersectsPetWindowAtPixelLevel:(PETPetWindow *)otherWindow
                          sampleSpacing:(CGFloat)sampleSpacing
                               hitPoint:(NSPoint *)hitPoint {
    return [self wouldIntersectPetWindowAtPixelLevel:otherWindow
                                          fromOrigin:self.frame.origin
                                       sampleSpacing:sampleSpacing
                                            hitPoint:hitPoint];
}

- (BOOL)wouldIntersectPetWindowAtPixelLevel:(PETPetWindow *)otherWindow
                                 fromOrigin:(NSPoint)origin
                              sampleSpacing:(CGFloat)sampleSpacing
                                   hitPoint:(NSPoint *)hitPoint {
    return [self wouldIntersectPetWindowAtPixelLevel:otherWindow
                                          fromOrigin:origin
                                         otherOrigin:otherWindow.frame.origin
                                       sampleSpacing:sampleSpacing
                                            hitPoint:hitPoint];
}

- (BOOL)wouldIntersectPetWindowAtPixelLevel:(PETPetWindow *)otherWindow
                                 fromOrigin:(NSPoint)origin
                                otherOrigin:(NSPoint)otherOrigin
                             sampleSpacing:(CGFloat)sampleSpacing
                                  hitPoint:(NSPoint *)hitPoint {
    if (otherWindow == nil || otherWindow == self) {
        return NO;
    }

    NSRect assumedFrame = self.frame;
    assumedFrame.origin = origin;
    NSRect otherAssumedFrame = otherWindow.frame;
    otherAssumedFrame.origin = otherOrigin;
    NSRect overlap = NSIntersectionRect(assumedFrame, otherAssumedFrame);
    if (NSIsEmptyRect(overlap)) {
        return NO;
    }

    CGFloat spacing = MAX(1.0, sampleSpacing);
    CGFloat minX = floor(NSMinX(overlap));
    CGFloat maxX = ceil(NSMaxX(overlap));
    CGFloat minY = floor(NSMinY(overlap));
    CGFloat maxY = ceil(NSMaxY(overlap));

    for (CGFloat y = minY; y < maxY; y += spacing) {
        for (CGFloat x = minX; x < maxX; x += spacing) {
            NSPoint screenPoint = NSMakePoint(x + 0.5, y + 0.5);
            if (![self containsOpaqueRenderedContentAtScreenPoint:screenPoint fromOrigin:origin]) {
                continue;
            }
            if (![otherWindow containsOpaqueRenderedContentAtScreenPoint:screenPoint fromOrigin:otherOrigin]) {
                continue;
            }
            if (hitPoint != NULL) {
                *hitPoint = screenPoint;
            }
            return YES;
        }
    }

    return NO;
}

- (void)handlePrimaryInteraction {
    if (self.supportsDesktopPetBehavior) {
        [self playTransientActionKey:PETActionTapPrimary fallbackBehaviorState:@"waving" duration:0.9];
    }
}

- (void)handleSecondaryInteraction {
    if (self.supportsDesktopPetBehavior) {
        [self playTransientActionKey:PETActionTapSecondary fallbackBehaviorState:@"review" duration:1.1];
    }
}

- (void)handleDragStateChanged:(BOOL)isDragging deltaX:(CGFloat)deltaX {
    self.isDraggingPet = isDragging;
    if (isDragging) {
        [self updateDragFeedbackForHorizontalDelta:deltaX];
        return;
    }

    [self.transientTimer invalidate];
    self.transientTimer = nil;
    [self resumeAmbientBehavior];
}

- (void)playStateOnActiveView:(NSString *)state loop:(BOOL)loop {
    if (self.spinePetView != nil) {
        [self.spinePetView playState:state loop:loop];
        return;
    }
    if ([self.petView.currentState isEqualToString:state]) {
        [self.petView recordProfilingWindowEventWithName:@"play.skip.same-state"];
        return;
    }
    [self.petView recordProfilingWindowEventWithName:@"play.apply"];
    [self.petView playState:state];
}

- (void)emitRuntimeEventWithActionKey:(NSString *)actionKey
                fallbackBehaviorState:(nullable NSString *)fallbackBehaviorState
               resolvedAnimationState:(NSString *)resolvedAnimationState
                                  mode:(NSString *)mode {
    NSMutableDictionary<NSString *, id> *userInfo = [NSMutableDictionary dictionary];
    userInfo[PETPetWindowProfileIdentifierUserInfoKey] = self.profile.identifier ?: @"";
    userInfo[PETPetWindowActionKeyUserInfoKey] = actionKey ?: @"";
    userInfo[PETPetWindowResolvedAnimationStateUserInfoKey] = resolvedAnimationState ?: @"";
    userInfo[PETPetWindowRuntimeModeUserInfoKey] = mode ?: @"runtime";
    if (fallbackBehaviorState.length > 0) {
        userInfo[PETPetWindowFallbackBehaviorStateUserInfoKey] = fallbackBehaviorState;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PETPetWindowDidEmitRuntimeEventNotification
                                                        object:self
                                                      userInfo:userInfo.copy];
}

- (void)resumeDefaultAnimationOnActiveView {
    if (self.spinePetView != nil) {
        [self.spinePetView resumeDefaultAnimation];
        return;
    }
    [self.petView resumeDefaultAnimation];
}

- (void)configureControlFocusOverlay {
    self.contentHostView.wantsLayer = YES;
    self.contentHostView.layer.cornerRadius = PETPetWindowControlFocusCornerRadius;

    self.controlFocusBadgeView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.controlFocusBadgeView.wantsLayer = YES;
    self.controlFocusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.14 green:0.63 blue:0.98 alpha:0.96].CGColor;
    self.controlFocusBadgeView.layer.cornerRadius = 10.0;
    self.controlFocusBadgeView.hidden = YES;
    self.controlFocusBadgeView.alphaValue = 0.0;
    self.controlFocusBadgeView.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;

    self.controlFocusBadgeLabel = [NSTextField labelWithString:@"当前控制"];
    self.controlFocusBadgeLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
    self.controlFocusBadgeLabel.textColor = NSColor.whiteColor;
    self.controlFocusBadgeLabel.alignment = NSTextAlignmentCenter;
    [self.controlFocusBadgeLabel sizeToFit];
    [self.controlFocusBadgeView addSubview:self.controlFocusBadgeLabel];
    [self.contentHostView addSubview:self.controlFocusBadgeView];
    [self layoutControlFocusBadge];
}

- (void)layoutControlFocusBadge {
    if (self.controlFocusBadgeView == nil || self.controlFocusBadgeLabel == nil) {
        return;
    }

    [self.controlFocusBadgeLabel sizeToFit];
    CGFloat horizontalPadding = 12.0;
    CGFloat verticalPadding = 5.0;
    NSSize labelSize = self.controlFocusBadgeLabel.fittingSize;
    CGFloat badgeWidth = ceil(labelSize.width + (horizontalPadding * 2.0));
    CGFloat badgeHeight = ceil(labelSize.height + (verticalPadding * 2.0));
    NSRect bounds = self.contentHostView.bounds;
    CGFloat badgeX = floor((NSWidth(bounds) - badgeWidth) * 0.5);
    CGFloat badgeY = MAX(8.0, NSHeight(bounds) - badgeHeight - 12.0);
    self.controlFocusBadgeView.frame = NSMakeRect(badgeX, badgeY, badgeWidth, badgeHeight);
    self.controlFocusBadgeLabel.frame = NSMakeRect(horizontalPadding,
                                                   verticalPadding - 1.0,
                                                   badgeWidth - (horizontalPadding * 2.0),
                                                   labelSize.height + 2.0);
}

- (void)showControlFocusBadgeTemporarily {
    [self.controlFocusBadgeTimer invalidate];
    self.controlFocusBadgeTimer = nil;
    [self layoutControlFocusBadge];
    self.controlFocusBadgeView.hidden = NO;
    self.controlFocusBadgeView.alphaValue = 1.0;

    __weak typeof(self) weakSelf = self;
    self.controlFocusBadgeTimer = [NSTimer scheduledTimerWithTimeInterval:PETPetWindowControlFocusBadgeDuration
                                                                  repeats:NO
                                                                    block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.controlFocusBadgeTimer = nil;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = 0.18;
            strongSelf.controlFocusBadgeView.animator.alphaValue = 0.0;
        } completionHandler:^{
            strongSelf.controlFocusBadgeView.hidden = YES;
        }];
    }];
}

- (void)setControlFocusActive:(BOOL)active animated:(BOOL)animated {
    _controlFocusActive = active;
    [self.controlFocusBadgeTimer invalidate];
    self.controlFocusBadgeTimer = nil;

    if (!active) {
        self.controlFocusBadgeView.hidden = YES;
        self.controlFocusBadgeView.alphaValue = 0.0;
        return;
    }

    if (!animated) {
        self.controlFocusBadgeView.hidden = YES;
        self.controlFocusBadgeView.alphaValue = 0.0;
        return;
    }

    [self showControlFocusBadgeTemporarily];
}

- (instancetype)initWithProfile:(PETPetProfile *)profile origin:(NSPoint)origin {
    NSRect frame = NSMakeRect(origin.x, origin.y, profile.canvasSize.width, profile.canvasSize.height);
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        _profile = profile;
        _petScale = PETPetWindowDefaultScale;
        _facingRight = YES;
        _clickThroughEnabled = NO;
        _anchorOrigin = origin;
        _baseNormalWindowSize = frame.size;
        _normalWindowSize = frame.size;
        _normalFrameBeforeTransientExpansion = frame;
        _currentState = [profile.defaultState copy];
        _supportedStates = [profile.supportedStates copy];
        self.backgroundColor = NSColor.clearColor;
        self.opaque = NO;
        self.hasShadow = NO;
        self.level = NSFloatingWindowLevel;
        self.releasedWhenClosed = NO;
        self.movableByWindowBackground = NO;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.ignoresMouseEvents = NO;

        __weak typeof(self) weakSelf = self;
        void (^menuActionHandler)(NSString *) = ^(NSString *state) {
            [weakSelf previewState:state];
        };

        if ([self usesSpineRuntimeView]) {
            NSError *error = nil;
            _spinePetView = [[PETSpineMetalView alloc] initWithProfile:profile error:&error];
            if (_spinePetView == nil) {
                NSLog(@"[DesktopPet] Failed to create Spine Metal view: %@", error.localizedDescription ?: @"unknown error");
                _petView = [[PETPetView alloc] initWithProfile:profile];
            }
        } else {
            _petView = [[PETPetView alloc] initWithProfile:profile];
        }

        if (_spinePetView != nil) {
            _spinePetView.menuActionHandler = menuActionHandler;
        }
        if (_petView != nil) {
            _petView.menuActionHandler = menuActionHandler;
        }

        _contentHostView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, frame.size.width, frame.size.height)];
        _contentHostView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSView *activeRendererView = [self activePetRendererView];
        activeRendererView.frame = _contentHostView.bounds;
        activeRendererView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_contentHostView addSubview:activeRendererView];
        self.contentView = _contentHostView;
        [self configureControlFocusOverlay];
        if (_spinePetView != nil) {
            NSSize spineNormalSize = [_spinePetView normalWindowSize];
            if (spineNormalSize.width > 0.0 && spineNormalSize.height > 0.0) {
                _baseNormalWindowSize = spineNormalSize;
                _normalWindowSize = spineNormalSize;
                NSRect normalFrame = self.frame;
                normalFrame.size = spineNormalSize;
                [self setFrame:normalFrame display:YES];
                _normalFrameBeforeTransientExpansion = normalFrame;
                [_contentHostView setFrame:NSMakeRect(0.0, 0.0, spineNormalSize.width, spineNormalSize.height)];
                [_spinePetView setFrame:_contentHostView.bounds];
                _spinePetView.contentLayoutRect = NSMakeRect(0.0, 0.0, spineNormalSize.width, spineNormalSize.height);
                [self layoutControlFocusBadge];
            }
        }
        [self applyFacingRight:self.facingRight];
        if (_spinePetView != nil) {
            [_spinePetView startAnimating];
        } else {
            [_petView startAnimating];
        }
        [self startMousePassThroughMonitoring];
        self.acceptsMouseMovedEvents = YES;
        [self applyScale:PETPetWindowDefaultScale];
        [self resumeAmbientBehavior];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (void)close {
    [self.ambientTimer invalidate];
    [self.transientTimer invalidate];
    [self.mousePassThroughTimer invalidate];
    [super close];
}

- (void)playTransientState:(NSString *)state duration:(NSTimeInterval)duration {
    [self playTransientState:state duration:duration loop:NO resumeAmbientOnCompletion:YES];
}

- (void)playTransientState:(NSString *)state duration:(NSTimeInterval)duration loop:(BOOL)loop {
    [self playTransientState:state duration:duration loop:loop resumeAmbientOnCompletion:YES];
}

- (void)playTransientState:(NSString *)state
                  duration:(NSTimeInterval)duration
                      loop:(BOOL)loop
  resumeAmbientOnCompletion:(BOOL)resumeAmbientOnCompletion {
    [self.transientTimer invalidate];
    [self.ambientTimer invalidate];
    self.ambientTimer = nil;
    self.hasManualStateOverride = NO;
    NSString *resolvedState = [self resolvedAnimationStateForBehaviorState:state] ?: state;
    [self expandWindowForTransientStateIfNeeded:resolvedState];
    [self playStateOnActiveView:resolvedState loop:loop];
    self.currentState = resolvedState;

    __weak typeof(self) weakSelf = self;
    self.transientTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                          repeats:NO
                                                            block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        weakSelf.transientTimer = nil;
        [weakSelf restoreWindowAfterTransientExpansionIfNeeded];
        if (resumeAmbientOnCompletion) {
            [weakSelf resumeAmbientBehavior];
            return;
        }
        weakSelf.combatTransientActive = NO;
        [weakSelf updateMousePassThroughState];
    }];
}

- (void)playTransientActionKey:(NSString *)actionKey fallbackBehaviorState:(nullable NSString *)fallbackBehaviorState duration:(NSTimeInterval)duration {
    NSArray<NSString *> *candidateActionKeys = [self candidateActionKeysForActionKey:actionKey];
    NSString *resolvedState = [self resolvedAnimationStateForActionKey:actionKey fallbackBehaviorState:fallbackBehaviorState];
    if (resolvedState.length == 0) {
        NSLog(@"[DesktopPet] Interaction action unresolved actionKey=%@ candidates=%@ fallback=%@ supportedStates=%@ userAliases=%@ baseAliases=%@",
              actionKey ?: @"<nil>",
              candidateActionKeys ?: @[],
              fallbackBehaviorState ?: @"<nil>",
              self.supportedStates ?: @[],
              self.profile.interactionAliases ?: @{},
              self.profile.baseInteractionAliases ?: @{});
        resolvedState = self.profile.defaultState;
    } else {
        NSLog(@"[DesktopPet] Interaction action resolved actionKey=%@ candidates=%@ fallback=%@ state=%@ userAliases=%@ baseAliases=%@",
              actionKey ?: @"<nil>",
              candidateActionKeys ?: @[],
              fallbackBehaviorState ?: @"<nil>",
              resolvedState,
              self.profile.interactionAliases ?: @{},
              self.profile.baseInteractionAliases ?: @{});
    }
    NSTimeInterval resolvedDuration = [self transientDurationForResolvedState:resolvedState
                                                        fallbackBehaviorState:fallbackBehaviorState
                                                              fallbackDuration:duration];
    NSLog(@"[DesktopPet] Interaction playback state=%@ duration=%.3f", resolvedState ?: @"<nil>", resolvedDuration);
    [self emitRuntimeEventWithActionKey:actionKey
                  fallbackBehaviorState:fallbackBehaviorState
                 resolvedAnimationState:resolvedState
                                   mode:@"transient"];
    [self playTransientState:resolvedState duration:resolvedDuration];
}

- (void)applyScale:(CGFloat)scale {
    CGFloat clampedScale = MIN(MAX(scale, 0.01), 3.0);
    _petScale = clampedScale;

    NSSize baseSize = self.baseNormalWindowSize;
    if (baseSize.width <= 0.0 || baseSize.height <= 0.0) {
        baseSize = self.profile.canvasSize;
    }
    NSSize scaledSize = NSMakeSize(baseSize.width * clampedScale, baseSize.height * clampedScale);
    self.normalWindowSize = scaledSize;
    [self restoreWindowAfterTransientExpansionIfNeeded];
    NSRect frame = self.frame;
    self.anchorOrigin = frame.origin;
    frame.size = scaledSize;
    frame.origin = self.anchorOrigin;
    if (!NSEqualRects(self.frame, frame)) {
        [self.petView recordProfilingWindowEventWithName:@"window.scale-frame"];
        [self setFrame:frame display:YES];
    }
    [self layoutControlFocusBadge];
    [self updateActiveRendererContentLayoutRectForFrame:frame normalFrame:frame];
}

- (void)applyFacingRight:(BOOL)facingRight {
    if (_facingRight == facingRight) {
        [self.petView recordProfilingWindowEventWithName:@"facing.skip.same"];
        return;
    }
    _facingRight = facingRight;
    self.petView.facingRight = facingRight;
    self.spinePetView.facingRight = facingRight;
    [self.petView recordProfilingWindowEventWithName:@"facing.apply"];
    if (self.petView != nil) {
        [self.petView setNeedsDisplay:YES];
    }
    if (self.spinePetView != nil) {
        [self.spinePetView setNeedsDisplay:YES];
    }
}

- (void)applyUserFacingRight:(BOOL)facingRight {
    if (self.hasLastGameMovementFacingRight) {
        self.gameMovementFacingInverted = (facingRight != self.lastGameMovementFacingRight);
    }
    [self applyFacingRight:facingRight];
}

- (void)setClickThroughEnabled:(BOOL)enabled {
    _clickThroughEnabled = enabled;
    if (enabled) {
        self.ignoresMouseEvents = YES;
        [self.mousePassThroughTimer invalidate];
        self.mousePassThroughTimer = nil;
    } else {
        [self startMousePassThroughMonitoring];
        [self updateMousePassThroughState];
    }
}

- (void)startMousePassThroughMonitoring {
    if (self.isClickThroughEnabled || self.mousePassThroughTimer != nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.mousePassThroughTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                                 repeats:YES
                                                                   block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        [weakSelf updateMousePassThroughState];
    }];
}

- (void)updateMousePassThroughState {
    if (self.isClickThroughEnabled || self.contentView == nil || self.isDraggingPet) {
        return;
    }

    NSWindow *keyWindow = NSApp.keyWindow;
    if (keyWindow != nil && keyWindow != self) {
        self.ignoresMouseEvents = YES;
        return;
    }

    NSPoint screenPoint = NSEvent.mouseLocation;
    NSRect frame = self.frame;
    if (!NSPointInRect(screenPoint, frame)) {
        self.ignoresMouseEvents = YES;
        return;
    }

    NSPoint windowPoint = [self convertPointFromScreen:screenPoint];
    NSPoint localPoint = [self.contentView convertPoint:windowPoint fromView:nil];
    BOOL isInteractive = [self activeRendererContainsInteractiveContentAtPoint:localPoint];
    self.ignoresMouseEvents = !isInteractive;
}

- (void)sendEvent:(NSEvent *)event {
    switch (event.type) {
        case NSEventTypeLeftMouseDown:
            [self handleLeftMouseDown:event];
            return;
        case NSEventTypeLeftMouseDragged:
            [self handleLeftMouseDragged:event];
            return;
        case NSEventTypeLeftMouseUp:
            [self handleLeftMouseUp:event];
            return;
        case NSEventTypeRightMouseUp:
            [self handleRightMouseUp:event];
            return;
        default:
            [super sendEvent:event];
            return;
    }
}

- (void)handleLeftMouseDown:(NSEvent *)event {
    NSPoint windowPoint = event.locationInWindow;
    NSPoint localPoint = [self.contentView convertPoint:windowPoint fromView:nil];
    if (![self activeRendererContainsInteractiveContentAtPoint:localPoint]) {
        [super sendEvent:event];
        return;
    }

    [self emitActivationEvent];
    self.ignoresMouseEvents = NO;
    self.dragStartPointInWindow = windowPoint;
    self.dragStartPointOnScreen = NSEvent.mouseLocation;
    self.dragStartWindowOrigin = self.frame.origin;
    self.didDragDuringMouseSession = NO;
    self.dragEligibleForCurrentMouseSession = [self activeRendererContainsDraggableContentAtPoint:localPoint];
}

- (void)handleLeftMouseDragged:(NSEvent *)event {
    if (!self.dragEligibleForCurrentMouseSession) {
        return;
    }

    NSPoint currentPointOnScreen = NSEvent.mouseLocation;
    CGFloat deltaX = currentPointOnScreen.x - self.dragStartPointOnScreen.x;
    CGFloat deltaY = currentPointOnScreen.y - self.dragStartPointOnScreen.y;
    if (!self.didDragDuringMouseSession &&
        hypot(deltaX, deltaY) < PETPetWindowDragActivationThreshold) {
        return;
    }

    NSPoint origin = self.dragStartWindowOrigin;
    origin.x += deltaX;
    origin.y += deltaY;
    [self setFrameOrigin:origin];
    self.didDragDuringMouseSession = YES;
    [self handleDragStateChanged:YES deltaX:deltaX];
}

- (void)handleLeftMouseUp:(NSEvent *)event {
    NSPoint windowPoint = event.locationInWindow;
    NSPoint localPoint = [self.contentView convertPoint:windowPoint fromView:nil];
    BOOL interactive = [self activeRendererContainsInteractiveContentAtPoint:localPoint];

    if (!self.didDragDuringMouseSession && interactive) {
        [self handlePrimaryInteractionForPoint:localPoint];
    }

    if (self.didDragDuringMouseSession || self.isDraggingPet) {
        [self handleDragStateChanged:NO deltaX:0.0];
    }

    self.dragEligibleForCurrentMouseSession = NO;
    self.didDragDuringMouseSession = NO;
    self.dragStartPointOnScreen = NSZeroPoint;
    [self updateMousePassThroughState];
}

- (void)handleRightMouseUp:(NSEvent *)event {
    NSPoint windowPoint = event.locationInWindow;
    NSPoint localPoint = [self.contentView convertPoint:windowPoint fromView:nil];
    if (![self activeRendererContainsInteractiveContentAtPoint:localPoint]) {
        [super sendEvent:event];
        return;
    }

    [self emitActivationEvent];
    [self handleSecondaryInteraction];
    NSMenu *menu = [self.contentView menuForEvent:event];
    if (menu != nil) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:self.contentView];
    }
}

- (void)emitActivationEvent {
    NSString *profileIdentifier = self.profile.identifier;
    if (profileIdentifier.length == 0) {
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PETPetWindowDidActivateNotification
                                                        object:self
                                                      userInfo:@{
        PETPetWindowProfileIdentifierUserInfoKey: profileIdentifier
    }];
}

- (void)resumeAmbientBehavior {
    [self.transientTimer invalidate];
    self.transientTimer = nil;
    self.hasManualStateOverride = NO;
    self.combatTransientActive = NO;
    [self restoreWindowAfterTransientExpansionIfNeeded];

    if (self.supportsDesktopPetBehavior) {
        NSString *idleState = [self resolvedAnimationStateForActionKey:PETActionAmbientIdle fallbackBehaviorState:@"idle"] ?: self.profile.defaultState;
        [self playStateOnActiveView:idleState loop:YES];
        self.currentState = idleState;
        [self emitRuntimeEventWithActionKey:PETActionAmbientIdle
                      fallbackBehaviorState:@"idle"
                     resolvedAnimationState:idleState
                                       mode:@"ambient"];
        [self scheduleNextAmbientVariant];
    } else {
        [self resumeDefaultAnimationOnActiveView];
        self.currentState = self.profile.defaultState;
        [self emitRuntimeEventWithActionKey:@"ambient.idle"
                      fallbackBehaviorState:@"idle"
                     resolvedAnimationState:self.profile.defaultState
                                       mode:@"ambient"];
    }
}

- (void)playCombatPresentationWithAnimationState:(NSString *)animationState
                                      actionKey:(NSString *)actionKey
                                       duration:(NSTimeInterval)duration {
    NSString *resolvedState = nil;
    if (actionKey.length > 0) {
        resolvedState = [self resolvedAnimationStateForActionKey:actionKey fallbackBehaviorState:animationState];
    }
    if (resolvedState.length == 0 && animationState.length > 0 && [self.supportedStates containsObject:animationState]) {
        resolvedState = animationState;
    }
    if (resolvedState.length == 0) {
        return;
    }

    NSTimeInterval resolvedDuration = [self transientDurationForResolvedState:resolvedState
                                                        fallbackBehaviorState:animationState
                                                              fallbackDuration:duration];
    resolvedDuration = MAX(0.05, resolvedDuration);
    self.combatTransientActive = YES;
    if (actionKey.length > 0) {
        [self playTransientActionKey:actionKey fallbackBehaviorState:resolvedState duration:resolvedDuration];
        return;
    }

    [self emitRuntimeEventWithActionKey:@"combat.perform"
                  fallbackBehaviorState:resolvedState
                 resolvedAnimationState:resolvedState
                                   mode:@"combat"];
    [self playTransientState:resolvedState duration:resolvedDuration];
}

- (void)playHitReactionForCombatState:(NSString *)combatState
                         launchVector:(CGVector)launchVector
                             duration:(NSTimeInterval)duration {
    NSString *resolvedState = [self resolvedAnimationStateForCombatReactionState:combatState launchVector:launchVector];
    if (resolvedState.length == 0) {
        return;
    }

    NSTimeInterval resolvedDuration = [self transientDurationForResolvedState:resolvedState
                                                        fallbackBehaviorState:combatState
                                                              fallbackDuration:duration];
    resolvedDuration = MAX(resolvedDuration, duration);
    resolvedDuration = MAX(0.08, resolvedDuration);
    NSTimeInterval runtimeDuration = self.spinePetView != nil ? [self.spinePetView durationForState:resolvedState] : 0.0;
    BOOL isLaunchedReaction = [combatState isEqualToString:@"combat.launched"];
    if (isLaunchedReaction && runtimeDuration > 0.0) {
        resolvedDuration = MIN(resolvedDuration, MIN(runtimeDuration, 0.18));
    } else if (isLaunchedReaction) {
        resolvedDuration = MIN(resolvedDuration, 0.18);
    }
    if (isLaunchedReaction) {
        resolvedDuration = MAX(0.12, resolvedDuration);
    }
    BOOL shouldLoop = !isLaunchedReaction && (runtimeDuration > 0.0 && resolvedDuration > runtimeDuration + 0.001);
    self.combatTransientActive = YES;
    [self emitRuntimeEventWithActionKey:[NSString stringWithFormat:@"combat.reaction.%@", combatState ?: @"hit"]
                  fallbackBehaviorState:resolvedState
                 resolvedAnimationState:resolvedState
                                   mode:@"combat.reaction"];
    [self playTransientState:resolvedState
                    duration:resolvedDuration
                        loop:shouldLoop
    resumeAmbientOnCompletion:!isLaunchedReaction];
}

- (void)previewState:(NSString *)state {
    if (![self.supportedStates containsObject:state]) {
        return;
    }

    [self.ambientTimer invalidate];
    self.ambientTimer = nil;
    [self.transientTimer invalidate];
    self.transientTimer = nil;
    self.hasManualStateOverride = YES;
    [self expandWindowForTransientStateIfNeeded:state];
    [self playStateOnActiveView:state loop:YES];
    self.currentState = state;
    [self emitRuntimeEventWithActionKey:@"manual.preview"
                  fallbackBehaviorState:state
                 resolvedAnimationState:state
                                   mode:@"manual"];
}

- (void)applyGameMovementState:(NSString *)movementState facingRight:(BOOL)facingRight {
    if (self.hasManualStateOverride || self.isDraggingPet) {
        return;
    }

    if (self.combatTransientActive && self.transientTimer != nil) {
        self.hasLastGameMovementFacingRight = YES;
        self.lastGameMovementFacingRight = facingRight;
        BOOL soulArkFacingInverted = [self.profile.metadata[@"灵魂方舟左右方向反转"] boolValue];
        BOOL visualFacingRight = facingRight;
        if (soulArkFacingInverted) {
            visualFacingRight = !visualFacingRight;
        }
        if (self.gameMovementFacingInverted) {
            visualFacingRight = !visualFacingRight;
        }
        [self applyFacingRight:visualFacingRight];
        return;
    }

    [self.ambientTimer invalidate];
    self.ambientTimer = nil;
    [self.transientTimer invalidate];
    self.transientTimer = nil;
    [self restoreWindowAfterTransientExpansionIfNeeded];
    self.hasLastGameMovementFacingRight = YES;
    self.lastGameMovementFacingRight = facingRight;
    BOOL soulArkFacingInverted = [self.profile.metadata[@"灵魂方舟左右方向反转"] boolValue];
    BOOL visualFacingRight = facingRight;
    if (soulArkFacingInverted) {
        visualFacingRight = !visualFacingRight;
    }
    if (self.gameMovementFacingInverted) {
        visualFacingRight = !visualFacingRight;
    }
    [self applyFacingRight:visualFacingRight];

    BOOL isIdle = [movementState isEqualToString:@"idle"];
    if (isIdle) {
        if (self.isGameMovementActive) {
            self.isGameMovementActive = NO;
            [self resumeAmbientBehavior];
        }
        return;
    }

    NSString *resolvedState = [self resolvedAnimationStateForGameMovementState:movementState facingRight:visualFacingRight];
    if (resolvedState.length == 0) {
        return;
    }

    self.isGameMovementActive = YES;
    if (![self.currentState isEqualToString:resolvedState]) {
        BOOL shouldLoop = !([movementState isEqualToString:@"jump"] || [movementState isEqualToString:@"jump-land"]);
        [self playStateOnActiveView:resolvedState loop:shouldLoop];
        self.currentState = resolvedState;
        [self emitRuntimeEventWithActionKey:[NSString stringWithFormat:@"game.move.%@", movementState ?: @"move"]
                      fallbackBehaviorState:movementState
                     resolvedAnimationState:resolvedState
                                       mode:@"game.movement"];
    }
}

- (NSString *)resolvedAnimationStateForGameMovementState:(NSString *)movementState facingRight:(BOOL)facingRight {
    NSArray<NSString *> *candidates = [self animationCandidatesForGameMovementState:movementState facingRight:facingRight];
    BOOL usesSoulArkMovementProfile = [self.profile.metadata[@"灵魂方舟"] boolValue];
    BOOL prefersMovementStateCandidates = usesSoulArkMovementProfile &&
        ([movementState isEqualToString:@"jump"] ||
         [movementState isEqualToString:@"jump-air"] ||
         [movementState isEqualToString:@"jump-land"]);
    if (prefersMovementStateCandidates) {
        for (NSString *candidate in candidates) {
            if ([self.supportedStates containsObject:candidate]) {
                return candidate;
            }
        }
    }

    for (NSString *candidate in candidates) {
        NSString *resolved = [self resolvedAnimationStateForActionKey:[NSString stringWithFormat:@"game.%@", candidate]
                                                fallbackBehaviorState:candidate];
        if (resolved.length > 0) {
            return resolved;
        }
        if ([self.supportedStates containsObject:candidate]) {
            return candidate;
        }
    }
    return self.profile.defaultState;
}

- (NSString *)resolvedAnimationStateForCombatReactionState:(NSString *)combatState launchVector:(CGVector)launchVector {
    BOOL usesSoulArkMovementProfile = [self.profile.metadata[@"灵魂方舟"] boolValue];
    BOOL prefersAirborneMovementStates = usesSoulArkMovementProfile && [combatState isEqualToString:@"combat.launched"];
    if (prefersAirborneMovementStates) {
        NSArray<NSString *> *candidates = [self animationCandidatesForCombatReactionState:combatState launchVector:launchVector];
        for (NSString *candidate in candidates) {
            if ([self.supportedStates containsObject:candidate]) {
                return candidate;
            }
        }
        for (NSString *candidate in candidates) {
            NSString *resolved = [self resolvedAnimationStateForActionKey:[NSString stringWithFormat:@"combat.%@", candidate]
                                                    fallbackBehaviorState:candidate];
            if (resolved.length > 0) {
                return resolved;
            }
        }
    }

    NSArray<NSString *> *actionKeys = [self combatReactionActionKeysForState:combatState];
    for (NSString *actionKey in actionKeys) {
        NSString *resolved = [self resolvedAnimationStateForActionKey:actionKey fallbackBehaviorState:nil];
        if (resolved.length > 0) {
            return resolved;
        }
    }

    NSArray<NSString *> *candidates = [self animationCandidatesForCombatReactionState:combatState launchVector:launchVector];
    for (NSString *candidate in candidates) {
        NSString *resolved = [self resolvedAnimationStateForActionKey:[NSString stringWithFormat:@"combat.%@", candidate]
                                                fallbackBehaviorState:candidate];
        if (resolved.length > 0) {
            return resolved;
        }
        if ([self.supportedStates containsObject:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)combatReactionActionKeysForState:(NSString *)combatState {
    if ([combatState isEqualToString:@"combat.knockeddown"]) {
        return @[@"combat.knockeddown", @"combat.knockdown", @"combat.down", @"combat.fall"];
    }
    if ([combatState isEqualToString:@"combat.launched"]) {
        return @[@"combat.air_up", @"combat.up", @"combat.launched", @"combat.launch", @"combat.air", @"combat.float", @"combat.hitfly"];
    }
    return @[@"combat.hitstun", @"combat.hit", @"combat.hurt", @"combat.damage"];
}

- (NSArray<NSString *> *)animationCandidatesForCombatReactionState:(NSString *)combatState launchVector:(CGVector)launchVector {
    BOOL usesSoulArkMovementProfile = [self.profile.metadata[@"灵魂方舟"] boolValue];
    if ([combatState isEqualToString:@"combat.knockeddown"]) {
        if (usesSoulArkMovementProfile) {
            return @[@"down", @"air_down", @"jump_landing", @"land", @"fall", @"knockdown", @"idle"];
        }
        return @[@"knockdown", @"down", @"fallen", @"fall", @"landing", @"land", @"hurt", @"hit", @"idle"];
    }
    if ([combatState isEqualToString:@"combat.launched"]) {
        if (usesSoulArkMovementProfile) {
            return @[@"air_up", @"up", @"air", @"air_ing", @"jump_ing", @"hit_fly", @"hurt", @"hit", @"idle"];
        }
        if (fabs(launchVector.dy) > fabs(launchVector.dx)) {
            return @[@"launch", @"launched", @"air", @"airborne", @"jumping", @"jump", @"hit_fly", @"hurt", @"hit", @"idle"];
        }
        return @[@"hit_fly", @"launch", @"launched", @"air", @"hurt", @"hit", @"idle"];
    }
    if (usesSoulArkMovementProfile) {
        return @[@"hit", @"hurt", @"damage", @"be_hit", @"stun", @"idle"];
    }
    return @[@"hitstun", @"hit", @"hurt", @"damage", @"stagger", @"impact", @"idle"];
}

- (NSArray<NSString *> *)animationCandidatesForGameMovementState:(NSString *)movementState facingRight:(BOOL)facingRight {
    NSString *directionalRunning = facingRight ? @"running-right" : @"running-left";
    NSString *directionalRun = facingRight ? @"run-right" : @"run-left";
    BOOL usesSoulArkMovementProfile = [self.profile.metadata[@"灵魂方舟"] boolValue];
    if ([movementState isEqualToString:@"jump"]) {
        if (usesSoulArkMovementProfile) {
            return @[@"jump", @"jump_start", @"jumpstart", @"air_up", @"up", @"idle"];
        }
        return @[@"jump", @"jumping", @"jump_start", @"jumpstart", directionalRunning, directionalRun, @"run", @"running", @"idle"];
    }
    if ([movementState isEqualToString:@"jump-air"]) {
        if (usesSoulArkMovementProfile) {
            return @[@"jump_ing", @"air_ing", @"air", @"jumping", @"idle"];
        }
        return @[@"jumping", @"jump", directionalRunning, directionalRun, @"run", @"running", @"idle"];
    }
    if ([movementState isEqualToString:@"jump-land"]) {
        if (usesSoulArkMovementProfile) {
            return @[@"jump_landing", @"jump_land", @"landing", @"land", @"air_down", @"down", @"idle"];
        }
        return @[@"landing", @"land", @"jump_landing", @"idle"];
    }
    if ([movementState isEqualToString:@"fly"]) {
        return @[@"fly", @"flying", @"hover", @"air_ing", @"jump_ing", directionalRunning, directionalRun, @"run", @"running", @"idle"];
    }
    if ([movementState isEqualToString:@"run"]) {
        return @[directionalRunning, directionalRun, @"run", @"running", @"walk", @"walking", @"idle"];
    }
    if ([movementState isEqualToString:@"walk"]) {
        return @[@"walk", @"walking", directionalRunning, directionalRun, @"run", @"running", @"idle"];
    }
    return @[@"idle"];
}

- (void)expandWindowForTransientStateIfNeeded:(NSString *)state {
    if (self.spinePetView == nil || state.length == 0) {
        return;
    }

    NSSize normalSize = self.normalWindowSize;
    if (normalSize.width <= 0.0 || normalSize.height <= 0.0) {
        normalSize = self.frame.size;
        self.normalWindowSize = normalSize;
    }

    NSSize recommendedSize = [self.spinePetView recommendedWindowSizeForState:state normalViewportSize:normalSize];
    recommendedSize.width = MAX(normalSize.width, recommendedSize.width);
    recommendedSize.height = MAX(normalSize.height, recommendedSize.height);
    NSLog(@"[DesktopPet] Transient window sizing state=%@ normal=%.1fx%.1f recommended=%.1fx%.1f",
          state,
          normalSize.width,
          normalSize.height,
          recommendedSize.width,
          recommendedSize.height);
    if (recommendedSize.width <= normalSize.width + 1.0 &&
        recommendedSize.height <= normalSize.height + 1.0) {
        [self.petView recordProfilingWindowEventWithName:@"window.expand.skip"];
        [self restoreWindowAfterTransientExpansionIfNeeded];
        [self updateActiveRendererContentLayoutRectForFrame:self.frame normalFrame:self.frame];
        return;
    }

    NSRect normalFrame = self.usingTransientExpandedWindow ? self.normalFrameBeforeTransientExpansion : self.frame;
    normalFrame.size = normalSize;
    self.normalFrameBeforeTransientExpansion = normalFrame;
    self.usingTransientExpandedWindow = YES;

    CGFloat extraWidth = recommendedSize.width - normalSize.width;
    CGFloat extraHeight = recommendedSize.height - normalSize.height;
    NSRect expandedFrame = NSMakeRect(normalFrame.origin.x - (extraWidth * 0.5),
                                      normalFrame.origin.y - (extraHeight * 0.5),
                                      recommendedSize.width,
                                      recommendedSize.height);
    if (!NSEqualRects(self.frame, expandedFrame)) {
        [self.petView recordProfilingWindowEventWithName:@"window.expand.apply"];
        [self setFrame:expandedFrame display:YES];
    }
    [self layoutControlFocusBadge];

    NSRect layoutRect = NSMakeRect(extraWidth * 0.5,
                                   extraHeight * 0.5,
                                   normalSize.width,
                                   normalSize.height);
    self.spinePetView.contentLayoutRect = layoutRect;
}

- (void)restoreWindowAfterTransientExpansionIfNeeded {
    if (!self.usingTransientExpandedWindow) {
        [self updateActiveRendererContentLayoutRectForFrame:self.frame normalFrame:self.frame];
        return;
    }

    NSRect normalFrame = self.normalFrameBeforeTransientExpansion;
    if (normalFrame.size.width <= 0.0 || normalFrame.size.height <= 0.0) {
        normalFrame = self.frame;
        normalFrame.size = self.normalWindowSize;
    }
    self.usingTransientExpandedWindow = NO;
    if (!NSEqualRects(self.frame, normalFrame)) {
        [self.petView recordProfilingWindowEventWithName:@"window.restore.apply"];
        [self setFrame:normalFrame display:YES];
    }
    [self layoutControlFocusBadge];
    [self updateActiveRendererContentLayoutRectForFrame:normalFrame normalFrame:normalFrame];
}

- (void)updateActiveRendererContentLayoutRectForFrame:(NSRect)frame normalFrame:(NSRect)normalFrame {
    (void)normalFrame;
    [self layoutControlFocusBadge];
    if (self.spinePetView != nil) {
        self.spinePetView.contentLayoutRect = NSMakeRect(0.0, 0.0, frame.size.width, frame.size.height);
    }
}

- (void)updateDragFeedbackForHorizontalDelta:(CGFloat)deltaX {
    if (!self.supportsDesktopPetBehavior || self.hasManualStateOverride) {
        return;
    }

    NSString *resolvedState = [self resolvedAnimationStateForActionKey:PETActionDragIdle fallbackBehaviorState:@"waiting"] ?: self.profile.defaultState;
    if (deltaX > 1.0) {
        resolvedState = [self resolvedAnimationStateForActionKey:PETActionDragMoveRight fallbackBehaviorState:@"running-right"] ?: resolvedState;
    } else if (deltaX < -1.0) {
        resolvedState = [self resolvedAnimationStateForActionKey:PETActionDragMoveLeft fallbackBehaviorState:@"running-left"] ?: resolvedState;
    }
    if (![self.currentState isEqualToString:resolvedState]) {
        [self playStateOnActiveView:resolvedState loop:YES];
        self.currentState = resolvedState;
        NSString *actionKey = PETActionDragIdle;
        if (deltaX > 1.0) {
            actionKey = PETActionDragMoveRight;
        } else if (deltaX < -1.0) {
            actionKey = PETActionDragMoveLeft;
        }
        [self emitRuntimeEventWithActionKey:actionKey
                      fallbackBehaviorState:@"waiting"
                     resolvedAnimationState:resolvedState
                                       mode:@"drag"];
    }
}

- (void)scheduleNextAmbientVariant {
    [self.ambientTimer invalidate];
    if (!self.supportsDesktopPetBehavior || self.hasManualStateOverride || self.isDraggingPet) {
        self.ambientTimer = nil;
        return;
    }

    NSTimeInterval delay = 12.0 + ((NSTimeInterval)arc4random_uniform(10000) / 1000.0);
    __weak typeof(self) weakSelf = self;
    self.ambientTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                        repeats:NO
                                                          block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        weakSelf.ambientTimer = nil;
        [weakSelf playRandomAmbientVariant];
    }];
}

- (void)playRandomAmbientVariant {
    if (!self.supportsDesktopPetBehavior || self.hasManualStateOverride || self.isDraggingPet) {
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *variants = [NSMutableArray array];
    if ([self resolvedAnimationStateForActionKey:PETActionDragIdle fallbackBehaviorState:@"waiting"].length > 0) {
        [variants addObject:@{@"action": PETActionDragIdle, @"fallback": @"waiting", @"duration": @1.6}];
    }
    if ([self resolvedAnimationStateForActionKey:PETActionTapSecondary fallbackBehaviorState:@"review"].length > 0) {
        [variants addObject:@{@"action": PETActionTapSecondary, @"fallback": @"review", @"duration": @1.8}];
    }

    if (variants.count == 0) {
        [self scheduleNextAmbientVariant];
        return;
    }

    NSUInteger index = (NSUInteger)arc4random_uniform((uint32_t)variants.count);
    NSDictionary<NSString *, id> *variant = variants[index];
    [self playTransientActionKey:variant[@"action"]
           fallbackBehaviorState:variant[@"fallback"]
                        duration:[variant[@"duration"] doubleValue]];
}

@end
