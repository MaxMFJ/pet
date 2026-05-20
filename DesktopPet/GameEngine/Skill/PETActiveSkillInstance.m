#import "PETActiveSkillInstance.h"

#import "PETSkillDefinition.h"
#import "PETSkillPhase.h"

@interface PETActiveSkillInstance ()

@property (nonatomic, copy) NSString *instanceIdentifier;
@property (nonatomic, copy) NSString *casterPetIdentifier;
@property (nonatomic, strong) PETSkillDefinition *skillDefinition;
@property (nonatomic, strong, nullable) PETSkillPhase *currentPhase;
@property (nonatomic, assign) NSTimeInterval elapsedTime;
@property (nonatomic, assign) NSTimeInterval phaseElapsedTime;
@property (nonatomic, assign, getter=isFinished) BOOL finished;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *> *hitTimestampsByWindowIdentifier;
@property (nonatomic, strong) NSMutableSet<NSString *> *executedEffectKeys;
@property (nonatomic, strong) NSMutableSet<NSString *> *activeProjectileIdentifiers;
@property (nonatomic, strong) NSMutableArray<NSString *> *returnedProjectileIdentifiers;
@property (nonatomic, copy, nullable) NSString *lastHitWindowIdentifier;
@property (nonatomic, copy, nullable) NSString *lastHitTargetIdentifier;
@property (nonatomic, copy, nullable) NSString *lastTransitionReason;

@end

@implementation PETActiveSkillInstance

- (instancetype)initWithSkillDefinition:(PETSkillDefinition *)skillDefinition
                    casterPetIdentifier:(NSString *)casterPetIdentifier {
    self = [super init];
    if (self) {
        _instanceIdentifier = [NSUUID.UUID.UUIDString copy];
        _casterPetIdentifier = [casterPetIdentifier copy] ?: @"";
        _skillDefinition = skillDefinition;
        _currentPhase = skillDefinition.entryPhase;
        _elapsedTime = 0.0;
        _phaseElapsedTime = 0.0;
        _finished = (_currentPhase == nil);
        _hitTimestampsByWindowIdentifier = [NSMutableDictionary dictionary];
        _executedEffectKeys = [NSMutableSet set];
        _activeProjectileIdentifiers = [NSMutableSet set];
        _returnedProjectileIdentifiers = [NSMutableArray array];
    }
    return self;
}

- (void)advanceTime:(NSTimeInterval)deltaTime {
    if (self.isFinished) {
        return;
    }

    NSTimeInterval clampedDelta = MAX(0.0, deltaTime);
    self.elapsedTime += clampedDelta;
    self.phaseElapsedTime += clampedDelta;

    PETSkillPhase *phase = self.currentPhase;
    if (phase == nil) {
        self.finished = YES;
        return;
    }

    if (self.phaseElapsedTime + 0.0001 < phase.duration) {
        return;
    }

    NSDictionary<NSString *, id> *transition = [self transitionForPhase:phase
                                                              eventType:@"onTimer"
                                                  requiresPhaseCompletion:NO];
    if (transition == nil) {
        transition = [self transitionForPhase:phase
                                    eventType:@"onPhaseComplete"
                        requiresPhaseCompletion:YES];
    }
    if ([self applyTransition:transition reason:@"phase"]) {
        return;
    }

    self.currentPhase = nil;
    self.finished = YES;
}

- (BOOL)transitionToPhaseIdentifier:(NSString *)phaseIdentifier {
    PETSkillPhase *phase = [self.skillDefinition phaseWithIdentifier:phaseIdentifier];
    if (phase == nil) {
        return NO;
    }
    self.currentPhase = phase;
    self.phaseElapsedTime = 0.0;
    return YES;
}

- (nullable NSDictionary<NSString *, id> *)transitionForPhase:(PETSkillPhase *)phase
                                                    eventType:(NSString *)eventType
                                        requiresPhaseCompletion:(BOOL)requiresPhaseCompletion {
    if (phase == nil || eventType.length == 0) {
        return nil;
    }

    for (NSDictionary<NSString *, id> *transition in phase.transitions) {
        NSString *type = [transition[@"type"] isKindOfClass:NSString.class] ? transition[@"type"] : @"";
        if (![type isEqualToString:eventType]) {
            continue;
        }
        if ([eventType isEqualToString:@"onTimer"]) {
            NSTimeInterval triggerTime = [transition[@"time"] doubleValue];
            if (self.phaseElapsedTime + 0.0001 < triggerTime) {
                continue;
            }
        } else if (requiresPhaseCompletion && self.phaseElapsedTime + 0.0001 < phase.duration) {
            continue;
        }
        return transition;
    }
    return nil;
}

- (BOOL)applyTransition:(NSDictionary<NSString *, id> *)transition reason:(NSString *)reason {
    NSString *nextPhaseIdentifier = [transition[@"toPhase"] isKindOfClass:NSString.class] ? transition[@"toPhase"] : nil;
    if (nextPhaseIdentifier.length == 0) {
        return NO;
    }
    if (![self transitionToPhaseIdentifier:nextPhaseIdentifier]) {
        return NO;
    }
    self.lastTransitionReason = reason.length > 0 ? reason : nil;
    return YES;
}

- (NSArray<NSDictionary<NSString *,id> *> *)activeHitWindows {
    return [self.currentPhase activeHitWindowsAtPhaseTime:self.phaseElapsedTime];
}

- (NSArray<NSDictionary<NSString *,id> *> *)currentPhaseEffects {
    return self.currentPhase.effects ?: @[];
}

- (NSArray<NSDictionary<NSString *,id> *> *)currentPhaseTransitions {
    return self.currentPhase.transitions ?: @[];
}

- (void)registerSpawnedProjectileIdentifier:(NSString *)projectileIdentifier {
    if (projectileIdentifier.length == 0) {
        return;
    }
    [self.activeProjectileIdentifiers addObject:projectileIdentifier];
}

- (BOOL)hasActiveProjectileIdentifier:(NSString *)projectileIdentifier {
    if (projectileIdentifier.length == 0) {
        return NO;
    }
    return [self.activeProjectileIdentifiers containsObject:projectileIdentifier];
}

- (BOOL)registerReturnedProjectileIdentifier:(NSString *)projectileIdentifier {
    if (projectileIdentifier.length == 0 || ![self.activeProjectileIdentifiers containsObject:projectileIdentifier]) {
        return NO;
    }
    [self.activeProjectileIdentifiers removeObject:projectileIdentifier];
    [self.returnedProjectileIdentifiers addObject:projectileIdentifier];
    return YES;
}

- (BOOL)handleProjectileReturnIdentifier:(NSString *)projectileIdentifier {
    if (self.currentPhase == nil || projectileIdentifier.length == 0) {
        return NO;
    }

    NSDictionary<NSString *, id> *transition = nil;
    for (NSDictionary<NSString *, id> *candidate in self.currentPhase.transitions) {
        NSString *type = [candidate[@"type"] isKindOfClass:NSString.class] ? candidate[@"type"] : @"";
        if (![type isEqualToString:@"onProjectileReturn"]) {
            continue;
        }
        NSString *requiredProjectileIdentifier = [candidate[@"projectileId"] isKindOfClass:NSString.class] ? candidate[@"projectileId"] : nil;
        if (requiredProjectileIdentifier.length > 0 && ![requiredProjectileIdentifier isEqualToString:projectileIdentifier]) {
            continue;
        }
        transition = candidate;
        break;
    }
    return [self applyTransition:transition reason:@"projectileReturn"];
}

- (NSString *)effectExecutionKeyForPhase:(PETSkillPhase *)phase
                             effectIndex:(NSUInteger)effectIndex
                              triggerTag:(NSString *)triggerTag
                        targetIdentifier:(NSString *)targetIdentifier {
    NSString *phaseIdentifier = phase.phaseIdentifier ?: @"phase";
    NSString *targetKey = targetIdentifier.length > 0 ? targetIdentifier : @"";
    NSString *triggerKey = triggerTag.length > 0 ? triggerTag : @"effect";
    return [NSString stringWithFormat:@"%@::%lu::%@::%@",
            phaseIdentifier,
            (unsigned long)effectIndex,
            triggerKey,
            targetKey];
}

- (NSArray<NSDictionary<NSString *, id> *> *)timedEffectsTriggeredWithinPhase:(PETSkillPhase *)phase
                                                                     fromTime:(NSTimeInterval)fromTime
                                                                       toTime:(NSTimeInterval)toTime {
    if (phase == nil || toTime + 0.0001 < fromTime) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *triggered = [NSMutableArray array];
    [phase.effects enumerateObjectsUsingBlock:^(NSDictionary<NSString *,id> * _Nonnull effect, NSUInteger index, BOOL * _Nonnull stop) {
        (void)stop;
        NSString *type = [effect[@"type"] isKindOfClass:NSString.class] ? effect[@"type"] : @"";
        if (type.length == 0) {
            return;
        }
        if ([type isEqualToString:@"launchTarget"] ||
            [type isEqualToString:@"airSuspendTarget"] ||
            [type isEqualToString:@"knockdownTarget"]) {
            return;
        }

        NSTimeInterval triggerTime = [effect[@"time"] respondsToSelector:@selector(doubleValue)] ? [effect[@"time"] doubleValue] : 0.0;
        BOOL crossedTrigger = (fromTime <= triggerTime + 0.0001 && toTime + 0.0001 >= triggerTime);
        if (!crossedTrigger) {
            return;
        }

        NSString *effectKey = [self effectExecutionKeyForPhase:phase
                                                   effectIndex:index
                                                    triggerTag:[NSString stringWithFormat:@"time:%0.4f", triggerTime]
                                              targetIdentifier:@""];
        if ([self.executedEffectKeys containsObject:effectKey]) {
            return;
        }
        [self.executedEffectKeys addObject:effectKey];

        NSMutableDictionary<NSString *, id> *payload = [effect mutableCopy];
        payload[@"_effectIndex"] = @(index);
        payload[@"_effectTriggerTime"] = @(triggerTime);
        payload[@"_effectPhaseId"] = phase.phaseIdentifier ?: @"";
        [triggered addObject:payload.copy];
    }];
    return triggered.copy;
}

- (NSArray<NSDictionary<NSString *, id> *> *)timedEffectsTriggeredFromPhase:(PETSkillPhase *)fromPhase
                                                                   fromTime:(NSTimeInterval)fromTime
                                                                    toPhase:(PETSkillPhase *)toPhase
                                                                     toTime:(NSTimeInterval)toTime {
    NSMutableArray<NSDictionary<NSString *, id> *> *triggered = [NSMutableArray array];
    if (fromPhase == toPhase) {
        [triggered addObjectsFromArray:[self timedEffectsTriggeredWithinPhase:toPhase
                                                                     fromTime:fromTime
                                                                       toTime:toTime]];
        return triggered.copy;
    }

    if (fromPhase != nil) {
        [triggered addObjectsFromArray:[self timedEffectsTriggeredWithinPhase:fromPhase
                                                                     fromTime:fromTime
                                                                       toTime:fromPhase.duration]];
    }
    if (toPhase != nil) {
        [triggered addObjectsFromArray:[self timedEffectsTriggeredWithinPhase:toPhase
                                                                     fromTime:0.0
                                                                       toTime:toTime]];
    }
    return triggered.copy;
}

- (BOOL)shouldExecuteHitEffect:(NSDictionary<NSString *, id> *)effect
               targetIdentifier:(NSString *)targetIdentifier
                          phase:(PETSkillPhase *)phase
                    effectIndex:(NSUInteger)effectIndex {
    if (phase == nil || targetIdentifier.length == 0) {
        return NO;
    }
    NSString *effectKey = [self effectExecutionKeyForPhase:phase
                                               effectIndex:effectIndex
                                                triggerTag:@"hit"
                                          targetIdentifier:targetIdentifier];
    return ![self.executedEffectKeys containsObject:effectKey];
}

- (void)registerExecutedHitEffect:(NSDictionary<NSString *, id> *)effect
                 targetIdentifier:(NSString *)targetIdentifier
                            phase:(PETSkillPhase *)phase
                      effectIndex:(NSUInteger)effectIndex {
    if (phase == nil || targetIdentifier.length == 0) {
        return;
    }
    NSString *effectKey = [self effectExecutionKeyForPhase:phase
                                               effectIndex:effectIndex
                                                triggerTag:@"hit"
                                          targetIdentifier:targetIdentifier];
    [self.executedEffectKeys addObject:effectKey];
}

- (NSString *)hitTrackingKeyForWindowIdentifier:(NSString *)windowIdentifier {
    if (windowIdentifier.length == 0) {
        return @"";
    }
    NSString *phaseIdentifier = self.currentPhase.phaseIdentifier ?: @"phase";
    return [NSString stringWithFormat:@"%@::%@", phaseIdentifier, windowIdentifier];
}

- (NSMutableArray<NSNumber *> *)mutableHitTimestampsForTargetIdentifier:(NSString *)targetIdentifier
                                                             trackingKey:(NSString *)trackingKey
                                                            createIfNeeded:(BOOL)createIfNeeded {
    if (targetIdentifier.length == 0 || trackingKey.length == 0) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *targetsByWindow = self.hitTimestampsByWindowIdentifier[trackingKey];
    if (targetsByWindow == nil && createIfNeeded) {
        targetsByWindow = [NSMutableDictionary dictionary];
        self.hitTimestampsByWindowIdentifier[trackingKey] = targetsByWindow;
    }

    NSMutableArray<NSNumber *> *timestamps = targetsByWindow[targetIdentifier];
    if (timestamps == nil && createIfNeeded) {
        timestamps = [NSMutableArray array];
        targetsByWindow[targetIdentifier] = timestamps;
    }
    return timestamps;
}

- (NSUInteger)maxHitsPerTargetForHitWindow:(NSDictionary<NSString *, id> *)hitWindow {
    NSUInteger configuredValue = [hitWindow[@"maxHitsPerTarget"] unsignedIntegerValue];
    return MAX((NSUInteger)1, configuredValue);
}

- (NSTimeInterval)rehitIntervalForHitWindow:(NSDictionary<NSString *, id> *)hitWindow {
    NSTimeInterval configuredValue = [hitWindow[@"rehitInterval"] doubleValue];
    if (configuredValue > 0.0) {
        return configuredValue;
    }

    NSUInteger maxHitsPerTarget = [self maxHitsPerTargetForHitWindow:hitWindow];
    if (maxHitsPerTarget <= 1) {
        return 0.0;
    }

    NSTimeInterval startTime = [hitWindow[@"startTime"] doubleValue];
    NSTimeInterval endTime = [hitWindow[@"endTime"] doubleValue];
    NSTimeInterval windowDuration = MAX(0.0, endTime - startTime);
    if (windowDuration <= 0.0) {
        return 0.0;
    }

    return MAX(windowDuration / (NSTimeInterval)maxHitsPerTarget, 1.0 / 60.0);
}

- (BOOL)canHitTargetIdentifier:(NSString *)targetIdentifier forHitWindow:(NSDictionary<NSString *,id> *)hitWindow {
    NSString *windowIdentifier = [hitWindow[@"windowId"] isKindOfClass:NSString.class] ? hitWindow[@"windowId"] : nil;
    NSString *trackingKey = [self hitTrackingKeyForWindowIdentifier:windowIdentifier ?: @""];
    if (targetIdentifier.length == 0 || trackingKey.length == 0) {
        return NO;
    }

    NSMutableArray<NSNumber *> *timestamps = [self mutableHitTimestampsForTargetIdentifier:targetIdentifier
                                                                                 trackingKey:trackingKey
                                                                                createIfNeeded:NO];
    NSUInteger hitCount = timestamps.count;
    NSUInteger maxHitsPerTarget = [self maxHitsPerTargetForHitWindow:hitWindow];
    if (hitCount >= maxHitsPerTarget) {
        return NO;
    }
    if (hitCount == 0) {
        return YES;
    }

    NSTimeInterval rehitInterval = [self rehitIntervalForHitWindow:hitWindow];
    if (rehitInterval <= 0.0) {
        return NO;
    }

    NSTimeInterval lastHitTime = timestamps.lastObject.doubleValue;
    return (self.phaseElapsedTime - lastHitTime + 0.0001) >= rehitInterval;
}

- (void)registerHitTargetIdentifier:(NSString *)targetIdentifier forHitWindow:(NSDictionary<NSString *,id> *)hitWindow {
    NSString *windowIdentifier = [hitWindow[@"windowId"] isKindOfClass:NSString.class] ? hitWindow[@"windowId"] : nil;
    NSString *trackingKey = [self hitTrackingKeyForWindowIdentifier:windowIdentifier ?: @""];
    if (targetIdentifier.length == 0 || trackingKey.length == 0) {
        return;
    }

    NSMutableArray<NSNumber *> *timestamps = [self mutableHitTimestampsForTargetIdentifier:targetIdentifier
                                                                                 trackingKey:trackingKey
                                                                                createIfNeeded:YES];
    [timestamps addObject:@(self.phaseElapsedTime)];
}

- (BOOL)handleHitForWindowIdentifier:(NSString *)windowIdentifier targetIdentifier:(NSString *)targetIdentifier {
    if (windowIdentifier.length == 0 || targetIdentifier.length == 0 || self.currentPhase == nil) {
        return NO;
    }

    self.lastHitWindowIdentifier = windowIdentifier;
    self.lastHitTargetIdentifier = targetIdentifier;
    NSDictionary<NSString *, id> *transition = [self transitionForPhase:self.currentPhase
                                                              eventType:@"onHit"
                                                  requiresPhaseCompletion:NO];
    return [self applyTransition:transition reason:@"hit"];
}

- (NSDictionary<NSString *,id> *)debugSnapshot {
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSArray<NSNumber *> *> *> *hitHistory = [NSMutableDictionary dictionaryWithCapacity:self.hitTimestampsByWindowIdentifier.count];
    [self.hitTimestampsByWindowIdentifier enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableDictionary<NSString *,NSMutableArray<NSNumber *> *> * _Nonnull obj, BOOL * _Nonnull stop) {
        (void)stop;
        NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *targets = [NSMutableDictionary dictionaryWithCapacity:obj.count];
        [obj enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull targetIdentifier, NSMutableArray<NSNumber *> * _Nonnull timestamps, BOOL * _Nonnull innerStop) {
            (void)innerStop;
            targets[targetIdentifier] = timestamps.copy ?: @[];
        }];
        hitHistory[key] = targets.copy ?: @{};
    }];
    return @{
        @"instanceId": self.instanceIdentifier ?: @"",
        @"casterPetIdentifier": self.casterPetIdentifier ?: @"",
        @"skillId": self.skillDefinition.skillIdentifier ?: @"",
        @"currentPhaseId": self.currentPhase.phaseIdentifier ?: @"",
        @"animationState": self.currentPhase.animationState ?: @"",
        @"movementLock": @(self.currentPhase.movementLock),
        @"gravityScale": @(self.currentPhase.gravityScale),
        @"allowMovementDuringCast": @(!self.currentPhase.movementLock),
        @"phaseDuration": @(self.currentPhase.duration),
        @"elapsedTime": @(self.elapsedTime),
        @"phaseElapsedTime": @(self.phaseElapsedTime),
        @"finished": @(self.isFinished),
        @"lastHitWindowId": self.lastHitWindowIdentifier ?: @"",
        @"lastHitTargetId": self.lastHitTargetIdentifier ?: @"",
        @"lastTransitionReason": self.lastTransitionReason ?: @"",
        @"activeProjectileIds": self.activeProjectileIdentifiers.allObjects ?: @[],
        @"returnedProjectileIds": self.returnedProjectileIdentifiers.copy ?: @[],
        @"activeHitWindows": [self activeHitWindows] ?: @[],
        @"currentPhaseEffects": [self currentPhaseEffects] ?: @[],
        @"currentPhaseTransitions": [self currentPhaseTransitions] ?: @[],
        @"executedEffectKeys": self.executedEffectKeys.allObjects ?: @[],
        @"hitHistoryByWindowIdentifier": hitHistory.copy ?: @{}
    };
}

@end
