#import "PETTargetMotionRuntime.h"

#import "../Combat/PETAttackDefinition.h"
#import "../Combat/PETHitResult.h"
#import "../Movement/PETMovementComponent.h"
#import "../Movement/PETMovementSystem.h"
#import "../Skill/PETSkillPhase.h"

@interface PETTargetMotionRuntime ()

@property (nonatomic, weak) PETMovementComponent *movementComponent;
@property (nonatomic, strong, nullable) PETHitResult *pendingHitMovementResult;
@property (nonatomic, assign) NSTimeInterval pendingHitMovementDelayRemaining;
@property (nonatomic, copy) NSString *motionControlMode;
@property (nonatomic, copy, nullable) NSString *constraintSourcePetIdentifier;
@property (nonatomic, assign) CGPoint constraintAnchorPoint;
@property (nonatomic, assign) CGVector constraintOffset;
@property (nonatomic, assign) NSTimeInterval constraintTimeRemaining;

@end

@implementation PETTargetMotionRuntime

static NSTimeInterval const PETDelayedHitMovementResponseDelay = 0.5;
static NSString * const PETMotionControlModeFree = @"free";
static NSString * const PETMotionControlModeLockPoint = @"lock_point";
static NSString * const PETMotionControlModeFollowAttackerRoot = @"follow_attacker_root";
static NSString * const PETMotionControlModeReleaseVelocity = @"release_velocity";

- (instancetype)initWithMovementComponent:(PETMovementComponent *)movementComponent {
    self = [super init];
    if (self) {
        _movementComponent = movementComponent;
        _motionControlMode = PETMotionControlModeFree;
    }
    return self;
}

- (void)queueHitMovementForHitResult:(PETHitResult *)hitResult {
    if (hitResult == nil) {
        return;
    }
    self.pendingHitMovementResult = hitResult;
    self.pendingHitMovementDelayRemaining = PETDelayedHitMovementResponseDelay;
    self.motionControlMode = @"pending_hit_response";
}

- (void)advanceWithDeltaTime:(NSTimeInterval)deltaTime {
    NSTimeInterval clampedDelta = MAX(0.0, deltaTime);
    if (self.constraintTimeRemaining > 0.0) {
        self.constraintTimeRemaining = MAX(0.0, self.constraintTimeRemaining - clampedDelta);
        if (self.constraintTimeRemaining <= 0.0001) {
            [self clearConstraintPreservingMotionMode:NO];
        }
    }

    if (self.pendingHitMovementResult == nil) {
        return;
    }

    self.pendingHitMovementDelayRemaining = MAX(0.0, self.pendingHitMovementDelayRemaining - clampedDelta);
    if (self.pendingHitMovementDelayRemaining > 0.0) {
        return;
    }

    PETHitResult *resolvedHitResult = self.pendingHitMovementResult;
    self.pendingHitMovementResult = nil;
    self.pendingHitMovementDelayRemaining = 0.0;
    [self applyMovementResponseForHitResult:resolvedHitResult];
}

- (BOOL)applyMotionDirective:(NSDictionary<NSString *,id> *)directive
         sourcePetIdentifier:(NSString *)sourcePetIdentifier
              sourcePosition:(CGPoint)sourcePosition
            sourceFacingRight:(BOOL)sourceFacingRight {
    NSString *type = [directive[@"type"] isKindOfClass:NSString.class] ? directive[@"type"] : @"";
    if (type.length == 0) {
        return NO;
    }

    if ([type isEqualToString:@"lockTargetPoint"]) {
        CGPoint anchorPoint = [self anchorPointForDirective:directive
                                              sourcePosition:sourcePosition
                                            sourceFacingRight:sourceFacingRight];
        [self applyConstraintAnchorPoint:anchorPoint];
        self.constraintSourcePetIdentifier = nil;
        self.constraintOffset = CGVectorMake(0.0, 0.0);
        self.constraintTimeRemaining = MAX(0.0, [directive[@"duration"] doubleValue]);
        self.motionControlMode = PETMotionControlModeLockPoint;
        return YES;
    }

    if ([type isEqualToString:@"followTargetRoot"]) {
        NSDictionary<NSString *, id> *offset = [directive[@"offset"] isKindOfClass:NSDictionary.class] ? directive[@"offset"] : nil;
        CGFloat offsetDX = [offset[@"dx"] doubleValue];
        CGFloat offsetDY = [offset[@"dy"] doubleValue];
        self.constraintOffset = CGVectorMake(offsetDX, offsetDY);
        self.constraintSourcePetIdentifier = sourcePetIdentifier.length > 0 ? [sourcePetIdentifier copy] : nil;
        self.constraintTimeRemaining = MAX(0.0, [directive[@"duration"] doubleValue]);
        self.motionControlMode = PETMotionControlModeFollowAttackerRoot;
        return [self syncConstraintAnchorFromSourcePosition:sourcePosition sourceFacingRight:sourceFacingRight];
    }

    if ([type isEqualToString:@"releaseTarget"]) {
        [self clearConstraintPreservingMotionMode:YES];
        NSDictionary<NSString *, id> *vector = [directive[@"vector"] isKindOfClass:NSDictionary.class] ? directive[@"vector"] : nil;
        CGFloat dx = [vector[@"dx"] doubleValue];
        CGFloat dy = [vector[@"dy"] doubleValue];
        BOOL facingRelative = directive[@"facingRelative"] != nil ? [directive[@"facingRelative"] boolValue] : YES;
        if (!sourceFacingRight && facingRelative) {
            dx = -dx;
        }
        if (fabs(dx) > 0.01 || fabs(dy) > 0.01) {
            self.movementComponent.velocity = CGVectorMake(dx, self.movementComponent.velocity.dy);
            if (fabs(dx) > 0.01) {
                self.movementComponent.facingDirection = dx >= 0.0 ? PETMovementFacingRight : PETMovementFacingLeft;
            }
            if (fabs(dy) > 0.01) {
                self.movementComponent.jumping = YES;
                self.movementComponent.jumpGroundY = self.movementComponent.position.y;
                self.movementComponent.jumpVelocity = dy;
                self.movementComponent.jumpTakeoffTimeRemaining = self.movementComponent.jumpTakeoffDuration;
                self.movementComponent.landingTimeRemaining = 0.0;
                self.movementComponent.jumpAirTimeRemaining = 0.0;
                self.movementComponent.movementState = PETMovementStateJump;
            }
            self.motionControlMode = PETMotionControlModeReleaseVelocity;
        }
        return YES;
    }

    return NO;
}

- (BOOL)syncConstraintAnchorFromSourcePosition:(CGPoint)sourcePosition
                              sourceFacingRight:(BOOL)sourceFacingRight {
    if (![self.motionControlMode isEqualToString:PETMotionControlModeFollowAttackerRoot]) {
        return NO;
    }
    CGFloat offsetX = sourceFacingRight ? self.constraintOffset.dx : -self.constraintOffset.dx;
    CGPoint anchorPoint = CGPointMake(sourcePosition.x + offsetX,
                                      sourcePosition.y + self.constraintOffset.dy);
    [self applyConstraintAnchorPoint:anchorPoint];
    return YES;
}

- (void)resetTransientMotionState {
    self.pendingHitMovementResult = nil;
    self.pendingHitMovementDelayRemaining = 0.0;
    [self clearConstraintPreservingMotionMode:NO];
    if (!self.movementComponent.isJumping) {
        self.movementComponent.velocity = CGVectorMake(0.0, 0.0);
    }
}

- (BOOL)applyCasterMotionForPreviousPhase:(PETSkillPhase *)previousPhase
                         previousPhaseTime:(NSTimeInterval)previousPhaseTime
                              currentPhase:(PETSkillPhase *)currentPhase
                         currentPhaseTime:(NSTimeInterval)currentPhaseTime {
    if (previousPhase == nil) {
        return NO;
    }

    BOOL facingRight = ![self.movementComponent.facingDirection isEqualToString:PETMovementFacingLeft];
    CGVector totalDelta = CGVectorMake(0.0, 0.0);
    if (previousPhase == currentPhase) {
        totalDelta = [self casterMotionDeltaForPhase:previousPhase
                                            fromTime:previousPhaseTime
                                              toTime:currentPhaseTime
                                         facingRight:facingRight];
    } else {
        totalDelta = [self casterMotionDeltaForPhase:previousPhase
                                            fromTime:previousPhaseTime
                                              toTime:previousPhase.duration
                                         facingRight:facingRight];
        if (currentPhase != nil) {
            CGVector currentPhaseDelta = [self casterMotionDeltaForPhase:currentPhase
                                                                fromTime:0.0
                                                                  toTime:currentPhaseTime
                                                             facingRight:facingRight];
            totalDelta.dx += currentPhaseDelta.dx;
            totalDelta.dy += currentPhaseDelta.dy;
        }
    }

    if (fabs(totalDelta.dx) <= 0.01 && fabs(totalDelta.dy) <= 0.01) {
        return NO;
    }

    CGPoint position = self.movementComponent.position;
    position.x += totalDelta.dx;
    position.y += totalDelta.dy;
    self.movementComponent.position = position;
    self.motionControlMode = @"skill_motion";
    return YES;
}

- (void)syncMovementLockForSkillPhase:(PETSkillPhase *)skillPhase
                 activeAttackDefinition:(PETAttackDefinition *)activeAttackDefinition
                      combatControlLocked:(BOOL)combatControlLocked {
    if (skillPhase != nil) {
        self.movementComponent.locked = skillPhase.movementLock;
        if (skillPhase.movementLock) {
            [self haltMovementForSkillLock];
        }
        self.motionControlMode = skillPhase.movementLock ? @"skill_locked" : @"skill_free";
        return;
    }

    if (activeAttackDefinition != nil && combatControlLocked) {
        self.movementComponent.locked = YES;
        self.motionControlMode = @"combat_locked";
        return;
    }

    self.movementComponent.locked = NO;
    if (![self hasActiveConstraint] &&
        self.pendingHitMovementResult == nil &&
        ![self.motionControlMode isEqualToString:@"launched"] &&
        ![self.motionControlMode isEqualToString:PETMotionControlModeReleaseVelocity]) {
        self.motionControlMode = PETMotionControlModeFree;
    }
}

- (void)syncReactionConstraintsWithGravityScale:(CGFloat)gravityScale
                                 lockHorizontal:(BOOL)lockHorizontal
                                   lockVertical:(BOOL)lockVertical {
    self.movementComponent.gravityScale = gravityScale > 0.0 ? gravityScale : 1.0;
    self.movementComponent.horizontalMotionLocked = lockHorizontal;
    self.movementComponent.verticalMotionLocked = lockVertical;
    if (lockHorizontal) {
        self.movementComponent.velocity = CGVectorMake(0.0, self.movementComponent.velocity.dy);
    }
    if (lockVertical) {
        self.movementComponent.velocity = CGVectorMake(self.movementComponent.velocity.dx, 0.0);
        if (self.movementComponent.isJumping) {
            self.movementComponent.jumpVelocity = 0.0;
        }
    }
}

- (NSDictionary<NSString *,id> *)movementEventContext {
    return @{
        @"position": @{@"x": @(self.movementComponent.position.x), @"y": @(self.movementComponent.position.y)},
        @"velocity": @{@"dx": @(self.movementComponent.velocity.dx), @"dy": @(self.movementComponent.velocity.dy)},
        @"bodySize": @{@"width": @(self.movementComponent.bodySize.width), @"height": @(self.movementComponent.bodySize.height)},
        @"facingDirection": self.movementComponent.facingDirection ?: PETMovementFacingRight,
        @"facingRight": @([self.movementComponent.facingDirection isEqualToString:PETMovementFacingRight]),
        @"movementState": self.movementComponent.movementState ?: PETMovementStateIdle,
        @"jumping": @(self.movementComponent.isJumping),
        @"jumpVelocity": @(self.movementComponent.jumpVelocity),
        @"jumpTakeoffTimeRemaining": @(self.movementComponent.jumpTakeoffTimeRemaining),
        @"landingTimeRemaining": @(self.movementComponent.landingTimeRemaining)
    };
}

- (NSDictionary<NSString *,id> *)debugSnapshot {
    return @{
        @"motionControlMode": self.motionControlMode ?: @"free",
        @"hasPendingHitMotion": @(self.pendingHitMovementResult != nil),
        @"pendingHitMotionDelayRemaining": @(self.pendingHitMovementDelayRemaining),
        @"hasActiveConstraint": @([self hasActiveConstraint]),
        @"constraintSourcePetIdentifier": self.constraintSourcePetIdentifier ?: @"",
        @"constraintAnchorPoint": @{@"x": @(self.constraintAnchorPoint.x), @"y": @(self.constraintAnchorPoint.y)},
        @"constraintOffset": @{@"dx": @(self.constraintOffset.dx), @"dy": @(self.constraintOffset.dy)},
        @"constraintTimeRemaining": @(self.constraintTimeRemaining),
        @"gravityScale": @(self.movementComponent.gravityScale),
        @"lockHorizontal": @(self.movementComponent.isHorizontalMotionLocked),
        @"lockVertical": @(self.movementComponent.isVerticalMotionLocked)
    };
}

- (void)applyMovementResponseForHitResult:(PETHitResult *)hitResult {
    if (hitResult == nil) {
        return;
    }

    CGFloat horizontalVelocity = hitResult.launchVector.dx;
    CGFloat verticalVelocity = hitResult.launchVector.dy;
    NSDictionary<NSString *, id> *collisionSnapshot = hitResult.collisionSnapshot;
    NSDictionary<NSString *, id> *sourceOrigin = [collisionSnapshot[@"sourceOrigin"] isKindOfClass:NSDictionary.class] ? collisionSnapshot[@"sourceOrigin"] : nil;
    NSDictionary<NSString *, id> *targetOrigin = [collisionSnapshot[@"targetOrigin"] isKindOfClass:NSDictionary.class] ? collisionSnapshot[@"targetOrigin"] : nil;
    if (sourceOrigin != nil && targetOrigin != nil && fabs(horizontalVelocity) > 0.01) {
        CGFloat sourceX = [sourceOrigin[@"x"] doubleValue];
        CGFloat targetX = [targetOrigin[@"x"] doubleValue];
        horizontalVelocity = targetX < sourceX ? -fabs(horizontalVelocity) : fabs(horizontalVelocity);
    }

    if (fabs(horizontalVelocity) > 0.01) {
        self.movementComponent.velocity = CGVectorMake(horizontalVelocity, self.movementComponent.velocity.dy);
        self.movementComponent.facingDirection = horizontalVelocity >= 0.0 ? PETMovementFacingRight : PETMovementFacingLeft;
    }

    NSString *combatState = hitResult.combatState;
    BOOL isLaunchedReaction = [combatState isEqualToString:@"combat.launched"] || verticalVelocity > 1.0;
    if (isLaunchedReaction) {
        self.movementComponent.jumping = YES;
        self.movementComponent.jumpGroundY = self.movementComponent.position.y;
        self.movementComponent.jumpVelocity = verticalVelocity;
        self.movementComponent.jumpTakeoffTimeRemaining = self.movementComponent.jumpTakeoffDuration;
        self.movementComponent.landingTimeRemaining = 0.0;
        self.movementComponent.jumpAirTimeRemaining = 0.0;
        self.movementComponent.movementState = PETMovementStateJump;
        self.motionControlMode = @"launched";
    }
}

- (nullable NSString *)activeConstraintSourcePetIdentifier {
    return self.constraintSourcePetIdentifier;
}

- (BOOL)hasActiveConstraint {
    return [self.motionControlMode isEqualToString:PETMotionControlModeLockPoint] ||
           [self.motionControlMode isEqualToString:PETMotionControlModeFollowAttackerRoot];
}

- (CGPoint)anchorPointForDirective:(NSDictionary<NSString *, id> *)directive
                     sourcePosition:(CGPoint)sourcePosition
                   sourceFacingRight:(BOOL)sourceFacingRight {
    NSDictionary<NSString *, id> *point = [directive[@"point"] isKindOfClass:NSDictionary.class] ? directive[@"point"] : nil;
    if (point != nil) {
        return CGPointMake([point[@"x"] doubleValue], [point[@"y"] doubleValue]);
    }
    NSDictionary<NSString *, id> *offset = [directive[@"offset"] isKindOfClass:NSDictionary.class] ? directive[@"offset"] : nil;
    CGFloat offsetX = [offset[@"dx"] doubleValue];
    CGFloat offsetY = [offset[@"dy"] doubleValue];
    if (!sourceFacingRight) {
        offsetX = -offsetX;
    }
    return CGPointMake(sourcePosition.x + offsetX, sourcePosition.y + offsetY);
}

- (void)applyConstraintAnchorPoint:(CGPoint)anchorPoint {
    self.constraintAnchorPoint = anchorPoint;
    self.movementComponent.position = anchorPoint;
    self.movementComponent.velocity = CGVectorMake(0.0, 0.0);
    self.movementComponent.jumping = NO;
    self.movementComponent.jumpVelocity = 0.0;
    self.movementComponent.jumpTakeoffTimeRemaining = 0.0;
    self.movementComponent.jumpAirTimeRemaining = 0.0;
    self.movementComponent.landingTimeRemaining = 0.0;
    self.movementComponent.movementState = PETMovementStateLocked;
}

- (void)clearConstraintPreservingMotionMode:(BOOL)preserveMotionMode {
    self.constraintSourcePetIdentifier = nil;
    self.constraintTimeRemaining = 0.0;
    self.constraintOffset = CGVectorMake(0.0, 0.0);
    self.constraintAnchorPoint = CGPointZero;
    if (!preserveMotionMode && ![self.motionControlMode isEqualToString:@"launched"]) {
        self.motionControlMode = PETMotionControlModeFree;
    }
}

- (void)haltMovementForSkillLock {
    self.movementComponent.velocity = CGVectorMake(0.0, 0.0);
    self.movementComponent.jumping = NO;
    self.movementComponent.jumpVelocity = 0.0;
    self.movementComponent.jumpTakeoffTimeRemaining = 0.0;
    self.movementComponent.jumpAirTimeRemaining = 0.0;
    self.movementComponent.landingTimeRemaining = 0.0;
    self.movementComponent.movementState = PETMovementStateLocked;
}

- (CGVector)casterMotionDeltaForPhase:(PETSkillPhase *)phase
                             fromTime:(NSTimeInterval)fromTime
                               toTime:(NSTimeInterval)toTime
                          facingRight:(BOOL)facingRight {
    if (phase == nil || toTime <= fromTime) {
        return CGVectorMake(0.0, 0.0);
    }

    CGVector startOffset = [phase casterMotionOffsetAtPhaseTime:fromTime facingRight:facingRight];
    CGVector endOffset = [phase casterMotionOffsetAtPhaseTime:toTime facingRight:facingRight];
    return CGVectorMake(endOffset.dx - startOffset.dx, endOffset.dy - startOffset.dy);
}

@end
