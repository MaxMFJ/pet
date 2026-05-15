#import "PETIOSSpineMetalView.h"

#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

#import "../../DesktopPet/Models/PETPetProfile.h"
#import "../../DesktopPet/Services/PETSpineRuntime.h"

static NSString * const PETIOSSpineMetalViewErrorDomain = @"PETIOSSpineMetalView";

typedef struct {
    matrix_float4x4 transform;
} PETIOSSpineUniforms;

static matrix_float4x4 PETIOSMatrixIdentity(void) {
    return matrix_identity_float4x4;
}

static matrix_float4x4 PETIOSMatrixMultiply(matrix_float4x4 left, matrix_float4x4 right) {
    return simd_mul(left, right);
}

static matrix_float4x4 PETIOSMatrixTranslation(float tx, float ty, float tz) {
    matrix_float4x4 matrix = PETIOSMatrixIdentity();
    matrix.columns[3] = (vector_float4){tx, ty, tz, 1.0f};
    return matrix;
}

static matrix_float4x4 PETIOSMatrixScale(float sx, float sy, float sz) {
    matrix_float4x4 matrix = PETIOSMatrixIdentity();
    matrix.columns[0].x = sx;
    matrix.columns[1].y = sy;
    matrix.columns[2].z = sz;
    return matrix;
}

@interface PETIOSSpineMetalView () <MTKViewDelegate>

@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, strong) PETSpineRuntime *runtime;
@property (nonatomic, copy, readwrite) NSString *currentState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) NSDictionary<NSNumber *, id<MTLRenderPipelineState>> *pipelineStates;
@property (nonatomic, strong) MTKTextureLoader *textureLoader;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, id<MTLTexture>> *textureCache;
@property (nonatomic, strong) NSMutableArray *reusableVertexBuffers;
@property (nonatomic, copy) NSArray<PETSpineRenderBatch *> *lastRenderedBatches;
@property (nonatomic, assign) matrix_float4x4 lastTransform;
@property (nonatomic, assign) CGSize lastDrawableSize;
@property (nonatomic, assign) CFTimeInterval lastFrameTimestamp;
@property (nonatomic, strong) id<MTLBuffer> reusableUniformBuffer;
@property (nonatomic, strong) NSTimer *frameRateCooldownTimer;
@property (nonatomic, assign) BOOL interactionBoosted;
@property (nonatomic, assign) BOOL temporaryFrameRateBoosted;

@end

@implementation PETIOSSpineMetalView

- (instancetype)initWithProfile:(PETPetProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETIOSSpineMetalViewErrorDomain
                                         code:9201
                                     userInfo:@{NSLocalizedDescriptionKey: @"Metal device is unavailable on this iOS device."}];
        }
        return nil;
    }

    self = [super initWithFrame:CGRectMake(0, 0, profile.canvasSize.width, profile.canvasSize.height) device:device];
    if (self == nil) {
        return nil;
    }

    NSString *atlasPath = [profile.metadata[@"atlasPath"] isKindOfClass:NSString.class] ? profile.metadata[@"atlasPath"] : @"";
    PETSpineRuntime *runtime = [[PETSpineRuntime alloc] initWithJSONURL:profile.sourceURL
                                                               atlasURL:[NSURL fileURLWithPath:atlasPath]
                                                                  error:error];
    if (runtime == nil) {
        return nil;
    }

    _profile = profile;
    _runtime = runtime;
    _currentState = [profile.defaultState copy];
    _commandQueue = [device newCommandQueue];
    _textureLoader = [[MTKTextureLoader alloc] initWithDevice:device];
    _textureCache = [NSMutableDictionary dictionary];
    _reusableVertexBuffers = [NSMutableArray array];
    _frameRateCooldownDuration = 1.2;

    self.delegate = self;
    self.enableSetNeedsDisplay = NO;
    self.paused = NO;
    self.preferredFramesPerSecond = 30;
    self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = NO;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeScaleAspectFit;

    NSError *pipelineError = nil;
    id<MTLLibrary> library = [device newDefaultLibraryWithBundle:NSBundle.mainBundle error:&pipelineError];
    if (library == nil) {
        if (error != NULL) {
            *error = pipelineError ?: [NSError errorWithDomain:PETIOSSpineMetalViewErrorDomain
                                                          code:9202
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Failed to load the default Metal shader library."}];
        }
        return nil;
    }

    NSMutableDictionary<NSNumber *, id<MTLRenderPipelineState>> *pipelineStates = [NSMutableDictionary dictionary];
    for (NSNumber *blendModeValue in @[@0, @1, @2, @3]) {
        id<MTLRenderPipelineState> pipelineState = [self buildPipelineStateForBlendMode:blendModeValue.integerValue
                                                                                library:library
                                                                                  error:&pipelineError];
        if (pipelineState == nil) {
            break;
        }
        pipelineStates[blendModeValue] = pipelineState;
    }
    _pipelineStates = [pipelineStates copy];
    if (_pipelineStates.count == 0) {
        if (error != NULL) {
            *error = pipelineError ?: [NSError errorWithDomain:PETIOSSpineMetalViewErrorDomain
                                                          code:9203
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Failed to create the Spine Metal pipeline state."}];
        }
        return nil;
    }

    return self;
}

- (nullable id<MTLRenderPipelineState>)buildPipelineStateForBlendMode:(NSInteger)blendMode
                                                              library:(id<MTLLibrary>)library
                                                                error:(NSError * _Nullable __autoreleasing *)error {
    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"petSpineVertexMain"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"petSpineFragmentMain"];
    descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;

    switch (blendMode) {
        case 1:
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
            break;
        case 2:
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorDestinationColor;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
        case 3:
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceColor;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
        default:
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
    }

    return [self.device newRenderPipelineStateWithDescriptor:descriptor error:error];
}

- (void)startAnimating {
    self.paused = NO;
    [self updatePreferredFrameRate];
}

- (void)playState:(NSString *)state {
    [self playState:state loop:YES];
}

- (void)playState:(NSString *)state loop:(BOOL)loop {
    if (state.length == 0) {
        return;
    }
    NSError *error = nil;
    if ([self.runtime setAnimationNamed:state loop:loop error:&error]) {
        self.currentState = [state copy];
        self.lastFrameTimestamp = 0.0;
        [self boostFrameRateTemporarily];
        [self setNeedsDisplay];
    } else {
        NSLog(@"[DesktopPet] iOS Spine playState failed state=%@ loop=%@ error=%@",
              state,
              loop ? @"YES" : @"NO",
              error.localizedDescription ?: @"unknown");
    }
}

- (void)pauseAnimation {
    self.paused = YES;
}

- (void)resumeDefaultAnimation {
    [self playState:self.profile.defaultState];
}

- (void)setInteractionBoosted:(BOOL)boosted {
    if (_interactionBoosted == boosted) {
        return;
    }
    _interactionBoosted = boosted;
    if (boosted) {
        [self.frameRateCooldownTimer invalidate];
        self.frameRateCooldownTimer = nil;
    } else {
        [self scheduleFrameRateCooldown];
    }
    [self updatePreferredFrameRate];
}

- (NSTimeInterval)durationForState:(NSString *)state {
    if (state.length == 0) {
        return 0.0;
    }
    return [self.runtime durationForAnimationNamed:state];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
    if (view.currentDrawable == nil || view.currentRenderPassDescriptor == nil) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval deltaTime = self.lastFrameTimestamp > 0.0 ? (now - self.lastFrameTimestamp) : (1.0 / 30.0);
    self.lastFrameTimestamp = now;
    deltaTime = MAX(1.0 / 120.0, MIN(deltaTime, 1.0 / 12.0));
    [self.runtime advanceTime:deltaTime];

    NSError *error = nil;
    NSArray<PETSpineRenderBatch *> *batches = [self.runtime currentRenderBatchesWithError:&error];
    if (batches.count == 0) {
        return;
    }

    CGRect contentBounds = self.runtime.stableReferenceContentBounds;
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = self.runtime.currentReferenceContentBounds;
    }
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = [self.runtime currentContentBounds];
    }

    matrix_float4x4 transform = [self transformationMatrixForBounds:contentBounds
                                                       drawableSize:view.drawableSize];
    self.lastRenderedBatches = batches;
    self.lastTransform = transform;
    self.lastDrawableSize = view.drawableSize;

    PETIOSSpineUniforms uniforms = {
        .transform = transform
    };
    if (self.reusableUniformBuffer == nil) {
        self.reusableUniformBuffer = [self.device newBufferWithLength:sizeof(uniforms) options:MTLResourceStorageModeShared];
    }
    memcpy(self.reusableUniformBuffer.contents, &uniforms, sizeof(uniforms));

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    [encoder setVertexBuffer:self.reusableUniformBuffer offset:0 atIndex:1];
    [encoder setFragmentBuffer:self.reusableUniformBuffer offset:0 atIndex:1];

    [self ensureReusableVertexBufferCapacity:batches.count];
    for (NSUInteger batchIndex = 0; batchIndex < batches.count; batchIndex++) {
        PETSpineRenderBatch *batch = batches[batchIndex];
        id<MTLTexture> texture = [self textureForBatch:batch];
        id<MTLRenderPipelineState> pipelineState = self.pipelineStates[@(batch.blendMode)] ?: self.pipelineStates[@0];
        if (texture == nil || batch.vertexCount == 0 || pipelineState == nil) {
            continue;
        }

        [encoder setRenderPipelineState:pipelineState];
        id<MTLBuffer> vertexBuffer = [self reusableVertexBufferAtIndex:batchIndex minimumLength:batch.vertexData.length];
        memcpy(vertexBuffer.contents, batch.vertexData.bytes, batch.vertexData.length);
        [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
        [encoder setFragmentTexture:texture atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:batch.vertexCount];
    }

    [encoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (void)ensureReusableVertexBufferCapacity:(NSUInteger)capacity {
    while (self.reusableVertexBuffers.count < capacity) {
        [self.reusableVertexBuffers addObject:[NSNull null]];
    }
}

- (id<MTLBuffer>)reusableVertexBufferAtIndex:(NSUInteger)index minimumLength:(NSUInteger)length {
    id storedBuffer = index < self.reusableVertexBuffers.count ? self.reusableVertexBuffers[index] : nil;
    id<MTLBuffer> buffer = [storedBuffer conformsToProtocol:@protocol(MTLBuffer)] ? storedBuffer : nil;
    if (buffer == nil || buffer.length < length) {
        buffer = [self.device newBufferWithLength:length options:MTLResourceStorageModeShared];
        self.reusableVertexBuffers[index] = buffer;
    }
    return buffer;
}

- (void)boostFrameRateTemporarily {
    self.temporaryFrameRateBoosted = YES;
    [self updatePreferredFrameRate];
    [self scheduleFrameRateCooldown];
}

- (void)scheduleFrameRateCooldown {
    [self.frameRateCooldownTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.frameRateCooldownTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.2, self.frameRateCooldownDuration)
                                                                  repeats:NO
                                                                    block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.frameRateCooldownTimer = nil;
        strongSelf.temporaryFrameRateBoosted = NO;
        if (!strongSelf.interactionBoosted) {
            [strongSelf updatePreferredFrameRate];
        }
    }];
}

- (void)updatePreferredFrameRate {
    self.preferredFramesPerSecond = 30;
}

- (matrix_float4x4)transformationMatrixForBounds:(CGRect)contentBounds
                                    drawableSize:(CGSize)drawableSize {
    CGFloat drawableWidth = MAX(1.0, drawableSize.width);
    CGFloat drawableHeight = MAX(1.0, drawableSize.height);
    CGFloat contentWidth = MAX(1.0, CGRectGetWidth(contentBounds));
    CGFloat contentHeight = MAX(1.0, CGRectGetHeight(contentBounds));
    CGFloat padding = 0.0;
    CGFloat availableWidth = MAX(1.0, drawableWidth - (padding * 2.0));
    CGFloat availableHeight = MAX(1.0, drawableHeight - (padding * 2.0));
    CGFloat fitScale = MIN(availableWidth / contentWidth, availableHeight / contentHeight);
    fitScale = MAX(0.01, fitScale) * 1.55;

    CGFloat contentMidX = CGRectGetMidX(contentBounds);
    CGFloat contentMidY = CGRectGetMidY(contentBounds);
    CGFloat offsetX = (drawableWidth * 0.5) - (contentMidX * fitScale);
    CGFloat offsetY = (drawableHeight * 0.5) - (contentMidY * fitScale);

    matrix_float4x4 pixelToClip = PETIOSMatrixIdentity();
    pixelToClip.columns[0].x = 2.0f / drawableWidth;
    pixelToClip.columns[1].y = -2.0f / drawableHeight;
    pixelToClip.columns[3].x = -1.0f;
    pixelToClip.columns[3].y = 1.0f;

    matrix_float4x4 contentTransform = PETIOSMatrixMultiply(PETIOSMatrixTranslation((float)offsetX, (float)offsetY, 0.0f),
                                                            PETIOSMatrixScale((float)fitScale, (float)fitScale, 1.0f));
    return PETIOSMatrixMultiply(pixelToClip, contentTransform);
}

- (id<MTLTexture>)textureForBatch:(PETSpineRenderBatch *)batch {
    NSValue *key = [NSValue valueWithPointer:batch.textureKey];
    id<MTLTexture> texture = self.textureCache[key];
    if (texture != nil) {
        return texture;
    }

    NSError *error = nil;
    texture = [self.textureLoader newTextureWithCGImage:batch.textureImage options:@{ MTKTextureLoaderOptionSRGB : @NO } error:&error];
    if (texture != nil) {
        self.textureCache[key] = texture;
    } else if (error != nil) {
        NSLog(@"[DesktopPet] iOS Spine texture load failed: %@", error.localizedDescription ?: @"unknown");
    }
    return texture;
}

- (BOOL)containsInteractiveContentAtPoint:(CGPoint)point {
    PETSpineHitInfo *hitInfo = [self.runtime hitInfoAtContentPoint:[self contentPointForViewPoint:point]];
    return hitInfo.attachmentName.length > 0 || hitInfo.slotName.length > 0 || hitInfo.boneName.length > 0;
}

- (BOOL)containsDraggableContentAtPoint:(CGPoint)point {
    return [self containsInteractiveContentAtPoint:point];
}

- (nullable NSString *)interactivePartIdentifierAtPoint:(CGPoint)point {
    PETSpineHitInfo *hitInfo = [self.runtime hitInfoAtContentPoint:[self contentPointForViewPoint:point]];
    if (hitInfo == nil) {
        return nil;
    }

    for (NSString *candidate in @[hitInfo.attachmentName ?: @"", hitInfo.slotName ?: @"", hitInfo.boneName ?: @""]) {
        if (candidate.length > 0) {
            return candidate;
        }
    }
    return nil;
}

- (CGPoint)contentPointForViewPoint:(CGPoint)point {
    if (self.bounds.size.width <= 0.0 || self.bounds.size.height <= 0.0 || self.lastDrawableSize.width <= 0.0 || self.lastDrawableSize.height <= 0.0) {
        return CGPointZero;
    }

    CGFloat scaleX = self.lastDrawableSize.width / self.bounds.size.width;
    CGFloat scaleY = self.lastDrawableSize.height / self.bounds.size.height;
    float drawableX = (float)(point.x * scaleX);
    float drawableY = (float)(point.y * scaleY);
    float clipX = ((drawableX / (float)self.lastDrawableSize.width) * 2.0f) - 1.0f;
    float clipY = 1.0f - ((drawableY / (float)self.lastDrawableSize.height) * 2.0f);

    matrix_float4x4 inverseTransform = simd_inverse(self.lastTransform);
    vector_float4 content = simd_mul(inverseTransform, (vector_float4){clipX, clipY, 0.0f, 1.0f});
    return CGPointMake(content.x, content.y);
}

@end
