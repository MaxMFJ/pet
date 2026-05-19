#import "PETCombatKeyboardBindings.h"

#import "../Core/PETGameCommand.h"
#import "../Skill/PETSkillLibrary.h"
#import "PETCombatKeyboardBinding.h"

static NSString * const PETCombatKeyboardBindingsErrorDomain = @"PETCombatKeyboardBindings";

static NSURL *PETCombatBindingsFindResourceURL(NSString *relativePath) {
    if (relativePath.length == 0) {
        return nil;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = @[
        NSBundle.mainBundle.resourcePath ?: @"",
        NSBundle.mainBundle.bundlePath ?: @"",
        NSFileManager.defaultManager.currentDirectoryPath ?: @"",
    ];
    NSArray<NSString *> *candidateRelativePaths = @[
        relativePath,
        [@"Resources/" stringByAppendingString:relativePath],
        [@"DesktopPet/Resources/" stringByAppendingString:relativePath],
    ];
    for (NSString *root in roots) {
        if (root.length == 0) {
            continue;
        }
        for (NSString *candidateRelativePath in candidateRelativePaths) {
            NSString *candidatePath = [root stringByAppendingPathComponent:candidateRelativePath];
            if ([fileManager fileExistsAtPath:candidatePath]) {
                return [NSURL fileURLWithPath:candidatePath];
            }
        }
    }
    return nil;
}

@implementation PETCombatKeyboardBindings

+ (instancetype)bindingsWithDefaultsValidatedBySkillLibrary:(PETSkillLibrary *)skillLibrary {
    PETCombatKeyboardBindings *bindings = [[self alloc] init];
    NSMutableArray<PETCombatKeyboardBinding *> *validatedBindings = [NSMutableArray array];
    NSMutableDictionary<NSString *, PETCombatKeyboardBinding *> *bindingsByKey = [NSMutableDictionary dictionary];
    for (PETCombatKeyboardBinding *binding in [self defaultBindings]) {
        if (![bindings validateBinding:binding skillLibrary:skillLibrary]) {
            continue;
        }
        if (bindingsByKey[binding.key] != nil) {
            continue;
        }
        [validatedBindings addObject:binding];
        bindingsByKey[binding.key] = binding;
    }
    bindings->_formatVersion = 1;
    bindings->_bindings = validatedBindings.copy;
    bindings->_bindingsByKey = bindingsByKey.copy;
    return bindings;
}

+ (NSArray<PETCombatKeyboardBinding *> *)defaultBindings {
    NSArray<NSDictionary<NSString *, id> *> *rawBindings = @[
        @{@"key": @"j", @"label": @"Primary", @"commandType": PETGameCommandSkillCast, @"skillId": @"basic_primary_strike", @"actionKey": @"combat.primary"},
        @{@"key": @"k", @"label": @"Secondary", @"commandType": PETGameCommandAttackSecondary, @"actionKey": @"combat.secondary"},
        @{@"key": @"l", @"label": @"Skill", @"commandType": PETGameCommandSkillCast, @"skillId": @"spear_sky_pierce", @"actionKey": @"combat.skill.1"},
        @{@"key": @"u", @"label": @"Ultimate", @"commandType": PETGameCommandUltimateCast, @"skillId": @"spear_sky_pierce", @"actionKey": @"combat.ultimate"},
        @{@"key": @"i", @"label": @"Quick Strike", @"commandType": PETGameCommandAttackPrimary, @"actionKey": @"combat.quick"},
        @{@"key": @"o", @"label": @"Cancel", @"commandType": PETGameCommandSkillCancel, @"actionKey": @"combat.cancel"},
    ];
    NSMutableArray<PETCombatKeyboardBinding *> *bindings = [NSMutableArray arrayWithCapacity:rawBindings.count];
    for (NSDictionary<NSString *, id> *rawBinding in rawBindings) {
        [bindings addObject:[[PETCombatKeyboardBinding alloc] initWithDictionaryRepresentation:rawBinding]];
    }
    return bindings.copy;
}

- (instancetype)initWithBundle:(NSBundle *)bundle
                  skillLibrary:(PETSkillLibrary *)skillLibrary
                         error:(NSError *__autoreleasing *)error {
    NSURL *jsonURL = [bundle URLForResource:@"combat-keybindings" withExtension:@"json" subdirectory:@"Combat"];
    if (jsonURL == nil) {
        jsonURL = PETCombatBindingsFindResourceURL(@"Combat/combat-keybindings.json");
    }
    if (jsonURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETCombatKeyboardBindingsErrorDomain
                                         code:9201
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to locate Combat/combat-keybindings.json in the app bundle."}];
        }
        return nil;
    }
    return [self initWithJSONURL:jsonURL skillLibrary:skillLibrary error:error];
}

- (instancetype)initWithJSONURL:(NSURL *)jsonURL skillLibrary:(PETSkillLibrary *)skillLibrary error:(NSError *__autoreleasing *)error {
    NSData *data = [NSData dataWithContentsOfURL:jsonURL options:0 error:error];
    if (data == nil) {
        return nil;
    }

    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![rootObject isKindOfClass:NSDictionary.class]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETCombatKeyboardBindingsErrorDomain
                                         code:9202
                                     userInfo:@{NSLocalizedDescriptionKey: @"combat-keybindings.json root object must be a dictionary."}];
        }
        return nil;
    }

    NSDictionary<NSString *, id> *root = rootObject;
    NSArray<NSDictionary<NSString *, id> *> *rawBindings = [root[@"bindings"] isKindOfClass:NSArray.class] ? root[@"bindings"] : @[];
    NSMutableArray<PETCombatKeyboardBinding *> *bindings = [NSMutableArray arrayWithCapacity:rawBindings.count];
    NSMutableDictionary<NSString *, PETCombatKeyboardBinding *> *bindingsByKey = [NSMutableDictionary dictionaryWithCapacity:rawBindings.count];

    for (NSDictionary<NSString *, id> *rawBinding in rawBindings) {
        if (![rawBinding isKindOfClass:NSDictionary.class]) {
            continue;
        }
        PETCombatKeyboardBinding *binding = [[PETCombatKeyboardBinding alloc] initWithDictionaryRepresentation:rawBinding];
        if (binding.key.length == 0 || binding.commandType.length == 0) {
            continue;
        }
        if (![self validateBinding:binding skillLibrary:skillLibrary]) {
            continue;
        }
        if (bindingsByKey[binding.key] != nil) {
            continue;
        }
        [bindings addObject:binding];
        bindingsByKey[binding.key] = binding;
    }

    if (bindings.count == 0) {
        bindings = [[self class] defaultBindings].mutableCopy;
        [bindingsByKey removeAllObjects];
        for (PETCombatKeyboardBinding *binding in bindings) {
            bindingsByKey[binding.key] = binding;
        }
    }

    self = [super init];
    if (self) {
        _formatVersion = [root[@"formatVersion"] integerValue];
        _bindings = bindings.copy;
        _bindingsByKey = bindingsByKey.copy;
    }
    return self;
}

- (BOOL)validateBinding:(PETCombatKeyboardBinding *)binding skillLibrary:(PETSkillLibrary *)skillLibrary {
    NSSet<NSString *> *supportedCommandTypes = [NSSet setWithArray:@[
        PETGameCommandAttackPrimary,
        PETGameCommandAttackSecondary,
        PETGameCommandSkillCast,
        PETGameCommandSkillCancel,
        PETGameCommandUltimateCast,
    ]];
    if (![supportedCommandTypes containsObject:binding.commandType]) {
        return NO;
    }

    BOOL requiresSkillIdentifier = [binding.commandType isEqualToString:PETGameCommandSkillCast] ||
                                   [binding.commandType isEqualToString:PETGameCommandUltimateCast];
    if (requiresSkillIdentifier && binding.skillIdentifier.length == 0) {
        return NO;
    }
    if (binding.skillIdentifier.length > 0 && skillLibrary != nil && [skillLibrary skillDefinitionForIdentifier:binding.skillIdentifier] == nil) {
        NSLog(@"[DesktopPet] Combat keyboard binding kept despite unknown skillId=%@ key=%@",
              binding.skillIdentifier,
              binding.key);
    }
    return YES;
}

- (nullable PETCombatKeyboardBinding *)bindingForKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    return self.bindingsByKey[key.lowercaseString];
}

@end
