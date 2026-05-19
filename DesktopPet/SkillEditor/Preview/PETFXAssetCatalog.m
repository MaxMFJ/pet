#import "PETFXAssetCatalog.h"

@implementation PETFXSequence

- (instancetype)initWithAssetName:(NSString *)assetName frames:(NSArray<NSImage *> *)frames framesPerSecond:(CGFloat)fps {
    self = [super init];
    if (self) {
        _assetName = [assetName copy];
        _frames = [frames copy];
        _framesPerSecond = fps > 0.0 ? fps : 24.0;
    }
    return self;
}

- (nullable NSImage *)frameAtIndex:(NSUInteger)index {
    if (self.frames.count == 0) {
        return nil;
    }
    return self.frames[index % self.frames.count];
}

@end

@interface PETFXAssetCatalog ()

@property (nonatomic, copy) NSDictionary<NSString *, PETFXSequence *> *cachedSequences;

@end

@implementation PETFXAssetCatalog

+ (instancetype)sharedCatalog {
    static PETFXAssetCatalog *catalog = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = [[PETFXAssetCatalog alloc] init];
    });
    return catalog;
}

- (NSURL *)fxRootDirectory {
    NSURL *bundleFX = [[NSBundle.mainBundle resourceURL] URLByAppendingPathComponent:@"FX" isDirectory:YES];
    if ([NSFileManager.defaultManager fileExistsAtPath:bundleFX.path]) {
        return bundleFX;
    }
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *documentsFX = [NSURL fileURLWithPath:[documents stringByAppendingPathComponent:@"FX"] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:documentsFX withIntermediateDirectories:YES attributes:nil error:nil];
    return documentsFX;
}

- (NSArray<NSString *> *)availableAssetNames {
    NSURL *root = [self fxRootDirectory];
    NSArray<NSURL *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtURL:root
                                                            includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:nil];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSURL *entry in entries) {
        NSNumber *isDirectory = nil;
        [entry getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) {
            [names addObject:entry.lastPathComponent];
        }
    }
    [names sortUsingSelector:@selector(caseInsensitiveCompare:)];
    return names.copy;
}

- (nullable PETFXSequence *)sequenceNamed:(NSString *)assetName {
    if (assetName.length == 0) {
        return nil;
    }
    PETFXSequence *cached = self.cachedSequences[assetName];
    if (cached != nil) {
        return cached;
    }

    NSURL *folder = [[self fxRootDirectory] URLByAppendingPathComponent:assetName isDirectory:YES];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder
                                                          includingPropertiesForKeys:nil
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                               error:nil];
    NSMutableArray<NSURL *> *pngFiles = [NSMutableArray array];
    for (NSURL *file in files) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"png"]) {
            [pngFiles addObject:file];
        }
    }
    [pngFiles sortUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        return [left.lastPathComponent compare:right.lastPathComponent options:NSNumericSearch];
    }];

    NSMutableArray<NSImage *> *frames = [NSMutableArray array];
    for (NSURL *file in pngFiles) {
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:file];
        if (image != nil) {
            [frames addObject:image];
        }
    }

    PETFXSequence *sequence = [[PETFXSequence alloc] initWithAssetName:assetName frames:frames framesPerSecond:24.0];
    NSMutableDictionary *cache = [self.cachedSequences mutableCopy] ?: [NSMutableDictionary dictionary];
    cache[assetName] = sequence;
    self.cachedSequences = cache.copy;
    return sequence;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedSequences = @{};
    }
    return self;
}

- (void)invalidateCache {
    self.cachedSequences = @{};
}

- (BOOL)importPNGSequenceFromDirectory:(NSURL *)sourceDirectory
                            assetName:(NSString *)assetName
                                error:(NSError * _Nullable __autoreleasing *)error {
    if (sourceDirectory == nil || assetName.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETFXAssetCatalog" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Choose a folder and asset name."}];
        }
        return NO;
    }

    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:sourceDirectory
                                                            includingPropertiesForKeys:nil
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:error];
    if (files == nil) {
        return NO;
    }

    NSURL *destination = [[self fxRootDirectory] URLByAppendingPathComponent:assetName isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:error];

    NSUInteger importedCount = 0;
    for (NSURL *file in files) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) {
            continue;
        }
        NSURL *target = [destination URLByAppendingPathComponent:file.lastPathComponent];
        [NSFileManager.defaultManager removeItemAtURL:target error:nil];
        if (![NSFileManager.defaultManager copyItemAtURL:file toURL:target error:error]) {
            return NO;
        }
        importedCount += 1;
    }

    if (importedCount == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETFXAssetCatalog" code:2 userInfo:@{NSLocalizedDescriptionKey: @"No PNG files found in the selected folder."}];
        }
        return NO;
    }

    [self invalidateCache];
    return YES;
}

@end
