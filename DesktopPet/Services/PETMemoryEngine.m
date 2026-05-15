#import "PETMemoryEngine.h"

#import "../Models/PETBehaviorDecision.h"
#import "../Models/PETCharacterEmotion.h"
#import "../Models/PETCharacterGoal.h"
#import "../Models/PETCharacterIntent.h"
#import "../Models/PETCharacterMemoryEvent.h"
#import "../Models/PETCharacterSnapshot.h"
#import "../Models/PETCharacterTask.h"

static const NSUInteger PETMemoryTimelineLimit = 24;

@implementation PETMemoryEngine

- (NSArray<PETCharacterMemoryEvent *> *)timelineFromSnapshot:(PETCharacterSnapshot *)snapshot {
    NSArray<NSDictionary<NSString *, id> *> *serializedTimeline = [snapshot.context[@"memoryTimeline"] isKindOfClass:NSArray.class] ? snapshot.context[@"memoryTimeline"] : @[];
    NSMutableArray<PETCharacterMemoryEvent *> *timeline = [NSMutableArray arrayWithCapacity:serializedTimeline.count];
    for (NSDictionary<NSString *, id> *dictionary in serializedTimeline) {
        PETCharacterMemoryEvent *event = [PETCharacterMemoryEvent eventFromDictionary:dictionary];
        if (event != nil) {
            [timeline addObject:event];
        }
    }
    return timeline.copy;
}

- (NSArray<PETCharacterMemoryEvent *> *)updatedTimelineForIntent:(PETCharacterIntent *)intent
                                                         emotion:(PETCharacterEmotion *)emotion
                                                            goal:(PETCharacterGoal *)goal
                                                        decision:(PETBehaviorDecision *)decision
                                                       taskStack:(NSArray<PETCharacterTask *> *)taskStack
                                                previousSnapshot:(PETCharacterSnapshot *)previousSnapshot {
    NSMutableArray<PETCharacterMemoryEvent *> *timeline = [[self timelineFromSnapshot:previousSnapshot] mutableCopy] ?: [NSMutableArray array];
    NSDate *now = [NSDate date];

    [timeline addObject:[self eventForIntent:intent emotion:emotion decision:decision goal:goal timestamp:now]];
    [timeline addObjectsFromArray:[self taskLifecycleEventsFromTaskStack:taskStack previousSnapshot:previousSnapshot timestamp:now]];

    if (timeline.count > PETMemoryTimelineLimit) {
        NSRange overflow = NSMakeRange(0, timeline.count - PETMemoryTimelineLimit);
        [timeline removeObjectsInRange:overflow];
    }
    return timeline.copy;
}

- (PETCharacterMemoryEvent *)eventForIntent:(PETCharacterIntent *)intent
                                    emotion:(PETCharacterEmotion *)emotion
                                   decision:(PETBehaviorDecision *)decision
                                       goal:(PETCharacterGoal *)goal
                                  timestamp:(NSDate *)timestamp {
    NSString *eventType = @"interaction";
    NSInteger salience = 40;
    if ([intent.name isEqualToString:@"ambient.exist"]) {
        eventType = @"ambient";
        salience = 8;
    } else if ([intent.name isEqualToString:@"manual.preview"]) {
        eventType = @"manual";
        salience = 80;
    } else if ([intent.actionKey hasPrefix:@"drag."]) {
        eventType = @"locomotion";
        salience = 65;
    } else if ([intent.actionKey hasPrefix:@"tap."]) {
        eventType = @"social";
        salience = 55;
    }

    NSMutableDictionary<NSString *, id> *metadata = [NSMutableDictionary dictionary];
    metadata[@"intentName"] = intent.name ?: @"runtime.react";
    metadata[@"actionKey"] = intent.actionKey ?: @"";
    metadata[@"emotionLabel"] = emotion.label ?: @"alert";
    metadata[@"behaviorState"] = decision.behaviorState ?: @"idle";
    if (goal != nil) {
        metadata[@"goalName"] = goal.goalName ?: goal.goalIdentifier;
    }

    NSString *summary = [NSString stringWithFormat:@"%@ -> %@ (%@)",
                         intent.actionKey.length > 0 ? intent.actionKey : intent.name,
                         decision.behaviorState ?: @"idle",
                         emotion.label ?: @"alert"];
    NSString *identifier = [NSString stringWithFormat:@"%@-%f", eventType, timestamp.timeIntervalSince1970];
    return [[PETCharacterMemoryEvent alloc] initWithEventIdentifier:identifier
                                                          eventType:eventType
                                                            summary:summary
                                                           salience:salience
                                                           metadata:metadata.copy
                                                          timestamp:timestamp];
}

- (NSArray<PETCharacterMemoryEvent *> *)taskLifecycleEventsFromTaskStack:(NSArray<PETCharacterTask *> *)taskStack
                                                         previousSnapshot:(PETCharacterSnapshot *)previousSnapshot
                                                                timestamp:(NSDate *)timestamp {
    NSArray<PETCharacterTask *> *previousTasks = [self tasksFromPreviousSnapshot:previousSnapshot];
    NSMutableDictionary<NSString *, PETCharacterTask *> *previousById = [NSMutableDictionary dictionaryWithCapacity:previousTasks.count];
    for (PETCharacterTask *task in previousTasks) {
        previousById[task.taskIdentifier] = task;
    }

    NSMutableArray<PETCharacterMemoryEvent *> *events = [NSMutableArray array];
    for (PETCharacterTask *task in taskStack) {
        PETCharacterTask *previousTask = previousById[task.taskIdentifier];
        if (previousTask == nil) {
            [events addObject:[self lifecycleEventForTask:task kind:@"task-started" summaryPrefix:@"Started" salience:70 timestamp:timestamp]];
            continue;
        }
        if (![previousTask.status isEqualToString:task.status]) {
            NSString *kind = [task.status isEqualToString:@"completed"] ? @"task-completed" : ([task.status isEqualToString:@"failed"] ? @"task-failed" : @"task-status");
            NSInteger salience = [task.status isEqualToString:@"completed"] ? 90 : 85;
            NSString *prefix = [task.status isEqualToString:@"completed"] ? @"Completed" : ([task.status isEqualToString:@"failed"] ? @"Failed" : @"Updated");
            [events addObject:[self lifecycleEventForTask:task kind:kind summaryPrefix:prefix salience:salience timestamp:timestamp]];
            continue;
        }

        NSString *previousStepName = [previousTask.context[@"currentStepName"] isKindOfClass:NSString.class] ? previousTask.context[@"currentStepName"] : nil;
        NSString *currentStepName = [task.context[@"currentStepName"] isKindOfClass:NSString.class] ? task.context[@"currentStepName"] : nil;
        if (currentStepName.length > 0 && ![previousStepName isEqualToString:currentStepName]) {
            [events addObject:[self lifecycleEventForTask:task kind:@"task-step" summaryPrefix:@"Advanced" salience:75 timestamp:timestamp]];
        }
    }
    return events.copy;
}

- (NSArray<PETCharacterTask *> *)tasksFromPreviousSnapshot:(PETCharacterSnapshot *)snapshot {
    NSArray<NSDictionary<NSString *, id> *> *serializedTasks = [snapshot.context[@"tasks"] isKindOfClass:NSArray.class] ? snapshot.context[@"tasks"] : @[];
    NSMutableArray<PETCharacterTask *> *tasks = [NSMutableArray arrayWithCapacity:serializedTasks.count];
    for (NSDictionary<NSString *, id> *dictionary in serializedTasks) {
        PETCharacterTask *task = [PETCharacterTask taskFromDictionary:dictionary];
        if (task != nil) {
            [tasks addObject:task];
        }
    }
    return tasks.copy;
}

- (PETCharacterMemoryEvent *)lifecycleEventForTask:(PETCharacterTask *)task
                                              kind:(NSString *)kind
                                     summaryPrefix:(NSString *)summaryPrefix
                                          salience:(NSInteger)salience
                                         timestamp:(NSDate *)timestamp {
    NSString *stepName = [task.context[@"currentStepName"] isKindOfClass:NSString.class] ? task.context[@"currentStepName"] : nil;
    NSString *summary = stepName.length > 0 ? [NSString stringWithFormat:@"%@ %@ (%@)", summaryPrefix, task.taskName ?: task.taskIdentifier, stepName] : [NSString stringWithFormat:@"%@ %@", summaryPrefix, task.taskName ?: task.taskIdentifier];
    NSMutableDictionary<NSString *, id> *metadata = [NSMutableDictionary dictionary];
    metadata[@"taskIdentifier"] = task.taskIdentifier ?: @"task";
    metadata[@"taskName"] = task.taskName ?: @"task";
    metadata[@"status"] = task.status ?: @"active";
    metadata[@"progress"] = @(task.progress);
    metadata[@"requiredProgress"] = @(task.requiredProgress);
    if (stepName.length > 0) {
        metadata[@"stepName"] = stepName;
    }
    NSString *identifier = [NSString stringWithFormat:@"%@-%@-%f", kind, task.taskIdentifier ?: @"task", timestamp.timeIntervalSince1970];
    return [[PETCharacterMemoryEvent alloc] initWithEventIdentifier:identifier
                                                          eventType:kind
                                                            summary:summary
                                                           salience:salience
                                                           metadata:metadata.copy
                                                          timestamp:timestamp];
}

@end
