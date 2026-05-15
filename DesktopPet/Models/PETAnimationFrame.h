#import "../Config/PETPlatformCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

@interface PETAnimationFrame : NSObject

@property (nonatomic, strong, readonly) PETPlatformImage *image;
@property (nonatomic, assign, readonly) NSTimeInterval duration;

- (instancetype)initWithImage:(PETPlatformImage *)image duration:(NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END
