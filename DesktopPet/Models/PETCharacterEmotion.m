#import "PETCharacterEmotion.h"

@implementation PETCharacterEmotion

- (instancetype)initWithLabel:(NSString *)label
                      valence:(double)valence
                     arousal:(double)arousal {
    self = [super init];
    if (self) {
        _label = [label copy];
        _valence = valence;
        _arousal = arousal;
    }
    return self;
}

@end
