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

NSNotificationName const PETPetWindowDidEmitRuntimeEventNotification = @"PETPetWindowDidEmitRuntimeEventNotification";
NSString * const PETPetWindowProfileIdentifierUserInfoKey = @"PETPetWindowProfileIdentifierUserInfoKey";
NSString * const PETPetWindowActionKeyUserInfoKey = @"PETPetWindowActionKeyUserInfoKey";
NSString * const PETPetWindowFallbackBehaviorStateUserInfoKey = @"PETPetWindowFallbackBehaviorStateUserInfoKey";
NSString * const PETPetWindowResolvedAnimationStateUserInfoKey = @"PETPetWindowResolvedAnimationStateUserInfoKey";
NSString * const PETPetWindowRuntimeModeUserInfoKey = @"PETPetWindowRuntimeModeUserInfoKey";

@interface PETPetWindow ()

@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, strong, nullable) PETPetView *petView;
@property (nonatomic, strong, nullable) PETSpineMetalView *spinePetView;
@property (nonatomic, assign) BOOL isDraggingPet;
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

- (BOOL)activeRendererContainsInteractiveContentAtPoint:(NSPoint)point {
    if (self.spinePetView != nil) {
        return [self.spinePetView containsInteractiveContentAtPoint:point];
    }
    if (self.petView != nil) {
        return [self.petView containsInteractiveContentAtPoint:point];
    }
    return NO;
}

- (BOOL)activeRendererContainsDraggableContentAtPoint:(NSPoint)point {
    if (self.spinePetView != nil) {
        return [self.spinePetView containsDraggableContentAtPoint:point];
    }
    if (self.petView != nil) {
        return [self.petView containsDraggableContentAtPoint:point];
    }
    return NO;
}

- (nullable NSString *)activeRendererInteractivePartIdentifierAtPoint:(NSPoint)point {
    if (self.spinePetView != nil) {
        return [self.spinePetView interactivePartIdentifierAtPoint:point];
    }
    return nil;
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

    if (self.supportsDesktopPetBehavior) {
        [self playTransientActionKey:PETActionDragRelease fallbackBehaviorState:@"jumping" duration:0.45];
    } else {
        [self resumeAmbientBehavior];
    }
}

- (void)playStateOnActiveView:(NSString *)state loop:(BOOL)loop {
    if (self.spinePetView != nil) {
        [self.spinePetView playState:state loop:loop];
        return;
    }
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

- (instancetype)initWithProfile:(PETPetProfile *)profile origin:(NSPoint)origin {
    NSRect frame = NSMakeRect(origin.x, origin.y, profile.canvasSize.width, profile.canvasSize.height);
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        _profile = profile;
        _petScale = 1.0;
        _facingRight = YES;
        _clickThroughEnabled = NO;
        _anchorOrigin = origin;
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

        self.contentView = [self activePetRendererView];
        [self applyFacingRight:self.facingRight];
        if (_spinePetView != nil) {
            [_spinePetView startAnimating];
        } else {
            [_petView startAnimating];
        }
        [self startMousePassThroughMonitoring];
        self.acceptsMouseMovedEvents = YES;
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
    [self.transientTimer invalidate];
    self.hasManualStateOverride = NO;
    NSString *resolvedState = [self resolvedAnimationStateForBehaviorState:state] ?: state;
    [self playStateOnActiveView:resolvedState loop:NO];
    self.currentState = resolvedState;

    __weak typeof(self) weakSelf = self;
    self.transientTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                          repeats:NO
                                                            block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        weakSelf.transientTimer = nil;
        [weakSelf resumeAmbientBehavior];
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

    NSSize baseSize = self.profile.canvasSize;
    NSSize scaledSize = NSMakeSize(baseSize.width * clampedScale, baseSize.height * clampedScale);
    NSRect frame = self.frame;
    self.anchorOrigin = frame.origin;
    frame.size = scaledSize;
    frame.origin = self.anchorOrigin;
    [self setFrame:frame display:YES];
}

- (void)applyFacingRight:(BOOL)facingRight {
    _facingRight = facingRight;
    self.petView.facingRight = facingRight;
    self.spinePetView.facingRight = facingRight;
    [self.petView setNeedsDisplay:YES];
    [self.spinePetView setNeedsDisplay:YES];
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

    [self handleSecondaryInteraction];
    NSMenu *menu = [self.contentView menuForEvent:event];
    if (menu != nil) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:self.contentView];
    }
}

- (void)resumeAmbientBehavior {
    [self.transientTimer invalidate];
    self.transientTimer = nil;
    self.hasManualStateOverride = NO;

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

- (void)previewState:(NSString *)state {
    if (![self.supportedStates containsObject:state]) {
        return;
    }

    [self.ambientTimer invalidate];
    self.ambientTimer = nil;
    [self.transientTimer invalidate];
    self.transientTimer = nil;
    self.hasManualStateOverride = YES;
    [self playStateOnActiveView:state loop:YES];
    self.currentState = state;
    [self emitRuntimeEventWithActionKey:@"manual.preview"
                  fallbackBehaviorState:state
                 resolvedAnimationState:state
                                   mode:@"manual"];
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
