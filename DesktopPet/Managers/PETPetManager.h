#import <Foundation/Foundation.h>

@class PETAppConfig;
@class PETGameCommand;
@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const PETPetManagerDidChangePetsNotification;
FOUNDATION_EXPORT NSNotificationName const PETPetManagerDidUpdateRuntimeDebugNotification;

@interface PETPetManager : NSObject

@property (nonatomic, copy, readonly) NSArray<PETPetProfile *> *activeProfiles;
@property (nonatomic, assign, readonly) NSUInteger visiblePetCount;
@property (nonatomic, copy, readonly, nullable) NSString *selectedPetIdentifier;

- (instancetype)initWithConfiguration:(PETAppConfig *)configuration;
- (BOOL)addPetProfile:(PETPetProfile *)profile error:(NSError **)error;
- (BOOL)isPetVisible:(PETPetProfile *)profile;
- (void)setVisibility:(BOOL)isVisible forPetProfile:(PETPetProfile *)profile;
- (CGFloat)scaleForPetProfile:(PETPetProfile *)profile;
- (void)setScale:(CGFloat)scale forPetProfile:(PETPetProfile *)profile;
- (BOOL)isFacingRightForPetProfile:(PETPetProfile *)profile;
- (void)setFacingRight:(BOOL)facingRight forPetProfile:(PETPetProfile *)profile;
- (BOOL)isClickThroughEnabledForPetProfile:(PETPetProfile *)profile;
- (void)setClickThroughEnabled:(BOOL)isEnabled forPetProfile:(PETPetProfile *)profile;
- (BOOL)isSoulArkEnabledForPetProfile:(PETPetProfile *)profile;
- (void)setSoulArkEnabled:(BOOL)isEnabled forPetProfile:(PETPetProfile *)profile;
- (BOOL)isSoulArkFacingInvertedForPetProfile:(PETPetProfile *)profile;
- (void)setSoulArkFacingInverted:(BOOL)isInverted forPetProfile:(PETPetProfile *)profile;
- (NSArray<NSString *> *)supportedStatesForPetProfile:(PETPetProfile *)profile;
- (NSString *)currentStateForPetProfile:(PETPetProfile *)profile;
- (NSDictionary<NSString *, id> *)characterSnapshotForPetProfile:(PETPetProfile *)profile;
- (NSDictionary<NSString *, id> *)gameStateForPetProfile:(PETPetProfile *)profile;
- (NSDictionary<NSString *, id> *)combatDebugSnapshotForPetProfile:(PETPetProfile *)profile;
- (nullable NSDictionary<NSString *, id> *)lastCollisionSnapshotForPetProfile:(PETPetProfile *)profile;
- (NSArray<NSDictionary<NSString *, id> *> *)recentGameEvents;
- (NSString *)characterRuntimeSummaryForPetProfile:(PETPetProfile *)profile;
- (void)restoreCharacterSnapshot:(NSDictionary<NSString *, id> *)snapshot forPetProfile:(PETPetProfile *)profile;
- (void)restoreGameState:(NSDictionary<NSString *, id> *)state forPetProfile:(PETPetProfile *)profile;
- (void)submitGameCommand:(PETGameCommand *)command;
- (void)setSelectedPetProfile:(nullable PETPetProfile *)profile;
- (nullable PETPetProfile *)selectedPetProfile;
- (void)previewState:(NSString *)state forPetProfile:(PETPetProfile *)profile;
- (void)resumeAmbientBehaviorForPetProfile:(PETPetProfile *)profile;
- (NSDictionary<NSString *, NSString *> *)interactionAliasesForPetProfile:(PETPetProfile *)profile;
- (void)setInteractionAlias:(nullable NSString *)animationState forActionKey:(NSString *)actionKey forPetProfile:(PETPetProfile *)profile;
- (void)renamePetProfile:(PETPetProfile *)profile displayName:(NSString *)displayName;
- (void)removePetProfile:(PETPetProfile *)profile;
- (void)setAllPetsHidden:(BOOL)hidden;
- (void)removeAllPets;
- (NSArray<NSDictionary<NSString *, id> *> *)serializedPetRecords;
- (nullable NSDictionary<NSString *, id> *)pixelCollisionSnapshotBetweenPetProfile:(PETPetProfile *)sourceProfile
                                                                      andPetProfile:(PETPetProfile *)targetProfile
                                                                      sampleSpacing:(CGFloat)sampleSpacing;

- (BOOL)mergeSkillLibraryFromJSONURL:(NSURL *)jsonURL error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
