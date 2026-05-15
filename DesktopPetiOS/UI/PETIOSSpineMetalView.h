#import <MetalKit/MetalKit.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETIOSSpineMetalView : MTKView

@property (nonatomic, strong, readonly) PETPetProfile *profile;
@property (nonatomic, copy, readonly) NSString *currentState;
@property (nonatomic, assign) NSTimeInterval frameRateCooldownDuration;

- (nullable instancetype)initWithProfile:(PETPetProfile *)profile error:(NSError * _Nullable * _Nullable)error;
- (void)startAnimating;
- (void)playState:(NSString *)state;
- (void)playState:(NSString *)state loop:(BOOL)loop;
- (void)pauseAnimation;
- (void)resumeDefaultAnimation;
- (void)setInteractionBoosted:(BOOL)boosted;
- (NSTimeInterval)durationForState:(NSString *)state;
- (BOOL)containsInteractiveContentAtPoint:(CGPoint)point;
- (BOOL)containsDraggableContentAtPoint:(CGPoint)point;
- (nullable NSString *)interactivePartIdentifierAtPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
