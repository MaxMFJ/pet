#import "PETSkillRuntimeExecutor.h"

#import "../Combat/PETAttackDefinition.h"
#import "../Combat/PETCombatStateComponent.h"
#import "../Combat/PETHitResult.h"
#import "../Skill/PETActiveSkillInstance.h"
#import "../Skill/PETSkillDefinition.h"
#import "../Skill/PETSkillPhase.h"
#import "PETGameEvent.h"
#import "PETTargetMotionRuntime.h"
#import "PETTargetReactionRuntime.h"

@interface PETSkillRuntimeAdvanceResult ()

@property (nonatomic, copy) NSArray<PETGameEvent *> *events;
@property (nonatomic, copy) NSArray<PETGameEvent *> *pendingEffectEvents;
@property (nonatomic, copy) NSArray<PETHitResult *> *pendingEffectHitResults;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *pendingMotionDirectives;
@property (nonatomic, assign) BOOL didChangePhase;
@property (nonatomic, assign) BOOL didFinishSkill;
@property (nonatomic, copy) NSDictionary<NSString *, id> *finalSkillSnapshot;

@end

@implementation PETSkillRuntimeAdvanceResult

- (instancetype)initWithEvents:(NSArray<PETGameEvent *> *)events
           pendingEffectEvents:(NSArray<PETGameEvent *> *)pendingEffectEvents
        pendingEffectHitResults:(NSArray<PETHitResult *> *)pendingEffectHitResults
         pendingMotionDirectives:(NSArray<NSDictionary<NSString *, id> *> *)pendingMotionDirectives
                 didChangePhase:(BOOL)didChangePhase
                 didFinishSkill:(BOOL)didFinishSkill
             finalSkillSnapshot:(NSDictionary<NSString *,id> *)finalSkillSnapshot {
    self = [super init];
    if (self) {
        _events = [events copy] ?: @[];
        _pendingEffectEvents = [pendingEffectEvents copy] ?: @[];
        _pendingEffectHitResults = [pendingEffectHitResults copy] ?: @[];
        _pendingMotionDirectives = [pendingMotionDirectives copy] ?: @[];
        _didChangePhase = didChangePhase;
        _didFinishSkill = didFinishSkill;
        _finalSkillSnapshot = [finalSkillSnapshot copy] ?: @{};
    }
    return self;
}

@end

@interface PETSkillRuntimeExecutor ()

@property (nonatomic, copy) NSString *petIdentifier;

@end

@implementation PETSkillRuntimeExecutor

- (instancetype)initWithPetIdentifier:(NSString *)petIdentifier {
    self = [super init];
    if (self) {
        _petIdentifier = [petIdentifier copy] ?: @"";
    }
    return self;
}

- (PETSkillRuntimeAdvanceResult *)advanceSkillInstance:(PETActiveSkillInstance *)activeSkillInstance
                                             deltaTime:(NSTimeInterval)deltaTime
                                         motionRuntime:(PETTargetMotionRuntime *)motionRuntime
                           combatDebugSnapshotProvider:(PETCombatDebugSnapshotProvider)combatDebugSnapshotProvider {
    if (activeSkillInstance == nil) {
        return [[PETSkillRuntimeAdvanceResult alloc] initWithEvents:@[]
                                                pendingEffectEvents:@[]
                                             pendingEffectHitResults:@[]
                                             pendingMotionDirectives:@[]
                                                      didChangePhase:NO
                                                      didFinishSkill:NO
                                                  finalSkillSnapshot:nil];
    }

    NSMutableArray<PETGameEvent *> *events = [NSMutableArray array];
    NSMutableArray<PETGameEvent *> *pendingEffectEvents = [NSMutableArray array];
    NSMutableArray<PETHitResult *> *pendingEffectHitResults = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *pendingMotionDirectives = [NSMutableArray array];

    NSString *previousPhaseIdentifier = activeSkillInstance.currentPhase.phaseIdentifier ?: @"";
    PETSkillPhase *previousPhase = activeSkillInstance.currentPhase;
    NSTimeInterval previousPhaseTime = activeSkillInstance.phaseElapsedTime;

    [activeSkillInstance advanceTime:deltaTime];

    NSArray<NSDictionary<NSString *, id> *> *effects = [activeSkillInstance timedEffectsTriggeredFromPhase:previousPhase
                                                                                                   fromTime:previousPhaseTime
                                                                                                    toPhase:activeSkillInstance.currentPhase
                                                                                                     toTime:activeSkillInstance.phaseElapsedTime];
    for (NSDictionary<NSString *, id> *effect in effects) {
        NSString *phaseIdentifier = [effect[@"_effectPhaseId"] isKindOfClass:NSString.class]
            ? effect[@"_effectPhaseId"]
            : (activeSkillInstance.currentPhase.phaseIdentifier ?: previousPhase.phaseIdentifier ?: @"");
        NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
        NSString *targetIdentifier = [self targetIdentifierForSkillEffect:effect activeSkillInstance:activeSkillInstance];
        NSString *projectileIdentifier = [effect[@"projectileId"] isKindOfClass:NSString.class] ? effect[@"projectileId"] : nil;
        if ([type isEqualToString:@"spawnProjectile"] && projectileIdentifier.length > 0) {
            [activeSkillInstance registerSpawnedProjectileIdentifier:projectileIdentifier];
        } else if ([type isEqualToString:@"returnProjectile"] && projectileIdentifier.length > 0) {
            BOOL didRegisterReturn = [activeSkillInstance registerReturnedProjectileIdentifier:projectileIdentifier];
            if (didRegisterReturn && [activeSkillInstance handleProjectileReturnIdentifier:projectileIdentifier]) {
                NSDictionary<NSString *, id> *snapshot = combatDebugSnapshotProvider != nil ? combatDebugSnapshotProvider() : @{};
                [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventCombatStateChanged
                                                            petIdentifier:self.petIdentifier
                                                                   source:@"game.skill.projectile"
                                                                  context:snapshot]];
            }
        }

        PETGameEvent *event = [self eventForExecutedEffect:effect
                                                   phaseId:phaseIdentifier
                                          targetIdentifier:targetIdentifier
                                             skillInstance:activeSkillInstance
                                              effectSource:@"game.skill.effect.timer"];
        if (event != nil) {
            [events addObject:event];
            [pendingEffectEvents addObject:event];
        }

        NSUInteger effectIndex = [effect[@"_effectIndex"] unsignedIntegerValue];
        PETHitResult *effectHitResult = [self hitResultForSkillEffect:effect
                                                     targetIdentifier:targetIdentifier.length > 0 ? targetIdentifier : self.petIdentifier
                                                              phaseId:phaseIdentifier
                                                        skillInstance:activeSkillInstance
                                                          effectIndex:effectIndex];
        if (effectHitResult != nil) {
            [pendingEffectHitResults addObject:effectHitResult];
        }
        NSDictionary<NSString *, id> *motionDirective = [self motionDirectiveForSkillEffect:effect
                                                                            targetIdentifier:targetIdentifier
                                                                                     phaseId:phaseIdentifier
                                                                               skillInstance:activeSkillInstance];
        if (motionDirective.count > 0) {
            [pendingMotionDirectives addObject:motionDirective];
        }
    }

    BOOL didMove = [motionRuntime applyCasterMotionForPreviousPhase:previousPhase
                                                   previousPhaseTime:previousPhaseTime
                                                        currentPhase:activeSkillInstance.currentPhase
                                                   currentPhaseTime:activeSkillInstance.phaseElapsedTime];
    if (didMove) {
        [events addObject:[[PETGameEvent alloc] initWithEventType:@"game.move.changed"
                                                    petIdentifier:self.petIdentifier
                                                           source:@"game.skill.motion"
                                                          context:[motionRuntime movementEventContext]]];
    }

    NSString *currentPhaseIdentifier = activeSkillInstance.currentPhase.phaseIdentifier ?: @"";
    BOOL didChangePhase = ![previousPhaseIdentifier isEqualToString:currentPhaseIdentifier];
    NSDictionary<NSString *, id> *finalSkillSnapshot = activeSkillInstance.isFinished ? [activeSkillInstance debugSnapshot] : @{};

    return [[PETSkillRuntimeAdvanceResult alloc] initWithEvents:events.copy
                                            pendingEffectEvents:pendingEffectEvents.copy
                                         pendingEffectHitResults:pendingEffectHitResults.copy
                                         pendingMotionDirectives:pendingMotionDirectives.copy
                                                  didChangePhase:didChangePhase
                                                  didFinishSkill:activeSkillInstance.isFinished
                                              finalSkillSnapshot:finalSkillSnapshot];
}

- (PETGameEvent *)eventForExecutedEffect:(NSDictionary<NSString *, id> *)effect
                                 phaseId:(NSString *)phaseIdentifier
                        targetIdentifier:(NSString *)targetIdentifier
                           skillInstance:(PETActiveSkillInstance *)activeSkillInstance
                            effectSource:(NSString *)effectSource {
    NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"effect";
    NSMutableDictionary<NSString *, id> *context = [NSMutableDictionary dictionaryWithDictionary:effect ?: @{}];
    [context removeObjectForKey:@"_effectIndex"];
    [context removeObjectForKey:@"_effectTriggerTime"];
    [context removeObjectForKey:@"_effectPhaseId"];
    context[@"type"] = type;
    context[@"skillId"] = activeSkillInstance.skillDefinition.skillIdentifier ?: @"";
    context[@"phaseId"] = phaseIdentifier ?: @"";
    if (targetIdentifier.length > 0) {
        context[@"targetPetIdentifier"] = targetIdentifier;
    }
    return [[PETGameEvent alloc] initWithEventType:@"game.skill.effect.triggered"
                                     petIdentifier:self.petIdentifier
                                            source:effectSource ?: @"game.skill.effect"
                                           context:context.copy];
}

- (PETHitResult *)hitResultForSkillEffect:(NSDictionary<NSString *, id> *)effect
                         targetIdentifier:(NSString *)targetIdentifier
                                  phaseId:(NSString *)phaseIdentifier
                            skillInstance:(PETActiveSkillInstance *)activeSkillInstance
                              effectIndex:(NSUInteger)effectIndex {
    if (activeSkillInstance == nil || targetIdentifier.length == 0) {
        return nil;
    }

    NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
    NSTimeInterval duration = [effect[@"duration"] respondsToSelector:@selector(doubleValue)] ? [effect[@"duration"] doubleValue] : 0.0;
    NSDictionary<NSString *, id> *vector = [effect[@"vector"] isKindOfClass:NSDictionary.class] ? effect[@"vector"] : nil;
    CGFloat dx = [vector[@"dx"] doubleValue];
    CGFloat dy = [vector[@"dy"] doubleValue];
    NSString *combatState = nil;
    NSString *reactionState = nil;
    NSString *reactionAnimationState = [effect[@"animationState"] isKindOfClass:NSString.class] ? effect[@"animationState"] : nil;
    CGFloat reactionGravityScale = [effect[@"gravityScale"] respondsToSelector:@selector(doubleValue)] ? [effect[@"gravityScale"] doubleValue] : 1.0;
    BOOL reactionLocksHorizontal = [effect[@"lockHorizontal"] boolValue];
    BOOL reactionLocksVertical = [effect[@"lockVertical"] boolValue];
    BOOL causesKnockdown = NO;

    if ([type isEqualToString:@"launchTarget"]) {
        combatState = PETCombatStateLaunched;
        reactionState = PETReactionStateLaunched;
        if (duration <= 0.0) {
            duration = 0.45;
        }
    } else if ([type isEqualToString:@"airSuspendTarget"]) {
        combatState = PETCombatStateLaunched;
        reactionState = PETReactionStateAirHold;
        reactionGravityScale = [effect[@"gravityScale"] respondsToSelector:@selector(doubleValue)] ? [effect[@"gravityScale"] doubleValue] : 0.18;
        reactionLocksHorizontal = effect[@"lockHorizontal"] != nil ? [effect[@"lockHorizontal"] boolValue] : YES;
        reactionLocksVertical = [effect[@"lockVertical"] boolValue];
        if (reactionAnimationState.length == 0) {
            reactionAnimationState = @"hit_air_hold";
        }
        if (duration <= 0.0) {
            duration = 0.65;
        }
    } else if ([type isEqualToString:@"knockdownTarget"]) {
        combatState = PETCombatStateKnockedDown;
        reactionState = PETReactionStateKnockdown;
        causesKnockdown = YES;
        reactionLocksHorizontal = effect[@"lockHorizontal"] != nil ? [effect[@"lockHorizontal"] boolValue] : YES;
        reactionLocksVertical = effect[@"lockVertical"] != nil ? [effect[@"lockVertical"] boolValue] : YES;
        if (duration <= 0.0) {
            duration = 0.8;
        }
    } else {
        return nil;
    }

    NSString *attackIdentifier = [NSString stringWithFormat:@"%@:%@:%lu",
                                  activeSkillInstance.instanceIdentifier ?: @"skill",
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
                                              reactionState:reactionState
                                           reactionIdentifier:nil
                                       reactionAnimationState:reactionAnimationState
                                        reactionGravityScale:reactionGravityScale
                                      reactionLocksHorizontal:reactionLocksHorizontal
                                        reactionLocksVertical:reactionLocksVertical
                                            causesKnockdown:causesKnockdown
                                           collisionSnapshot:[self collisionSnapshotForSkillEffect:effect
                                                                                targetIdentifier:targetIdentifier
                                                                                         phaseId:phaseIdentifier
                                                                                    skillInstance:activeSkillInstance]];
}

- (NSDictionary<NSString *, id> *)collisionSnapshotForSkillEffect:(NSDictionary<NSString *, id> *)effect
                                                  targetIdentifier:(NSString *)targetIdentifier
                                                           phaseId:(NSString *)phaseIdentifier
                                                      skillInstance:(PETActiveSkillInstance *)activeSkillInstance {
    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"skillId"] = activeSkillInstance.skillDefinition.skillIdentifier ?: @"";
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

- (NSDictionary<NSString *, id> *)motionDirectiveForSkillEffect:(NSDictionary<NSString *, id> *)effect
                                               targetIdentifier:(NSString *)targetIdentifier
                                                        phaseId:(NSString *)phaseIdentifier
                                                  skillInstance:(PETActiveSkillInstance *)activeSkillInstance {
    NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
    if (targetIdentifier.length == 0) {
        return @{};
    }
    if (![type isEqualToString:@"followTargetRoot"] &&
        ![type isEqualToString:@"lockTargetPoint"] &&
        ![type isEqualToString:@"releaseTarget"]) {
        return @{};
    }

    NSMutableDictionary<NSString *, id> *directive = [NSMutableDictionary dictionaryWithDictionary:effect ?: @{}];
    directive[@"targetPetIdentifier"] = targetIdentifier;
    directive[@"sourcePetIdentifier"] = self.petIdentifier ?: @"";
    directive[@"phaseId"] = phaseIdentifier ?: @"";
    directive[@"skillId"] = activeSkillInstance.skillDefinition.skillIdentifier ?: @"";
    return directive.copy;
}

- (NSString *)targetIdentifierForSkillEffect:(NSDictionary<NSString *, id> *)effect
                         activeSkillInstance:(PETActiveSkillInstance *)activeSkillInstance {
    NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
    BOOL requiresResolvedTarget = [type isEqualToString:@"launchTarget"] ||
                                  [type isEqualToString:@"airSuspendTarget"] ||
                                  [type isEqualToString:@"knockdownTarget"] ||
                                  [type isEqualToString:@"followTargetRoot"] ||
                                  [type isEqualToString:@"lockTargetPoint"] ||
                                  [type isEqualToString:@"releaseTarget"];
    NSString *explicitTargetIdentifier = [effect[@"targetPetIdentifier"] isKindOfClass:NSString.class] ? effect[@"targetPetIdentifier"] : nil;
    if (explicitTargetIdentifier.length > 0) {
        return explicitTargetIdentifier;
    }
    NSString *targetSelector = [effect[@"targetSelector"] isKindOfClass:NSString.class] ? effect[@"targetSelector"] : nil;
    if ([targetSelector isEqualToString:@"lastHitTarget"]) {
        return activeSkillInstance.lastHitTargetIdentifier ?: @"";
    }
    if ([targetSelector isEqualToString:@"self"]) {
        return self.petIdentifier ?: @"";
    }
    if (requiresResolvedTarget && activeSkillInstance.lastHitTargetIdentifier.length > 0) {
        return activeSkillInstance.lastHitTargetIdentifier;
    }
    if (requiresResolvedTarget) {
        return @"";
    }
    return self.petIdentifier ?: @"";
}

@end
