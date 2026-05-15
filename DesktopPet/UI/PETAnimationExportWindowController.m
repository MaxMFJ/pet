#import "PETAnimationExportWindowController.h"

#import "PETAnimationExportViewController.h"

@implementation PETAnimationExportWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 880, 660)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = @"Spine Animation Export Tool";
        window.minSize = NSMakeSize(820, 620);
        window.releasedWhenClosed = NO;
        window.contentViewController = [[PETAnimationExportViewController alloc] init];
        [window center];
    }
    return self;
}

@end
