#import "PETGameSession.h"

#import "../../Models/PETPetProfile.h"
#import "../../Services/PETCharacterRuntimeController.h"
#import "../Combat/PETAttackDefinition.h"
#import "../Combat/PETCombatStateComponent.h"
#import "../Combat/PETHitResult.h"
#import "../Input/PETGameInputState.h"
#import "../Movement/PETMovementComponent.h"
#import "../Movement/PETMovementSystem.h"
#import "../Skill/PETActiveSkillInstance.h"
#import "../Skill/PETSkillDefinition.h"
#import "../Skill/PETSkillLibrary.h"
#import "../Skill/PETSkillPhase.h"
#import "PETGameCommand.h"
#import "PETGameEvent.h"

@interface PETGameSession ()

@property (nonatomic, copy) NSString *petIdentifier;
@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, weak) PETCharacterRuntimeController *runtimeController;
@property (nonatomic, assign, getter=isPaused) BOOL paused;
@property (nonatomic, assign) NSUInteger tickCount;
@property (nonatomic, strong) NSDate *lastTickDate;
@property (nonatomic, strong) NSMutableArray<PETGameCommand *> *pendingCommands;
@property (nonatomic, copy) NSString *lastPauseReason;
@property (nonatomic, strong) PETGameInputState *inputState;
@property (nonatomic, strong) PETMovementComponent *movementComponent;
@property (nonatomic, strong) PETMovementSystem *movementSystem;
@property (nonatomic, strong) PETCombatStateComponent *combatStateComponent;
@property (nonatomic, strong, nullable) PETAttackDefinition *activeAttackDefinition;
@property (nonatomic, strong, nullable) PETActiveSkillInstance *activeSkillInstance;
@property (nonatomic, strong, nullable) PETSkillLibrary *skillLibrary;
@property (nonatomic, strong, nullable) PETHitResult *pendingHitMovementResult;
@property (nonatomic, assign) NSTimeInterval pendingHitMovementDelayRemaining;
@property (nonatomic, strong) NSMutableArray<PETHitResult *> *pendingSkillEffectHitResults;
@property (nonatomic, strong) NSMutableArray<PETGameEvent *> *pendingSkillEffectEvents;

@end

@implementation PETGameSession

static NSTimeInterval const PETDelayedHitMovementResponseDelay = 0.5;

- (nullable PETSkillDefinition *)reloadSkillDefinitionForIdentifier:(NSString *)skillIdentifier {
    if (skillIdentifier.length == 0) {
        return nil;
    }

    NSError *reloadError = nil;
    PETSkillLibrary *reloadedLibrary = [[PETSkillLibrary alloc] initWithBundle:NSBundle.mainBundle error:&reloadError];
    if (reloadedLibrary == nil) {
        NSLog(@"[DesktopPet] Skill library reload failed for skillId=%@ pet=%@ error=%@",
              skillIdentifier,
              self.petIdentifier ?: @"",
              reloadError.localizedDescription ?: @"unknown");
        return nil;
    }

    self.skillLibrary = reloadedLibrary;
    PETSkillDefinition *skillDefinition = [reloadedLibrary skillDefinitionForIdentifier:skillIdentifier];
    NSLog(@"[DesktopPet] Skill library reloaded for pet=%@ skillId=%@ found=%@ totalSkills=%lu",
          self.petIdentifier ?: @"",
          skillIdentifier,
          skillDefinition != nil ? @"YES" : @"NO",
          (unsigned long)reloadedLibrary.skills.count);
    return skillDefinition;
}

- (instancetype)initWithProfile:(PETPetProfile *)profile
              runtimeController:(PETCharacterRuntimeController *)runtimeController
                   skillLibrary:(PETSkillLibrary *)skillLibrary {
    self = [super init];
    if (self) {
        _profile = profile;
        _petIdentifier = [profile.identifier copy] ?: @"";
        _runtimeController = runtimeController;
        _pendingCommands = [NSMutableArray array];
        _inputState = [[PETGameInputState alloc] init];
        _movementComponent = [[PETMovementComponent alloc] init];
        _movementSystem = [[PETMovementSystem alloc] init];
        _combatStateComponent = [[PETCombatStateComponent alloc] init];
        _skillLibrary = skillLibrary;
        _pendingSkillEffectHitResults = [NSMutableArray array];
        _pendingSkillEffectEvents = [NSMutableArray array];
    }
    return self;
}

- (void)submitCommand:(PETGameCommand *)command {
    if (command.petIdentifier.length > 0 && ![command.petIdentifier isEqualToString:self.petIdentifier]) {
        return;
    }
    [self.pendingCommands addObject:command];
}

- (NSArray<PETGameEvent *> *)tickWithDeltaTime:(NSTimeInterval)deltaTime {
    if (self.isPaused) {
        [self.pendingCommands removeAllObjects];
        return @[];
    }

    self.tickCount += 1;
    self.lastTickDate = NSDate.date;

    NSMutableArray<PETGameEvent *> *events = [NSMutableArray array];
    NSArray<PETGameCommand *> *commands = self.pendingCommands.copy;
    [self.pendingCommands removeAllObjects];

    for (PETGameCommand *command in commands) {
        [self.inputState applyCommand:command];
        NSMutableDictionary<NSString *, id> *context = [[command dictionaryRepresentation] mutableCopy];
        context[@"deltaTime"] = @(deltaTime);
        [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventCommandAccepted
                                                    petIdentifier:self.petIdentifier
                                                           source:@"game.session"
                                                          context:context.copy]];
        [events addObjectsFromArray:[self combatEventsForCommand:command]];
    }

    if (self.tickCount == 1) {
        [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventTick
                                                    petIdentifier:self.petIdentifier
                                                           source:@"game.session"
                                                          context:@{@"tickCount": @(self.tickCount),
                                                                    @"deltaTime": @(deltaTime)}]];
    }
    [self advancePendingHitMovementResponseWithDeltaTime:deltaTime];
    [self syncMovementRestrictionsFromCombatState];
    [events addObjectsFromArray:[self.movementSystem updateMovementComponent:self.movementComponent
                                                               movementVector:self.inputState.movementVector
                                                                 jumpRequested:self.inputState.jumpRequested
                                                                   deltaTime:deltaTime
                                                               petIdentifier:self.petIdentifier]];
    [events addObjectsFromArray:[self updateCombatWithDeltaTime:deltaTime]];
    [self.inputState consumeJumpRequest];
    return events.copy;
}

- (void)setMovementPosition:(CGPoint)position bodySize:(CGSize)bodySize {
    self.movementComponent.position = position;
    self.movementComponent.bodySize = CGSizeMake(MAX(1.0, bodySize.width), MAX(1.0, bodySize.height));
}

- (NSDictionary<NSString *,id> *)serializedState {
    NSMutableDictionary<NSString *, id> *state = [NSMutableDictionary dictionary];
    state[@"gameStateVersion"] = @1;
    state[@"petId"] = self.petIdentifier ?: @"";
    state[@"paused"] = @(self.isPaused);
    state[@"tickCount"] = @(self.tickCount);
    if (self.lastTickDate != nil) {
        state[@"lastTickTimestamp"] = @([self.lastTickDate timeIntervalSince1970]);
    }
    if (self.lastPauseReason.length > 0) {
        state[@"pauseReason"] = self.lastPauseReason;
    }
    state[@"input"] = [self.inputState serializedState];
    state[@"movement"] = [self.movementComponent serializedState];
    state[@"combat"] = [self.combatStateComponent serializedState];
    if (self.activeAttackDefinition != nil) {
        state[@"activeAttack"] = [self.activeAttackDefinition dictionaryRepresentation];
    }
    if (self.activeSkillInstance != nil) {
        state[@"activeSkill"] = [self.activeSkillInstance debugSnapshot];
    }
    return state.copy;
}

- (void)restoreFromSerializedState:(NSDictionary<NSString *,id> *)state {
    NSNumber *paused = [state[@"paused"] respondsToSelector:@selector(boolValue)] ? state[@"paused"] : nil;
    NSNumber *tickCount = [state[@"tickCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? state[@"tickCount"] : nil;
    NSNumber *lastTickTimestamp = [state[@"lastTickTimestamp"] respondsToSelector:@selector(doubleValue)] ? state[@"lastTickTimestamp"] : nil;
    NSString *pauseReason = [state[@"pauseReason"] isKindOfClass:NSString.class] ? state[@"pauseReason"] : nil;
    NSDictionary<NSString *, id> *input = [state[@"input"] isKindOfClass:NSDictionary.class] ? state[@"input"] : nil;
    NSDictionary<NSString *, id> *movement = [state[@"movement"] isKindOfClass:NSDictionary.class] ? state[@"movement"] : nil;
    NSDictionary<NSString *, id> *combat = [state[@"combat"] isKindOfClass:NSDictionary.class] ? state[@"combat"] : nil;
    NSDictionary<NSString *, id> *activeAttack = [state[@"activeAttack"] isKindOfClass:NSDictionary.class] ? state[@"activeAttack"] : nil;

    self.paused = paused.boolValue;
    self.tickCount = tickCount.unsignedIntegerValue;
    self.lastPauseReason = [pauseReason copy];
    if (lastTickTimestamp.doubleValue > 0.0) {
        self.lastTickDate = [NSDate dateWithTimeIntervalSince1970:lastTickTimestamp.doubleValue];
    }
    if (input != nil) {
        [self.inputState restoreFromSerializedState:input];
    }
    if (movement != nil) {
        [self.movementComponent restoreFromSerializedState:movement];
    }
    if (combat != nil) {
        [self.combatStateComponent restoreFromSerializedState:combat];
    }
    self.activeAttackDefinition = activeAttack.count > 0 ? [[PETAttackDefinition alloc] initWithDictionaryRepresentation:activeAttack] : nil;
}

- (void)setPaused:(BOOL)paused reason:(NSString *)reason {
    _paused = paused;
    self.lastPauseReason = [reason copy];
    if (paused) {
        [self.pendingCommands removeAllObjects];
        [self.inputState clearAllInputs];
    }
}

- (NSArray<PETGameEvent *> *)applyResolvedHitResult:(PETHitResult *)hitResult {
    if (hitResult == nil || ![hitResult.targetPetIdentifier isEqualToString:self.petIdentifier]) {
        return @[];
    }

    [self.combatStateComponent applyHitResult:hitResult];
    [self queueMovementResponseForHitResult:hitResult];
    return @[
        [[PETGameEvent alloc] initWithEventType:PETGameEventAttackHit
                                  petIdentifier:self.petIdentifier
                                         source:@"game.combat"
                                        context:[hitResult dictionaryRepresentation]],
        [[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                  petIdentifier:self.petIdentifier
                                         source:@"game.combat"
                                        context:[self combatDebugSnapshot]]
    ];
}

- (void)queueMovementResponseForHitResult:(PETHitResult *)hitResult {
    self.pendingHitMovementResult = hitResult;
    self.pendingHitMovementDelayRemaining = PETDelayedHitMovementResponseDelay;
}

- (void)advancePendingHitMovementResponseWithDeltaTime:(NSTimeInterval)deltaTime {
    if (self.pendingHitMovementResult == nil) {
        return;
    }

    self.pendingHitMovementDelayRemaining = MAX(0.0, self.pendingHitMovementDelayRemaining - MAX(0.0, deltaTime));
    if (self.pendingHitMovementDelayRemaining > 0.0) {
        return;
    }

    PETHitResult *resolvedHitResult = self.pendingHitMovementResult;
    self.pendingHitMovementResult = nil;
    self.pendingHitMovementDelayRemaining = 0.0;
    [self applyMovementResponseForHitResult:resolvedHitResult];
}

- (void)applyMovementResponseForHitResult:(PETHitResult *)hitResult {
    if (hitResult == nil) {
        return;
    }

    CGFloat horizontalVelocity = hitResult.launchVector.dx;
    CGFloat verticalVelocity = hitResult.launchVector.dy;
    NSDictionary<NSString *, id> *collisionSnapshot = hitResult.collisionSnapshot;
    NSDictionary<NSString *, id> *sourceOrigin = [collisionSnapshot[@"sourceOrigin"] isKindOfClass:NSDictionary.class] ? collisionSnapshot[@"sourceOrigin"] : nil;
    NSDictionary<NSString *, id> *targetOrigin = [collisionSnapshot[@"targetOrigin"] isKindOfClass:NSDictionary.class] ? collisionSnapshot[@"targetOrigin"] : nil;
    if (sourceOrigin != nil && targetOrigin != nil && fabs(horizontalVelocity) > 0.01) {
        CGFloat sourceX = [sourceOrigin[@"x"] doubleValue];
        CGFloat targetX = [targetOrigin[@"x"] doubleValue];
        horizontalVelocity = targetX < sourceX ? -fabs(horizontalVelocity) : fabs(horizontalVelocity);
    }

    if (fabs(horizontalVelocity) > 0.01) {
        self.movementComponent.velocity = CGVectorMake(horizontalVelocity, self.movementComponent.velocity.dy);
        self.movementComponent.facingDirection = horizontalVelocity >= 0.0 ? PETMovementFacingRight : PETMovementFacingLeft;
    }

    NSString *combatState = hitResult.combatState;
    BOOL isLaunchedReaction = [combatState isEqualToString:PETCombatStateLaunched] || verticalVelocity > 1.0;
    if (isLaunchedReaction) {
        self.movementComponent.jumping = YES;
        self.movementComponent.jumpGroundY = self.movementComponent.position.y;
        self.movementComponent.jumpVelocity = verticalVelocity;
        self.movementComponent.jumpTakeoffTimeRemaining = self.movementComponent.jumpTakeoffDuration;
        self.movementComponent.landingTimeRemaining = 0.0;
        self.movementComponent.jumpAirTimeRemaining = 0.0;
        self.movementComponent.movementState = PETMovementStateJump;
    }
}

- (void)syncMovementRestrictionsFromCombatState {
    if (self.activeSkillInstance != nil && self.activeSkillInstance.currentPhase != nil) {
        self.movementComponent.locked = self.activeSkillInstance.currentPhase.movementLock;
        return;
    }

    if (self.activeAttackDefinition != nil && self.combatStateComponent.isControlLocked) {
        self.movementComponent.locked = YES;
        return;
    }

    self.movementComponent.locked = NO;
}

- (NSDictionary<NSString *,id> *)combatDebugSnapshot {
    NSMutableDictionary<NSString *, id> *snapshot = [[self.combatStateComponent debugSnapshot] mutableCopy];
    snapshot[@"activeAttack"] = self.activeAttackDefinition != nil ? [self.activeAttackDefinition dictionaryRepresentation] : @{};
    snapshot[@"activeSkill"] = self.activeSkillInstance != nil ? [self.activeSkillInstance debugSnapshot] : @{};
    snapshot[@"pendingSkillEffectHitResults"] = @([self.pendingSkillEffectHitResults count]);
    return snapshot.copy;
}

- (NSArray<PETGameEvent *> *)combatEventsForCommand:(PETGameCommand *)command {
    NSArray<PETGameEvent *> *cancelEvents = [self cancelEventsForCommand:command];
    if (cancelEvents.count > 0) {
        return cancelEvents;
    }

    NSArray<PETGameEvent *> *skillEvents = [self skillEventsForCommand:command];
    if (skillEvents.count > 0) {
        return skillEvents;
    }

    PETAttackDefinition *attackDefinition = [PETAttackDefinition attackDefinitionForCommand:command];
    if (attackDefinition == nil) {
        return @[];
    }
    if (self.activeAttackDefinition != nil || self.activeSkillInstance != nil || ![self.combatStateComponent beginAttackWithDefinition:attackDefinition]) {
        return @[];
    }

    self.activeAttackDefinition = attackDefinition;
    NSMutableDictionary<NSString *, id> *attackContext = [[attackDefinition dictionaryRepresentation] mutableCopy];
    NSString *actionKey = [command.context[@"actionKey"] isKindOfClass:NSString.class] ? command.context[@"actionKey"] : nil;
    if (actionKey.length > 0) {
        attackContext[@"actionKey"] = actionKey;
    }
    attackContext[@"phaseDuration"] = @(attackDefinition.startupDuration + attackDefinition.activeDuration + attackDefinition.recoveryDuration);
    return @[
        [[PETGameEvent alloc] initWithEventType:PETGameEventAttackStarted
                                  petIdentifier:self.petIdentifier
                                         source:@"game.combat"
                                        context:attackContext.copy],
        [[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                  petIdentifier:self.petIdentifier
                                         source:@"game.combat"
                                        context:[self combatDebugSnapshot]]
    ];
}

- (NSArray<PETGameEvent *> *)updateCombatWithDeltaTime:(NSTimeInterval)deltaTime {
    NSMutableArray<PETGameEvent *> *events = [NSMutableArray array];
    if (self.activeAttackDefinition != nil) {
        BOOL wasFinished = self.activeAttackDefinition.isFinished;
        [self.activeAttackDefinition advanceTime:deltaTime];
        if (!wasFinished && self.activeAttackDefinition.isFinished) {
            NSString *finishedAttackIdentifier = self.activeAttackDefinition.attackIdentifier ?: @"";
            [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventAttackEnded
                                                        petIdentifier:self.petIdentifier
                                                               source:@"game.combat"
                                                              context:[self.activeAttackDefinition dictionaryRepresentation]]];
            [self.combatStateComponent clearAttackIdentifierIfMatches:finishedAttackIdentifier];
            self.activeAttackDefinition = nil;
            [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                                        petIdentifier:self.petIdentifier
                                                               source:@"game.combat"
                                                              context:[self combatDebugSnapshot]]];
        }
    }
    if (self.activeSkillInstance != nil) {
        NSString *previousPhaseIdentifier = self.activeSkillInstance.currentPhase.phaseIdentifier ?: @"";
        PETSkillPhase *previousPhase = self.activeSkillInstance.currentPhase;
        NSTimeInterval previousPhaseTime = self.activeSkillInstance.phaseElapsedTime;
        [self.activeSkillInstance advanceTime:deltaTime];
        [events addObjectsFromArray:[self executeTimedEffectsFromPreviousPhase:previousPhase
                                                              previousPhaseTime:previousPhaseTime
                                                                   currentPhase:self.activeSkillInstance.currentPhase
                                                              currentPhaseTime:self.activeSkillInstance.phaseElapsedTime]];
        [events addObjectsFromArray:[self applyCasterMotionForPreviousPhase:previousPhase
                                                           previousPhaseTime:previousPhaseTime
                                                                currentPhase:self.activeSkillInstance.currentPhase
                                                           currentPhaseTime:self.activeSkillInstance.phaseElapsedTime
                                                                  deltaTime:deltaTime]];
        NSString *currentPhaseIdentifier = self.activeSkillInstance.currentPhase.phaseIdentifier ?: @"";
        if (![previousPhaseIdentifier isEqualToString:currentPhaseIdentifier]) {
            [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                                        petIdentifier:self.petIdentifier
                                                               source:@"game.skill"
                                                              context:[self combatDebugSnapshot]]];
        }
        if (self.activeSkillInstance.isFinished) {
            NSDictionary<NSString *, id> *finalSnapshot = [self.activeSkillInstance debugSnapshot];
            self.activeSkillInstance = nil;
            self.activeAttackDefinition = nil;
            [self.combatStateComponent advanceTime:DBL_MAX];
            [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventAttackEnded
                                                        petIdentifier:self.petIdentifier
                                                               source:@"game.skill"
                                                              context:finalSnapshot]];
            [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                                        petIdentifier:self.petIdentifier
                                                               source:@"game.skill"
                                                              context:[self combatDebugSnapshot]]];
        }
    }
    if ([self.combatStateComponent advanceTime:deltaTime]) {
        [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                                    petIdentifier:self.petIdentifier
                                                           source:@"game.combat"
                                                          context:[self combatDebugSnapshot]]];
    }
    return events.copy;
}

- (NSArray<PETGameEvent *> *)applyCasterMotionForPreviousPhase:(PETSkillPhase *)previousPhase
                                              previousPhaseTime:(NSTimeInterval)previousPhaseTime
                                                   currentPhase:(PETSkillPhase *)currentPhase
                                              currentPhaseTime:(NSTimeInterval)currentPhaseTime
                                                     deltaTime:(NSTimeInterval)deltaTime {
    if (previousPhase == nil || deltaTime <= 0.0) {
        return @[];
    }

    BOOL facingRight = ![self.movementComponent.facingDirection isEqualToString:PETMovementFacingLeft];
    CGVector totalDelta = CGVectorMake(0.0, 0.0);
    if (previousPhase == currentPhase) {
        totalDelta = [self casterMotionDeltaForPhase:previousPhase
                                            fromTime:previousPhaseTime
                                              toTime:currentPhaseTime
                                         facingRight:facingRight];
    } else {
        totalDelta = [self casterMotionDeltaForPhase:previousPhase
                                            fromTime:previousPhaseTime
                                              toTime:previousPhase.duration
                                         facingRight:facingRight];
        if (currentPhase != nil) {
            CGVector currentPhaseDelta = [self casterMotionDeltaForPhase:currentPhase
                                                                fromTime:0.0
                                                                  toTime:currentPhaseTime
                                                             facingRight:facingRight];
            totalDelta.dx += currentPhaseDelta.dx;
            totalDelta.dy += currentPhaseDelta.dy;
        }
    }

    if (fabs(totalDelta.dx) <= 0.01 && fabs(totalDelta.dy) <= 0.01) {
        return @[];
    }

    CGPoint position = self.movementComponent.position;
    position.x += totalDelta.dx;
    position.y += totalDelta.dy;
    self.movementComponent.position = position;

    return @[
        [[PETGameEvent alloc] initWithEventType:@"game.move.changed"
                                  petIdentifier:self.petIdentifier
                                         source:@"game.skill.motion"
                                        context:[self movementEventContext]]
    ];
}

- (NSArray<PETGameEvent *> *)executeTimedEffectsFromPreviousPhase:(PETSkillPhase *)previousPhase
                                                previousPhaseTime:(NSTimeInterval)previousPhaseTime
                                                     currentPhase:(PETSkillPhase *)currentPhase
                                                currentPhaseTime:(NSTimeInterval)currentPhaseTime {
    if (self.activeSkillInstance == nil) {
        return @[];
    }

    NSArray<NSDictionary<NSString *, id> *> *effects = [self.activeSkillInstance timedEffectsTriggeredFromPhase:previousPhase
                                                                                                       fromTime:previousPhaseTime
                                                                                                        toPhase:currentPhase
                                                                                                         toTime:currentPhaseTime];
    NSMutableArray<PETGameEvent *> *events = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *effect in effects) {
        NSString *phaseIdentifier = [effect[@"_effectPhaseId"] isKindOfClass:NSString.class]
            ? effect[@"_effectPhaseId"]
            : (currentPhase.phaseIdentifier ?: previousPhase.phaseIdentifier ?: @"");
        PETGameEvent *event = [self eventForExecutedEffect:effect
                                                   phaseId:phaseIdentifier
                                          targetIdentifier:nil
                                               effectSource:@"game.skill.effect.timer"];
        if (event != nil) {
            [events addObject:event];
            [self.pendingSkillEffectEvents addObject:event];
        }
    }
    return events.copy;
}

- (PETGameEvent *)eventForExecutedEffect:(NSDictionary<NSString *, id> *)effect
                                 phaseId:(NSString *)phaseIdentifier
                        targetIdentifier:(NSString *)targetIdentifier
                            effectSource:(NSString *)effectSource {
    NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"effect";
    NSMutableDictionary<NSString *, id> *context = [NSMutableDictionary dictionaryWithDictionary:effect ?: @{}];
    [context removeObjectForKey:@"_effectIndex"];
    [context removeObjectForKey:@"_effectTriggerTime"];
    [context removeObjectForKey:@"_effectPhaseId"];
    context[@"type"] = type;
    context[@"skillId"] = self.activeSkillInstance.skillDefinition.skillIdentifier ?: @"";
    context[@"phaseId"] = phaseIdentifier ?: @"";
    if (targetIdentifier.length > 0) {
        context[@"targetPetIdentifier"] = targetIdentifier;
    }
    return [[PETGameEvent alloc] initWithEventType:@"game.skill.effect.triggered"
                                     petIdentifier:self.petIdentifier
                                            source:effectSource ?: @"game.skill.effect"
                                           context:context.copy];
}

- (NSDictionary<NSString *, id> *)collisionSnapshotForSkillEffect:(NSDictionary<NSString *, id> *)effect
                                                 targetIdentifier:(NSString *)targetIdentifier
                                                          phaseId:(NSString *)phaseIdentifier {
    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"skillId"] = self.activeSkillInstance.skillDefinition.skillIdentifier ?: @"";
    snapshot[@"phaseId"] = phaseIdentifier ?: @"";
    snapshot[@"effectType"] = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
    snapshot[@"sourcePetIdentifier"] = self.petIdentifier ?: @"";
    snapshot[@"targetPetIdentifier"] = targetIdentifier ?: @"";
    if ([effect[@"vector"] isKindOfClass:NSDictionary.class]) {
        snapshot[@"effectVector"] = effect[@"vector"];
    }
    if ([effect[@"duration"] respondsToSelector:@selector(doubleValue)]) {
        snapshot[@"effectDuration"] = effect[@"duration"];
    }
    return snapshot.copy;
}

- (PETHitResult *)hitResultForSkillEffect:(NSDictionary<NSString *, id> *)effect
                         targetIdentifier:(NSString *)targetIdentifier
                                  phaseId:(NSString *)phaseIdentifier
                              effectIndex:(NSUInteger)effectIndex {
    if (self.activeSkillInstance == nil || targetIdentifier.length == 0) {
        return nil;
    }

    NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
    NSTimeInterval duration = [effect[@"duration"] respondsToSelector:@selector(doubleValue)] ? [effect[@"duration"] doubleValue] : 0.0;
    NSDictionary<NSString *, id> *vector = [effect[@"vector"] isKindOfClass:NSDictionary.class] ? effect[@"vector"] : nil;
    CGFloat dx = [vector[@"dx"] doubleValue];
    CGFloat dy = [vector[@"dy"] doubleValue];
    NSString *combatState = nil;
    BOOL causesKnockdown = NO;

    if ([type isEqualToString:@"launchTarget"]) {
        combatState = PETCombatStateLaunched;
        if (duration <= 0.0) {
            duration = 0.45;
        }
    } else if ([type isEqualToString:@"airSuspendTarget"]) {
        combatState = PETCombatStateLaunched;
        if (duration <= 0.0) {
            duration = 0.65;
        }
    } else if ([type isEqualToString:@"knockdownTarget"]) {
        combatState = PETCombatStateKnockedDown;
        causesKnockdown = YES;
        if (duration <= 0.0) {
            duration = 0.8;
        }
    } else {
        return nil;
    }

    NSString *attackIdentifier = [NSString stringWithFormat:@"%@:%@:%lu",
                                  self.activeSkillInstance.instanceIdentifier ?: @"skill",
                                  type ?: @"effect",
                                  (unsigned long)effectIndex];
    return [[PETHitResult alloc] initWithSourcePetIdentifier:self.petIdentifier
                                         targetPetIdentifier:targetIdentifier
                                            attackIdentifier:attackIdentifier
                                                  attackKind:PETAttackKindSkill
                                             hitStunDuration:duration
                                          knockdownDuration:duration
                                                launchVector:CGVectorMake(dx, dy)
                                                 combatState:combatState
                                            causesKnockdown:causesKnockdown
                                           collisionSnapshot:[self collisionSnapshotForSkillEffect:effect
                                                                                targetIdentifier:targetIdentifier
                                                                                         phaseId:phaseIdentifier]];
}

- (NSArray<PETGameEvent *> *)drainPendingSkillEffectEvents {
    NSArray<PETGameEvent *> *events = self.pendingSkillEffectEvents.copy;
    [self.pendingSkillEffectEvents removeAllObjects];
    return events;
}

- (NSArray<PETHitResult *> *)drainPendingSkillEffectHitResults {
    NSArray<PETHitResult *> *results = self.pendingSkillEffectHitResults.copy;
    [self.pendingSkillEffectHitResults removeAllObjects];
    return results;
}

- (CGVector)casterMotionDeltaForPhase:(PETSkillPhase *)phase
                             fromTime:(NSTimeInterval)fromTime
                               toTime:(NSTimeInterval)toTime
                          facingRight:(BOOL)facingRight {
    if (phase == nil || toTime <= fromTime) {
        return CGVectorMake(0.0, 0.0);
    }

    CGVector startOffset = [phase casterMotionOffsetAtPhaseTime:fromTime facingRight:facingRight];
    CGVector endOffset = [phase casterMotionOffsetAtPhaseTime:toTime facingRight:facingRight];
    return CGVectorMake(endOffset.dx - startOffset.dx, endOffset.dy - startOffset.dy);
}

- (NSDictionary<NSString *, id> *)movementEventContext {
    return @{
        @"position": @{@"x": @(self.movementComponent.position.x), @"y": @(self.movementComponent.position.y)},
        @"velocity": @{@"dx": @(self.movementComponent.velocity.dx), @"dy": @(self.movementComponent.velocity.dy)},
        @"bodySize": @{@"width": @(self.movementComponent.bodySize.width), @"height": @(self.movementComponent.bodySize.height)},
        @"facingDirection": self.movementComponent.facingDirection ?: PETMovementFacingRight,
        @"facingRight": @([self.movementComponent.facingDirection isEqualToString:PETMovementFacingRight]),
        @"movementState": self.movementComponent.movementState ?: PETMovementStateIdle,
        @"jumping": @(self.movementComponent.isJumping),
        @"jumpVelocity": @(self.movementComponent.jumpVelocity),
        @"jumpTakeoffTimeRemaining": @(self.movementComponent.jumpTakeoffTimeRemaining),
        @"landingTimeRemaining": @(self.movementComponent.landingTimeRemaining)
    };
}

- (NSArray<PETGameEvent *> *)cancelEventsForCommand:(PETGameCommand *)command {
    if (![command.commandType isEqualToString:PETGameCommandSkillCancel]) {
        return @[];
    }
    if (self.activeSkillInstance == nil && self.activeAttackDefinition == nil) {
        return @[];
    }

    NSMutableDictionary<NSString *, id> *cancelContext = [NSMutableDictionary dictionary];
    if (self.activeSkillInstance != nil) {
        [cancelContext addEntriesFromDictionary:[self.activeSkillInstance debugSnapshot]];
    }
    NSString *actionKey = [command.context[@"actionKey"] isKindOfClass:NSString.class] ? command.context[@"actionKey"] : @"";
    if (actionKey.length > 0) {
        cancelContext[@"actionKey"] = actionKey;
    }
    cancelContext[@"source"] = command.source ?: @"";

    self.activeSkillInstance = nil;
    self.activeAttackDefinition = nil;
    [self.combatStateComponent advanceTime:DBL_MAX];
    return @[
        [[PETGameEvent alloc] initWithEventType:PETGameEventAttackEnded
                                  petIdentifier:self.petIdentifier
                                         source:@"game.skill.cancel"
                                        context:cancelContext.copy],
        [[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                  petIdentifier:self.petIdentifier
                                         source:@"game.skill.cancel"
                                        context:[self combatDebugSnapshot]]
    ];
}

- (NSArray<PETGameEvent *> *)skillEventsForCommand:(PETGameCommand *)command {
    BOOL isSkillCast = [command.commandType isEqualToString:PETGameCommandSkillCast];
    BOOL isUltimateSkillCast = [command.commandType isEqualToString:PETGameCommandUltimateCast] && command.skillIdentifier.length > 0;
    if (!isSkillCast && !isUltimateSkillCast) {
        return @[];
    }
    if (self.activeSkillInstance != nil || self.activeAttackDefinition != nil || command.skillIdentifier.length == 0) {
        return @[];
    }

    PETSkillDefinition *skillDefinition = [self.skillLibrary skillDefinitionForIdentifier:command.skillIdentifier];
    if (skillDefinition == nil) {
        skillDefinition = [self reloadSkillDefinitionForIdentifier:command.skillIdentifier];
    }
    if (skillDefinition == nil) {
        NSLog(@"[DesktopPet] skill.cast rejected: unknown skillId=%@ pet=%@", command.skillIdentifier ?: @"", self.petIdentifier ?: @"");
        return @[];
    }

    PETAttackDefinition *stateLockDefinition = [[PETAttackDefinition alloc] initWithSourcePetIdentifier:self.petIdentifier
                                                                                              attackKind:PETAttackKindSkill
                                                                                         skillIdentifier:skillDefinition.skillIdentifier
                                                                                         startupDuration:0.0
                                                                                          activeDuration:skillDefinition.totalDuration
                                                                                        recoveryDuration:0.0
                                                                                         hitStunDuration:0.0
                                                                                      knockdownDuration:0.0
                                                                                            launchVector:CGVectorMake(0.0, 0.0)
                                                                                        causesKnockdown:NO
                                                                                       collisionEnabled:NO
                                                                                           sampleSpacing:1.0
                                                                                    maxHitCountPerTarget:1];
    if (![self.combatStateComponent beginAttackWithDefinition:stateLockDefinition]) {
        return @[];
    }

    self.activeSkillInstance = [[PETActiveSkillInstance alloc] initWithSkillDefinition:skillDefinition
                                                                    casterPetIdentifier:self.petIdentifier];
    NSMutableDictionary<NSString *, id> *skillContext = [[self.activeSkillInstance debugSnapshot] mutableCopy];
    NSString *actionKey = [command.context[@"actionKey"] isKindOfClass:NSString.class] ? command.context[@"actionKey"] : nil;
    if (actionKey.length > 0) {
        skillContext[@"actionKey"] = actionKey;
    }
    skillContext[@"castKind"] = isUltimateSkillCast ? @"ultimate" : @"skill";
    return @[
        [[PETGameEvent alloc] initWithEventType:PETGameEventAttackStarted
                                  petIdentifier:self.petIdentifier
                                         source:@"game.skill"
                                        context:skillContext.copy],
        [[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                  petIdentifier:self.petIdentifier
                                         source:@"game.skill"
                                        context:[self combatDebugSnapshot]]
    ];
}

- (NSArray<NSDictionary<NSString *,id> *> *)activeSkillHitWindows {
    return self.activeSkillInstance != nil ? [self.activeSkillInstance activeHitWindows] : @[];
}

- (NSDictionary<NSString *,id> *)reactionDefinitionForActiveSkillHitWindow:(NSDictionary<NSString *,id> *)hitWindow {
    NSString *reactionIdentifier = [hitWindow[@"reactionId"] isKindOfClass:NSString.class] ? hitWindow[@"reactionId"] : nil;
    return [self.skillLibrary reactionDefinitionForIdentifier:reactionIdentifier];
}

- (BOOL)activeSkillCanHitTargetIdentifier:(NSString *)targetIdentifier hitWindow:(NSDictionary<NSString *,id> *)hitWindow {
    return [self.activeSkillInstance canHitTargetIdentifier:targetIdentifier forHitWindow:hitWindow];
}

- (void)registerActiveSkillHitTargetIdentifier:(NSString *)targetIdentifier hitWindow:(NSDictionary<NSString *,id> *)hitWindow {
    NSString *windowIdentifier = [hitWindow[@"windowId"] isKindOfClass:NSString.class] ? hitWindow[@"windowId"] : nil;
    PETSkillPhase *phase = self.activeSkillInstance.currentPhase;
    NSString *phaseIdentifier = phase.phaseIdentifier ?: @"";
    [self.activeSkillInstance registerHitTargetIdentifier:targetIdentifier forHitWindow:hitWindow];
    NSArray<NSDictionary<NSString *, id> *> *effects = phase.effects ?: @[];
    [effects enumerateObjectsUsingBlock:^(NSDictionary<NSString *,id> * _Nonnull effect, NSUInteger index, BOOL * _Nonnull stop) {
        (void)stop;
        NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
        BOOL isTargetEffect = [type isEqualToString:@"launchTarget"] ||
                              [type isEqualToString:@"airSuspendTarget"] ||
                              [type isEqualToString:@"knockdownTarget"];
        if (!isTargetEffect) {
            return;
        }
        if (![self.activeSkillInstance shouldExecuteHitEffect:effect
                                             targetIdentifier:targetIdentifier
                                                        phase:phase
                                                  effectIndex:index]) {
            return;
        }

        PETHitResult *effectHitResult = [self hitResultForSkillEffect:effect
                                                     targetIdentifier:targetIdentifier
                                                              phaseId:phaseIdentifier
                                                          effectIndex:index];
        if (effectHitResult != nil) {
            [self.pendingSkillEffectHitResults addObject:effectHitResult];
        }
        PETGameEvent *effectEvent = [self eventForExecutedEffect:effect
                                                         phaseId:phaseIdentifier
                                                targetIdentifier:targetIdentifier
                                                    effectSource:@"game.skill.effect.hit"];
        if (effectEvent != nil) {
            [self.pendingSkillEffectEvents addObject:effectEvent];
        }
        [self.activeSkillInstance registerExecutedHitEffect:effect
                                           targetIdentifier:targetIdentifier
                                                      phase:phase
                                                effectIndex:index];
    }];
    [self.activeSkillInstance handleHitForWindowIdentifier:windowIdentifier ?: @"" targetIdentifier:targetIdentifier ?: @""];
}

- (PETHitResult *)hitResultForActiveSkillHitWindow:(NSDictionary<NSString *,id> *)hitWindow
                               targetPetIdentifier:(NSString *)targetPetIdentifier
                                 collisionSnapshot:(NSDictionary<NSString *,id> *)collisionSnapshot {
    NSDictionary<NSString *, id> *reaction = [self reactionDefinitionForActiveSkillHitWindow:hitWindow];
    NSString *windowIdentifier = [hitWindow[@"windowId"] isKindOfClass:NSString.class] ? hitWindow[@"windowId"] : @"";
    CGFloat launchDX = [reaction[@"launchVector"][@"dx"] doubleValue];
    CGFloat launchDY = [reaction[@"launchVector"][@"dy"] doubleValue];
    NSString *combatState = [reaction[@"combatState"] isKindOfClass:NSString.class] ? reaction[@"combatState"] : nil;
    if (launchDX == 0.0 && launchDY == 0.0) {
        launchDX = [[hitWindow valueForKeyPath:@"vector.dx"] doubleValue];
        launchDY = [[hitWindow valueForKeyPath:@"vector.dy"] doubleValue];
    }
    if (combatState.length == 0) {
        BOOL causesKnockdown = [reaction[@"knockdown"] boolValue];
        combatState = causesKnockdown ? PETCombatStateKnockedDown : (fabs(launchDY) > 1.0 ? PETCombatStateLaunched : PETCombatStateHitStun);
    }
    NSMutableDictionary<NSString *, id> *snapshot = [collisionSnapshot mutableCopy];
    snapshot[@"skillId"] = self.activeSkillInstance.skillDefinition.skillIdentifier ?: @"";
    snapshot[@"windowId"] = windowIdentifier ?: @"";
    return [[PETHitResult alloc] initWithSourcePetIdentifier:self.petIdentifier
                                         targetPetIdentifier:targetPetIdentifier
                                            attackIdentifier:[NSString stringWithFormat:@"%@:%@", self.activeSkillInstance.instanceIdentifier ?: @"skill", windowIdentifier ?: @"window"]
                                                  attackKind:PETAttackKindSkill
                                             hitStunDuration:[reaction[@"duration"] doubleValue]
                                          knockdownDuration:[reaction[@"duration"] doubleValue]
                                                launchVector:CGVectorMake(launchDX, launchDY)
                                                 combatState:combatState
                                            causesKnockdown:[reaction[@"knockdown"] boolValue]
                                           collisionSnapshot:snapshot.copy];
}

@end
