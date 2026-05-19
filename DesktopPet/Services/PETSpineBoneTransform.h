#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETSpineBoneTransform : NSObject

@property (nonatomic, copy, readonly) NSString *boneName;
@property (nonatomic, assign, readonly) vector_float2 worldPosition;
@property (nonatomic, assign, readonly) float worldRotationRadians;
@property (nonatomic, assign, readonly) vector_float2 worldScale;
@property (nonatomic, assign, readonly) BOOL active;

- (instancetype)initWithBoneName:(NSString *)boneName
                   worldPosition:(vector_float2)worldPosition
            worldRotationRadians:(float)worldRotationRadians
                      worldScale:(vector_float2)worldScale
                          active:(BOOL)active NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
