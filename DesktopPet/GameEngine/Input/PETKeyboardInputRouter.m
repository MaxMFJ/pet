#import "PETKeyboardInputRouter.h"

#import "../Core/PETGameCommand.h"
#import "PETCombatCharacterCatalog.h"
#import "PETCombatKeyboardBinding.h"
#import "PETCombatKeyboardBindings.h"

@interface PETKeyboardInputRouter ()

@property (nonatomic, strong) id keyDownMonitor;
@property (nonatomic, strong) id keyUpMonitor;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *pressedDirectionsByKeyCode;
@property (nonatomic, assign, getter=isRunning) BOOL running;

@end

static NSDictionary<NSNumber *, NSString *> *PETCombatKeyCodesByKeyCode(void) {
    static NSDictionary<NSNumber *, NSString *> *mapping = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mapping = @{
            @(38): @"j",
            @(40): @"k",
            @(37): @"l",
            @(32): @"u",
            @(34): @"i",
            @(31): @"o",
        };
    });
    return mapping;
}

@implementation PETKeyboardInputRouter

- (instancetype)init {
    self = [super init];
    if (self) {
        _pressedDirectionsByKeyCode = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)start {
    if (self.isRunning) {
        return;
    }
    self.running = YES;
    __weak typeof(self) weakSelf = self;
    self.keyDownMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        return [strongSelf handleKeyEvent:event pressed:YES];
    }];
    self.keyUpMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp handler:^NSEvent * _Nullable(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        return [strongSelf handleKeyEvent:event pressed:NO];
    }];
}

- (void)stop {
    if (self.keyDownMonitor != nil) {
        [NSEvent removeMonitor:self.keyDownMonitor];
        self.keyDownMonitor = nil;
    }
    if (self.keyUpMonitor != nil) {
        [NSEvent removeMonitor:self.keyUpMonitor];
        self.keyUpMonitor = nil;
    }
    [self releaseAllPressedKeys];
    self.running = NO;
}

- (NSEvent *)handleKeyEvent:(NSEvent *)event pressed:(BOOL)pressed {
    if ([self shouldPassThroughEventToTextInput:event]) {
        return event;
    }
    if (event.isARepeat) {
        return nil;
    }
    if ([self isJumpEvent:event]) {
        [self emitJumpCommandPressed:pressed key:event.charactersIgnoringModifiers ?: @"" keyCode:event.keyCode];
        return nil;
    }
    if (pressed && [self handleCombatKeyEvent:event]) {
        return nil;
    }
    NSString *direction = [self directionForEvent:event];
    if (direction.length == 0) {
        return event;
    }

    NSNumber *keyCode = @(event.keyCode);
    if (pressed) {
        if (self.pressedDirectionsByKeyCode[keyCode] != nil) {
            return nil;
        }
        self.pressedDirectionsByKeyCode[keyCode] = direction;
    } else {
        if (self.pressedDirectionsByKeyCode[keyCode] == nil) {
            return nil;
        }
        [self.pressedDirectionsByKeyCode removeObjectForKey:keyCode];
    }
    [self emitMoveCommandForDirection:direction pressed:pressed key:event.charactersIgnoringModifiers ?: @"" keyCode:event.keyCode];
    return nil;
}

- (BOOL)shouldPassThroughEventToTextInput:(NSEvent *)event {
    if ([self hasCombatBindingForEvent:event]) {
        return NO;
    }
    NSString *direction = [self directionForEvent:event];
    if (direction.length == 0 && ![self isJumpEvent:event]) {
        return NO;
    }
    NSResponder *firstResponder = NSApp.keyWindow.firstResponder;
    return [firstResponder isKindOfClass:NSTextView.class] || [firstResponder isKindOfClass:NSTextField.class];
}

- (BOOL)hasCombatBindingForEvent:(NSEvent *)event {
    if ([self combatBindingForEvent:event petIdentifier:nil] != nil) {
        return YES;
    }
    NSArray<NSString *> *petIdentifiers = self.petProvider != nil ? self.petProvider() : @[];
    for (NSString *petIdentifier in petIdentifiers) {
        if ([self combatBindingForEvent:event petIdentifier:petIdentifier] != nil) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)resolvedCombatKeyForEvent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers.lowercaseString ?: @"";
    if (key.length == 1) {
        unichar character = [key characterAtIndex:0];
        if (character >= 'a' && character <= 'z') {
            return key;
        }
    }
    return PETCombatKeyCodesByKeyCode()[@(event.keyCode)] ?: @"";
}

- (BOOL)handleCombatKeyEvent:(NSEvent *)event {
    NSString *key = [self resolvedCombatKeyForEvent:event];
    if (key.length == 0) {
        return NO;
    }
    if ([self shouldPassThroughEventToTextInput:event]) {
        return NO;
    }

    NSArray<NSString *> *petIdentifiers = self.petProvider != nil ? self.petProvider() : @[];
    if (petIdentifiers.count == 0) {
        return NO;
    }

    BOOL emitted = NO;
    for (NSString *petIdentifier in petIdentifiers) {
        PETCombatKeyboardBinding *binding = [self combatBindingForKey:key petIdentifier:petIdentifier];
        if (binding == nil) {
            continue;
        }
        [self emitCombatCommandForBinding:binding
                            petIdentifier:petIdentifier
                                      key:key
                                  keyCode:event.keyCode];
        emitted = YES;
    }
    return emitted;
}

- (nullable PETCombatKeyboardBinding *)combatBindingForEvent:(NSEvent *)event petIdentifier:(nullable NSString *)petIdentifier {
    NSString *key = [self resolvedCombatKeyForEvent:event];
    if (key.length == 0) {
        return nil;
    }
    return [self combatBindingForKey:key petIdentifier:petIdentifier];
}

- (nullable PETCombatKeyboardBinding *)combatBindingForKey:(NSString *)key petIdentifier:(nullable NSString *)petIdentifier {
    if (key.length == 0) {
        return nil;
    }

    if (petIdentifier.length > 0 && self.combatProfileProvider != nil) {
        PETCombatCharacterProfile *characterProfile = self.combatProfileProvider(petIdentifier);
        PETCombatKeyboardBinding *characterBinding = [characterProfile bindingForKey:key];
        if (characterProfile != nil && characterBinding != nil) {
            NSLog(@"[DesktopPet] Combat profile binding lookup pet=%@ key=%@ sourceStem=%@ found=YES skillId=%@",
                  petIdentifier ?: @"",
                  key ?: @"",
                  characterProfile.sourceStem ?: @"",
                  characterBinding.skillIdentifier ?: @"");
        }
        if (characterBinding != nil) {
            return characterBinding;
        }
    }

    if (petIdentifier.length > 0 && self.petSourceURLProvider != nil && self.combatCharacterCatalog != nil) {
        NSURL *sourceURL = self.petSourceURLProvider(petIdentifier);
        PETCombatCharacterProfile *characterProfile = [self.combatCharacterCatalog profileForSourceURL:sourceURL];
        PETCombatKeyboardBinding *characterBinding = [characterProfile bindingForKey:key];
        if (characterBinding != nil) {
            return characterBinding;
        }
    }

    if (self.combatBindings == nil) {
        return nil;
    }
    return [self.combatBindings bindingForKey:key];
}

- (nullable PETCombatKeyboardBinding *)combatBindingForEvent:(NSEvent *)event {
    return [self combatBindingForEvent:event petIdentifier:nil];
}

- (void)emitCombatCommandForBinding:(PETCombatKeyboardBinding *)binding
                    petIdentifier:(NSString *)petIdentifier
                              key:(NSString *)key
                          keyCode:(unsigned short)keyCode {
    NSMutableDictionary<NSString *, id> *context = [@{
        @"key": key ?: @"",
        @"keyCode": @(keyCode),
    } mutableCopy];
    if (binding.label.length > 0) {
        context[@"label"] = binding.label;
    }
    if (binding.actionKey.length > 0) {
        context[@"actionKey"] = binding.actionKey;
    }

    PETGameCommand *command = [[PETGameCommand alloc] initWithPetIdentifier:petIdentifier
                                                                 commandType:binding.commandType
                                                                      source:PETGameCommandSourceKeyboard
                                                                   direction:nil
                                                             skillIdentifier:binding.skillIdentifier
                                                                    strength:1.0
                                                                     context:context.copy];
    NSLog(@"[DesktopPet] Combat key routed pet=%@ key=%@ commandType=%@ skillId=%@ actionKey=%@",
          petIdentifier ?: @"",
          key ?: @"",
          binding.commandType ?: @"",
          binding.skillIdentifier ?: @"",
          binding.actionKey ?: @"");
    if (self.commandHandler != nil) {
        self.commandHandler(command);
    }
}

- (void)releaseAllPressedKeys {
    NSDictionary<NSNumber *, NSString *> *pressed = self.pressedDirectionsByKeyCode.copy;
    [self.pressedDirectionsByKeyCode removeAllObjects];
    [pressed enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull keyCode, NSString * _Nonnull direction, BOOL * _Nonnull stop) {
        (void)stop;
        [self emitMoveCommandForDirection:direction pressed:NO key:@"" keyCode:keyCode.unsignedShortValue];
    }];
}

- (void)emitMoveCommandForDirection:(NSString *)direction pressed:(BOOL)pressed key:(NSString *)key keyCode:(unsigned short)keyCode {
    NSArray<NSString *> *petIdentifiers = self.petProvider != nil ? self.petProvider() : @[];
    for (NSString *petIdentifier in petIdentifiers) {
        PETGameCommand *command = [[PETGameCommand alloc] initWithPetIdentifier:petIdentifier
                                                                     commandType:pressed ? PETGameCommandMovePressed : PETGameCommandMoveReleased
                                                                          source:PETGameCommandSourceKeyboard
                                                                       direction:direction
                                                                 skillIdentifier:nil
                                                                        strength:1.0
                                                                         context:@{@"key": key ?: @"", @"keyCode": @(keyCode)}];
        if (self.commandHandler != nil) {
            self.commandHandler(command);
        }
    }
}

- (void)emitJumpCommandPressed:(BOOL)pressed key:(NSString *)key keyCode:(unsigned short)keyCode {
    NSArray<NSString *> *petIdentifiers = self.petProvider != nil ? self.petProvider() : @[];
    for (NSString *petIdentifier in petIdentifiers) {
        PETGameCommand *command = [[PETGameCommand alloc] initWithPetIdentifier:petIdentifier
                                                                     commandType:pressed ? PETGameCommandJumpPressed : PETGameCommandJumpReleased
                                                                          source:PETGameCommandSourceKeyboard
                                                                       direction:nil
                                                                 skillIdentifier:nil
                                                                        strength:1.0
                                                                         context:@{@"key": key ?: @"", @"keyCode": @(keyCode)}];
        if (self.commandHandler != nil) {
            self.commandHandler(command);
        }
    }
}

- (BOOL)isJumpEvent:(NSEvent *)event {
    return event.keyCode == 49;
}

- (NSString *)directionForEvent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers.lowercaseString ?: @"";
    if ([key isEqualToString:@"w"]) {
        return PETGameDirectionUp;
    }
    if ([key isEqualToString:@"s"]) {
        return PETGameDirectionDown;
    }
    if ([key isEqualToString:@"a"]) {
        return PETGameDirectionLeft;
    }
    if ([key isEqualToString:@"d"]) {
        return PETGameDirectionRight;
    }

    switch (event.keyCode) {
        case 126:
            return PETGameDirectionUp;
        case 125:
            return PETGameDirectionDown;
        case 123:
            return PETGameDirectionLeft;
        case 124:
            return PETGameDirectionRight;
        default:
            return nil;
    }
}

@end
