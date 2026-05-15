#import "PETTaskEngine.h"

#import "../Models/PETCharacterGoal.h"
#import "../Models/PETCharacterIntent.h"
#import "../Models/PETCharacterSnapshot.h"
#import "../Models/PETCharacterTask.h"
#import "PETCharacterSemanticConfig.h"

@implementation PETTaskEngine

- (NSArray<PETCharacterTask *> *)taskStackFromSnapshot:(PETCharacterSnapshot *)snapshot {
    NSArray<NSDictionary<NSString *, id> *> *serializedTasks = [snapshot.context[@"tasks"] isKindOfClass:NSArray.class] ? snapshot.context[@"tasks"] : @[];
    NSMutableArray<PETCharacterTask *> *tasks = [NSMutableArray arrayWithCapacity:serializedTasks.count];
    for (NSDictionary<NSString *, id> *dictionary in serializedTasks) {
        PETCharacterTask *task = [PETCharacterTask taskFromDictionary:dictionary];
        if (task != nil) {
            [tasks addObject:task];
        }
    }
    return [self prunedTaskStack:tasks referenceDate:[NSDate date]];
}

- (NSArray<PETCharacterTask *> *)updatedTaskStackForIntent:(PETCharacterIntent *)intent
                                                      goal:(PETCharacterGoal *)goal
                                          previousSnapshot:(PETCharacterSnapshot *)previousSnapshot {
    NSDate *now = [NSDate date];
    NSMutableArray<PETCharacterTask *> *tasks = [[self taskStackFromSnapshot:previousSnapshot] mutableCopy] ?: [NSMutableArray array];
    tasks = [[self taskStackByApplyingLifecycleRulesToTasks:tasks intent:intent now:now] mutableCopy];
    NSDictionary<NSString *, id> *rule = [[PETCharacterSemanticConfig sharedConfig] taskRuleForIntentName:intent.name
                                                                                                 actionKey:intent.actionKey];
    NSString *taskName = [rule[@"taskName"] isKindOfClass:NSString.class] ? rule[@"taskName"] : nil;
    if (taskName.length == 0) {
        return [self prunedTaskStack:tasks referenceDate:now];
    }

    NSString *taskIdentifier = [rule[@"taskIdentifier"] isKindOfClass:NSString.class] ? rule[@"taskIdentifier"] : taskName;
    NSInteger priority = [rule[@"priority"] respondsToSelector:@selector(integerValue)] ? [rule[@"priority"] integerValue] : 0;
    NSString *taskCategory = [rule[@"taskCategory"] isKindOfClass:NSString.class] ? rule[@"taskCategory"] : @"general";
    NSTimeInterval duration = [rule[@"duration"] respondsToSelector:@selector(doubleValue)] ? [rule[@"duration"] doubleValue] : 0.0;
    NSDate *expiresAt = duration > 0.0 ? [now dateByAddingTimeInterval:duration] : nil;
    NSArray<NSDictionary<NSString *, id> *> *steps = [rule[@"steps"] isKindOfClass:NSArray.class] ? rule[@"steps"] : @[];

    NSUInteger existingIndex = [tasks indexOfObjectPassingTest:^BOOL(PETCharacterTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)idx;
        (void)stop;
        return [task.taskIdentifier isEqualToString:taskIdentifier];
    }];

    PETCharacterTask *existingTask = existingIndex != NSNotFound ? tasks[existingIndex] : nil;
    NSMutableDictionary<NSString *, id> *context = [NSMutableDictionary dictionary];
    if (existingTask.context.count > 0) {
        [context addEntriesFromDictionary:existingTask.context];
    }
    context[@"steps"] = steps;
    NSInteger stepIndex = [self resolvedStepIndexForExistingTask:existingTask steps:steps];
    NSDictionary<NSString *, id> *activeStep = [self activeStepAtIndex:stepIndex steps:steps fallbackRule:rule];
    NSInteger requiredProgress = [self requiredProgressForStep:activeStep fallbackRule:rule];
    NSInteger progressIncrement = [self progressIncrementForStep:activeStep fallbackRule:rule];
    NSString *progressMode = [self progressModeForStep:activeStep fallbackRule:rule];

    if (goal != nil) {
        context[@"goalIdentifier"] = goal.goalIdentifier ?: @"goal";
        context[@"goalName"] = goal.goalName ?: @"goal";
        context[@"goalCategory"] = goal.goalCategory ?: @"general";
        context[@"goalPriority"] = @(goal.priority);
        context[@"targetBehaviorState"] = goal.targetBehaviorState ?: @"idle";
        if (goal.expiresAt != nil) {
            context[@"goalExpiresAt"] = @([goal.expiresAt timeIntervalSince1970]);
        }
    }
    context[@"sourceIntent"] = intent.name ?: @"runtime.react";
    context[@"progressMode"] = progressMode;
    context[@"currentStepIndex"] = @(stepIndex);
    context[@"currentStepName"] = [activeStep[@"name"] isKindOfClass:NSString.class] ? activeStep[@"name"] : taskName;
    NSString *stepTargetBehavior = [activeStep[@"targetBehaviorState"] isKindOfClass:NSString.class] ? activeStep[@"targetBehaviorState"] : context[@"targetBehaviorState"];
    if (stepTargetBehavior.length > 0) {
        context[@"targetBehaviorState"] = stepTargetBehavior;
    }
    NSArray<NSString *> *completeOnPrefixes = [activeStep[@"completeOnActionPrefixes"] isKindOfClass:NSArray.class] ? activeStep[@"completeOnActionPrefixes"] : @[];
    if (completeOnPrefixes.count > 0) {
        context[@"completeOnActionPrefixes"] = completeOnPrefixes;
    }
    NSArray<NSString *> *failOnPrefixes = [activeStep[@"failOnActionPrefixes"] isKindOfClass:NSArray.class] ? activeStep[@"failOnActionPrefixes"] : @[];
    if (failOnPrefixes.count > 0) {
        context[@"failOnActionPrefixes"] = failOnPrefixes;
    }

    NSInteger nextProgress = existingTask.progress;
    if ([progressMode isEqualToString:@"increment"]) {
        nextProgress = MIN(requiredProgress, nextProgress + progressIncrement);
    } else {
        nextProgress = MAX(existingTask.progress, MIN(requiredProgress, progressIncrement));
    }

    BOOL completesCurrentStep = [self intent:intent matchesAnyActionPrefix:completeOnPrefixes];
    if ([progressMode isEqualToString:@"increment"] && nextProgress >= requiredProgress) {
        completesCurrentStep = YES;
    }

    PETCharacterTask *updatedTask = [[PETCharacterTask alloc] initWithTaskIdentifier:taskIdentifier
                                                                             taskName:taskName
                                                                         taskCategory:taskCategory
                                                                               status:@"active"
                                                                             priority:priority
                                                                             progress:nextProgress
                                                                     requiredProgress:requiredProgress
                                                                              context:context.copy
                                                                            createdAt:existingTask.createdAt ?: now
                                                                            updatedAt:now
                                                                            expiresAt:expiresAt ?: existingTask.expiresAt];

    if (completesCurrentStep) {
        updatedTask = [self taskByAdvancingTask:updatedTask
                                          steps:steps
                                           rule:rule
                                            now:now];
    }

    if (existingIndex != NSNotFound) {
        tasks[existingIndex] = updatedTask;
    } else {
        [tasks addObject:updatedTask];
    }

    return [self prunedTaskStack:tasks referenceDate:now];
}

- (PETCharacterTask *)activeTaskInTaskStack:(NSArray<PETCharacterTask *> *)taskStack {
    NSDate *now = [NSDate date];
    PETCharacterTask *activeTask = nil;
    for (PETCharacterTask *task in taskStack) {
        if (![task isActiveAtDate:now]) {
            continue;
        }
        if (activeTask == nil || task.priority > activeTask.priority) {
            activeTask = task;
        }
    }
    return activeTask;
}

- (NSArray<PETCharacterTask *> *)prunedTaskStack:(NSArray<PETCharacterTask *> *)taskStack
                                   referenceDate:(NSDate *)referenceDate {
    NSMutableArray<PETCharacterTask *> *pruned = [NSMutableArray array];
    for (PETCharacterTask *task in taskStack) {
        if ([task isActiveAtDate:referenceDate] || [task.status isEqualToString:@"completed"]) {
            [pruned addObject:task];
        }
    }
    return [pruned sortedArrayUsingComparator:^NSComparisonResult(PETCharacterTask * _Nonnull left, PETCharacterTask * _Nonnull right) {
        if (left.priority > right.priority) {
            return NSOrderedAscending;
        }
        if (left.priority < right.priority) {
            return NSOrderedDescending;
        }
        return [right.updatedAt compare:left.updatedAt];
    }];
}

- (NSMutableArray<PETCharacterTask *> *)taskStackByApplyingLifecycleRulesToTasks:(NSArray<PETCharacterTask *> *)tasks
                                                                           intent:(PETCharacterIntent *)intent
                                                                              now:(NSDate *)now {
    NSMutableArray<PETCharacterTask *> *updated = [NSMutableArray arrayWithCapacity:tasks.count];
    for (PETCharacterTask *task in tasks) {
        if (![task.status isEqualToString:@"active"]) {
            [updated addObject:task];
            continue;
        }
        NSArray<NSString *> *failOnPrefixes = [task.context[@"failOnActionPrefixes"] isKindOfClass:NSArray.class] ? task.context[@"failOnActionPrefixes"] : @[];
        if ([self intent:intent matchesAnyActionPrefix:failOnPrefixes]) {
            NSMutableDictionary<NSString *, id> *context = [task.context mutableCopy] ?: [NSMutableDictionary dictionary];
            context[@"failureActionKey"] = intent.actionKey ?: @"";
            PETCharacterTask *failedTask = [[PETCharacterTask alloc] initWithTaskIdentifier:task.taskIdentifier
                                                                                   taskName:task.taskName
                                                                               taskCategory:task.taskCategory
                                                                                     status:@"failed"
                                                                                   priority:task.priority
                                                                                   progress:task.progress
                                                                           requiredProgress:task.requiredProgress
                                                                                    context:context.copy
                                                                                  createdAt:task.createdAt
                                                                                  updatedAt:now
                                                                                  expiresAt:task.expiresAt];
            [updated addObject:failedTask];
            continue;
        }
        [updated addObject:task];
    }
    return updated;
}

- (PETCharacterTask *)taskByAdvancingTask:(PETCharacterTask *)task
                                    steps:(NSArray<NSDictionary<NSString *, id> *> *)steps
                                     rule:(NSDictionary<NSString *, id> *)rule
                                      now:(NSDate *)now {
    NSInteger currentStepIndex = [task.context[@"currentStepIndex"] respondsToSelector:@selector(integerValue)] ? [task.context[@"currentStepIndex"] integerValue] : NSNotFound;
    NSInteger nextStepIndex = currentStepIndex + 1;
    if (steps.count == 0 || nextStepIndex >= (NSInteger)steps.count) {
        NSMutableDictionary<NSString *, id> *context = [task.context mutableCopy] ?: [NSMutableDictionary dictionary];
        context[@"completedAt"] = @([now timeIntervalSince1970]);
        return [[PETCharacterTask alloc] initWithTaskIdentifier:task.taskIdentifier
                                                       taskName:task.taskName
                                                   taskCategory:task.taskCategory
                                                         status:@"completed"
                                                       priority:task.priority
                                                       progress:task.requiredProgress
                                               requiredProgress:task.requiredProgress
                                                        context:context.copy
                                                      createdAt:task.createdAt
                                                      updatedAt:now
                                                      expiresAt:task.expiresAt];
    }

    NSDictionary<NSString *, id> *nextStep = steps[nextStepIndex];
    NSMutableDictionary<NSString *, id> *context = [task.context mutableCopy] ?: [NSMutableDictionary dictionary];
    context[@"currentStepIndex"] = @(nextStepIndex);
    context[@"currentStepName"] = [nextStep[@"name"] isKindOfClass:NSString.class] ? nextStep[@"name"] : task.taskName;
    NSString *targetBehaviorState = [nextStep[@"targetBehaviorState"] isKindOfClass:NSString.class] ? nextStep[@"targetBehaviorState"] : context[@"targetBehaviorState"];
    if (targetBehaviorState.length > 0) {
        context[@"targetBehaviorState"] = targetBehaviorState;
    }
    NSArray<NSString *> *completeOnPrefixes = [nextStep[@"completeOnActionPrefixes"] isKindOfClass:NSArray.class] ? nextStep[@"completeOnActionPrefixes"] : @[];
    if (completeOnPrefixes.count > 0) {
        context[@"completeOnActionPrefixes"] = completeOnPrefixes;
    } else {
        [context removeObjectForKey:@"completeOnActionPrefixes"];
    }
    NSArray<NSString *> *failOnPrefixes = [nextStep[@"failOnActionPrefixes"] isKindOfClass:NSArray.class] ? nextStep[@"failOnActionPrefixes"] : @[];
    if (failOnPrefixes.count > 0) {
        context[@"failOnActionPrefixes"] = failOnPrefixes;
    } else {
        [context removeObjectForKey:@"failOnActionPrefixes"];
    }
    context[@"progressMode"] = [self progressModeForStep:nextStep fallbackRule:rule];
    context[@"lastTransitionAt"] = @([now timeIntervalSince1970]);

    NSInteger requiredProgress = [self requiredProgressForStep:nextStep fallbackRule:rule];
    return [[PETCharacterTask alloc] initWithTaskIdentifier:task.taskIdentifier
                                                   taskName:task.taskName
                                               taskCategory:task.taskCategory
                                                     status:@"active"
                                                   priority:task.priority
                                                   progress:0
                                           requiredProgress:requiredProgress
                                                    context:context.copy
                                                  createdAt:task.createdAt
                                                  updatedAt:now
                                                  expiresAt:task.expiresAt];
}

- (NSInteger)resolvedStepIndexForExistingTask:(PETCharacterTask *)existingTask
                                        steps:(NSArray<NSDictionary<NSString *, id> *> *)steps {
    if (existingTask == nil || steps.count == 0) {
        return 0;
    }
    NSInteger stepIndex = [existingTask.context[@"currentStepIndex"] respondsToSelector:@selector(integerValue)] ? [existingTask.context[@"currentStepIndex"] integerValue] : 0;
    return MAX(0, MIN(stepIndex, (NSInteger)steps.count - 1));
}

- (NSDictionary<NSString *, id> *)activeStepAtIndex:(NSInteger)stepIndex
                                              steps:(NSArray<NSDictionary<NSString *, id> *> *)steps
                                       fallbackRule:(NSDictionary<NSString *, id> *)rule {
    if (steps.count == 0 || stepIndex >= (NSInteger)steps.count) {
        return rule;
    }
    return [steps[stepIndex] isKindOfClass:NSDictionary.class] ? steps[stepIndex] : rule;
}

- (NSInteger)requiredProgressForStep:(NSDictionary<NSString *, id> *)step
                        fallbackRule:(NSDictionary<NSString *, id> *)rule {
    id value = [step[@"requiredProgress"] respondsToSelector:@selector(integerValue)] ? step[@"requiredProgress"] : rule[@"requiredProgress"];
    return MAX(1, [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 1);
}

- (NSInteger)progressIncrementForStep:(NSDictionary<NSString *, id> *)step
                         fallbackRule:(NSDictionary<NSString *, id> *)rule {
    id value = [step[@"progressIncrement"] respondsToSelector:@selector(integerValue)] ? step[@"progressIncrement"] : rule[@"progressIncrement"];
    return MAX(0, [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 1);
}

- (NSString *)progressModeForStep:(NSDictionary<NSString *, id> *)step
                     fallbackRule:(NSDictionary<NSString *, id> *)rule {
    NSString *value = [step[@"progressMode"] isKindOfClass:NSString.class] ? step[@"progressMode"] : nil;
    if (value.length == 0) {
        value = [rule[@"progressMode"] isKindOfClass:NSString.class] ? rule[@"progressMode"] : nil;
    }
    return value.length > 0 ? value : @"increment";
}

- (BOOL)intent:(PETCharacterIntent *)intent matchesAnyActionPrefix:(NSArray<NSString *> *)prefixes {
    if (intent.actionKey.length == 0 || prefixes.count == 0) {
        return NO;
    }
    for (NSString *prefix in prefixes) {
        if ([prefix isKindOfClass:NSString.class] && prefix.length > 0 && [intent.actionKey hasPrefix:prefix]) {
            return YES;
        }
    }
    return NO;
}

@end
