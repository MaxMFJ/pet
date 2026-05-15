#import <Foundation/Foundation.h>

@class PETBehaviorDecision;
@class PETCharacterGoal;
@class PETCharacterEmotion;
@class PETCharacterIntent;
@class PETCharacterSnapshot;
@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETBehaviorPlanner : NSObject

- (PETBehaviorDecision *)planBehaviorForIntent:(PETCharacterIntent *)intent
                                       emotion:(PETCharacterEmotion *)emotion
                                          goal:(nullable PETCharacterGoal *)goal
                                       profile:(PETPetProfile *)profile
                              previousSnapshot:(nullable PETCharacterSnapshot *)previousSnapshot;

@end

NS_ASSUME_NONNULL_END
