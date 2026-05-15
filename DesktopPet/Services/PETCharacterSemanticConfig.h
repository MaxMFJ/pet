#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterSemanticConfig : NSObject

+ (instancetype)sharedConfig;

- (NSDictionary<NSString *, id> *)intentRuleForActionKey:(NSString *)actionKey;
- (NSDictionary<NSString *, id> *)emotionRuleForIntentName:(NSString *)intentName
                                                 actionKey:(NSString *)actionKey;
- (NSDictionary<NSString *, id> *)goalRuleForIntentName:(NSString *)intentName
                                              actionKey:(NSString *)actionKey;
- (NSDictionary<NSString *, id> *)taskRuleForIntentName:(NSString *)intentName
                                              actionKey:(NSString *)actionKey;
- (NSDictionary<NSString *, id> *)behaviorRuleForIntentName:(NSString *)intentName
                                                  actionKey:(NSString *)actionKey;

@end

NS_ASSUME_NONNULL_END
