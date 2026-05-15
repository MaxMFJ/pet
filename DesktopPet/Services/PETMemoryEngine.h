#import <Foundation/Foundation.h>

@class PETBehaviorDecision;
@class PETCharacterEmotion;
@class PETCharacterGoal;
@class PETCharacterIntent;
@class PETCharacterMemoryEvent;
@class PETCharacterSnapshot;
@class PETCharacterTask;

NS_ASSUME_NONNULL_BEGIN

@interface PETMemoryEngine : NSObject

- (NSArray<PETCharacterMemoryEvent *> *)timelineFromSnapshot:(nullable PETCharacterSnapshot *)snapshot;
- (NSArray<PETCharacterMemoryEvent *> *)updatedTimelineForIntent:(PETCharacterIntent *)intent
                                                         emotion:(PETCharacterEmotion *)emotion
                                                            goal:(nullable PETCharacterGoal *)goal
                                                        decision:(PETBehaviorDecision *)decision
                                                        taskStack:(NSArray<PETCharacterTask *> *)taskStack
                                                previousSnapshot:(nullable PETCharacterSnapshot *)previousSnapshot;

@end

NS_ASSUME_NONNULL_END
