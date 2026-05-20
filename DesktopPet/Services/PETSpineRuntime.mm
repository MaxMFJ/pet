#import "PETSpineRuntime.h"


#import <ImageIO/ImageIO.h>
#import <TargetConditionals.h>

#include <spine/Animation.h>
#include <spine/AnimationState.h>
#include <spine/AnimationStateData.h>
#include <spine/Atlas.h>
#include <spine/AtlasAttachmentLoader.h>
#include <spine/ClippingAttachment.h>
#include <spine/Bone.h>
#include <spine/BoneData.h>
#include <spine/BlendMode.h>
#include <spine/MixBlend.h>
#include <spine/MixDirection.h>
#include <spine/MeshAttachment.h>
#include <spine/RegionAttachment.h>
#include <spine/Skeleton.h>
#include <spine/SkeletonClipping.h>
#include <spine/SkeletonData.h>
#include <spine/SkeletonJson.h>
#include <spine/Slot.h>
#include <spine/SlotData.h>
#include <spine/TextureLoader.h>
#include <spine/Vector.h>

static NSString * const PETSpineRuntimeErrorDomain = @"PETSpineRuntime";

namespace {

struct PETSpinePageTexture {
    CGImageRef image = nullptr;
    size_t width = 0;
    size_t height = 0;
};

static void PETDisposeSpinePageTexture(void *rendererObject) {
    PETSpinePageTexture *pageTexture = static_cast<PETSpinePageTexture *>(rendererObject);
    if (pageTexture == nullptr) {
        return;
    }
    if (pageTexture->image != nullptr) {
        CGImageRelease(pageTexture->image);
        pageTexture->image = nullptr;
    }
    delete pageTexture;
}

class PETSpineTextureLoader final : public spine::TextureLoader {
public:
    void load(spine::AtlasPage &page, const spine::String &path) override {
        @autoreleasepool {
            NSString *filePath = [NSString stringWithUTF8String:path.buffer()];
            NSURL *fileURL = [NSURL fileURLWithPath:filePath];
            CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, nullptr);
            if (source == nullptr) {
                return;
            }

            CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
            CFRelease(source);
            if (image == nullptr) {
                return;
            }

            PETSpinePageTexture *pageTexture = new PETSpinePageTexture();
            pageTexture->image = image;
            pageTexture->width = CGImageGetWidth(image);
            pageTexture->height = CGImageGetHeight(image);
            page.width = (int)pageTexture->width;
            page.height = (int)pageTexture->height;
            page.setRendererObject(pageTexture);
        }
    }

    void unload(void *texture) override {
        PETDisposeSpinePageTexture(texture);
    }
};

struct PETAffineTriangleTransform {
    bool valid = false;
    CGAffineTransform transform = CGAffineTransformIdentity;
};

static PETAffineTriangleTransform PETAffineTransformForTriangles(CGPoint s0,
                                                                 CGPoint s1,
                                                                 CGPoint s2,
                                                                 CGPoint d0,
                                                                 CGPoint d1,
                                                                 CGPoint d2) {
    CGFloat dsx1 = s1.x - s0.x;
    CGFloat dsy1 = s1.y - s0.y;
    CGFloat dsx2 = s2.x - s0.x;
    CGFloat dsy2 = s2.y - s0.y;
    CGFloat determinant = (dsx1 * dsy2) - (dsy1 * dsx2);
    if (fabs(determinant) < 0.00001) {
        return {};
    }

    CGFloat inv00 = dsy2 / determinant;
    CGFloat inv01 = -dsx2 / determinant;
    CGFloat inv10 = -dsy1 / determinant;
    CGFloat inv11 = dsx1 / determinant;

    CGFloat ddx1 = d1.x - d0.x;
    CGFloat ddy1 = d1.y - d0.y;
    CGFloat ddx2 = d2.x - d0.x;
    CGFloat ddy2 = d2.y - d0.y;

    CGFloat a = (ddx1 * inv00) + (ddx2 * inv10);
    CGFloat c = (ddx1 * inv01) + (ddx2 * inv11);
    CGFloat b = (ddy1 * inv00) + (ddy2 * inv10);
    CGFloat d = (ddy1 * inv01) + (ddy2 * inv11);
    CGFloat tx = d0.x - (a * s0.x) - (c * s0.y);
    CGFloat ty = d0.y - (b * s0.x) - (d * s0.y);

    PETAffineTriangleTransform result;
    result.valid = true;
    result.transform = CGAffineTransformMake(a, b, c, d, tx, ty);
    return result;
}

static inline CGFloat PETClampUnitFloat(float value) {
    return MIN(1.0, MAX(0.0, value));
}

static float PETRuntimeTriangleArea(vector_float2 a, vector_float2 b, vector_float2 c) {
    return ((b.x - a.x) * (c.y - a.y)) - ((b.y - a.y) * (c.x - a.x));
}

static BOOL PETRuntimePointInTriangle(vector_float2 point, vector_float2 a, vector_float2 b, vector_float2 c, vector_float3 *barycentricOut) {
    float area = PETRuntimeTriangleArea(a, b, c);
    if (fabsf(area) < 0.0001f) {
        return NO;
    }

    float w0 = PETRuntimeTriangleArea(point, b, c) / area;
    float w1 = PETRuntimeTriangleArea(point, c, a) / area;
    float w2 = 1.0f - w0 - w1;
    BOOL contains = w0 >= -0.001f && w1 >= -0.001f && w2 >= -0.001f;
    if (contains && barycentricOut != NULL) {
        *barycentricOut = (vector_float3){w0, w1, w2};
    }
    return contains;
}

static BOOL PETRuntimeImageHasVisibleAlphaAtUV(CGImageRef image, vector_float2 uv) {
    if (image == NULL) {
        return NO;
    }

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        return NO;
    }

    size_t bytesPerPixel = 4;
    size_t bytesPerRow = width * bytesPerPixel;
    size_t totalBytes = bytesPerRow * height;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL) {
        return NO;
    }

    void *bitmapData = calloc(totalBytes, sizeof(uint8_t));
    if (bitmapData == NULL) {
        CGColorSpaceRelease(colorSpace);
        return NO;
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
        return NO;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);

    float clampedU = fmaxf(0.0f, fminf(uv.x, 1.0f));
    float clampedV = fmaxf(0.0f, fminf(uv.y, 1.0f));
    NSInteger pixelX = (NSInteger)fminf((float)(width - 1), floorf(clampedU * (float)width));
    NSInteger pixelY = (NSInteger)fminf((float)(height - 1), floorf(clampedV * (float)height));
    NSInteger flippedY = (NSInteger)height - 1 - pixelY;
    BOOL hasAlpha = NO;
    NSInteger samplePoints[2][2] = {
        {pixelX, pixelY},
        {pixelX, flippedY}
    };
    uint8_t *pixels = (uint8_t *)bitmapData;
    for (NSUInteger index = 0; index < 2; index += 1) {
        NSInteger sampleX = samplePoints[index][0];
        NSInteger sampleY = samplePoints[index][1];
        if (sampleX < 0 || sampleY < 0 || sampleX >= (NSInteger)width || sampleY >= (NSInteger)height) {
            continue;
        }
        size_t offset = ((size_t)sampleY * bytesPerRow) + ((size_t)sampleX * bytesPerPixel);
        if (offset + 3 < totalBytes && pixels[offset + 3] > 12) {
            hasAlpha = YES;
            break;
        }
    }

    free(bitmapData);
    return hasAlpha;
}

static BOOL PETStringContainsAnyKeyword(NSString *string, NSArray<NSString *> *keywords) {
    NSString *normalized = string.lowercaseString ?: @"";
    if (normalized.length == 0) {
        return NO;
    }
    for (NSString *keyword in keywords) {
        if (keyword.length == 0) {
            continue;
        }
        if ([normalized containsString:keyword.lowercaseString]) {
            return YES;
        }
    }
    return NO;
}

static BOOL PETAnimationNameNeedsExperimentalEffectSlotSuppression(NSString *animationName) {
    NSString *normalized = animationName.lowercaseString ?: @"";
    if (normalized.length == 0) {
        return NO;
    }

    NSArray<NSString *> *ambientKeywords = @[
        @"idle",
        @"stand",
        @"standby",
        @"wait",
        @"waiting",
        @"run",
        @"move",
        @"walk",
        @"loop",
        @"hit",
        @"review",
        @"waving",
        @"jump"
    ];
    if (PETStringContainsAnyKeyword(normalized, ambientKeywords)) {
        return NO;
    }

    NSArray<NSString *> *effectKeywords = @[
        @"skill",
        @"boss",
        @"bigboss",
        @"ultimate",
        @"atk",
        @"attack",
        @"magic",
        @"spell",
        @"fire",
        @"wind",
        @"s1",
        @"s2",
        @"s3"
    ];
    return PETStringContainsAnyKeyword(normalized, effectKeywords);
}

static BOOL PETShouldSuppressExperimentalEffectSlotNamed(NSString *slotName, NSString *attachmentName, NSString *animationName) {
    NSArray<NSString *> *effectKeywords = @[
        @"s2shouji",
        @"shadw",
        @"shadow",
        @"sdw",
        @"sdwl",
        @"suishi",
        @"feng",
        @"fenghuo",
        @"fengxian",
        @"fx",
        @"huo",
        @"huoyan",
        @"yan",
        @"hy",
        @"hn",
        @"skill",
        @"boss",
        @"bigboss",
        @"texiao",
        @"effect"
    ];

    if (PETStringContainsAnyKeyword(slotName, effectKeywords) ||
        PETStringContainsAnyKeyword(attachmentName, effectKeywords)) {
        return YES;
    }

    NSMutableArray<NSString *> *animationKeywords = [NSMutableArray array];
    NSString *normalizedAnimation = animationName.lowercaseString ?: @"";
    if (normalizedAnimation.length > 0) {
        [animationKeywords addObject:normalizedAnimation];
        for (NSString *genericKeyword in @[@"skill", @"boss", @"bigboss", @"s1", @"s2", @"s3"]) {
            if ([normalizedAnimation containsString:genericKeyword]) {
                [animationKeywords addObject:genericKeyword];
            }
        }
    }
    return PETStringContainsAnyKeyword(slotName, animationKeywords) ||
           PETStringContainsAnyKeyword(attachmentName, animationKeywords);
}

static BOOL PETWriteNormalizedSpineJSONIfNeeded(NSURL *jsonURL,
                                                NSURL * _Nullable __autoreleasing *effectiveURL,
                                                NSError * _Nullable __autoreleasing *error) {
    NSData *data = [NSData dataWithContentsOfURL:jsonURL options:0 error:error];
    if (data == nil) {
        return NO;
    }

    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    if (![rootObject isKindOfClass:NSMutableDictionary.class]) {
        if (effectiveURL != NULL) {
            *effectiveURL = jsonURL;
        }
        return YES;
    }

    NSMutableDictionary *root = (NSMutableDictionary *)rootObject;
    id skinsObject = root[@"skins"];
    BOOL mutated = NO;

    if ([skinsObject isKindOfClass:NSDictionary.class]) {
        NSMutableArray *normalizedSkins = [NSMutableArray array];
        NSDictionary *skinsDictionary = (NSDictionary *)skinsObject;
        NSArray<NSString *> *sortedSkinNames = [[skinsDictionary allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *skinName in sortedSkinNames) {
            id attachments = skinsDictionary[skinName];
            if (![attachments isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSMutableDictionary *skinEntry = [NSMutableDictionary dictionary];
            skinEntry[@"name"] = skinName.length > 0 ? skinName : @"default";
            skinEntry[@"attachments"] = attachments;
            [normalizedSkins addObject:skinEntry];
        }
        root[@"skins"] = normalizedSkins;
        mutated = YES;
    } else if ([skinsObject isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)skinsObject) {
            if (![item isKindOfClass:NSMutableDictionary.class]) {
                continue;
            }
            NSMutableDictionary *skinEntry = (NSMutableDictionary *)item;
            NSString *name = [skinEntry[@"name"] isKindOfClass:NSString.class] ? skinEntry[@"name"] : nil;
            if (name.length == 0) {
                skinEntry[@"name"] = @"default";
                mutated = YES;
            }
        }
    }

    if (!mutated) {
        if (effectiveURL != NULL) {
            *effectiveURL = jsonURL;
        }
        return YES;
    }

    NSData *normalizedData = [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
    if (normalizedData == nil) {
        return NO;
    }

    NSString *fileName = jsonURL.lastPathComponent.length > 0 ? jsonURL.lastPathComponent : @"skeleton.json";
    NSURL *tempDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *normalizedURL = [tempDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"pet-normalized-%@-%@", NSUUID.UUID.UUIDString, fileName]];
    if (![normalizedData writeToURL:normalizedURL options:NSDataWritingAtomic error:error]) {
        return NO;
    }

    if (effectiveURL != NULL) {
        *effectiveURL = normalizedURL;
    }
    return YES;
}

static CGRect PETDesktopPetDisplayBoundsFromSpineJSONURL(NSURL *jsonURL) {
    NSData *data = [NSData dataWithContentsOfURL:jsonURL options:0 error:nil];
    if (data == nil) {
        return CGRectZero;
    }

    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![rootObject isKindOfClass:NSDictionary.class]) {
        return CGRectZero;
    }

    NSDictionary *root = (NSDictionary *)rootObject;
    NSDictionary *desktopPet = [root[@"desktopPet"] isKindOfClass:NSDictionary.class] ? root[@"desktopPet"] : nil;
    NSDictionary *displayBounds = [desktopPet[@"displayBounds"] isKindOfClass:NSDictionary.class] ? desktopPet[@"displayBounds"] : nil;
    if (displayBounds == nil) {
        return CGRectZero;
    }

    id widthValue = displayBounds[@"width"];
    id heightValue = displayBounds[@"height"];
    if (![widthValue respondsToSelector:@selector(doubleValue)] ||
        ![heightValue respondsToSelector:@selector(doubleValue)]) {
        return CGRectZero;
    }

    CGFloat width = [widthValue doubleValue];
    CGFloat height = [heightValue doubleValue];
    if (width <= 0.0 || height <= 0.0) {
        return CGRectZero;
    }

    id xValue = displayBounds[@"x"];
    id yValue = displayBounds[@"y"];
    CGFloat x = [xValue respondsToSelector:@selector(doubleValue)] ? [xValue doubleValue] : 0.0;
    CGFloat y = [yValue respondsToSelector:@selector(doubleValue)] ? [yValue doubleValue] : 0.0;
    return CGRectMake(x, y, width, height);
}

} // namespace

@interface PETSpineRuntime () {
    PETSpineTextureLoader *_textureLoader;
    spine::Atlas *_atlas;
    spine::SkeletonData *_skeletonData;
    spine::AnimationStateData *_stateData;
    spine::Skeleton *_skeleton;
    spine::AnimationState *_animationState;
    spine::Vector<float> _boundsScratch;
}

@property (nonatomic, copy, readwrite) NSArray<NSString *> *animationNames;
@property (nonatomic, copy, readwrite) NSString *versionString;
@property (nonatomic, assign, readwrite) CGSize skeletonCanvasSize;
@property (nonatomic, copy, readwrite) NSString *currentAnimationName;
@property (nonatomic, assign, readwrite) CGRect currentReferenceContentBounds;
@property (nonatomic, assign, readwrite) CGRect stableReferenceContentBounds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *referenceBoundsCache;

@end

@implementation PETSpineRenderBatch {
    CGImageRef _textureImageStorage;
}

- (instancetype)initWithVertexData:(NSData *)vertexData
                       vertexCount:(NSUInteger)vertexCount
                      textureImage:(CGImageRef)textureImage
                        textureKey:(void *)textureKey
                         blendMode:(NSInteger)blendMode {
    self = [super init];
    if (self) {
        _vertexData = [vertexData copy];
        _vertexCount = vertexCount;
        _textureImageStorage = textureImage != NULL ? CGImageRetain(textureImage) : NULL;
        _textureKey = textureKey;
        _blendMode = blendMode;
    }
    return self;
}

- (void)dealloc {
    if (_textureImageStorage != NULL) {
        CGImageRelease(_textureImageStorage);
        _textureImageStorage = NULL;
    }
}

- (CGImageRef)textureImage {
    return _textureImageStorage;
}

@end

@implementation PETSpineHitInfo

- (instancetype)initWithBoneName:(NSString *)boneName
                        slotName:(NSString *)slotName
                  attachmentName:(NSString *)attachmentName {
    self = [super init];
    if (self) {
        _boneName = [boneName copy] ?: @"";
        _slotName = [slotName copy] ?: @"";
        _attachmentName = [attachmentName copy] ?: @"";
    }
    return self;
}

@end

@implementation PETSpineRuntime

- (void)applyExperimentalEffectSlotSuppressionForAnimationNamed:(NSString *)animationName {
    if (!PETAnimationNameNeedsExperimentalEffectSlotSuppression(animationName) || _skeleton == nullptr) {
        return;
    }

    NSMutableArray<NSString *> *hiddenSlotNames = [NSMutableArray array];
    spine::Vector<spine::Slot *> &slots = _skeleton->getSlots();
    for (size_t index = 0; index < slots.size(); ++index) {
        spine::Slot *slot = slots[index];
        if (slot == nullptr || slot->getAttachment() == nullptr) {
            continue;
        }

        NSString *slotName = [NSString stringWithUTF8String:slot->getData().getName().buffer()] ?: @"";
        NSString *attachmentName = [NSString stringWithUTF8String:slot->getAttachment()->getName().buffer()] ?: @"";
        if (!PETShouldSuppressExperimentalEffectSlotNamed(slotName, attachmentName, animationName)) {
            continue;
        }

        slot->setAttachment(nullptr);
        [hiddenSlotNames addObject:[NSString stringWithFormat:@"%@(%@)", slotName, attachmentName.length > 0 ? attachmentName : @"<none>"]];
    }

    if (hiddenSlotNames.count > 0) {
        NSLog(@"[DesktopPet] Experimental effect slot suppression animation=%@ hiddenSlots=%@",
              animationName,
              hiddenSlotNames);
    }
}

- (instancetype)initWithJSONURL:(NSURL *)jsonURL
                       atlasURL:(NSURL *)atlasURL
                          error:(NSError * _Nullable __autoreleasing *)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    spine::Bone::setYDown(true);

    _textureLoader = new PETSpineTextureLoader();
    _atlas = new spine::Atlas(atlasURL.path.UTF8String, _textureLoader);
    if (_atlas == nullptr || _atlas->getPages().size() == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                         code:8101
                                     userInfo:@{NSLocalizedDescriptionKey: @"Spine atlas could not be loaded."}];
        }
        return nil;
    }

    NSURL *effectiveJSONURL = jsonURL;
    CGRect desktopPetDisplayBounds = PETDesktopPetDisplayBoundsFromSpineJSONURL(jsonURL);

    if (!PETWriteNormalizedSpineJSONIfNeeded(jsonURL, &effectiveJSONURL, error)) {
        return nil;
    }

    spine::SkeletonJson skeletonJson(_atlas);
    _skeletonData = skeletonJson.readSkeletonDataFile(effectiveJSONURL.path.UTF8String);
    if (_skeletonData == nullptr) {
        NSString *message = [NSString stringWithUTF8String:skeletonJson.getError().buffer()];
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                         code:8102
                                     userInfo:@{NSLocalizedDescriptionKey: message.length > 0 ? message : @"Spine skeleton JSON could not be parsed."}];
        }
        return nil;
    }

    _skeleton = new spine::Skeleton(_skeletonData);
    _stateData = new spine::AnimationStateData(_skeletonData);
    _stateData->setDefaultMix(0.12f);
    _animationState = new spine::AnimationState(_stateData);

    NSMutableArray<NSString *> *animationNames = [NSMutableArray array];
    for (size_t index = 0; index < _skeletonData->getAnimations().size(); ++index) {
        spine::Animation *animation = _skeletonData->getAnimations()[index];
        NSString *name = [NSString stringWithUTF8String:animation->getName().buffer()];
        if (name.length > 0) {
            [animationNames addObject:name];
        }
    }
    self.animationNames = animationNames.copy;
    self.referenceBoundsCache = [NSMutableDictionary dictionary];

    NSString *version = [NSString stringWithUTF8String:_skeletonData->getVersion().buffer()];
    self.versionString = version.length > 0 ? version : @"unknown";
    if (!CGRectIsEmpty(desktopPetDisplayBounds)) {
        self.skeletonCanvasSize = CGSizeMake(MAX(1.0, CGRectGetWidth(desktopPetDisplayBounds)),
                                             MAX(1.0, CGRectGetHeight(desktopPetDisplayBounds)));
    } else {
        self.skeletonCanvasSize = CGSizeMake(MAX(1.0, _skeletonData->getWidth()), MAX(1.0, _skeletonData->getHeight()));
    }

    NSString *defaultAnimation = nil;
    for (NSString *candidate in @[@"Idle", @"idle", @"Move", @"move"]) {
        if ([self.animationNames containsObject:candidate]) {
            defaultAnimation = candidate;
            break;
        }
    }
    if (defaultAnimation == nil) {
        defaultAnimation = self.animationNames.firstObject;
    }

    if (defaultAnimation.length > 0 && ![self setAnimationNamed:defaultAnimation loop:YES error:error]) {
        return nil;
    }

    self.stableReferenceContentBounds = [self stableReferenceBounds];

    return self;
}

- (void)dealloc {
    delete _animationState;
    delete _stateData;
    delete _skeleton;
    delete _skeletonData;
    delete _atlas;
    delete _textureLoader;
}

- (BOOL)setAnimationNamed:(NSString *)animationName
                     loop:(BOOL)loop
                    error:(NSError * _Nullable __autoreleasing *)error {
    if (animationName.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                         code:8103
                                     userInfo:@{NSLocalizedDescriptionKey: @"Animation name is empty."}];
        }
        return NO;
    }

    spine::Animation *animation = _skeletonData != nullptr ? _skeletonData->findAnimation(animationName.UTF8String) : nullptr;
    if (animation == nullptr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                         code:8104
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Animation \"%@\" was not found in this Spine skeleton.", animationName]}];
        }
        return NO;
    }

    spine::TrackEntry *entry = _animationState->setAnimation(0, animationName.UTF8String, loop);
    if (entry == nullptr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                         code:8104
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Animation \"%@\" was not found in this Spine skeleton.", animationName]}];
        }
        return NO;
    }

    self.currentAnimationName = animationName;
    _animationState->apply(*_skeleton);
    [self applyExperimentalEffectSlotSuppressionForAnimationNamed:animationName];
    _skeleton->updateWorldTransform();
    self.currentReferenceContentBounds = [self referenceContentBoundsForAnimationNamed:animationName];
    return YES;
}

- (NSTimeInterval)durationForAnimationNamed:(NSString *)animationName {
    if (animationName.length == 0) {
        return 0.0;
    }

    spine::Animation *animation = _skeletonData->findAnimation(animationName.UTF8String);
    if (animation == nullptr) {
        return 0.0;
    }
    return MAX(0.0, (NSTimeInterval)animation->getDuration());
}

- (void)advanceTime:(NSTimeInterval)deltaTime {
    float clampedDelta = (float)MAX(0.0, deltaTime);
    _skeleton->update(clampedDelta);
    _animationState->update(clampedDelta);
    _animationState->apply(*_skeleton);
    _skeleton->updateWorldTransform();
}

- (CGRect)currentContentBounds {
    float boundsX = 0.0f;
    float boundsY = 0.0f;
    float boundsWidth = 0.0f;
    float boundsHeight = 0.0f;
    _skeleton->getBounds(boundsX, boundsY, boundsWidth, boundsHeight, _boundsScratch);
    return CGRectMake(boundsX, boundsY, boundsWidth, boundsHeight);
}

- (CGRect)referenceContentBoundsForAnimationNamed:(NSString *)animationName {
    if (animationName.length == 0) {
        return [self fallbackReferenceBounds];
    }

    NSValue *cachedValue = self.referenceBoundsCache[animationName];
    if (cachedValue != nil) {
        return PETPlatformRectValue(cachedValue);
    }

    spine::Animation *animation = _skeletonData->findAnimation(animationName.UTF8String);
    if (animation == nullptr) {
        return [self fallbackReferenceBounds];
    }

    spine::Skeleton sampledSkeleton(_skeletonData);
    float duration = animation->getDuration();
    NSUInteger sampleCount = duration > 0.0f ? MAX((NSUInteger)24, MIN((NSUInteger)90, (NSUInteger)ceil(duration * 30.0f))) : 1;
    CGRect unionBounds = CGRectZero;
    BOOL hasBounds = NO;

    for (NSUInteger sampleIndex = 0; sampleIndex < sampleCount; sampleIndex += 1) {
        float time = 0.0f;
        if (duration > 0.0f && sampleCount > 1) {
            time = duration * ((float)sampleIndex / (float)(sampleCount - 1));
        }

        sampledSkeleton.setToSetupPose();
        animation->apply(sampledSkeleton, 0.0f, time, true, nullptr, 1.0f, spine::MixBlend_Replace, spine::MixDirection_In);
        sampledSkeleton.updateWorldTransform();

        float boundsX = 0.0f;
        float boundsY = 0.0f;
        float boundsWidth = 0.0f;
        float boundsHeight = 0.0f;
        spine::Vector<float> sampledBoundsScratch;
        sampledSkeleton.getBounds(boundsX, boundsY, boundsWidth, boundsHeight, sampledBoundsScratch);
        CGRect sampleBounds = CGRectMake(boundsX, boundsY, boundsWidth, boundsHeight);
        if (CGRectIsEmpty(sampleBounds)) {
            continue;
        }

        unionBounds = hasBounds ? CGRectUnion(unionBounds, sampleBounds) : sampleBounds;
        hasBounds = YES;
    }

    CGRect resolvedBounds = hasBounds ? unionBounds : [self fallbackReferenceBounds];
    self.referenceBoundsCache[animationName] = PETPlatformValueWithRect(resolvedBounds);
    return resolvedBounds;
}

- (CGRect)fallbackReferenceBounds {
    CGRect currentBounds = [self currentContentBounds];
    if (!CGRectIsEmpty(currentBounds)) {
        return currentBounds;
    }

    CGSize canvasSize = self.skeletonCanvasSize;
    return CGRectMake(0.0, 0.0, MAX(1.0, canvasSize.width), MAX(1.0, canvasSize.height));
}

- (CGRect)stableReferenceBounds {
    NSMutableArray<NSString *> *preferredAnimations = [NSMutableArray array];
    if (self.currentAnimationName.length > 0) {
        [preferredAnimations addObject:self.currentAnimationName];
    }
    for (NSString *candidate in @[@"Idle", @"idle", @"Stand", @"stand", @"Wait", @"wait"]) {
        if ([self.animationNames containsObject:candidate]) {
            [preferredAnimations addObject:candidate];
        }
    }

    if (preferredAnimations.count == 0 && self.animationNames.firstObject.length > 0) {
        [preferredAnimations addObject:self.animationNames.firstObject];
    }

    for (NSString *animationName in preferredAnimations) {
        CGRect bounds = [self referenceContentBoundsForAnimationNamed:animationName];
        if (!CGRectIsEmpty(bounds)) {
            return bounds;
        }
    }

    return [self fallbackReferenceBounds];
}

- (NSArray<PETSpineRenderBatch *> *)currentRenderBatchesWithError:(NSError * _Nullable __autoreleasing *)error {
    NSMutableArray<PETSpineRenderBatch *> *batches = [NSMutableArray array];
    NSMutableData *currentVertexData = nil;
    NSUInteger currentVertexCount = 0;
    CGImageRef currentTextureImage = NULL;
    void *currentTextureKey = NULL;
    NSInteger currentBlendMode = spine::BlendMode_Normal;
    spine::SkeletonClipping clipper;

    for (size_t slotIndex = 0; slotIndex < _skeleton->getDrawOrder().size(); ++slotIndex) {
        spine::Slot *slot = _skeleton->getDrawOrder()[slotIndex];
        spine::Attachment *attachment = slot->getAttachment();
        if (attachment == nullptr || !slot->getBone().isActive()) {
            clipper.clipEnd(*slot);
            continue;
        }

        if (attachment->getRTTI().isExactly(spine::ClippingAttachment::rtti)) {
            clipper.clipStart(*slot, static_cast<spine::ClippingAttachment *>(attachment));
            continue;
        }

        float skeletonAlpha = _skeleton->getColor().a;
        float slotAlpha = slot->getColor().a;
        if (skeletonAlpha <= 0.0f || slotAlpha <= 0.0f) {
            clipper.clipEnd(*slot);
            continue;
        }

        spine::Vector<float> *vertices = nullptr;
        spine::Vector<float> *uvs = nullptr;
        const unsigned short *indices = nullptr;
        size_t indexCount = 0;
        spine::Color *attachmentColor = nullptr;
        spine::AtlasRegion *atlasRegion = nullptr;
        spine::Vector<float> localVertices;

        if (attachment->getRTTI().isExactly(spine::RegionAttachment::rtti)) {
            auto *regionAttachment = static_cast<spine::RegionAttachment *>(attachment);
            attachmentColor = &regionAttachment->getColor();
            if (attachmentColor->a <= 0.0f) {
                clipper.clipEnd(*slot);
                continue;
            }

            static const unsigned short quadIndices[] = {0, 1, 2, 2, 3, 0};
            localVertices.setSize(8, 0.0f);
            regionAttachment->computeWorldVertices(slot->getBone(), localVertices, 0, 2);
            vertices = &localVertices;
            uvs = &regionAttachment->getUVs();
            indices = quadIndices;
            indexCount = 6;
            atlasRegion = static_cast<spine::AtlasRegion *>(regionAttachment->getRendererObject());
        } else if (attachment->getRTTI().isExactly(spine::MeshAttachment::rtti)) {
            auto *meshAttachment = static_cast<spine::MeshAttachment *>(attachment);
            attachmentColor = &meshAttachment->getColor();
            if (attachmentColor->a <= 0.0f) {
                clipper.clipEnd(*slot);
                continue;
            }

            localVertices.setSize(meshAttachment->getWorldVerticesLength(), 0.0f);
            meshAttachment->computeWorldVertices(*slot, 0, meshAttachment->getWorldVerticesLength(), localVertices, 0, 2);
            vertices = &localVertices;
            uvs = &meshAttachment->getUVs();
            indices = meshAttachment->getTriangles().buffer();
            indexCount = meshAttachment->getTriangles().size();
            atlasRegion = static_cast<spine::AtlasRegion *>(meshAttachment->getRendererObject());
        } else {
            clipper.clipEnd(*slot);
            continue;
        }

        if (atlasRegion == nullptr || atlasRegion->page == nullptr) {
            clipper.clipEnd(*slot);
            continue;
        }

        PETSpinePageTexture *pageTexture = static_cast<PETSpinePageTexture *>(atlasRegion->page->getRendererObject());
        if (pageTexture == nullptr || pageTexture->image == nullptr || vertices == nullptr || uvs == nullptr) {
            clipper.clipEnd(*slot);
            continue;
        }

        CGImageRef textureImage = pageTexture->image;
        void *textureKey = pageTexture;
        NSInteger blendMode = slot->getData().getBlendMode();

        if (clipper.isClipping()) {
            spine::Vector<unsigned short> indicesVector;
            indicesVector.setSize(indexCount, 0);
            for (size_t i = 0; i < indexCount; i += 1) {
                indicesVector[i] = indices[i];
            }
            clipper.clipTriangles(*vertices, indicesVector, *uvs, 2);
            vertices = &clipper.getClippedVertices();
            uvs = &clipper.getClippedUVs();
            indices = clipper.getClippedTriangles().buffer();
            indexCount = clipper.getClippedTriangles().size();
        }

        if (currentVertexData != nil && (currentTextureKey != textureKey || currentBlendMode != blendMode)) {
            [batches addObject:[[PETSpineRenderBatch alloc] initWithVertexData:currentVertexData
                                                                   vertexCount:currentVertexCount
                                                                  textureImage:currentTextureImage
                                                                    textureKey:currentTextureKey
                                                                     blendMode:currentBlendMode]];
            currentVertexData = nil;
            currentVertexCount = 0;
            currentTextureImage = NULL;
            currentTextureKey = NULL;
        }
        if (currentVertexData == nil) {
            currentVertexData = [NSMutableData data];
            currentTextureImage = textureImage;
            currentTextureKey = textureKey;
            currentBlendMode = blendMode;
        }

        vector_float4 color = {
            (float)PETClampUnitFloat(_skeleton->getColor().r * slot->getColor().r * attachmentColor->r),
            (float)PETClampUnitFloat(_skeleton->getColor().g * slot->getColor().g * attachmentColor->g),
            (float)PETClampUnitFloat(_skeleton->getColor().b * slot->getColor().b * attachmentColor->b),
            (float)PETClampUnitFloat(_skeleton->getColor().a * slot->getColor().a * attachmentColor->a)
        };

        for (size_t triangleIndex = 0; triangleIndex + 2 < indexCount; triangleIndex += 3) {
            unsigned short i0 = indices[triangleIndex];
            unsigned short i1 = indices[triangleIndex + 1];
            unsigned short i2 = indices[triangleIndex + 2];
            size_t baseIndices[] = {(size_t)i0 * 2, (size_t)i1 * 2, (size_t)i2 * 2};

            for (NSUInteger vertexIndex = 0; vertexIndex < 3; vertexIndex += 1) {
                size_t base = baseIndices[vertexIndex];
                if (base + 1 >= vertices->size() || base + 1 >= uvs->size()) {
                    continue;
                }

                PETSpineMetalVertex vertex;
                vertex.position = {(float)(*vertices)[base], (float)(*vertices)[base + 1]};
                vertex.uv = {(float)(*uvs)[base], (float)(*uvs)[base + 1]};
                vertex.color = color;
                [currentVertexData appendBytes:&vertex length:sizeof(vertex)];
                currentVertexCount += 1;
            }
        }

        clipper.clipEnd(*slot);
    }

    if (currentVertexData != nil && currentVertexCount > 0) {
        [batches addObject:[[PETSpineRenderBatch alloc] initWithVertexData:currentVertexData
                                                               vertexCount:currentVertexCount
                                                              textureImage:currentTextureImage
                                                                textureKey:currentTextureKey
                                                                 blendMode:currentBlendMode]];
    }

    if (batches.count == 0 && error != NULL) {
        *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                     code:8107
                                 userInfo:@{NSLocalizedDescriptionKey: @"No drawable Spine attachments were available for the current frame."}];
    }
    return batches.copy;
}

- (nullable PETSpineHitInfo *)hitInfoAtContentPoint:(CGPoint)contentPoint {
    spine::SkeletonClipping clipper;
    vector_float2 point = {(float)contentPoint.x, (float)contentPoint.y};

    for (int slotIndex = (int)_skeleton->getDrawOrder().size() - 1; slotIndex >= 0; slotIndex -= 1) {
        spine::Slot *slot = _skeleton->getDrawOrder()[(size_t)slotIndex];
        spine::Attachment *attachment = slot->getAttachment();
        if (attachment == nullptr || !slot->getBone().isActive()) {
            clipper.clipEnd(*slot);
            continue;
        }

        if (attachment->getRTTI().isExactly(spine::ClippingAttachment::rtti)) {
            clipper.clipStart(*slot, static_cast<spine::ClippingAttachment *>(attachment));
            continue;
        }

        float skeletonAlpha = _skeleton->getColor().a;
        float slotAlpha = slot->getColor().a;
        if (skeletonAlpha <= 0.0f || slotAlpha <= 0.0f) {
            clipper.clipEnd(*slot);
            continue;
        }

        spine::Vector<float> *vertices = nullptr;
        spine::Vector<float> *uvs = nullptr;
        const unsigned short *indices = nullptr;
        size_t indexCount = 0;
        spine::Color *attachmentColor = nullptr;
        spine::AtlasRegion *atlasRegion = nullptr;
        spine::Vector<float> localVertices;

        if (attachment->getRTTI().isExactly(spine::RegionAttachment::rtti)) {
            auto *regionAttachment = static_cast<spine::RegionAttachment *>(attachment);
            attachmentColor = &regionAttachment->getColor();
            if (attachmentColor->a <= 0.0f) {
                clipper.clipEnd(*slot);
                continue;
            }

            static const unsigned short quadIndices[] = {0, 1, 2, 2, 3, 0};
            localVertices.setSize(8, 0.0f);
            regionAttachment->computeWorldVertices(slot->getBone(), localVertices, 0, 2);
            vertices = &localVertices;
            uvs = &regionAttachment->getUVs();
            indices = quadIndices;
            indexCount = 6;
            atlasRegion = static_cast<spine::AtlasRegion *>(regionAttachment->getRendererObject());
        } else if (attachment->getRTTI().isExactly(spine::MeshAttachment::rtti)) {
            auto *meshAttachment = static_cast<spine::MeshAttachment *>(attachment);
            attachmentColor = &meshAttachment->getColor();
            if (attachmentColor->a <= 0.0f) {
                clipper.clipEnd(*slot);
                continue;
            }

            localVertices.setSize(meshAttachment->getWorldVerticesLength(), 0.0f);
            meshAttachment->computeWorldVertices(*slot, 0, meshAttachment->getWorldVerticesLength(), localVertices, 0, 2);
            vertices = &localVertices;
            uvs = &meshAttachment->getUVs();
            indices = meshAttachment->getTriangles().buffer();
            indexCount = meshAttachment->getTriangles().size();
            atlasRegion = static_cast<spine::AtlasRegion *>(meshAttachment->getRendererObject());
        } else {
            clipper.clipEnd(*slot);
            continue;
        }

        if (atlasRegion == nullptr || atlasRegion->page == nullptr) {
            clipper.clipEnd(*slot);
            continue;
        }

        PETSpinePageTexture *pageTexture = static_cast<PETSpinePageTexture *>(atlasRegion->page->getRendererObject());
        if (pageTexture == nullptr || pageTexture->image == nullptr || vertices == nullptr || uvs == nullptr) {
            clipper.clipEnd(*slot);
            continue;
        }

        if (clipper.isClipping()) {
            spine::Vector<unsigned short> indicesVector;
            indicesVector.setSize(indexCount, 0);
            for (size_t i = 0; i < indexCount; i += 1) {
                indicesVector[i] = indices[i];
            }
            clipper.clipTriangles(*vertices, indicesVector, *uvs, 2);
            vertices = &clipper.getClippedVertices();
            uvs = &clipper.getClippedUVs();
            indices = clipper.getClippedTriangles().buffer();
            indexCount = clipper.getClippedTriangles().size();
        }

        for (size_t triangleIndex = 0; triangleIndex + 2 < indexCount; triangleIndex += 3) {
            unsigned short i0 = indices[triangleIndex];
            unsigned short i1 = indices[triangleIndex + 1];
            unsigned short i2 = indices[triangleIndex + 2];
            size_t base0 = (size_t)i0 * 2;
            size_t base1 = (size_t)i1 * 2;
            size_t base2 = (size_t)i2 * 2;
            if (base0 + 1 >= vertices->size() || base1 + 1 >= vertices->size() || base2 + 1 >= vertices->size()) {
                continue;
            }
            if (base0 + 1 >= uvs->size() || base1 + 1 >= uvs->size() || base2 + 1 >= uvs->size()) {
                continue;
            }

            vector_float2 a = {(float)(*vertices)[base0], (float)(*vertices)[base0 + 1]};
            vector_float2 b = {(float)(*vertices)[base1], (float)(*vertices)[base1 + 1]};
            vector_float2 c = {(float)(*vertices)[base2], (float)(*vertices)[base2 + 1]};
            vector_float3 barycentric;
            if (!PETRuntimePointInTriangle(point, a, b, c, &barycentric)) {
                continue;
            }

            vector_float2 uv =
                (((vector_float2){(float)(*uvs)[base0], (float)(*uvs)[base0 + 1]}) * barycentric.x) +
                (((vector_float2){(float)(*uvs)[base1], (float)(*uvs)[base1 + 1]}) * barycentric.y) +
                (((vector_float2){(float)(*uvs)[base2], (float)(*uvs)[base2 + 1]}) * barycentric.z);
            if (!PETRuntimeImageHasVisibleAlphaAtUV(pageTexture->image, uv)) {
                continue;
            }

            NSString *boneName = [NSString stringWithUTF8String:slot->getBone().getData().getName().buffer()] ?: @"";
            NSString *slotName = [NSString stringWithUTF8String:slot->getData().getName().buffer()] ?: @"";
            NSString *attachmentName = [NSString stringWithUTF8String:attachment->getName().buffer()] ?: @"";
            return [[PETSpineHitInfo alloc] initWithBoneName:boneName slotName:slotName attachmentName:attachmentName];
        }

        clipper.clipEnd(*slot);
    }

    return nil;
}

- (PETPlatformImage *)renderPreviewImageWithSize:(CGSize)size
                                    contentScale:(CGFloat)contentScale
                                    backingScale:(CGFloat)backingScale
                                           error:(NSError * _Nullable __autoreleasing *)error {
    CGFloat logicalWidth = MAX(1.0, size.width);
    CGFloat logicalHeight = MAX(1.0, size.height);
    CGFloat resolvedBackingScale = MAX(1.0, backingScale);
    size_t pixelWidth = (size_t)llround(logicalWidth * resolvedBackingScale);
    size_t pixelHeight = (size_t)llround(logicalHeight * resolvedBackingScale);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 pixelWidth,
                                                 pixelHeight,
                                                 8,
                                                 pixelWidth * 4,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == nullptr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                         code:8105
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create bitmap context for Spine preview."}];
        }
        return nil;
    }

    CGContextScaleCTM(context, resolvedBackingScale, resolvedBackingScale);
    CGContextTranslateCTM(context, 0.0, logicalHeight);
    CGContextScaleCTM(context, 1.0, -1.0);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextClearRect(context, CGRectMake(0.0, 0.0, logicalWidth, logicalHeight));

    float boundsX = 0.0f;
    float boundsY = 0.0f;
    float boundsWidth = 0.0f;
    float boundsHeight = 0.0f;
    _skeleton->getBounds(boundsX, boundsY, boundsWidth, boundsHeight, _boundsScratch);

    CGFloat padding = 20.0;
    CGFloat availableWidth = MAX(1.0, logicalWidth - (padding * 2.0));
    CGFloat availableHeight = MAX(1.0, logicalHeight - (padding * 2.0));
    CGFloat fitScaleX = availableWidth / MAX(1.0, boundsWidth);
    CGFloat fitScaleY = availableHeight / MAX(1.0, boundsHeight);
    CGFloat fitScale = MIN(fitScaleX, fitScaleY);
    fitScale *= MAX(0.1, contentScale);
    CGFloat offsetX = padding + ((availableWidth - (boundsWidth * fitScale)) * 0.5) - (boundsX * fitScale);
    CGFloat offsetY = padding + ((availableHeight - (boundsHeight * fitScale)) * 0.5) - (boundsY * fitScale);

    static const unsigned short quadIndices[] = {0, 1, 2, 2, 3, 0};

    for (size_t slotIndex = 0; slotIndex < _skeleton->getDrawOrder().size(); ++slotIndex) {
        spine::Slot *slot = _skeleton->getDrawOrder()[slotIndex];
        spine::Attachment *attachment = slot->getAttachment();
        if (attachment == nullptr || !slot->getBone().isActive()) {
            continue;
        }

        float skeletonAlpha = _skeleton->getColor().a;
        float slotAlpha = slot->getColor().a;
        if (skeletonAlpha <= 0.0f || slotAlpha <= 0.0f) {
            continue;
        }

        spine::Vector<float> *vertices = nullptr;
        spine::Vector<float> *uvs = nullptr;
        const unsigned short *indices = nullptr;
        size_t indexCount = 0;
        spine::Color *attachmentColor = nullptr;
        spine::AtlasRegion *atlasRegion = nullptr;
        spine::Vector<float> localVertices;

        if (attachment->getRTTI().isExactly(spine::RegionAttachment::rtti)) {
            auto *regionAttachment = static_cast<spine::RegionAttachment *>(attachment);
            attachmentColor = &regionAttachment->getColor();
            if (attachmentColor->a <= 0.0f) {
                continue;
            }

            localVertices.setSize(8, 0.0f);
            regionAttachment->computeWorldVertices(slot->getBone(), localVertices, 0, 2);
            vertices = &localVertices;
            uvs = &regionAttachment->getUVs();
            indices = quadIndices;
            indexCount = 6;
            atlasRegion = static_cast<spine::AtlasRegion *>(regionAttachment->getRendererObject());
        } else if (attachment->getRTTI().isExactly(spine::MeshAttachment::rtti)) {
            auto *meshAttachment = static_cast<spine::MeshAttachment *>(attachment);
            attachmentColor = &meshAttachment->getColor();
            if (attachmentColor->a <= 0.0f) {
                continue;
            }

            localVertices.setSize(meshAttachment->getWorldVerticesLength(), 0.0f);
            meshAttachment->computeWorldVertices(*slot, 0, meshAttachment->getWorldVerticesLength(), localVertices, 0, 2);
            vertices = &localVertices;
            uvs = &meshAttachment->getUVs();
            indices = meshAttachment->getTriangles().buffer();
            indexCount = meshAttachment->getTriangles().size();
            atlasRegion = static_cast<spine::AtlasRegion *>(meshAttachment->getRendererObject());
        } else {
            continue;
        }

        if (atlasRegion == nullptr || atlasRegion->page == nullptr) {
            continue;
        }

        PETSpinePageTexture *pageTexture = static_cast<PETSpinePageTexture *>(atlasRegion->page->getRendererObject());
        if (pageTexture == nullptr || pageTexture->image == nullptr || vertices == nullptr || uvs == nullptr) {
            continue;
        }

        CGFloat attachmentAlpha = PETClampUnitFloat(skeletonAlpha * slotAlpha * attachmentColor->a);
        if (attachmentAlpha <= 0.0) {
            continue;
        }

        for (size_t triangleIndex = 0; triangleIndex + 2 < indexCount; triangleIndex += 3) {
            unsigned short i0 = indices[triangleIndex];
            unsigned short i1 = indices[triangleIndex + 1];
            unsigned short i2 = indices[triangleIndex + 2];

            size_t v0 = (size_t)i0 * 2;
            size_t v1 = (size_t)i1 * 2;
            size_t v2 = (size_t)i2 * 2;
            if (v2 + 1 >= vertices->size() || v2 + 1 >= uvs->size()) {
                continue;
            }

            CGPoint destination0 = CGPointMake(((*vertices)[v0] * fitScale) + offsetX, ((*vertices)[v0 + 1] * fitScale) + offsetY);
            CGPoint destination1 = CGPointMake(((*vertices)[v1] * fitScale) + offsetX, ((*vertices)[v1 + 1] * fitScale) + offsetY);
            CGPoint destination2 = CGPointMake(((*vertices)[v2] * fitScale) + offsetX, ((*vertices)[v2 + 1] * fitScale) + offsetY);

            CGPoint source0 = CGPointMake((*uvs)[v0] * pageTexture->width, (1.0 - (*uvs)[v0 + 1]) * pageTexture->height);
            CGPoint source1 = CGPointMake((*uvs)[v1] * pageTexture->width, (1.0 - (*uvs)[v1 + 1]) * pageTexture->height);
            CGPoint source2 = CGPointMake((*uvs)[v2] * pageTexture->width, (1.0 - (*uvs)[v2 + 1]) * pageTexture->height);

            PETAffineTriangleTransform triangleTransform = PETAffineTransformForTriangles(source0, source1, source2,
                                                                                          destination0, destination1, destination2);
            if (!triangleTransform.valid) {
                continue;
            }

            CGContextSaveGState(context);
            CGContextBeginPath(context);
            CGContextMoveToPoint(context, destination0.x, destination0.y);
            CGContextAddLineToPoint(context, destination1.x, destination1.y);
            CGContextAddLineToPoint(context, destination2.x, destination2.y);
            CGContextClosePath(context);
            CGContextClip(context);
            CGContextSetAlpha(context, attachmentAlpha);
            CGContextConcatCTM(context, triangleTransform.transform);
            CGContextDrawImage(context,
                               CGRectMake(0.0, 0.0, (CGFloat)pageTexture->width, (CGFloat)pageTexture->height),
                               pageTexture->image);
            CGContextRestoreGState(context);
        }
    }

    CGImageRef frameImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (frameImage == nullptr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineRuntimeErrorDomain
                                         code:8106
                                     userInfo:@{NSLocalizedDescriptionKey: @"Spine preview image could not be finalized."}];
        }
        return nil;
    }

    PETPlatformImage *image = PETPlatformImageFromCGImage(frameImage, CGSizeMake(logicalWidth, logicalHeight));
    CGImageRelease(frameImage);
    return image;
}

@end
