#import <Foundation/Foundation.h>

@class PETCharacterIntent;

NS_ASSUME_NONNULL_BEGIN

@interface PETIntentEngine : NSObject

- (PETCharacterIntent *)intentForActionKey:(NSString *)actionKey
                     fallbackBehaviorState:(nullable NSString *)fallbackBehaviorState
                    resolvedAnimationState:(NSString *)resolvedAnimationState
                                   context:(nullable NSDictionary<NSString *, id> *)context;

- (PETCharacterIntent *)ambientIntentWithAnimationState:(NSString *)animationState
                                                context:(nullable NSDictionary<NSString *, id> *)context;

- (PETCharacterIntent *)manualPreviewIntentWithAnimationState:(NSString *)animationState
                                                      context:(nullable NSDictionary<NSString *, id> *)context;

@end

NS_ASSUME_NONNULL_END
