#import "PETBehaviorPlanner.h"

#import "../Models/PETBehaviorDecision.h"
#import "../Models/PETCharacterGoal.h"
#import "../Models/PETCharacterEmotion.h"
#import "../Models/PETCharacterIntent.h"
#import "../Models/PETCharacterSnapshot.h"
#import "../Models/PETPetProfile.h"
#import "PETCharacterSemanticConfig.h"

@implementation PETBehaviorPlanner

- (PETBehaviorDecision *)planBehaviorForIntent:(PETCharacterIntent *)intent
                                       emotion:(PETCharacterEmotion *)emotion
                                          goal:(PETCharacterGoal *)goal
                                       profile:(PETPetProfile *)profile
                              previousSnapshot:(PETCharacterSnapshot *)previousSnapshot {
    NSDictionary<NSString *, id> *rule = [[PETCharacterSemanticConfig sharedConfig] behaviorRuleForIntentName:intent.name
                                                                                                     actionKey:intent.actionKey];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary<NSString *, id> *existingPlanner = [previousSnapshot.context[@"planner"] isKindOfClass:NSDictionary.class] ? previousSnapshot.context[@"planner"] : @{};
    NSMutableDictionary<NSString *, NSNumber *> *cooldowns = [self mutableCooldownsFromPlannerContext:existingPlanner];

    NSString *candidateState = [self resolvedBehaviorStateFromRule:rule intent:intent profile:profile];
    NSString *candidateMode = [rule[@"behaviorMode"] isKindOfClass:NSString.class] ? rule[@"behaviorMode"] : @"runtime";
    NSString *candidateAnimation = intent.resolvedAnimationState.length > 0 ? intent.resolvedAnimationState : profile.defaultState;
    NSInteger candidatePriority = [rule[@"priority"] respondsToSelector:@selector(integerValue)] ? [rule[@"priority"] integerValue] : 100;
    NSTimeInterval candidateCooldown = [rule[@"cooldown"] respondsToSelector:@selector(doubleValue)] ? [rule[@"cooldown"] doubleValue] : 0.0;
    NSTimeInterval minimumHold = [rule[@"minimumHold"] respondsToSelector:@selector(doubleValue)] ? [rule[@"minimumHold"] doubleValue] : 0.0;
    NSString *candidateCategory = [rule[@"behaviorCategory"] isKindOfClass:NSString.class] ? rule[@"behaviorCategory"] : @"runtime";
    BOOL candidateInterruptible = [rule[@"interruptible"] respondsToSelector:@selector(boolValue)] ? [rule[@"interruptible"] boolValue] : YES;
    NSString *behaviorReason = intent.actionKey.length > 0 ? intent.actionKey : intent.name;
    if (goal != nil && goal.priority > candidatePriority && goal.targetBehaviorState.length > 0) {
        candidateState = goal.targetBehaviorState;
        candidatePriority = goal.priority;
        if ([candidateMode isEqualToString:@"runtime"] || [candidateMode isEqualToString:@"ambient"]) {
            candidateMode = @"goal";
        }
        if (intent.resolvedAnimationState.length == 0 || [intent.name isEqualToString:@"ambient.exist"]) {
            candidateAnimation = goal.targetBehaviorState;
        }
        behaviorReason = [NSString stringWithFormat:@"goal:%@", goal.goalName ?: goal.goalIdentifier];
    }

    NSString *cooldownKey = [self cooldownKeyForIntent:intent];
    NSTimeInterval cooldownUntil = [cooldowns[cooldownKey] doubleValue];

    NSString *currentState = [existingPlanner[@"currentBehaviorState"] isKindOfClass:NSString.class] ? existingPlanner[@"currentBehaviorState"] : previousSnapshot.behaviorState;
    NSString *currentMode = [existingPlanner[@"currentBehaviorMode"] isKindOfClass:NSString.class] ? existingPlanner[@"currentBehaviorMode"] : previousSnapshot.behaviorMode;
    NSString *currentAnimation = [existingPlanner[@"currentAnimationState"] isKindOfClass:NSString.class] ? existingPlanner[@"currentAnimationState"] : previousSnapshot.animationState;
    NSInteger currentPriority = [existingPlanner[@"currentBehaviorPriority"] respondsToSelector:@selector(integerValue)] ? [existingPlanner[@"currentBehaviorPriority"] integerValue] : 0;
    NSString *currentCategory = [existingPlanner[@"currentBehaviorCategory"] isKindOfClass:NSString.class] ? existingPlanner[@"currentBehaviorCategory"] : @"runtime";
    BOOL currentInterruptible = [existingPlanner[@"currentInterruptible"] respondsToSelector:@selector(boolValue)] ? [existingPlanner[@"currentInterruptible"] boolValue] : YES;
    NSTimeInterval holdUntil = [existingPlanner[@"holdUntil"] respondsToSelector:@selector(doubleValue)] ? [existingPlanner[@"holdUntil"] doubleValue] : 0.0;

    BOOL blockedByCooldown = cooldownUntil > now;
    BOOL mustHoldCurrent = (currentState.length > 0 && holdUntil > now && candidatePriority < currentPriority);
    BOOL categoryInterruptAllowed = [self candidateCategory:candidateCategory
                               mayInterruptCurrentCategory:currentCategory
                                                      rule:rule
                                      currentInterruptible:currentInterruptible];

    NSString *finalState = candidateState;
    NSString *finalMode = candidateMode;
    NSString *finalAnimation = candidateAnimation;
    NSInteger finalPriority = candidatePriority;
    NSString *finalCategory = candidateCategory;
    BOOL finalInterruptible = candidateInterruptible;
    NSDictionary<NSString *, id> *currentYieldPolicy = [existingPlanner[@"currentYieldPolicy"] isKindOfClass:NSDictionary.class] ? existingPlanner[@"currentYieldPolicy"] : @{};
    BOOL currentShouldYield = [self currentBehaviorShouldYieldToCandidateCategory:candidateCategory
                                                                candidatePriority:candidatePriority
                                                                  currentCategory:currentCategory
                                                                  currentPriority:currentPriority
                                                                        holdUntil:holdUntil
                                                                              now:now
                                                                      yieldPolicy:currentYieldPolicy];

    if (blockedByCooldown && currentState.length > 0) {
        finalState = currentState;
        finalMode = currentMode.length > 0 ? currentMode : candidateMode;
        finalAnimation = currentAnimation.length > 0 ? currentAnimation : candidateAnimation;
        finalPriority = MAX(currentPriority, candidatePriority);
        finalCategory = currentCategory.length > 0 ? currentCategory : candidateCategory;
        finalInterruptible = currentInterruptible;
        behaviorReason = [NSString stringWithFormat:@"cooldown:%@", cooldownKey];
    } else if (!categoryInterruptAllowed && currentState.length > 0) {
        finalState = currentState;
        finalMode = currentMode.length > 0 ? currentMode : candidateMode;
        finalAnimation = currentAnimation.length > 0 ? currentAnimation : candidateAnimation;
        finalPriority = currentPriority;
        finalCategory = currentCategory.length > 0 ? currentCategory : candidateCategory;
        finalInterruptible = currentInterruptible;
        behaviorReason = [NSString stringWithFormat:@"interrupt-block:%@->%@", candidateCategory, currentCategory];
    } else if (mustHoldCurrent && !currentShouldYield) {
        finalState = currentState;
        finalMode = currentMode.length > 0 ? currentMode : candidateMode;
        finalAnimation = currentAnimation.length > 0 ? currentAnimation : candidateAnimation;
        finalPriority = currentPriority;
        finalCategory = currentCategory.length > 0 ? currentCategory : candidateCategory;
        finalInterruptible = currentInterruptible;
        behaviorReason = [NSString stringWithFormat:@"hold:%@", currentState];
    } else if (currentState.length > 0 &&
               candidatePriority < currentPriority &&
               [currentMode isEqualToString:@"interactive"] &&
               !currentShouldYield) {
        finalState = currentState;
        finalMode = currentMode;
        finalAnimation = currentAnimation.length > 0 ? currentAnimation : candidateAnimation;
        finalPriority = currentPriority;
        finalCategory = currentCategory.length > 0 ? currentCategory : candidateCategory;
        finalInterruptible = currentInterruptible;
        behaviorReason = [NSString stringWithFormat:@"priority:%@", currentState];
    } else if (currentShouldYield && currentState.length > 0) {
        behaviorReason = [NSString stringWithFormat:@"yield:%@->%@", currentCategory, candidateCategory];
    }

    if (emotion.arousal > 0.8 && [candidateMode isEqualToString:@"runtime"]) {
        candidateMode = @"alert";
        if ([finalMode isEqualToString:@"runtime"]) {
            finalMode = @"alert";
        }
    }

    if (!blockedByCooldown) {
        if (candidateCooldown > 0.0) {
            cooldowns[cooldownKey] = @(now + candidateCooldown);
        }
    }

    NSMutableDictionary<NSString *, id> *plannerContext = [NSMutableDictionary dictionary];
    plannerContext[@"currentBehaviorState"] = finalState ?: @"idle";
    plannerContext[@"currentBehaviorMode"] = finalMode ?: @"runtime";
    plannerContext[@"currentAnimationState"] = finalAnimation ?: profile.defaultState;
    plannerContext[@"currentBehaviorPriority"] = @(finalPriority);
    plannerContext[@"currentBehaviorCategory"] = finalCategory ?: @"runtime";
    plannerContext[@"currentInterruptible"] = @(finalInterruptible);
    plannerContext[@"currentYieldPolicy"] = [self yieldPolicyFromRule:rule];
    plannerContext[@"holdUntil"] = @(now + MAX(minimumHold, (mustHoldCurrent ? holdUntil - now : 0.0)));
    plannerContext[@"cooldowns"] = cooldowns.copy;
    plannerContext[@"lastPlannerReason"] = behaviorReason ?: @"runtime";
    if (goal != nil) {
        plannerContext[@"activeGoalIdentifier"] = goal.goalIdentifier ?: @"goal";
        plannerContext[@"activeGoalName"] = goal.goalName ?: @"goal";
    }

    return [[PETBehaviorDecision alloc] initWithBehaviorState:finalState
                                                 behaviorMode:finalMode
                                               behaviorReason:behaviorReason
                                               animationState:finalAnimation
                                             behaviorPriority:finalPriority
                                             behaviorCategory:finalCategory
                                                interruptible:finalInterruptible
                                               plannerContext:plannerContext.copy];
}

- (NSString *)resolvedBehaviorStateFromRule:(NSDictionary<NSString *, id> *)rule
                                     intent:(PETCharacterIntent *)intent
                                    profile:(PETPetProfile *)profile {
    NSString *strategy = [rule[@"behaviorStateFrom"] isKindOfClass:NSString.class] ? rule[@"behaviorStateFrom"] : @"value";
    NSString *configuredValue = [rule[@"behaviorState"] isKindOfClass:NSString.class] ? rule[@"behaviorState"] : @"idle";

    if ([strategy isEqualToString:@"fallback_or_value"]) {
        return intent.fallbackBehaviorState.length > 0 ? intent.fallbackBehaviorState : configuredValue;
    }
    if ([strategy isEqualToString:@"animation"]) {
        return intent.resolvedAnimationState.length > 0 ? intent.resolvedAnimationState : profile.defaultState;
    }
    if ([strategy isEqualToString:@"fallback_or_animation_or_value"]) {
        if (intent.fallbackBehaviorState.length > 0) {
            return intent.fallbackBehaviorState;
        }
        if (intent.resolvedAnimationState.length > 0) {
            return intent.resolvedAnimationState;
        }
        return configuredValue;
    }
    if ([strategy isEqualToString:@"animation_or_value"]) {
        return intent.resolvedAnimationState.length > 0 ? intent.resolvedAnimationState : configuredValue;
    }
    return configuredValue.length > 0 ? configuredValue : @"idle";
}

- (NSMutableDictionary<NSString *, NSNumber *> *)mutableCooldownsFromPlannerContext:(NSDictionary<NSString *, id> *)plannerContext {
    NSDictionary<NSString *, NSNumber *> *storedCooldowns = [plannerContext[@"cooldowns"] isKindOfClass:NSDictionary.class] ? plannerContext[@"cooldowns"] : @{};
    NSMutableDictionary<NSString *, NSNumber *> *cooldowns = [NSMutableDictionary dictionaryWithCapacity:storedCooldowns.count];
    [storedCooldowns enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSNumber * _Nonnull value, BOOL * _Nonnull stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [value respondsToSelector:@selector(doubleValue)]) {
            cooldowns[key] = @([value doubleValue]);
        }
    }];
    return cooldowns;
}

- (NSString *)cooldownKeyForIntent:(PETCharacterIntent *)intent {
    if (intent.actionKey.length > 0) {
        return [NSString stringWithFormat:@"action:%@", intent.actionKey];
    }
    return [NSString stringWithFormat:@"intent:%@", intent.name ?: @"runtime.react"];
}

- (BOOL)candidateCategory:(NSString *)candidateCategory
 mayInterruptCurrentCategory:(NSString *)currentCategory
                      rule:(NSDictionary<NSString *, id> *)rule
      currentInterruptible:(BOOL)currentInterruptible {
    if (currentCategory.length == 0) {
        return YES;
    }
    if (!currentInterruptible) {
        NSArray<NSString *> *allowed = [rule[@"allowedInterrupterCategories"] isKindOfClass:NSArray.class] ? rule[@"allowedInterrupterCategories"] : @[];
        return [allowed containsObject:currentCategory] || [allowed containsObject:candidateCategory];
    }

    NSArray<NSString *> *blocked = [rule[@"blockedCurrentCategories"] isKindOfClass:NSArray.class] ? rule[@"blockedCurrentCategories"] : @[];
    if ([blocked containsObject:currentCategory]) {
        return NO;
    }

    NSArray<NSString *> *allowedCurrent = [rule[@"allowedCurrentCategories"] isKindOfClass:NSArray.class] ? rule[@"allowedCurrentCategories"] : @[];
    if (allowedCurrent.count > 0 && ![allowedCurrent containsObject:currentCategory]) {
        return NO;
    }

    return YES;
}

- (NSDictionary<NSString *, id> *)yieldPolicyFromRule:(NSDictionary<NSString *, id> *)rule {
    NSMutableDictionary<NSString *, id> *policy = [NSMutableDictionary dictionary];
    NSArray<NSString *> *yieldToCategories = [rule[@"yieldToCategories"] isKindOfClass:NSArray.class] ? rule[@"yieldToCategories"] : @[];
    if (yieldToCategories.count > 0) {
        policy[@"yieldToCategories"] = yieldToCategories;
    }
    NSNumber *yieldAfterHold = [rule[@"yieldAfterHold"] respondsToSelector:@selector(boolValue)] ? @([rule[@"yieldAfterHold"] boolValue]) : nil;
    if (yieldAfterHold != nil) {
        policy[@"yieldAfterHold"] = yieldAfterHold;
    }
    NSNumber *yieldToHigherPriorityOnly = [rule[@"yieldToHigherPriorityOnly"] respondsToSelector:@selector(boolValue)] ? @([rule[@"yieldToHigherPriorityOnly"] boolValue]) : nil;
    if (yieldToHigherPriorityOnly != nil) {
        policy[@"yieldToHigherPriorityOnly"] = yieldToHigherPriorityOnly;
    }
    NSNumber *yieldPriorityMargin = [rule[@"yieldPriorityMargin"] respondsToSelector:@selector(integerValue)] ? @([rule[@"yieldPriorityMargin"] integerValue]) : nil;
    if (yieldPriorityMargin != nil) {
        policy[@"yieldPriorityMargin"] = yieldPriorityMargin;
    }
    return policy.copy;
}

- (BOOL)currentBehaviorShouldYieldToCandidateCategory:(NSString *)candidateCategory
                                    candidatePriority:(NSInteger)candidatePriority
                                      currentCategory:(NSString *)currentCategory
                                      currentPriority:(NSInteger)currentPriority
                                            holdUntil:(NSTimeInterval)holdUntil
                                                  now:(NSTimeInterval)now
                                          yieldPolicy:(NSDictionary<NSString *, id> *)yieldPolicy {
    if (yieldPolicy.count == 0 || candidateCategory.length == 0 || currentCategory.length == 0) {
        return NO;
    }

    NSArray<NSString *> *yieldToCategories = [yieldPolicy[@"yieldToCategories"] isKindOfClass:NSArray.class] ? yieldPolicy[@"yieldToCategories"] : @[];
    if (yieldToCategories.count > 0 && ![yieldToCategories containsObject:candidateCategory]) {
        return NO;
    }

    BOOL yieldAfterHold = [yieldPolicy[@"yieldAfterHold"] respondsToSelector:@selector(boolValue)] ? [yieldPolicy[@"yieldAfterHold"] boolValue] : NO;
    if (yieldAfterHold && holdUntil > now) {
        return NO;
    }

    BOOL higherPriorityOnly = [yieldPolicy[@"yieldToHigherPriorityOnly"] respondsToSelector:@selector(boolValue)] ? [yieldPolicy[@"yieldToHigherPriorityOnly"] boolValue] : NO;
    NSInteger priorityMargin = [yieldPolicy[@"yieldPriorityMargin"] respondsToSelector:@selector(integerValue)] ? [yieldPolicy[@"yieldPriorityMargin"] integerValue] : 0;
    if (higherPriorityOnly && candidatePriority < (currentPriority + priorityMargin)) {
        return NO;
    }

    return YES;
}

@end
