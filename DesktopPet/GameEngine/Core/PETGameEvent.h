#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PETGameEventSessionRegistered;
FOUNDATION_EXPORT NSString * const PETGameEventSessionRemoved;
FOUNDATION_EXPORT NSString * const PETGameEventCommandAccepted;
FOUNDATION_EXPORT NSString * const PETGameEventCommandRejected;
FOUNDATION_EXPORT NSString * const PETGameEventTick;
FOUNDATION_EXPORT NSString * const PETGameEventCombatStateChanged;
FOUNDATION_EXPORT NSString * const PETGameEventAttackStarted;
FOUNDATION_EXPORT NSString * const PETGameEventAttackEnded;
FOUNDATION_EXPORT NSString * const PETGameEventAttackHit;

@interface PETGameEvent : NSObject

@property (nonatomic, copy, readonly) NSString *eventIdentifier;
@property (nonatomic, copy, readonly) NSString *eventType;
@property (nonatomic, copy, readonly) NSString *petIdentifier;
@property (nonatomic, copy, readonly) NSString *source;
@property (nonatomic, strong, readonly) NSDate *timestamp;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;

- (instancetype)initWithEventType:(NSString *)eventType
                     petIdentifier:(NSString *)petIdentifier
                            source:(NSString *)source
                           context:(nullable NSDictionary<NSString *, id> *)context NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
