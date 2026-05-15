#import "PETBehaviorDecision.h"

@implementation PETBehaviorDecision

- (instancetype)initWithBehaviorState:(NSString *)behaviorState
                         behaviorMode:(NSString *)behaviorMode
                       behaviorReason:(NSString *)behaviorReason
                       animationState:(NSString *)animationState
                     behaviorPriority:(NSInteger)behaviorPriority
                     behaviorCategory:(NSString *)behaviorCategory
                        interruptible:(BOOL)interruptible
                       plannerContext:(NSDictionary<NSString *,id> *)plannerContext {
    self = [super init];
    if (self) {
        _behaviorState = [behaviorState copy];
        _behaviorMode = [behaviorMode copy];
        _behaviorReason = [behaviorReason copy];
        _animationState = [animationState copy];
        _behaviorPriority = behaviorPriority;
        _behaviorCategory = [behaviorCategory copy];
        _interruptible = interruptible;
        _plannerContext = [plannerContext copy] ?: @{};
    }
    return self;
}

@end
