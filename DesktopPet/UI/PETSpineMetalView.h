#import <MetalKit/MetalKit.h>

@class PETPetProfile;
@class PETSpineRuntime;

NS_ASSUME_NONNULL_BEGIN

@interface PETSpineMetalView : MTKView

@property (nonatomic, copy, nullable) void (^dragStateChangeHandler)(BOOL isDragging);
@property (nonatomic, copy, nullable) void (^dragMovementHandler)(CGFloat deltaX);
@property (nonatomic, copy, nullable) void (^interactionHandler)(void);
@property (nonatomic, copy, nullable) void (^secondaryInteractionHandler)(void);
@property (nonatomic, copy, nullable) void (^menuActionHandler)(NSString *state);
@property (nonatomic, copy, readonly) NSString *currentState;
@property (nonatomic, assign) BOOL facingRight;
@property (nonatomic, assign) NSRect contentLayoutRect;
@property (nonatomic, assign) BOOL editorPlaybackEnabled;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *activeShaderPayload;
@property (nonatomic, strong, readonly) PETSpineRuntime *spineRuntime;

- (nullable instancetype)initWithProfile:(PETPetProfile *)profile error:(NSError * _Nullable * _Nullable)error;
- (void)startAnimating;
- (void)playState:(NSString *)state;
- (void)playState:(NSString *)state loop:(BOOL)loop;
- (void)pauseAnimation;
- (void)resumeDefaultAnimation;
- (NSTimeInterval)durationForState:(NSString *)state;
- (void)seekToAnimationTime:(NSTimeInterval)time;
- (void)redrawSpineFrame;
- (BOOL)containsInteractiveContentAtPoint:(NSPoint)point;
- (BOOL)containsDraggableContentAtPoint:(NSPoint)point;
- (nullable NSString *)interactivePartIdentifierAtPoint:(NSPoint)point;
- (BOOL)containsOpaqueRenderedContentAtPoint:(NSPoint)point;
- (NSRect)visibleRenderedContentRect;
- (NSSize)normalWindowSize;
- (NSSize)recommendedWindowSizeForState:(NSString *)state normalViewportSize:(NSSize)normalViewportSize;

@end

NS_ASSUME_NONNULL_END
