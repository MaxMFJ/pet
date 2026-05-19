#import "PETAnimationSourceLoader.h"

#import <ImageIO/ImageIO.h>

#import "../Config/PETPlatformCompatibility.h"
#import "../Models/PETAnimationFrame.h"
#import "../Models/PETPetProfile.h"
#import "PETPetAssetLoader.h"

static NSTimeInterval const PETDefaultSequenceFrameDuration = 1.0 / 12.0;
static NSString * const PETBehaviorStateIdle = @"idle";
static NSString * const PETBehaviorStateWaving = @"waving";
static NSString * const PETBehaviorStateWaiting = @"waiting";
static NSString * const PETBehaviorStateReview = @"review";
static NSString * const PETBehaviorStateJumping = @"jumping";
static NSString * const PETBehaviorStateRunningLeft = @"running-left";
static NSString * const PETBehaviorStateRunningRight = @"running-right";
static NSString * const PETActionAmbientIdle = @"ambient.idle";
static NSString * const PETActionTapPrimary = @"tap.primary";
static NSString * const PETActionTapSecondary = @"tap.secondary";
static NSString * const PETActionTapHead = @"tap.head";
static NSString * const PETActionTapTail = @"tap.tail";
static NSString * const PETActionTapBody = @"tap.body";
static NSString * const PETActionTapPartPrefix = @"tap.part.";
static NSString * const PETActionDragMoveLeft = @"drag.move.left";
static NSString * const PETActionDragMoveRight = @"drag.move.right";
static NSString * const PETActionDragIdle = @"drag.idle";
static NSString * const PETActionDragRelease = @"drag.release";

@interface PETAnimationSourceLoader ()

@property (nonatomic, strong) PETPetAssetLoader *petAssetLoader;

@end

@implementation PETAnimationSourceLoader

- (instancetype)init {
    self = [super init];
    if (self) {
        _petAssetLoader = [[PETPetAssetLoader alloc] init];
    }
    return self;
}

- (PETPetProfile *)loadAnimationSourceAtURL:(NSURL *)fileURL error:(NSError **)error {
    if ([self isDirectoryURL:fileURL]) {
        NSURL *spineJSONURL = [self spineRuntimeJSONURLInDirectory:fileURL];
        if (spineJSONURL != nil) {
            PETPetProfile *profile = [self loadSpineRuntimeProfileFromJSONURL:spineJSONURL error:error];
            if (profile != nil) {
                return profile;
            }
        }
    }

    if ([self isSpineRuntimeJSONURL:fileURL]) {
        PETPetProfile *profile = [self loadSpineRuntimeProfileFromJSONURL:fileURL error:error];
        if (profile != nil) {
            return profile;
        }
    }

    if ([self packageManifestExistsAtURL:fileURL] || [self isDirectlySupportedAssetURL:fileURL]) {
        PETPetProfile *profile = [self.petAssetLoader loadPetProfileAtURL:fileURL error:error];
        if (profile != nil) {
            return profile;
        }
    }

    if ([self isDirectoryURL:fileURL]) {
        PETPetProfile *directoryProfile = [self loadProfileFromSequenceDirectory:fileURL error:error];
        if (directoryProfile != nil) {
            return directoryProfile;
        }
    }

    NSString *extension = fileURL.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"json"] || [extension isEqualToString:@"skel"] || [extension isEqualToString:@"atlas"]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7102
                                     userInfo:@{NSLocalizedDescriptionKey: @"Raw Spine runtime files are not parsed yet. For now, choose a pet package, animated image, or a folder of per-animation image sequences."}];
        }
        return nil;
    }

    if (error != NULL) {
        *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                     code:7101
                                 userInfo:@{NSLocalizedDescriptionKey: @"Supported inputs: pet package folder, pet.json, spritesheet.webp, animated WEBP/GIF, or a directory containing animation image sequences."}];
    }
    return nil;
}

- (PETPetProfile *)loadProfileFromSequenceDirectory:(NSURL *)directoryURL error:(NSError **)error {
    NSArray<NSURL *> *childURLs = [self visibleChildURLsAtDirectoryURL:directoryURL];
    if (childURLs.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7103
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected folder is empty."}];
        }
        return nil;
    }

    NSMutableDictionary<NSString *, NSArray<PETAnimationFrame *> *> *clips = [NSMutableDictionary dictionary];
    PETPlatformSize maxCanvasSize = CGSizeZero;

    NSArray<NSURL *> *subdirectories = [self directoryURLsFromURLs:childURLs];
    if (subdirectories.count > 0) {
        for (NSURL *subdirectoryURL in subdirectories) {
            NSArray<PETAnimationFrame *> *frames = [self framesFromImageDirectoryURL:subdirectoryURL canvasSize:&maxCanvasSize];
            if (frames.count == 0) {
                continue;
            }

            NSString *state = subdirectoryURL.lastPathComponent.length > 0 ? subdirectoryURL.lastPathComponent : @"animation";
            clips[state] = frames;
        }
    } else {
        NSDictionary<NSString *, NSArray<NSURL *> *> *groupedFiles = [self groupedImageFilesFromURLs:childURLs];
        NSArray<NSString *> *sortedKeys = [[groupedFiles allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *state in sortedKeys) {
            NSArray<PETAnimationFrame *> *frames = [self framesFromImageURLs:groupedFiles[state] canvasSize:&maxCanvasSize];
            if (frames.count > 0) {
                clips[state] = frames;
            }
        }
    }

    if (clips.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7104
                                     userInfo:@{NSLocalizedDescriptionKey: @"No readable animation frames were found. Try a folder whose subfolders are animation names and whose contents are ordered PNG files."}];
        }
        return nil;
    }

    NSString *defaultState = [[[clips allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] firstObject] ?: @"idle";
    return [[PETPetProfile alloc] initWithDisplayName:directoryURL.lastPathComponent ?: @"Animation Source"
                                            sourceURL:directoryURL
                                       animationClips:clips
                                         defaultState:defaultState
                                           canvasSize:maxCanvasSize
                                  usesCodexSpriteAtlas:NO];
}

- (NSArray<PETAnimationFrame *> *)framesFromImageDirectoryURL:(NSURL *)directoryURL canvasSize:(PETPlatformSize *)canvasSize {
    NSArray<NSURL *> *imageURLs = [self imageURLsFromURLs:[self visibleChildURLsAtDirectoryURL:directoryURL]];
    return [self framesFromImageURLs:imageURLs canvasSize:canvasSize];
}

- (NSArray<PETAnimationFrame *> *)framesFromImageURLs:(NSArray<NSURL *> *)imageURLs canvasSize:(PETPlatformSize *)canvasSize {
    NSMutableArray<PETAnimationFrame *> *frames = [NSMutableArray arrayWithCapacity:imageURLs.count];

    for (NSURL *imageURL in imageURLs) {
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)imageURL, NULL);
        if (source == NULL) {
            continue;
        }

        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (cgImage == NULL) {
            continue;
        }

        PETPlatformSize imageSize = CGSizeMake(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
        canvasSize->width = MAX(canvasSize->width, imageSize.width);
        canvasSize->height = MAX(canvasSize->height, imageSize.height);

        PETPlatformImage *image = PETPlatformImageFromCGImage(cgImage, imageSize);
        PETAnimationFrame *frame = [[PETAnimationFrame alloc] initWithImage:image duration:PETDefaultSequenceFrameDuration];
        [frames addObject:frame];
        CGImageRelease(cgImage);
    }

    return frames.copy;
}

- (NSDictionary<NSString *, NSArray<NSURL *> *> *)groupedImageFilesFromURLs:(NSArray<NSURL *> *)urls {
    NSMutableDictionary<NSString *, NSMutableArray<NSURL *> *> *groups = [NSMutableDictionary dictionary];

    for (NSURL *url in [self imageURLsFromURLs:urls]) {
        NSString *groupName = [self animationGroupNameForFilename:url.lastPathComponent];
        if (groups[groupName] == nil) {
            groups[groupName] = [NSMutableArray array];
        }
        [groups[groupName] addObject:url];
    }

    NSMutableDictionary<NSString *, NSArray<NSURL *> *> *result = [NSMutableDictionary dictionaryWithCapacity:groups.count];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<NSURL *> *groupURLs, BOOL *stop) {
        (void)stop;
        NSArray<NSURL *> *sorted = [groupURLs sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
            return [left.lastPathComponent localizedStandardCompare:right.lastPathComponent];
        }];
        result[key] = sorted;
    }];
    return result.copy;
}

- (NSString *)animationGroupNameForFilename:(NSString *)filename {
    NSString *name = filename.stringByDeletingPathExtension;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([_-]?\\d+)$" options:0 error:nil];
    NSString *trimmed = [regex stringByReplacingMatchesInString:name options:0 range:NSMakeRange(0, name.length) withTemplate:@""];
    NSString *normalized = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_- "]];
    return normalized.length > 0 ? normalized : @"default";
}

- (NSArray<NSURL *> *)visibleChildURLsAtDirectoryURL:(NSURL *)directoryURL {
    NSArray<NSURL *> *urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directoryURL
                                                         includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                            options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                              error:nil];
    return [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        return [left.lastPathComponent localizedStandardCompare:right.lastPathComponent];
    }];
}

- (NSArray<NSURL *> *)directoryURLsFromURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSURL *> *directories = [NSMutableArray array];
    for (NSURL *url in urls) {
        if ([self isDirectoryURL:url]) {
            [directories addObject:url];
        }
    }
    return directories.copy;
}

- (NSArray<NSURL *> *)imageURLsFromURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSURL *> *images = [NSMutableArray array];
    NSSet<NSString *> *extensions = [NSSet setWithArray:@[@"png", @"webp", @"gif", @"jpg", @"jpeg", @"tiff"]];
    for (NSURL *url in urls) {
        if ([self isDirectoryURL:url]) {
            continue;
        }
        if ([extensions containsObject:url.pathExtension.lowercaseString]) {
            [images addObject:url];
        }
    }
    return images.copy;
}

- (BOOL)isDirectoryURL:(NSURL *)url {
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    return isDirectory.boolValue;
}

- (BOOL)packageManifestExistsAtURL:(NSURL *)url {
    if (![self isDirectoryURL:url]) {
        return [url.lastPathComponent.lowercaseString isEqualToString:@"pet.json"];
    }

    NSURL *manifestURL = [url URLByAppendingPathComponent:@"pet.json"];
    return [NSFileManager.defaultManager fileExistsAtPath:manifestURL.path];
}

- (BOOL)isDirectlySupportedAssetURL:(NSURL *)url {
    if ([self isDirectoryURL:url]) {
        return NO;
    }

    NSString *extension = url.pathExtension.lowercaseString;
    return [@[@"webp", @"gif", @"png"] containsObject:extension];
}

- (BOOL)isSpineRuntimeJSONURL:(NSURL *)url {
    if ([self isDirectoryURL:url]) {
        return NO;
    }
    return [url.pathExtension.lowercaseString isEqualToString:@"json"] && ![url.lastPathComponent.lowercaseString isEqualToString:@"pet.json"];
}

- (NSURL *)spineRuntimeJSONURLInDirectory:(NSURL *)directoryURL {
    NSString *directoryName = directoryURL.lastPathComponent.stringByDeletingPathExtension;
    NSURL *preferredJSONURL = [directoryURL URLByAppendingPathComponent:[directoryName stringByAppendingPathExtension:@"json"]];
    if ([self isValidSpineRuntimeJSONURLInDirectory:preferredJSONURL]) {
        return preferredJSONURL;
    }

    NSArray<NSURL *> *childURLs = [self visibleChildURLsAtDirectoryURL:directoryURL];
    for (NSURL *childURL in childURLs) {
        if ([self isValidSpineRuntimeJSONURLInDirectory:childURL]) {
            return childURL;
        }
    }
    return nil;
}

- (BOOL)isValidSpineRuntimeJSONURLInDirectory:(NSURL *)jsonURL {
    if (![self isSpineRuntimeJSONURL:jsonURL]) {
        return NO;
    }

    NSURL *atlasURL = [[jsonURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"atlas"];
    if (![NSFileManager.defaultManager fileExistsAtPath:atlasURL.path]) {
        return NO;
    }

    NSData *data = [NSData dataWithContentsOfURL:jsonURL options:0 error:nil];
    if (data == nil) {
        return NO;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        return NO;
    }

    NSDictionary *animations = [json[@"animations"] isKindOfClass:NSDictionary.class] ? json[@"animations"] : nil;
    return animations.count > 0;
}

- (PETPetProfile *)loadSpineRuntimeProfileFromJSONURL:(NSURL *)jsonURL error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:jsonURL options:0 error:error];
    if (data == nil) {
        return nil;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7110
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected Spine JSON file is not a valid JSON object."}];
        }
        return nil;
    }

    NSDictionary *skeleton = [json[@"skeleton"] isKindOfClass:NSDictionary.class] ? json[@"skeleton"] : @{};
    NSDictionary *animations = [json[@"animations"] isKindOfClass:NSDictionary.class] ? json[@"animations"] : nil;
    if (animations.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7111
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected Spine JSON file does not contain any animations."}];
        }
        return nil;
    }

    NSURL *atlasURL = [[jsonURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"atlas"];
    if (![NSFileManager.defaultManager fileExistsAtPath:atlasURL.path]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7112
                                     userInfo:@{NSLocalizedDescriptionKey: @"The matching .atlas file could not be found next to the Spine JSON file."}];
        }
        return nil;
    }

    NSString *atlasText = [NSString stringWithContentsOfURL:atlasURL encoding:NSUTF8StringEncoding error:error];
    if (atlasText.length == 0) {
        return nil;
    }

    NSURL *atlasImageURL = [self atlasImageURLFromAtlasText:atlasText baseURL:[atlasURL URLByDeletingLastPathComponent]];
    if (atlasImageURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7113
                                     userInfo:@{NSLocalizedDescriptionKey: @"The atlas file does not point to a page image that could be found."}];
        }
        return nil;
    }

    PETPlatformImage *atlasImage = [self imageAtURL:atlasImageURL error:error];
    if (atlasImage == nil) {
        return nil;
    }

    PETPlatformSize canvasSize = [self canvasSizeFromSpineJSON:json atlasImage:atlasImage];
    NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *clips = [self placeholderClipsFromAnimations:animations atlasImage:atlasImage];
    NSString *defaultState = [self defaultAnimationNameFromAnimations:animations];
    NSDictionary<NSString *, id> *metadata = [self metadataForSpineRuntimeJSON:json
                                               jsonURL:jsonURL
                                              atlasURL:atlasURL
                                             imageURL:atlasImageURL];

    return [[PETPetProfile alloc] initWithDisplayName:jsonURL.lastPathComponent.stringByDeletingPathExtension ?: @"Spine Runtime"
                                            sourceURL:jsonURL
                                       animationClips:clips
                                         defaultState:defaultState
                                           canvasSize:canvasSize
                                  usesCodexSpriteAtlas:NO
                                              metadata:metadata
                           supportsFrameAccuratePreview:NO];
}

- (NSURL *)atlasImageURLFromAtlasText:(NSString *)atlasText baseURL:(NSURL *)baseURL {
    NSArray<NSString *> *lines = [atlasText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0 || [trimmed containsString:@":"]) {
            continue;
        }

        NSURL *candidateURL = [baseURL URLByAppendingPathComponent:trimmed];
        if ([NSFileManager.defaultManager fileExistsAtPath:candidateURL.path]) {
            return candidateURL;
        }
    }
    return nil;
}

- (PETPlatformImage *)imageAtURL:(NSURL *)url error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7114
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to open the atlas page image referenced by the Spine atlas."}];
        }
        return nil;
    }

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (cgImage == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationSourceLoader"
                                         code:7115
                                     userInfo:@{NSLocalizedDescriptionKey: @"The atlas page image could not be decoded."}];
        }
        return nil;
    }

    PETPlatformSize imageSize = CGSizeMake(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    PETPlatformImage *image = PETPlatformImageFromCGImage(cgImage, imageSize);
    CGImageRelease(cgImage);
    return image;
}

- (PETPlatformSize)canvasSizeFromSpineJSON:(NSDictionary *)json atlasImage:(PETPlatformImage *)atlasImage {
    NSDictionary *desktopPet = [json[@"desktopPet"] isKindOfClass:NSDictionary.class] ? json[@"desktopPet"] : nil;
    NSDictionary *displayBounds = [desktopPet[@"displayBounds"] isKindOfClass:NSDictionary.class] ? desktopPet[@"displayBounds"] : nil;
    CGFloat displayWidth = [displayBounds[@"width"] respondsToSelector:@selector(doubleValue)] ? [displayBounds[@"width"] doubleValue] : 0.0;
    CGFloat displayHeight = [displayBounds[@"height"] respondsToSelector:@selector(doubleValue)] ? [displayBounds[@"height"] doubleValue] : 0.0;
    if (displayWidth > 0.0 && displayHeight > 0.0) {
        return CGSizeMake(displayWidth, displayHeight);
    }

    NSDictionary *skeleton = [json[@"skeleton"] isKindOfClass:NSDictionary.class] ? json[@"skeleton"] : @{};
    CGFloat width = [skeleton[@"width"] respondsToSelector:@selector(doubleValue)] ? [skeleton[@"width"] doubleValue] : 0.0;
    CGFloat height = [skeleton[@"height"] respondsToSelector:@selector(doubleValue)] ? [skeleton[@"height"] doubleValue] : 0.0;
    if (width <= 0.0 || height <= 0.0) {
        return PETPlatformImagePixelSize(atlasImage);
    }
    return CGSizeMake(width, height);
}

- (NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *)placeholderClipsFromAnimations:(NSDictionary<NSString *, id> *)animations
                                                                                    atlasImage:(PETPlatformImage *)atlasImage {
    NSMutableDictionary<NSString *, NSArray<PETAnimationFrame *> *> *clips = [NSMutableDictionary dictionaryWithCapacity:animations.count];
    NSArray<NSString *> *names = [[animations allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in names) {
        NSTimeInterval duration = [self durationForAnimationObject:animations[name]];
        PETAnimationFrame *frame = [[PETAnimationFrame alloc] initWithImage:atlasImage duration:MAX(0.1, duration)];
        clips[name] = @[frame];
    }
    return clips.copy;
}

- (NSTimeInterval)durationForAnimationObject:(NSDictionary *)animation {
    __block double maxTime = 0.0;
    [self enumerateFramesInJSONObject:animation usingBlock:^(NSDictionary *frame) {
        id timeValue = frame[@"time"];
        if ([timeValue respondsToSelector:@selector(doubleValue)]) {
            maxTime = MAX(maxTime, [timeValue doubleValue]);
        }
    }];
    return maxTime > 0.0 ? maxTime : PETDefaultSequenceFrameDuration;
}

- (void)enumerateFramesInJSONObject:(id)object usingBlock:(void (^)(NSDictionary *frame))block {
    if ([object isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)object) {
            if ([item isKindOfClass:NSDictionary.class]) {
                block((NSDictionary *)item);
            } else {
                [self enumerateFramesInJSONObject:item usingBlock:block];
            }
        }
        return;
    }

    if ([object isKindOfClass:NSDictionary.class]) {
        for (id value in [(NSDictionary *)object allValues]) {
            [self enumerateFramesInJSONObject:value usingBlock:block];
        }
    }
}

- (NSString *)defaultAnimationNameFromAnimations:(NSDictionary<NSString *, id> *)animations {
    for (NSString *preferred in @[@"battle_idle", @"Idle", @"idle", @"Move", @"move"]) {
        if (animations[preferred] != nil) {
            return preferred;
        }
    }
    return [[animations allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)].firstObject ?: @"Animation";
}

- (NSDictionary<NSString *, id> *)metadataForSpineRuntimeJSON:(NSDictionary *)json
                                                      jsonURL:(NSURL *)jsonURL
                                                     atlasURL:(NSURL *)atlasURL
                                                     imageURL:(NSURL *)imageURL {
    NSDictionary *skeleton = [json[@"skeleton"] isKindOfClass:NSDictionary.class] ? json[@"skeleton"] : @{};
    NSDictionary *animations = [json[@"animations"] isKindOfClass:NSDictionary.class] ? json[@"animations"] : @{};
    NSArray<NSString *> *names = [[animations allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSArray<NSString *> *detectedSemanticParts = [self inferredSemanticPartsFromSpineRuntimeJSON:json];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *directionPairs = [NSMutableArray array];
    NSMutableSet<NSString *> *nameSet = [NSMutableSet setWithArray:names];
    for (NSString *name in names) {
        if (![name hasSuffix:@"b"]) {
            NSString *variant = [name stringByAppendingString:@"b"];
            if ([nameSet containsObject:variant]) {
                [directionPairs addObject:@{@"forward": name, @"reverse": variant}];
            }
        }
    }

    NSDictionary<NSString *, NSString *> *stateAliases = [self inferredStateAliasesFromAnimationNames:names
                                                                                        directionPairs:directionPairs];
    NSMutableDictionary<NSString *, NSString *> *interactionAliases = [[self inferredInteractionAliasesFromAnimationNames:names
                                                                                                               stateAliases:stateAliases] mutableCopy];
    BOOL soulArkEnabled = [self isSoulArkSpineRuntimeJSONURL:jsonURL atlasURL:atlasURL imageURL:imageURL];
    if (soulArkEnabled) {
        NSDictionary<NSString *, NSString *> *combatAliases = [self inferredSoulArkCombatInteractionAliasesFromAnimationNames:names];
        [combatAliases enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            (void)stop;
            if (obj.length > 0) {
                interactionAliases[key] = obj;
            }
        }];
    }

    return @{
        @"sourceType": @"spine-runtime-json",
        @"spineVersion": [skeleton[@"spine"] isKindOfClass:NSString.class] ? skeleton[@"spine"] : @"unknown",
        @"atlasPath": atlasURL.path ?: @"",
        @"imagePath": imageURL.path ?: @"",
        @"animationCount": @(names.count),
        @"灵魂方舟": @(soulArkEnabled),
        @"灵魂方舟左右方向反转": @(soulArkEnabled),
        @"detectedSemanticParts": detectedSemanticParts ?: @[],
        @"directionPairs": directionPairs.copy,
        @"stateAliases": stateAliases ?: @{},
        @"baseInteractionAliases": interactionAliases ?: @{},
        @"interactionAliases": @{}
    };
}

- (BOOL)isSoulArkSpineRuntimeJSONURL:(NSURL *)jsonURL atlasURL:(NSURL *)atlasURL imageURL:(NSURL *)imageURL {
    for (NSURL *url in @[jsonURL ?: NSURL.new, atlasURL ?: NSURL.new, imageURL ?: NSURL.new]) {
        NSString *stem = url.lastPathComponent.stringByDeletingPathExtension.lowercaseString ?: @"";
        if ([stem hasPrefix:@"char_"]) {
            return YES;
        }
    }
    return NO;
}

- (NSDictionary<NSString *, NSString *> *)inferredStateAliasesFromAnimationNames:(NSArray<NSString *> *)names
                                                                  directionPairs:(NSArray<NSDictionary<NSString *, NSString *> *> *)directionPairs {
    NSMutableDictionary<NSString *, NSString *> *aliases = [NSMutableDictionary dictionary];

    NSString *(^bestMatch)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *candidates) {
        for (NSString *candidate in candidates) {
            for (NSString *name in names) {
                if ([name localizedCaseInsensitiveCompare:candidate] == NSOrderedSame) {
                    return name;
                }
            }
        }
        for (NSString *candidate in candidates) {
            NSString *needle = candidate.lowercaseString;
            for (NSString *name in names) {
                if ([name.lowercaseString containsString:needle]) {
                    return name;
                }
            }
        }
        return nil;
    };

    NSString *idle = bestMatch(@[@"battle_idle", @"Idle", @"Stand", @"Wait"]);
    if (idle.length > 0) {
        aliases[PETBehaviorStateIdle] = idle;
    }

    NSString *move = bestMatch(@[@"run", @"dash", @"Move", @"Run", @"Walk"]);
    if (move.length > 0) {
        aliases[PETBehaviorStateRunningRight] = move;
        aliases[PETBehaviorStateWaiting] = move;
    }

    NSString *jump = bestMatch(@[@"jump", @"jump_ing", @"Jump", @"Fall"]);
    if (jump.length > 0) {
        aliases[PETBehaviorStateJumping] = jump;
    }

    NSString *wave = bestMatch(@[@"Cheer", @"Wave", @"Hello", @"Atk", @"atk"]);
    if (wave.length > 0) {
        aliases[PETBehaviorStateWaving] = wave;
    }

    NSString *review = bestMatch(@[@"Ult", @"ult", @"Skill", @"Cast", @"Cheer"]);
    if (review.length > 0) {
        aliases[PETBehaviorStateReview] = review;
    }

    for (NSDictionary<NSString *, NSString *> *pair in directionPairs) {
        NSString *forward = [pair[@"forward"] isKindOfClass:NSString.class] ? pair[@"forward"] : nil;
        NSString *reverse = [pair[@"reverse"] isKindOfClass:NSString.class] ? pair[@"reverse"] : nil;
        if (forward.length == 0 || reverse.length == 0) {
            continue;
        }
        NSString *forwardLowercase = forward.lowercaseString;
        if ([forwardLowercase containsString:@"move"] || [forwardLowercase containsString:@"run"] || [forwardLowercase containsString:@"walk"]) {
            aliases[PETBehaviorStateRunningRight] = forward;
            aliases[PETBehaviorStateRunningLeft] = reverse;
            break;
        }
    }

    if (aliases[PETBehaviorStateRunningLeft] == nil && aliases[PETBehaviorStateRunningRight] != nil) {
        aliases[PETBehaviorStateRunningLeft] = aliases[PETBehaviorStateRunningRight];
    }
    if (aliases[PETBehaviorStateWaiting] == nil) {
        aliases[PETBehaviorStateWaiting] = aliases[PETBehaviorStateIdle] ?: aliases[PETBehaviorStateRunningRight];
    }
    if (aliases[PETBehaviorStateWaving] == nil) {
        aliases[PETBehaviorStateWaving] = aliases[PETBehaviorStateIdle];
    }
    if (aliases[PETBehaviorStateReview] == nil) {
        aliases[PETBehaviorStateReview] = aliases[PETBehaviorStateWaving] ?: aliases[PETBehaviorStateIdle];
    }
    if (aliases[PETBehaviorStateJumping] == nil) {
        aliases[PETBehaviorStateJumping] = aliases[PETBehaviorStateWaiting] ?: aliases[PETBehaviorStateIdle];
    }

    return aliases.copy;
}

- (NSDictionary<NSString *, NSString *> *)inferredInteractionAliasesFromAnimationNames:(NSArray<NSString *> *)names
                                                                           stateAliases:(NSDictionary<NSString *, NSString *> *)stateAliases {
    NSMutableDictionary<NSString *, NSString *> *aliases = [NSMutableDictionary dictionary];

    NSString *(^bestMatch)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *candidates) {
        for (NSString *candidate in candidates) {
            for (NSString *name in names) {
                if ([name localizedCaseInsensitiveCompare:candidate] == NSOrderedSame) {
                    return name;
                }
            }
        }
        for (NSString *candidate in candidates) {
            NSString *needle = candidate.lowercaseString;
            for (NSString *name in names) {
                if ([name.lowercaseString containsString:needle]) {
                    return name;
                }
            }
        }
        return nil;
    };

    NSString *idle = stateAliases[PETBehaviorStateIdle] ?: bestMatch(@[@"Idle", @"Stand", @"Wait"]);
    NSString *wave = stateAliases[PETBehaviorStateWaving] ?: bestMatch(@[@"Wave", @"Hello", @"Cheer", @"Touch", @"Tap", @"Pat"]);
    NSString *review = stateAliases[PETBehaviorStateReview] ?: bestMatch(@[@"Skill", @"Cast", @"Ult", @"Attack", @"Atk"]);
    NSString *jump = stateAliases[PETBehaviorStateJumping] ?: bestMatch(@[@"Jump", @"Bounce", @"Happy"]);
    NSString *moveLeft = stateAliases[PETBehaviorStateRunningLeft];
    NSString *moveRight = stateAliases[PETBehaviorStateRunningRight];
    NSString *dragIdle = stateAliases[PETBehaviorStateWaiting] ?: idle;

    if (idle.length > 0) {
        aliases[PETActionAmbientIdle] = idle;
    }
    if (wave.length > 0) {
        aliases[PETActionTapPrimary] = wave;
        aliases[PETActionTapHead] = wave;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"head"]] = wave;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"ear"]] = wave;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"hand"]] = wave;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"paw"]] = wave;
    }
    if (review.length > 0) {
        aliases[PETActionTapSecondary] = review;
        aliases[PETActionTapTail] = review;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"tail"]] = review;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"wing"]] = review;
    }
    if (jump.length > 0) {
        aliases[PETActionTapBody] = jump;
        aliases[PETActionDragRelease] = jump;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"body"]] = jump;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"leg"]] = jump;
        aliases[[PETActionTapPartPrefix stringByAppendingString:@"foot"]] = jump;
    }
    if (dragIdle.length > 0) {
        aliases[PETActionDragIdle] = dragIdle;
    }
    if (moveLeft.length > 0) {
        aliases[PETActionDragMoveLeft] = moveLeft;
    }
    if (moveRight.length > 0) {
        aliases[PETActionDragMoveRight] = moveRight;
    }

    if (aliases[PETActionTapPrimary] == nil && idle.length > 0) {
        aliases[PETActionTapPrimary] = idle;
    }
    if (aliases[PETActionTapSecondary] == nil) {
        aliases[PETActionTapSecondary] = aliases[PETActionTapPrimary] ?: idle;
    }
    if (aliases[PETActionTapHead] == nil) {
        aliases[PETActionTapHead] = aliases[PETActionTapPrimary] ?: idle;
    }
    if (aliases[PETActionTapTail] == nil) {
        aliases[PETActionTapTail] = aliases[PETActionTapSecondary] ?: aliases[PETActionTapPrimary] ?: idle;
    }
    if (aliases[PETActionTapBody] == nil) {
        aliases[PETActionTapBody] = aliases[PETActionTapPrimary] ?: idle;
    }
    if (aliases[PETActionDragRelease] == nil) {
        aliases[PETActionDragRelease] = aliases[PETActionTapBody] ?: idle;
    }
    if (aliases[PETActionDragIdle] == nil) {
        aliases[PETActionDragIdle] = idle;
    }
    if (aliases[PETActionDragMoveLeft] == nil) {
        aliases[PETActionDragMoveLeft] = aliases[PETActionDragIdle];
    }
    if (aliases[PETActionDragMoveRight] == nil) {
        aliases[PETActionDragMoveRight] = aliases[PETActionDragIdle];
    }

    return aliases.copy;
}

- (NSDictionary<NSString *, NSString *> *)inferredSoulArkCombatInteractionAliasesFromAnimationNames:(NSArray<NSString *> *)names {
    NSMutableDictionary<NSString *, NSString *> *aliases = [NSMutableDictionary dictionary];

    NSString *(^bestMatch)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *candidates) {
        for (NSString *candidate in candidates) {
            for (NSString *name in names) {
                if ([name localizedCaseInsensitiveCompare:candidate] == NSOrderedSame) {
                    return name;
                }
            }
        }
        for (NSString *candidate in candidates) {
            NSString *needle = candidate.lowercaseString;
            for (NSString *name in names) {
                if ([name.lowercaseString containsString:needle]) {
                    return name;
                }
            }
        }
        return nil;
    };

    NSString *attack = bestMatch(@[@"attack"]);
    NSString *skill1 = bestMatch(@[@"attack_skill_link01", @"attack_skill_1"]);
    NSString *skill2 = bestMatch(@[@"attack_skill_link02", @"attack_skill_2"]);
    NSString *special = bestMatch(@[@"attack_skill_special", @"attack_skill_special_legend"]);
    NSString *dash = bestMatch(@[@"dash"]);
    NSString *battleIdle = bestMatch(@[@"battle_idle", @"idle"]);
    NSString *hit = bestMatch(@[@"hit"]);
    NSString *stun = bestMatch(@[@"stun"]);
    NSString *down = bestMatch(@[@"down"]);
    NSString *getup = bestMatch(@[@"getup"]);
    NSString *knockback = bestMatch(@[@"knockback", @"hit_down"]);

    if (attack.length > 0) {
        aliases[@"combat.primary"] = attack;
    }
    if (skill1.length > 0) {
        aliases[@"combat.secondary"] = skill1;
    }
    if (skill2.length > 0) {
        aliases[@"combat.skill.1"] = skill2;
    }
    if (special.length > 0) {
        aliases[@"combat.ultimate"] = special;
    }
    if (dash.length > 0) {
        aliases[@"combat.quick"] = dash;
    }
    if (battleIdle.length > 0) {
        aliases[@"combat.idle"] = battleIdle;
    }
    if (hit.length > 0) {
        aliases[@"combat.hit"] = hit;
    }
    if (stun.length > 0) {
        aliases[@"combat.hitstun"] = stun;
    }
    if (down.length > 0) {
        aliases[@"combat.knockeddown"] = down;
    }
    if (getup.length > 0) {
        aliases[@"combat.getup"] = getup;
    }
    if (knockback.length > 0) {
        aliases[@"combat.launched"] = knockback;
    }
    if (attack.length > 0) {
        aliases[@"combat.cancel"] = bestMatch(@[@"return"]) ?: attack;
    }

    return aliases.copy;
}

- (NSArray<NSString *> *)inferredSemanticPartsFromSpineRuntimeJSON:(NSDictionary *)json {
    NSMutableOrderedSet<NSString *> *nameSet = [NSMutableOrderedSet orderedSet];

    NSArray *bones = [json[@"bones"] isKindOfClass:NSArray.class] ? json[@"bones"] : @[];
    for (NSDictionary *bone in bones) {
        NSString *name = [bone[@"name"] isKindOfClass:NSString.class] ? bone[@"name"] : nil;
        if (name.length > 0) {
            [nameSet addObject:name];
        }
    }

    NSArray *slots = [json[@"slots"] isKindOfClass:NSArray.class] ? json[@"slots"] : @[];
    for (NSDictionary *slot in slots) {
        NSString *name = [slot[@"name"] isKindOfClass:NSString.class] ? slot[@"name"] : nil;
        if (name.length > 0) {
            [nameSet addObject:name];
        }
        NSString *attachment = [slot[@"attachment"] isKindOfClass:NSString.class] ? slot[@"attachment"] : nil;
        if (attachment.length > 0) {
            [nameSet addObject:attachment];
        }
    }

    NSDictionary *skinsDictionary = [json[@"skins"] isKindOfClass:NSDictionary.class] ? json[@"skins"] : @{};
    for (id skinName in skinsDictionary) {
        id attachmentsBySlot = skinsDictionary[skinName];
        if (![attachmentsBySlot isKindOfClass:NSDictionary.class]) {
            continue;
        }
        for (id slotName in (NSDictionary *)attachmentsBySlot) {
            if ([slotName isKindOfClass:NSString.class]) {
                [nameSet addObject:slotName];
            }
            id attachmentEntries = [(NSDictionary *)attachmentsBySlot objectForKey:slotName];
            if (![attachmentEntries isKindOfClass:NSDictionary.class]) {
                continue;
            }
            for (id attachmentName in (NSDictionary *)attachmentEntries) {
                if ([attachmentName isKindOfClass:NSString.class]) {
                    [nameSet addObject:attachmentName];
                }
            }
        }
    }

    NSMutableOrderedSet<NSString *> *semanticParts = [NSMutableOrderedSet orderedSet];
    for (NSString *name in nameSet.array) {
        NSString *semanticPart = [self semanticPartForIdentifier:name];
        if (semanticPart.length > 0) {
            [semanticParts addObject:semanticPart];
        }
    }
    return semanticParts.array;
}

- (NSString *)semanticPartForIdentifier:(NSString *)identifier {
    NSString *normalized = identifier.lowercaseString ?: @"";
    if (normalized.length == 0) {
        return @"body";
    }

    NSArray<NSArray<NSString *> *> *rules = @[
        @[@"head", @"head", @"face", @"tou", @"lian", @"yan", @"jing", @"zui", @"zuiba", @"bi", @"mouth", @"nose", @"horn"],
        @[@"tail", @"tail", @"weiba", @"wei"],
        @[@"ear", @"ear", @"duo", @"erduo"],
        @[@"hand", @"hand", @"arm", @"shou", @"gebi"],
        @[@"paw", @"paw", @"claw", @"zhua", @"zhazi", @"shoumao"],
        @[@"leg", @"leg", @"tui", @"datui", @"xiaotui"],
        @[@"foot", @"foot", @"feet", @"jiao", @"jiaozhang"],
        @[@"wing", @"wing", @"chi", @"chibang"]
    ];

    for (NSArray<NSString *> *rule in rules) {
        NSString *semanticPart = rule.firstObject;
        for (NSUInteger index = 1; index < rule.count; index += 1) {
            if ([normalized containsString:rule[index]]) {
                return semanticPart;
            }
        }
    }

    return @"body";
}

@end
