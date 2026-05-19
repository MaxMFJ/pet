#import "PETAppDelegate.h"

#import "../Config/PETAppConfig.h"
#import "../Managers/PETAssetImportManager.h"
#import "../Managers/PETPetManager.h"
#import "../Models/PETPetProfile.h"
#import "../Services/PETAnimationSourceLoader.h"
#import "../UI/PETAnimationExportWindowController.h"
#import "../UI/PETManagerWindowController.h"
#import "../SkillEditor/UI/PETSkillEditorWindowController.h"

@interface PETAppDelegate ()

@property (nonatomic, strong) PETAppConfig *appConfig;
@property (nonatomic, strong) PETPetManager *petManager;
@property (nonatomic, strong) PETAssetImportManager *assetImportManager;
@property (nonatomic, strong) PETManagerWindowController *managerWindowController;
@property (nonatomic, strong) PETAnimationExportWindowController *animationExportWindowController;
@property (nonatomic, strong) PETSkillEditorWindowController *skillEditorWindowController;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) PETAnimationSourceLoader *animationSourceLoader;

@end

@implementation PETAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    self.appConfig = [[PETAppConfig alloc] init];
    self.petManager = [[PETPetManager alloc] initWithConfiguration:self.appConfig];
    self.assetImportManager = [[PETAssetImportManager alloc] initWithPetManager:self.petManager];
    self.animationSourceLoader = [[PETAnimationSourceLoader alloc] init];
    self.managerWindowController = [[PETManagerWindowController alloc] initWithPetManager:self.petManager
                                                                             configuration:self.appConfig
                                                                        assetImportManager:self.assetImportManager];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(persistPetSessions)
                                                 name:PETPetManagerDidChangePetsNotification
                                               object:self.petManager];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self setupStatusMenu];
    [self restorePersistedPets];
    [self showManagerWindow:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (void)setupStatusMenu {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"Pet";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Desktop Pet"];
    [menu addItemWithTitle:@"Open Manager" action:@selector(showManagerWindow:) keyEquivalent:@"m"];
    [menu addItemWithTitle:@"Import Pet Package..." action:@selector(importPet:) keyEquivalent:@"o"];
    [menu addItemWithTitle:@"Spine Export Tool" action:@selector(showAnimationExportTool:) keyEquivalent:@"e"];
    [menu addItemWithTitle:@"Skill Timeline Editor" action:@selector(showSkillTimelineEditor:) keyEquivalent:@"t"];
    [menu addItemWithTitle:@"Hide All Pets" action:@selector(hideAllPets:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Show All Pets" action:@selector(showAllPets:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"OCR Module (Planned)" action:@selector(showComingSoon:) keyEquivalent:@""];
    [menu addItemWithTitle:@"AI Base URL (Planned)" action:@selector(showComingSoon:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Interactive Extensions (Planned)" action:@selector(showComingSoon:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

- (void)importPet:(id)sender {
    [self.assetImportManager importPetFromOpenPanel:sender];
}

- (void)showManagerWindow:(id)sender {
    (void)sender;
    [self.managerWindowController showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showAnimationExportTool:(id)sender {
    (void)sender;
    if (self.animationExportWindowController == nil) {
        self.animationExportWindowController = [[PETAnimationExportWindowController alloc] init];
    }
    [self.animationExportWindowController showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showSkillTimelineEditor:(id)sender {
    (void)sender;
    if (self.skillEditorWindowController == nil) {
        self.skillEditorWindowController = [[PETSkillEditorWindowController alloc] initWithPetManager:self.petManager];
    }
    [self.skillEditorWindowController showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)hideAllPets:(id)sender {
    (void)sender;
    [self.petManager setAllPetsHidden:YES];
}

- (void)showAllPets:(id)sender {
    (void)sender;
    [self.petManager setAllPetsHidden:NO];
}

- (void)showComingSoon:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Project scaffolding is ready";
    alert.informativeText = @"This module has an interface reserved in the architecture and can be implemented next.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self persistPetSessions];
}

- (void)persistPetSessions {
    self.appConfig.petInstanceRecords = [self.petManager serializedPetRecords];
    [self.appConfig persist];
}

- (void)restorePersistedPets {
    for (NSDictionary<NSString *, id> *record in self.appConfig.petInstanceRecords) {
        NSString *sourcePath = [record[@"sourcePath"] isKindOfClass:NSString.class] ? record[@"sourcePath"] : nil;
        if (sourcePath.length == 0) {
            continue;
        }

        NSURL *sourceURL = [NSURL fileURLWithPath:sourcePath];
        NSError *loadError = nil;
        PETPetProfile *profile = [self.animationSourceLoader loadAnimationSourceAtURL:sourceURL error:&loadError];
        if (profile == nil) {
            continue;
        }

        NSString *displayName = [record[@"displayName"] isKindOfClass:NSString.class] ? record[@"displayName"] : nil;
        if (displayName.length > 0) {
            profile.displayName = displayName;
        }

        NSDictionary<NSString *, id> *profileMetadataOverrides = [record[@"profileMetadataOverrides"] isKindOfClass:NSDictionary.class] ? record[@"profileMetadataOverrides"] : nil;
        [profileMetadataOverrides enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull value, BOOL * _Nonnull stop) {
            (void)stop;
            if ([key isKindOfClass:NSString.class]) {
                [profile setMetadataValue:value forKey:key];
            }
        }];

        NSDictionary<NSString *, NSString *> *interactionAliases = [record[@"interactionAliases"] isKindOfClass:NSDictionary.class] ? record[@"interactionAliases"] : nil;
        [interactionAliases enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull actionKey, NSString * _Nonnull animationState, BOOL * _Nonnull stop) {
            (void)stop;
            if ([actionKey isKindOfClass:NSString.class] && [animationState isKindOfClass:NSString.class]) {
                [profile setInteractionAlias:animationState forActionKey:actionKey];
            }
        }];

        NSError *addError = nil;
        if (![self.petManager addPetProfile:profile error:&addError]) {
            break;
        }

        NSDictionary<NSString *, id> *characterSnapshot = [record[@"characterSnapshot"] isKindOfClass:NSDictionary.class] ? record[@"characterSnapshot"] : nil;
        if (characterSnapshot.count > 0) {
            [self.petManager restoreCharacterSnapshot:characterSnapshot forPetProfile:profile];
        }

        NSDictionary<NSString *, id> *gameState = [record[@"gameState"] isKindOfClass:NSDictionary.class] ? record[@"gameState"] : nil;
        if (gameState.count > 0) {
            [self.petManager restoreGameState:gameState forPetProfile:profile];
        }

        NSNumber *scaleValue = [record[@"scale"] isKindOfClass:NSNumber.class] ? record[@"scale"] : nil;
        if (scaleValue != nil) {
            [self.petManager setScale:scaleValue.doubleValue forPetProfile:profile];
        }

        NSNumber *facingRightValue = [record[@"facingRight"] isKindOfClass:NSNumber.class] ? record[@"facingRight"] : nil;
        if (facingRightValue != nil) {
            [self.petManager setFacingRight:facingRightValue.boolValue forPetProfile:profile];
        }

        NSNumber *clickThroughValue = [record[@"clickThrough"] isKindOfClass:NSNumber.class] ? record[@"clickThrough"] : nil;
        if (clickThroughValue != nil) {
            [self.petManager setClickThroughEnabled:clickThroughValue.boolValue forPetProfile:profile];
        }

        NSNumber *visibleValue = [record[@"visible"] isKindOfClass:NSNumber.class] ? record[@"visible"] : nil;
        if (visibleValue != nil && !visibleValue.boolValue) {
            [self.petManager setVisibility:NO forPetProfile:profile];
        }
    }
}

@end
