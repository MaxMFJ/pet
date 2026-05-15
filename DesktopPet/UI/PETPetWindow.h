#import <Cocoa/Cocoa.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const PETPetWindowDidEmitRuntimeEventNotification;
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
- (void)applyScale:(CGFloat)scale;
- (void)applyFacingRight:(BOOL)facingRight;
- (void)setClickThroughEnabled:(BOOL)enabled;
- (void)previewState:(NSString *)state;
- (void)resumeAmbientBehavior;

@end

NS_ASSUME_NONNULL_END
