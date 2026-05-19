#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETGameCommand;

NS_ASSUME_NONNULL_BEGIN

@interface PETGameInputState : NSObject

@property (nonatomic, assign, readonly) BOOL upPressed;
@property (nonatomic, assign, readonly) BOOL downPressed;
@property (nonatomic, assign, readonly) BOOL leftPressed;
@property (nonatomic, assign, readonly) BOOL rightPressed;
@property (nonatomic, assign, readonly) BOOL jumpPressed;
@property (nonatomic, assign, readonly) BOOL jumpRequested;
@property (nonatomic, assign, readonly) CGVector movementVector;

- (void)applyCommand:(PETGameCommand *)command;
- (void)consumeJumpRequest;
- (void)clearAllInputs;
- (NSDictionary<NSString *, id> *)serializedState;
- (void)restoreFromSerializedState:(NSDictionary<NSString *, id> *)state;

@end

NS_ASSUME_NONNULL_END
