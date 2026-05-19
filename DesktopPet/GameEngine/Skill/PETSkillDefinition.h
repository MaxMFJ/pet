#import <Foundation/Foundation.h>

@class PETSkillPhase;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillDefinition : NSObject

@property (nonatomic, copy, readonly) NSString *skillIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *castType;
@property (nonatomic, copy, readonly) NSString *entryPhaseIdentifier;
@property (nonatomic, copy, readonly) NSArray<NSString *> *tags;
@property (nonatomic, copy, readonly) NSArray<PETSkillPhase *> *phases;
@property (nonatomic, assign, readonly) NSTimeInterval totalDuration;

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *, id> *)dictionary NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable PETSkillPhase *)phaseWithIdentifier:(NSString *)phaseIdentifier;
- (nullable PETSkillPhase *)entryPhase;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
