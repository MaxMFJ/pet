#import "PETGoalEngine.h"

#import "../Models/PETCharacterGoal.h"
#import "../Models/PETCharacterIntent.h"
#import "../Models/PETCharacterSnapshot.h"
#import "../Models/PETCharacterTask.h"
#import "PETCharacterSemanticConfig.h"

@implementation PETGoalEngine

- (PETCharacterGoal *)activeGoalFromSnapshot:(PETCharacterSnapshot *)snapshot {
    NSDictionary<NSString *, id> *goalDictionary = [snapshot.context[@"goal"] isKindOfClass:NSDictionary.class] ? snapshot.context[@"goal"] : nil;
    PETCharacterGoal *goal = [PETCharacterGoal goalFromDictionary:goalDictionary];
    if (goal == nil) {
        return nil;
    }
    return [goal isActiveAtDate:[NSDate date]] ? goal : nil;
}

- (PETCharacterGoal *)updatedGoalForIntent:(PETCharacterIntent *)intent
                          previousSnapshot:(PETCharacterSnapshot *)previousSnapshot {
    PETCharacterGoal *existingGoal = [self activeGoalFromSnapshot:previousSnapshot];
    NSDictionary<NSString *, id> *rule = [[PETCharacterSemanticConfig sharedConfig] goalRuleForIntentName:intent.name
                                                                                                 actionKey:intent.actionKey];
    NSString *goalName = [rule[@"goalName"] isKindOfClass:NSString.class] ? rule[@"goalName"] : nil;
    if (goalName.length == 0) {
        return existingGoal;
    }

    NSString *goalIdentifier = [rule[@"goalIdentifier"] isKindOfClass:NSString.class] ? rule[@"goalIdentifier"] : goalName;
    NSString *goalCategory = [rule[@"goalCategory"] isKindOfClass:NSString.class] ? rule[@"goalCategory"] : @"general";
    NSString *targetBehaviorState = [self resolvedGoalBehaviorStateFromRule:rule intent:intent existingGoal:existingGoal];
    NSInteger priority = [rule[@"priority"] respondsToSelector:@selector(integerValue)] ? [rule[@"priority"] integerValue] : 0;
    NSTimeInterval duration = [rule[@"duration"] respondsToSelector:@selector(doubleValue)] ? [rule[@"duration"] doubleValue] : 0.0;
    NSDate *expiresAt = duration > 0.0 ? [NSDate dateWithTimeIntervalSinceNow:duration] : nil;

    NSMutableDictionary<NSString *, id> *context = [NSMutableDictionary dictionary];
    if (existingGoal.context.count > 0) {
        [context addEntriesFromDictionary:existingGoal.context];
    }
    if (intent.context.count > 0) {
        [context addEntriesFromDictionary:intent.context];
    }
    context[@"sourceIntent"] = intent.name ?: @"runtime.react";

    return [[PETCharacterGoal alloc] initWithGoalIdentifier:goalIdentifier
                                                   goalName:goalName
                                               goalCategory:goalCategory
                                        targetBehaviorState:targetBehaviorState
                                                   priority:priority
                                                  expiresAt:expiresAt
                                                    context:context.copy];
}

- (PETCharacterGoal *)projectedGoalFromTask:(PETCharacterTask *)task {
    if (task == nil || ![task.status isEqualToString:@"active"]) {
        return nil;
    }
    NSString *goalIdentifier = [task.context[@"goalIdentifier"] isKindOfClass:NSString.class] ? task.context[@"goalIdentifier"] : task.taskIdentifier;
    NSString *goalName = [task.context[@"goalName"] isKindOfClass:NSString.class] ? task.context[@"goalName"] : task.taskName;
    NSString *goalCategory = [task.context[@"goalCategory"] isKindOfClass:NSString.class] ? task.context[@"goalCategory"] : task.taskCategory;
    NSString *targetBehaviorState = [task.context[@"targetBehaviorState"] isKindOfClass:NSString.class] ? task.context[@"targetBehaviorState"] : @"idle";
    NSString *stepName = [task.context[@"currentStepName"] isKindOfClass:NSString.class] ? task.context[@"currentStepName"] : nil;
    NSInteger priority = [task.context[@"goalPriority"] respondsToSelector:@selector(integerValue)] ? [task.context[@"goalPriority"] integerValue] : task.priority;
    NSDate *expiresAt = nil;
    if ([task.context[@"goalExpiresAt"] respondsToSelector:@selector(doubleValue)]) {
        expiresAt = [NSDate dateWithTimeIntervalSince1970:[task.context[@"goalExpiresAt"] doubleValue]];
    }
    return [[PETCharacterGoal alloc] initWithGoalIdentifier:goalIdentifier
                                                   goalName:stepName.length > 0 ? [NSString stringWithFormat:@"%@:%@", goalName, stepName] : goalName
                                               goalCategory:goalCategory
                                        targetBehaviorState:targetBehaviorState
                                                   priority:priority
                                                  expiresAt:expiresAt
                                                    context:task.context];
}

- (NSString *)resolvedGoalBehaviorStateFromRule:(NSDictionary<NSString *, id> *)rule
                                         intent:(PETCharacterIntent *)intent
                                   existingGoal:(PETCharacterGoal *)existingGoal {
    NSString *strategy = [rule[@"targetBehaviorStateFrom"] isKindOfClass:NSString.class] ? rule[@"targetBehaviorStateFrom"] : @"value";
    NSString *configuredValue = [rule[@"targetBehaviorState"] isKindOfClass:NSString.class] ? rule[@"targetBehaviorState"] : @"idle";

    if ([strategy isEqualToString:@"fallback_or_value"]) {
        return intent.fallbackBehaviorState.length > 0 ? intent.fallbackBehaviorState : configuredValue;
    }
    if ([strategy isEqualToString:@"animation_or_value"]) {
        return intent.resolvedAnimationState.length > 0 ? intent.resolvedAnimationState : configuredValue;
    }
    if ([strategy isEqualToString:@"existing_or_value"]) {
        return existingGoal.targetBehaviorState.length > 0 ? existingGoal.targetBehaviorState : configuredValue;
    }
    return configuredValue;
}

@end
