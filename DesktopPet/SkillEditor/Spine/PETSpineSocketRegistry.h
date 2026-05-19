#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETSpineSocketDefinition : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *boneName;
@property (nonatomic, assign, readonly) vector_float2 localOffset;
@property (nonatomic, assign, readonly) float localRotationRadians;

@end

@interface PETSpineSocketRegistry : NSObject

+ (instancetype)sharedRegistry;

- (NSArray<NSString *> *)socketNamesForProfileId:(NSString *)profileId;
- (nullable PETSpineSocketDefinition *)socketNamed:(NSString *)socketName profileId:(NSString *)profileId;
- (void)reloadFromBundle;

@end

NS_ASSUME_NONNULL_END
