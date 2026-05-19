#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETCharacterRuntimeController;
@class PETGameCommand;
@class PETGameEvent;
@class PETPetProfile;
@class PETSkillLibrary;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const PETGameEngineDidEmitEventsNotification;
FOUNDATION_EXPORT NSString * const PETGameEngineEventsUserInfoKey;
typedef NSDictionary<NSString *, id> * _Nullable (^PETGameEnginePixelCollisionEvaluator)(NSString *sourcePetIdentifier,
                                                                                         NSString *targetPetIdentifier,
                                                                                         CGFloat sampleSpacing);

@interface PETGameEngine : NSObject

@property (nonatomic, assign, readonly) BOOL running;
@property (nonatomic, copy, readonly) NSArray<NSString *> *registeredPetIdentifiers;
@property (nonatomic, copy, readonly) NSArray<PETGameEvent *> *recentEvents;
@property (nonatomic, strong, readonly, nullable) PETSkillLibrary *skillLibrary;
@property (nonatomic, copy, nullable) PETGameEnginePixelCollisionEvaluator pixelCollisionEvaluator;

- (void)registerPetWithProfile:(PETPetProfile *)profile
              runtimeController:(nullable PETCharacterRuntimeController *)runtimeController;
- (void)removePetWithIdentifier:(NSString *)petIdentifier;
- (void)removeAllPets;
- (void)submitCommand:(PETGameCommand *)command;
- (void)setMovementPosition:(CGPoint)position bodySize:(CGSize)bodySize forPetIdentifier:(NSString *)petIdentifier;
- (nullable NSDictionary<NSString *, id> *)serializedStateForPetIdentifier:(NSString *)petIdentifier;
- (nullable NSDictionary<NSString *, id> *)combatDebugSnapshotForPetIdentifier:(NSString *)petIdentifier;
- (void)restorePetIdentifier:(NSString *)petIdentifier fromState:(NSDictionary<NSString *, id> *)state;
- (void)clearRecentEvents;

@end

NS_ASSUME_NONNULL_END
