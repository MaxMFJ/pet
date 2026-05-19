#import <Cocoa/Cocoa.h>

@class PETCombatCharacterCatalog;
@class PETCombatCharacterProfile;
@class PETCombatKeyboardBinding;
@class PETCombatKeyboardBindings;
@class PETGameCommand;

NS_ASSUME_NONNULL_BEGIN

typedef NSArray<NSString *> * _Nonnull (^PETKeyboardInputPetProvider)(void);
typedef NSURL * _Nullable (^PETKeyboardInputPetSourceURLProvider)(NSString *petIdentifier);
typedef PETCombatCharacterProfile * _Nullable (^PETKeyboardInputCombatProfileProvider)(NSString *petIdentifier);
typedef void (^PETKeyboardInputCommandHandler)(PETGameCommand *command);

@interface PETKeyboardInputRouter : NSObject

@property (nonatomic, copy, nullable) PETKeyboardInputPetProvider petProvider;
@property (nonatomic, copy, nullable) PETKeyboardInputPetSourceURLProvider petSourceURLProvider;
@property (nonatomic, copy, nullable) PETKeyboardInputCombatProfileProvider combatProfileProvider;
@property (nonatomic, copy, nullable) PETKeyboardInputCommandHandler commandHandler;
@property (nonatomic, strong, nullable) PETCombatKeyboardBindings *combatBindings;
@property (nonatomic, strong, nullable) PETCombatCharacterCatalog *combatCharacterCatalog;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;

- (void)start;
- (void)stop;
- (void)releaseAllPressedKeys;

@end

NS_ASSUME_NONNULL_END
