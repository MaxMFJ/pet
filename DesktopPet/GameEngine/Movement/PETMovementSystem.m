#import "PETMovementSystem.h"

#import <Cocoa/Cocoa.h>

#import "../Core/PETGameEvent.h"
#import "PETMovementComponent.h"

static NSString * const PETGameEventMoveStarted = @"game.move.started";
static NSString * const PETGameEventMoveChanged = @"game.move.changed";
static NSString * const PETGameEventMoveEnded = @"game.move.ended";

@implementation PETMovementSystem

- (NSArray<PETGameEvent *> *)updateMovementComponent:(PETMovementComponent *)component
                                       movementVector:(CGVector)movementVector
                                         jumpRequested:(BOOL)jumpRequested
                                           deltaTime:(NSTimeInterval)deltaTime
                                       petIdentifier:(NSString *)petIdentifier {
    CGVector resolvedMovementVector = component.isLocked ? CGVectorMake(0.0, 0.0) : movementVector;
    if (jumpRequested && !component.isLocked) {
        [component beginJumpIfPossible];
    }
    if (component.jumpTakeoffTimeRemaining > 0.0) {
        component.jumpTakeoffTimeRemaining = MAX(0.0, component.jumpTakeoffTimeRemaining - deltaTime);
    }
    if (component.landingTimeRemaining > 0.0) {
        component.landingTimeRemaining = MAX(0.0, component.landingTimeRemaining - deltaTime);
    }
    if (component.jumpAirTimeRemaining > 0.0) {
        component.jumpAirTimeRemaining = MAX(0.0, component.jumpAirTimeRemaining - deltaTime);
    }

    NSString *previousState = component.movementState ?: PETMovementStateIdle;
    CGPoint previousPosition = component.position;
    CGFloat previousSpeed = hypot(component.velocity.dx, component.velocity.dy);
    CGFloat targetVX = component.isHorizontalMotionLocked ? 0.0 : (resolvedMovementVector.dx * component.maxSpeed);
    CGFloat targetVY = component.isVerticalMotionLocked ? 0.0 : (resolvedMovementVector.dy * component.maxSpeed);
    BOOL hasInput = hypot(resolvedMovementVector.dx, resolvedMovementVector.dy) > 0.0;
    CGFloat rate = hasInput ? component.acceleration : component.deceleration;
    CGFloat maxStep = rate * MAX(0.0, deltaTime);

    component.velocity = CGVectorMake([self moveValue:component.velocity.dx towardValue:targetVX maxStep:maxStep],
                                      [self moveValue:component.velocity.dy towardValue:targetVY maxStep:maxStep]);
    if (component.isHorizontalMotionLocked) {
        component.velocity = CGVectorMake(0.0, component.velocity.dy);
    }
    if (component.isVerticalMotionLocked) {
        component.velocity = CGVectorMake(component.velocity.dx, 0.0);
    }

    CGPoint nextPosition = CGPointMake(component.position.x + component.velocity.dx * deltaTime,
                                       component.position.y + component.velocity.dy * deltaTime);
    BOOL didLand = NO;
    if (component.isJumping) {
        if (component.isVerticalMotionLocked) {
            nextPosition.y = component.position.y;
            component.jumpVelocity = 0.0;
        } else {
            nextPosition.y += component.jumpVelocity * deltaTime;
            component.jumpVelocity -= (component.gravity * MAX(0.0, component.gravityScale)) * deltaTime;
            if (nextPosition.y <= component.jumpGroundY && component.jumpVelocity <= 0.0) {
                nextPosition.y = component.jumpGroundY;
                component.jumpVelocity = 0.0;
                component.jumping = NO;
                component.landingTimeRemaining = component.landingDuration;
                component.jumpAirTimeRemaining = 0.0;
                didLand = YES;
            }
        }
    }
    nextPosition = [self clampedPositionForPosition:nextPosition bodySize:component.bodySize];
    component.position = nextPosition;

    CGFloat speed = hypot(component.velocity.dx, component.velocity.dy);
    if (fabs(component.velocity.dx) > 1.0) {
        component.facingDirection = component.velocity.dx >= 0.0 ? PETMovementFacingRight : PETMovementFacingLeft;
    }
    if (didLand || component.landingTimeRemaining > 0.0) {
        component.movementState = PETMovementStateJumpLand;
    } else if (component.isJumping) {
        CGFloat distanceToGround = MAX(0.0, component.position.y - component.jumpGroundY);
        BOOL shouldLandSoon = component.jumpVelocity < 0.0 && distanceToGround <= component.landingTriggerHeight;
        if (component.jumpTakeoffTimeRemaining > 0.0) {
            component.movementState = PETMovementStateJump;
        } else if (component.jumpAirTimeRemaining > 0.0) {
            component.movementState = PETMovementStateJumpAir;
        } else if (shouldLandSoon) {
            component.movementState = PETMovementStateJumpLand;
        } else {
            component.movementState = PETMovementStateJumpAir;
            component.jumpAirTimeRemaining = component.jumpAirMinimumDuration;
        }
    } else if (component.isLocked && speed < 1.0) {
        component.velocity = CGVectorMake(0.0, 0.0);
        component.movementState = PETMovementStateLocked;
    } else if (speed < 1.0) {
        component.velocity = CGVectorMake(0.0, 0.0);
        component.movementState = PETMovementStateIdle;
    } else if (speed < component.maxSpeed * 0.65) {
        component.movementState = PETMovementStateWalk;
    } else {
        component.movementState = PETMovementStateRun;
    }

    BOOL didMove = hypot(component.position.x - previousPosition.x, component.position.y - previousPosition.y) > 0.01;
    BOOL wasIdle = [previousState isEqualToString:PETMovementStateIdle] || previousSpeed < 1.0;
    BOOL isIdle = [component.movementState isEqualToString:PETMovementStateIdle];
    if (!didMove && [previousState isEqualToString:component.movementState]) {
        return @[];
    }
    if (!didMove && wasIdle && isIdle) {
        return @[];
    }

    NSString *eventType = PETGameEventMoveChanged;
    if (wasIdle && !isIdle) {
        eventType = PETGameEventMoveStarted;
    } else if (!wasIdle && isIdle) {
        eventType = PETGameEventMoveEnded;
    }

    PETGameEvent *event = [[PETGameEvent alloc] initWithEventType:eventType
                                                    petIdentifier:petIdentifier
                                                           source:@"game.movement"
                                                          context:[self contextForComponent:component]];
    return @[event];
}

- (CGFloat)moveValue:(CGFloat)value towardValue:(CGFloat)target maxStep:(CGFloat)maxStep {
    if (value < target) {
        return MIN(value + maxStep, target);
    }
    if (value > target) {
        return MAX(value - maxStep, target);
    }
    return value;
}

- (CGPoint)clampedPositionForPosition:(CGPoint)position bodySize:(CGSize)bodySize {
    NSScreen *screen = [self screenForPosition:position bodySize:bodySize] ?: NSScreen.mainScreen;
    NSRect screenFrame = screen.frame;
    CGFloat minX = NSMinX(screenFrame);
    CGFloat maxX = NSMaxX(screenFrame) - bodySize.width;
    CGFloat minY = NSMinY(screenFrame);
    CGFloat maxY = NSMaxY(screenFrame) - bodySize.height;
    if (maxX < minX) {
        maxX = minX;
    }
    if (maxY < minY) {
        maxY = minY;
    }
    return CGPointMake(MIN(MAX(position.x, minX), maxX),
                       MIN(MAX(position.y, minY), maxY));
}

- (nullable NSScreen *)screenForPosition:(CGPoint)position bodySize:(CGSize)bodySize {
    NSPoint center = NSMakePoint(position.x + bodySize.width * 0.5, position.y + bodySize.height * 0.5);
    for (NSScreen *screen in NSScreen.screens) {
        if (NSPointInRect(center, screen.frame)) {
            return screen;
        }
    }
    return nil;
}

- (NSDictionary<NSString *, id> *)contextForComponent:(PETMovementComponent *)component {
    return @{
        @"position": @{@"x": @(component.position.x), @"y": @(component.position.y)},
        @"velocity": @{@"dx": @(component.velocity.dx), @"dy": @(component.velocity.dy)},
        @"bodySize": @{@"width": @(component.bodySize.width), @"height": @(component.bodySize.height)},
        @"facingDirection": component.facingDirection ?: PETMovementFacingRight,
        @"facingRight": @([component.facingDirection isEqualToString:PETMovementFacingRight]),
        @"movementState": component.movementState ?: PETMovementStateIdle,
        @"jumping": @(component.isJumping),
        @"jumpVelocity": @(component.jumpVelocity),
        @"gravityScale": @(component.gravityScale),
        @"horizontalMotionLocked": @(component.isHorizontalMotionLocked),
        @"verticalMotionLocked": @(component.isVerticalMotionLocked),
        @"jumpTakeoffTimeRemaining": @(component.jumpTakeoffTimeRemaining),
        @"landingTimeRemaining": @(component.landingTimeRemaining)
    };
}

@end
