#import "PETIOSViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "../../DesktopPet/Config/PETAppConfig.h"
#import "../../DesktopPet/Models/PETCharacterSnapshot.h"
#import "../../DesktopPet/Models/PETPetProfile.h"
#import "../../DesktopPet/Models/PETStructuredCognitionSuggestion.h"
#import "../../DesktopPet/Services/PETAIService.h"
#import "../../DesktopPet/Services/PETAnimationSourceLoader.h"
#import "../../DesktopPet/Services/PETCharacterRuntimeController.h"
#import "../../DesktopPet/Services/PETPetAssetLoader.h"
#import "../../DesktopPet/Services/PETStructuredCognitionEngine.h"
#import "PETIOSAnimatedPetView.h"

#if __has_include(<SSZipArchive/SSZipArchive.h>)
#import <SSZipArchive/SSZipArchive.h>
#define PET_IOS_HAS_SSZIPARCHIVE 1
#else
#define PET_IOS_HAS_SSZIPARCHIVE 0
#endif

static NSString * const PETIOSPetListCellReuseIdentifier = @"PETIOSPetListCell";
static NSString * const PETIOSImportedPetsDirectoryName = @"ImportedPets";

static NSString * const PETIOSActionAmbientIdle = @"ambient.idle";
static NSString * const PETIOSActionTapPrimary = @"tap.primary";
static NSString * const PETIOSActionTapSecondary = @"tap.secondary";
static NSString * const PETIOSActionTapHead = @"tap.head";
static NSString * const PETIOSActionTapBody = @"tap.body";
static NSString * const PETIOSActionTapHand = @"tap.hand";
static NSString * const PETIOSActionTapTail = @"tap.tail";
static NSString * const PETIOSActionDragIdle = @"drag.idle";
static NSString * const PETIOSActionDragMoveLeft = @"drag.move.left";
static NSString * const PETIOSActionDragMoveRight = @"drag.move.right";
static NSString * const PETIOSActionDragRelease = @"drag.release";

static NSString * const PETIOSRecordSourcePathKey = @"sourcePath";
static NSString * const PETIOSRecordScaleKey = @"scale";
static NSString * const PETIOSRecordOffsetXKey = @"offsetX";
static NSString * const PETIOSRecordOffsetYKey = @"offsetY";
static NSString * const PETIOSRecordSnapshotKey = @"snapshot";
static NSString * const PETIOSRecordLastSelectedKey = @"lastSelected";
static NSString * const PETIOSRecordDefaultStateKey = @"defaultState";
static NSString * const PETIOSRecordInteractionAliasesKey = @"interactionAliases";
static NSString * const PETIOSRecordDragActivationThresholdKey = @"dragActivationThreshold";
static NSString * const PETIOSRecordFrameRateCooldownKey = @"frameRateCooldown";

static const CGFloat PETIOSDefaultDragActivationThreshold = 6.0f;
static const CGFloat PETIOSDefaultFrameRateCooldownDuration = 1.2f;

@interface PETIOSViewController () <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate, UITextFieldDelegate, PETIOSAnimatedPetViewDelegate>

@property (nonatomic, strong) PETAppConfig *appConfig;
@property (nonatomic, strong) PETPetAssetLoader *assetLoader;
@property (nonatomic, strong) PETAnimationSourceLoader *animationSourceLoader;
@property (nonatomic, strong) PETStructuredCognitionEngine *cognitionEngine;
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *petItems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *petShellRecords;

@property (nonatomic, strong) PETPetProfile *currentProfile;
@property (nonatomic, strong) NSURL *currentPackageURL;
@property (nonatomic, strong) PETCharacterRuntimeController *runtimeController;
@property (nonatomic, assign) NSInteger selectedPetIndex;
@property (nonatomic, assign) BOOL sidebarCollapsed;
@property (nonatomic, assign) NSTimeInterval lastDragRuntimeUpdateTime;
@property (nonatomic, copy) NSString *lastDragActionKey;
@property (nonatomic, copy) NSString *previewStateOverride;

@property (nonatomic, strong) UILabel *headlineLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *runtimeSummaryLabel;
@property (nonatomic, strong) UIView *stageShell;
@property (nonatomic, strong) UIView *sidebarContainer;
@property (nonatomic, strong) UIScrollView *sidebarScrollView;
@property (nonatomic, strong) UIView *sidebarContentView;
@property (nonatomic, strong) UITableView *petListView;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *sidebarToggleButton;
@property (nonatomic, strong) UIButton *stateButton;
@property (nonatomic, strong) UIButton *defaultStateButton;
@property (nonatomic, strong) UIButton *interactionMapButton;
@property (nonatomic, strong) UIButton *thinkButton;
@property (nonatomic, strong) UISlider *scaleSlider;
@property (nonatomic, strong) UILabel *scaleLabel;
@property (nonatomic, strong) UISlider *dragThresholdSlider;
@property (nonatomic, strong) UILabel *dragThresholdLabel;
@property (nonatomic, strong) UISlider *frameRateCooldownSlider;
@property (nonatomic, strong) UILabel *frameRateCooldownLabel;
@property (nonatomic, strong) UILabel *interactionHintLabel;
@property (nonatomic, strong) PETIOSAnimatedPetView *petView;

@property (nonatomic, strong) NSLayoutConstraint *petListHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarWidthConstraint;
@property (nonatomic, strong) NSTimer *ambientResumeTimer;
@property (nonatomic, strong) NSTimer *shellRecordPersistTimer;

@end

@implementation PETIOSViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.appConfig = [[PETAppConfig alloc] init];
    self.assetLoader = [[PETPetAssetLoader alloc] init];
    self.animationSourceLoader = [[PETAnimationSourceLoader alloc] init];
    self.petShellRecords = [NSMutableDictionary dictionary];
    self.selectedPetIndex = NSNotFound;

    [self loadShellRecords];
    [self configureCognitionEngine];

    self.title = @"桌宠";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(importBarButtonTapped:)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"侧边栏"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(toggleSidebar:)];

    [self buildInterface];
    [self reloadPetItemsSelectingURL:[self preferredSelectionURLFromShellRecords]];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self persistCurrentShellRecordImmediately];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (void)dealloc {
    [self.ambientResumeTimer invalidate];
    [self.shellRecordPersistTimer invalidate];
}

- (void)buildInterface {
    UIView *rootView = [[UIView alloc] initWithFrame:CGRectZero];
    rootView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:rootView];

    self.sidebarContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.sidebarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarContainer.backgroundColor = UIColor.secondarySystemBackgroundColor;

    UIView *stageContainer = [[UIView alloc] initWithFrame:CGRectZero];
    stageContainer.translatesAutoresizingMaskIntoConstraints = NO;

    [rootView addSubview:stageContainer];
    [rootView addSubview:self.sidebarContainer];

    self.sidebarWidthConstraint = [self.sidebarContainer.widthAnchor constraintEqualToConstant:340.0];
    self.sidebarWidthConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [rootView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12.0],
        [rootView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
        [rootView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [rootView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],

        [stageContainer.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
        [stageContainer.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [stageContainer.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
        [stageContainer.trailingAnchor constraintEqualToAnchor:self.sidebarContainer.leadingAnchor constant:-12.0],

        [self.sidebarContainer.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [self.sidebarContainer.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
        [self.sidebarContainer.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor]
    ]];

    self.headlineLabel = [[UILabel alloc] init];
    self.headlineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headlineLabel.hidden = YES;

    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.hidden = YES;

    self.sidebarToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarToggleButton.configuration = [UIButtonConfiguration tintedButtonConfiguration];
    self.sidebarToggleButton.configuration.title = @"隐藏侧边栏";
    [self.sidebarToggleButton addTarget:self action:@selector(toggleSidebar:) forControlEvents:UIControlEventTouchUpInside];

    self.stageShell = [[UIView alloc] initWithFrame:CGRectZero];
    self.stageShell.translatesAutoresizingMaskIntoConstraints = NO;
    self.stageShell.backgroundColor = UIColor.clearColor;
    self.stageShell.layer.cornerRadius = 0.0;
    self.stageShell.layer.borderWidth = 0.0;

    self.petView = [[PETIOSAnimatedPetView alloc] initWithFrame:CGRectZero];
    self.petView.translatesAutoresizingMaskIntoConstraints = NO;
    self.petView.delegate = self;
    [self.stageShell addSubview:self.petView];

    self.runtimeSummaryLabel = [[UILabel alloc] init];
    self.runtimeSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.runtimeSummaryLabel.hidden = YES;

    [stageContainer addSubview:self.sidebarToggleButton];
    [stageContainer addSubview:self.stageShell];

    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarToggleButton.trailingAnchor constraintEqualToAnchor:stageContainer.trailingAnchor constant:-16.0],
        [self.sidebarToggleButton.topAnchor constraintEqualToAnchor:stageContainer.topAnchor constant:12.0],

        [self.stageShell.leadingAnchor constraintEqualToAnchor:stageContainer.leadingAnchor],
        [self.stageShell.trailingAnchor constraintEqualToAnchor:stageContainer.trailingAnchor],
        [self.stageShell.topAnchor constraintEqualToAnchor:stageContainer.topAnchor],
        [self.stageShell.bottomAnchor constraintEqualToAnchor:stageContainer.bottomAnchor],

        [self.petView.leadingAnchor constraintEqualToAnchor:self.stageShell.leadingAnchor],
        [self.petView.trailingAnchor constraintEqualToAnchor:self.stageShell.trailingAnchor],
        [self.petView.topAnchor constraintEqualToAnchor:self.stageShell.topAnchor],
        [self.petView.bottomAnchor constraintEqualToAnchor:self.stageShell.bottomAnchor],
    ]];

    NSLayoutConstraint *minimumStageHeightConstraint = [self.stageShell.heightAnchor constraintGreaterThanOrEqualToConstant:360.0];
    minimumStageHeightConstraint.priority = UILayoutPriorityDefaultLow;
    minimumStageHeightConstraint.active = YES;

    self.sidebarScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.sidebarScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarScrollView.alwaysBounceVertical = YES;
    [self.sidebarContainer addSubview:self.sidebarScrollView];

    self.sidebarContentView = [[UIView alloc] initWithFrame:CGRectZero];
    self.sidebarContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebarScrollView addSubview:self.sidebarContentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarScrollView.leadingAnchor constraintEqualToAnchor:self.sidebarContainer.leadingAnchor],
        [self.sidebarScrollView.trailingAnchor constraintEqualToAnchor:self.sidebarContainer.trailingAnchor],
        [self.sidebarScrollView.topAnchor constraintEqualToAnchor:self.sidebarContainer.topAnchor],
        [self.sidebarScrollView.bottomAnchor constraintEqualToAnchor:self.sidebarContainer.bottomAnchor],

        [self.sidebarContentView.leadingAnchor constraintEqualToAnchor:self.sidebarScrollView.contentLayoutGuide.leadingAnchor constant:16.0],
        [self.sidebarContentView.trailingAnchor constraintEqualToAnchor:self.sidebarScrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
        [self.sidebarContentView.topAnchor constraintEqualToAnchor:self.sidebarScrollView.contentLayoutGuide.topAnchor constant:16.0],
        [self.sidebarContentView.bottomAnchor constraintEqualToAnchor:self.sidebarScrollView.contentLayoutGuide.bottomAnchor constant:-16.0],
        [self.sidebarContentView.widthAnchor constraintEqualToAnchor:self.sidebarScrollView.frameLayoutGuide.widthAnchor constant:-32.0]
    ]];

    UILabel *settingsTitle = [self sidebarSectionTitle:@"宠物"];
    self.importButton = [self filledButtonWithTitle:@"导入宠物"];
    [self.importButton addTarget:self action:@selector(importButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    self.petListView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.petListView.translatesAutoresizingMaskIntoConstraints = NO;
    self.petListView.dataSource = self;
    self.petListView.delegate = self;
    self.petListView.rowHeight = 58.0;
    self.petListView.scrollEnabled = NO;
    self.petListView.layer.cornerRadius = 8.0;

    UILabel *stateTitle = [self sidebarSectionTitle:@"预览动作"];
    self.stateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stateButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateButton.configuration = [UIButtonConfiguration tintedButtonConfiguration];
    self.stateButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;

    UILabel *defaultStateTitle = [self sidebarSectionTitle:@"默认动作"];
    self.defaultStateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.defaultStateButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.defaultStateButton.configuration = [UIButtonConfiguration tintedButtonConfiguration];
    self.defaultStateButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;

    UILabel *interactionTitle = [self sidebarSectionTitle:@"点击映射"];
    self.interactionMapButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.interactionMapButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.interactionMapButton.configuration = [UIButtonConfiguration tintedButtonConfiguration];
    self.interactionMapButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    self.interactionMapButton.showsMenuAsPrimaryAction = YES;

    self.interactionHintLabel = [[UILabel alloc] init];
    self.interactionHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.interactionHintLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    self.interactionHintLabel.textColor = UIColor.secondaryLabelColor;
    self.interactionHintLabel.numberOfLines = 0;

    UILabel *scaleTitle = [self sidebarSectionTitle:@"大小"];
    self.scaleLabel = [[UILabel alloc] init];
    self.scaleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.scaleLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.scaleLabel.textColor = UIColor.secondaryLabelColor;
    self.scaleLabel.textAlignment = NSTextAlignmentRight;

    self.scaleSlider = [[UISlider alloc] init];
    self.scaleSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.scaleSlider.minimumValue = 0.6f;
    self.scaleSlider.maximumValue = 2.4f;
    self.scaleSlider.value = 1.0f;
    [self.scaleSlider addTarget:self action:@selector(scaleChanged:) forControlEvents:UIControlEventValueChanged];

    UILabel *dragThresholdTitle = [self sidebarSectionTitle:@"拖拽阈值"];
    self.dragThresholdLabel = [[UILabel alloc] init];
    self.dragThresholdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dragThresholdLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.dragThresholdLabel.textColor = UIColor.secondaryLabelColor;
    self.dragThresholdLabel.textAlignment = NSTextAlignmentRight;

    self.dragThresholdSlider = [[UISlider alloc] init];
    self.dragThresholdSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.dragThresholdSlider.minimumValue = 2.0f;
    self.dragThresholdSlider.maximumValue = 24.0f;
    self.dragThresholdSlider.value = PETIOSDefaultDragActivationThreshold;
    [self.dragThresholdSlider addTarget:self action:@selector(dragThresholdChanged:) forControlEvents:UIControlEventValueChanged];

    UILabel *frameRateCooldownTitle = [self sidebarSectionTitle:@"降频等待"];
    self.frameRateCooldownLabel = [[UILabel alloc] init];
    self.frameRateCooldownLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.frameRateCooldownLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.frameRateCooldownLabel.textColor = UIColor.secondaryLabelColor;
    self.frameRateCooldownLabel.textAlignment = NSTextAlignmentRight;

    self.frameRateCooldownSlider = [[UISlider alloc] init];
    self.frameRateCooldownSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.frameRateCooldownSlider.minimumValue = 0.2f;
    self.frameRateCooldownSlider.maximumValue = 3.0f;
    self.frameRateCooldownSlider.value = PETIOSDefaultFrameRateCooldownDuration;
    [self.frameRateCooldownSlider addTarget:self action:@selector(frameRateCooldownChanged:) forControlEvents:UIControlEventValueChanged];

    [self.sidebarContentView addSubview:settingsTitle];
    [self.sidebarContentView addSubview:self.importButton];
    [self.sidebarContentView addSubview:self.petListView];
    [self.sidebarContentView addSubview:stateTitle];
    [self.sidebarContentView addSubview:self.stateButton];
    [self.sidebarContentView addSubview:defaultStateTitle];
    [self.sidebarContentView addSubview:self.defaultStateButton];
    [self.sidebarContentView addSubview:interactionTitle];
    [self.sidebarContentView addSubview:self.interactionMapButton];
    [self.sidebarContentView addSubview:self.interactionHintLabel];
    [self.sidebarContentView addSubview:scaleTitle];
    [self.sidebarContentView addSubview:self.scaleLabel];
    [self.sidebarContentView addSubview:self.scaleSlider];
    [self.sidebarContentView addSubview:dragThresholdTitle];
    [self.sidebarContentView addSubview:self.dragThresholdLabel];
    [self.sidebarContentView addSubview:self.dragThresholdSlider];
    [self.sidebarContentView addSubview:frameRateCooldownTitle];
    [self.sidebarContentView addSubview:self.frameRateCooldownLabel];
    [self.sidebarContentView addSubview:self.frameRateCooldownSlider];

    self.petListHeightConstraint = [self.petListView.heightAnchor constraintEqualToConstant:220.0];
    self.petListHeightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [settingsTitle.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [settingsTitle.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [settingsTitle.topAnchor constraintEqualToAnchor:self.sidebarContentView.topAnchor],

        [self.importButton.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.importButton.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.importButton.topAnchor constraintEqualToAnchor:settingsTitle.bottomAnchor constant:10.0],
        [self.importButton.heightAnchor constraintEqualToConstant:44.0],

        [self.petListView.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.petListView.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.petListView.topAnchor constraintEqualToAnchor:self.importButton.bottomAnchor constant:12.0],

        [stateTitle.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [stateTitle.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [stateTitle.topAnchor constraintEqualToAnchor:self.petListView.bottomAnchor constant:18.0],

        [self.stateButton.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.stateButton.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.stateButton.topAnchor constraintEqualToAnchor:stateTitle.bottomAnchor constant:8.0],
        [self.stateButton.heightAnchor constraintEqualToConstant:42.0],

        [defaultStateTitle.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [defaultStateTitle.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [defaultStateTitle.topAnchor constraintEqualToAnchor:self.stateButton.bottomAnchor constant:18.0],

        [self.defaultStateButton.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.defaultStateButton.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.defaultStateButton.topAnchor constraintEqualToAnchor:defaultStateTitle.bottomAnchor constant:8.0],
        [self.defaultStateButton.heightAnchor constraintEqualToConstant:42.0],

        [interactionTitle.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [interactionTitle.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [interactionTitle.topAnchor constraintEqualToAnchor:self.defaultStateButton.bottomAnchor constant:18.0],

        [self.interactionMapButton.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.interactionMapButton.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.interactionMapButton.topAnchor constraintEqualToAnchor:interactionTitle.bottomAnchor constant:8.0],
        [self.interactionMapButton.heightAnchor constraintEqualToConstant:42.0],

        [self.interactionHintLabel.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.interactionHintLabel.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.interactionHintLabel.topAnchor constraintEqualToAnchor:self.interactionMapButton.bottomAnchor constant:8.0],

        [scaleTitle.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [scaleTitle.topAnchor constraintEqualToAnchor:self.interactionHintLabel.bottomAnchor constant:18.0],

        [self.scaleLabel.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.scaleLabel.centerYAnchor constraintEqualToAnchor:scaleTitle.centerYAnchor],

        [self.scaleSlider.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.scaleSlider.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.scaleSlider.topAnchor constraintEqualToAnchor:scaleTitle.bottomAnchor constant:8.0],

        [dragThresholdTitle.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [dragThresholdTitle.topAnchor constraintEqualToAnchor:self.scaleSlider.bottomAnchor constant:18.0],

        [self.dragThresholdLabel.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.dragThresholdLabel.centerYAnchor constraintEqualToAnchor:dragThresholdTitle.centerYAnchor],

        [self.dragThresholdSlider.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.dragThresholdSlider.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.dragThresholdSlider.topAnchor constraintEqualToAnchor:dragThresholdTitle.bottomAnchor constant:8.0],

        [frameRateCooldownTitle.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [frameRateCooldownTitle.topAnchor constraintEqualToAnchor:self.dragThresholdSlider.bottomAnchor constant:18.0],

        [self.frameRateCooldownLabel.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.frameRateCooldownLabel.centerYAnchor constraintEqualToAnchor:frameRateCooldownTitle.centerYAnchor],

        [self.frameRateCooldownSlider.leadingAnchor constraintEqualToAnchor:self.sidebarContentView.leadingAnchor],
        [self.frameRateCooldownSlider.trailingAnchor constraintEqualToAnchor:self.sidebarContentView.trailingAnchor],
        [self.frameRateCooldownSlider.topAnchor constraintEqualToAnchor:frameRateCooldownTitle.bottomAnchor constant:8.0],
        [self.frameRateCooldownSlider.bottomAnchor constraintEqualToAnchor:self.sidebarContentView.bottomAnchor]
    ]];

    [self applyCurrentInteractionTuning];
    [self refreshStateButtonTitle];
    [self refreshDefaultStateButtonTitle];
    [self updateInteractionMappingMenu];
}

- (UIButton *)filledButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.title = title;
    button.configuration = configuration;
    return button;
}

- (UILabel *)sidebarSectionTitle:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.labelColor;
    label.text = title;
    return label;
}

- (void)refreshInteractionTuningLabels {
    self.dragThresholdLabel.text = [NSString stringWithFormat:@"%.0f pt", self.dragThresholdSlider.value];
    self.frameRateCooldownLabel.text = [NSString stringWithFormat:@"%.1f s", self.frameRateCooldownSlider.value];
}

- (void)applyCurrentInteractionTuning {
    self.petView.dragActivationThreshold = self.dragThresholdSlider.value;
    self.petView.frameRateCooldownDuration = self.frameRateCooldownSlider.value;
    [self refreshInteractionTuningLabels];
}

- (void)configureCognitionEngine {
    NSURL *baseURL = [NSURL URLWithString:self.appConfig.aiBaseURLString ?: @"https://api.openai.com/v1"];
    PETAIService *aiService = [[PETAIService alloc] initWithBaseURL:baseURL ?: [NSURL URLWithString:@"https://api.openai.com/v1"]];
    self.cognitionEngine = [[PETStructuredCognitionEngine alloc] initWithAIService:aiService];
}

- (void)loadShellRecords {
    [self.petShellRecords removeAllObjects];
    for (NSDictionary<NSString *, id> *record in self.appConfig.petInstanceRecords) {
        NSString *sourcePath = [record[PETIOSRecordSourcePathKey] isKindOfClass:NSString.class] ? record[PETIOSRecordSourcePathKey] : nil;
        if (sourcePath.length == 0) {
            continue;
        }
        self.petShellRecords[sourcePath] = [record mutableCopy];
    }
}

- (void)persistShellRecords {
    self.appConfig.petInstanceRecords = self.petShellRecords.allValues.copy;
    [self.appConfig persist];
}

- (nullable NSURL *)preferredSelectionURLFromShellRecords {
    for (NSDictionary<NSString *, id> *record in self.petShellRecords.allValues) {
        if (![record[PETIOSRecordLastSelectedKey] boolValue]) {
            continue;
        }
        NSString *sourcePath = [record[PETIOSRecordSourcePathKey] isKindOfClass:NSString.class] ? record[PETIOSRecordSourcePathKey] : nil;
        if (sourcePath.length > 0) {
            return [NSURL fileURLWithPath:sourcePath];
        }
    }
    return nil;
}

- (NSMutableDictionary<NSString *, id> *)currentShellRecordCreatingIfNeeded {
    NSString *sourcePath = self.currentPackageURL.path;
    if (sourcePath.length == 0) {
        return [NSMutableDictionary dictionary];
    }
    NSMutableDictionary<NSString *, id> *record = self.petShellRecords[sourcePath];
    if (record == nil) {
        record = [NSMutableDictionary dictionary];
        record[PETIOSRecordSourcePathKey] = sourcePath;
        self.petShellRecords[sourcePath] = record;
    }
    return record;
}

- (void)persistCurrentShellRecord {
    [self persistCurrentShellRecordImmediately];
}

- (void)schedulePersistCurrentShellRecord {
    [self.shellRecordPersistTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.shellRecordPersistTimer = [NSTimer scheduledTimerWithTimeInterval:0.35
                                                                   repeats:NO
                                                                     block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.shellRecordPersistTimer = nil;
        [strongSelf persistCurrentShellRecordImmediately];
    }];
}

- (void)persistCurrentShellRecordImmediately {
    if (self.currentProfile == nil || self.currentPackageURL.path.length == 0) {
        return;
    }

    NSMutableDictionary<NSString *, id> *record = [self currentShellRecordCreatingIfNeeded];
    record[PETIOSRecordScaleKey] = @(self.scaleSlider.value);
    record[PETIOSRecordOffsetXKey] = @(self.petView.petOffset.x);
    record[PETIOSRecordOffsetYKey] = @(self.petView.petOffset.y);
    record[PETIOSRecordSnapshotKey] = [self.runtimeController serializedSnapshot] ?: @{};
    record[PETIOSRecordLastSelectedKey] = @YES;
    record[PETIOSRecordDefaultStateKey] = self.currentProfile.defaultState ?: @"";
    record[PETIOSRecordInteractionAliasesKey] = self.currentProfile.interactionAliases ?: @{};
    record[PETIOSRecordDragActivationThresholdKey] = @(self.dragThresholdSlider.value);
    record[PETIOSRecordFrameRateCooldownKey] = @(self.frameRateCooldownSlider.value);

    for (NSString *sourcePath in self.petShellRecords.allKeys) {
        if ([sourcePath isEqualToString:self.currentPackageURL.path]) {
            continue;
        }
        self.petShellRecords[sourcePath][PETIOSRecordLastSelectedKey] = @NO;
    }

    [self persistShellRecords];
}

- (void)importBarButtonTapped:(UIBarButtonItem *)sender {
    (void)sender;
    [self importButtonTapped:self.importButton];
}

- (void)importButtonTapped:(UIButton *)sender {
    (void)sender;

    NSArray<UTType *> *allowedContentTypes = @[
        UTTypeZIP,
        UTTypeJSON,
        [UTType typeWithFilenameExtension:@"webp"] ?: UTTypeData,
        UTTypePNG,
        [UTType typeWithFilenameExtension:@"atlas"] ?: UTTypePlainText
    ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:allowedContentTypes asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)toggleSidebar:(id)sender {
    (void)sender;
    self.sidebarCollapsed = !self.sidebarCollapsed;
    self.sidebarWidthConstraint.constant = self.sidebarCollapsed ? 0.0 : 340.0;
    self.sidebarContainer.alpha = self.sidebarCollapsed ? 0.0 : 1.0;

    UIButtonConfiguration *configuration = self.sidebarToggleButton.configuration ?: [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = self.sidebarCollapsed ? @"显示侧边栏" : @"隐藏侧边栏";
    self.sidebarToggleButton.configuration = configuration;
    self.navigationItem.leftBarButtonItem.title = @"侧边栏";

    [UIView animateWithDuration:0.25 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)scaleChanged:(UISlider *)sender {
    self.previewStateOverride = nil;
    [self.petView setPetScale:sender.value];
    self.scaleLabel.text = [NSString stringWithFormat:@"%.2fx", sender.value];
    [self schedulePersistCurrentShellRecord];
}

- (void)dragThresholdChanged:(UISlider *)sender {
    self.petView.dragActivationThreshold = sender.value;
    [self refreshInteractionTuningLabels];
    [self schedulePersistCurrentShellRecord];
}

- (void)frameRateCooldownChanged:(UISlider *)sender {
    self.petView.frameRateCooldownDuration = sender.value;
    [self refreshInteractionTuningLabels];
    [self schedulePersistCurrentShellRecord];
}

- (void)triggerPrimaryTap:(id)sender {
    (void)sender;
    self.previewStateOverride = nil;
    [self runRuntimeActionKey:PETIOSActionTapPrimary
        fallbackBehaviorState:@"waving"
                      context:@{@"runtimeMode": @"ios.touch", @"platform": @"ios"}];
    [self scheduleAmbientResumeAfterDuration:0.95];
}

- (void)triggerSecondaryTap:(id)sender {
    (void)sender;
    self.previewStateOverride = nil;
    [self runRuntimeActionKey:PETIOSActionTapSecondary
        fallbackBehaviorState:@"review"
                      context:@{@"runtimeMode": @"ios.touch", @"platform": @"ios"}];
    [self scheduleAmbientResumeAfterDuration:1.1];
}

- (void)triggerAmbient:(id)sender {
    (void)sender;
    self.previewStateOverride = nil;
    [self.ambientResumeTimer invalidate];
    [self.runtimeController resumeAmbientBehavior];
    [self applyCurrentRuntimeVisualStateAnimated:YES];
}

- (void)triggerStructuredCognition:(id)sender {
    (void)sender;
    if (self.currentProfile == nil || self.runtimeController == nil) {
        return;
    }
    if (!self.appConfig.cognitionEnabled) {
        [self presentNoticeWithTitle:@"认知未开启" message:@"请先在侧边栏里开启结构化认知。"];
        return;
    }

    self.previewStateOverride = nil;
    self.thinkButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [self.cognitionEngine requestSuggestionForSnapshot:self.runtimeController.currentSnapshot completion:^(PETStructuredCognitionSuggestion *suggestion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.thinkButton.enabled = YES;
            if (suggestion != nil) {
                [strongSelf.runtimeController applyStructuredCognitionSuggestion:suggestion];
                [strongSelf applyCurrentRuntimeVisualStateAnimated:YES];
                [strongSelf scheduleAmbientResumeAfterDuration:0.8];
                return;
            }
            [strongSelf presentNoticeWithTitle:@"认知暂不可用"
                                       message:(error.localizedDescription ?: @"结构化认知服务暂时不可用。")];
        });
    }];
}

- (void)runRuntimeActionKey:(NSString *)actionKey
      fallbackBehaviorState:(NSString *)fallbackBehaviorState
                    context:(NSDictionary<NSString *, id> *)context {
    if (self.currentProfile == nil || self.runtimeController == nil) {
        return;
    }
    self.previewStateOverride = nil;
    NSString *resolvedAnimationState = [self resolvedAnimationStateForActionKey:actionKey fallbackBehaviorState:fallbackBehaviorState];
    NSMutableDictionary<NSString *, id> *mergedContext = [NSMutableDictionary dictionaryWithDictionary:context ?: @{}];
    mergedContext[@"platform"] = @"ios";
    mergedContext[@"viewport"] = @"landscape-shell";
    mergedContext[@"petScale"] = @(self.scaleSlider.value);
    mergedContext[@"petOffsetX"] = @(self.petView.petOffset.x);
    mergedContext[@"petOffsetY"] = @(self.petView.petOffset.y);
    [self.runtimeController recordActionKey:actionKey
                      fallbackBehaviorState:fallbackBehaviorState
                     resolvedAnimationState:resolvedAnimationState
                                    context:mergedContext.copy];
    [self applyCurrentRuntimeVisualStateAnimated:NO];
}

- (void)scheduleAmbientResumeAfterDuration:(NSTimeInterval)duration {
    [self.ambientResumeTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.ambientResumeTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(duration, 0.25)
                                                              repeats:NO
                                                                block:^(NSTimer *timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.ambientResumeTimer = nil;
        strongSelf.previewStateOverride = nil;
        [strongSelf.runtimeController resumeAmbientBehavior];
        [strongSelf applyCurrentRuntimeVisualStateAnimated:YES];
    }];
}

- (void)loadPetAtIndex:(NSInteger)index preferredState:(NSString *)preferredState {
    if (index < 0 || index >= (NSInteger)self.petItems.count) {
        return;
    }

    [self persistCurrentShellRecordImmediately];

    NSDictionary<NSString *, id> *item = self.petItems[(NSUInteger)index];
    NSURL *packageURL = item[@"url"];
    if (packageURL == nil) {
        [self presentMissingBundleStateForPackage:@"Unknown Package"];
        return;
    }

    NSError *error = nil;
    PETPetProfile *profile = [self.animationSourceLoader loadAnimationSourceAtURL:packageURL error:&error];
    if (profile == nil) {
        self.detailLabel.text = error.localizedDescription ?: @"宠物资源加载失败。";
        [self.petView displayProfile:nil preferredState:nil];
        self.runtimeSummaryLabel.text = @"";
        return;
    }

    self.selectedPetIndex = index;
    self.currentProfile = profile;
    self.currentPackageURL = packageURL;
    self.previewStateOverride = nil;

    NSDictionary<NSString *, id> *record = self.petShellRecords[packageURL.path];

    NSDictionary<NSString *, NSString *> *storedAliases = [record[PETIOSRecordInteractionAliasesKey] isKindOfClass:NSDictionary.class] ? record[PETIOSRecordInteractionAliasesKey] : nil;
    [storedAliases enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull actionKey, NSString * _Nonnull animationState, BOOL * _Nonnull stop) {
        (void)stop;
        if ([actionKey isKindOfClass:NSString.class] && [animationState isKindOfClass:NSString.class]) {
            [profile setInteractionAlias:animationState forActionKey:actionKey];
        }
    }];
    NSString *storedDefaultState = [record[PETIOSRecordDefaultStateKey] isKindOfClass:NSString.class] ? record[PETIOSRecordDefaultStateKey] : nil;
    if (storedDefaultState.length > 0) {
        [profile setDefaultAnimationState:storedDefaultState];
    }

    self.runtimeController = [[PETCharacterRuntimeController alloc] initWithProfile:profile];

    NSDictionary<NSString *, id> *snapshot = [record[PETIOSRecordSnapshotKey] isKindOfClass:NSDictionary.class] ? record[PETIOSRecordSnapshotKey] : nil;
    if (snapshot.count > 0) {
        [self.runtimeController restoreFromSerializedSnapshot:snapshot];
    }

    CGFloat defaultScale = profile.usesSpineRuntime ? 1.55 : 1.0;
    CGFloat scale = [record[PETIOSRecordScaleKey] respondsToSelector:@selector(doubleValue)] ? [record[PETIOSRecordScaleKey] doubleValue] : defaultScale;
    CGPoint offset = CGPointZero;
    if ([record[PETIOSRecordOffsetXKey] respondsToSelector:@selector(doubleValue)] && [record[PETIOSRecordOffsetYKey] respondsToSelector:@selector(doubleValue)]) {
        offset = CGPointMake([record[PETIOSRecordOffsetXKey] doubleValue], [record[PETIOSRecordOffsetYKey] doubleValue]);
    }

    self.scaleSlider.value = MIN(MAX(scale, self.scaleSlider.minimumValue), self.scaleSlider.maximumValue);
    [self.petView setPetScale:self.scaleSlider.value];
    [self.petView setPetOffset:offset animated:NO];

    CGFloat dragThreshold = [record[PETIOSRecordDragActivationThresholdKey] respondsToSelector:@selector(doubleValue)] ? [record[PETIOSRecordDragActivationThresholdKey] doubleValue] : PETIOSDefaultDragActivationThreshold;
    NSTimeInterval frameRateCooldown = [record[PETIOSRecordFrameRateCooldownKey] respondsToSelector:@selector(doubleValue)] ? [record[PETIOSRecordFrameRateCooldownKey] doubleValue] : PETIOSDefaultFrameRateCooldownDuration;
    self.dragThresholdSlider.value = MIN(MAX(dragThreshold, self.dragThresholdSlider.minimumValue), self.dragThresholdSlider.maximumValue);
    self.frameRateCooldownSlider.value = MIN(MAX(frameRateCooldown, self.frameRateCooldownSlider.minimumValue), self.frameRateCooldownSlider.maximumValue);
    [self applyCurrentInteractionTuning];

    NSString *resolvedState = preferredState.length > 0 ? preferredState : self.runtimeController.currentSnapshot.animationState;
    if (resolvedState.length == 0) {
        resolvedState = profile.defaultState;
    }

    [self.petView displayProfile:profile preferredState:resolvedState];
    [self refreshDetailLabelWithItem:item];
    [self.petListView reloadData];
    [self updateStateMenu];
    [self updateInteractionMappingMenu];
    [self applyCurrentRuntimeVisualStateAnimated:NO];
}

- (void)refreshDetailLabelWithItem:(NSDictionary<NSString *, id> *)item {
    (void)item;
    self.detailLabel.text = @"";
}

- (void)applyCurrentRuntimeVisualStateAnimated:(BOOL)animated {
    if (self.currentProfile == nil || self.runtimeController == nil) {
        self.runtimeSummaryLabel.text = @"";
        return;
    }

    NSString *animationState = self.previewStateOverride.length > 0
        ? self.previewStateOverride
        : (self.runtimeController.currentSnapshot.animationState.length > 0
        ? self.runtimeController.currentSnapshot.animationState
        : self.currentProfile.defaultState);
    [self.petView displayProfile:self.currentProfile preferredState:animationState];
    [self.petView setPetScale:self.scaleSlider.value];
    [self.petView setPetOffset:[self clampedOffset:self.petView.petOffset] animated:animated];
    self.scaleLabel.text = [NSString stringWithFormat:@"%.2fx", self.scaleSlider.value];
    self.runtimeSummaryLabel.text = @"";
    [self refreshStateButtonTitle];
    [self schedulePersistCurrentShellRecord];
}

- (void)updateStateMenu {
    if (self.currentProfile == nil) {
        return;
    }

    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray arrayWithCapacity:self.currentProfile.supportedStates.count];
    for (NSString *state in self.currentProfile.supportedStates) {
        UIAction *action = [UIAction actionWithTitle:[self titleForState:state]
                                               image:nil
                                          identifier:nil
                                             handler:^(__kindof UIAction *menuAction) {
            (void)menuAction;
            self.previewStateOverride = state;
            [self applyCurrentRuntimeVisualStateAnimated:NO];
        }];
        [actions addObject:action];
    }

    self.stateButton.menu = [UIMenu menuWithTitle:@"预览动作" children:actions];
    self.stateButton.showsMenuAsPrimaryAction = YES;
    [self refreshStateButtonTitle];
    [self updateDefaultStateMenu];
    [self updateInteractionMappingMenu];
}

- (void)refreshStateButtonTitle {
    NSString *state = self.previewStateOverride.length > 0 ? self.previewStateOverride : (self.petView.currentState ?: self.currentProfile.defaultState ?: @"idle");
    UIButtonConfiguration *configuration = self.stateButton.configuration ?: [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = [NSString stringWithFormat:@"当前预览：%@", [self titleForState:state]];
    self.stateButton.configuration = configuration;
}

- (void)updateDefaultStateMenu {
    if (self.currentProfile == nil) {
        return;
    }

    NSMutableArray<UIAction *> *actions = [NSMutableArray arrayWithCapacity:self.currentProfile.supportedStates.count];
    for (NSString *state in self.currentProfile.supportedStates) {
        UIMenuElementState actionState = [state isEqualToString:self.currentProfile.defaultState] ? UIMenuElementStateOn : UIMenuElementStateOff;
        __weak typeof(self) weakSelf = self;
        [actions addObject:[UIAction actionWithTitle:[self titleForState:state]
                                               image:nil
                                          identifier:nil
                                             handler:^(__kindof UIAction *menuAction) {
            (void)menuAction;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf.currentProfile setDefaultAnimationState:state];
            [strongSelf.runtimeController resumeAmbientBehavior];
            [strongSelf updateDefaultStateMenu];
            [strongSelf applyCurrentRuntimeVisualStateAnimated:NO];
        }]];
        actions.lastObject.state = actionState;
    }

    self.defaultStateButton.menu = [UIMenu menuWithTitle:@"默认动作" children:actions];
    self.defaultStateButton.showsMenuAsPrimaryAction = YES;
    [self refreshDefaultStateButtonTitle];
}

- (void)refreshDefaultStateButtonTitle {
    UIButtonConfiguration *configuration = self.defaultStateButton.configuration ?: [UIButtonConfiguration tintedButtonConfiguration];
    NSString *defaultState = self.currentProfile.defaultState ?: @"idle";
    configuration.title = [NSString stringWithFormat:@"默认：%@", [self titleForState:defaultState]];
    self.defaultStateButton.configuration = configuration;
}

- (NSArray<NSString *> *)editableInteractionActionKeys {
    return @[
        PETIOSActionTapHead,
        PETIOSActionTapBody,
        PETIOSActionTapHand,
        PETIOSActionTapTail,
        PETIOSActionTapPrimary,
        PETIOSActionTapSecondary,
        PETIOSActionDragMoveLeft,
        PETIOSActionDragMoveRight,
        PETIOSActionDragRelease,
        PETIOSActionAmbientIdle
    ];
}

- (NSString *)titleForActionKey:(NSString *)actionKey {
    NSDictionary<NSString *, NSString *> *titles = @{
        PETIOSActionTapHead: @"点头部",
        PETIOSActionTapBody: @"点身体",
        PETIOSActionTapHand: @"点手部",
        PETIOSActionTapTail: @"点尾巴",
        PETIOSActionTapPrimary: @"主点击",
        PETIOSActionTapSecondary: @"副点击",
        PETIOSActionDragMoveLeft: @"拖向左侧",
        PETIOSActionDragMoveRight: @"拖向右侧",
        PETIOSActionDragRelease: @"拖拽结束",
        PETIOSActionAmbientIdle: @"待机"
    };
    return titles[actionKey] ?: actionKey;
}

- (void)updateInteractionMappingMenu {
    if (self.currentProfile == nil) {
        return;
    }

    NSMutableArray<UIMenuElement *> *actionMenus = [NSMutableArray array];
    for (NSString *actionKey in [self editableInteractionActionKeys]) {
        NSMutableArray<UIAction *> *stateActions = [NSMutableArray array];
        NSString *currentAlias = [self.currentProfile userInteractionAnimationStateForActionKey:actionKey];
        NSString *baseAlias = [self.currentProfile baseInteractionAnimationStateForActionKey:actionKey];
        NSString *resolvedAlias = currentAlias ?: baseAlias ?: self.currentProfile.defaultState;

        __weak typeof(self) weakSelf = self;
        UIAction *useDefaultAction = [UIAction actionWithTitle:@"跟随默认动作"
                                                         image:nil
                                                    identifier:nil
                                                       handler:^(__kindof UIAction *menuAction) {
            (void)menuAction;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf.currentProfile setInteractionAlias:nil forActionKey:actionKey];
            [strongSelf updateInteractionMappingMenu];
            [strongSelf schedulePersistCurrentShellRecord];
        }];
        useDefaultAction.state = currentAlias.length == 0 ? UIMenuElementStateOn : UIMenuElementStateOff;
        [stateActions addObject:useDefaultAction];

        for (NSString *state in self.currentProfile.supportedStates) {
            UIAction *stateAction = [UIAction actionWithTitle:[self titleForState:state]
                                                        image:nil
                                                   identifier:nil
                                                      handler:^(__kindof UIAction *menuAction) {
                (void)menuAction;
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf.currentProfile setInteractionAlias:state forActionKey:actionKey];
                [strongSelf updateInteractionMappingMenu];
                [strongSelf schedulePersistCurrentShellRecord];
            }];
            stateAction.state = [currentAlias isEqualToString:state] ? UIMenuElementStateOn : UIMenuElementStateOff;
            [stateActions addObject:stateAction];
        }

        NSString *subtitle = [NSString stringWithFormat:@"%@ -> %@", [self titleForActionKey:actionKey], [self titleForState:resolvedAlias]];
        [actionMenus addObject:[UIMenu menuWithTitle:subtitle children:stateActions]];
    }

    self.interactionMapButton.menu = [UIMenu menuWithTitle:@"点击映射" children:actionMenus];
    UIButtonConfiguration *configuration = self.interactionMapButton.configuration ?: [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = @"编辑点击映射";
    self.interactionMapButton.configuration = configuration;

    NSMutableArray<NSString *> *summaryLines = [NSMutableArray array];
    for (NSString *actionKey in @[PETIOSActionTapHead, PETIOSActionTapBody, PETIOSActionTapHand, PETIOSActionTapTail]) {
        NSString *resolvedAlias = [self.currentProfile resolvedInteractionAnimationStateForActionKey:actionKey] ?: self.currentProfile.defaultState;
        [summaryLines addObject:[NSString stringWithFormat:@"%@: %@", [self titleForActionKey:actionKey], [self titleForState:resolvedAlias]]];
    }
    self.interactionHintLabel.text = [summaryLines componentsJoinedByString:@"\n"];
}

- (NSString *)titleForState:(NSString *)state {
    NSDictionary<NSString *, NSString *> *titles = @{
        @"idle": @"Idle",
        @"waving": @"Waving",
        @"waiting": @"Waiting",
        @"review": @"Review",
        @"jumping": @"Jumping",
        @"failed": @"Failed",
        @"running": @"Running",
        @"running-left": @"Run Left",
        @"running-right": @"Run Right",
        @"social": @"Social"
    };
    return titles[state] ?: state.capitalizedString;
}

- (NSArray<NSString *> *)candidateActionKeysForActionKey:(NSString *)actionKey {
    if (actionKey.length == 0) {
        return @[];
    }
    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithObject:actionKey];
    if ([actionKey isEqualToString:PETIOSActionTapHead]) {
        [candidates addObject:PETIOSActionTapPrimary];
    } else if ([actionKey isEqualToString:PETIOSActionTapBody]) {
        [candidates addObject:PETIOSActionTapPrimary];
    } else if ([actionKey isEqualToString:PETIOSActionTapHand] || [actionKey isEqualToString:PETIOSActionTapTail]) {
        [candidates addObject:PETIOSActionTapPrimary];
    }
    return [NSOrderedSet orderedSetWithArray:candidates].array;
}

- (NSString *)actionKeyForInteractivePartIdentifier:(NSString *)partIdentifier fallbackPoint:(CGPoint)point {
    NSString *normalized = partIdentifier.lowercaseString;
    NSArray<NSString *> *headKeywords = @[@"head", @"face", @"eye", @"yan", @"mouth", @"ear", @"hair"];
    NSArray<NSString *> *handKeywords = @[@"hand", @"arm", @"paw", @"finger", @"sleeve"];
    NSArray<NSString *> *tailKeywords = @[@"tail"];

    for (NSString *keyword in headKeywords) {
        if ([normalized containsString:keyword]) {
            return PETIOSActionTapHead;
        }
    }
    for (NSString *keyword in handKeywords) {
        if ([normalized containsString:keyword]) {
            return PETIOSActionTapHand;
        }
    }
    for (NSString *keyword in tailKeywords) {
        if ([normalized containsString:keyword]) {
            return PETIOSActionTapTail;
        }
    }

    CGFloat normalizedY = CGRectGetHeight(self.stageShell.bounds) > 0.0 ? point.y / CGRectGetHeight(self.stageShell.bounds) : 0.5;
    return normalizedY < 0.42 ? PETIOSActionTapHead : PETIOSActionTapBody;
}

- (NSString *)resolvedAnimationStateForActionKey:(NSString *)actionKey fallbackBehaviorState:(NSString *)fallbackBehaviorState {
    for (NSString *candidate in [self candidateActionKeysForActionKey:actionKey]) {
        NSString *userAlias = [self.currentProfile userInteractionAnimationStateForActionKey:candidate];
        if (userAlias.length > 0) {
            return userAlias;
        }
    }
    for (NSString *candidate in [self candidateActionKeysForActionKey:actionKey]) {
        NSString *baseAlias = [self.currentProfile baseInteractionAnimationStateForActionKey:candidate];
        if (baseAlias.length > 0) {
            return baseAlias;
        }
    }
    if ([self.currentProfile.supportedStates containsObject:actionKey]) {
        return actionKey;
    }
    NSString *behaviorState = [self.currentProfile resolvedAnimationStateForBehaviorState:fallbackBehaviorState];
    if (behaviorState.length > 0) {
        return behaviorState;
    }
    return self.currentProfile.defaultState;
}

- (CGPoint)clampedOffset:(CGPoint)offset {
    CGFloat horizontalLimit = MAX(CGRectGetWidth(self.stageShell.bounds) * 0.28, 80.0);
    CGFloat verticalLimit = MAX(CGRectGetHeight(self.stageShell.bounds) * 0.22, 60.0);
    return CGPointMake(MIN(MAX(offset.x, -horizontalLimit), horizontalLimit),
                       MIN(MAX(offset.y, -verticalLimit), verticalLimit));
}

- (NSString *)prettyJSONStringFromObject:(id)object {
    if (object == nil) {
        return @"{}";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    if (data == nil) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

- (void)presentNoticeWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reloadPetItemsSelectingURL:(NSURL *)preferredURL {
    NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray array];

    NSURL *bundledManifestURL = [NSBundle.mainBundle URLForResource:@"pet" withExtension:@"json"];
    if (bundledManifestURL != nil) {
        [items addObject:@{
            @"title": @"Bundled Shell Pet",
            @"url": bundledManifestURL,
            @"source": @"Bundled"
        }];
    }

    NSArray<NSURL *> *importedURLs = [self importedPetPackageURLs];
    for (NSURL *url in importedURLs) {
        [items addObject:@{
            @"title": url.URLByDeletingLastPathComponent.lastPathComponent ?: url.lastPathComponent ?: @"Imported Pet",
            @"url": url,
            @"source": @"Imported"
        }];
    }

    self.petItems = items.copy;
    CGFloat desiredHeight = MIN(MAX((CGFloat)self.petItems.count * 58.0 + 32.0, 92.0), 260.0);
    self.petListHeightConstraint.constant = desiredHeight;
    [self.petListView reloadData];

    NSInteger selectedIndex = NSNotFound;
    NSURL *candidateURL = preferredURL ?: self.currentPackageURL;
    if (candidateURL != nil) {
        for (NSUInteger index = 0; index < self.petItems.count; index++) {
            NSURL *itemURL = self.petItems[index][@"url"];
            if ([itemURL.path isEqualToString:candidateURL.path]) {
                selectedIndex = (NSInteger)index;
                break;
            }
        }
    }

    if (selectedIndex == NSNotFound && self.petItems.count > 0) {
        selectedIndex = 0;
    }

    if (selectedIndex != NSNotFound) {
        [self loadPetAtIndex:selectedIndex preferredState:nil];
        return;
    }

    self.detailLabel.text = @"Import a zip package or raw pet files: pet.json + webp, or Spine atlas + json + png.";
    self.currentProfile = nil;
    self.currentPackageURL = nil;
    self.runtimeController = nil;
    [self.petView displayProfile:nil preferredState:nil];
    [self applyCurrentRuntimeVisualStateAnimated:NO];
}

- (NSArray<NSURL *> *)importedPetPackageURLs {
    NSURL *directoryURL = [self importedPetsDirectoryURL];
    NSArray<NSURL *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directoryURL
                                                             includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                  error:nil];
    NSMutableArray<NSURL *> *packages = [NSMutableArray array];
    for (NSURL *url in contents) {
        NSURL *packageURL = [self packageCandidateURLFromURL:url];
        if (packageURL != nil) {
            [packages addObject:packageURL];
        }
    }
    return [packages sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        return [left.lastPathComponent localizedCaseInsensitiveCompare:right.lastPathComponent];
    }];
}

- (NSURL *)importedPetsDirectoryURL {
    NSURL *baseURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directoryURL = [baseURL URLByAppendingPathComponent:@"DesktopPetiOS" isDirectory:YES];
    directoryURL = [directoryURL URLByAppendingPathComponent:PETIOSImportedPetsDirectoryName isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return directoryURL;
}

- (NSURL *)packageCandidateURLFromURL:(NSURL *)url {
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    if (isDirectory.boolValue) {
        NSURL *manifestURL = [url URLByAppendingPathComponent:@"pet.json"];
        if ([NSFileManager.defaultManager fileExistsAtPath:manifestURL.path]) {
            return manifestURL;
        }

        NSURL *spineJSONURL = [self spineRuntimeJSONURLFromDirectoryURL:url];
        if (spineJSONURL != nil) {
            return spineJSONURL;
        }

        NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:url
                                                                  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                       error:nil];
        for (NSURL *childURL in children) {
            NSURL *candidateURL = [self packageCandidateURLFromURL:childURL];
            if (candidateURL != nil) {
                return candidateURL;
            }
        }
        return nil;
    }

    if ([url.lastPathComponent.lowercaseString isEqualToString:@"pet.json"]) {
        return url;
    }
    if ([self isSpineRuntimeJSONURL:url inDirectory:url.URLByDeletingLastPathComponent]) {
        return url;
    }
    return nil;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    if (urls.count == 0) {
        return;
    }

    NSError *error = nil;
    NSURL *installedURL = [self installImportedPackageFromURLs:urls error:&error];
    if (installedURL == nil) {
        [self presentImportError:error];
        return;
    }

    [self reloadPetItemsSelectingURL:installedURL];
}

- (NSURL *)installImportedPackageFromURLs:(NSArray<NSURL *> *)urls error:(NSError **)error {
    NSMutableArray<NSURL *> *zipURLs = [NSMutableArray array];
    NSMutableArray<NSURL *> *rawAssetURLs = [NSMutableArray array];

    for (NSURL *url in urls) {
        NSString *extension = url.pathExtension.lowercaseString;
        if ([extension isEqualToString:@"zip"]) {
            [zipURLs addObject:url];
        } else if ([extension isEqualToString:@"json"] ||
                   [extension isEqualToString:@"webp"] ||
                   [extension isEqualToString:@"png"] ||
                   [extension isEqualToString:@"atlas"]) {
            [rawAssetURLs addObject:url];
        }
    }

    if (zipURLs.count > 0 && rawAssetURLs.count > 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETIOSImport"
                                         code:7101
                                     userInfo:@{NSLocalizedDescriptionKey: @"Please import either zip archives or raw pet files at one time."}];
        }
        return nil;
    }

    if (zipURLs.count > 0) {
        return [self installImportedZipURL:zipURLs.firstObject error:error];
    }

    if (rawAssetURLs.count > 0) {
        return [self installImportedRawFiles:rawAssetURLs error:error];
    }

    if (error != NULL) {
        *error = [NSError errorWithDomain:@"PETIOSImport"
                                     code:7102
                                 userInfo:@{NSLocalizedDescriptionKey: @"Supported import types are zip, pet.json + webp, or Spine atlas + json + png."}];
    }
    return nil;
}

- (NSURL *)installImportedZipURL:(NSURL *)zipURL error:(NSError **)error {
#if !PET_IOS_HAS_SSZIPARCHIVE
    (void)zipURL;
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"PETIOSImport"
                                     code:7106
                                 userInfo:@{NSLocalizedDescriptionKey: @"Zip import is waiting for SSZipArchive to finish installing. You can already import pet.json + webp, or Spine atlas + json + png directly."}];
    }
    return nil;
#else
    NSURL *workingDirectory = [self uniqueImportedPackageDirectoryNamed:zipURL.URLByDeletingPathExtension.lastPathComponent ?: @"ImportedPet"];
    NSString *destinationPath = workingDirectory.path;

    BOOL unzipSucceeded = [SSZipArchive unzipFileAtPath:zipURL.path toDestination:destinationPath];
    if (!unzipSucceeded) {
        [NSFileManager.defaultManager removeItemAtURL:workingDirectory error:nil];
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETIOSImport"
                                         code:7103
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to unzip the selected pet archive."}];
        }
        return nil;
    }

    NSURL *packageURL = [self packageCandidateURLFromURL:workingDirectory];
    if (packageURL == nil) {
        [NSFileManager.defaultManager removeItemAtURL:workingDirectory error:nil];
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETIOSImport"
                                         code:7104
                                     userInfo:@{NSLocalizedDescriptionKey: @"The zip archive does not contain a valid pet package or Spine atlas/json/png runtime bundle."}];
        }
        return nil;
    }

    NSError *validationError = nil;
    if ([self.animationSourceLoader loadAnimationSourceAtURL:packageURL error:&validationError] == nil) {
        [NSFileManager.defaultManager removeItemAtURL:workingDirectory error:nil];
        if (error != NULL) {
            *error = validationError;
        }
        return nil;
    }

    return packageURL;
#endif
}

- (NSURL *)installImportedRawFiles:(NSArray<NSURL *> *)urls error:(NSError **)error {
    BOOL hasPetManifest = NO;
    BOOL hasWebP = NO;
    BOOL hasAtlas = NO;
    BOOL hasSpineJSON = NO;
    BOOL hasPNG = NO;
    for (NSURL *url in urls) {
        NSString *extension = url.pathExtension.lowercaseString;
        if ([extension isEqualToString:@"json"]) {
            if ([url.lastPathComponent.lowercaseString isEqualToString:@"pet.json"]) {
                hasPetManifest = YES;
            } else {
                hasSpineJSON = YES;
            }
        } else if ([extension isEqualToString:@"webp"]) {
            hasWebP = YES;
        } else if ([extension isEqualToString:@"atlas"]) {
            hasAtlas = YES;
        } else if ([extension isEqualToString:@"png"]) {
            hasPNG = YES;
        }
    }

    BOOL isPetPackage = hasPetManifest && hasWebP;
    BOOL isSpineRuntimePackage = hasAtlas && hasSpineJSON && hasPNG;
    if (!isPetPackage && !isSpineRuntimePackage) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETIOSImport"
                                         code:7105
                                     userInfo:@{NSLocalizedDescriptionKey: @"Import raw files as either pet.json + webp, or Spine atlas + json + png."}];
        }
        return nil;
    }

    NSURL *workingDirectory = [self uniqueImportedPackageDirectoryNamed:isSpineRuntimePackage ? @"ImportedSpinePet" : @"ImportedPet"];
    for (NSURL *url in urls) {
        NSString *destinationFilename = url.lastPathComponent;
        if (isPetPackage && [url.pathExtension.lowercaseString isEqualToString:@"json"]) {
            destinationFilename = @"pet.json";
        }

        NSURL *destinationURL = [workingDirectory URLByAppendingPathComponent:destinationFilename];
        NSError *copyError = nil;
        if (![NSFileManager.defaultManager copyItemAtURL:url toURL:destinationURL error:&copyError]) {
            [NSFileManager.defaultManager removeItemAtURL:workingDirectory error:nil];
            if (error != NULL) {
                *error = copyError;
            }
            return nil;
        }
    }

    NSURL *entryURL = isPetPackage
        ? [workingDirectory URLByAppendingPathComponent:@"pet.json"]
        : [self spineRuntimeJSONURLFromDirectoryURL:workingDirectory];
    NSError *validationError = nil;
    if (entryURL == nil || [self.animationSourceLoader loadAnimationSourceAtURL:entryURL error:&validationError] == nil) {
        [NSFileManager.defaultManager removeItemAtURL:workingDirectory error:nil];
        if (error != NULL) {
            *error = validationError ?: [NSError errorWithDomain:@"PETIOSImport"
                                                            code:7107
                                                        userInfo:@{NSLocalizedDescriptionKey: @"The imported files do not form a valid pet package."}];
        }
        return nil;
    }
    return entryURL;
}

- (NSURL *)uniqueImportedPackageDirectoryNamed:(NSString *)baseName {
    NSString *trimmedName = [baseName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedName.length == 0) {
        trimmedName = @"ImportedPet";
    }

    NSString *safeName = [[trimmedName componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"-"];
    if (safeName.length == 0) {
        safeName = @"ImportedPet";
    }

    NSString *directoryName = [NSString stringWithFormat:@"%@-%@", safeName, NSUUID.UUID.UUIDString.lowercaseString];
    NSURL *directoryURL = [[self importedPetsDirectoryURL] URLByAppendingPathComponent:directoryName isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return directoryURL;
}

- (void)presentImportError:(NSError *)error {
    [self presentNoticeWithTitle:@"Import Failed"
                         message:(error.localizedDescription ?: @"Unable to import the selected pet files.")];
}

- (void)presentMissingBundleStateForPackage:(NSString *)packageName {
    self.detailLabel.text = [NSString stringWithFormat:@"Bundled pet package \"%@\" is missing from the iOS target resources.", packageName];
    [self.petView displayProfile:nil preferredState:nil];
}

- (nullable NSURL *)spineRuntimeJSONURLFromDirectoryURL:(NSURL *)directoryURL {
    NSArray<NSURL *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directoryURL
                                                             includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                  error:nil];
    for (NSURL *candidateURL in contents) {
        if ([self isSpineRuntimeJSONURL:candidateURL inDirectory:directoryURL]) {
            return candidateURL;
        }
    }
    return nil;
}

- (BOOL)isSpineRuntimeJSONURL:(NSURL *)jsonURL inDirectory:(NSURL *)directoryURL {
    if (![jsonURL.pathExtension.lowercaseString isEqualToString:@"json"]) {
        return NO;
    }
    if ([jsonURL.lastPathComponent.lowercaseString isEqualToString:@"pet.json"]) {
        return NO;
    }

    NSURL *atlasURL = [[directoryURL URLByAppendingPathComponent:jsonURL.lastPathComponent.stringByDeletingPathExtension] URLByAppendingPathExtension:@"atlas"];
    if (![NSFileManager.defaultManager fileExistsAtPath:atlasURL.path]) {
        return NO;
    }

    NSString *atlasText = [NSString stringWithContentsOfURL:atlasURL encoding:NSUTF8StringEncoding error:nil];
    if (atlasText.length == 0) {
        return NO;
    }

    NSArray<NSString *> *lines = [atlasText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0 || [trimmed containsString:@":"]) {
            continue;
        }
        NSURL *imageURL = [directoryURL URLByAppendingPathComponent:trimmed];
        if ([NSFileManager.defaultManager fileExistsAtPath:imageURL.path]) {
            return YES;
        }
    }
    return NO;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.petItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:PETIOSPetListCellReuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:PETIOSPetListCellReuseIdentifier];
    }

    NSDictionary<NSString *, id> *item = self.petItems[(NSUInteger)indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"source"];
    cell.accessoryType = (indexPath.row == self.selectedPetIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self loadPetAtIndex:indexPath.row preferredState:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *trimmed = [textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.appConfig.aiBaseURLString = trimmed.length > 0 ? trimmed : @"https://api.openai.com/v1";
    textField.text = self.appConfig.aiBaseURLString;
    [self.appConfig persist];
    [self configureCognitionEngine];
}

- (void)animatedPetViewDidReceivePrimaryTap:(PETIOSAnimatedPetView *)petView
                                    atPoint:(CGPoint)point
                             partIdentifier:(NSString *)partIdentifier {
    (void)petView;
    NSString *actionKey = [self actionKeyForInteractivePartIdentifier:partIdentifier fallbackPoint:point];
    NSString *fallbackBehaviorState = @"jumping";
    if ([actionKey isEqualToString:PETIOSActionTapHead]) {
        fallbackBehaviorState = @"waving";
    } else if ([actionKey isEqualToString:PETIOSActionTapHand]) {
        fallbackBehaviorState = @"review";
    } else if ([actionKey isEqualToString:PETIOSActionTapTail]) {
        fallbackBehaviorState = @"social";
    }
    [self runRuntimeActionKey:actionKey
        fallbackBehaviorState:fallbackBehaviorState
                      context:@{
        @"runtimeMode": @"ios.touch",
        @"touchX": @(point.x),
        @"touchY": @(point.y),
        @"partIdentifier": partIdentifier ?: @""
    }];
    [self scheduleAmbientResumeAfterDuration:0.9];
}

- (void)animatedPetViewDidBeginDrag:(PETIOSAnimatedPetView *)petView atPoint:(CGPoint)point {
    (void)petView;
    self.lastDragActionKey = nil;
    self.lastDragRuntimeUpdateTime = 0.0;
    [self.ambientResumeTimer invalidate];
    [self runRuntimeActionKey:PETIOSActionDragIdle
        fallbackBehaviorState:@"waiting"
                      context:@{
        @"runtimeMode": @"ios.drag",
        @"dragStartX": @(point.x),
        @"dragStartY": @(point.y)
    }];
}

- (void)animatedPetViewDidDrag:(PETIOSAnimatedPetView *)petView translation:(CGPoint)translation velocity:(CGPoint)velocity {
    CGPoint clampedOffset = [self clampedOffset:petView.petOffset];
    if (!CGPointEqualToPoint(clampedOffset, petView.petOffset)) {
        [petView setPetOffset:clampedOffset animated:NO];
    }

    NSString *actionKey = PETIOSActionDragIdle;
    NSString *fallbackBehaviorState = @"waiting";
    if (translation.x > 12.0) {
        actionKey = PETIOSActionDragMoveRight;
        fallbackBehaviorState = @"running-right";
    } else if (translation.x < -12.0) {
        actionKey = PETIOSActionDragMoveLeft;
        fallbackBehaviorState = @"running-left";
    }

    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    BOOL shouldEmit = ![actionKey isEqualToString:self.lastDragActionKey] || (now - self.lastDragRuntimeUpdateTime) >= 0.22;
    if (!shouldEmit) {
        return;
    }

    self.lastDragActionKey = actionKey;
    self.lastDragRuntimeUpdateTime = now;
    [self runRuntimeActionKey:actionKey
        fallbackBehaviorState:fallbackBehaviorState
                      context:@{
        @"runtimeMode": @"ios.drag",
        @"dragTranslationX": @(translation.x),
        @"dragTranslationY": @(translation.y),
        @"dragVelocityX": @(velocity.x),
        @"dragVelocityY": @(velocity.y)
    }];
}

- (void)animatedPetViewDidEndDrag:(PETIOSAnimatedPetView *)petView velocity:(CGPoint)velocity {
    [petView setPetOffset:[self clampedOffset:petView.petOffset] animated:YES];
    [self runRuntimeActionKey:PETIOSActionDragRelease
        fallbackBehaviorState:@"jumping"
                      context:@{
        @"runtimeMode": @"ios.drag",
        @"dragVelocityX": @(velocity.x),
        @"dragVelocityY": @(velocity.y)
    }];
    [self scheduleAmbientResumeAfterDuration:0.55];
}

@end
