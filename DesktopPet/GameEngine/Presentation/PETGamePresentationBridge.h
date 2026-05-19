#import <Cocoa/Cocoa.h>

@class PETGameEvent;
@class PETPetWindow;

NS_ASSUME_NONNULL_BEGIN

typedef PETPetWindow * _Nullable (^PETGamePresentationWindowProvider)(NSString *petIdentifier);
typedef NSDictionary<NSString *, id> * _Nullable (^PETGamePresentationCombatSnapshotProvider)(NSString *petIdentifier);
typedef NSDictionary<NSString *, id> * _Nullable (^PETGamePresentationMovementCollisionEvaluator)(NSString *petIdentifier, CGPoint proposedOrigin, CGFloat sampleSpacing);

@interface PETGamePresentationBridge : NSObject

@property (nonatomic, copy, nullable) PETGamePresentationWindowProvider windowProvider;
@property (nonatomic, copy, nullable) PETGamePresentationCombatSnapshotProvider combatSnapshotProvider;
@property (nonatomic, copy, nullable) PETGamePresentationMovementCollisionEvaluator movementCollisionEvaluator;

- (void)applyGameEvents:(NSArray<PETGameEvent *> *)events;

@end

NS_ASSUME_NONNULL_END
