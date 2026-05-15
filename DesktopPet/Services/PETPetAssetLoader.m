#import "PETPetAssetLoader.h"

#import <ImageIO/ImageIO.h>

#import "../Models/PETAnimationFrame.h"
#import "../Models/PETPetProfile.h"
#import "PETWebPDecoder.h"

static NSString * const PETStateIdle = @"idle";
static NSString * const PETStateRunningRight = @"running-right";
static NSString * const PETStateRunningLeft = @"running-left";
static NSString * const PETStateWaving = @"waving";
static NSString * const PETStateJumping = @"jumping";
static NSString * const PETStateFailed = @"failed";
static NSString * const PETStateWaiting = @"waiting";
static NSString * const PETStateRunning = @"running";
static NSString * const PETStateReview = @"review";

@interface PETPetAssetLoader ()

@property (nonatomic, strong) PETWebPDecoder *webPDecoder;

@end

@implementation PETPetAssetLoader

- (instancetype)init {
    self = [super init];
    if (self) {
        _webPDecoder = [[PETWebPDecoder alloc] init];
    }
    return self;
}

- (PETPetProfile *)loadPetProfileAtURL:(NSURL *)fileURL error:(NSError **)error {
    if ([self isDirectoryURL:fileURL]) {
        return [self loadPetProfileFromPackageAtURL:fileURL error:error];
    }

    if ([[fileURL.lastPathComponent lowercaseString] isEqualToString:@"pet.json"]) {
        return [self loadPetProfileFromPackageAtURL:fileURL error:error];
    }

    NSString *displayName = fileURL.lastPathComponent.stringByDeletingPathExtension ?: @"Pet";

    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (source == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to open pet asset."}];
        }
        return nil;
    }

    BOOL usesAtlas = [self isCodexSpriteAtlas:source];
    CFRelease(source);

    if (usesAtlas) {
        return [self loadCodexSpriteAtlasAtURL:fileURL displayName:displayName error:error];
    }

    PETPlatformSize canvasSize = CGSizeZero;
    NSArray<PETAnimationFrame *> *frames = [self.webPDecoder decodeFramesAtURL:fileURL canvasSize:&canvasSize error:error];
    if (frames.count == 0) {
        return nil;
    }

    return [[PETPetProfile alloc] initWithDisplayName:displayName
                                            sourceURL:fileURL
                                               frames:frames
                                           canvasSize:canvasSize];
}

- (PETPetProfile *)loadPetProfileFromPackageAtURL:(NSURL *)packageURL error:(NSError **)error {
    NSURL *manifestURL = [self manifestURLForPackageURL:packageURL];
    if (manifestURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6010
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected pet package does not contain a pet.json manifest."}];
        }
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfURL:manifestURL options:0 error:error];
    if (data == nil) {
        return nil;
    }

    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![manifest isKindOfClass:NSDictionary.class]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6011
                                     userInfo:@{NSLocalizedDescriptionKey: @"pet.json is not a valid JSON object."}];
        }
        return nil;
    }

    NSString *displayName = [manifest[@"displayName"] isKindOfClass:NSString.class] ? manifest[@"displayName"] : nil;
    NSString *spritesheetPath = [manifest[@"spritesheetPath"] isKindOfClass:NSString.class] ? manifest[@"spritesheetPath"] : nil;
    if (spritesheetPath.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6012
                                     userInfo:@{NSLocalizedDescriptionKey: @"pet.json is missing spritesheetPath."}];
        }
        return nil;
    }

    NSURL *baseDirectoryURL = [manifestURL URLByDeletingLastPathComponent];
    NSURL *spritesheetURL = [baseDirectoryURL URLByAppendingPathComponent:spritesheetPath];
    if (![NSFileManager.defaultManager fileExistsAtPath:spritesheetURL.path]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6013
                                     userInfo:@{NSLocalizedDescriptionKey: @"The spritesheet referenced by pet.json could not be found."}];
        }
        return nil;
    }

    NSString *resolvedName = displayName.length > 0 ? displayName : baseDirectoryURL.lastPathComponent;
    return [self loadCodexSpriteAtlasAtURL:spritesheetURL displayName:resolvedName error:error];
}

- (BOOL)isCodexSpriteAtlas:(CGImageSourceRef)source {
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    if (image == NULL) {
        return NO;
    }

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CGImageRelease(image);
    return width == 1536 && height == 1872;
}

- (BOOL)isDirectoryURL:(NSURL *)url {
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    return isDirectory.boolValue;
}

- (NSURL *)manifestURLForPackageURL:(NSURL *)packageURL {
    if ([[packageURL.lastPathComponent lowercaseString] isEqualToString:@"pet.json"]) {
        return packageURL;
    }

    if (![self isDirectoryURL:packageURL]) {
        return nil;
    }

    NSURL *manifestURL = [packageURL URLByAppendingPathComponent:@"pet.json"];
    return [NSFileManager.defaultManager fileExistsAtPath:manifestURL.path] ? manifestURL : nil;
}

- (PETPetProfile *)loadCodexSpriteAtlasAtURL:(NSURL *)fileURL
                                 displayName:(NSString *)displayName
                                       error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (source == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to decode Codex pet atlas."}];
        }
        return nil;
    }

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (image == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6003
                                     userInfo:@{NSLocalizedDescriptionKey: @"The Codex pet atlas does not contain an image frame."}];
        }
        return nil;
    }

    NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *clips = [self clipsFromAtlasImage:image];
    CGImageRelease(image);

    NSArray<PETAnimationFrame *> *idleFrames = clips[PETStateIdle];
    if (idleFrames.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetAssetLoader"
                                         code:6004
                                     userInfo:@{NSLocalizedDescriptionKey: @"This spritesheet is missing the idle row required for Codex-style pets."}];
        }
        return nil;
    }

    return [[PETPetProfile alloc] initWithDisplayName:displayName
                                            sourceURL:fileURL
                                       animationClips:clips
                                         defaultState:PETStateIdle
                                           canvasSize:CGSizeMake(192.0, 208.0)
                                  usesCodexSpriteAtlas:YES];
}

- (NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *)clipsFromAtlasImage:(CGImageRef)atlasImage {
    NSArray<NSDictionary<NSString *, id> *> *rows = @[
        @{@"state": PETStateIdle, @"row": @0, @"durations": @[@0.280, @0.110, @0.110, @0.140, @0.140, @0.320]},
        @{@"state": PETStateRunningRight, @"row": @1, @"durations": @[@0.120, @0.120, @0.120, @0.120, @0.120, @0.120, @0.120, @0.220]},
        @{@"state": PETStateRunningLeft, @"row": @2, @"durations": @[@0.120, @0.120, @0.120, @0.120, @0.120, @0.120, @0.120, @0.220]},
        @{@"state": PETStateWaving, @"row": @3, @"durations": @[@0.140, @0.140, @0.140, @0.280]},
        @{@"state": PETStateJumping, @"row": @4, @"durations": @[@0.140, @0.140, @0.140, @0.140, @0.280]},
        @{@"state": PETStateFailed, @"row": @5, @"durations": @[@0.140, @0.140, @0.140, @0.140, @0.140, @0.140, @0.140, @0.240]},
        @{@"state": PETStateWaiting, @"row": @6, @"durations": @[@0.150, @0.150, @0.150, @0.150, @0.150, @0.260]},
        @{@"state": PETStateRunning, @"row": @7, @"durations": @[@0.120, @0.120, @0.120, @0.120, @0.120, @0.220]},
        @{@"state": PETStateReview, @"row": @8, @"durations": @[@0.150, @0.150, @0.150, @0.150, @0.150, @0.280]}
    ];

    NSMutableDictionary<NSString *, NSArray<PETAnimationFrame *> *> *clips = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *definition in rows) {
        NSString *state = definition[@"state"];
        NSInteger rowIndex = [definition[@"row"] integerValue];
        NSArray<NSNumber *> *durations = definition[@"durations"];
        NSArray<PETAnimationFrame *> *frames = [self framesFromAtlasImage:atlasImage rowIndex:rowIndex durations:durations];
        if (frames.count > 0) {
            clips[state] = frames;
        }
    }
    return clips.copy;
}

- (NSArray<PETAnimationFrame *> *)framesFromAtlasImage:(CGImageRef)atlasImage
                                              rowIndex:(NSInteger)rowIndex
                                             durations:(NSArray<NSNumber *> *)durations {
    const CGFloat cellWidth = 192.0;
    const CGFloat cellHeight = 208.0;
    size_t atlasHeight = CGImageGetHeight(atlasImage);
    NSMutableArray<PETAnimationFrame *> *frames = [NSMutableArray arrayWithCapacity:durations.count];

    for (NSUInteger column = 0; column < durations.count; column++) {
        CGRect cropRect = CGRectMake(column * cellWidth,
                                     rowIndex * cellHeight,
                                     cellWidth,
                                     cellHeight);
        CGImageRef frameImage = CGImageCreateWithImageInRect(atlasImage, cropRect);
        if (frameImage == NULL) {
            continue;
        }

        if ([self imageIsFullyTransparent:frameImage]) {
            CGImageRelease(frameImage);
            continue;
        }

        PETPlatformImage *image = PETPlatformImageFromCGImage(frameImage, CGSizeMake(cellWidth, cellHeight));
        PETAnimationFrame *frame = [[PETAnimationFrame alloc] initWithImage:image duration:durations[column].doubleValue];
        [frames addObject:frame];
        CGImageRelease(frameImage);
    }

    return frames.copy;
}

- (BOOL)imageIsFullyTransparent:(CGImageRef)image {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        return YES;
    }

    size_t bytesPerPixel = 4;
    size_t bytesPerRow = width * bytesPerPixel;
    size_t totalBytes = bytesPerRow * height;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL) {
        return YES;
    }

    void *bitmapData = calloc(totalBytes, sizeof(uint8_t));
    if (bitmapData == NULL) {
        CGColorSpaceRelease(colorSpace);
        return YES;
    }

    CGContextRef context = CGBitmapContextCreate(bitmapData,
                                                 width,
                                                 height,
                                                 8,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        free(bitmapData);
        return YES;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);

    BOOL fullyTransparent = YES;
    uint8_t *pixels = (uint8_t *)bitmapData;
    for (size_t offset = 0; offset < totalBytes; offset += bytesPerPixel) {
        if (pixels[offset + 3] > 5) {
            fullyTransparent = NO;
            break;
        }
    }

    free(bitmapData);
    return fullyTransparent;
}

@end
