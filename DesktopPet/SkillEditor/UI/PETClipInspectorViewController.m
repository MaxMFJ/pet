#import "PETClipInspectorViewController.h"

#import <objc/runtime.h>

#import "../../Services/PETSpineRuntime.h"
#import "../../UI/PETSpineMetalView.h"
#import "../Model/PETSkillTimelineClip.h"
#import "../Model/PETSkillTimelineDocument.h"
#import "../Model/PETSkillTimelineEnums.h"
#import "../Preview/PETFXAssetCatalog.h"
#import "../Spine/PETSpineSocketRegistry.h"

@interface PETClipInspectorViewController ()

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong, nullable) PETSkillTimelineClip *clip;
@property (nonatomic, copy) NSArray<NSString *> *boneNames;
@property (nonatomic, copy) NSArray<NSString *> *fxAssetNames;
@property (nonatomic, weak, nullable) PETSpineMetalView *spineView;
@property (nonatomic, copy) NSString *profileId;

@end

static const void *PETClipInspectorPayloadKeyAssociation = &PETClipInspectorPayloadKeyAssociation;

@implementation PETClipInspectorViewController

- (void)attachPayloadKey:(NSString *)key toControl:(id)control {
    objc_setAssociatedObject(control, PETClipInspectorPayloadKeyAssociation, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)payloadKeyForControl:(id)control {
    return objc_getAssociatedObject(control, PETClipInspectorPayloadKeyAssociation);
}

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 600)];
    self.scrollView = [[NSScrollView alloc] initWithFrame:container.bounds];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;

    self.stackView = [NSStackView stackViewWithViews:@[]];
    self.stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stackView.alignment = NSLayoutAttributeLeading;
    self.stackView.spacing = 8;
    self.stackView.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *documentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
    [documentView addSubview:self.stackView];
    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [self.stackView.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [self.stackView.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [self.stackView.bottomAnchor constraintLessThanOrEqualToAnchor:documentView.bottomAnchor]
    ]];
    self.scrollView.documentView = documentView;
    [container addSubview:self.scrollView];
    self.view = container;
    [self displayClip:nil];
}

- (void)setSpineViewForBoneChoices:(PETSpineMetalView *)spineView profileId:(NSString *)profileId {
    self.spineView = spineView;
    self.profileId = profileId ?: @"";
    [self reloadBoneAndAssetChoices];
}

- (void)reloadBoneAndAssetChoices {
    NSMutableOrderedSet<NSString *> *socketNames = [[NSMutableOrderedSet alloc] init];
    for (NSString *socket in [PETSpineSocketRegistry.sharedRegistry socketNamesForProfileId:self.profileId]) {
        [socketNames addObject:socket];
    }
    if (self.spineView.spineRuntime != nil) {
        for (NSString *bone in self.spineView.spineRuntime.boneNames) {
            [socketNames addObject:bone];
        }
    }
    if (socketNames.count == 0) {
        [socketNames addObject:@"root"];
    }
    self.boneNames = socketNames.array;
    self.fxAssetNames = [PETFXAssetCatalog.sharedCatalog availableAssetNames];
    if (self.clip != nil) {
        [self displayClip:self.clip];
    }
}

- (void)displayClip:(PETSkillTimelineClip *)clip {
    self.clip = clip;
    for (NSView *view in self.stackView.arrangedSubviews.copy) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    [self.stackView addArrangedSubview:[self sectionLabel:@"Clip Inspector"]];
    if (clip == nil) {
        [self.stackView addArrangedSubview:[self hintLabel:@"Select a clip on the timeline"]];
        return;
    }

    [self.stackView addArrangedSubview:[self hintLabel:[NSString stringWithFormat:@"%@ · %@", PETSkillTimelineStringFromTrackType(clip.trackType), clip.clipIdentifier]]];
    [self addNumberField:@"Start" value:clip.startTime action:@selector(startTimeChanged:)];
    if (clip.clipKind == PETSkillTimelineClipKindSpan) {
        [self addNumberField:@"End" value:clip.endTime action:@selector(endTimeChanged:)];
    }

    switch (clip.trackType) {
        case PETSkillTimelineTrackTypeFX:
            [self buildFXFields:clip];
            break;
        case PETSkillTimelineTrackTypeHitbox:
            [self buildHitboxFields:clip];
            break;
        case PETSkillTimelineTrackTypeCharacter:
            [self buildCharacterFields:clip];
            break;
        case PETSkillTimelineTrackTypeShader:
            [self buildShaderFields:clip];
            break;
        case PETSkillTimelineTrackTypeEvent:
            [self buildEventFields:clip];
            break;
    }
}

#pragma mark - Field builders

- (void)buildFXFields:(PETSkillTimelineClip *)clip {
    NSDictionary *payload = clip.payload ?: @{};
    [self addPopUpField:@"Asset" options:self.fxAssetNames.count > 0 ? self.fxAssetNames : @[@"slash_fx"] selected:[payload[@"asset"] isKindOfClass:NSString.class] ? payload[@"asset"] : @"slash_fx" action:@selector(textPayloadChanged:)];
    [self addPopUpField:@"Socket" options:self.boneNames selected:[payload[@"socket"] isKindOfClass:NSString.class] ? payload[@"socket"] : @"root" action:@selector(textPayloadChanged:)];
    [self addNumberField:@"Offset X" value:[payload[@"offsetX"] doubleValue] action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Offset Y" value:[payload[@"offsetY"] doubleValue] action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Rotation" value:[payload[@"rotation"] doubleValue] action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Scale" value:[payload[@"scale"] doubleValue] ?: 1.0 action:@selector(numberPayloadChanged:)];
    [self addPopUpField:@"Blend" options:@[@"alpha", @"additive", @"multiply"] selected:[payload[@"blendMode"] isKindOfClass:NSString.class] ? payload[@"blendMode"] : @"additive" action:@selector(textPayloadChanged:)];
    [self addCheckbox:@"Flip X" checked:[payload[@"flipX"] boolValue] action:@selector(boolPayloadChanged:)];
}

- (void)buildHitboxFields:(PETSkillTimelineClip *)clip {
    NSDictionary *payload = clip.payload ?: @{};
    [self addPopUpField:@"Shape" options:@[@"rect", @"circle", @"capsule"] selected:[payload[@"shape"] isKindOfClass:NSString.class] ? payload[@"shape"] : @"rect" action:@selector(textPayloadChanged:)];
    [self addPopUpField:@"Socket" options:self.boneNames selected:[payload[@"socket"] isKindOfClass:NSString.class] ? payload[@"socket"] : @"root" action:@selector(textPayloadChanged:)];
    [self addNumberField:@"X" value:[payload[@"x"] doubleValue] action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Y" value:[payload[@"y"] doubleValue] action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Width" value:[payload[@"width"] doubleValue] ?: 100 action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Height" value:[payload[@"height"] doubleValue] ?: 50 action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Radius" value:[payload[@"radius"] doubleValue] action:@selector(numberPayloadChanged:)];
    [self addNumberField:@"Damage" value:[payload[@"damage"] doubleValue] ?: 100 action:@selector(numberPayloadChanged:)];
    [self addTextField:@"Window ID" value:[payload[@"windowId"] isKindOfClass:NSString.class] ? payload[@"windowId"] : @"" action:@selector(textPayloadChanged:)];
    [self addTextField:@"Reaction ID" value:[payload[@"reactionId"] isKindOfClass:NSString.class] ? payload[@"reactionId"] : @"hit_stun_light" action:@selector(textPayloadChanged:)];
}

- (void)buildCharacterFields:(PETSkillTimelineClip *)clip {
    NSDictionary *payload = clip.payload ?: @{};
    NSArray<NSString *> *animations = self.spineView.spineRuntime.animationNames ?: @[@"idle"];
    [self addPopUpField:@"Animation" options:animations selected:[payload[@"animation"] isKindOfClass:NSString.class] ? payload[@"animation"] : @"idle" action:@selector(textPayloadChanged:)];
    [self addCheckbox:@"Loop" checked:[payload[@"loop"] boolValue] action:@selector(boolPayloadChanged:)];
}

- (void)buildShaderFields:(PETSkillTimelineClip *)clip {
    NSDictionary *payload = clip.payload ?: @{};
    [self addTextField:@"Shader" value:[payload[@"shader"] isKindOfClass:NSString.class] ? payload[@"shader"] : @"glow" action:@selector(textPayloadChanged:)];
}

- (void)buildEventFields:(PETSkillTimelineClip *)clip {
    NSDictionary *payload = clip.payload ?: @{};
    [self addPopUpField:@"Event" options:@[@"cameraShake", @"playSound", @"freezeFrame", @"spawnProjectile"] selected:[payload[@"eventType"] isKindOfClass:NSString.class] ? payload[@"eventType"] : @"cameraShake" action:@selector(textPayloadChanged:)];
}

#pragma mark - UI helpers

- (NSTextField *)sectionLabel:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:13];
    return label;
}

- (NSTextField *)hintLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.textColor = NSColor.secondaryLabelColor;
    label.font = [NSFont systemFontOfSize:11];
    label.maximumNumberOfLines = 0;
    label.preferredMaxLayoutWidth = 200;
    return label;
}

- (void)addTextField:(NSString *)label value:(NSString *)value action:(SEL)action {
    [self.stackView addArrangedSubview:[self labeledRow:label control:[self editableField:value action:action tag:label]]];
}

- (void)addNumberField:(NSString *)label value:(double)value action:(SEL)action {
    NSTextField *field = [self editableField:[NSString stringWithFormat:@"%.3f", value] action:action tag:label];
    field.formatter = [[NSNumberFormatter alloc] init];
    [self.stackView addArrangedSubview:[self labeledRow:label control:field]];
}

- (void)addPopUpField:(NSString *)label options:(NSArray<NSString *> *)options selected:(NSString *)selected action:(SEL)action {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 140, 24) pullsDown:NO];
    [popup addItemsWithTitles:options.count > 0 ? options : @[@"-" ]];
    popup.target = self;
    popup.action = action;
    [self attachPayloadKey:label toControl:popup];
    NSInteger index = [options indexOfObject:selected];
    if (index != NSNotFound) {
        [popup selectItemAtIndex:index];
    }
    [self.stackView addArrangedSubview:[self labeledRow:label control:popup]];
}

- (void)addCheckbox:(NSString *)label checked:(BOOL)checked action:(SEL)action {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 140, 24)];
    checkbox.buttonType = NSButtonTypeSwitch;
    checkbox.title = label;
    checkbox.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
    checkbox.target = self;
    checkbox.action = action;
    [self attachPayloadKey:label toControl:checkbox];
    [self.stackView addArrangedSubview:checkbox];
}

- (NSView *)labeledRow:(NSString *)label control:(NSControl *)control {
    NSTextField *title = [NSTextField labelWithString:label];
    title.font = [NSFont systemFontOfSize:11];
    title.textColor = NSColor.secondaryLabelColor;
    NSStackView *row = [NSStackView stackViewWithViews:@[title, control]];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    row.spacing = 2;
    return row;
}

- (NSTextField *)editableField:(NSString *)value action:(SEL)action tag:(NSString *)tag {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
    field.stringValue = value ?: @"";
    field.target = self;
    field.action = action;
    [self attachPayloadKey:tag toControl:field];
    return field;
}

#pragma mark - Actions

- (void)startTimeChanged:(NSTextField *)sender {
    if (self.clip == nil || self.document == nil) {
        return;
    }
    self.clip.startTime = MAX(0.0, sender.doubleValue);
    if (self.clip.endTime < self.clip.startTime) {
        self.clip.endTime = self.clip.startTime + (1.0 / 60.0);
    }
    [self notifyTimingChange];
}

- (void)endTimeChanged:(NSTextField *)sender {
    if (self.clip == nil) {
        return;
    }
    self.clip.endTime = MAX(self.clip.startTime + (1.0 / 60.0), sender.doubleValue);
    [self notifyTimingChange];
}

- (void)textPayloadChanged:(id)sender {
    if (self.clip == nil) {
        return;
    }
    NSString *key = [self resolvedPayloadKeyForControl:sender];
    if (key.length == 0) {
        return;
    }
    NSMutableDictionary *payload = [self.clip.payload mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([sender isKindOfClass:NSPopUpButton.class]) {
        payload[key] = [(NSPopUpButton *)sender titleOfSelectedItem] ?: @"";
    } else if ([sender isKindOfClass:NSTextField.class]) {
        payload[key] = [(NSTextField *)sender stringValue] ?: @"";
    }
    self.clip.payload = payload.copy;
    [self notifyPayloadChange];
}

- (void)numberPayloadChanged:(NSTextField *)sender {
    if (self.clip == nil) {
        return;
    }
    NSString *key = [self resolvedPayloadKeyForControl:sender];
    if (key.length == 0) {
        return;
    }
    NSMutableDictionary *payload = [self.clip.payload mutableCopy] ?: [NSMutableDictionary dictionary];
    payload[key] = @(sender.doubleValue);
    self.clip.payload = payload.copy;
    [self notifyPayloadChange];
}

- (void)boolPayloadChanged:(NSButton *)sender {
    if (self.clip == nil) {
        return;
    }
    NSString *key = [self resolvedPayloadKeyForControl:sender];
    if (key.length == 0) {
        return;
    }
    NSMutableDictionary *payload = [self.clip.payload mutableCopy] ?: [NSMutableDictionary dictionary];
    payload[key] = @(sender.state == NSControlStateValueOn);
    self.clip.payload = payload.copy;
    [self notifyPayloadChange];
}

- (NSString *)resolvedPayloadKeyForControl:(id)sender {
    NSString *label = [self payloadKeyForControl:sender];
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"Asset": @"asset",
            @"Socket": @"socket",
            @"Offset X": @"offsetX",
            @"Offset Y": @"offsetY",
            @"Rotation": @"rotation",
            @"Scale": @"scale",
            @"Blend": @"blendMode",
            @"Flip X": @"flipX",
            @"Shape": @"shape",
            @"X": @"x",
            @"Y": @"y",
            @"Width": @"width",
            @"Height": @"height",
            @"Radius": @"radius",
            @"Damage": @"damage",
            @"Window ID": @"windowId",
            @"Reaction ID": @"reactionId",
            @"Animation": @"animation",
            @"Loop": @"loop",
            @"Shader": @"shader",
            @"Event": @"eventType"
        };
    });
    return map[label] ?: label.lowercaseString;
}

- (void)notifyPayloadChange {
    [self.document notifyChanged];
    if ([self.inspectorDelegate respondsToSelector:@selector(clipInspectorDidUpdateClip:)]) {
        [self.inspectorDelegate clipInspectorDidUpdateClip:self.clip];
    }
}

- (void)notifyTimingChange {
    [self.document notifyChanged];
    if ([self.inspectorDelegate respondsToSelector:@selector(clipInspectorDidChangeClipTiming:)]) {
        [self.inspectorDelegate clipInspectorDidChangeClipTiming:self.clip];
    }
}

@end
