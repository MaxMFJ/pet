#import "PETCombatStateComponent.h"

#import "PETAttackDefinition.h"
#import "PETHitResult.h"

NSString * const PETCombatStateIdle = @"combat.idle";
NSString * const PETCombatStateAttacking = @"combat.attacking";
NSString * const PETCombatStateHitStun = @"combat.hitstun";
NSString * const PETCombatStateLaunched = @"combat.launched";
NSString * const PETCombatStateKnockedDown = @"combat.knockeddown";

@interface PETCombatStateComponent ()

@property (nonatomic, copy) NSString *currentState;
@property (nonatomic, assign) NSTimeInterval stateTimeRemaining;
@property (nonatomic, assign, getter=isControlLocked) BOOL controlLocked;
@property (nonatomic, copy, nullable) NSString *currentAttackIdentifier;
@property (nonatomic, copy, nullable) NSString *lastHitIdentifier;

@end

@implementation PETCombatStateComponent

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentState = [PETCombatStateIdle copy];
    }
    return self;
}

- (BOOL)beginAttackWithDefinition:(PETAttackDefinition *)attackDefinition {
    if (attackDefinition == nil || (self.isControlLocked && ![self.currentState isEqualToString:PETCombatStateAttacking])) {
        return NO;
    }

    self.currentState = PETCombatStateAttacking;
    self.stateTimeRemaining = attackDefinition.startupDuration + attackDefinition.activeDuration + attackDefinition.recoveryDuration;
    self.controlLocked = YES;
    self.currentAttackIdentifier = attackDefinition.attackIdentifier;
    return YES;
}

- (BOOL)advanceTime:(NSTimeInterval)deltaTime {
    NSTimeInterval clampedDelta = MAX(0.0, deltaTime);
    if (self.stateTimeRemaining > 0.0) {
        self.stateTimeRemaining = MAX(0.0, self.stateTimeRemaining - clampedDelta);
    }
    if (self.stateTimeRemaining > 0.0) {
        return NO;
    }
    if ([self.currentState isEqualToString:PETCombatStateIdle] && self.currentAttackIdentifier.length == 0) {
        return NO;
    }

    self.currentState = PETCombatStateIdle;
    self.controlLocked = NO;
    self.currentAttackIdentifier = nil;
    return YES;
}

- (BOOL)clearAttackIdentifierIfMatches:(NSString *)attackIdentifier {
    if (attackIdentifier.length == 0 || ![self.currentAttackIdentifier isEqualToString:attackIdentifier]) {
        return NO;
    }
    self.currentAttackIdentifier = nil;
    self.currentState = PETCombatStateIdle;
    self.stateTimeRemaining = 0.0;
    self.controlLocked = NO;
    return YES;
}

- (BOOL)applyHitResult:(PETHitResult *)hitResult {
    if (hitResult == nil) {
        return NO;
    }

    self.lastHitIdentifier = hitResult.hitIdentifier;
    self.currentAttackIdentifier = nil;
    NSString *resolvedCombatState = hitResult.combatState;
    if (resolvedCombatState.length == 0) {
        resolvedCombatState = hitResult.causesKnockdown ? PETCombatStateKnockedDown : (fabs(hitResult.launchVector.dy) > 1.0 ? PETCombatStateLaunched : PETCombatStateHitStun);
    }

    if ([resolvedCombatState isEqualToString:PETCombatStateKnockedDown] || hitResult.causesKnockdown) {
        self.currentState = PETCombatStateKnockedDown;
        self.stateTimeRemaining = MAX(0.0, hitResult.knockdownDuration);
    } else if ([resolvedCombatState isEqualToString:PETCombatStateLaunched]) {
        self.currentState = PETCombatStateLaunched;
        self.stateTimeRemaining = MAX(hitResult.hitStunDuration, 0.18);
    } else {
        self.currentState = PETCombatStateHitStun;
        self.stateTimeRemaining = MAX(0.0, hitResult.hitStunDuration);
    }
    self.controlLocked = YES;
    return YES;
}

- (NSDictionary<NSString *,id> *)serializedState {
    return @{
        @"currentState": self.currentState ?: PETCombatStateIdle,
        @"stateTimeRemaining": @(self.stateTimeRemaining),
        @"controlLocked": @(self.isControlLocked),
        @"currentAttackIdentifier": self.currentAttackIdentifier ?: @"",
        @"lastHitIdentifier": self.lastHitIdentifier ?: @""
    };
}

- (void)restoreFromSerializedState:(NSDictionary<NSString *,id> *)state {
    NSString *currentState = [state[@"currentState"] isKindOfClass:NSString.class] ? state[@"currentState"] : nil;
    self.currentState = currentState.length > 0 ? currentState : PETCombatStateIdle;
    self.stateTimeRemaining = MAX(0.0, [state[@"stateTimeRemaining"] doubleValue]);
    self.controlLocked = [state[@"controlLocked"] boolValue];
    NSString *attackIdentifier = [state[@"currentAttackIdentifier"] isKindOfClass:NSString.class] ? state[@"currentAttackIdentifier"] : nil;
    self.currentAttackIdentifier = attackIdentifier.length > 0 ? attackIdentifier : nil;
    NSString *lastHitIdentifier = [state[@"lastHitIdentifier"] isKindOfClass:NSString.class] ? state[@"lastHitIdentifier"] : nil;
    self.lastHitIdentifier = lastHitIdentifier.length > 0 ? lastHitIdentifier : nil;
}

- (NSDictionary<NSString *,id> *)debugSnapshot {
    return @{
        @"currentState": self.currentState ?: PETCombatStateIdle,
        @"stateTimeRemaining": @(self.stateTimeRemaining),
        @"controlLocked": @(self.isControlLocked),
        @"currentAttackIdentifier": self.currentAttackIdentifier ?: @"",
        @"lastHitIdentifier": self.lastHitIdentifier ?: @""
    };
}

@end
