#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCombatKeyboardBinding : NSObject

@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly, nullable) NSString *label;
@property (nonatomic, copy, readonly) NSString *commandType;
@property (nonatomic, copy, readonly, nullable) NSString *skillIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *actionKey;

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *, id> *)dictionary NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
