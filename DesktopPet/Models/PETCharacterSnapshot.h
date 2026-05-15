#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterSnapshot : NSObject

@property (nonatomic, copy, readonly) NSString *schemaVersion;
@property (nonatomic, copy, readonly) NSString *intentName;
@property (nonatomic, copy, readonly) NSString *intentSource;
@property (nonatomic, assign, readonly) double intentConfidence;
@property (nonatomic, copy, readonly) NSString *emotionLabel;
@property (nonatomic, assign, readonly) double emotionValence;
@property (nonatomic, assign, readonly) double emotionArousal;
@property (nonatomic, copy, readonly) NSString *behaviorState;
@property (nonatomic, copy, readonly) NSString *behaviorMode;
@property (nonatomic, copy, readonly) NSString *behaviorReason;
@property (nonatomic, copy, readonly) NSString *animationState;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;
@property (nonatomic, strong, readonly) NSDate *timestamp;

- (instancetype)initWithIntentName:(NSString *)intentName
                      intentSource:(NSString *)intentSource
                  intentConfidence:(double)intentConfidence
                      emotionLabel:(NSString *)emotionLabel
                    emotionValence:(double)emotionValence
                    emotionArousal:(double)emotionArousal
                     behaviorState:(NSString *)behaviorState
                      behaviorMode:(NSString *)behaviorMode
                    behaviorReason:(NSString *)behaviorReason
                    animationState:(NSString *)animationState
                           context:(nullable NSDictionary<NSString *, id> *)context
                         timestamp:(NSDate *)timestamp;

- (NSDictionary<NSString *, id> *)serializedRepresentation;
+ (nullable instancetype)snapshotFromDictionary:(NSDictionary<NSString *, id> *)dictionary;
- (NSString *)runtimeSummary;

@end

NS_ASSUME_NONNULL_END
