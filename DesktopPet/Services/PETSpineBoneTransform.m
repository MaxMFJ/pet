#import "PETSpineBoneTransform.h"

@implementation PETSpineBoneTransform

- (instancetype)initWithBoneName:(NSString *)boneName
                   worldPosition:(vector_float2)worldPosition
            worldRotationRadians:(float)worldRotationRadians
                      worldScale:(vector_float2)worldScale
                          active:(BOOL)active {
    self = [super init];
    if (self) {
        _boneName = [boneName copy] ?: @"";
        _worldPosition = worldPosition;
        _worldRotationRadians = worldRotationRadians;
        _worldScale = worldScale;
        _active = active;
    }
    return self;
}

@end
