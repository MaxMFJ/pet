#import <Cocoa/Cocoa.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const PETPetWindowDidEmitRuntimeEventNotification;
FOUNDATION_EXPORT NSNotificationName const PETPetWindowDidActivateNotification;
FOUNDATION_EXPORT NSString * const PETPetWindowProfileIdentifierUserInfoKey;
FOUNDATION_EXPORT NSString * const PETPetWindowActionKeyUserInfoKey;
FOUNDATION_EXPORT NSString * const PETPetWindowFallbackBehaviorStateUserInfoKey;
FOUNDATION_EXPORT NSString * const PETPetWindowResolvedAnimationStateUserInfoKey;
FOUNDATION_EXPORT NSString * const PETPetWindowRuntimeModeUserInfoKey;

@interface PETPetWindow : NSWindow

@property (nonatomic, assign, readonly) CGFloat petScale;
@property (nonatomic, assign, readonly) BOOL facingRight;
@property (nonatomic, assign, readonly, getter=isClickThroughEnabled) BOOL clickThroughEnabled;
@property (nonatomic, copy, readonly) NSString *currentState;
@property (nonatomic, copy, readonly) NSArray<NSString *> *supportedStates;

- (instancetype)initWithProfile:(PETPetProfile *)profile origin:(NSPoint)origin;
- (void)setControlFocusActive:(BOOL)active animated:(BOOL)animated;
- (void)applyScale:(CGFloat)scale;
- (void)applyFacingRight:(BOOL)facingRight;
- (void)applyUserFacingRight:(BOOL)facingRight;
- (void)setClickThroughEnabled:(BOOL)enabled;
- (void)previewState:(NSString *)state;
- (void)resumeAmbientBehavior;
- (void)applyGameMovementState:(NSString *)movementState facingRight:(BOOL)facingRight;
- (void)playCombatPresentationWithAnimationState:(nullable NSString *)animationState
                                      actionKey:(nullable NSString *)actionKey
                                       duration:(NSTimeInterval)duration;
- (void)playHitReactionForCombatState:(NSString *)combatState
                         launchVector:(CGVector)launchVector
                             duration:(NSTimeInterval)duration;
- (NSPoint)stableFrameOrigin;
- (CGSize)stableFrameSize;
- (NSPoint)presentedFrameOriginForStableOrigin:(NSPoint)origin;
- (NSPoint)constrainedFrameOriginForVisibleContentFromOrigin:(NSPoint)origin;
- (NSRect)visibleRenderedContentRectAtScreenOrigin:(NSPoint)origin;
- (BOOL)containsOpaqueRenderedContentAtScreenPoint:(NSPoint)screenPoint;
- (BOOL)intersectsPetWindowAtPixelLevel:(PETPetWindow *)otherWindow
                          sampleSpacing:(CGFloat)sampleSpacing
                               hitPoint:(nullable NSPoint *)hitPoint;
- (BOOL)wouldIntersectPetWindowAtPixelLevel:(PETPetWindow *)otherWindow
                                 fromOrigin:(NSPoint)origin
                              sampleSpacing:(CGFloat)sampleSpacing
                                   hitPoint:(nullable NSPoint *)hitPoint;
- (BOOL)wouldIntersectPetWindowAtPixelLevel:(PETPetWindow *)otherWindow
                                 fromOrigin:(NSPoint)origin
                                otherOrigin:(NSPoint)otherOrigin
                             sampleSpacing:(CGFloat)sampleSpacing
                                  hitPoint:(nullable NSPoint *)hitPoint;

@end

NS_ASSUME_NONNULL_END
