#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterGoal : NSObject

@property (nonatomic, copy, readonly) NSString *goalIdentifier;
@property (nonatomic, copy, readonly) NSString *goalName;
@property (nonatomic, copy, readonly) NSString *goalCategory;
@property (nonatomic, copy, readonly) NSString *targetBehaviorState;
@property (nonatomic, assign, readonly) NSInteger priority;
@property (nonatomic, strong, readonly, nullable) NSDate *expiresAt;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;

- (instancetype)initWithGoalIdentifier:(NSString *)goalIdentifier
                              goalName:(NSString *)goalName
                          goalCategory:(NSString *)goalCategory
                   targetBehaviorState:(NSString *)targetBehaviorState
                              priority:(NSInteger)priority
                             expiresAt:(nullable NSDate *)expiresAt
                               context:(nullable NSDictionary<NSString *, id> *)context;

- (BOOL)isActiveAtDate:(NSDate *)date;
- (NSDictionary<NSString *, id> *)serializedRepresentation;
+ (nullable instancetype)goalFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
