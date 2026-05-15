#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETBehaviorDecision : NSObject

@property (nonatomic, copy, readonly) NSString *behaviorState;
@property (nonatomic, copy, readonly) NSString *behaviorMode;
@property (nonatomic, copy, readonly) NSString *behaviorReason;
@property (nonatomic, copy, readonly) NSString *animationState;
@property (nonatomic, assign, readonly) NSInteger behaviorPriority;
@property (nonatomic, copy, readonly) NSString *behaviorCategory;
@property (nonatomic, assign, readonly, getter=isInterruptible) BOOL interruptible;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *plannerContext;

- (instancetype)initWithBehaviorState:(NSString *)behaviorState
                         behaviorMode:(NSString *)behaviorMode
                       behaviorReason:(NSString *)behaviorReason
                       animationState:(NSString *)animationState
                     behaviorPriority:(NSInteger)behaviorPriority
                     behaviorCategory:(NSString *)behaviorCategory
                        interruptible:(BOOL)interruptible
                       plannerContext:(nullable NSDictionary<NSString *, id> *)plannerContext;

@end

NS_ASSUME_NONNULL_END
