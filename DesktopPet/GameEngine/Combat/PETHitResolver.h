#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETGameSession;
@class PETHitResult;

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, id> * _Nullable (^PETCombatCollisionEvaluator)(NSString *sourcePetIdentifier,
                                                                               NSString *targetPetIdentifier,
                                                                               CGFloat sampleSpacing);

@interface PETHitResolver : NSObject

- (NSArray<PETHitResult *> *)resolveHitsForSessions:(NSArray<PETGameSession *> *)sessions
                                 collisionEvaluator:(nullable PETCombatCollisionEvaluator)collisionEvaluator;

@end

NS_ASSUME_NONNULL_END
