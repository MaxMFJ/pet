#import <Foundation/Foundation.h>

@class PETSkillDefinition;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillLibrary : NSObject

@property (nonatomic, assign, readonly) NSInteger formatVersion;
@property (nonatomic, copy, readonly) NSArray<PETSkillDefinition *> *skills;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary<NSString *, id> *> *reactionDefinitionsByIdentifier;

- (nullable instancetype)initWithBundle:(NSBundle *)bundle error:(NSError * _Nullable * _Nullable)error;
- (nullable instancetype)initWithJSONURL:(NSURL *)jsonURL error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable PETSkillDefinition *)skillDefinitionForIdentifier:(NSString *)skillIdentifier;
- (nullable NSDictionary<NSString *, id> *)reactionDefinitionForIdentifier:(NSString *)reactionIdentifier;
- (BOOL)mergeFromJSONURL:(NSURL *)jsonURL error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
