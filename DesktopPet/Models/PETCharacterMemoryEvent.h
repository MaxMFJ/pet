#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterMemoryEvent : NSObject

@property (nonatomic, copy, readonly) NSString *eventIdentifier;
@property (nonatomic, copy, readonly) NSString *eventType;
@property (nonatomic, copy, readonly) NSString *summary;
@property (nonatomic, assign, readonly) NSInteger salience;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *metadata;
@property (nonatomic, strong, readonly) NSDate *timestamp;

- (instancetype)initWithEventIdentifier:(NSString *)eventIdentifier
                              eventType:(NSString *)eventType
                                summary:(NSString *)summary
                               salience:(NSInteger)salience
                               metadata:(nullable NSDictionary<NSString *, id> *)metadata
                              timestamp:(NSDate *)timestamp;

- (NSDictionary<NSString *, id> *)serializedRepresentation;
+ (nullable instancetype)eventFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
