#import <Foundation/Foundation.h>

@class PETAppConfig;
@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const PETPetManagerDidChangePetsNotification;

@interface PETPetManager : NSObject

@property (nonatomic, copy, readonly) NSArray<PETPetProfile *> *activeProfiles;

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
- (NSArray<NSString *> *)supportedStatesForPetProfile:(PETPetProfile *)profile;
- (NSString *)currentStateForPetProfile:(PETPetProfile *)profile;
- (NSDictionary<NSString *, id> *)characterSnapshotForPetProfile:(PETPetProfile *)profile;
- (NSString *)characterRuntimeSummaryForPetProfile:(PETPetProfile *)profile;
- (void)restoreCharacterSnapshot:(NSDictionary<NSString *, id> *)snapshot forPetProfile:(PETPetProfile *)profile;
- (void)previewState:(NSString *)state forPetProfile:(PETPetProfile *)profile;
- (void)resumeAmbientBehaviorForPetProfile:(PETPetProfile *)profile;
- (NSDictionary<NSString *, NSString *> *)interactionAliasesForPetProfile:(PETPetProfile *)profile;
- (void)setInteractionAlias:(nullable NSString *)animationState forActionKey:(NSString *)actionKey forPetProfile:(PETPetProfile *)profile;
- (void)renamePetProfile:(PETPetProfile *)profile displayName:(NSString *)displayName;
- (void)removePetProfile:(PETPetProfile *)profile;
- (void)setAllPetsHidden:(BOOL)hidden;
- (void)removeAllPets;
- (NSArray<NSDictionary<NSString *, id> *> *)serializedPetRecords;

@end

NS_ASSUME_NONNULL_END
