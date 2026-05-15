#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterEmotion : NSObject

@property (nonatomic, copy, readonly) NSString *label;
@property (nonatomic, assign, readonly) double valence;
@property (nonatomic, assign, readonly) double arousal;

- (instancetype)initWithLabel:(NSString *)label
                      valence:(double)valence
                     arousal:(double)arousal;

@end

NS_ASSUME_NONNULL_END
