#import "PETCharacterRuntimeController.h"

#import "../Models/PETBehaviorDecision.h"
#import "../Models/PETCharacterGoal.h"
#import "../Models/PETCharacterEmotion.h"
#import "../Models/PETCharacterIntent.h"
#import "../Models/PETCharacterMemoryEvent.h"
#import "../Models/PETCharacterSnapshot.h"
#import "../Models/PETStructuredCognitionSuggestion.h"
#import "../Models/PETCharacterTask.h"
#import "../Models/PETPetProfile.h"
#import "PETBehaviorPlanner.h"
#import "PETEmotionEngine.h"
#import "PETGoalEngine.h"
#import "PETIntentEngine.h"
#import "PETMemoryEngine.h"
#import "PETTaskEngine.h"

@interface PETCharacterRuntimeController ()

@property (nonatomic, strong, readwrite) PETPetProfile *profile;
@property (nonatomic, strong, readwrite) PETCharacterSnapshot *currentSnapshot;
@property (nonatomic, strong) PETIntentEngine *intentEngine;
@property (nonatomic, strong) PETEmotionEngine *emotionEngine;
@property (nonatomic, strong) PETGoalEngine *goalEngine;
@property (nonatomic, strong) PETMemoryEngine *memoryEngine;
@property (nonatomic, strong) PETTaskEngine *taskEngine;
@property (nonatomic, strong) PETBehaviorPlanner *behaviorPlanner;

@end

@implementation PETCharacterRuntimeController

- (NSString *)validatedAnimationStateForRequestedState:(NSString *)requestedState behaviorState:(NSString *)behaviorState {
    if (requestedState.length > 0 && [self.profile.supportedStates containsObject:requestedState]) {
        return requestedState;
    }

    NSString *resolvedBehaviorState = [self.profile resolvedAnimationStateForBehaviorState:behaviorState];
    if (resolvedBehaviorState.length > 0) {
        return resolvedBehaviorState;
    }

    if (self.profile.defaultState.length > 0 && [self.profile.supportedStates containsObject:self.profile.defaultState]) {
        return self.profile.defaultState;
    }

    return self.profile.supportedStates.firstObject ?: requestedState ?: @"";
}

- (instancetype)initWithProfile:(PETPetProfile *)profile {
    self = [super init];
    if (self) {
        _profile = profile;
        _intentEngine = [[PETIntentEngine alloc] init];
        _emotionEngine = [[PETEmotionEngine alloc] init];
        _goalEngine = [[PETGoalEngine alloc] init];
        _memoryEngine = [[PETMemoryEngine alloc] init];
        _taskEngine = [[PETTaskEngine alloc] init];
        _behaviorPlanner = [[PETBehaviorPlanner alloc] init];
        [self resumeAmbientBehavior];
    }
    return self;
}

- (void)restoreFromSerializedSnapshot:(NSDictionary<NSString *,id> *)snapshotDictionary {
    PETCharacterSnapshot *snapshot = [PETCharacterSnapshot snapshotFromDictionary:snapshotDictionary];
    if (snapshot != nil) {
        NSString *validatedAnimationState = [self validatedAnimationStateForRequestedState:snapshot.animationState
                                                                             behaviorState:snapshot.behaviorState];
        if (validatedAnimationState.length > 0 && ![validatedAnimationState isEqualToString:snapshot.animationState]) {
            snapshot = [[PETCharacterSnapshot alloc] initWithIntentName:snapshot.intentName
                                                           intentSource:snapshot.intentSource
                                                       intentConfidence:snapshot.intentConfidence
                                                           emotionLabel:snapshot.emotionLabel
                                                         emotionValence:snapshot.emotionValence
                                                         emotionArousal:snapshot.emotionArousal
                                                          behaviorState:snapshot.behaviorState
                                                           behaviorMode:snapshot.behaviorMode
                                                         behaviorReason:snapshot.behaviorReason
                                                         animationState:validatedAnimationState
                                                                context:snapshot.context
                                                              timestamp:snapshot.timestamp];
        }
        self.currentSnapshot = snapshot;
    }
}

- (void)recordActionKey:(NSString *)actionKey
  fallbackBehaviorState:(NSString *)fallbackBehaviorState
 resolvedAnimationState:(NSString *)resolvedAnimationState
                context:(NSDictionary<NSString *,id> *)context {
    PETCharacterIntent *intent = [self.intentEngine intentForActionKey:actionKey
                                                 fallbackBehaviorState:fallbackBehaviorState
                                                resolvedAnimationState:resolvedAnimationState
                                                               context:context];
    PETCharacterEmotion *emotion = [self.emotionEngine emotionForIntent:intent previousSnapshot:self.currentSnapshot];
    PETCharacterGoal *goal = [self.goalEngine updatedGoalForIntent:intent previousSnapshot:self.currentSnapshot];
    NSArray<PETCharacterTask *> *taskStack = [self.taskEngine updatedTaskStackForIntent:intent goal:goal previousSnapshot:self.currentSnapshot];
    PETCharacterTask *activeTask = [self.taskEngine activeTaskInTaskStack:taskStack];
    PETCharacterGoal *effectiveGoal = goal ?: [self.goalEngine projectedGoalFromTask:activeTask];
    PETBehaviorDecision *decision = [self.behaviorPlanner planBehaviorForIntent:intent
                                                                        emotion:emotion
                                                                          goal:effectiveGoal
                                                                        profile:self.profile
                                                               previousSnapshot:self.currentSnapshot];

    NSMutableDictionary<NSString *, id> *mergedContext = [NSMutableDictionary dictionary];
    if (self.currentSnapshot.context.count > 0) {
        [mergedContext addEntriesFromDictionary:self.currentSnapshot.context];
    }
    if (intent.context.count > 0) {
        [mergedContext addEntriesFromDictionary:intent.context];
    }
    if (intent.actionKey.length > 0) {
        mergedContext[@"lastActionKey"] = intent.actionKey;
    }
    if (decision.plannerContext.count > 0) {
        mergedContext[@"planner"] = decision.plannerContext;
    }
    if (effectiveGoal != nil) {
        mergedContext[@"goal"] = [effectiveGoal serializedRepresentation];
    } else {
        [mergedContext removeObjectForKey:@"goal"];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *serializedTasks = [NSMutableArray arrayWithCapacity:taskStack.count];
    for (PETCharacterTask *task in taskStack) {
        [serializedTasks addObject:[task serializedRepresentation]];
    }
    mergedContext[@"tasks"] = serializedTasks.copy;
    NSArray<PETCharacterMemoryEvent *> *timeline = [self.memoryEngine updatedTimelineForIntent:intent
                                                                                       emotion:emotion
                                                                                          goal:effectiveGoal
                                                                                      decision:decision
                                                                                     taskStack:taskStack
                                                                              previousSnapshot:self.currentSnapshot];
    NSMutableArray<NSDictionary<NSString *, id> *> *serializedTimeline = [NSMutableArray arrayWithCapacity:timeline.count];
    for (PETCharacterMemoryEvent *event in timeline) {
        [serializedTimeline addObject:[event serializedRepresentation]];
    }
    mergedContext[@"memoryTimeline"] = serializedTimeline.copy;

    self.currentSnapshot = [[PETCharacterSnapshot alloc] initWithIntentName:intent.name
                                                               intentSource:intent.source
                                                           intentConfidence:intent.confidence
                                                               emotionLabel:emotion.label
                                                             emotionValence:emotion.valence
                                                             emotionArousal:emotion.arousal
                                                              behaviorState:decision.behaviorState
                                                               behaviorMode:decision.behaviorMode
                                                             behaviorReason:decision.behaviorReason
                                                             animationState:decision.animationState.length > 0 ? decision.animationState : self.profile.defaultState
                                                                    context:mergedContext.copy
                                                                  timestamp:[NSDate date]];
}

- (void)previewAnimationState:(NSString *)animationState {
    NSString *resolvedState = animationState.length > 0 ? animationState : self.profile.defaultState;
    PETCharacterIntent *intent = [self.intentEngine manualPreviewIntentWithAnimationState:resolvedState
                                                                                   context:self.currentSnapshot.context];
    PETCharacterEmotion *emotion = [self.emotionEngine emotionForIntent:intent previousSnapshot:self.currentSnapshot];
    PETCharacterGoal *goal = [self.goalEngine updatedGoalForIntent:intent previousSnapshot:self.currentSnapshot];
    NSArray<PETCharacterTask *> *taskStack = [self.taskEngine updatedTaskStackForIntent:intent goal:goal previousSnapshot:self.currentSnapshot];
    PETCharacterTask *activeTask = [self.taskEngine activeTaskInTaskStack:taskStack];
    PETCharacterGoal *effectiveGoal = goal ?: [self.goalEngine projectedGoalFromTask:activeTask];
    PETBehaviorDecision *decision = [self.behaviorPlanner planBehaviorForIntent:intent
                                                                        emotion:emotion
                                                                          goal:effectiveGoal
                                                                        profile:self.profile
                                                               previousSnapshot:self.currentSnapshot];
    NSMutableDictionary<NSString *, id> *context = [self.currentSnapshot.context mutableCopy] ?: [NSMutableDictionary dictionary];
    if (decision.plannerContext.count > 0) {
        context[@"planner"] = decision.plannerContext;
    }
    if (effectiveGoal != nil) {
        context[@"goal"] = [effectiveGoal serializedRepresentation];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *serializedTasks = [NSMutableArray arrayWithCapacity:taskStack.count];
    for (PETCharacterTask *task in taskStack) {
        [serializedTasks addObject:[task serializedRepresentation]];
    }
    context[@"tasks"] = serializedTasks.copy;
    NSArray<PETCharacterMemoryEvent *> *timeline = [self.memoryEngine updatedTimelineForIntent:intent
                                                                                       emotion:emotion
                                                                                          goal:effectiveGoal
                                                                                      decision:decision
                                                                                     taskStack:taskStack
                                                                              previousSnapshot:self.currentSnapshot];
    NSMutableArray<NSDictionary<NSString *, id> *> *serializedTimeline = [NSMutableArray arrayWithCapacity:timeline.count];
    for (PETCharacterMemoryEvent *event in timeline) {
        [serializedTimeline addObject:[event serializedRepresentation]];
    }
    context[@"memoryTimeline"] = serializedTimeline.copy;
    self.currentSnapshot = [[PETCharacterSnapshot alloc] initWithIntentName:intent.name
                                                               intentSource:intent.source
                                                           intentConfidence:intent.confidence
                                                               emotionLabel:emotion.label
                                                             emotionValence:emotion.valence
                                                             emotionArousal:emotion.arousal
                                                              behaviorState:decision.behaviorState
                                                               behaviorMode:decision.behaviorMode
                                                             behaviorReason:decision.behaviorReason
                                                             animationState:decision.animationState
                                                                    context:context.copy
                                                                  timestamp:[NSDate date]];
}

- (void)resumeAmbientBehavior {
    NSString *idleState = [self.profile resolvedAnimationStateForBehaviorState:@"idle"] ?: self.profile.defaultState;
    PETCharacterIntent *intent = [self.intentEngine ambientIntentWithAnimationState:idleState
                                                                            context:self.currentSnapshot.context];
    PETCharacterEmotion *emotion = [self.emotionEngine emotionForIntent:intent previousSnapshot:self.currentSnapshot];
    PETCharacterGoal *goal = [self.goalEngine updatedGoalForIntent:intent previousSnapshot:self.currentSnapshot];
    NSArray<PETCharacterTask *> *taskStack = [self.taskEngine updatedTaskStackForIntent:intent goal:goal previousSnapshot:self.currentSnapshot];
    PETCharacterTask *activeTask = [self.taskEngine activeTaskInTaskStack:taskStack];
    PETCharacterGoal *effectiveGoal = goal ?: [self.goalEngine projectedGoalFromTask:activeTask];
    PETBehaviorDecision *decision = [self.behaviorPlanner planBehaviorForIntent:intent
                                                                        emotion:emotion
                                                                          goal:effectiveGoal
                                                                        profile:self.profile
                                                               previousSnapshot:self.currentSnapshot];
    NSMutableDictionary<NSString *, id> *context = [self.currentSnapshot.context mutableCopy] ?: [NSMutableDictionary dictionary];
    if (decision.plannerContext.count > 0) {
        context[@"planner"] = decision.plannerContext;
    }
    if (effectiveGoal != nil) {
        context[@"goal"] = [effectiveGoal serializedRepresentation];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *serializedTasks = [NSMutableArray arrayWithCapacity:taskStack.count];
    for (PETCharacterTask *task in taskStack) {
        [serializedTasks addObject:[task serializedRepresentation]];
    }
    context[@"tasks"] = serializedTasks.copy;
    NSArray<PETCharacterMemoryEvent *> *timeline = [self.memoryEngine updatedTimelineForIntent:intent
                                                                                       emotion:emotion
                                                                                          goal:effectiveGoal
                                                                                      decision:decision
                                                                                     taskStack:taskStack
                                                                              previousSnapshot:self.currentSnapshot];
    NSMutableArray<NSDictionary<NSString *, id> *> *serializedTimeline = [NSMutableArray arrayWithCapacity:timeline.count];
    for (PETCharacterMemoryEvent *event in timeline) {
        [serializedTimeline addObject:[event serializedRepresentation]];
    }
    context[@"memoryTimeline"] = serializedTimeline.copy;
    self.currentSnapshot = [[PETCharacterSnapshot alloc] initWithIntentName:intent.name
                                                               intentSource:intent.source
                                                           intentConfidence:intent.confidence
                                                               emotionLabel:emotion.label
                                                             emotionValence:emotion.valence
                                                             emotionArousal:emotion.arousal
                                                              behaviorState:decision.behaviorState
                                                               behaviorMode:decision.behaviorMode
                                                             behaviorReason:@"ambient.loop"
                                                             animationState:decision.animationState
                                                                    context:context.copy
                                                                  timestamp:[NSDate date]];
}

- (NSDictionary<NSString *,id> *)serializedSnapshot {
    return [self.currentSnapshot serializedRepresentation];
}

- (void)applyStructuredCognitionSuggestion:(PETStructuredCognitionSuggestion *)suggestion {
    if (suggestion == nil || ![suggestion.actionKey hasPrefix:@"cognition."]) {
        return;
    }
    NSMutableDictionary<NSString *, id> *context = [suggestion.context mutableCopy] ?: [NSMutableDictionary dictionary];
    context[@"runtimeMode"] = @"cognition";
    context[@"cognitionSummary"] = suggestion.summary ?: @"structured-cognition";
    if (suggestion.goalHint.length > 0) {
        context[@"goalHint"] = suggestion.goalHint;
    }
    context[@"cognitionConfidence"] = @(suggestion.confidence);
    NSString *resolvedAnimationState = self.currentSnapshot.animationState.length > 0 ? self.currentSnapshot.animationState : self.profile.defaultState;
    [self recordActionKey:suggestion.actionKey
    fallbackBehaviorState:self.currentSnapshot.behaviorState
   resolvedAnimationState:resolvedAnimationState
                  context:context.copy];
}

- (NSString *)runtimeSummary {
    PETCharacterGoal *goal = [self.goalEngine activeGoalFromSnapshot:self.currentSnapshot];
    PETCharacterTask *task = [self.taskEngine activeTaskInTaskStack:[self.taskEngine taskStackFromSnapshot:self.currentSnapshot]];
    NSMutableString *summary = [[self.currentSnapshot runtimeSummary] mutableCopy];
    if (task != nil) {
        [summary appendFormat:@" | Task %@ %ld/%ld",
         task.taskName ?: task.taskIdentifier,
         (long)task.progress,
         (long)task.requiredProgress];
    }
    if (goal != nil) {
        [summary appendFormat:@" | Goal %@", goal.goalName ?: goal.goalIdentifier];
    }
    NSArray<PETCharacterMemoryEvent *> *timeline = [self.memoryEngine timelineFromSnapshot:self.currentSnapshot];
    if (timeline.count > 0) {
        PETCharacterMemoryEvent *latestEvent = timeline.lastObject;
        [summary appendFormat:@" | Memory %@", latestEvent.eventType ?: @"runtime"];
    }
    return summary.copy;
}

@end
