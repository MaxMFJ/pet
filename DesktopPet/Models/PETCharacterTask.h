#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterTask : NSObject

@property (nonatomic, copy, readonly) NSString *taskIdentifier;
@property (nonatomic, copy, readonly) NSString *taskName;
@property (nonatomic, copy, readonly) NSString *taskCategory;
@property (nonatomic, copy, readonly) NSString *status;
@property (nonatomic, assign, readonly) NSInteger priority;
@property (nonatomic, assign, readonly) NSInteger progress;
@property (nonatomic, assign, readonly) NSInteger requiredProgress;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, strong, readonly) NSDate *updatedAt;
@property (nonatomic, strong, readonly, nullable) NSDate *expiresAt;

- (instancetype)initWithTaskIdentifier:(NSString *)taskIdentifier
                              taskName:(NSString *)taskName
                          taskCategory:(NSString *)taskCategory
                                status:(NSString *)status
                              priority:(NSInteger)priority
                              progress:(NSInteger)progress
                      requiredProgress:(NSInteger)requiredProgress
                               context:(nullable NSDictionary<NSString *, id> *)context
                             createdAt:(NSDate *)createdAt
                             updatedAt:(NSDate *)updatedAt
                             expiresAt:(nullable NSDate *)expiresAt;

- (BOOL)isActiveAtDate:(NSDate *)date;
- (NSDictionary<NSString *, id> *)serializedRepresentation;
+ (nullable instancetype)taskFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
