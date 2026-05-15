#import "PETAssetImportManager.h"

#import "../Models/PETPetProfile.h"
#import "../Services/PETAnimationSourceLoader.h"
#import "PETPetManager.h"

@interface PETAssetImportManager ()

@property (nonatomic, strong) PETPetManager *petManager;
@property (nonatomic, strong) PETAnimationSourceLoader *assetLoader;

@end

@implementation PETAssetImportManager

- (instancetype)initWithPetManager:(PETPetManager *)petManager {
    self = [super init];
    if (self) {
        _petManager = petManager;
        _assetLoader = [[PETAnimationSourceLoader alloc] init];
    }
    return self;
}

- (void)importPetFromOpenPanel:(id)sender {
    (void)sender;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.resolvesAliases = YES;
    panel.title = @"Import Desktop Pet";
    panel.message = @"Choose a pet package, Spine JSON, animated image, or an image-sequence folder.";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        NSError *spawnError = nil;
        if (![self importPetAtURL:panel.URL error:&spawnError]) {
            [self presentError:spawnError];
        }
    }];
}

- (BOOL)importPetAtURL:(NSURL *)fileURL error:(NSError **)error {
    PETPetProfile *profile = [self.assetLoader loadAnimationSourceAtURL:fileURL error:error];
    if (profile == nil) {
        return NO;
    }

    return [self.petManager addPetProfile:profile error:error];
}

- (void)presentError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Unable to import pet";
    alert.informativeText = error.localizedDescription ?: @"Supported inputs: pet package, Spine JSON, animated image, or image-sequence folder.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end
