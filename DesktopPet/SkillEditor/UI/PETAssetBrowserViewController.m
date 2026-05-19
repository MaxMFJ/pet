#import "PETAssetBrowserViewController.h"

#import "../../Managers/PETPetManager.h"
#import "../../Models/PETPetProfile.h"
#import "../../Services/PETSpineRuntime.h"
#import "../Preview/PETFXAssetCatalog.h"

@interface PETAssetBrowserViewController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) PETPetManager *petManager;
@property (nonatomic, copy) NSArray<PETPetProfile *> *spineProfiles;
@property (nonatomic, strong) NSTableView *profileTableView;
@property (nonatomic, strong) NSTableView *animationTableView;
@property (nonatomic, strong) NSTableView *fxTableView;
@property (nonatomic, copy) NSArray<NSString *> *animationNames;
@property (nonatomic, copy) NSArray<NSString *> *fxAssetNames;
@property (nonatomic, strong) NSSearchField *searchField;

@end

@implementation PETAssetBrowserViewController

- (instancetype)initWithPetManager:(PETPetManager *)petManager {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _petManager = petManager;
    }
    return self;
}

- (void)loadView {
    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 260, 600)];
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;

    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    self.searchField.placeholderString = @"Search";
    self.searchField.target = self;
    self.searchField.action = @selector(reloadProfiles);

    self.profileTableView = [self tableViewWithIdentifier:@"Profiles"];
    self.animationTableView = [self tableViewWithIdentifier:@"Animations"];
    self.fxTableView = [self tableViewWithIdentifier:@"FX"];

    NSView *profileContainer = [self containerWithTitle:@"Spine Characters" tableView:self.profileTableView accessory:self.searchField];
    NSView *animationContainer = [self containerWithTitle:@"Animations" tableView:self.animationTableView accessory:nil];
    NSView *fxContainer = [self containerWithTitle:@"FX Assets" tableView:self.fxTableView accessory:nil];

    [splitView addSubview:profileContainer];
    [splitView addSubview:animationContainer];
    [splitView addSubview:fxContainer];
    [splitView adjustSubviews];
    [splitView setPosition:220 ofDividerAtIndex:0];
    [splitView setPosition:420 ofDividerAtIndex:1];

    self.view = splitView;
    self.fxAssetNames = [PETFXAssetCatalog.sharedCatalog availableAssetNames];
    [self.fxTableView reloadData];
    [self reloadProfiles];
}

- (NSTableView *)tableViewWithIdentifier:(NSString *)identifier {
    NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 260, 200)];
    tableView.headerView = nil;
    tableView.usesAlternatingRowBackgroundColors = YES;
    tableView.identifier = identifier;
    tableView.dataSource = self;
    tableView.delegate = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    column.width = 240;
    [tableView addTableColumn:column];
    return tableView;
}

- (NSView *)containerWithTitle:(NSString *)title tableView:(NSTableView *)tableView accessory:(nullable NSView *)accessory {
    NSView *container = [[NSView alloc] initWithFrame:tableView.frame];
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:12];
    label.frame = NSMakeRect(8, container.bounds.size.height - 22, 220, 18);
    label.autoresizingMask = NSViewMinYMargin;
    [container addSubview:label];

    CGFloat top = container.bounds.size.height - 28;
    if (accessory != nil) {
        accessory.frame = NSMakeRect(8, top - 26, container.bounds.size.width - 16, 24);
        accessory.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [container addSubview:accessory];
        top -= 30;
    }

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, container.bounds.size.width, top)];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.documentView = tableView;
    [container addSubview:scrollView];
    return container;
}

- (void)reloadProfiles {
    NSString *query = self.searchField.stringValue.lowercaseString;
    NSMutableArray<PETPetProfile *> *profiles = [NSMutableArray array];
    for (PETPetProfile *profile in self.petManager.activeProfiles) {
        if (!profile.usesSpineRuntime) {
            continue;
        }
        if (query.length > 0) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@", profile.displayName, profile.identifier].lowercaseString;
            if ([haystack rangeOfString:query].location == NSNotFound) {
                continue;
            }
        }
        [profiles addObject:profile];
    }
    self.spineProfiles = profiles.copy;
    [self.profileTableView reloadData];
    if (self.spineProfiles.count > 0 && self.selectedProfile == nil) {
        [self.profileTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.profileTableView]];
    }
}

- (void)reloadAnimationsForSelectedProfile {
    self.animationNames = @[];
    PETPetProfile *profile = self.selectedProfile;
    if (profile == nil) {
        [self.animationTableView reloadData];
        return;
    }
    NSString *atlasPath = [profile.metadata[@"atlasPath"] isKindOfClass:NSString.class] ? profile.metadata[@"atlasPath"] : @"";
    NSURL *atlasURL = atlasPath.length > 0 ? [NSURL fileURLWithPath:atlasPath] : nil;
    NSError *error = nil;
    PETSpineRuntime *runtime = atlasURL != nil ? [[PETSpineRuntime alloc] initWithJSONURL:profile.sourceURL
                                                                                atlasURL:atlasURL
                                                                                   error:&error] : nil;
    if (runtime != nil) {
        self.animationNames = runtime.animationNames ?: @[];
    } else {
        self.animationNames = profile.supportedStates ?: @[];
    }
    [self.animationTableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.profileTableView) {
        return self.spineProfiles.count;
    }
    if (tableView == self.fxTableView) {
        return self.fxAssetNames.count;
    }
    return self.animationNames.count;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.profileTableView) {
        PETPetProfile *profile = self.spineProfiles[(NSUInteger)row];
        return profile.displayName.length > 0 ? profile.displayName : profile.identifier;
    }
    if (tableView == self.fxTableView) {
        return self.fxAssetNames[(NSUInteger)row];
    }
    return self.animationNames[(NSUInteger)row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView == self.profileTableView) {
        NSInteger row = tableView.selectedRow;
        if (row < 0 || row >= (NSInteger)self.spineProfiles.count) {
            return;
        }
        self.selectedProfile = self.spineProfiles[(NSUInteger)row];
        [self reloadAnimationsForSelectedProfile];
        if ([self.browserDelegate respondsToSelector:@selector(assetBrowserDidSelectProfile:)]) {
            [self.browserDelegate assetBrowserDidSelectProfile:self.selectedProfile];
        }
        return;
    }

    if (tableView == self.animationTableView) {
        NSInteger row = self.animationTableView.selectedRow;
        if (row < 0 || row >= (NSInteger)self.animationNames.count) {
            return;
        }
        NSString *animation = self.animationNames[(NSUInteger)row];
        if ([self.browserDelegate respondsToSelector:@selector(assetBrowserDidSelectAnimation:)]) {
            [self.browserDelegate assetBrowserDidSelectAnimation:animation];
        }
        return;
    }

    if (tableView == self.fxTableView) {
        NSInteger row = self.fxTableView.selectedRow;
        if (row < 0 || row >= (NSInteger)self.fxAssetNames.count) {
            return;
        }
        NSString *asset = self.fxAssetNames[(NSUInteger)row];
        if ([self.browserDelegate respondsToSelector:@selector(assetBrowserDidSelectFXAsset:)]) {
            [self.browserDelegate assetBrowserDidSelectFXAsset:asset];
        }
    }
}

@end
