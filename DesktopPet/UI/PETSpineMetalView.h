#import <MetalKit/MetalKit.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETSpineMetalView : MTKView

@property (nonatomic, copy, nullable) void (^dragStateChangeHandler)(BOOL isDragging);
@property (nonatomic, copy, nullable) void (^dragMovementHandler)(CGFloat deltaX);
@property (nonatomic, copy, nullable) void (^interactionHandler)(void);
@property (nonatomic, copy, nullable) void (^secondaryInteractionHandler)(void);
@property (nonatomic, copy, nullable) void (^menuActionHandler)(NSString *state);
@property (nonatomic, copy, readonly) NSString *currentState;
@property (nonatomic, assign) BOOL facingRight;

- (nullable instancetype)initWithProfile:(PETPetProfile *)profile error:(NSError * _Nullable * _Nullable)error;
- (void)startAnimating;
- (void)playState:(NSString *)state;
- (void)playState:(NSString *)state loop:(BOOL)loop;
- (void)pauseAnimation;
- (void)resumeDefaultAnimation;
- (NSTimeInterval)durationForState:(NSString *)state;
- (BOOL)containsInteractiveContentAtPoint:(NSPoint)point;
- (BOOL)containsDraggableContentAtPoint:(NSPoint)point;
- (nullable NSString *)interactivePartIdentifierAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
