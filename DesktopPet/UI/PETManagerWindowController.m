#import "PETManagerWindowController.h"

#import "PETManagerViewController.h"

@implementation PETManagerWindowController

- (instancetype)initWithPetManager:(PETPetManager *)petManager
                     configuration:(PETAppConfig *)configuration
                assetImportManager:(PETAssetImportManager *)assetImportManager {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 520)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = @"Desktop Pet Manager";
        window.minSize = NSMakeSize(720, 460);
        window.releasedWhenClosed = NO;
        window.contentViewController = [[PETManagerViewController alloc] initWithPetManager:petManager
                                                                               configuration:configuration
                                                                          assetImportManager:assetImportManager];
        [window center];
    }
    return self;
}

@end
