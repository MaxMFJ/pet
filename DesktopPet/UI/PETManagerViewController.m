#import "PETManagerViewController.h"

#import "../Config/PETAppConfig.h"
#import "../GameEngine/Core/PETGameCommand.h"
#import "../Managers/PETAssetImportManager.h"
#import "../Managers/PETPetManager.h"
#import "../Models/PETPetProfile.h"

@interface PETManagerViewController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSplitViewDelegate>

@property (nonatomic, strong) PETPetManager *petManager;
@property (nonatomic, strong) PETAppConfig *configuration;
@property (nonatomic, strong) PETAssetImportManager *assetImportManager;

@property (nonatomic, strong) NSTextField *baseURLField;
@property (nonatomic, strong) NSTextField *petCountLabel;
@property (nonatomic, strong) NSButton *toggleVisibilityButton;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSSlider *scaleSlider;
@property (nonatomic, strong) NSTextField *scaleValueLabel;
@property (nonatomic, strong) NSSegmentedControl *facingDirectionControl;
@property (nonatomic, strong) NSButton *clickThroughCheckbox;
@property (nonatomic, strong) NSButton *soulArkCheckbox;
@property (nonatomic, strong) NSButton *soulArkFacingInvertedCheckbox;
@property (nonatomic, strong) NSPopUpButton *statePopUpButton;
@property (nonatomic, strong) NSButton *previewStateButton;
@property (nonatomic, strong) NSButton *resumeAmbientButton;
@property (nonatomic, strong) NSTextField *currentStateLabel;
@property (nonatomic, strong) NSTextField *combatDebugLabel;
@property (nonatomic, strong) NSTextField *collisionDebugLabel;
@property (nonatomic, strong) NSButton *combatPrimaryButton;
@property (nonatomic, strong) NSButton *combatSkillButton;
@property (nonatomic, strong) NSButton *combatUltimateButton;
@property (nonatomic, strong) NSButton *combatCancelButton;
@property (nonatomic, strong) NSTableView *interactionMappingTableView;
@property (nonatomic, copy) NSArray<NSString *> *interactionMappingActionKeys;
@property (nonatomic, strong) NSSplitView *listDetailSplitView;

@end

@implementation PETManagerViewController

static NSString * const PETManagerInteractionAmbientIdle = @"ambient.idle";
static NSString * const PETManagerInteractionTapPrimary = @"tap.primary";
static NSString * const PETManagerInteractionTapSecondary = @"tap.secondary";
static NSString * const PETManagerInteractionTapHead = @"tap.head";
static NSString * const PETManagerInteractionTapTail = @"tap.tail";
static NSString * const PETManagerInteractionTapBody = @"tap.body";
static NSString * const PETManagerInteractionTapPartPrefix = @"tap.part.";
static NSString * const PETManagerInteractionDragMoveLeft = @"drag.move.left";
static NSString * const PETManagerInteractionDragMoveRight = @"drag.move.right";
static NSString * const PETManagerInteractionDragIdle = @"drag.idle";
static NSString * const PETManagerInteractionDragRelease = @"drag.release";
static CGFloat const PETManagerDefaultScale = 0.3;

static NSImage * _Nullable PETLoadManagerToolbarTemplateImage(NSString *nameWithoutExtension) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:nameWithoutExtension withExtension:@"png" subdirectory:@"ManagerToolbar"];
    if (url == nil) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (image == nil) {
        return nil;
    }
    image.template = YES;
    image.size = NSMakeSize(18, 18);
    return image;
}

static void PETApplyToolbarChromeToButton(NSButton *button) {
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeRegular;
}

static void PETSetToolbarTemplateImage(NSButton *button, NSString * _Nullable nameWithoutExtension) {
    if (nameWithoutExtension.length == 0) {
        button.image = nil;
        return;
    }
    NSImage *image = PETLoadManagerToolbarTemplateImage(nameWithoutExtension);
    if (image != nil) {
        button.image = image;
        button.imagePosition = NSImageLeading;
    }
}

- (instancetype)initWithPetManager:(PETPetManager *)petManager
                     configuration:(PETAppConfig *)configuration
                assetImportManager:(PETAssetImportManager *)assetImportManager {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _petManager = petManager;
        _configuration = configuration;
        _assetImportManager = assetImportManager;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadPetList)
                                                     name:PETPetManagerDidChangePetsNotification
                                                   object:_petManager];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRuntimeDebugUpdate:)
                                                     name:PETPetManagerDidUpdateRuntimeDebugNotification
                                                   object:_petManager];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSBox *)pet_sectionBoxWithTitle:(NSString *)title content:(NSView *)content {
    NSBox *box = [[NSBox alloc] init];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.title = title;
    box.boxType = NSBoxPrimary;
    box.titlePosition = NSAtTop;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *host = box.contentView;
    [host addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:8],
        [content.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-8],
        [content.topAnchor constraintEqualToAnchor:host.topAnchor constant:4],
        [content.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-8],
    ]];
    return box;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 560)];
    self.view.wantsLayer = YES;
    self.view.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.spacing = 12.0;
    rootStack.edgeInsets = NSEdgeInsetsMake(16.0, 20.0, 20.0, 20.0);
    rootStack.distribution = NSStackViewDistributionFill;
    [self.view addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [rootStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [rootStack.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [rootStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    NSTextField *titleLabel = [self labelWithString:@"桌面宠物" font:[NSFont systemFontOfSize:22.0 weight:NSFontWeightSemibold]];
    [rootStack addArrangedSubview:titleLabel];

    NSTextField *subtitleLabel = [self labelWithString:@"管理已导入的宠物、窗口显示与 AI 端点。建议优先使用 Codex 标准宠物包。" font:[NSFont systemFontOfSize:12.0]];
    subtitleLabel.textColor = NSColor.secondaryLabelColor;
    subtitleLabel.maximumNumberOfLines = 2;
    [rootStack addArrangedSubview:subtitleLabel];

    NSGridView *settingsGrid = [self buildSettingsGrid];
    NSBox *settingsBox = [self pet_sectionBoxWithTitle:@"连接与上限" content:settingsGrid];
    [rootStack addArrangedSubview:settingsBox];

    NSStackView *toolbar = [self buildToolbar];
    NSBox *actionsBox = [self pet_sectionBoxWithTitle:@"快捷操作" content:toolbar];
    [rootStack addArrangedSubview:actionsBox];

    NSScrollView *tableScrollView = [self buildTableView];
    NSGridView *petSettingsGrid = [self buildPetSettingsGrid];
    petSettingsGrid.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *detailScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    detailScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    detailScrollView.hasVerticalScroller = YES;
    detailScrollView.hasHorizontalScroller = NO;
    detailScrollView.autohidesScrollers = YES;
    detailScrollView.borderType = NSBezelBorder;
    detailScrollView.documentView = petSettingsGrid;
    NSClipView *detailClip = detailScrollView.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [petSettingsGrid.leadingAnchor constraintEqualToAnchor:detailClip.leadingAnchor],
        [petSettingsGrid.trailingAnchor constraintEqualToAnchor:detailClip.trailingAnchor],
        [petSettingsGrid.topAnchor constraintEqualToAnchor:detailClip.topAnchor],
        [petSettingsGrid.widthAnchor constraintEqualToAnchor:detailClip.widthAnchor]
    ]];
    [detailScrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

    NSBox *listBox = [self pet_sectionBoxWithTitle:@"宠物列表" content:tableScrollView];
    NSBox *detailBox = [self pet_sectionBoxWithTitle:@"选中宠物" content:detailScrollView];
    listBox.translatesAutoresizingMaskIntoConstraints = YES;
    detailBox.translatesAutoresizingMaskIntoConstraints = YES;
    listBox.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    detailBox.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 920, 360)];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.vertical = NO;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    splitView.autosaveName = @"PETManagerListDetailSplit";
    splitView.delegate = self;
    self.listDetailSplitView = splitView;
    [splitView addSubview:listBox];
    [splitView addSubview:detailBox];
    [splitView adjustSubviews];

    [splitView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [splitView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [rootStack addArrangedSubview:splitView];
    [splitView.heightAnchor constraintGreaterThanOrEqualToConstant:300.0].active = YES;

    self.petCountLabel = [self labelWithString:@"" font:[NSFont systemFontOfSize:12.0]];
    self.petCountLabel.textColor = NSColor.secondaryLabelColor;
    [rootStack addArrangedSubview:self.petCountLabel];

    [self reloadPetList];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    [self.listDetailSplitView adjustSubviews];
}

- (NSGridView *)buildSettingsGrid {
    NSTextField *baseURLLabel = [self labelWithString:@"BaseURL" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]];
    self.baseURLField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.baseURLField.stringValue = self.configuration.aiBaseURLString ?: @"";
    self.baseURLField.placeholderString = @"https://api.openai.com/v1";
    self.baseURLField.delegate = self;

    NSButton *saveButton = [NSButton buttonWithTitle:@"保存配置" target:self action:@selector(saveConfiguration:)];
    PETApplyToolbarChromeToButton(saveButton);
    PETSetToolbarTemplateImage(saveButton, @"PETToolbarSave");

    NSTextField *maxPetsLabel = [self labelWithString:@"多宠物上限" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]];
    NSTextField *maxPetsValue = [self labelWithString:[NSString stringWithFormat:@"%ld", (long)self.configuration.maxConcurrentPets]
                                                 font:[NSFont systemFontOfSize:13.0]];
    maxPetsValue.textColor = NSColor.secondaryLabelColor;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[baseURLLabel, self.baseURLField, saveButton],
        @[maxPetsLabel, maxPetsValue, [NSView new]]
    ]];
    grid.rowSpacing = 10.0;
    grid.columnSpacing = 12.0;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    return grid;
}

- (NSStackView *)buildToolbar {
    NSButton *addButton = [NSButton buttonWithTitle:@"导入宠物包" target:self action:@selector(addPet:)];
    PETApplyToolbarChromeToButton(addButton);
    PETSetToolbarTemplateImage(addButton, @"PETToolbarImport");

    NSButton *spineToolButton = [NSButton buttonWithTitle:@"Spine 工具" target:self action:@selector(openSpineTool:)];
    PETApplyToolbarChromeToButton(spineToolButton);
    PETSetToolbarTemplateImage(spineToolButton, @"PETToolbarSpine");

    self.toggleVisibilityButton = [NSButton buttonWithTitle:@"隐藏宠物" target:self action:@selector(toggleSelectedPetVisibility:)];
    PETApplyToolbarChromeToButton(self.toggleVisibilityButton);

    self.removeButton = [NSButton buttonWithTitle:@"删除宠物" target:self action:@selector(removeSelectedPet:)];
    PETApplyToolbarChromeToButton(self.removeButton);
    PETSetToolbarTemplateImage(self.removeButton, @"PETToolbarTrash");

    NSButton *showAllButton = [NSButton buttonWithTitle:@"全部显示" target:self action:@selector(showAllPets:)];
    PETApplyToolbarChromeToButton(showAllButton);
    PETSetToolbarTemplateImage(showAllButton, @"PETToolbarEyeVisible");

    NSButton *hideAllButton = [NSButton buttonWithTitle:@"全部隐藏" target:self action:@selector(hideAllPets:)];
    PETApplyToolbarChromeToButton(hideAllButton);
    PETSetToolbarTemplateImage(hideAllButton, @"PETToolbarHideAll");

    NSStackView *toolbar = [[NSStackView alloc] initWithFrame:NSZeroRect];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 10.0;
    toolbar.alignment = NSLayoutAttributeCenterY;
    [toolbar addArrangedSubview:addButton];
    [toolbar addArrangedSubview:spineToolButton];
    [toolbar addArrangedSubview:self.toggleVisibilityButton];
    [toolbar addArrangedSubview:self.removeButton];
    [toolbar addArrangedSubview:showAllButton];
    [toolbar addArrangedSubview:hideAllButton];
    return toolbar;
}

- (NSGridView *)buildPetSettingsGrid {
    self.nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.nameField.placeholderString = @"Pet Name";
    self.nameField.delegate = self;

    self.scaleSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    self.scaleSlider.minValue = 0.01;
    self.scaleSlider.maxValue = 3.0;
    self.scaleSlider.doubleValue = PETManagerDefaultScale;
    self.scaleSlider.target = self;
    self.scaleSlider.action = @selector(scaleChanged:);

    self.scaleValueLabel = [self labelWithString:@"30%" font:[NSFont systemFontOfSize:12.0]];
    self.scaleValueLabel.textColor = NSColor.secondaryLabelColor;

    self.facingDirectionControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 120, 28)];
    self.facingDirectionControl.segmentCount = 2;
    self.facingDirectionControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    [self.facingDirectionControl setLabel:@"左" forSegment:0];
    [self.facingDirectionControl setLabel:@"右" forSegment:1];
    self.facingDirectionControl.target = self;
    self.facingDirectionControl.action = @selector(facingDirectionChanged:);
    self.facingDirectionControl.selectedSegment = 1;

    self.clickThroughCheckbox = [NSButton checkboxWithTitle:@"点击穿透" target:self action:@selector(clickThroughChanged:)];
    self.soulArkCheckbox = [NSButton checkboxWithTitle:@"灵魂方舟适配" target:self action:@selector(soulArkChanged:)];
    self.soulArkFacingInvertedCheckbox = [NSButton checkboxWithTitle:@"灵魂方舟左右反转" target:self action:@selector(soulArkFacingInvertedChanged:)];
    NSStackView *adaptationStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    adaptationStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    adaptationStack.alignment = NSLayoutAttributeLeading;
    adaptationStack.spacing = 6.0;
    [adaptationStack addArrangedSubview:self.soulArkCheckbox];
    [adaptationStack addArrangedSubview:self.soulArkFacingInvertedCheckbox];
    self.statePopUpButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.previewStateButton = [NSButton buttonWithTitle:@"预览动作" target:self action:@selector(previewSelectedState:)];
    PETApplyToolbarChromeToButton(self.previewStateButton);
    PETSetToolbarTemplateImage(self.previewStateButton, @"PETToolbarPlay");
    self.resumeAmbientButton = [NSButton buttonWithTitle:@"恢复待机" target:self action:@selector(resumeAmbientState:)];
    PETApplyToolbarChromeToButton(self.resumeAmbientButton);
    PETSetToolbarTemplateImage(self.resumeAmbientButton, @"PETToolbarHomeIdle");
    self.currentStateLabel = [self labelWithString:@"当前: idle" font:[NSFont systemFontOfSize:12.0]];
    self.currentStateLabel.textColor = NSColor.secondaryLabelColor;
    self.combatDebugLabel = [self multilineLabel];
    self.collisionDebugLabel = [self multilineLabel];
    self.combatPrimaryButton = [NSButton buttonWithTitle:@"Primary" target:self action:@selector(triggerCombatPrimary:)];
    self.combatSkillButton = [NSButton buttonWithTitle:@"Skill" target:self action:@selector(triggerCombatSkill:)];
    self.combatUltimateButton = [NSButton buttonWithTitle:@"Ultimate" target:self action:@selector(triggerCombatUltimate:)];
    self.combatCancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(triggerCombatCancel:)];
    NSArray<NSButton *> *combatButtons = @[
        self.combatPrimaryButton,
        self.combatSkillButton,
        self.combatUltimateButton,
        self.combatCancelButton
    ];
    for (NSButton *button in combatButtons) {
        PETApplyToolbarChromeToButton(button);
    }
    NSStackView *combatControlsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    combatControlsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    combatControlsStack.spacing = 8.0;
    combatControlsStack.alignment = NSLayoutAttributeCenterY;
    combatControlsStack.distribution = NSStackViewDistributionFillEqually;
    [combatControlsStack addArrangedSubview:self.combatPrimaryButton];
    [combatControlsStack addArrangedSubview:self.combatSkillButton];
    [combatControlsStack addArrangedSubview:self.combatUltimateButton];
    [combatControlsStack addArrangedSubview:self.combatCancelButton];

    self.interactionMappingTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.interactionMappingTableView.delegate = self;
    self.interactionMappingTableView.dataSource = self;
    self.interactionMappingTableView.headerView = nil;
    self.interactionMappingTableView.allowsEmptySelection = YES;
    self.interactionMappingTableView.rowHeight = 30.0;

    NSTableColumn *mappingKeyColumn = [[NSTableColumn alloc] initWithIdentifier:@"mappingKey"];
    mappingKeyColumn.width = 200.0;
    mappingKeyColumn.minWidth = 160.0;
    NSTableColumn *mappingValueColumn = [[NSTableColumn alloc] initWithIdentifier:@"mappingValue"];
    mappingValueColumn.width = 220.0;
    mappingValueColumn.minWidth = 160.0;
    [self.interactionMappingTableView addTableColumn:mappingKeyColumn];
    [self.interactionMappingTableView addTableColumn:mappingValueColumn];

    NSScrollView *interactionMappingScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    interactionMappingScrollView.documentView = self.interactionMappingTableView;
    interactionMappingScrollView.hasVerticalScroller = YES;
    interactionMappingScrollView.hasHorizontalScroller = YES;
    interactionMappingScrollView.borderType = NSBezelBorder;
    interactionMappingScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [interactionMappingScrollView.heightAnchor constraintEqualToConstant:180.0].active = YES;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self labelWithString:@"名称" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.nameField, [NSView new]],
        @[[self labelWithString:@"缩放" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.scaleSlider, self.scaleValueLabel],
        @[[self labelWithString:@"朝向" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.facingDirectionControl, [NSView new]],
        @[[self labelWithString:@"交互" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.clickThroughCheckbox, [NSView new]],
        @[[self labelWithString:@"素材适配" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], adaptationStack, [NSView new]],
        @[[self labelWithString:@"动作" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.statePopUpButton, self.previewStateButton],
        @[[self labelWithString:@"交互映射" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], interactionMappingScrollView, [NSView new]],
        @[[self labelWithString:@"状态" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.currentStateLabel, self.resumeAmbientButton],
        @[[self labelWithString:@"战斗调试" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.combatDebugLabel, combatControlsStack],
        @[[self labelWithString:@"触碰检测" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.collisionDebugLabel, [NSView new]]
    ]];
    grid.rowSpacing = 10.0;
    grid.columnSpacing = 12.0;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    return grid;
}

- (NSScrollView *)buildTableView {
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.allowsEmptySelection = YES;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.rowHeight = 32.0;
    self.tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    self.tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.tableView.headerView = [[NSTableHeaderView alloc] initWithFrame:NSZeroRect];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"名称";
    nameColumn.width = 160.0;
    nameColumn.minWidth = 100.0;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask;

    NSTableColumn *statusColumn = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    statusColumn.title = @"显示";
    statusColumn.width = 72.0;
    statusColumn.minWidth = 56.0;
    statusColumn.maxWidth = 100.0;
    statusColumn.resizingMask = NSTableColumnUserResizingMask;

    NSTableColumn *sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"source"];
    sourceColumn.title = @"来源路径";
    sourceColumn.width = 360.0;
    sourceColumn.minWidth = 120.0;
    sourceColumn.resizingMask = NSTableColumnAutoresizingMask;

    [self.tableView addTableColumn:nameColumn];
    [self.tableView addTableColumn:statusColumn];
    [self.tableView addTableColumn:sourceColumn];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = self.tableView;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [scrollView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return scrollView;
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSTextField *)multilineLabel {
    NSTextField *label = [NSTextField labelWithString:@"-"];
    label.font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    label.textColor = NSColor.secondaryLabelColor;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    label.usesSingleLineMode = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (void)reloadPetList {
    NSString *selectedIdentifier = self.petManager.selectedPetIdentifier ?: [self selectedProfile].identifier;
    [self.tableView reloadData];
    [self restoreSelectionWithIdentifier:selectedIdentifier];
    self.petCountLabel.stringValue = [NSString stringWithFormat:@"已导入: %lu    显示: %lu / %ld",
                                      (unsigned long)self.petManager.activeProfiles.count,
                                      (unsigned long)self.petManager.visiblePetCount,
                                      (long)self.configuration.maxConcurrentPets];
    [self updateButtons];
    [self refreshPetSettings];
}

- (void)updateButtons {
    PETPetProfile *selectedProfile = [self selectedProfile];
    BOOL hasSelection = (selectedProfile != nil);
    self.toggleVisibilityButton.enabled = hasSelection;
    self.removeButton.enabled = hasSelection;

    if (!hasSelection) {
        self.toggleVisibilityButton.title = @"隐藏宠物";
        self.toggleVisibilityButton.image = nil;
        return;
    }

    BOOL isVisible = [self.petManager isPetVisible:selectedProfile];
    self.toggleVisibilityButton.title = isVisible ? @"隐藏宠物" : @"显示宠物";
    PETSetToolbarTemplateImage(self.toggleVisibilityButton, isVisible ? @"PETToolbarEyeHidden" : @"PETToolbarEyeVisible");
}

- (void)refreshPetSettings {
    PETPetProfile *selectedProfile = [self selectedProfile];
    BOOL hasSelection = (selectedProfile != nil);

    self.nameField.enabled = hasSelection;
    self.scaleSlider.enabled = hasSelection;
    self.facingDirectionControl.enabled = hasSelection;
    self.clickThroughCheckbox.enabled = hasSelection;
    self.soulArkCheckbox.enabled = hasSelection;
    self.soulArkFacingInvertedCheckbox.enabled = hasSelection;
    self.statePopUpButton.enabled = hasSelection;
    self.previewStateButton.enabled = hasSelection;
    self.resumeAmbientButton.enabled = hasSelection;
    self.interactionMappingTableView.enabled = hasSelection;
    [self refreshCombatControlButtonsForProfile:selectedProfile];

    if (!hasSelection) {
        self.nameField.stringValue = @"";
        self.scaleSlider.doubleValue = PETManagerDefaultScale;
        self.scaleValueLabel.stringValue = @"30%";
        self.facingDirectionControl.selectedSegment = 1;
        self.clickThroughCheckbox.state = NSControlStateValueOff;
        self.soulArkCheckbox.state = NSControlStateValueOff;
        self.soulArkFacingInvertedCheckbox.state = NSControlStateValueOff;
        [self.statePopUpButton removeAllItems];
        self.interactionMappingActionKeys = @[];
        [self.interactionMappingTableView reloadData];
        [self.currentStateLabel setStringValue:@"当前: -"];
        self.combatDebugLabel.stringValue = @"-";
        self.collisionDebugLabel.stringValue = @"-";
        return;
    }

    self.nameField.stringValue = selectedProfile.displayName ?: @"";
    CGFloat scale = [self.petManager scaleForPetProfile:selectedProfile];
    self.scaleSlider.doubleValue = scale;
    self.scaleValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", scale * 100.0];
    self.facingDirectionControl.selectedSegment = [self.petManager isFacingRightForPetProfile:selectedProfile] ? 1 : 0;
    self.clickThroughCheckbox.state = [self.petManager isClickThroughEnabledForPetProfile:selectedProfile] ? NSControlStateValueOn : NSControlStateValueOff;
    self.soulArkCheckbox.state = [self.petManager isSoulArkEnabledForPetProfile:selectedProfile] ? NSControlStateValueOn : NSControlStateValueOff;
    self.soulArkFacingInvertedCheckbox.state = [self.petManager isSoulArkFacingInvertedForPetProfile:selectedProfile] ? NSControlStateValueOn : NSControlStateValueOff;
    self.soulArkFacingInvertedCheckbox.enabled = hasSelection && (self.soulArkCheckbox.state == NSControlStateValueOn);
    [self reloadStateControlsForProfile:selectedProfile];
    [self reloadInteractionMappingTableForProfile:selectedProfile];
    self.currentStateLabel.stringValue = [self.petManager characterRuntimeSummaryForPetProfile:selectedProfile];
    [self refreshCombatDebugPanelForProfile:selectedProfile];
}

- (void)refreshCombatButton:(NSButton *)button
             descriptorKey:(NSString *)descriptorKey
                 forProfile:(PETPetProfile *)profile
               defaultTitle:(NSString *)defaultTitle {
    NSDictionary<NSString *, id> *descriptor = profile != nil
        ? [self.petManager combatDebugBindingDescriptorForKey:descriptorKey forPetProfile:profile]
        : nil;
    NSString *label = [descriptor[@"label"] isKindOfClass:NSString.class] ? descriptor[@"label"] : nil;
    NSString *skillIdentifier = [descriptor[@"skillId"] isKindOfClass:NSString.class] ? descriptor[@"skillId"] : nil;
    NSString *commandType = [descriptor[@"commandType"] isKindOfClass:NSString.class] ? descriptor[@"commandType"] : nil;

    button.enabled = (descriptor != nil);
    button.title = label.length > 0 ? label : defaultTitle;
    if (descriptor == nil) {
        button.toolTip = defaultTitle;
        return;
    }

    NSMutableArray<NSString *> *tooltipLines = [NSMutableArray array];
    [tooltipLines addObject:[NSString stringWithFormat:@"key: %@", descriptorKey]];
    if (commandType.length > 0) {
        [tooltipLines addObject:[NSString stringWithFormat:@"command: %@", commandType]];
    }
    if (skillIdentifier.length > 0) {
        [tooltipLines addObject:[NSString stringWithFormat:@"skill: %@", skillIdentifier]];
    }
    button.toolTip = [tooltipLines componentsJoinedByString:@"\n"];
}

- (void)refreshCombatControlButtonsForProfile:(PETPetProfile *)profile {
    [self refreshCombatButton:self.combatPrimaryButton descriptorKey:@"j" forProfile:profile defaultTitle:@"Primary"];
    [self refreshCombatButton:self.combatSkillButton descriptorKey:@"l" forProfile:profile defaultTitle:@"Skill"];
    [self refreshCombatButton:self.combatUltimateButton descriptorKey:@"u" forProfile:profile defaultTitle:@"Ultimate"];
    [self refreshCombatButton:self.combatCancelButton descriptorKey:@"o" forProfile:profile defaultTitle:@"Cancel"];
}

- (PETPetProfile * _Nullable)selectedProfile {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.petManager.activeProfiles.count) {
        return nil;
    }
    return self.petManager.activeProfiles[(NSUInteger)row];
}

- (void)saveConfiguration:(id)sender {
    (void)sender;
    self.configuration.aiBaseURLString = self.baseURLField.stringValue.length > 0 ? self.baseURLField.stringValue : @"https://api.openai.com/v1";
    [self.configuration persist];
    [self reloadPetList];
}

- (void)addPet:(id)sender {
    [self.assetImportManager importPetFromOpenPanel:sender];
}

- (void)openSpineTool:(id)sender {
    (void)sender;
    [NSApp sendAction:@selector(showAnimationExportTool:) to:NSApp.delegate from:self];
}

- (void)toggleSelectedPetVisibility:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    BOOL isVisible = [self.petManager isPetVisible:profile];
    [self.petManager setVisibility:!isVisible forPetProfile:profile];
}

- (void)removeSelectedPet:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    [self.petManager removePetProfile:profile];
}

- (void)scaleChanged:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    [self.petManager setScale:self.scaleSlider.doubleValue forPetProfile:profile];
    [self refreshPetSettings];
}

- (void)clickThroughChanged:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    BOOL isEnabled = self.clickThroughCheckbox.state == NSControlStateValueOn;
    [self.petManager setClickThroughEnabled:isEnabled forPetProfile:profile];
    [self refreshPetSettings];
}

- (void)facingDirectionChanged:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    BOOL facingRight = (self.facingDirectionControl.selectedSegment != 0);
    [self.petManager setFacingRight:facingRight forPetProfile:profile];
    [self refreshPetSettings];
}

- (void)soulArkChanged:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    BOOL isEnabled = (self.soulArkCheckbox.state == NSControlStateValueOn);
    [self.petManager setSoulArkEnabled:isEnabled forPetProfile:profile];
    if (!isEnabled) {
        [self.petManager setSoulArkFacingInverted:NO forPetProfile:profile];
    }
    [self refreshPetSettings];
}

- (void)soulArkFacingInvertedChanged:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    BOOL isInverted = (self.soulArkFacingInvertedCheckbox.state == NSControlStateValueOn);
    [self.petManager setSoulArkFacingInverted:isInverted forPetProfile:profile];
    [self refreshPetSettings];
}

- (void)previewSelectedState:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    NSString *state = self.statePopUpButton.selectedItem.representedObject;
    if (state.length == 0) {
        return;
    }

    [self.petManager previewState:state forPetProfile:profile];
    [self refreshPetSettings];
}

- (void)resumeAmbientState:(id)sender {
    (void)sender;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    [self.petManager resumeAmbientBehaviorForPetProfile:profile];
    [self refreshPetSettings];
}

- (void)triggerCombatBindingForKey:(NSString *)key {
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil || key.length == 0) {
        return;
    }
    if ([self.petManager triggerCombatDebugBindingForKey:key forPetProfile:profile]) {
        [self refreshCombatDebugPanelForProfile:profile];
    }
}

- (void)triggerCombatPrimary:(id)sender {
    (void)sender;
    [self triggerCombatBindingForKey:@"j"];
}

- (void)triggerCombatSkill:(id)sender {
    (void)sender;
    [self triggerCombatBindingForKey:@"l"];
}

- (void)triggerCombatUltimate:(id)sender {
    (void)sender;
    [self triggerCombatBindingForKey:@"u"];
}

- (void)triggerCombatCancel:(id)sender {
    (void)sender;
    [self triggerCombatBindingForKey:@"o"];
}

- (void)interactionAliasSelectionChanged:(NSPopUpButton *)sender {
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }

    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)self.interactionMappingActionKeys.count) {
        return;
    }
    NSString *actionKey = self.interactionMappingActionKeys[(NSUInteger)row];
    if (actionKey.length == 0) {
        return;
    }

    NSString *animationState = sender.selectedItem.representedObject;
    if ([animationState isEqualToString:@"__auto__"]) {
        animationState = nil;
    }
    [self.petManager setInteractionAlias:animationState forActionKey:actionKey forPetProfile:profile];
    [self reloadInteractionMappingTableForProfile:profile];
}

- (void)showAllPets:(id)sender {
    (void)sender;
    [self.petManager setAllPetsHidden:NO];
}

- (void)hideAllPets:(id)sender {
    (void)sender;
    [self.petManager setAllPetsHidden:YES];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.tableView) {
        return (NSInteger)self.petManager.activeProfiles.count;
    }
    if (tableView == self.interactionMappingTableView) {
        return (NSInteger)self.interactionMappingActionKeys.count;
    }
    return 0;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.interactionMappingTableView) {
        return [self interactionMappingTableView:tableView viewForTableColumn:tableColumn row:row];
    }

    PETPetProfile *profile = self.petManager.activeProfiles[(NSUInteger)row];
    NSString *identifier = tableColumn.identifier;
    NSTextField *cell = [self.tableView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = identifier;
        cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }

    if ([identifier isEqualToString:@"name"]) {
        cell.stringValue = profile.displayName;
    } else if ([identifier isEqualToString:@"status"]) {
        cell.stringValue = [self.petManager isPetVisible:profile] ? @"显示中" : @"已隐藏";
    } else {
        cell.stringValue = profile.sourceURL.path ?: @"";
    }

    return cell;
}

- (nullable NSView *)interactionMappingTableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil || row < 0 || row >= (NSInteger)self.interactionMappingActionKeys.count) {
        return nil;
    }

    NSString *actionKey = self.interactionMappingActionKeys[(NSUInteger)row];
    if ([tableColumn.identifier isEqualToString:@"mappingKey"]) {
        NSTextField *cell = [self.interactionMappingTableView makeViewWithIdentifier:@"mappingKey" owner:self];
        if (cell == nil) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"mappingKey";
            cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
        }
        cell.stringValue = [NSString stringWithFormat:@"%@  (%@)",
                            [self localizedTitleForInteractionActionKey:actionKey],
                            actionKey];
        cell.toolTip = actionKey;
        return cell;
    }

    NSPopUpButton *popup = [self.interactionMappingTableView makeViewWithIdentifier:@"mappingValue" owner:self];
    if (popup == nil) {
        popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 260, 26) pullsDown:NO];
        popup.identifier = @"mappingValue";
        popup.target = self;
        popup.action = @selector(interactionAliasSelectionChanged:);
    }

    popup.tag = row;
    [popup removeAllItems];
    NSMenuItem *autoItem = [[NSMenuItem alloc] initWithTitle:@"自动"
                                                      action:nil
                                               keyEquivalent:@""];
    autoItem.representedObject = @"__auto__";
    [popup.menu addItem:autoItem];
    for (NSString *state in profile.supportedStates) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self localizedTitleForState:state]
                                                      action:nil
                                               keyEquivalent:@""];
        item.representedObject = state;
        [popup.menu addItem:item];
    }

    NSString *selectedAlias = [profile userInteractionAnimationStateForActionKey:actionKey];
    if (selectedAlias.length > 0) {
        NSInteger aliasIndex = [profile.supportedStates indexOfObject:selectedAlias];
        [popup selectItemAtIndex:(aliasIndex != NSNotFound) ? aliasIndex + 1 : 0];
    } else {
        [popup selectItemAtIndex:0];
    }
    popup.toolTip = [self mappingSummaryForProfile:profile actionKey:actionKey];
    return popup;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self.petManager setSelectedPetProfile:[self selectedProfile]];
    [self updateButtons];
    [self refreshPetSettings];
}

- (void)handleRuntimeDebugUpdate:(NSNotification *)notification {
    (void)notification;
    PETPetProfile *profile = [self selectedProfile];
    if (profile == nil) {
        return;
    }
    [self refreshCombatDebugPanelForProfile:profile];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    id field = obj.object;
    if (field == self.baseURLField) {
        [self saveConfiguration:nil];
        return;
    }

    if (field == self.nameField) {
        PETPetProfile *profile = [self selectedProfile];
        if (profile != nil) {
            [self.petManager renamePetProfile:profile displayName:self.nameField.stringValue];
        }
    }
}

- (void)reloadStateControlsForProfile:(PETPetProfile *)profile {
    NSArray<NSString *> *states = [self.petManager supportedStatesForPetProfile:profile];
    NSString *currentState = [self.petManager currentStateForPetProfile:profile];

    [self.statePopUpButton removeAllItems];
    for (NSString *state in states) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self localizedTitleForState:state]
                                                      action:nil
                                               keyEquivalent:@""];
        item.representedObject = state;
        [self.statePopUpButton.menu addItem:item];
    }

    NSInteger selectedIndex = [states indexOfObject:currentState];
    if (selectedIndex == NSNotFound) {
        selectedIndex = 0;
    }
    if (selectedIndex != NSNotFound && self.statePopUpButton.numberOfItems > 0) {
        [self.statePopUpButton selectItemAtIndex:selectedIndex];
    }

    self.currentStateLabel.stringValue = [NSString stringWithFormat:@"当前: %@", [self localizedTitleForState:currentState ?: @"-"]];
}

- (NSArray<NSString *> *)interactionActionKeysForProfile:(PETPetProfile *)profile {
    NSMutableArray<NSString *> *keys = [NSMutableArray arrayWithArray:@[
        PETManagerInteractionAmbientIdle,
        PETManagerInteractionTapPrimary,
        PETManagerInteractionTapSecondary,
        PETManagerInteractionTapHead,
        PETManagerInteractionTapTail,
        PETManagerInteractionTapBody,
        PETManagerInteractionDragMoveLeft,
        PETManagerInteractionDragMoveRight,
        PETManagerInteractionDragIdle,
        PETManagerInteractionDragRelease
    ]];

    NSArray<NSString *> *detectedSemanticParts = [profile.metadata[@"detectedSemanticParts"] isKindOfClass:NSArray.class] ? profile.metadata[@"detectedSemanticParts"] : @[];
    for (NSString *semanticPart in detectedSemanticParts) {
        if (![semanticPart isKindOfClass:NSString.class] || semanticPart.length == 0) {
            continue;
        }
        if ([@[@"head", @"tail", @"body"] containsObject:semanticPart.lowercaseString]) {
            continue;
        }
        NSString *actionKey = [PETManagerInteractionTapPartPrefix stringByAppendingString:semanticPart.lowercaseString];
        if (![keys containsObject:actionKey]) {
            [keys addObject:actionKey];
        }
    }
    return keys.copy;
}

- (void)reloadInteractionMappingTableForProfile:(PETPetProfile *)profile {
    self.interactionMappingActionKeys = profile != nil ? [self interactionActionKeysForProfile:profile] : @[];
    [self.interactionMappingTableView reloadData];
}

- (NSString *)mappingSummaryForProfile:(PETPetProfile *)profile actionKey:(NSString *)actionKey {
    NSString *userState = [profile userInteractionAnimationStateForActionKey:actionKey];
    NSString *baseState = [profile baseInteractionAnimationStateForActionKey:actionKey];
    NSString *effectiveState = [profile resolvedInteractionAnimationStateForActionKey:actionKey];
    return [NSString stringWithFormat:@"key: %@\nuser: %@\nbase: %@\neffective: %@",
            actionKey,
            userState.length > 0 ? userState : @"(空)",
            baseState.length > 0 ? baseState : @"(空)",
            effectiveState.length > 0 ? effectiveState : @"(空)"];
}

- (NSString *)localizedTitleForState:(NSString *)state {
    NSDictionary<NSString *, NSString *> *titles = @{
        @"idle": @"待机",
        @"waving": @"挥手",
        @"waiting": @"等待",
        @"review": @"审阅",
        @"jumping": @"跳跃",
        @"jump": @"起跳",
        @"jump-air": @"滞空",
        @"jump-land": @"落地",
        @"failed": @"失败",
        @"running": @"跑动",
        @"running-left": @"左跑",
        @"running-right": @"右跑"
    };
    return titles[state] ?: state;
}

- (NSString *)localizedTitleForInteractionActionKey:(NSString *)actionKey {
    NSDictionary<NSString *, NSString *> *titles = @{
        PETManagerInteractionAmbientIdle: @"待机循环",
        PETManagerInteractionTapPrimary: @"主点击",
        PETManagerInteractionTapSecondary: @"右键点击",
        PETManagerInteractionTapHead: @"点头部",
        PETManagerInteractionTapTail: @"点尾巴",
        PETManagerInteractionTapBody: @"点身体",
        PETManagerInteractionDragMoveLeft: @"左拖移动",
        PETManagerInteractionDragMoveRight: @"右拖移动",
        PETManagerInteractionDragIdle: @"拖拽保持",
        PETManagerInteractionDragRelease: @"拖拽放开"
    };
    if ([actionKey hasPrefix:PETManagerInteractionTapPartPrefix]) {
        NSString *semanticPart = [actionKey substringFromIndex:PETManagerInteractionTapPartPrefix.length];
        return [NSString stringWithFormat:@"点%@",
                [self localizedTitleForSemanticPart:semanticPart]];
    }
    return titles[actionKey] ?: actionKey;
}

- (NSString *)localizedTitleForSemanticPart:(NSString *)semanticPart {
    NSDictionary<NSString *, NSString *> *titles = @{
        @"head": @"头部",
        @"tail": @"尾巴",
        @"body": @"身体",
        @"ear": @"耳朵",
        @"hand": @"手臂",
        @"paw": @"爪子",
        @"leg": @"腿部",
        @"foot": @"脚部",
        @"wing": @"翅膀"
    };
    return titles[semanticPart.lowercaseString] ?: semanticPart;
}

- (void)restoreSelectionWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }

    NSArray<PETPetProfile *> *profiles = self.petManager.activeProfiles;
    NSUInteger index = [profiles indexOfObjectPassingTest:^BOOL(PETPetProfile * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)idx;
        (void)stop;
        return [obj.identifier isEqualToString:identifier];
    }];
    if (index == NSNotFound) {
        return;
    }

    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
}

- (void)refreshCombatDebugPanelForProfile:(PETPetProfile *)profile {
    NSDictionary<NSString *, id> *combat = [self.petManager combatDebugSnapshotForPetProfile:profile];
    NSDictionary<NSString *, id> *activeSkill = [combat[@"activeSkill"] isKindOfClass:NSDictionary.class] ? combat[@"activeSkill"] : nil;
    NSDictionary<NSString *, id> *activeAttack = [combat[@"activeAttack"] isKindOfClass:NSDictionary.class] ? combat[@"activeAttack"] : nil;
    NSArray<NSDictionary<NSString *, id> *> *activeHitWindows = [activeSkill[@"activeHitWindows"] isKindOfClass:NSArray.class] ? activeSkill[@"activeHitWindows"] : @[];
    NSString *combatState = [combat[@"currentState"] isKindOfClass:NSString.class] ? combat[@"currentState"] : @"-";
    NSString *currentAction = [self.petManager currentStateForPetProfile:profile] ?: @"-";
    NSString *skillId = [activeSkill[@"skillId"] isKindOfClass:NSString.class] ? activeSkill[@"skillId"] : @"-";
    NSString *phaseId = [activeSkill[@"currentPhaseId"] isKindOfClass:NSString.class] ? activeSkill[@"currentPhaseId"] : @"-";
    NSString *phaseAnimation = [activeSkill[@"animationState"] isKindOfClass:NSString.class] ? activeSkill[@"animationState"] : @"-";
    NSString *lastTransitionReason = [activeSkill[@"lastTransitionReason"] isKindOfClass:NSString.class] ? activeSkill[@"lastTransitionReason"] : @"-";
    NSString *lastHitWindowId = [activeSkill[@"lastHitWindowId"] isKindOfClass:NSString.class] ? activeSkill[@"lastHitWindowId"] : @"-";
    NSString *lastHitTargetId = [activeSkill[@"lastHitTargetId"] isKindOfClass:NSString.class] ? activeSkill[@"lastHitTargetId"] : @"-";
    NSString *attackKind = [activeAttack[@"attackKind"] isKindOfClass:NSString.class] ? activeAttack[@"attackKind"] : @"-";
    NSNumber *stateTimeRemaining = [combat[@"stateTimeRemaining"] respondsToSelector:@selector(doubleValue)] ? combat[@"stateTimeRemaining"] : nil;
    NSMutableArray<NSString *> *windowSummaries = [NSMutableArray arrayWithCapacity:activeHitWindows.count];
    for (NSDictionary<NSString *, id> *window in activeHitWindows) {
        NSString *windowId = [window[@"windowId"] isKindOfClass:NSString.class] ? window[@"windowId"] : @"window";
        [windowSummaries addObject:windowId];
    }
    NSString *activeWindowsSummary = windowSummaries.count > 0 ? [windowSummaries componentsJoinedByString:@", "] : @"-";
    self.combatDebugLabel.stringValue = [NSString stringWithFormat:@"state: %@\naction: %@\nattack: %@\nskill: %@\nphase: %@\nphaseAnim: %@\nactiveWindows: %@\nlastHit: %@ -> %@\nlastTransition: %@\nremain: %.2fs",
                                         combatState ?: @"-",
                                         currentAction ?: @"-",
                                         attackKind ?: @"-",
                                         skillId ?: @"-",
                                         phaseId ?: @"-",
                                         phaseAnimation ?: @"-",
                                         activeWindowsSummary,
                                         lastHitWindowId ?: @"-",
                                         lastHitTargetId ?: @"-",
                                         lastTransitionReason ?: @"-",
                                         stateTimeRemaining.doubleValue];

    NSDictionary<NSString *, id> *collision = [self.petManager lastCollisionSnapshotForPetProfile:profile];
    NSDictionary<NSString *, id> *screenPoint = [collision[@"screenPoint"] isKindOfClass:NSDictionary.class] ? collision[@"screenPoint"] : nil;
    NSString *sourcePetIdentifier = [collision[@"sourcePetIdentifier"] isKindOfClass:NSString.class] ? collision[@"sourcePetIdentifier"] : @"-";
    NSString *targetPetIdentifier = [collision[@"targetPetIdentifier"] isKindOfClass:NSString.class] ? collision[@"targetPetIdentifier"] : @"-";
    NSString *attackIdentifier = [collision[@"attackIdentifier"] isKindOfClass:NSString.class] ? collision[@"attackIdentifier"] : @"-";
    NSString *attackKindForCollision = [collision[@"attackKind"] isKindOfClass:NSString.class] ? collision[@"attackKind"] : @"-";
    NSNumber *sampleSpacing = [collision[@"sampleSpacing"] respondsToSelector:@selector(doubleValue)] ? collision[@"sampleSpacing"] : nil;
    NSNumber *timestamp = [collision[@"timestamp"] respondsToSelector:@selector(doubleValue)] ? collision[@"timestamp"] : nil;
    if (collision.count == 0) {
        self.collisionDebugLabel.stringValue = @"-";
        return;
    }
    NSString *timeSummary = @"-";
    if (timestamp.doubleValue > 0.0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
        timeSummary = [formatter stringFromDate:date] ?: @"-";
    }
    self.collisionDebugLabel.stringValue = [NSString stringWithFormat:@"source: %@\ntarget: %@\nattack: %@\nkind: %@\npoint: (%.1f, %.1f)\nspacing: %.1f\ntime: %@",
                                            sourcePetIdentifier ?: @"-",
                                            targetPetIdentifier ?: @"-",
                                            attackIdentifier ?: @"-",
                                            attackKindForCollision ?: @"-",
                                            [screenPoint[@"x"] doubleValue],
                                            [screenPoint[@"y"] doubleValue],
                                            sampleSpacing.doubleValue,
                                            timeSummary];
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
    (void)splitView;
    if (dividerIndex == 0) {
        return MAX(proposedMin, 200.0);
    }
    return proposedMin;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex {
    if (dividerIndex != 0) {
        return proposedMax;
    }
    CGFloat total = NSWidth(splitView.bounds);
    if (total < 480.0) {
        return proposedMax;
    }
    CGFloat rightMin = 260.0;
    return MIN(proposedMax, total - rightMin);
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    (void)splitView;
    (void)subview;
    return NO;
}

@end
