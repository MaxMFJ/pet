#import "PETSpineMetalView.h"

#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

#import "../Models/PETPetProfile.h"
#import "../Services/PETSpineRuntime.h"

static NSString * const PETSpineMetalViewErrorDomain = @"PETSpineMetalView";

typedef struct {
    matrix_float4x4 transform;
} PETSpineUniforms;

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

@interface PETSpineMetalView () <MTKViewDelegate>

@property (nonatomic, strong) PETPetProfile *profile;
@property (nonatomic, strong) PETSpineRuntime *runtime;
@property (nonatomic, copy, readwrite) NSString *currentState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) NSDictionary<NSNumber *, id<MTLRenderPipelineState>> *pipelineStates;
@property (nonatomic, strong) MTKTextureLoader *textureLoader;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, id<MTLTexture>> *textureCache;
@property (nonatomic, copy) NSArray<PETSpineRenderBatch *> *lastRenderedBatches;
@property (nonatomic, assign) matrix_float4x4 lastTransform;
@property (nonatomic, assign) CGSize lastDrawableSize;
@property (nonatomic, assign) CFTimeInterval lastFrameTimestamp;
@property (nonatomic, assign) NSPoint dragStartPoint;
@property (nonatomic, assign) BOOL didDragDuringMouseSession;
@property (nonatomic, assign) BOOL dragEligibleForCurrentMouseSession;

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

static BOOL PETSpineBitmapRepHasVisibleAlphaAtPoint(NSBitmapImageRep *bitmap, NSInteger pixelX, NSInteger pixelY) {
    if (bitmap == nil) {
        return NO;
    }
    if (pixelX < 0 || pixelY < 0 || pixelX >= bitmap.pixelsWide || pixelY >= bitmap.pixelsHigh) {
        return NO;
    }
    NSColor *color = [bitmap colorAtX:pixelX y:pixelY];
    return color != nil && color.alphaComponent > (12.0 / 255.0);
}

static BOOL PETCGImageHasVisibleAlphaAtUV(CGImageRef image, vector_float2 uv) {
    if (image == NULL) {
        return NO;
    }

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        return NO;
    }

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
    if (bitmap == nil) {
        return NO;
    }

    float clampedU = fmaxf(0.0f, fminf(uv.x, 1.0f));
    float clampedV = fmaxf(0.0f, fminf(uv.y, 1.0f));
    NSInteger pixelX = (NSInteger)fminf((float)(width - 1), floorf(clampedU * (float)width));
    NSInteger pixelY = (NSInteger)fminf((float)(height - 1), floorf(clampedV * (float)height));
    if (PETSpineBitmapRepHasVisibleAlphaAtPoint(bitmap, pixelX, pixelY)) {
        return YES;
    }

    NSInteger flippedY = (NSInteger)height - 1 - pixelY;
    return PETSpineBitmapRepHasVisibleAlphaAtPoint(bitmap, pixelX, flippedY);
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

    self.delegate = self;
    self.enableSetNeedsDisplay = NO;
    self.paused = NO;
    self.preferredFramesPerSecond = 60;
    self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = NO;
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

- (void)drawInMTKView:(MTKView *)view {
    if (view.currentDrawable == nil || view.currentRenderPassDescriptor == nil) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval deltaTime = self.lastFrameTimestamp > 0.0 ? (now - self.lastFrameTimestamp) : (1.0 / 60.0);
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
    PETSpineUniforms uniforms = {
        .transform = transform
    };
    id<MTLBuffer> uniformBuffer = [self.device newBufferWithBytes:&uniforms length:sizeof(uniforms) options:MTLResourceStorageModeShared];

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

        [encoder setRenderPipelineState:pipelineState];
        id<MTLBuffer> vertexBuffer = [self.device newBufferWithBytes:batch.vertexData.bytes
                                                              length:batch.vertexData.length
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
                                    drawableSize:(CGSize)drawableSize {
    CGFloat drawableWidth = MAX(1.0, drawableSize.width);
    CGFloat drawableHeight = MAX(1.0, drawableSize.height);
    CGFloat contentWidth = MAX(1.0, CGRectGetWidth(contentBounds));
    CGFloat contentHeight = MAX(1.0, CGRectGetHeight(contentBounds));
    CGFloat padding = 18.0;
    CGFloat availableWidth = MAX(1.0, drawableWidth - (padding * 2.0));
    CGFloat availableHeight = MAX(1.0, drawableHeight - (padding * 2.0));
    CGFloat fitScale = MIN(availableWidth / contentWidth, availableHeight / contentHeight);
    fitScale = MAX(0.01, fitScale);

    CGFloat contentMidX = CGRectGetMidX(contentBounds);
    CGFloat contentMidY = CGRectGetMidY(contentBounds);
    CGFloat offsetX = (drawableWidth * 0.5) - (contentMidX * fitScale);
    CGFloat offsetY = (drawableHeight * 0.5) - (contentMidY * fitScale);

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
            if (PETCGImageHasVisibleAlphaAtUV(batch.textureImage, uv)) {
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
    if (self.bounds.size.width <= 0.0 || self.bounds.size.height <= 0.0) {
        return NO;
    }

    NSRect dragZone = NSInsetRect(self.bounds, self.bounds.size.width * 0.2, self.bounds.size.height * 0.16);
    return NSPointInRect(point, dragZone);
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
    if (!NSPointInRect(point, self.bounds) || self.bounds.size.width <= 0.0 || self.bounds.size.height <= 0.0) {
        return nil;
    }
    if (self.lastDrawableSize.width <= 0.0 || self.lastDrawableSize.height <= 0.0) {
        return nil;
    }

    CGFloat scaleX = self.lastDrawableSize.width / self.bounds.size.width;
    CGFloat scaleY = self.lastDrawableSize.height / self.bounds.size.height;
    float drawableX = (float)(point.x * scaleX);
    float drawableY = (float)(point.y * scaleY);
    float clipX = ((drawableX / (float)self.lastDrawableSize.width) * 2.0f) - 1.0f;
    float clipY = 1.0f - ((drawableY / (float)self.lastDrawableSize.height) * 2.0f);

    matrix_float4x4 inverseTransform = simd_inverse(self.lastTransform);
    vector_float4 content = simd_mul(inverseTransform, (vector_float4){clipX, clipY, 0.0f, 1.0f});
    return [self.runtime hitInfoAtContentPoint:CGPointMake(content.x, content.y)];
}

@end
