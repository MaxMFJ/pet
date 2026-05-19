#import "PETSpineMetalView.h"

#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

#import "../Models/PETPetProfile.h"
#import "../Services/PETSpineRuntime.h"

static NSString * const PETSpineMetalViewErrorDomain = @"PETSpineMetalView";

typedef struct {
    matrix_float4x4 transform;
} PETSpineUniforms;

@interface PETSpineTextureAlphaMask : NSObject

@property (nonatomic, strong, readonly) NSData *pixelData;
@property (nonatomic, assign, readonly) size_t width;
@property (nonatomic, assign, readonly) size_t height;
@property (nonatomic, assign, readonly) size_t bytesPerRow;

- (instancetype)initWithPixelData:(NSData *)pixelData
                            width:(size_t)width
                           height:(size_t)height
                      bytesPerRow:(size_t)bytesPerRow;

@end

static matrix_float4x4 PETMatrixIdentity(void) {
    return matrix_identity_float4x4;
}

static matrix_float4x4 PETMatrixMultiply(matrix_float4x4 left, matrix_float4x4 right) {
    return simd_mul(left, right);
}

static matrix_float4x4 PETMatrixTranslation(float tx, float ty, float tz) {
    matrix_float4x4 matrix = PETMatrixIdentity();
    matrix.columns[3] = (vector_float4){tx, ty, tz, 1.0f};
    return matrix;
}

static matrix_float4x4 PETMatrixScale(float sx, float sy, float sz) {
    matrix_float4x4 matrix = PETMatrixIdentity();
    matrix.columns[0].x = sx;
    matrix.columns[1].y = sy;
    matrix.columns[2].z = sz;
    return matrix;
}

static NSRect PETIntegralRect(NSRect rect) {
    return NSMakeRect(round(rect.origin.x),
                      round(rect.origin.y),
                      round(rect.size.width),
                      round(rect.size.height));
}

@interface PETSpineMetalView () <MTKViewDelegate>

@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, strong) PETSpineRuntime *runtime;
@property (nonatomic, copy, readwrite) NSString *currentState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) NSDictionary<NSNumber *, id<MTLRenderPipelineState>> *pipelineStates;
@property (nonatomic, strong) MTKTextureLoader *textureLoader;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, id<MTLTexture>> *textureCache;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, PETSpineTextureAlphaMask *> *alphaMaskCache;
@property (nonatomic, copy) NSArray<PETSpineRenderBatch *> *lastRenderedBatches;
@property (nonatomic, assign) matrix_float4x4 lastTransform;
@property (nonatomic, assign) CGSize lastDrawableSize;
@property (nonatomic, assign) CFTimeInterval lastFrameTimestamp;
@property (nonatomic, assign) NSPoint dragStartPoint;
@property (nonatomic, assign) BOOL didDragDuringMouseSession;
@property (nonatomic, assign) BOOL dragEligibleForCurrentMouseSession;

@end

@implementation PETSpineTextureAlphaMask

- (instancetype)initWithPixelData:(NSData *)pixelData
                            width:(size_t)width
                           height:(size_t)height
                      bytesPerRow:(size_t)bytesPerRow {
    self = [super init];
    if (self != nil) {
        _pixelData = pixelData;
        _width = width;
        _height = height;
        _bytesPerRow = bytesPerRow;
    }
    return self;
}

@end

@implementation PETSpineMetalView

static vector_float2 PETClipPointToDrawablePoint(vector_float4 clipPosition, CGSize drawableSize) {
    float x = ((clipPosition.x * 0.5f) + 0.5f) * (float)drawableSize.width;
    float y = (1.0f - ((clipPosition.y * 0.5f) + 0.5f)) * (float)drawableSize.height;
    return (vector_float2){x, y};
}

static float PETTriangleArea(vector_float2 a, vector_float2 b, vector_float2 c) {
    return ((b.x - a.x) * (c.y - a.y)) - ((b.y - a.y) * (c.x - a.x));
}

static BOOL PETPointInTriangle(vector_float2 point, vector_float2 a, vector_float2 b, vector_float2 c, vector_float3 *barycentricOut) {
    float area = PETTriangleArea(a, b, c);
    if (fabsf(area) < 0.0001f) {
        return NO;
    }

    float w0 = PETTriangleArea(point, b, c) / area;
    float w1 = PETTriangleArea(point, c, a) / area;
    float w2 = 1.0f - w0 - w1;
    BOOL contains = w0 >= -0.001f && w1 >= -0.001f && w2 >= -0.001f;
    if (contains && barycentricOut != NULL) {
        *barycentricOut = (vector_float3){w0, w1, w2};
    }
    return contains;
}

static BOOL PETSpinePixelBufferHasVisibleAlphaAtPoint(const uint8_t *pixels,
                                                      size_t width,
                                                      size_t height,
                                                      size_t bytesPerRow,
                                                      NSInteger pixelX,
                                                      NSInteger pixelY) {
    if (pixels == NULL || width == 0 || height == 0 || bytesPerRow == 0) {
        return NO;
    }
    if (pixelX < 0 || pixelY < 0 || pixelX >= (NSInteger)width || pixelY >= (NSInteger)height) {
        return NO;
    }

    size_t offset = ((size_t)pixelY * bytesPerRow) + ((size_t)pixelX * 4);
    return pixels[offset + 3] > 12;
}

static BOOL PETAlphaMaskHasVisibleAlphaAtUV(PETSpineTextureAlphaMask *alphaMask, vector_float2 uv) {
    if (alphaMask == nil) {
        return NO;
    }

    size_t width = alphaMask.width;
    size_t height = alphaMask.height;
    const uint8_t *pixels = (const uint8_t *)alphaMask.pixelData.bytes;
    size_t bytesPerRow = alphaMask.bytesPerRow;
    if (pixels == NULL || width == 0 || height == 0 || bytesPerRow == 0) {
        return NO;
    }

    float clampedU = fmaxf(0.0f, fminf(uv.x, 1.0f));
    float clampedV = fmaxf(0.0f, fminf(uv.y, 1.0f));
    NSInteger pixelX = (NSInteger)fminf((float)(width - 1), floorf(clampedU * (float)width));
    NSInteger pixelY = (NSInteger)fminf((float)(height - 1), floorf(clampedV * (float)height));
    if (PETSpinePixelBufferHasVisibleAlphaAtPoint(pixels, width, height, bytesPerRow, pixelX, pixelY)) {
        return YES;
    }

    NSInteger flippedY = (NSInteger)height - 1 - pixelY;
    return PETSpinePixelBufferHasVisibleAlphaAtPoint(pixels, width, height, bytesPerRow, pixelX, flippedY);
}

- (nullable PETSpineTextureAlphaMask *)alphaMaskForBatch:(PETSpineRenderBatch *)batch {
    NSValue *key = [NSValue valueWithPointer:batch.textureKey];
    PETSpineTextureAlphaMask *cachedMask = self.alphaMaskCache[key];
    if (cachedMask != nil) {
        return cachedMask;
    }

    CGImageRef image = batch.textureImage;
    if (image == NULL) {
        return nil;
    }

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        return nil;
    }

    size_t bytesPerRow = width * 4;
    NSMutableData *pixelData = [NSMutableData dataWithLength:bytesPerRow * height];
    if (pixelData.length == 0) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL) {
        return nil;
    }

    CGContextRef context = CGBitmapContextCreate(pixelData.mutableBytes,
                                                 width,
                                                 height,
                                                 8,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        return nil;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);

    PETSpineTextureAlphaMask *alphaMask = [[PETSpineTextureAlphaMask alloc] initWithPixelData:pixelData
                                                                                         width:width
                                                                                        height:height
                                                                                   bytesPerRow:bytesPerRow];
    self.alphaMaskCache[key] = alphaMask;
    return alphaMask;
}

- (instancetype)initWithProfile:(PETPetProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSpineMetalViewErrorDomain
                                         code:8201
                                     userInfo:@{NSLocalizedDescriptionKey: @"Metal device is unavailable on this Mac."}];
        }
        return nil;
    }

    self = [super initWithFrame:NSMakeRect(0, 0, profile.canvasSize.width, profile.canvasSize.height) device:device];
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
    _facingRight = YES;
    _commandQueue = [device newCommandQueue];
    _textureLoader = [[MTKTextureLoader alloc] initWithDevice:device];
    _textureCache = [NSMutableDictionary dictionary];
    _alphaMaskCache = [NSMutableDictionary dictionary];
    _contentLayoutRect = NSZeroRect;

    self.delegate = self;
    self.enableSetNeedsDisplay = NO;
    self.paused = NO;
    self.preferredFramesPerSecond = 60;
    self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = YES;
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    self.layer.opaque = NO;

    NSError *pipelineError = nil;
    id<MTLLibrary> library = [device newDefaultLibraryWithBundle:NSBundle.mainBundle error:&pipelineError];
    if (library == nil) {
        if (error != NULL) {
            *error = pipelineError ?: [NSError errorWithDomain:PETSpineMetalViewErrorDomain
                                                          code:8202
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
            *error = pipelineError ?: [NSError errorWithDomain:PETSpineMetalViewErrorDomain
                                                          code:8203
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
        case 1: // additive
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
            break;
        case 2: // multiply
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorDestinationColor;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
        case 3: // screen
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceColor;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
        default: // normal
            descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            break;
    }

    return [self.device newRenderPipelineStateWithDescriptor:descriptor error:error];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (nullable NSView *)hitTest:(NSPoint)point {
    if (![self containsInteractiveContentAtPoint:point]) {
        return nil;
    }
    return [super hitTest:point];
}

- (void)startAnimating {
    self.paused = NO;
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
    } else {
        NSLog(@"[DesktopPet] Spine playState failed state=%@ loop=%@ error=%@",
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

- (NSTimeInterval)durationForState:(NSString *)state {
    if (state.length == 0) {
        return 0.0;
    }
    return [self.runtime durationForAnimationNamed:state];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragStartPoint = event.locationInWindow;
    self.didDragDuringMouseSession = NO;
    NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];
    self.dragEligibleForCurrentMouseSession = [self containsDraggableContentAtPoint:localPoint];
    if (self.dragStateChangeHandler != nil) {
        self.dragStateChangeHandler(NO);
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSWindow *window = self.window;
    if (window == nil || !self.dragEligibleForCurrentMouseSession) {
        return;
    }

    NSPoint currentPoint = event.locationInWindow;
    NSPoint origin = window.frame.origin;
    CGFloat deltaX = currentPoint.x - self.dragStartPoint.x;
    origin.x += deltaX;
    origin.y += currentPoint.y - self.dragStartPoint.y;
    [window setFrameOrigin:origin];
    self.didDragDuringMouseSession = YES;
    if (self.dragStateChangeHandler != nil) {
        self.dragStateChangeHandler(YES);
    }
    if (self.dragMovementHandler != nil) {
        self.dragMovementHandler(deltaX);
    }
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (!self.didDragDuringMouseSession && self.interactionHandler != nil) {
        self.interactionHandler();
    }
    if (self.dragStateChangeHandler != nil) {
        self.dragStateChangeHandler(NO);
    }
}

- (void)rightMouseUp:(NSEvent *)event {
    (void)event;
    if (self.secondaryInteractionHandler != nil) {
        self.secondaryInteractionHandler();
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    if (self.profile.supportedStates.count == 0) {
        return nil;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Pet Actions"];
    for (NSString *state in self.profile.supportedStates) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:state action:@selector(handleMenuAction:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = state;
        [menu addItem:item];
    }
    return menu;
}

- (void)handleMenuAction:(NSMenuItem *)sender {
    NSString *state = [sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : nil;
    if (state.length > 0 && self.menuActionHandler != nil) {
        self.menuActionHandler(state);
    }
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (PETSpineRuntime *)spineRuntime {
    return self.runtime;
}

- (void)seekToAnimationTime:(NSTimeInterval)time {
    [self.runtime setAnimationTime:time];
    [self setNeedsDisplay:YES];
}

- (void)redrawSpineFrame {
    [self setNeedsDisplay:YES];
}

- (NSData *)vertexDataByApplyingShaderPayload:(NSData *)sourceData vertexCount:(NSUInteger)vertexCount {
    if (self.activeShaderPayload.count == 0 || sourceData.length == 0 || vertexCount == 0) {
        return sourceData;
    }
    NSDictionary *params = [self.activeShaderPayload[@"params"] isKindOfClass:NSDictionary.class] ? self.activeShaderPayload[@"params"] : @{};
    float intensity = [params[@"intensity"] respondsToSelector:@selector(floatValue)] ? (float)[params[@"intensity"] floatValue] : 1.0f;
    intensity = MAX(0.0f, MIN(intensity, 3.0f));
    NSString *shaderName = [self.activeShaderPayload[@"shader"] isKindOfClass:NSString.class] ? self.activeShaderPayload[@"shader"] : @"glow";

    vector_float4 tint = {1.0f, 1.0f, 1.0f, 1.0f};
    if ([shaderName isEqualToString:@"glow"] || [shaderName isEqualToString:@"outline"]) {
        float boost = 0.25f * intensity;
        tint = (vector_float4){1.0f + boost, 1.0f + (boost * 0.35f), 1.0f + (boost * 1.2f), 1.0f};
    } else if ([shaderName isEqualToString:@"desaturate"]) {
        tint = (vector_float4){0.85f, 0.85f, 0.85f, 1.0f};
    }

    NSMutableData *mutableData = [sourceData mutableCopy];
    PETSpineMetalVertex *vertices = (PETSpineMetalVertex *)mutableData.mutableBytes;
    for (NSUInteger index = 0; index < vertexCount; index++) {
        vector_float4 color = vertices[index].color;
        vertices[index].color = (vector_float4){
            MIN(color.x * tint.x, 1.0f),
            MIN(color.y * tint.y, 1.0f),
            MIN(color.z * tint.z, 1.0f),
            color.w
        };
    }
    return mutableData;
}

- (void)drawInMTKView:(MTKView *)view {
    if (view.currentDrawable == nil || view.currentRenderPassDescriptor == nil) {
        return;
    }

    if (!self.editorPlaybackEnabled) {
        CFTimeInterval now = CACurrentMediaTime();
        CFTimeInterval deltaTime = self.lastFrameTimestamp > 0.0 ? (now - self.lastFrameTimestamp) : (1.0 / 60.0);
        self.lastFrameTimestamp = now;
        deltaTime = MAX(1.0 / 120.0, MIN(deltaTime, 1.0 / 12.0));
        [self.runtime advanceTime:deltaTime];
    }

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
                                                       drawableSize:view.drawableSize
                                                  contentLayoutRect:[self effectiveContentLayoutRect]];
    self.lastRenderedBatches = batches;
    self.lastTransform = transform;
    self.lastDrawableSize = view.drawableSize;
    PETSpineUniforms uniforms = {
        .transform = transform
    };
    id<MTLBuffer> uniformBuffer = [self.device newBufferWithBytes:&uniforms length:sizeof(uniforms) options:MTLResourceStorageModeShared];
    if (uniformBuffer == nil) {
        return;
    }

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    [encoder setVertexBuffer:uniformBuffer offset:0 atIndex:1];
    [encoder setFragmentBuffer:uniformBuffer offset:0 atIndex:1];

    for (PETSpineRenderBatch *batch in batches) {
        id<MTLTexture> texture = [self textureForBatch:batch];
        id<MTLRenderPipelineState> pipelineState = self.pipelineStates[@(batch.blendMode)] ?: self.pipelineStates[@0];
        if (texture == nil || batch.vertexCount == 0 || pipelineState == nil) {
            continue;
        }

        NSData *vertexData = [self vertexDataByApplyingShaderPayload:batch.vertexData vertexCount:batch.vertexCount];
        [encoder setRenderPipelineState:pipelineState];
        id<MTLBuffer> vertexBuffer = [self.device newBufferWithBytes:vertexData.bytes
                                                              length:vertexData.length
                                                             options:MTLResourceStorageModeShared];
        [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
        [encoder setFragmentTexture:texture atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:batch.vertexCount];
    }

    [encoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (matrix_float4x4)transformationMatrixForBounds:(CGRect)contentBounds
                                    drawableSize:(CGSize)drawableSize
                               contentLayoutRect:(NSRect)contentLayoutRect {
    CGFloat drawableWidth = MAX(1.0, drawableSize.width);
    CGFloat drawableHeight = MAX(1.0, drawableSize.height);
    CGFloat viewWidth = MAX(1.0, self.bounds.size.width);
    CGFloat viewHeight = MAX(1.0, self.bounds.size.height);
    CGFloat pointToDrawableX = drawableWidth / viewWidth;
    CGFloat pointToDrawableY = drawableHeight / viewHeight;
    NSRect layoutRect = NSIntersectionRect(PETIntegralRect(contentLayoutRect), self.bounds);
    if (NSIsEmptyRect(layoutRect) || layoutRect.size.width <= 0.0 || layoutRect.size.height <= 0.0) {
        layoutRect = self.bounds;
    }
    CGFloat layoutX = layoutRect.origin.x * pointToDrawableX;
    CGFloat layoutY = layoutRect.origin.y * pointToDrawableY;
    CGFloat layoutWidth = MAX(1.0, layoutRect.size.width * pointToDrawableX);
    CGFloat layoutHeight = MAX(1.0, layoutRect.size.height * pointToDrawableY);
    CGFloat contentWidth = MAX(1.0, CGRectGetWidth(contentBounds));
    CGFloat contentHeight = MAX(1.0, CGRectGetHeight(contentBounds));
    CGFloat padding = 18.0;
    CGFloat availableWidth = MAX(1.0, layoutWidth - (padding * 2.0));
    CGFloat availableHeight = MAX(1.0, layoutHeight - (padding * 2.0));
    CGFloat fitScale = MIN(availableWidth / contentWidth, availableHeight / contentHeight);
    fitScale = MAX(0.01, fitScale);

    CGFloat contentMidX = CGRectGetMidX(contentBounds);
    CGFloat contentMidY = CGRectGetMidY(contentBounds);
    CGFloat offsetX = layoutX + (layoutWidth * 0.5) - (contentMidX * fitScale);
    CGFloat offsetY = layoutY + (layoutHeight * 0.5) - (contentMidY * fitScale);

    matrix_float4x4 pixelToClip = PETMatrixIdentity();
    pixelToClip.columns[0].x = 2.0f / drawableWidth;
    pixelToClip.columns[1].y = -2.0f / drawableHeight;
    pixelToClip.columns[3].x = -1.0f;
    pixelToClip.columns[3].y = 1.0f;

    matrix_float4x4 orientationTransform = self.facingRight
        ? PETMatrixIdentity()
        : PETMatrixMultiply(PETMatrixTranslation((float)(contentMidX * 2.0), 0.0f, 0.0f),
                            PETMatrixScale(-1.0f, 1.0f, 1.0f));
    matrix_float4x4 contentTransform = PETMatrixMultiply(PETMatrixTranslation((float)offsetX, (float)offsetY, 0.0f),
                                                         PETMatrixMultiply(PETMatrixScale((float)fitScale, (float)fitScale, 1.0f),
                                                                           orientationTransform));
    return PETMatrixMultiply(pixelToClip, contentTransform);
}

- (NSRect)effectiveContentLayoutRect {
    if (NSIsEmptyRect(self.contentLayoutRect) ||
        self.contentLayoutRect.size.width <= 0.0 ||
        self.contentLayoutRect.size.height <= 0.0) {
        return self.bounds;
    }
    return self.contentLayoutRect;
}

- (void)setContentLayoutRect:(NSRect)contentLayoutRect {
    _contentLayoutRect = contentLayoutRect;
    [self setNeedsDisplay:YES];
}

- (NSSize)normalWindowSize {
    CGRect stableBounds = self.runtime.stableReferenceContentBounds;
    if (CGRectIsEmpty(stableBounds)) {
        stableBounds = self.runtime.currentReferenceContentBounds;
    }
    if (CGRectIsEmpty(stableBounds)) {
        stableBounds = [self.runtime currentContentBounds];
    }
    if (CGRectIsEmpty(stableBounds)) {
        return self.bounds.size;
    }

    CGFloat padding = 18.0;
    return NSMakeSize(ceil(MAX(1.0, CGRectGetWidth(stableBounds)) + (padding * 2.0)),
                      ceil(MAX(1.0, CGRectGetHeight(stableBounds)) + (padding * 2.0)));
}

- (NSSize)recommendedWindowSizeForState:(NSString *)state normalViewportSize:(NSSize)normalViewportSize {
    if (state.length == 0 || normalViewportSize.width <= 0.0 || normalViewportSize.height <= 0.0) {
        return normalViewportSize;
    }

    CGRect stableBounds = self.runtime.stableReferenceContentBounds;
    if (CGRectIsEmpty(stableBounds)) {
        stableBounds = self.runtime.currentReferenceContentBounds;
    }
    if (CGRectIsEmpty(stableBounds)) {
        stableBounds = [self.runtime currentContentBounds];
    }
    CGRect stateBounds = [self.runtime referenceContentBoundsForAnimationNamed:state];
    if (CGRectIsEmpty(stableBounds) || CGRectIsEmpty(stateBounds)) {
        return normalViewportSize;
    }

    CGFloat padding = 18.0;
    CGFloat contentWidth = MAX(1.0, CGRectGetWidth(stableBounds));
    CGFloat contentHeight = MAX(1.0, CGRectGetHeight(stableBounds));
    CGFloat availableWidth = MAX(1.0, normalViewportSize.width - (padding * 2.0));
    CGFloat availableHeight = MAX(1.0, normalViewportSize.height - (padding * 2.0));
    CGFloat fitScale = MAX(0.01, MIN(availableWidth / contentWidth, availableHeight / contentHeight));
    CGFloat stableMidX = CGRectGetMidX(stableBounds);
    CGFloat stableMidY = CGRectGetMidY(stableBounds);
    CGFloat layoutMidX = normalViewportSize.width * 0.5;
    CGFloat layoutMidY = normalViewportSize.height * 0.5;

    CGFloat visualMinX = layoutMidX + ((CGRectGetMinX(stateBounds) - stableMidX) * fitScale);
    CGFloat visualMaxX = layoutMidX + ((CGRectGetMaxX(stateBounds) - stableMidX) * fitScale);
    CGFloat visualMinY = layoutMidY + ((CGRectGetMinY(stateBounds) - stableMidY) * fitScale);
    CGFloat visualMaxY = layoutMidY + ((CGRectGetMaxY(stateBounds) - stableMidY) * fitScale);

    CGFloat overflowLeft = MAX(0.0, padding - visualMinX);
    CGFloat overflowRight = MAX(0.0, visualMaxX - (normalViewportSize.width - padding));
    CGFloat overflowTop = MAX(0.0, padding - visualMinY);
    CGFloat overflowBottom = MAX(0.0, visualMaxY - (normalViewportSize.height - padding));
    CGFloat horizontalExpansion = ceil(MAX(overflowLeft, overflowRight) * 2.0);
    CGFloat verticalExpansion = ceil(MAX(overflowTop, overflowBottom) * 2.0);

    return NSMakeSize(ceil(normalViewportSize.width + horizontalExpansion),
                      ceil(normalViewportSize.height + verticalExpansion));
}

- (id<MTLTexture>)textureForBatch:(PETSpineRenderBatch *)batch {
    NSValue *key = [NSValue valueWithPointer:batch.textureKey];
    id<MTLTexture> texture = self.textureCache[key];
    if (texture != nil) {
        return texture;
    }

    NSDictionary *options = @{
        MTKTextureLoaderOptionSRGB : @NO
    };
    NSError *error = nil;
    texture = [self.textureLoader newTextureWithCGImage:batch.textureImage options:options error:&error];
    if (texture != nil) {
        self.textureCache[key] = texture;
    }
    return texture;
}

- (BOOL)containsInteractiveContentAtPoint:(NSPoint)point {
    return [self containsOpaqueRenderedContentAtPoint:point];
}

- (BOOL)containsOpaqueRenderedContentAtPoint:(NSPoint)point {
    if (!NSPointInRect(point, self.bounds) || self.lastRenderedBatches.count == 0) {
        return NO;
    }
    if (self.bounds.size.width <= 0.0 || self.bounds.size.height <= 0.0 || self.lastDrawableSize.width <= 0.0 || self.lastDrawableSize.height <= 0.0) {
        return NO;
    }

    CGFloat scaleX = self.lastDrawableSize.width / self.bounds.size.width;
    CGFloat scaleY = self.lastDrawableSize.height / self.bounds.size.height;
    vector_float2 drawablePoint = {(float)(point.x * scaleX), (float)(point.y * scaleY)};

    NSEnumerator<PETSpineRenderBatch *> *reverseEnumerator = self.lastRenderedBatches.reverseObjectEnumerator;
    for (PETSpineRenderBatch *batch in reverseEnumerator) {
        const PETSpineMetalVertex *vertices = (const PETSpineMetalVertex *)batch.vertexData.bytes;
        if (vertices == NULL || batch.vertexCount < 3) {
            continue;
        }
        PETSpineTextureAlphaMask *alphaMask = [self alphaMaskForBatch:batch];
        if (alphaMask == nil) {
            continue;
        }

        for (NSUInteger index = 0; index + 2 < batch.vertexCount; index += 3) {
            vector_float4 clip0 = simd_mul(self.lastTransform, (vector_float4){vertices[index].position.x, vertices[index].position.y, 0.0f, 1.0f});
            vector_float4 clip1 = simd_mul(self.lastTransform, (vector_float4){vertices[index + 1].position.x, vertices[index + 1].position.y, 0.0f, 1.0f});
            vector_float4 clip2 = simd_mul(self.lastTransform, (vector_float4){vertices[index + 2].position.x, vertices[index + 2].position.y, 0.0f, 1.0f});

            vector_float2 p0 = PETClipPointToDrawablePoint(clip0, self.lastDrawableSize);
            vector_float2 p1 = PETClipPointToDrawablePoint(clip1, self.lastDrawableSize);
            vector_float2 p2 = PETClipPointToDrawablePoint(clip2, self.lastDrawableSize);

            vector_float3 barycentric;
            if (!PETPointInTriangle(drawablePoint, p0, p1, p2, &barycentric)) {
                continue;
            }

            vector_float2 uv =
                (vertices[index].uv * barycentric.x) +
                (vertices[index + 1].uv * barycentric.y) +
                (vertices[index + 2].uv * barycentric.z);
            if (PETAlphaMaskHasVisibleAlphaAtUV(alphaMask, uv)) {
                return YES;
            }
        }
    }

    return NO;
}

- (BOOL)containsDraggableContentAtPoint:(NSPoint)point {
    if (![self containsInteractiveContentAtPoint:point]) {
        return NO;
    }
    CGPoint contentPoint = CGPointZero;
    if (![self contentPoint:&contentPoint forViewPoint:point]) {
        return NO;
    }

    CGRect referenceBounds = self.runtime.stableReferenceContentBounds;
    if (CGRectIsEmpty(referenceBounds)) {
        referenceBounds = self.runtime.currentReferenceContentBounds;
    }
    if (CGRectIsEmpty(referenceBounds)) {
        referenceBounds = [self.runtime currentContentBounds];
    }
    if (CGRectIsEmpty(referenceBounds)) {
        return NO;
    }

    CGRect dragBounds = CGRectInset(referenceBounds,
                                    CGRectGetWidth(referenceBounds) * 0.2,
                                    CGRectGetHeight(referenceBounds) * 0.16);
    if (CGRectIsEmpty(dragBounds)) {
        dragBounds = referenceBounds;
    }
    return CGRectContainsPoint(dragBounds, contentPoint);
}

- (nullable NSString *)interactivePartIdentifierAtPoint:(NSPoint)point {
    PETSpineHitInfo *hitInfo = [self hitInfoAtViewPoint:point];
    if (hitInfo == nil) {
        return nil;
    }

    NSArray<NSString *> *candidates = @[
        hitInfo.attachmentName ?: @"",
        hitInfo.slotName ?: @"",
        hitInfo.boneName ?: @""
    ];
    for (NSString *candidate in candidates) {
        if (candidate.length > 0) {
            return candidate;
        }
    }
    return nil;
}

- (nullable PETSpineHitInfo *)hitInfoAtViewPoint:(NSPoint)point {
    CGPoint contentPoint = CGPointZero;
    if (![self contentPoint:&contentPoint forViewPoint:point]) {
        return nil;
    }
    return [self.runtime hitInfoAtContentPoint:contentPoint];
}

- (BOOL)contentPoint:(CGPoint *)contentPointOut forViewPoint:(NSPoint)point {
    if (!NSPointInRect(point, self.bounds) || self.bounds.size.width <= 0.0 || self.bounds.size.height <= 0.0) {
        return NO;
    }
    if (self.lastDrawableSize.width <= 0.0 || self.lastDrawableSize.height <= 0.0) {
        return NO;
    }

    CGFloat scaleX = self.lastDrawableSize.width / self.bounds.size.width;
    CGFloat scaleY = self.lastDrawableSize.height / self.bounds.size.height;
    float drawableX = (float)(point.x * scaleX);
    float drawableY = (float)(point.y * scaleY);
    float clipX = ((drawableX / (float)self.lastDrawableSize.width) * 2.0f) - 1.0f;
    float clipY = 1.0f - ((drawableY / (float)self.lastDrawableSize.height) * 2.0f);

    matrix_float4x4 inverseTransform = simd_inverse(self.lastTransform);
    vector_float4 content = simd_mul(inverseTransform, (vector_float4){clipX, clipY, 0.0f, 1.0f});
    if (contentPointOut != NULL) {
        *contentPointOut = CGPointMake(content.x, content.y);
    }
    return YES;
}

- (NSRect)visibleRenderedContentRect {
    CGRect contentBounds = [self.runtime currentContentBounds];
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = self.runtime.currentReferenceContentBounds;
    }
    if (CGRectIsEmpty(contentBounds)) {
        contentBounds = self.runtime.stableReferenceContentBounds;
    }
    if (CGRectIsEmpty(contentBounds) || self.lastDrawableSize.width <= 0.0 || self.lastDrawableSize.height <= 0.0) {
        return self.bounds;
    }

    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(contentBounds), CGRectGetMinY(contentBounds)),
        CGPointMake(CGRectGetMaxX(contentBounds), CGRectGetMinY(contentBounds)),
        CGPointMake(CGRectGetMinX(contentBounds), CGRectGetMaxY(contentBounds)),
        CGPointMake(CGRectGetMaxX(contentBounds), CGRectGetMaxY(contentBounds))
    };

    CGFloat minX = CGFLOAT_MAX;
    CGFloat minY = CGFLOAT_MAX;
    CGFloat maxX = -CGFLOAT_MAX;
    CGFloat maxY = -CGFLOAT_MAX;
    CGFloat drawableToViewX = self.bounds.size.width / MAX(1.0, self.lastDrawableSize.width);
    CGFloat drawableToViewY = self.bounds.size.height / MAX(1.0, self.lastDrawableSize.height);

    for (NSUInteger index = 0; index < 4; index += 1) {
        vector_float4 clip = simd_mul(self.lastTransform, (vector_float4){(float)corners[index].x, (float)corners[index].y, 0.0f, 1.0f});
        vector_float2 drawablePoint = PETClipPointToDrawablePoint(clip, self.lastDrawableSize);
        CGFloat viewX = drawablePoint.x * drawableToViewX;
        CGFloat viewY = drawablePoint.y * drawableToViewY;
        minX = MIN(minX, viewX);
        minY = MIN(minY, viewY);
        maxX = MAX(maxX, viewX);
        maxY = MAX(maxY, viewY);
    }

    if (maxX < minX || maxY < minY) {
        return self.bounds;
    }
    return NSIntersectionRect(NSMakeRect(minX, minY, maxX - minX, maxY - minY), self.bounds);
}

@end
