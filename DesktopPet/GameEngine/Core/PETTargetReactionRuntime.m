#import "PETTargetReactionRuntime.h"

#import "../Combat/PETCombatStateComponent.h"
#import "../Combat/PETHitResult.h"

NSString * const PETReactionStateNone = @"reaction.none";
NSString * const PETReactionStateHitStun = @"reaction.hitstun";
NSString * const PETReactionStateLaunched = @"reaction.launched";
NSString * const PETReactionStateAirHold = @"reaction.air_hold";
NSString * const PETReactionStateKnockdown = @"reaction.knockdown";
NSString * const PETReactionStateGrabbed = @"reaction.grabbed";

@interface PETTargetReactionRuntime ()

@property (nonatomic, copy) NSString *currentReactionState;
@property (nonatomic, copy, nullable) NSString *currentReactionAnimationState;
@property (nonatomic, copy, nullable) NSString *lastReactionIdentifier;
@property (nonatomic, assign) NSTimeInterval reactionTimeRemaining;
@property (nonatomic, assign) CGFloat currentGravityScale;
@property (nonatomic, assign) BOOL locksHorizontalMotion;
@property (nonatomic, assign) BOOL locksVerticalMotion;

@end

@implementation PETTargetReactionRuntime

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentReactionState = [PETReactionStateNone copy];
        _currentGravityScale = 1.0;
    }
    return self;
}

- (BOOL)applyHitResult:(PETHitResult *)hitResult
 toCombatStateComponent:(PETCombatStateComponent *)combatStateComponent {
    if (hitResult == nil || combatStateComponent == nil) {
        return NO;
    }

    BOOL didApply = [combatStateComponent applyHitResult:hitResult];
    if (!didApply) {
        return NO;
    }

    self.currentReactionState = [self semanticReactionStateForHitResult:hitResult combatStateComponent:combatStateComponent];
    self.currentReactionAnimationState = hitResult.reactionAnimationState.length > 0 ? hitResult.reactionAnimationState : nil;
    self.lastReactionIdentifier = hitResult.reactionIdentifier.length > 0 ? hitResult.reactionIdentifier : nil;
    self.reactionTimeRemaining = MAX(0.0, combatStateComponent.stateTimeRemaining);
    self.currentGravityScale = hitResult.reactionGravityScale > 0.0 ? hitResult.reactionGravityScale : 1.0;
    self.locksHorizontalMotion = hitResult.reactionLocksHorizontal;
    self.locksVerticalMotion = hitResult.reactionLocksVertical;
    return YES;
}

- (void)syncWithCombatStateComponent:(PETCombatStateComponent *)combatStateComponent {
    if (combatStateComponent == nil) {
        return;
    }

    self.reactionTimeRemaining = MAX(0.0, combatStateComponent.stateTimeRemaining);
    if ([combatStateComponent.currentState isEqualToString:PETCombatStateIdle]) {
        self.currentReactionState = PETReactionStateNone;
        self.currentReactionAnimationState = nil;
        self.lastReactionIdentifier = nil;
        self.currentGravityScale = 1.0;
        self.locksHorizontalMotion = NO;
        self.locksVerticalMotion = NO;
    } else if ([self.currentReactionState isEqualToString:PETReactionStateNone]) {
        self.currentReactionState = [self semanticReactionStateForCombatState:combatStateComponent.currentState];
    }
}

- (NSDictionary<NSString *, id> *)serializedState {
    return @{
        @"currentReactionState": self.currentReactionState ?: PETReactionStateNone,
        @"reactionAnimationState": self.currentReactionAnimationState ?: @"",
        @"reactionIdentifier": self.lastReactionIdentifier ?: @"",
        @"reactionTimeRemaining": @(self.reactionTimeRemaining),
        @"gravityScale": @(self.currentGravityScale),
        @"lockHorizontal": @(self.locksHorizontalMotion),
        @"lockVertical": @(self.locksVerticalMotion)
    };
}

- (void)restoreFromSerializedState:(NSDictionary<NSString *,id> *)state {
    NSString *currentReactionState = [state[@"currentReactionState"] isKindOfClass:NSString.class] ? state[@"currentReactionState"] : nil;
    NSString *reactionAnimationState = [state[@"reactionAnimationState"] isKindOfClass:NSString.class] ? state[@"reactionAnimationState"] : nil;
    NSString *reactionIdentifier = [state[@"reactionIdentifier"] isKindOfClass:NSString.class] ? state[@"reactionIdentifier"] : nil;
    NSNumber *gravityScale = [state[@"gravityScale"] respondsToSelector:@selector(doubleValue)] ? state[@"gravityScale"] : nil;

    self.currentReactionState = currentReactionState.length > 0 ? currentReactionState : PETReactionStateNone;
    self.currentReactionAnimationState = reactionAnimationState.length > 0 ? reactionAnimationState : nil;
    self.lastReactionIdentifier = reactionIdentifier.length > 0 ? reactionIdentifier : nil;
    self.reactionTimeRemaining = MAX(0.0, [state[@"reactionTimeRemaining"] doubleValue]);
    self.currentGravityScale = gravityScale != nil ? MAX(0.0, gravityScale.doubleValue) : 1.0;
    self.locksHorizontalMotion = [state[@"lockHorizontal"] boolValue];
    self.locksVerticalMotion = [state[@"lockVertical"] boolValue];
}

- (NSDictionary<NSString *,id> *)debugSnapshot {
    return @{
        @"currentReactionState": self.currentReactionState ?: @"",
        @"reactionSemanticState": self.currentReactionState ?: @"",
        @"reactionAnimationState": self.currentReactionAnimationState ?: @"",
        @"reactionIdentifier": self.lastReactionIdentifier ?: @"",
        @"reactionTimeRemaining": @(self.reactionTimeRemaining),
        @"gravityScale": @(self.currentGravityScale),
        @"lockHorizontal": @(self.locksHorizontalMotion),
        @"lockVertical": @(self.locksVerticalMotion)
    };
}

- (NSString *)semanticReactionStateForHitResult:(PETHitResult *)hitResult
                           combatStateComponent:(PETCombatStateComponent *)combatStateComponent {
    if (hitResult.reactionState.length > 0) {
        return hitResult.reactionState;
    }
    return [self semanticReactionStateForCombatState:hitResult.combatState.length > 0 ? hitResult.combatState : combatStateComponent.currentState];
}

- (NSString *)semanticReactionStateForCombatState:(NSString *)combatState {
    if ([combatState isEqualToString:PETCombatStateKnockedDown]) {
        return PETReactionStateKnockdown;
    }
    if ([combatState isEqualToString:PETCombatStateLaunched]) {
        return PETReactionStateLaunched;
    }
    if ([combatState isEqualToString:PETCombatStateHitStun]) {
        return PETReactionStateHitStun;
    }
    return PETReactionStateNone;
}

@end
