#import <Foundation/Foundation.h>
#import <simd/simd.h>

@class PETSpineMetalView;

NS_ASSUME_NONNULL_BEGIN

@interface PETSpineLayoutHelper : NSObject

+ (NSPoint)viewPointForBoneNamed:(NSString *)boneName
                     localOffset:(vector_float2)localOffset
                  localRotation:(float)localRotationRadians
                          flipX:(BOOL)flipX
                      spineView:(PETSpineMetalView *)spineView
                    facingRight:(BOOL)facingRight;

+ (NSPoint)viewPointForPayload:(NSDictionary<NSString *, id> *)payload
                     spineView:(PETSpineMetalView *)spineView
                   facingRight:(BOOL)facingRight;

+ (NSDictionary<NSString *, id> *)payloadByApplyingViewDelta:(NSPoint)delta
                                                   toPayload:(NSDictionary<NSString *, id> *)payload
                                                   spineView:(PETSpineMetalView *)spineView
                                                 facingRight:(BOOL)facingRight
                                                   offsetKeys:(NSArray<NSString *> *)offsetKeys;

@end

NS_ASSUME_NONNULL_END
