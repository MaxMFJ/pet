#import "PETGamePresentationBridge.h"

#import "../Core/PETGameEvent.h"
#import "../../UI/PETPetWindow.h"

static NSTimeInterval const PETGameHitReactionPresentationDelay = 0.5;

@implementation PETGamePresentationBridge

- (void)logMovementContext:(NSDictionary<NSString *, id> *)context
             petIdentifier:(NSString *)petIdentifier
                    source:(NSString *)source
                     label:(NSString *)label {
    NSDictionary<NSString *, id> *position = [context[@"position"] isKindOfClass:NSDictionary.class] ? context[@"position"] : nil;
    NSDictionary<NSString *, id> *velocity = [context[@"velocity"] isKindOfClass:NSDictionary.class] ? context[@"velocity"] : nil;
    NSString *movementState = [context[@"movementState"] isKindOfClass:NSString.class] ? context[@"movementState"] : @"";
    NSNumber *facingRight = [context[@"facingRight"] isKindOfClass:NSNumber.class] ? context[@"facingRight"] : nil;
    NSLog(@"[DesktopPet] %@ pet=%@ source=%@ pos=(%.2f, %.2f) vel=(%.2f, %.2f) facingRight=%@ movementState=%@",
          label ?: @"Movement",
          petIdentifier ?: @"",
          source ?: @"",
          [position[@"x"] doubleValue],
          [position[@"y"] doubleValue],
          [velocity[@"dx"] doubleValue],
          [velocity[@"dy"] doubleValue],
          facingRight != nil ? (facingRight.boolValue ? @"YES" : @"NO") : @"<nil>",
          movementState ?: @"");
}

- (void)applyGameEvents:(NSArray<PETGameEvent *> *)events {
    for (PETGameEvent *event in events) {
        PETPetWindow *window = self.windowProvider != nil ? self.windowProvider(event.petIdentifier) : nil;
        if (window == nil) {
            continue;
        }

        if ([event.eventType isEqualToString:PETGameEventAttackStarted]) {
            [self applyCombatPresentationForEvent:event window:window];
            continue;
        }

        if ([event.eventType isEqualToString:PETGameEventAttackHit]) {
            [self applyHitReactionPresentationForEvent:event window:window];
            continue;
        }

        if ([event.eventType isEqualToString:PETGameEventCombatStateChanged]) {
            [self applyCombatStatePresentationForEvent:event window:window];
            continue;
        }

        if ([event.eventType isEqualToString:PETGameEventAttackEnded]) {
            [self applyCombatEndPresentationForEvent:event window:window];
            continue;
        }

        if (![event.eventType hasPrefix:@"game.move."]) {
            continue;
        }
        NSDictionary<NSString *, id> *position = [event.context[@"position"] isKindOfClass:NSDictionary.class] ? event.context[@"position"] : nil;
        if (position == nil) {
            continue;
        }
        [self logMovementContext:event.context
                   petIdentifier:event.petIdentifier
                          source:event.source
                           label:@"Movement event"];
        NSPoint origin = NSMakePoint([position[@"x"] doubleValue], [position[@"y"] doubleValue]);
        origin = [window presentedFrameOriginForStableOrigin:origin];
        origin = [window constrainedFrameOriginForVisibleContentFromOrigin:origin];
        BOOL shouldAllowOverlapForPresentation = [event.source isEqualToString:@"game.skill.motion"];
        NSDictionary<NSString *, id> *collisionSnapshot = shouldAllowOverlapForPresentation || self.movementCollisionEvaluator == nil
            ? nil
            : self.movementCollisionEvaluator(event.petIdentifier, origin, 3.0);
        if (shouldAllowOverlapForPresentation || collisionSnapshot.count == 0) {
            [window setFrameOrigin:origin];
        }

        NSNumber *facingRight = [event.context[@"facingRight"] isKindOfClass:NSNumber.class] ? event.context[@"facingRight"] : nil;
        if (facingRight != nil) {
            [window applyFacingRight:facingRight.boolValue];
        }
        if ([self shouldSuppressMovementPresentationForPetIdentifier:event.petIdentifier]) {
            continue;
        }

        NSString *movementState = [event.context[@"movementState"] isKindOfClass:NSString.class] ? event.context[@"movementState"] : nil;
        if (movementState.length > 0) {
            [window applyGameMovementState:movementState facingRight:facingRight != nil ? facingRight.boolValue : window.facingRight];
        }
    }
}

- (BOOL)shouldSuppressMovementPresentationForPetIdentifier:(NSString *)petIdentifier {
    if (petIdentifier.length == 0 || self.combatSnapshotProvider == nil) {
        return NO;
    }

    NSDictionary<NSString *, id> *combatSnapshot = self.combatSnapshotProvider(petIdentifier);
    NSDictionary<NSString *, id> *activeSkill = [combatSnapshot[@"activeSkill"] isKindOfClass:NSDictionary.class] ? combatSnapshot[@"activeSkill"] : nil;
    if (activeSkill.count == 0) {
        return NO;
    }

    NSString *skillIdentifier = [activeSkill[@"skillId"] isKindOfClass:NSString.class] ? activeSkill[@"skillId"] : nil;
    if (skillIdentifier.length == 0 || [activeSkill[@"finished"] boolValue]) {
        return NO;
    }

    if (activeSkill[@"allowMovementDuringCast"] != nil) {
        return ![activeSkill[@"allowMovementDuringCast"] boolValue];
    }

    return [activeSkill[@"movementLock"] boolValue];
}

- (void)applyCombatPresentationForEvent:(PETGameEvent *)event window:(PETPetWindow *)window {
    NSDictionary<NSString *, id> *context = event.context ?: @{};
    NSString *animationState = [context[@"animationState"] isKindOfClass:NSString.class] ? context[@"animationState"] : nil;
    NSString *actionKey = [context[@"actionKey"] isKindOfClass:NSString.class] ? context[@"actionKey"] : nil;
    NSDictionary<NSString *, id> *movement = [context[@"movement"] isKindOfClass:NSDictionary.class] ? context[@"movement"] : nil;
    if (movement.count > 0) {
        [self logMovementContext:movement
                   petIdentifier:event.petIdentifier
                          source:event.source
                           label:@"Combat start"];
    }

    NSTimeInterval duration = [context[@"phaseDuration"] doubleValue];
    if (duration <= 0.0) {
        duration = [context[@"activeDuration"] doubleValue];
    }
    if (duration <= 0.0) {
        duration = 0.6;
    }

    [window playCombatPresentationWithAnimationState:animationState
                                           actionKey:actionKey
                                            duration:duration];
}

- (void)applyCombatStatePresentationForEvent:(PETGameEvent *)event window:(PETPetWindow *)window {
    NSDictionary<NSString *, id> *context = event.context ?: @{};
    NSDictionary<NSString *, id> *movement = [context[@"movement"] isKindOfClass:NSDictionary.class] ? context[@"movement"] : nil;
    if (movement.count > 0) {
        [self logMovementContext:movement
                   petIdentifier:event.petIdentifier
                          source:event.source
                           label:@"Combat state"];
    }
    NSDictionary<NSString *, id> *activeSkill = [context[@"activeSkill"] isKindOfClass:NSDictionary.class] ? context[@"activeSkill"] : nil;
    if (activeSkill.count > 0 && ![activeSkill[@"finished"] boolValue]) {
        NSString *animationState = [activeSkill[@"animationState"] isKindOfClass:NSString.class] ? activeSkill[@"animationState"] : nil;
        if (animationState.length > 0 && [window.currentState isEqualToString:animationState]) {
            return;
        }
        NSTimeInterval duration = [activeSkill[@"phaseDuration"] doubleValue];
        if (duration <= 0.0) {
            duration = 0.2;
        }
        [window playCombatPresentationWithAnimationState:animationState
                                               actionKey:nil
                                                duration:duration];
        return;
    }

    NSDictionary<NSString *, id> *activeAttack = [context[@"activeAttack"] isKindOfClass:NSDictionary.class] ? context[@"activeAttack"] : nil;
    NSString *animationState = [activeAttack[@"animationState"] isKindOfClass:NSString.class] ? activeAttack[@"animationState"] : nil;
    if (animationState.length == 0) {
        return;
    }
    if ([window.currentState isEqualToString:animationState]) {
        return;
    }

    NSTimeInterval duration = [activeAttack[@"activeDuration"] doubleValue];
    if (duration <= 0.0) {
        duration = 0.2;
    }
    [window playCombatPresentationWithAnimationState:animationState
                                           actionKey:nil
                                            duration:duration];
}

- (void)applyHitReactionPresentationForEvent:(PETGameEvent *)event window:(PETPetWindow *)window {
    NSDictionary<NSString *, id> *context = event.context ?: @{};
    NSString *targetPetIdentifier = [context[@"targetPetIdentifier"] isKindOfClass:NSString.class] ? context[@"targetPetIdentifier"] : nil;
    if (targetPetIdentifier.length == 0 || ![targetPetIdentifier isEqualToString:event.petIdentifier]) {
        return;
    }

    BOOL causesKnockdown = [context[@"causesKnockdown"] boolValue];
    NSDictionary<NSString *, id> *launchVectorDictionary = [context[@"launchVector"] isKindOfClass:NSDictionary.class] ? context[@"launchVector"] : nil;
    CGVector launchVector = CGVectorMake([launchVectorDictionary[@"dx"] doubleValue],
                                         [launchVectorDictionary[@"dy"] doubleValue]);
    NSString *combatState = [context[@"combatState"] isKindOfClass:NSString.class] ? context[@"combatState"] : nil;
    NSString *reactionState = [context[@"reactionState"] isKindOfClass:NSString.class] ? context[@"reactionState"] : nil;
    NSString *reactionAnimationState = [context[@"reactionAnimationState"] isKindOfClass:NSString.class] ? context[@"reactionAnimationState"] : nil;
    if (combatState.length == 0) {
        combatState = causesKnockdown ? @"combat.knockeddown" : (fabs(launchVector.dy) > 1.0 ? @"combat.launched" : @"combat.hitstun");
    }
    NSTimeInterval duration = causesKnockdown ? [context[@"knockdownDuration"] doubleValue] : [context[@"hitStunDuration"] doubleValue];
    if (duration <= 0.0) {
        duration = causesKnockdown ? 0.45 : 0.2;
    }

    __weak PETPetWindow *weakWindow = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PETGameHitReactionPresentationDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        PETPetWindow *strongWindow = weakWindow;
        if (strongWindow == nil) {
            return;
        }
        [strongWindow playHitReactionForCombatState:combatState
                                      reactionState:reactionState
                            preferredAnimationState:reactionAnimationState
                                       launchVector:launchVector
                                           duration:duration];
    });
}

- (void)applyCombatEndPresentationForEvent:(PETGameEvent *)event window:(PETPetWindow *)window {
    if ([event.source isEqualToString:@"game.skill.cancel"]) {
        [window resumeAmbientBehavior];
    }
}

@end
