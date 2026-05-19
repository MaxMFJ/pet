#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETGameEvent;
@class PETMovementComponent;

NS_ASSUME_NONNULL_BEGIN

@interface PETMovementSystem : NSObject

- (NSArray<PETGameEvent *> *)updateMovementComponent:(PETMovementComponent *)component
                                       movementVector:(CGVector)movementVector
                                         jumpRequested:(BOOL)jumpRequested
                                           deltaTime:(NSTimeInterval)deltaTime
                                       petIdentifier:(NSString *)petIdentifier;

@end

NS_ASSUME_NONNULL_END
