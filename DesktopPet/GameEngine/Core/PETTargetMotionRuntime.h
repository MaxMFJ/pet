#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETAttackDefinition;
@class PETHitResult;
@class PETMovementComponent;
@class PETSkillPhase;

NS_ASSUME_NONNULL_BEGIN

@interface PETTargetMotionRuntime : NSObject

- (instancetype)initWithMovementComponent:(PETMovementComponent *)movementComponent NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)queueHitMovementForHitResult:(PETHitResult *)hitResult;
- (void)advanceWithDeltaTime:(NSTimeInterval)deltaTime;
- (BOOL)applyMotionDirective:(NSDictionary<NSString *, id> *)directive
         sourcePetIdentifier:(nullable NSString *)sourcePetIdentifier
              sourcePosition:(CGPoint)sourcePosition
            sourceFacingRight:(BOOL)sourceFacingRight;
- (BOOL)syncConstraintAnchorFromSourcePosition:(CGPoint)sourcePosition
                              sourceFacingRight:(BOOL)sourceFacingRight;
- (void)resetTransientMotionState;
- (BOOL)applyCasterMotionForPreviousPhase:(nullable PETSkillPhase *)previousPhase
                         previousPhaseTime:(NSTimeInterval)previousPhaseTime
                              currentPhase:(nullable PETSkillPhase *)currentPhase
                         currentPhaseTime:(NSTimeInterval)currentPhaseTime;
- (void)syncMovementLockForSkillPhase:(nullable PETSkillPhase *)skillPhase
                 activeAttackDefinition:(nullable PETAttackDefinition *)activeAttackDefinition
                      combatControlLocked:(BOOL)combatControlLocked;
- (void)syncReactionConstraintsWithGravityScale:(CGFloat)gravityScale
                                 lockHorizontal:(BOOL)lockHorizontal
                                   lockVertical:(BOOL)lockVertical;
- (nullable NSString *)activeConstraintSourcePetIdentifier;
- (BOOL)hasActiveConstraint;
- (NSDictionary<NSString *, id> *)movementEventContext;
- (NSDictionary<NSString *, id> *)debugSnapshot;

@end

NS_ASSUME_NONNULL_END
