#import "PETSkillEditorViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "../../Managers/PETPetManager.h"
#import "../../Models/PETPetProfile.h"
#import "../../UI/PETSpineMetalView.h"
#import "../Compiler/PETSkillTimelineCompiler.h"
#import "../Compiler/PETSkillTimelineJSONSerializer.h"
#import "../Compiler/PETSkillTimelineJSONValidator.h"
#import "../Model/PETSkillTimelineDocument.h"
#import "../Model/PETSkillTimelineUndoManager.h"
#import "../Preview/PETFXAssetCatalog.h"
#import "../Compiler/PETSkillEditorRuntimeBridge.h"
#import "../Preview/PETFXOverlayView.h"
#import "../Preview/PETHitboxOverlayView.h"
#import "../Preview/PETShaderOverlayView.h"
#import "../Preview/PETSkillPreviewDirector.h"
#import "../Model/PETSkillTimelineClip.h"
#import "../TimelineUI/PETTimelineView.h"
#import "PETAssetBrowserViewController.h"
#import "PETClipInspectorViewController.h"

@interface PETSkillEditorViewController () <PETAssetBrowserViewControllerDelegate, PETTimelineViewDelegate, PETClipInspectorDelegate>

@property (nonatomic, strong) PETPetManager *petManager;
@property (nonatomic, strong) PETSkillTimelineDocument *document;
@property (nonatomic, strong) PETAssetBrowserViewController *browserViewController;
@property (nonatomic, strong) PETSpineMetalView *spineView;
@property (nonatomic, strong) PETHitboxOverlayView *hitboxOverlay;
@property (nonatomic, strong) PETFXOverlayView *fxOverlay;
@property (nonatomic, strong) PETShaderOverlayView *shaderOverlay;
@property (nonatomic, strong, nullable) PETSkillTimelineClip *clipboardClip;
@property (nonatomic, strong) PETTimelineView *timelineView;
@property (nonatomic, strong) PETClipInspectorViewController *inspectorViewController;
@property (nonatomic, strong) PETSkillPreviewDirector *previewDirector;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong, nullable) PETPetProfile *loadedProfile;
@property (nonatomic, strong) PETSkillTimelineUndoManager *undoManager;
@property (nonatomic, strong, nullable) id eventMonitor;

@end

@implementation PETSkillEditorViewController

- (instancetype)initWithPetManager:(PETPetManager *)petManager {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _petManager = petManager;
        PETSkillTimelineDocument *bundled = [PETSkillTimelineJSONSerializer bundledDocumentNamed:@"slash_01"];
        _document = bundled ?: [PETSkillTimelineDocument sampleDocument];
        _undoManager = [[PETSkillTimelineUndoManager alloc] init];
    }
    return self;
}

- (void)dealloc {
    if (self.eventMonitor != nil) {
        [NSEvent removeMonitor:self.eventMonitor];
    }
}

- (void)loadView {
    NSSplitView *rootSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 760)];
    rootSplit.vertical = NO;
    rootSplit.dividerStyle = NSSplitViewDividerStyleThin;

    self.browserViewController = [[PETAssetBrowserViewController alloc] initWithPetManager:self.petManager];
    self.browserViewController.browserDelegate = self;

    NSView *previewContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 520)];
    previewContainer.wantsLayer = YES;

    NSView *placeholder = [[NSView alloc] initWithFrame:previewContainer.bounds];
    placeholder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    placeholder.wantsLayer = YES;
    placeholder.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    NSTextField *placeholderLabel = [NSTextField labelWithString:@"Select a Spine character on the left"];
    placeholderLabel.frame = NSMakeRect(40, 220, 400, 24);
    placeholderLabel.alignment = NSTextAlignmentCenter;
    [placeholder addSubview:placeholderLabel];
    [previewContainer addSubview:placeholder];

    self.fxOverlay = [[PETFXOverlayView alloc] initWithFrame:previewContainer.bounds];
    self.fxOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.shaderOverlay = [[PETShaderOverlayView alloc] initWithFrame:previewContainer.bounds];
    self.shaderOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.hitboxOverlay = [[PETHitboxOverlayView alloc] initWithFrame:previewContainer.bounds];
    self.hitboxOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [previewContainer addSubview:self.fxOverlay];
    [previewContainer addSubview:self.shaderOverlay];
    [previewContainer addSubview:self.hitboxOverlay];

    __weak typeof(self) weakSelf = self;
    self.hitboxOverlay.onPayloadDragged = ^(NSDictionary<NSString *,id> *payload) {
        [weakSelf updateSelectedClipPayload:payload];
    };
    self.fxOverlay.onPayloadDragged = ^(NSDictionary<NSString *,id> *payload, PETFXPreviewInstance *instance) {
        (void)instance;
        [weakSelf updateSelectedClipPayload:payload];
    };

    NSView *transportBar = [self buildTransportBar];
    transportBar.frame = NSMakeRect(0, 0, 900, 40);
    transportBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

    self.inspectorViewController = [[PETClipInspectorViewController alloc] init];
    self.inspectorViewController.document = self.document;
    self.inspectorViewController.inspectorDelegate = self;

    NSSplitView *contentSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 760)];
    contentSplit.vertical = NO;
    contentSplit.dividerStyle = NSSplitViewDividerStyleThin;

    NSSplitView *editorSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 760, 760)];
    editorSplit.vertical = YES;
    editorSplit.dividerStyle = NSSplitViewDividerStyleThin;

    NSView *previewStack = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 760, 520)];
    previewContainer.frame = NSMakeRect(0, 40, 900, 480);
    previewContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [previewStack addSubview:previewContainer];
    [previewStack addSubview:transportBar];

    self.timelineView = [[PETTimelineView alloc] initWithFrame:NSMakeRect(0, 0, 900, 220)];
    self.timelineView.document = self.document;
    self.timelineView.delegate = self;

    [editorSplit addSubview:previewStack];
    [editorSplit addSubview:self.timelineView];
    [editorSplit adjustSubviews];
    [editorSplit setPosition:520 ofDividerAtIndex:0];

    [contentSplit addSubview:editorSplit];
    [contentSplit addSubview:self.inspectorViewController.view];
    [contentSplit adjustSubviews];
    [contentSplit setPosition:760 ofDividerAtIndex:0];

    [rootSplit addSubview:self.browserViewController.view];
    [rootSplit addSubview:contentSplit];
    [rootSplit adjustSubviews];
    [rootSplit setPosition:260 ofDividerAtIndex:0];

    self.statusLabel = [NSTextField labelWithString:@"Ready"];
    self.statusLabel.frame = NSMakeRect(12, 4, 500, 18);
    [transportBar addSubview:self.statusLabel];

    self.view = rootSplit;

    self.previewDirector = [[PETSkillPreviewDirector alloc] init];
    self.previewDirector.document = self.document;
    self.previewDirector.hitboxOverlay = self.hitboxOverlay;
    self.previewDirector.fxOverlay = self.fxOverlay;
    self.previewDirector.shaderOverlay = self.shaderOverlay;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(documentDidChange:)
                                                 name:PETSkillTimelineDocumentDidChangeNotification
                                               object:self.document];
    [self.undoManager prepareWithDocument:self.document];

    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (weakSelf.view.window == nil || event.window != weakSelf.view.window) {
            return event;
        }
        if ((event.modifierFlags & NSEventModifierFlagCommand) == 0) {
            return event;
        }
        if ([event.charactersIgnoringModifiers isEqualToString:@"z"]) {
            if (event.modifierFlags & NSEventModifierFlagShift) {
                [weakSelf redo:nil];
            } else {
                [weakSelf undo:nil];
            }
            return nil;
        }
        return event;
    }];

    [self updateStatusLabel];
}

- (NSView *)buildTransportBar {
    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 40)];
    NSArray<NSDictionary *> *buttons = @[
        @{@"title": @"Play", @"action": NSStringFromSelector(@selector(play:))},
        @{@"title": @"Pause", @"action": NSStringFromSelector(@selector(pause:))},
        @{@"title": @"|<", @"action": NSStringFromSelector(@selector(jumpToStart:))},
        @{@"title": @"<<", @"action": NSStringFromSelector(@selector(stepBackward:))},
        @{@"title": @">>", @"action": NSStringFromSelector(@selector(stepForward:))},
        @{@"title": @"Export", @"action": NSStringFromSelector(@selector(exportTimeline:))},
        @{@"title": @"Open", @"action": NSStringFromSelector(@selector(openTimeline:))},
        @{@"title": @"+ Hitbox", @"action": NSStringFromSelector(@selector(addHitboxClip:))},
        @{@"title": @"+ FX", @"action": NSStringFromSelector(@selector(addFXClip:))},
        @{@"title": @"Test", @"action": NSStringFromSelector(@selector(testInGame:))},
        @{@"title": @"Merge", @"action": NSStringFromSelector(@selector(mergeToRuntime:))},
        @{@"title": @"Undo", @"action": NSStringFromSelector(@selector(undo:))},
        @{@"title": @"Redo", @"action": NSStringFromSelector(@selector(redo:))},
        @{@"title": @"Import FX", @"action": NSStringFromSelector(@selector(importFX:))}
    ];
    CGFloat x = 8;
    for (NSDictionary *spec in buttons) {
        NSButton *button = [NSButton buttonWithTitle:spec[@"title"] target:self action:NSSelectorFromString(spec[@"action"])];
        button.frame = NSMakeRect(x, 8, 72, 24);
        [bar addSubview:button];
        x += 78;
    }
    return bar;
}

- (void)documentDidChange:(NSNotification *)notification {
    (void)notification;
    [self.timelineView reloadData];
    [self updateStatusLabel];
}

- (void)updateStatusLabel {
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ | %.2fs / %.2fs | anim=%@",
                                    self.document.skillIdentifier,
                                    self.document.playheadTime,
                                    self.document.duration,
                                    self.document.characterAnimation ?: @"-"];
}

- (void)loadProfile:(PETPetProfile *)profile animation:(NSString *)animation {
    self.loadedProfile = profile;
    NSError *error = nil;
    PETSpineMetalView *newSpineView = [[PETSpineMetalView alloc] initWithProfile:profile error:&error];
    if (newSpineView == nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to load Spine profile";
        alert.informativeText = error.localizedDescription ?: @"Unknown error";
        [alert runModal];
        return;
    }

    NSView *container = self.hitboxOverlay.superview;
    for (NSView *subview in container.subviews.copy) {
        if (subview != self.hitboxOverlay && subview != self.fxOverlay && subview != self.shaderOverlay) {
            [subview removeFromSuperview];
        }
    }
    newSpineView.frame = container.bounds;
    newSpineView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    newSpineView.editorPlaybackEnabled = YES;
    newSpineView.paused = YES;
    [container addSubview:newSpineView positioned:NSWindowBelow relativeTo:self.fxOverlay];
    self.spineView = newSpineView;
    self.fxOverlay.spineView = newSpineView;
    self.hitboxOverlay.spineView = newSpineView;
    self.previewDirector.spineView = newSpineView;
    [self.inspectorViewController setSpineViewForBoneChoices:newSpineView profileId:profile.identifier];

    self.document.characterProfileId = profile.identifier;
    self.document.characterAnimation = animation.length > 0 ? animation : profile.defaultState;
    NSTimeInterval duration = [newSpineView durationForState:self.document.characterAnimation];
    if (duration > 0.01) {
        self.document.duration = duration;
    }

    PETSkillTimelineTrack *characterTrack = [self.document trackWithType:PETSkillTimelineTrackTypeCharacter createIfNeeded:YES];
    if (characterTrack.clips.count == 0) {
        PETSkillTimelineClip *clip = [[PETSkillTimelineClip alloc] init];
        clip.trackType = PETSkillTimelineTrackTypeCharacter;
        clip.startTime = 0.0;
        clip.endTime = self.document.duration;
        clip.payload = @{ @"animation": self.document.characterAnimation, @"loop": @NO };
        [characterTrack.clips addObject:clip];
    } else {
        PETSkillTimelineClip *clip = characterTrack.clips.firstObject;
        clip.endTime = self.document.duration;
        clip.payload = @{ @"animation": self.document.characterAnimation, @"loop": @NO };
    }

    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
    [self updateStatusLabel];
}

#pragma mark - Transport

- (void)play:(id)sender {
    (void)sender;
    [self.previewDirector start];
}

- (void)pause:(id)sender {
    (void)sender;
    [self.previewDirector stop];
}

- (void)jumpToStart:(id)sender {
    (void)sender;
    [self.previewDirector seekToTime:0.0];
    [self.timelineView reloadData];
}

- (void)stepBackward:(id)sender {
    (void)sender;
    [self.previewDirector stepFrame:-1];
    [self.timelineView reloadData];
}

- (void)stepForward:(id)sender {
    (void)sender;
    [self.previewDirector stepFrame:1];
    [self.timelineView reloadData];
}

- (void)exportTimeline:(id)sender {
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"timeline.json"]];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.timeline.json", self.document.skillIdentifier];
    NSURL *directory = [PETSkillTimelineJSONSerializer defaultExportDirectory];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    panel.directoryURL = directory;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }
        NSError *error = nil;
        if (![PETSkillTimelineJSONValidator validateDocument:self.document error:&error]) {
            [self showEditorError:error];
            return;
        }
        if (![PETSkillTimelineJSONSerializer exportDocument:self.document toURL:panel.URL error:&error]) {
            [self showEditorError:error];
            return;
        }
        NSDictionary *compiled = [PETSkillTimelineCompiler compileToSkillDictionary:self.document];
        NSURL *compiledURL = [panel.URL.URLByDeletingPathExtension URLByAppendingPathExtension:@"compiled-skill.json"];
        NSData *data = [NSJSONSerialization dataWithJSONObject:compiled options:NSJSONWritingPrettyPrinted error:&error];
        [data writeToURL:compiledURL options:NSDataWritingAtomic error:nil];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Exported %@", panel.URL.lastPathComponent];
    }];
}

- (void)openTimeline:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"timeline.json"], UTTypeJSON];
    panel.directoryURL = [PETSkillTimelineJSONSerializer defaultExportDirectory];
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }
        NSError *error = nil;
        PETSkillTimelineDocument *document = [PETSkillTimelineJSONSerializer documentFromURL:panel.URL error:&error];
        if (document == nil) {
            [self showEditorError:error];
            return;
        }
        if (![PETSkillTimelineJSONValidator validateDocument:document error:&error]) {
            [self showEditorError:error];
            return;
        }
        self.document = document;
        self.timelineView.document = document;
        self.previewDirector.document = document;
        self.inspectorViewController.document = document;
        [self.undoManager prepareWithDocument:document];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(documentDidChange:)
                                                     name:PETSkillTimelineDocumentDidChangeNotification
                                                   object:document];
        if (self.loadedProfile != nil) {
            [self loadProfile:self.loadedProfile animation:document.characterAnimation];
        } else {
            [self.previewDirector syncPreviewToPlayhead];
        }
        [self.timelineView reloadData];
        [self updateStatusLabel];
    }];
}

- (void)undo:(id)sender {
    (void)sender;
    if (![self.undoManager undo]) {
        return;
    }
    [self refreshAfterUndoRedo];
}

- (void)redo:(id)sender {
    (void)sender;
    if (![self.undoManager redo]) {
        return;
    }
    [self refreshAfterUndoRedo];
}

- (void)refreshAfterUndoRedo {
    self.timelineView.selectedClip = nil;
    [self.inspectorViewController displayClip:nil];
    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
    [self updateStatusLabel];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ | undo:%@ redo:%@",
                                    self.document.skillIdentifier,
                                    self.undoManager.canUndo ? @"yes" : @"no",
                                    self.undoManager.canRedo ? @"yes" : @"no"];
}

- (void)importFX:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select a folder containing numbered PNG frames";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }
        NSString *assetName = panel.URL.lastPathComponent;
        NSError *error = nil;
        if (![PETFXAssetCatalog.sharedCatalog importPNGSequenceFromDirectory:panel.URL assetName:assetName error:&error]) {
            [self showEditorError:error];
            return;
        }
        [self.inspectorViewController reloadBoneAndAssetChoices];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Imported FX '%@'", assetName];
    }];
}

- (void)addFXClip:(id)sender {
    (void)sender;
    [self.undoManager recordSnapshotNow];
    PETSkillTimelineTrack *track = [self.document trackWithType:PETSkillTimelineTrackTypeFX createIfNeeded:YES];
    PETSkillTimelineClip *clip = [[PETSkillTimelineClip alloc] init];
    clip.trackType = PETSkillTimelineTrackTypeFX;
    clip.startTime = self.document.playheadTime;
    clip.endTime = MIN(self.document.duration, clip.startTime + 0.35);
    clip.payload = @{
        @"asset": @"slash_fx",
        @"assetType": @"pngSequence",
        @"socket": @"root",
        @"offsetX": @0,
        @"offsetY": @0,
        @"rotation": @0,
        @"scale": @1.0,
        @"flipX": @NO,
        @"blendMode": @"additive"
    };
    [track.clips addObject:clip];
    self.timelineView.selectedClip = clip;
    [self.inspectorViewController displayClip:clip];
    [self.document notifyChanged];
    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
}

- (void)addHitboxClip:(id)sender {
    (void)sender;
    [self.undoManager recordSnapshotNow];
    PETSkillTimelineTrack *track = [self.document trackWithType:PETSkillTimelineTrackTypeHitbox createIfNeeded:YES];
    PETSkillTimelineClip *clip = [[PETSkillTimelineClip alloc] init];
    clip.trackType = PETSkillTimelineTrackTypeHitbox;
    clip.startTime = self.document.playheadTime;
    clip.endTime = MIN(self.document.duration, clip.startTime + 0.08);
    clip.payload = @{
        @"shape": @"rect",
        @"socket": @"root",
        @"x": @0,
        @"y": @0,
        @"width": @100,
        @"height": @50,
        @"damage": @100,
        @"windowId": [NSString stringWithFormat:@"hit_%@", clip.clipIdentifier],
        @"reactionId": @"hit_stun_light",
        @"collisionMode": @"pixelOverlap"
    };
    [track.clips addObject:clip];
    self.timelineView.selectedClip = clip;
    [self.inspectorViewController displayClip:clip];
    [self.document notifyChanged];
    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
}

- (void)showEditorError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Skill Timeline Editor";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    [alert runModal];
}

#pragma mark - PETAssetBrowserViewControllerDelegate

- (void)assetBrowserDidSelectProfile:(PETPetProfile *)profile {
    [self loadProfile:profile animation:self.document.characterAnimation];
}

- (void)assetBrowserDidSelectAnimation:(NSString *)animationName {
    if (self.loadedProfile == nil) {
        return;
    }
    [self loadProfile:self.loadedProfile animation:animationName];
}

- (void)assetBrowserDidSelectFXAsset:(NSString *)assetName {
    PETSkillTimelineClip *clip = self.timelineView.selectedClip;
    if (clip == nil || clip.trackType != PETSkillTimelineTrackTypeFX) {
        return;
    }
    NSMutableDictionary *payload = [clip.payload mutableCopy] ?: [NSMutableDictionary dictionary];
    payload[@"asset"] = assetName;
    clip.payload = payload.copy;
    [self.inspectorViewController displayClip:clip];
    [self.document notifyChanged];
    [self.previewDirector syncPreviewToPlayhead];
}

- (void)updateSelectedClipPayload:(NSDictionary<NSString *, id> *)payload {
    PETSkillTimelineClip *clip = self.timelineView.selectedClip;
    if (clip == nil) {
        return;
    }
    clip.payload = payload.copy;
    [self.document notifyChanged];
    [self.inspectorViewController displayClip:clip];
    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
}

- (PETSkillTimelineTrack *)trackContainingClip:(PETSkillTimelineClip *)clip {
    for (PETSkillTimelineTrack *track in self.document.tracks) {
        if ([track.clips containsObject:clip]) {
            return track;
        }
    }
    return nil;
}

- (void)testInGame:(id)sender {
    (void)sender;
    if (self.loadedProfile == nil) {
        [self showEditorError:[NSError errorWithDomain:@"PETSkillEditor" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Load a Spine character before testing in game."}]];
        return;
    }
    NSError *error = nil;
    if (![PETSkillEditorRuntimeBridge previewSkillInGameForDocument:self.document
                                                         petProfile:self.loadedProfile
                                                         petManager:self.petManager
                                                              error:&error]) {
        [self showEditorError:error];
        return;
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Testing skill '%@' in game", self.document.skillIdentifier];
}

- (void)mergeToRuntime:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (![PETSkillEditorRuntimeBridge mergeDocumentIntoSkillLibrary:self.document petManager:self.petManager error:&error]) {
        [self showEditorError:error];
        return;
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Merged '%@' into runtime skill library", self.document.skillIdentifier];
}

#pragma mark - PETTimelineViewDelegate

- (void)timelineViewDidChangePlayhead:(NSTimeInterval)time {
    (void)time;
    [self.previewDirector syncPreviewToPlayhead];
    [self updateStatusLabel];
}

- (void)timelineViewDidSelectClip:(PETSkillTimelineClip *)clip {
    [self.inspectorViewController displayClip:clip];
}

- (void)timelineViewWillBeginEditingClip:(PETSkillTimelineClip *)clip {
    (void)clip;
    [self.undoManager recordSnapshotNow];
}

- (void)timelineViewDidUpdateClip:(PETSkillTimelineClip *)clip {
    [self.inspectorViewController displayClip:clip];
    [self.previewDirector syncPreviewToPlayhead];
    [self updateStatusLabel];
}

#pragma mark - PETClipInspectorDelegate

- (void)clipInspectorDidUpdateClip:(PETSkillTimelineClip *)clip {
    (void)clip;
    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
    [self updateStatusLabel];
}

- (void)clipInspectorDidChangeClipTiming:(PETSkillTimelineClip *)clip {
    [self.undoManager recordSnapshotNow];
    [self clipInspectorDidUpdateClip:clip];
}

- (void)timelineViewDidDeleteClip:(PETSkillTimelineClip *)clip {
    [self.undoManager recordSnapshotNow];
    PETSkillTimelineTrack *track = [self trackContainingClip:clip];
    [track.clips removeObject:clip];
    [self.document notifyChanged];
    [self.inspectorViewController displayClip:nil];
    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
}

- (void)timelineViewDidRequestCopyClip:(PETSkillTimelineClip *)clip {
    self.clipboardClip = clip.copy;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Copied %@", clip.clipIdentifier];
}

- (void)timelineViewDidRequestPasteClip {
    if (self.clipboardClip == nil) {
        return;
    }
    [self.undoManager recordSnapshotNow];
    PETSkillTimelineClip *paste = self.clipboardClip.copy;
    paste.clipIdentifier = NSUUID.UUID.UUIDString;
    NSTimeInterval duration = MAX(paste.endTime - paste.startTime, 1.0 / 60.0);
    paste.startTime = self.document.playheadTime;
    paste.endTime = MIN(self.document.duration, paste.startTime + duration);
    PETSkillTimelineTrack *track = [self.document trackWithType:paste.trackType createIfNeeded:YES];
    [track.clips addObject:paste];
    self.timelineView.selectedClip = paste;
    [self.inspectorViewController displayClip:paste];
    [self.document notifyChanged];
    [self.previewDirector syncPreviewToPlayhead];
    [self.timelineView reloadData];
}

@end
