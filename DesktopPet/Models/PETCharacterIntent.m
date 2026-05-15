#import "PETCharacterIntent.h"

@implementation PETCharacterIntent

- (instancetype)initWithName:(NSString *)name
                      source:(NSString *)source
                  confidence:(double)confidence
                   actionKey:(NSString *)actionKey
       fallbackBehaviorState:(NSString *)fallbackBehaviorState
      resolvedAnimationState:(NSString *)resolvedAnimationState
                     context:(NSDictionary<NSString *,id> *)context {
    self = [super init];
    if (self) {
        _name = [name copy];
        _source = [source copy];
        _confidence = confidence;
        _actionKey = [actionKey copy];
        _fallbackBehaviorState = [fallbackBehaviorState copy];
        _resolvedAnimationState = [resolvedAnimationState copy];
        _context = [context copy] ?: @{};
    }
    return self;
}

@end
