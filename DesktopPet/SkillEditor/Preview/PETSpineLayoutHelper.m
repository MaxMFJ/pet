#import "PETSpineLayoutHelper.h"

#import "../../Services/PETSpineRuntime.h"
#import "../../UI/PETSpineMetalView.h"

@implementation PETSpineLayoutHelper

+ (NSPoint)viewPointForBoneNamed:(NSString *)boneName
                     localOffset:(vector_float2)localOffset
                  localRotation:(float)localRotationRadians
                          flipX:(BOOL)flipX
                      spineView:(PETSpineMetalView *)spineView
                    facingRight:(BOOL)facingRight {
    PETSpineRuntime *runtime = spineView.spineRuntime;
    if (runtime == nil) {
        return NSZeroPoint;
    }
    NSString *resolvedBone = boneName.length > 0 ? boneName : @"root";
    vector_float2 world = [runtime worldPositionForBoneNamed:resolvedBone
                                                 localOffset:localOffset
                                              localRotation:localRotationRadians
                                                      flipX:!facingRight];
    CGRect contentBounds = runtime.stableReferenceContentBounds;
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = runtime.currentReferenceContentBounds;
    }
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = [runtime currentContentBounds];
    }
    CGFloat normalizedX = (world.x - CGRectGetMinX(contentBounds)) / MAX(1.0, CGRectGetWidth(contentBounds));
    CGFloat normalizedY = (world.y - CGRectGetMinY(contentBounds)) / MAX(1.0, CGRectGetHeight(contentBounds));
    NSRect layout = spineView.contentLayoutRect;
    return NSMakePoint(NSMinX(layout) + normalizedX * NSWidth(layout),
                      NSMinY(layout) + normalizedY * NSHeight(layout));
}

+ (NSPoint)viewPointForPayload:(NSDictionary<NSString *, id> *)payload
                     spineView:(PETSpineMetalView *)spineView
                   facingRight:(BOOL)facingRight {
    NSString *socket = [payload[@"socket"] isKindOfClass:NSString.class] ? payload[@"socket"] : @"root";
    vector_float2 offset = {
        [payload[@"offsetX"] respondsToSelector:@selector(floatValue)] ? [payload[@"offsetX"] floatValue] : ([payload[@"x"] respondsToSelector:@selector(floatValue)] ? [payload[@"x"] floatValue] : 0.0f),
        [payload[@"offsetY"] respondsToSelector:@selector(floatValue)] ? [payload[@"offsetY"] floatValue] : ([payload[@"y"] respondsToSelector:@selector(floatValue)] ? [payload[@"y"] floatValue] : 0.0f)
    };
    float rotation = [payload[@"rotation"] respondsToSelector:@selector(floatValue)] ? (float)([payload[@"rotation"] doubleValue] * M_PI / 180.0) : 0.0f;
    BOOL flipX = [payload[@"flipX"] boolValue];
    return [self viewPointForBoneNamed:socket localOffset:offset localRotation:rotation flipX:flipX spineView:spineView facingRight:facingRight];
}

+ (NSDictionary<NSString *,id> *)payloadByApplyingViewDelta:(NSPoint)delta
                                                   toPayload:(NSDictionary<NSString *, id> *)payload
                                                   spineView:(PETSpineMetalView *)spineView
                                                 facingRight:(BOOL)facingRight
                                                   offsetKeys:(NSArray<NSString *> *)offsetKeys {
    PETSpineRuntime *runtime = spineView.spineRuntime;
    if (runtime == nil || offsetKeys.count < 2) {
        return payload ?: @{};
    }
    CGRect contentBounds = runtime.stableReferenceContentBounds;
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = runtime.currentReferenceContentBounds;
    }
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = [runtime currentContentBounds];
    }
    NSRect layout = spineView.contentLayoutRect;
    CGFloat scaleX = CGRectGetWidth(contentBounds) / MAX(1.0, NSWidth(layout));
    CGFloat scaleY = CGRectGetHeight(contentBounds) / MAX(1.0, NSHeight(layout));
    CGFloat contentDX = delta.x * scaleX * (facingRight ? 1.0 : -1.0);
    CGFloat contentDY = delta.y * scaleY;

    NSMutableDictionary *mutable = [payload mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *xKey = offsetKeys[0];
    NSString *yKey = offsetKeys[1];
    double x = [mutable[xKey] respondsToSelector:@selector(doubleValue)] ? [mutable[xKey] doubleValue] : 0.0;
    double y = [mutable[yKey] respondsToSelector:@selector(doubleValue)] ? [mutable[yKey] doubleValue] : 0.0;
    mutable[xKey] = @(x + contentDX);
    mutable[yKey] = @(y + contentDY);
    return mutable.copy;
}

@end
