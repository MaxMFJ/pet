#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterIntent : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *source;
@property (nonatomic, assign, readonly) double confidence;
@property (nonatomic, copy, readonly) NSString *actionKey;
@property (nonatomic, copy, readonly) NSString *fallbackBehaviorState;
@property (nonatomic, copy, readonly) NSString *resolvedAnimationState;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;

- (instancetype)initWithName:(NSString *)name
                      source:(NSString *)source
                  confidence:(double)confidence
                   actionKey:(NSString *)actionKey
       fallbackBehaviorState:(NSString *)fallbackBehaviorState
      resolvedAnimationState:(NSString *)resolvedAnimationState
                     context:(nullable NSDictionary<NSString *, id> *)context;

@end

NS_ASSUME_NONNULL_END
