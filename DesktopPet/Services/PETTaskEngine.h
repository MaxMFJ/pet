#import <Foundation/Foundation.h>

@class PETCharacterGoal;
@class PETCharacterIntent;
@class PETCharacterSnapshot;
@class PETCharacterTask;

NS_ASSUME_NONNULL_BEGIN

@interface PETTaskEngine : NSObject

- (NSArray<PETCharacterTask *> *)taskStackFromSnapshot:(nullable PETCharacterSnapshot *)snapshot;
- (NSArray<PETCharacterTask *> *)updatedTaskStackForIntent:(PETCharacterIntent *)intent
                                                      goal:(nullable PETCharacterGoal *)goal
                                          previousSnapshot:(nullable PETCharacterSnapshot *)previousSnapshot;
- (nullable PETCharacterTask *)activeTaskInTaskStack:(NSArray<PETCharacterTask *> *)taskStack;

@end

NS_ASSUME_NONNULL_END
