#import "PETAnimationExportViewController.h"

#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <WebKit/WebKit.h>

#import "../Models/PETAnimationFrame.h"
#import "../Models/PETPetProfile.h"
#import "../Services/PETAnimationExporter.h"
#import "../Services/PETAnimationSourceLoader.h"
#import "PETSpineMetalView.h"
#import "../Services/PETSpineRuntime.h"

@interface PETAnimationExportViewController () <WKNavigationDelegate, WKScriptMessageHandler>

@property (nonatomic, strong) PETAnimationSourceLoader *sourceLoader;
@property (nonatomic, strong) PETAnimationExporter *exporter;
@property (nonatomic, strong, nullable) PETPetProfile *profile;

@property (nonatomic, strong) NSTextField *sourceLabel;
@property (nonatomic, strong) NSPopUpButton *animationPopUpButton;
@property (nonatomic, strong) NSImageView *previewImageView;
@property (nonatomic, strong) NSView *previewContentView;
@property (nonatomic, strong) NSTextField *previewHintLabel;
@property (nonatomic, strong) WKWebView *spinePreviewWebView;
@property (nonatomic, strong, nullable) PETSpineMetalView *spineMetalPreviewView;
@property (nonatomic, strong) NSTextField *detailsLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *scaleField;
@property (nonatomic, strong) NSButton *exportPNGButton;
@property (nonatomic, strong) NSButton *exportGIFButton;
@property (nonatomic, strong) NSTextField *directionLabel;
@property (nonatomic, strong, nullable) PETSpineRuntime *spineRuntime;
@property (nonatomic, assign) CGRect previewContentRect;
@property (nonatomic, assign) BOOL previewContentRectValid;
@property (nonatomic, assign) CFTimeInterval lastSpinePreviewTimestamp;

@property (nonatomic, strong, nullable) NSTimer *playbackTimer;
@property (nonatomic, assign) NSUInteger currentFrameIndex;
@property (nonatomic, assign) BOOL spinePreviewReady;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *pendingSpinePayload;
@property (nonatomic, copy) NSString *spinePreviewDirectoryPath;

@end

@implementation PETAnimationExportViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _sourceLoader = [[PETAnimationSourceLoader alloc] init];
        _exporter = [[PETAnimationExporter alloc] init];
        _spinePreviewDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DesktopPetSpinePreview"];
    }
    return self;
}

- (void)dealloc {
    [self.playbackTimer invalidate];
    [self.spinePreviewWebView.configuration.userContentController removeScriptMessageHandlerForName:@"spineBridge"];
    self.spineRuntime = nil;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 880, 660)];
    self.view.wantsLayer = YES;
    self.view.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.spacing = 16.0;
    rootStack.edgeInsets = NSEdgeInsetsMake(20.0, 20.0, 20.0, 20.0);
    [self.view addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [rootStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [rootStack.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [rootStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [rootStack addArrangedSubview:[self labelWithString:@"Spine Animation Export Tool" font:[NSFont boldSystemFontOfSize:24.0]]];

    NSTextField *subtitleLabel = [self labelWithString:@"当前可导入宠物包、Codex 图集、WEBP/GIF、Spine runtime JSON，以及按动画分目录的 PNG 序列。"
                                                  font:[NSFont systemFontOfSize:13.0]];
    subtitleLabel.textColor = NSColor.secondaryLabelColor;
    [rootStack addArrangedSubview:subtitleLabel];

    [rootStack addArrangedSubview:[self buildSourceToolbar]];
    [rootStack addArrangedSubview:[self buildExportControls]];
    [rootStack addArrangedSubview:[self buildPreviewContainer]];

    self.detailsLabel = [self labelWithString:@"尚未载入动画资源" font:[NSFont systemFontOfSize:12.0]];
    self.detailsLabel.textColor = NSColor.secondaryLabelColor;
    [rootStack addArrangedSubview:self.detailsLabel];

    self.statusLabel = [self labelWithString:@"Raw Spine json/skel/atlas 解析接口已预留，当前先走图片资源导出链路。" font:[NSFont systemFontOfSize:12.0]];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [rootStack addArrangedSubview:self.statusLabel];

    [self refreshUI];
}

- (NSView *)buildSourceToolbar {
    NSButton *openButton = [NSButton buttonWithTitle:@"打开资源" target:self action:@selector(openSource:)];
    openButton.bezelStyle = NSBezelStyleRounded;

    NSButton *arthurButton = [NSButton buttonWithTitle:@"Arthur 测试资源" target:self action:@selector(loadArthurFixture:)];
    arthurButton.bezelStyle = NSBezelStyleRounded;

    self.sourceLabel = [self labelWithString:@"未选择资源" font:[NSFont systemFontOfSize:12.0]];
    self.sourceLabel.textColor = NSColor.secondaryLabelColor;
    self.sourceLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = 12.0;
    [stack addArrangedSubview:openButton];
    [stack addArrangedSubview:arthurButton];
    [stack addArrangedSubview:self.sourceLabel];
    [self.sourceLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.sourceLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return stack;
}

- (NSGridView *)buildExportControls {
    self.animationPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.animationPopUpButton.target = self;
    self.animationPopUpButton.action = @selector(animationSelectionChanged:);

    self.scaleField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.scaleField.stringValue = @"1.0";
    self.scaleField.placeholderString = @"1.0";

    self.exportPNGButton = [NSButton buttonWithTitle:@"导出 PNG 序列" target:self action:@selector(exportPNGSequence:)];
    self.exportPNGButton.bezelStyle = NSBezelStyleRounded;

    self.exportGIFButton = [NSButton buttonWithTitle:@"导出 GIF" target:self action:@selector(exportGIF:)];
    self.exportGIFButton.bezelStyle = NSBezelStyleRounded;

    self.directionLabel = [self labelWithString:@"方向: -"
                                           font:[NSFont systemFontOfSize:12.0]];
    self.directionLabel.textColor = NSColor.secondaryLabelColor;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self labelWithString:@"动画" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.animationPopUpButton, self.exportPNGButton],
        @[[self labelWithString:@"缩放" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.scaleField, self.exportGIFButton],
        @[[self labelWithString:@"方向" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.directionLabel, [NSView new]]
    ]];
    grid.rowSpacing = 10.0;
    grid.columnSpacing = 12.0;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    return grid;
}

- (NSView *)buildPreviewContainer {
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.boxType = NSBoxCustom;
    box.cornerRadius = 8.0;
    box.borderColor = [NSColor colorWithWhite:0.8 alpha:1.0];
    box.fillColor = [NSColor colorWithWhite:0.98 alpha:1.0];
    box.contentViewMargins = CGSizeMake(16.0, 16.0);

    self.previewImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.previewImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.previewImageView.animates = NO;
    self.previewImageView.translatesAutoresizingMaskIntoConstraints = NO;

    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    [userContentController addScriptMessageHandler:self name:@"spineBridge"];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = userContentController;

    self.spinePreviewWebView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.spinePreviewWebView.navigationDelegate = self;
    self.spinePreviewWebView.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinePreviewWebView.hidden = YES;
    if (@available(macOS 13.3, *)) {
        self.spinePreviewWebView.inspectable = YES;
    }

    self.previewHintLabel = [self labelWithString:@"预览区域" font:[NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold]];
    self.previewHintLabel.textColor = NSColor.tertiaryLabelColor;
    self.previewHintLabel.alignment = NSTextAlignmentCenter;
    self.previewHintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.previewContentView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.previewContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.previewContentView addSubview:self.previewImageView];
    [self.previewContentView addSubview:self.spinePreviewWebView];
    [self.previewContentView addSubview:self.previewHintLabel];
    box.contentView = self.previewContentView;

    [NSLayoutConstraint activateConstraints:@[
        [self.previewContentView.heightAnchor constraintGreaterThanOrEqualToConstant:360.0],
        [self.previewImageView.leadingAnchor constraintEqualToAnchor:self.previewContentView.leadingAnchor],
        [self.previewImageView.trailingAnchor constraintEqualToAnchor:self.previewContentView.trailingAnchor],
        [self.previewImageView.topAnchor constraintEqualToAnchor:self.previewContentView.topAnchor],
        [self.previewImageView.bottomAnchor constraintEqualToAnchor:self.previewContentView.bottomAnchor],
        [self.spinePreviewWebView.leadingAnchor constraintEqualToAnchor:self.previewContentView.leadingAnchor],
        [self.spinePreviewWebView.trailingAnchor constraintEqualToAnchor:self.previewContentView.trailingAnchor],
        [self.spinePreviewWebView.topAnchor constraintEqualToAnchor:self.previewContentView.topAnchor],
        [self.spinePreviewWebView.bottomAnchor constraintEqualToAnchor:self.previewContentView.bottomAnchor],
        [self.previewHintLabel.centerXAnchor constraintEqualToAnchor:self.previewContentView.centerXAnchor],
        [self.previewHintLabel.centerYAnchor constraintEqualToAnchor:self.previewContentView.centerYAnchor],
        [self.previewHintLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.previewContentView.leadingAnchor constant:24.0],
        [self.previewHintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.previewContentView.trailingAnchor constant:-24.0]
    ]];

    return box;
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (void)openSource:(id)sender {
    (void)sender;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.resolvesAliases = YES;
    panel.title = @"Open Animation Source";
    panel.message = @"Choose a pet package, Spine JSON, animated image, Codex spritesheet, or a folder containing animation image sequences.";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        NSError *error = nil;
        PETPetProfile *profile = [self.sourceLoader loadAnimationSourceAtURL:panel.URL error:&error];
        if (profile == nil) {
            [self presentError:error title:@"Unable to open source"];
            return;
        }

        [self applyLoadedProfile:profile sourcePath:panel.URL.path ?: @""];
    }];
}

- (void)loadArthurFixture:(id)sender {
    (void)sender;
    NSURL *jsonURL = [NSURL fileURLWithPath:@"/Users/lzz/Downloads/dc/Arthur.json"];
    if (![NSFileManager.defaultManager fileExistsAtPath:jsonURL.path]) {
        [self presentError:[NSError errorWithDomain:@"PETAnimationExportViewController"
                                               code:7301
                                           userInfo:@{NSLocalizedDescriptionKey: @"Arthur.json was not found at /Users/lzz/Downloads/dc/Arthur.json."}]
                     title:@"Arthur fixture missing"];
        return;
    }

    NSError *error = nil;
    PETPetProfile *profile = [self.sourceLoader loadAnimationSourceAtURL:jsonURL error:&error];
    if (profile == nil) {
        [self presentError:error title:@"Unable to load Arthur fixture"];
        return;
    }

    [self applyLoadedProfile:profile sourcePath:jsonURL.path ?: @""];
}

- (void)applyLoadedProfile:(PETPetProfile *)profile sourcePath:(NSString *)sourcePath {
    self.profile = profile;
    self.spineRuntime = nil;
    [self.spineMetalPreviewView pauseAnimation];
    [self.spineMetalPreviewView removeFromSuperview];
    self.spineMetalPreviewView = nil;
    self.previewContentRect = CGRectZero;
    self.previewContentRectValid = NO;
    self.sourceLabel.stringValue = sourcePath;
    [self reloadAnimationSelector];
    [self restartPreview];
    if (profile.supportsFrameAccuratePreview) {
        self.statusLabel.stringValue = @"资源已载入，可以切换动画并导出 PNG 序列或 GIF。";
    } else if ([self isSpineRuntimeProfile]) {
        self.statusLabel.stringValue = @"官方 spine-cpp 3.8 已接进 Metal 预览链路，正在启动原生骨骼播放器。PNG/GIF 导出下一步继续接。";
    } else {
        self.statusLabel.stringValue = @"Arthur 已作为 Spine runtime 样本接入；动画列表和方向变体已识别，但骨骼渲染/逐帧导出仍待接入完整 runtime。";
    }
    [self refreshUI];
}

- (void)animationSelectionChanged:(id)sender {
    (void)sender;
    self.previewContentRect = CGRectZero;
    self.previewContentRectValid = NO;
    if ([self isSpineRuntimeProfile]) {
        NSError *error = nil;
        if ([self ensureSpineRuntimeReady] && ![self.spineRuntime setAnimationNamed:self.selectedState loop:YES error:&error]) {
            [self presentError:error title:@"Unable to switch Spine animation"];
        }
    }
    [self restartPreview];
    [self refreshUI];
}

- (void)exportPNGSequence:(id)sender {
    (void)sender;
    if (self.profile == nil) {
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.title = @"Choose Export Directory";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        NSError *error = nil;
        BOOL success = [self.exporter exportPNGSequenceForProfile:self.profile
                                                           state:self.selectedState
                                                    directoryURL:panel.URL
                                                           scale:self.exportScale
                                                           error:&error];
        if (!success) {
            [self presentError:error title:@"PNG export failed"];
            return;
        }

        self.statusLabel.stringValue = [NSString stringWithFormat:@"PNG 序列已导出到 %@", panel.URL.path];
    }];
}

- (void)exportGIF:(id)sender {
    (void)sender;
    if (self.profile == nil) {
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Export GIF";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@-%@.gif", self.profile.displayName ?: @"animation", self.selectedState];
    UTType *gifType = [UTType typeWithFilenameExtension:@"gif"];
    panel.allowedContentTypes = gifType != nil ? @[gifType] : @[];

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        NSError *error = nil;
        BOOL success = [self.exporter exportGIFForProfile:self.profile
                                                    state:self.selectedState
                                                  fileURL:panel.URL
                                                    scale:self.exportScale
                                                loopCount:0
                                                    error:&error];
        if (!success) {
            [self presentError:error title:@"GIF export failed"];
            return;
        }

        self.statusLabel.stringValue = [NSString stringWithFormat:@"GIF 已导出到 %@", panel.URL.path];
    }];
}

- (void)reloadAnimationSelector {
    [self.animationPopUpButton removeAllItems];
    [self.animationPopUpButton addItemsWithTitles:self.profile.supportedStates ?: @[]];
    NSString *defaultState = self.profile.defaultState;
    if (defaultState.length > 0) {
        [self.animationPopUpButton selectItemWithTitle:defaultState];
    }
}

- (void)restartPreview {
    [self.playbackTimer invalidate];
    self.playbackTimer = nil;
    self.currentFrameIndex = 0;
    self.lastSpinePreviewTimestamp = 0.0;
    if (![self isSpineRuntimeProfile]) {
        [self updatePreviewContentRectIfNeeded];
    }
    if ([self isSpineRuntimeProfile]) {
        if (![self ensureSpineMetalPreviewReady]) {
            return;
        }
        [self.spineMetalPreviewView playState:self.selectedState];
        [self.spineMetalPreviewView startAnimating];
        return;
    }
    [self showCurrentFrame];
    [self scheduleNextFrame];
}

- (void)scheduleNextFrame {
    if ([self isSpineRuntimeProfile]) {
        return;
    }

    NSArray<PETAnimationFrame *> *frames = self.selectedFrames;
    if (frames.count <= 1) {
        return;
    }

    PETAnimationFrame *frame = frames[MIN(self.currentFrameIndex, frames.count - 1)];
    NSTimeInterval duration = MAX(0.02, frame.duration);
    self.playbackTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                          target:self
                                                        selector:@selector(stepPreview:)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)stepPreview:(NSTimer *)timer {
    (void)timer;
    if ([self isSpineRuntimeProfile]) {
        return;
    }

    NSArray<PETAnimationFrame *> *frames = self.selectedFrames;
    if (frames.count == 0) {
        return;
    }

    self.currentFrameIndex = (self.currentFrameIndex + 1) % frames.count;
    [self showCurrentFrame];
    [self scheduleNextFrame];
}

- (void)showCurrentFrame {
    NSArray<PETAnimationFrame *> *frames = self.selectedFrames;
    if ([self isSpineRuntimeProfile]) {
        self.previewImageView.image = nil;
        self.previewHintLabel.hidden = YES;
        return;
    }
    if (!self.profile.supportsFrameAccuratePreview) {
        self.previewImageView.image = nil;
        return;
    }
    PETPlatformImage *sourceImage = frames.count > 0 ? frames[MIN(self.currentFrameIndex, frames.count - 1)].image : nil;
    self.previewImageView.image = [self previewImageForSourceImage:sourceImage];
}

- (void)refreshUI {
    BOOL hasProfile = (self.profile != nil);
    BOOL isSpineRuntime = [self isSpineRuntimeProfile];
    self.animationPopUpButton.enabled = hasProfile;
    self.scaleField.enabled = hasProfile;
    self.previewImageView.hidden = !hasProfile || isSpineRuntime || !self.profile.supportsFrameAccuratePreview;
    self.spineMetalPreviewView.hidden = !isSpineRuntime;
    self.spinePreviewWebView.hidden = YES;
    self.exportPNGButton.enabled = hasProfile && self.profile.supportsFrameAccuratePreview && !isSpineRuntime;
    self.exportGIFButton.enabled = hasProfile && self.profile.supportsFrameAccuratePreview && !isSpineRuntime;

    if (!hasProfile) {
        self.detailsLabel.stringValue = @"尚未载入动画资源";
        self.directionLabel.stringValue = @"方向: -";
        self.previewHintLabel.hidden = NO;
        self.previewHintLabel.stringValue = @"预览区域";
        return;
    }

    NSArray<PETAnimationFrame *> *frames = self.selectedFrames;
    NSTimeInterval totalDuration = 0.0;
    for (PETAnimationFrame *frame in frames) {
        totalDuration += frame.duration;
    }

    NSString *sourceType = [self.profile.metadata[@"sourceType"] isKindOfClass:NSString.class] ? self.profile.metadata[@"sourceType"] : @"frames";
    NSString *spineVersion = [self.profile.metadata[@"spineVersion"] isKindOfClass:NSString.class] ? self.profile.metadata[@"spineVersion"] : nil;
    NSString *detailPrefix = spineVersion.length > 0 ? [NSString stringWithFormat:@"Spine %@   ", spineVersion] : @"";
    self.detailsLabel.stringValue = [NSString stringWithFormat:@"%@动画: %@   帧数: %lu   总时长: %.2fs   画布: %.0fx%.0f   类型: %@",
                                     detailPrefix,
                                     self.selectedState,
                                     (unsigned long)frames.count,
                                     totalDuration,
                                     self.profile.canvasSize.width,
                                     self.profile.canvasSize.height,
                                     sourceType];
    self.directionLabel.stringValue = [NSString stringWithFormat:@"方向: %@", [self directionDescriptionForSelectedState]];
    self.previewHintLabel.hidden = self.profile.supportsFrameAccuratePreview || isSpineRuntime;
    if (!self.profile.supportsFrameAccuratePreview && !isSpineRuntime) {
        self.previewHintLabel.stringValue = @"Arthur 资源已识别，当前只读到了动画列表和方向变体。\n真实骨骼播放还没接入，所以这里不会直接显示动画。";
    }
}

- (BOOL)ensureSpineMetalPreviewReady {
    if (![self isSpineRuntimeProfile]) {
        return NO;
    }

    if (self.spineMetalPreviewView != nil) {
        return YES;
    }

    NSError *error = nil;
    PETSpineMetalView *metalView = [[PETSpineMetalView alloc] initWithProfile:self.profile error:&error];
    if (metalView == nil) {
        self.previewHintLabel.hidden = NO;
        self.previewHintLabel.stringValue = [NSString stringWithFormat:@"Spine Metal 预览初始化失败:\n%@", error.localizedDescription ?: @"unknown error"];
        self.statusLabel.stringValue = self.previewHintLabel.stringValue;
        return NO;
    }

    metalView.translatesAutoresizingMaskIntoConstraints = NO;
    metalView.hidden = NO;
    [self.previewContentView addSubview:metalView positioned:NSWindowBelow relativeTo:self.previewHintLabel];
    [NSLayoutConstraint activateConstraints:@[
        [metalView.leadingAnchor constraintEqualToAnchor:self.previewContentView.leadingAnchor],
        [metalView.trailingAnchor constraintEqualToAnchor:self.previewContentView.trailingAnchor],
        [metalView.topAnchor constraintEqualToAnchor:self.previewContentView.topAnchor],
        [metalView.bottomAnchor constraintEqualToAnchor:self.previewContentView.bottomAnchor]
    ]];

    self.spineMetalPreviewView = metalView;
    self.previewHintLabel.hidden = YES;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Spine %@ 已载入，正在 Metal 预览 %@", self.profile.metadata[@"spineVersion"] ?: @"3.8", self.selectedState];
    return YES;
}

- (BOOL)ensureSpineRuntimeReady {
    if (![self isSpineRuntimeProfile]) {
        return NO;
    }

    if (self.spineRuntime != nil) {
        return YES;
    }

    NSString *atlasPath = [self.profile.metadata[@"atlasPath"] isKindOfClass:NSString.class] ? self.profile.metadata[@"atlasPath"] : @"";
    if (self.profile.sourceURL.path.length == 0 || atlasPath.length == 0) {
        self.previewHintLabel.hidden = NO;
        self.previewHintLabel.stringValue = @"Spine 资源路径不完整，无法初始化运行时。";
        self.statusLabel.stringValue = self.previewHintLabel.stringValue;
        return NO;
    }

    NSError *error = nil;
    self.spineRuntime = [[PETSpineRuntime alloc] initWithJSONURL:self.profile.sourceURL
                                                        atlasURL:[NSURL fileURLWithPath:atlasPath]
                                                           error:&error];
    if (self.spineRuntime == nil) {
        self.previewHintLabel.hidden = NO;
        self.previewHintLabel.stringValue = [NSString stringWithFormat:@"Spine 运行时初始化失败:\n%@", error.localizedDescription ?: @"unknown error"];
        self.statusLabel.stringValue = self.previewHintLabel.stringValue;
        return NO;
    }

    self.previewHintLabel.hidden = YES;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Spine %@ 已载入，正在原生预览 %@", self.spineRuntime.versionString ?: @"3.8", self.selectedState];
    return YES;
}

- (void)updatePreviewContentRectIfNeeded {
    self.previewContentRect = CGRectZero;
    self.previewContentRectValid = NO;

    NSArray<PETAnimationFrame *> *frames = self.selectedFrames;
    if (frames.count == 0) {
        return;
    }

    PETPlatformSize canvasSize = self.profile.canvasSize;
    CGFloat maxCanvasDimension = MAX(canvasSize.width, canvasSize.height);
    CGFloat canvasArea = canvasSize.width * canvasSize.height;
    if (maxCanvasDimension < 1800.0 && canvasArea < (1800.0 * 1800.0)) {
        return;
    }

    NSUInteger sampleCount = MIN((NSUInteger)12, frames.count);
    NSUInteger step = MAX((NSUInteger)1, frames.count / sampleCount);
    CGRect unionRect = CGRectZero;
    BOOL hasBounds = NO;

    for (NSUInteger frameIndex = 0; frameIndex < frames.count; frameIndex += step) {
        CGImageRef cgImage = [self cgImageFromPlatformImage:frames[frameIndex].image];
        if (cgImage == NULL) {
            continue;
        }

        CGRect contentRect = [self detectedContentRectForCGImage:cgImage];
        if (CGRectIsEmpty(contentRect)) {
            continue;
        }

        unionRect = hasBounds ? CGRectUnion(unionRect, contentRect) : contentRect;
        hasBounds = YES;
    }

    CGImageRef firstFrameImage = [self cgImageFromPlatformImage:frames.firstObject.image];
    if (!hasBounds || firstFrameImage == NULL) {
        return;
    }

    CGSize fullSize = CGSizeMake(CGImageGetWidth(firstFrameImage), CGImageGetHeight(firstFrameImage));
    if (fullSize.width <= 0.0 || fullSize.height <= 0.0) {
        return;
    }

    CGFloat coverage = (CGRectGetWidth(unionRect) * CGRectGetHeight(unionRect)) / MAX(1.0, fullSize.width * fullSize.height);
    if (coverage > 0.92) {
        return;
    }

    CGFloat insetX = MAX(12.0, CGRectGetWidth(unionRect) * 0.08);
    CGFloat insetY = MAX(12.0, CGRectGetHeight(unionRect) * 0.08);
    CGRect paddedRect = CGRectInset(unionRect, -insetX, -insetY);
    CGRect fullRect = CGRectMake(0.0, 0.0, fullSize.width, fullSize.height);
    self.previewContentRect = CGRectIntersection(CGRectIntegral(paddedRect), fullRect);
    self.previewContentRectValid = !CGRectIsEmpty(self.previewContentRect);
}

- (PETPlatformImage *)previewImageForSourceImage:(PETPlatformImage *)image {
    if (image == nil || !self.previewContentRectValid) {
        return image;
    }

    CGImageRef cgImage = [self cgImageFromPlatformImage:image];
    if (cgImage == NULL) {
        return image;
    }

    CGRect imageRect = CGRectMake(0.0, 0.0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    CGRect cropRect = CGRectIntersection(CGRectIntegral(self.previewContentRect), imageRect);
    if (CGRectIsEmpty(cropRect)) {
        return image;
    }

    CGImageRef croppedImage = CGImageCreateWithImageInRect(cgImage, cropRect);
    if (croppedImage == NULL) {
        return image;
    }

    NSImage *previewImage = [[NSImage alloc] initWithCGImage:croppedImage
                                                        size:NSMakeSize(CGRectGetWidth(cropRect), CGRectGetHeight(cropRect))];
    CGImageRelease(croppedImage);
    return previewImage;
}

- (CGImageRef)cgImageFromPlatformImage:(PETPlatformImage *)image {
    if (image == nil) {
        return NULL;
    }

    CGRect proposedRect = CGRectZero;
    return [image CGImageForProposedRect:&proposedRect context:nil hints:nil];
}

- (CGRect)detectedContentRectForCGImage:(CGImageRef)cgImage {
    size_t sourceWidth = CGImageGetWidth(cgImage);
    size_t sourceHeight = CGImageGetHeight(cgImage);
    if (sourceWidth == 0 || sourceHeight == 0) {
        return CGRectZero;
    }

    CGFloat maxDimension = MAX((CGFloat)sourceWidth, (CGFloat)sourceHeight);
    CGFloat sampleScale = maxDimension > 1024.0 ? (1024.0 / maxDimension) : 1.0;
    size_t scanWidth = MAX((size_t)1, (size_t)llround(sourceWidth * sampleScale));
    size_t scanHeight = MAX((size_t)1, (size_t)llround(sourceHeight * sampleScale));
    size_t bytesPerRow = scanWidth * 4;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 scanWidth,
                                                 scanHeight,
                                                 8,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        return CGRectZero;
    }

    CGContextClearRect(context, CGRectMake(0.0, 0.0, scanWidth, scanHeight));
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, scanWidth, scanHeight), cgImage);

    unsigned char *pixels = (unsigned char *)CGBitmapContextGetData(context);
    if (pixels == NULL) {
        CGContextRelease(context);
        return CGRectZero;
    }

    NSInteger minX = (NSInteger)scanWidth;
    NSInteger minY = (NSInteger)scanHeight;
    NSInteger maxX = -1;
    NSInteger maxY = -1;

    for (size_t y = 0; y < scanHeight; y += 1) {
        unsigned char *row = pixels + (y * bytesPerRow);
        for (size_t x = 0; x < scanWidth; x += 1) {
            unsigned char alpha = row[(x * 4) + 3];
            if (alpha <= 8) {
                continue;
            }

            minX = MIN(minX, (NSInteger)x);
            minY = MIN(minY, (NSInteger)y);
            maxX = MAX(maxX, (NSInteger)x);
            maxY = MAX(maxY, (NSInteger)y);
        }
    }

    CGContextRelease(context);
    if (maxX < minX || maxY < minY) {
        return CGRectZero;
    }

    CGFloat scaleX = (CGFloat)sourceWidth / (CGFloat)scanWidth;
    CGFloat scaleY = (CGFloat)sourceHeight / (CGFloat)scanHeight;
    return CGRectMake(minX * scaleX,
                      minY * scaleY,
                      (maxX - minX + 1) * scaleX,
                      (maxY - minY + 1) * scaleY);
}

- (CGFloat)livePreviewBackingScaleForSize:(CGSize)previewSize requestedScale:(CGFloat)requestedScale {
    CGFloat clampedScale = MAX(1.0, requestedScale);
    CGFloat maxPixelBudget = 1280.0 * 720.0;
    CGFloat currentPixels = previewSize.width * previewSize.height * clampedScale * clampedScale;
    if (currentPixels <= maxPixelBudget) {
        return clampedScale;
    }

    CGFloat fittedScale = sqrt(maxPixelBudget / MAX(1.0, previewSize.width * previewSize.height));
    return MAX(0.75, MIN(clampedScale, fittedScale));
}

- (NSArray<PETAnimationFrame *> *)selectedFrames {
    return self.profile != nil ? [self.profile framesForState:self.selectedState] : @[];
}

- (NSString *)selectedState {
    NSString *title = self.animationPopUpButton.selectedItem.title;
    if (title.length > 0) {
        return title;
    }
    return self.profile.defaultState ?: @"idle";
}

- (CGFloat)exportScale {
    CGFloat scale = self.scaleField.doubleValue;
    return scale > 0.0 ? scale : 1.0;
}

- (NSString *)directionDescriptionForSelectedState {
    NSArray<NSDictionary<NSString *, NSString *> *> *pairs = [self.profile.metadata[@"directionPairs"] isKindOfClass:NSArray.class] ? self.profile.metadata[@"directionPairs"] : @[];
    NSString *selected = self.selectedState;
    for (NSDictionary<NSString *, NSString *> *pair in pairs) {
        NSString *forward = pair[@"forward"];
        NSString *reverse = pair[@"reverse"];
        if ([selected isEqualToString:forward]) {
            return [NSString stringWithFormat:@"%@ -> %@", forward, reverse];
        }
        if ([selected isEqualToString:reverse]) {
            return [NSString stringWithFormat:@"%@ <- %@", forward, reverse];
        }
    }
    return @"单动画/可用 scaleX 翻转";
}

- (void)presentError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (BOOL)isSpineRuntimeProfile {
    NSString *sourceType = [self.profile.metadata[@"sourceType"] isKindOfClass:NSString.class] ? self.profile.metadata[@"sourceType"] : @"";
    return [sourceType isEqualToString:@"spine-runtime-json"];
}

- (void)loadSpinePreviewDocumentIfNeeded {
    if (self.spinePreviewReady) {
        return;
    }

    NSURL *pixiURL = [NSBundle.mainBundle URLForResource:@"pixi.min" withExtension:@"js"];
    NSURL *spineRuntimeURL = [NSBundle.mainBundle URLForResource:@"pixi-spine-3.8.umd" withExtension:@"js"];
    if (pixiURL == nil || spineRuntimeURL == nil) {
        self.previewHintLabel.hidden = NO;
        self.previewHintLabel.stringValue = @"Spine 播放器资源没有打进 app bundle，当前没法启动预览。";
        return;
    }

    NSString *html = [NSString stringWithFormat:
                      @"<!doctype html>\n"
                      "<html><head><meta charset=\"utf-8\">"
                      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                      "<style>"
                      "html,body{margin:0;width:100%%;height:100%%;overflow:hidden;background:transparent;}"
                      "#stage{width:100%%;height:100%%;background:radial-gradient(circle at top, rgba(88,106,155,0.18), rgba(0,0,0,0) 45%%),linear-gradient(180deg, rgba(249,250,252,1), rgba(241,243,246,1));}"
                      "canvas{display:block;width:100%%;height:100%%;}"
                      "</style>"
                      "<script src=\"%@\"></script>"
                      "<script src=\"%@\"></script>"
                      "</head><body><div id=\"stage\"></div><script>"
                      "const bridge=(type,payload)=>window.webkit.messageHandlers.spineBridge.postMessage(Object.assign({type:type},payload||{}));"
                      "const host=document.getElementById('stage');"
                      "const app=new PIXI.Application({resizeTo:host,backgroundAlpha:0,antialias:true,autoDensity:true});"
                      "host.appendChild(app.view);"
                      "let currentSpine=null;let currentAtlas=null;let currentPayload=null;"
                      "function destroyCurrent(){if(currentSpine){app.stage.removeChild(currentSpine);currentSpine.destroy({children:true});currentSpine=null;}if(currentAtlas&&currentAtlas.dispose){currentAtlas.dispose();}currentAtlas=null;}"
                      "function fitCurrent(){if(!currentSpine){return;}const bounds=currentSpine.getLocalBounds();const baseW=Math.max(1,bounds.width);const baseH=Math.max(1,bounds.height);const usableW=app.renderer.width*0.72;const usableH=app.renderer.height*0.78;const fit=Math.min(usableW/baseW,usableH/baseH);const scale=Math.max(0.05,fit*(currentPayload.displayScale||1));currentSpine.scale.set(scale);currentSpine.x=(app.renderer.width*0.5)-((bounds.x+bounds.width*0.5)*scale);currentSpine.y=(app.renderer.height*0.88)-((bounds.y+bounds.height)*scale);}"
                      "function playAnimation(name){if(!currentSpine){return;}const target=(name&&name.length>0)?name:currentPayload.animationName;try{const animation=currentSpine.spineData.findAnimation(target);if(!animation){throw new Error('Animation not found: '+target);}currentSpine.state.setAnimation(0,target,true);bridge('playing',{animationName:target});}catch(error){bridge('error',{message:error&&error.message?error.message:String(error)});}}"
                      "async function loadSpine(payload){currentPayload=payload;destroyCurrent();try{const skeletonData=payload.skeletonData;const atlasText=payload.atlasText;const imageTexture=PIXI.Texture.from(payload.imageDataURL||payload.imageURL);const baseTexture=imageTexture.baseTexture;const start=()=>{currentAtlas=new PIXI.spine.core.TextureAtlas(atlasText,function(_line,callback){callback(baseTexture);},function(spineAtlas){if(!spineAtlas){bridge('error',{message:'Texture atlas could not be constructed.'});return;}try{const attachmentLoader=new PIXI.spine.core.AtlasAttachmentLoader(spineAtlas);const skeletonJson=new PIXI.spine.core.SkeletonJson(attachmentLoader);const runtimeData=skeletonJson.readSkeletonData(skeletonData);currentSpine=new PIXI.spine.Spine(runtimeData);currentSpine.state.timeScale=1;app.stage.addChild(currentSpine);fitCurrent();playAnimation(payload.animationName);bridge('loaded',{animationName:payload.animationName});}catch(error){bridge('error',{message:error&&error.message?error.message:String(error)});}});};if(baseTexture.valid){start();}else{baseTexture.once('loaded',start);baseTexture.once('error',function(){bridge('error',{message:'Atlas page image failed to load.'});});}}catch(error){bridge('error',{message:error&&error.message?error.message:String(error)});}}"
                      "window.addEventListener('resize',fitCurrent);"
                      "window.codexSpineBridge={loadSpine:loadSpine,playAnimation:playAnimation};"
                      "bridge('ready',{});"
                      "</script></body></html>",
                      pixiURL.absoluteString,
                      spineRuntimeURL.absoluteString];

    [[NSFileManager defaultManager] createDirectoryAtPath:self.spinePreviewDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *htmlPath = [self.spinePreviewDirectoryPath stringByAppendingPathComponent:@"index.html"];
    NSError *writeError = nil;
    if (![html writeToFile:htmlPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        self.previewHintLabel.hidden = NO;
        self.previewHintLabel.stringValue = writeError.localizedDescription ?: @"Spine 预览页生成失败。";
        return;
    }

    NSURL *htmlURL = [NSURL fileURLWithPath:htmlPath];
    [self.spinePreviewWebView loadFileURL:htmlURL allowingReadAccessToURL:[NSURL fileURLWithPath:@"/"]];
}

- (void)pushCurrentSpineSelectionToPreview {
    if (![self isSpineRuntimeProfile]) {
        return;
    }

    NSString *atlasPath = [self.profile.metadata[@"atlasPath"] isKindOfClass:NSString.class] ? self.profile.metadata[@"atlasPath"] : @"";
    NSString *imagePath = [self.profile.metadata[@"imagePath"] isKindOfClass:NSString.class] ? self.profile.metadata[@"imagePath"] : @"";
    if (self.profile.sourceURL.path.length == 0 || atlasPath.length == 0 || imagePath.length == 0) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:self.spinePreviewDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *stagedJSONPath = [self.spinePreviewDirectoryPath stringByAppendingPathComponent:@"preview.json"];
    NSString *stagedAtlasPath = [self.spinePreviewDirectoryPath stringByAppendingPathComponent:@"preview.atlas"];
    NSString *stagedImagePath = [self.spinePreviewDirectoryPath stringByAppendingPathComponent:@"preview.png"];

    [fileManager removeItemAtPath:stagedJSONPath error:nil];
    [fileManager removeItemAtPath:stagedAtlasPath error:nil];
    [fileManager removeItemAtPath:stagedImagePath error:nil];

    NSError *copyError = nil;
    BOOL copiedJSON = [fileManager copyItemAtPath:self.profile.sourceURL.path toPath:stagedJSONPath error:&copyError];
    BOOL copiedAtlas = [fileManager copyItemAtPath:atlasPath toPath:stagedAtlasPath error:&copyError];
    BOOL copiedImage = [fileManager copyItemAtPath:imagePath toPath:stagedImagePath error:&copyError];
    if (!copiedJSON || !copiedAtlas || !copiedImage) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Spine 预览资源复制失败: %@", copyError.localizedDescription ?: @"unknown error"];
        return;
    }

    NSData *jsonData = [NSData dataWithContentsOfURL:self.profile.sourceURL];
    NSData *atlasData = [NSData dataWithContentsOfFile:atlasPath];
    NSDictionary *skeletonData = jsonData != nil ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
    NSString *atlasText = atlasData != nil ? [[NSString alloc] initWithData:atlasData encoding:NSUTF8StringEncoding] : nil;
    NSString *imageDataURL = imagePath.length > 0 ? [NSString stringWithFormat:@"data:image/png;base64,%@", [[NSData dataWithContentsOfFile:imagePath] base64EncodedStringWithOptions:0]] : nil;
    if (![skeletonData isKindOfClass:NSDictionary.class] || atlasText.length == 0 || imageDataURL.length == 0) {
        self.statusLabel.stringValue = @"Spine 骨骼数据未能解析成预览 payload。";
        return;
    }

    self.pendingSpinePayload = @{
        @"skeletonData": skeletonData,
        @"atlasText": atlasText,
        @"imageDataURL": imageDataURL,
        @"imageURL": [NSURL fileURLWithPath:stagedImagePath].absoluteString ?: @"",
        @"animationName": self.selectedState ?: self.profile.defaultState ?: @"Idle",
        @"displayScale": @(self.exportScale)
    };
    [self flushPendingSpinePayloadIfPossible];
}

- (void)flushPendingSpinePayloadIfPossible {
    if (!self.spinePreviewReady || self.pendingSpinePayload == nil) {
        return;
    }

    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:self.pendingSpinePayload options:0 error:nil];
    if (payloadData == nil) {
        return;
    }

    NSString *payloadJSON = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];
    NSString *script = [NSString stringWithFormat:@"window.codexSpineBridge.loadSpine(%@);", payloadJSON ?: @"{}"];
    [self.spinePreviewWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        if (error != nil) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Spine 预览调用失败: %@", error.localizedDescription ?: @"unknown error"];
        }
    }];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.body isKindOfClass:NSDictionary.class]) {
        return;
    }

    NSDictionary<NSString *, id> *body = (NSDictionary<NSString *, id> *)message.body;
    NSString *type = [body[@"type"] isKindOfClass:NSString.class] ? body[@"type"] : @"";
    if ([type isEqualToString:@"ready"]) {
        self.spinePreviewReady = YES;
        [self flushPendingSpinePayloadIfPossible];
        return;
    }

    if ([type isEqualToString:@"loaded"] || [type isEqualToString:@"playing"]) {
        NSString *animationName = [body[@"animationName"] isKindOfClass:NSString.class] ? body[@"animationName"] : self.selectedState;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Spine 预览正在播放 %@", animationName ?: @"动画"];
        return;
    }

    if ([type isEqualToString:@"error"]) {
        NSString *messageText = [body[@"message"] isKindOfClass:NSString.class] ? body[@"message"] : @"unknown error";
        self.previewHintLabel.hidden = NO;
        self.previewHintLabel.stringValue = [NSString stringWithFormat:@"Spine 播放失败:\n%@", messageText];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Spine 播放失败: %@", messageText];
    }
}

@end
