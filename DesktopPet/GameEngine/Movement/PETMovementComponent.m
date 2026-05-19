#import "PETMovementComponent.h"

NSString * const PETMovementFacingLeft = @"left";
NSString * const PETMovementFacingRight = @"right";
NSString * const PETMovementStateIdle = @"idle";
NSString * const PETMovementStateWalk = @"walk";
NSString * const PETMovementStateRun = @"run";
NSString * const PETMovementStateFly = @"fly";
NSString * const PETMovementStateJump = @"jump";
NSString * const PETMovementStateJumpAir = @"jump-air";
NSString * const PETMovementStateJumpLand = @"jump-land";
NSString * const PETMovementStateLocked = @"locked";

@implementation PETMovementComponent

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxSpeed = 220.0;
        _acceleration = 1400.0;
        _deceleration = 1800.0;
        _facingDirection = [PETMovementFacingRight copy];
        _movementState = [PETMovementStateIdle copy];
        _bodySize = CGSizeMake(160.0, 160.0);
        _jumpInitialVelocity = 520.0;
        _gravity = 1600.0;
        _jumpTakeoffDuration = 0.12;
        _landingTriggerHeight = 26.0;
        _landingDuration = 0.18;
        _jumpAirMinimumDuration = 0.12;
    }
    return self;
}

- (void)beginJumpIfPossible {
    if (self.isLocked || self.isJumping) {
        return;
    }
    self.jumping = YES;
    self.jumpGroundY = self.position.y;
    self.jumpVelocity = self.jumpInitialVelocity;
    self.jumpTakeoffTimeRemaining = self.jumpTakeoffDuration;
    self.landingTimeRemaining = 0.0;
    self.jumpAirTimeRemaining = 0.0;
    self.movementState = PETMovementStateJump;
}

- (NSDictionary<NSString *,id> *)serializedState {
    return @{
        @"position": @{@"x": @(self.position.x), @"y": @(self.position.y)},
        @"velocity": @{@"dx": @(self.velocity.dx), @"dy": @(self.velocity.dy)},
        @"bodySize": @{@"width": @(self.bodySize.width), @"height": @(self.bodySize.height)},
        @"facingDirection": self.facingDirection ?: PETMovementFacingRight,
        @"movementState": self.movementState ?: PETMovementStateIdle,
        @"locked": @(self.isLocked),
        @"jumping": @(self.isJumping),
        @"jumpVelocity": @(self.jumpVelocity),
        @"jumpGroundY": @(self.jumpGroundY),
        @"jumpTakeoffTimeRemaining": @(self.jumpTakeoffTimeRemaining),
        @"landingTimeRemaining": @(self.landingTimeRemaining),
        @"jumpAirTimeRemaining": @(self.jumpAirTimeRemaining)
    };
}

- (void)restoreFromSerializedState:(NSDictionary<NSString *,id> *)state {
    NSDictionary<NSString *, id> *position = [state[@"position"] isKindOfClass:NSDictionary.class] ? state[@"position"] : nil;
    NSDictionary<NSString *, id> *velocity = [state[@"velocity"] isKindOfClass:NSDictionary.class] ? state[@"velocity"] : nil;
    NSDictionary<NSString *, id> *bodySize = [state[@"bodySize"] isKindOfClass:NSDictionary.class] ? state[@"bodySize"] : nil;
    NSString *facingDirection = [state[@"facingDirection"] isKindOfClass:NSString.class] ? state[@"facingDirection"] : nil;
    NSString *movementState = [state[@"movementState"] isKindOfClass:NSString.class] ? state[@"movementState"] : nil;

    if (position != nil) {
        self.position = CGPointMake([position[@"x"] doubleValue], [position[@"y"] doubleValue]);
    }
    if (velocity != nil) {
        self.velocity = CGVectorMake([velocity[@"dx"] doubleValue], [velocity[@"dy"] doubleValue]);
    }
    if (bodySize != nil) {
        self.bodySize = CGSizeMake(MAX(1.0, [bodySize[@"width"] doubleValue]), MAX(1.0, [bodySize[@"height"] doubleValue]));
    }
    if (facingDirection.length > 0) {
        self.facingDirection = facingDirection;
    }
    if (movementState.length > 0) {
        self.movementState = movementState;
    }
    self.locked = [state[@"locked"] boolValue];
    self.jumping = [state[@"jumping"] boolValue];
    self.jumpVelocity = [state[@"jumpVelocity"] doubleValue];
    self.jumpGroundY = [state[@"jumpGroundY"] doubleValue];
    self.jumpTakeoffTimeRemaining = [state[@"jumpTakeoffTimeRemaining"] doubleValue];
    self.landingTimeRemaining = [state[@"landingTimeRemaining"] doubleValue];
    self.jumpAirTimeRemaining = [state[@"jumpAirTimeRemaining"] doubleValue];
}

@end
