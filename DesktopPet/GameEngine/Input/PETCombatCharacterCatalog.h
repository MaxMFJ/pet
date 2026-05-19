#import <Foundation/Foundation.h>

@class PETCombatKeyboardBinding;
@class PETSkillLibrary;

NS_ASSUME_NONNULL_BEGIN

@interface PETCombatCharacterProfile : NSObject

@property (nonatomic, copy, readonly) NSString *characterIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *sourceStem;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *interactionAliases;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, PETCombatKeyboardBinding *> *bindingsByKey;

- (nullable PETCombatKeyboardBinding *)bindingForKey:(NSString *)key;

@end

FOUNDATION_EXPORT NSString * const PETSoulArkCharacterSourceStemPrefix;
FOUNDATION_EXPORT NSString * const PETSoulArkCharacterDefaultProfileStem;

@interface PETCombatCharacterCatalog : NSObject

@property (nonatomic, copy, readonly) NSDictionary<NSString *, PETCombatCharacterProfile *> *profilesBySourceStem;
@property (nonatomic, strong, readonly, nullable) PETCombatCharacterProfile *soulArkCharacterDefaultProfile;

- (instancetype)initWithBundle:(NSBundle *)bundle skillLibrary:(nullable PETSkillLibrary *)skillLibrary;
- (void)registerProfile:(PETCombatCharacterProfile *)profile forSourceStem:(NSString *)sourceStem;
- (nullable PETCombatCharacterProfile *)profileForSourceStem:(NSString *)sourceStem;
- (nullable PETCombatCharacterProfile *)profileForSourceURL:(NSURL *)sourceURL;
- (nullable PETCombatCharacterProfile *)loadProfileForSourceURL:(NSURL *)sourceURL skillLibrary:(nullable PETSkillLibrary *)skillLibrary;

@end

NS_ASSUME_NONNULL_END
