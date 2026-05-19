#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PETGameCommandMovePressed;
FOUNDATION_EXPORT NSString * const PETGameCommandMoveReleased;
FOUNDATION_EXPORT NSString * const PETGameCommandJumpPressed;
FOUNDATION_EXPORT NSString * const PETGameCommandJumpReleased;
FOUNDATION_EXPORT NSString * const PETGameCommandAttackPrimary;
FOUNDATION_EXPORT NSString * const PETGameCommandAttackSecondary;
FOUNDATION_EXPORT NSString * const PETGameCommandSkillCast;
FOUNDATION_EXPORT NSString * const PETGameCommandSkillCancel;
FOUNDATION_EXPORT NSString * const PETGameCommandUltimateCast;
FOUNDATION_EXPORT NSString * const PETGameCommandPause;
FOUNDATION_EXPORT NSString * const PETGameCommandResume;

FOUNDATION_EXPORT NSString * const PETGameDirectionUp;
FOUNDATION_EXPORT NSString * const PETGameDirectionDown;
FOUNDATION_EXPORT NSString * const PETGameDirectionLeft;
FOUNDATION_EXPORT NSString * const PETGameDirectionRight;

FOUNDATION_EXPORT NSString * const PETGameCommandSourceKeyboard;
FOUNDATION_EXPORT NSString * const PETGameCommandSourceMouse;
FOUNDATION_EXPORT NSString * const PETGameCommandSourceTouch;
FOUNDATION_EXPORT NSString * const PETGameCommandSourceRuntime;
FOUNDATION_EXPORT NSString * const PETGameCommandSourceDebug;

@interface PETGameCommand : NSObject

@property (nonatomic, copy, readonly) NSString *commandIdentifier;
@property (nonatomic, copy, readonly) NSString *petIdentifier;
@property (nonatomic, copy, readonly) NSString *commandType;
@property (nonatomic, copy, readonly) NSString *source;
@property (nonatomic, copy, readonly, nullable) NSString *direction;
@property (nonatomic, copy, readonly, nullable) NSString *skillIdentifier;
@property (nonatomic, assign, readonly) double strength;
@property (nonatomic, strong, readonly) NSDate *timestamp;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;

- (instancetype)initWithPetIdentifier:(NSString *)petIdentifier
                           commandType:(NSString *)commandType
                                source:(NSString *)source
                             direction:(nullable NSString *)direction
                       skillIdentifier:(nullable NSString *)skillIdentifier
                              strength:(double)strength
                               context:(nullable NSDictionary<NSString *, id> *)context NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
