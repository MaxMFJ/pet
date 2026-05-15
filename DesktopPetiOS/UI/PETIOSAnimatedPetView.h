#import <UIKit/UIKit.h>

@class PETPetProfile;
@class PETIOSAnimatedPetView;

@protocol PETIOSAnimatedPetViewDelegate <NSObject>

- (void)animatedPetViewDidReceivePrimaryTap:(PETIOSAnimatedPetView * _Nonnull)petView
                                    atPoint:(CGPoint)point
                             partIdentifier:(nullable NSString *)partIdentifier;
- (void)animatedPetViewDidBeginDrag:(PETIOSAnimatedPetView * _Nonnull)petView atPoint:(CGPoint)point;
- (void)animatedPetViewDidDrag:(PETIOSAnimatedPetView * _Nonnull)petView translation:(CGPoint)translation velocity:(CGPoint)velocity;
- (void)animatedPetViewDidEndDrag:(PETIOSAnimatedPetView * _Nonnull)petView velocity:(CGPoint)velocity;

@end

NS_ASSUME_NONNULL_BEGIN

@interface PETIOSAnimatedPetView : UIView

@property (nonatomic, weak) id<PETIOSAnimatedPetViewDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *currentState;
@property (nonatomic, assign, readonly) CGFloat petScale;
@property (nonatomic, assign, readonly) CGPoint petOffset;
@property (nonatomic, assign) CGFloat dragActivationThreshold;
@property (nonatomic, assign) NSTimeInterval frameRateCooldownDuration;

- (void)displayProfile:(nullable PETPetProfile *)profile preferredState:(nullable NSString *)state;
- (void)setPetScale:(CGFloat)petScale;
- (void)setPetOffset:(CGPoint)petOffset animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
