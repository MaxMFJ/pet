#import "PETManagerViewController.h"

#import "../Config/PETAppConfig.h"
#import "../Managers/PETAssetImportManager.h"
#import "../Managers/PETPetManager.h"
#import "../Models/PETPetProfile.h"

@interface PETManagerViewController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

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
@property (nonatomic, strong) NSPopUpButton *statePopUpButton;
@property (nonatomic, strong) NSButton *previewStateButton;
@property (nonatomic, strong) NSButton *resumeAmbientButton;
@property (nonatomic, strong) NSTextField *currentStateLabel;
@property (nonatomic, strong) NSTableView *interactionMappingTableView;
@property (nonatomic, copy) NSArray<NSString *> *interactionMappingActionKeys;

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
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 940, 560)];
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

    NSTextField *titleLabel = [self labelWithString:@"Desktop Pet Manager" font:[NSFont boldSystemFontOfSize:24.0]];
    [rootStack addArrangedSubview:titleLabel];

    NSTextField *subtitleLabel = [self labelWithString:@"管理宠物显示状态，优先导入 Codex 标准宠物包，并配置 AI BaseURL。" font:[NSFont systemFontOfSize:13.0]];
    subtitleLabel.textColor = NSColor.secondaryLabelColor;
    [rootStack addArrangedSubview:subtitleLabel];

    NSGridView *settingsGrid = [self buildSettingsGrid];
    [rootStack addArrangedSubview:settingsGrid];

    NSStackView *toolbar = [self buildToolbar];
    [rootStack addArrangedSubview:toolbar];

    NSScrollView *tableScrollView = [self buildTableView];
    [rootStack addArrangedSubview:tableScrollView];

    NSGridView *petSettingsGrid = [self buildPetSettingsGrid];
    [rootStack addArrangedSubview:petSettingsGrid];

    self.petCountLabel = [self labelWithString:@"" font:[NSFont systemFontOfSize:12.0]];
    self.petCountLabel.textColor = NSColor.secondaryLabelColor;
    [rootStack addArrangedSubview:self.petCountLabel];

    [tableScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:280.0].active = YES;
    [self reloadPetList];
}

- (NSGridView *)buildSettingsGrid {
    NSTextField *baseURLLabel = [self labelWithString:@"BaseURL" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]];
    self.baseURLField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.baseURLField.stringValue = self.configuration.aiBaseURLString ?: @"";
    self.baseURLField.placeholderString = @"https://api.openai.com/v1";
    self.baseURLField.delegate = self;

    NSButton *saveButton = [NSButton buttonWithTitle:@"保存配置" target:self action:@selector(saveConfiguration:)];
    saveButton.bezelStyle = NSBezelStyleRounded;

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
    addButton.bezelStyle = NSBezelStyleRounded;

    NSButton *spineToolButton = [NSButton buttonWithTitle:@"Spine 工具" target:self action:@selector(openSpineTool:)];
    spineToolButton.bezelStyle = NSBezelStyleRounded;

    self.toggleVisibilityButton = [NSButton buttonWithTitle:@"隐藏宠物" target:self action:@selector(toggleSelectedPetVisibility:)];
    self.toggleVisibilityButton.bezelStyle = NSBezelStyleRounded;

    self.removeButton = [NSButton buttonWithTitle:@"删除宠物" target:self action:@selector(removeSelectedPet:)];
    self.removeButton.bezelStyle = NSBezelStyleRounded;

    NSButton *showAllButton = [NSButton buttonWithTitle:@"全部显示" target:self action:@selector(showAllPets:)];
    showAllButton.bezelStyle = NSBezelStyleRounded;

    NSButton *hideAllButton = [NSButton buttonWithTitle:@"全部隐藏" target:self action:@selector(hideAllPets:)];
    hideAllButton.bezelStyle = NSBezelStyleRounded;

    NSStackView *toolbar = [[NSStackView alloc] initWithFrame:NSZeroRect];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 10.0;
    [toolbar addArrangedSubview:addButton];
    [toolbar addArrangedSubview:spineToolButton];
    [toolbar addArrangedSubview:self.toggleVisibilityButton];
    [toolbar addArrangedSubview:self.removeButton];
    [toolbar addArrangedSubview:showAllButton];
    [toolbar addArrangedSubview:hideAllButton];
    return toolbar;
}

- (NSGridView *)buildPetSettingsGrid {
    NSTextField *sectionLabel = [self labelWithString:@"当前宠物设置" font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];

    self.nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.nameField.placeholderString = @"Pet Name";
    self.nameField.delegate = self;

    self.scaleSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    self.scaleSlider.minValue = 0.01;
    self.scaleSlider.maxValue = 3.0;
    self.scaleSlider.doubleValue = 1.0;
    self.scaleSlider.target = self;
    self.scaleSlider.action = @selector(scaleChanged:);

    self.scaleValueLabel = [self labelWithString:@"100%" font:[NSFont systemFontOfSize:12.0]];
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
    self.statePopUpButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.previewStateButton = [NSButton buttonWithTitle:@"预览动作" target:self action:@selector(previewSelectedState:)];
    self.previewStateButton.bezelStyle = NSBezelStyleRounded;
    self.resumeAmbientButton = [NSButton buttonWithTitle:@"恢复待机" target:self action:@selector(resumeAmbientState:)];
    self.resumeAmbientButton.bezelStyle = NSBezelStyleRounded;
    self.currentStateLabel = [self labelWithString:@"当前: idle" font:[NSFont systemFontOfSize:12.0]];
    self.currentStateLabel.textColor = NSColor.secondaryLabelColor;

    self.interactionMappingTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.interactionMappingTableView.delegate = self;
    self.interactionMappingTableView.dataSource = self;
    self.interactionMappingTableView.headerView = nil;
    self.interactionMappingTableView.allowsEmptySelection = YES;
    self.interactionMappingTableView.rowHeight = 30.0;

    NSTableColumn *mappingKeyColumn = [[NSTableColumn alloc] initWithIdentifier:@"mappingKey"];
    mappingKeyColumn.width = 320.0;
    mappingKeyColumn.minWidth = 280.0;
    NSTableColumn *mappingValueColumn = [[NSTableColumn alloc] initWithIdentifier:@"mappingValue"];
    mappingValueColumn.width = 360.0;
    mappingValueColumn.minWidth = 320.0;
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
        @[sectionLabel, [NSView new], [NSView new]],
        @[[self labelWithString:@"名称" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.nameField, [NSView new]],
        @[[self labelWithString:@"缩放" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.scaleSlider, self.scaleValueLabel],
        @[[self labelWithString:@"朝向" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.facingDirectionControl, [NSView new]],
        @[[self labelWithString:@"交互" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.clickThroughCheckbox, [NSView new]],
        @[[self labelWithString:@"动作" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.statePopUpButton, self.previewStateButton],
        @[[self labelWithString:@"交互映射" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], interactionMappingScrollView, [NSView new]],
        @[[self labelWithString:@"状态" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]], self.currentStateLabel, self.resumeAmbientButton]
    ]];
    grid.rowSpacing = 10.0;
    grid.columnSpacing = 12.0;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    [[grid columnAtIndex:1] setWidth:700.0];
    return grid;
}

- (NSScrollView *)buildTableView {
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.headerView = nil;
    self.tableView.allowsEmptySelection = YES;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.rowHeight = 34.0;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Name";
    nameColumn.width = 180.0;

    NSTableColumn *statusColumn = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    statusColumn.title = @"Status";
    statusColumn.width = 90.0;

    NSTableColumn *sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"source"];
    sourceColumn.title = @"Source";
    sourceColumn.width = 420.0;

    [self.tableView addTableColumn:nameColumn];
    [self.tableView addTableColumn:statusColumn];
    [self.tableView addTableColumn:sourceColumn];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.documentView = self.tableView;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    return scrollView;
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (void)reloadPetList {
    NSString *selectedIdentifier = [self selectedProfile].identifier;
    [self.tableView reloadData];
    [self restoreSelectionWithIdentifier:selectedIdentifier];
    self.petCountLabel.stringValue = [NSString stringWithFormat:@"当前宠物: %lu / %ld",
                                      (unsigned long)self.petManager.activeProfiles.count,
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
        return;
    }

    BOOL isVisible = [self.petManager isPetVisible:selectedProfile];
    self.toggleVisibilityButton.title = isVisible ? @"隐藏宠物" : @"显示宠物";
}

- (void)refreshPetSettings {
    PETPetProfile *selectedProfile = [self selectedProfile];
    BOOL hasSelection = (selectedProfile != nil);

    self.nameField.enabled = hasSelection;
    self.scaleSlider.enabled = hasSelection;
    self.facingDirectionControl.enabled = hasSelection;
    self.clickThroughCheckbox.enabled = hasSelection;
    self.statePopUpButton.enabled = hasSelection;
    self.previewStateButton.enabled = hasSelection;
    self.resumeAmbientButton.enabled = hasSelection;
    self.interactionMappingTableView.enabled = hasSelection;

    if (!hasSelection) {
        self.nameField.stringValue = @"";
        self.scaleSlider.doubleValue = 1.0;
        self.scaleValueLabel.stringValue = @"100%";
        self.facingDirectionControl.selectedSegment = 1;
        self.clickThroughCheckbox.state = NSControlStateValueOff;
        [self.statePopUpButton removeAllItems];
        self.interactionMappingActionKeys = @[];
        [self.interactionMappingTableView reloadData];
        [self.currentStateLabel setStringValue:@"当前: -"];
        return;
    }

    self.nameField.stringValue = selectedProfile.displayName ?: @"";
    CGFloat scale = [self.petManager scaleForPetProfile:selectedProfile];
    self.scaleSlider.doubleValue = scale;
    self.scaleValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", scale * 100.0];
    self.facingDirectionControl.selectedSegment = [self.petManager isFacingRightForPetProfile:selectedProfile] ? 1 : 0;
    self.clickThroughCheckbox.state = [self.petManager isClickThroughEnabledForPetProfile:selectedProfile] ? NSControlStateValueOn : NSControlStateValueOff;
    [self reloadStateControlsForProfile:selectedProfile];
    [self reloadInteractionMappingTableForProfile:selectedProfile];
    self.currentStateLabel.stringValue = [self.petManager characterRuntimeSummaryForPetProfile:selectedProfile];
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
    [self updateButtons];
    [self refreshPetSettings];
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

@end
