#import <Foundation/Foundation.h>

@class PETCharacterGoal;
@class PETCharacterIntent;
@class PETCharacterSnapshot;
@class PETCharacterTask;

NS_ASSUME_NONNULL_BEGIN

@interface PETGoalEngine : NSObject

- (nullable PETCharacterGoal *)activeGoalFromSnapshot:(nullable PETCharacterSnapshot *)snapshot;
- (nullable PETCharacterGoal *)updatedGoalForIntent:(PETCharacterIntent *)intent
                                   previousSnapshot:(nullable PETCharacterSnapshot *)previousSnapshot;
- (nullable PETCharacterGoal *)projectedGoalFromTask:(nullable PETCharacterTask *)task;

@end

NS_ASSUME_NONNULL_END
