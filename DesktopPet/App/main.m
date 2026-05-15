#import <Cocoa/Cocoa.h>

#import "PETAppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        PETAppDelegate *delegate = [[PETAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return EXIT_SUCCESS;
}
