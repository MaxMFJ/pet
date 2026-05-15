#import "PETAnimationFrame.h"

@implementation PETAnimationFrame

- (instancetype)initWithImage:(PETPlatformImage *)image duration:(NSTimeInterval)duration {
    self = [super init];
    if (self) {
        _image = image;
        _duration = duration;
    }
    return self;
}

@end
