#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETHitResult : NSObject

@property (nonatomic, copy, readonly) NSString *hitIdentifier;
@property (nonatomic, copy, readonly) NSString *sourcePetIdentifier;
@property (nonatomic, copy, readonly) NSString *targetPetIdentifier;
@property (nonatomic, copy, readonly) NSString *attackIdentifier;
@property (nonatomic, copy, readonly) NSString *attackKind;
@property (nonatomic, strong, readonly) NSDate *timestamp;
@property (nonatomic, assign, readonly) NSTimeInterval hitStunDuration;
@property (nonatomic, assign, readonly) NSTimeInterval knockdownDuration;
@property (nonatomic, assign, readonly) CGVector launchVector;
@property (nonatomic, copy, readonly, nullable) NSString *combatState;
@property (nonatomic, assign, readonly) BOOL causesKnockdown;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *collisionSnapshot;

- (instancetype)initWithSourcePetIdentifier:(NSString *)sourcePetIdentifier
                        targetPetIdentifier:(NSString *)targetPetIdentifier
                           attackIdentifier:(NSString *)attackIdentifier
                                 attackKind:(NSString *)attackKind
                            hitStunDuration:(NSTimeInterval)hitStunDuration
                         knockdownDuration:(NSTimeInterval)knockdownDuration
                               launchVector:(CGVector)launchVector
                                combatState:(nullable NSString *)combatState
                           causesKnockdown:(BOOL)causesKnockdown
                          collisionSnapshot:(nullable NSDictionary<NSString *, id> *)collisionSnapshot NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
