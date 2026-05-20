#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PETMovementFacingLeft;
FOUNDATION_EXPORT NSString * const PETMovementFacingRight;
FOUNDATION_EXPORT NSString * const PETMovementStateIdle;
FOUNDATION_EXPORT NSString * const PETMovementStateWalk;
FOUNDATION_EXPORT NSString * const PETMovementStateRun;
FOUNDATION_EXPORT NSString * const PETMovementStateFly;
FOUNDATION_EXPORT NSString * const PETMovementStateJump;
FOUNDATION_EXPORT NSString * const PETMovementStateJumpAir;
FOUNDATION_EXPORT NSString * const PETMovementStateJumpLand;
FOUNDATION_EXPORT NSString * const PETMovementStateLocked;

@interface PETMovementComponent : NSObject

@property (nonatomic, assign) CGPoint position;
@property (nonatomic, assign) CGSize bodySize;
@property (nonatomic, assign) CGVector velocity;
@property (nonatomic, assign) CGFloat maxSpeed;
@property (nonatomic, assign) CGFloat acceleration;
@property (nonatomic, assign) CGFloat deceleration;
@property (nonatomic, copy) NSString *facingDirection;
@property (nonatomic, copy) NSString *movementState;
@property (nonatomic, assign, getter=isLocked) BOOL locked;
@property (nonatomic, assign, getter=isJumping) BOOL jumping;
@property (nonatomic, assign) CGFloat jumpVelocity;
@property (nonatomic, assign) CGFloat jumpGroundY;
@property (nonatomic, assign) CGFloat jumpInitialVelocity;
@property (nonatomic, assign) CGFloat gravity;
@property (nonatomic, assign) CGFloat gravityScale;
@property (nonatomic, assign, getter=isHorizontalMotionLocked) BOOL horizontalMotionLocked;
@property (nonatomic, assign, getter=isVerticalMotionLocked) BOOL verticalMotionLocked;
@property (nonatomic, assign) NSTimeInterval jumpTakeoffTimeRemaining;
@property (nonatomic, assign) NSTimeInterval jumpTakeoffDuration;
@property (nonatomic, assign) CGFloat landingTriggerHeight;
@property (nonatomic, assign) NSTimeInterval landingTimeRemaining;
@property (nonatomic, assign) NSTimeInterval landingDuration;
@property (nonatomic, assign) NSTimeInterval jumpAirTimeRemaining;
@property (nonatomic, assign) NSTimeInterval jumpAirMinimumDuration;

- (void)beginJumpIfPossible;
- (NSDictionary<NSString *, id> *)serializedState;
- (void)restoreFromSerializedState:(NSDictionary<NSString *, id> *)state;

@end

NS_ASSUME_NONNULL_END
