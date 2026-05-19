#import "PETSkillEditorWindowController.h"

#import "PETSkillEditorViewController.h"

@implementation PETSkillEditorWindowController

- (instancetype)initWithPetManager:(PETPetManager *)petManager {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 760)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = @"Skill Timeline Editor";
        window.minSize = NSMakeSize(960, 640);
        window.releasedWhenClosed = NO;
        window.contentViewController = [[PETSkillEditorViewController alloc] initWithPetManager:petManager];
        [window center];
    }
    return self;
}

@end
