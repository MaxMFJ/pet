#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETSkillDefinition;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillReactionDefinition : NSObject

@property (nonatomic, copy, readonly) NSString *reactionIdentifier;
@property (nonatomic, copy, readonly) NSString *combatState;
@property (nonatomic, copy, readonly, nullable) NSString *animationState;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) CGFloat gravityScale;
@property (nonatomic, assign, readonly) BOOL lockHorizontal;
@property (nonatomic, assign, readonly) BOOL lockVertical;
@property (nonatomic, assign, readonly, getter=isKnockdown) BOOL knockdown;
@property (nonatomic, assign, readonly) CGVector launchVector;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *dictionaryRepresentation;

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *, id> *)dictionary NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface PETSkillLibrary : NSObject

@property (nonatomic, assign, readonly) NSInteger formatVersion;
@property (nonatomic, copy, readonly) NSArray<PETSkillDefinition *> *skills;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, PETSkillReactionDefinition *> *reactionDefinitionsByIdentifier;

- (nullable instancetype)initWithBundle:(NSBundle *)bundle error:(NSError * _Nullable * _Nullable)error;
- (nullable instancetype)initWithJSONURL:(NSURL *)jsonURL error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable PETSkillDefinition *)skillDefinitionForIdentifier:(NSString *)skillIdentifier;
- (nullable PETSkillReactionDefinition *)reactionDefinitionForIdentifier:(NSString *)reactionIdentifier;
- (BOOL)mergeFromJSONURL:(NSURL *)jsonURL error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
