#import "PETGameInputState.h"

#import "../Core/PETGameCommand.h"

@interface PETGameInputState ()

@property (nonatomic, assign) BOOL upPressed;
@property (nonatomic, assign) BOOL downPressed;
@property (nonatomic, assign) BOOL leftPressed;
@property (nonatomic, assign) BOOL rightPressed;
@property (nonatomic, assign) BOOL jumpPressed;
@property (nonatomic, assign) BOOL jumpRequested;

@end

@implementation PETGameInputState

- (CGVector)movementVector {
    CGFloat dx = 0.0;
    CGFloat dy = 0.0;
    if (self.leftPressed) {
        dx -= 1.0;
    }
    if (self.rightPressed) {
        dx += 1.0;
    }
    if (self.downPressed) {
        dy -= 1.0;
    }
    if (self.upPressed) {
        dy += 1.0;
    }
    CGFloat length = hypot(dx, dy);
    if (length > 0.0) {
        dx /= length;
        dy /= length;
    }
    return CGVectorMake(dx, dy);
}

- (void)applyCommand:(PETGameCommand *)command {
    BOOL pressed = [command.commandType isEqualToString:PETGameCommandMovePressed];
    BOOL released = [command.commandType isEqualToString:PETGameCommandMoveReleased];
    BOOL jumpPressed = [command.commandType isEqualToString:PETGameCommandJumpPressed];
    BOOL jumpReleased = [command.commandType isEqualToString:PETGameCommandJumpReleased];
    if (jumpPressed || jumpReleased) {
        self.jumpPressed = jumpPressed;
        if (jumpPressed) {
            self.jumpRequested = YES;
        }
        return;
    }
    if (!pressed && !released) {
        return;
    }

    BOOL value = pressed;
    if ([command.direction isEqualToString:PETGameDirectionUp]) {
        self.upPressed = value;
    } else if ([command.direction isEqualToString:PETGameDirectionDown]) {
        self.downPressed = value;
    } else if ([command.direction isEqualToString:PETGameDirectionLeft]) {
        self.leftPressed = value;
    } else if ([command.direction isEqualToString:PETGameDirectionRight]) {
        self.rightPressed = value;
    }
}

- (void)consumeJumpRequest {
    self.jumpRequested = NO;
}

- (void)clearAllInputs {
    self.upPressed = NO;
    self.downPressed = NO;
    self.leftPressed = NO;
    self.rightPressed = NO;
    self.jumpPressed = NO;
    self.jumpRequested = NO;
}

- (NSDictionary<NSString *,id> *)serializedState {
    return @{
        @"upPressed": @(self.upPressed),
        @"downPressed": @(self.downPressed),
        @"leftPressed": @(self.leftPressed),
        @"rightPressed": @(self.rightPressed),
        @"jumpPressed": @(self.jumpPressed)
    };
}

- (void)restoreFromSerializedState:(NSDictionary<NSString *,id> *)state {
    self.upPressed = [state[@"upPressed"] boolValue];
    self.downPressed = [state[@"downPressed"] boolValue];
    self.leftPressed = [state[@"leftPressed"] boolValue];
    self.rightPressed = [state[@"rightPressed"] boolValue];
    self.jumpPressed = [state[@"jumpPressed"] boolValue];
    self.jumpRequested = NO;
}

@end
