#import <Foundation/Foundation.h>

@class PETCombatKeyboardBinding;
@class PETSkillLibrary;

NS_ASSUME_NONNULL_BEGIN

@interface PETCombatKeyboardBindings : NSObject

@property (nonatomic, assign, readonly) NSInteger formatVersion;
@property (nonatomic, copy, readonly) NSArray<PETCombatKeyboardBinding *> *bindings;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, PETCombatKeyboardBinding *> *bindingsByKey;

- (nullable instancetype)initWithBundle:(NSBundle *)bundle
                          skillLibrary:(nullable PETSkillLibrary *)skillLibrary
                                  error:(NSError * _Nullable * _Nullable)error;
- (nullable instancetype)initWithJSONURL:(NSURL *)jsonURL
                            skillLibrary:(nullable PETSkillLibrary *)skillLibrary
                                    error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;

+ (NSArray<PETCombatKeyboardBinding *> *)defaultBindings;
+ (instancetype)bindingsWithDefaultsValidatedBySkillLibrary:(nullable PETSkillLibrary *)skillLibrary;
- (nullable PETCombatKeyboardBinding *)bindingForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
