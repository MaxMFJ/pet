#import "PETShaderOverlayView.h"

@implementation PETShaderOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _activeShaders = @[];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.activeShaders.count == 0) {
        return;
    }
    NSDictionary *shader = self.activeShaders.firstObject;
    NSString *shaderName = [shader[@"shader"] isKindOfClass:NSString.class] ? shader[@"shader"] : @"shader";
    NSRect border = NSInsetRect(self.bounds, 8, 8);
    [[NSColor systemPurpleColor] setStroke];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:border xRadius:10 yRadius:10];
    path.lineWidth = 3.0;
    [path stroke];

    NSString *label = [NSString stringWithFormat:@"Shader: %@", shaderName];
    [label drawAtPoint:NSMakePoint(16, 16) withAttributes:@{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: NSColor.systemPurpleColor
    }];
}

@end
