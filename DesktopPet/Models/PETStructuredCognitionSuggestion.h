#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETStructuredCognitionSuggestion : NSObject

@property (nonatomic, copy, readonly) NSString *actionKey;
@property (nonatomic, copy, readonly) NSString *summary;
@property (nonatomic, copy, readonly) NSString *goalHint;
@property (nonatomic, assign, readonly) double confidence;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;

- (instancetype)initWithActionKey:(NSString *)actionKey
                          summary:(NSString *)summary
                         goalHint:(nullable NSString *)goalHint
                       confidence:(double)confidence
                          context:(nullable NSDictionary<NSString *, id> *)context;

+ (nullable instancetype)suggestionFromDictionary:(NSDictionary<NSString *, id> *)dictionary;
- (NSDictionary<NSString *, id> *)serializedRepresentation;

@end

NS_ASSUME_NONNULL_END
