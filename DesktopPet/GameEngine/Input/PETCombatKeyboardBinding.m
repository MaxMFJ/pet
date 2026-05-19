#import "PETCombatKeyboardBinding.h"

@interface PETCombatKeyboardBinding ()

@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, copy) NSString *commandType;
@property (nonatomic, copy, nullable) NSString *skillIdentifier;
@property (nonatomic, copy, nullable) NSString *actionKey;

@end

@implementation PETCombatKeyboardBinding

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *,id> *)dictionary {
    self = [super init];
    if (self) {
        NSString *key = [dictionary[@"key"] isKindOfClass:NSString.class] ? dictionary[@"key"] : @"";
        NSString *commandType = [dictionary[@"commandType"] isKindOfClass:NSString.class] ? dictionary[@"commandType"] : @"";
        NSString *label = [dictionary[@"label"] isKindOfClass:NSString.class] ? dictionary[@"label"] : nil;
        NSString *skillIdentifier = [dictionary[@"skillId"] isKindOfClass:NSString.class] ? dictionary[@"skillId"] : nil;
        NSString *actionKey = [dictionary[@"actionKey"] isKindOfClass:NSString.class] ? dictionary[@"actionKey"] : nil;

        _key = [key.lowercaseString copy];
        _label = [label copy];
        _commandType = [commandType copy];
        _skillIdentifier = [skillIdentifier copy];
        _actionKey = [actionKey copy];
    }
    return self;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    NSMutableDictionary<NSString *, id> *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"key"] = self.key ?: @"";
    dictionary[@"commandType"] = self.commandType ?: @"";
    if (self.label.length > 0) {
        dictionary[@"label"] = self.label;
    }
    if (self.skillIdentifier.length > 0) {
        dictionary[@"skillId"] = self.skillIdentifier;
    }
    if (self.actionKey.length > 0) {
        dictionary[@"actionKey"] = self.actionKey;
    }
    return dictionary.copy;
}

@end
