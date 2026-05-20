#import <Foundation/Foundation.h>
#import <simd/simd.h>

#import "../Config/PETPlatformCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    vector_float2 position;
    vector_float2 uv;
    vector_float4 color;
} PETSpineMetalVertex;

@interface PETSpineRenderBatch : NSObject

@property (nonatomic, strong, readonly) NSData *vertexData;
@property (nonatomic, assign, readonly) NSUInteger vertexCount;
@property (nonatomic, assign, readonly) CGImageRef textureImage;
@property (nonatomic, assign, readonly) void *textureKey;
@property (nonatomic, assign, readonly) NSInteger blendMode;

- (instancetype)initWithVertexData:(NSData *)vertexData
                       vertexCount:(NSUInteger)vertexCount
                      textureImage:(CGImageRef)textureImage
                        textureKey:(void *)textureKey
                         blendMode:(NSInteger)blendMode;

@end

@interface PETSpineHitInfo : NSObject

@property (nonatomic, copy, readonly) NSString *boneName;
@property (nonatomic, copy, readonly) NSString *slotName;
@property (nonatomic, copy, readonly) NSString *attachmentName;

- (instancetype)initWithBoneName:(NSString *)boneName
                        slotName:(NSString *)slotName
                  attachmentName:(NSString *)attachmentName;

@end

@interface PETSpineRuntime : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString *> *animationNames;
@property (nonatomic, copy, readonly) NSString *versionString;
@property (nonatomic, assign, readonly) CGSize skeletonCanvasSize;
@property (nonatomic, copy, readonly) NSString *currentAnimationName;
@property (nonatomic, assign, readonly) CGRect currentReferenceContentBounds;
@property (nonatomic, assign, readonly) CGRect stableReferenceContentBounds;

- (nullable instancetype)initWithJSONURL:(NSURL *)jsonURL
                                atlasURL:(NSURL *)atlasURL
                                   error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setAnimationNamed:(NSString *)animationName
                     loop:(BOOL)loop
                    error:(NSError * _Nullable * _Nullable)error;

- (NSTimeInterval)durationForAnimationNamed:(NSString *)animationName;

- (void)advanceTime:(NSTimeInterval)deltaTime;

- (CGRect)currentContentBounds;

- (CGRect)referenceContentBoundsForAnimationNamed:(NSString *)animationName;

- (nullable PETSpineHitInfo *)hitInfoAtContentPoint:(CGPoint)contentPoint;

- (NSArray<PETSpineRenderBatch *> *)currentRenderBatchesWithError:(NSError * _Nullable * _Nullable)error;

- (nullable PETPlatformImage *)renderPreviewImageWithSize:(CGSize)size
                                             contentScale:(CGFloat)contentScale
                                             backingScale:(CGFloat)backingScale
                                                    error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
