#import "PETWebPDecoder.h"

#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "../Models/PETAnimationFrame.h"

@implementation PETWebPDecoder

- (NSArray<PETAnimationFrame *> *)decodeFramesAtURL:(NSURL *)fileURL
                                         canvasSize:(PETPlatformSize *)canvasSize
                                              error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (source == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETWebPDecoder"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to open WEBP asset."}];
        }
        return nil;
    }

    size_t frameCount = CGImageSourceGetCount(source);
    if (frameCount == 0) {
        CFRelease(source);
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETWebPDecoder"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"The WEBP file contains no decodable frames."}];
        }
        return nil;
    }

    NSMutableArray<PETAnimationFrame *> *frames = [NSMutableArray arrayWithCapacity:frameCount];
    PETPlatformSize detectedCanvasSize = CGSizeZero;

    for (size_t index = 0; index < frameCount; index++) {
        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, index, NULL);
        if (cgImage == NULL) {
            continue;
        }

        if (CGSizeEqualToSize(detectedCanvasSize, CGSizeZero)) {
            detectedCanvasSize = CGSizeMake(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
        }

        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
        NSTimeInterval duration = [self animationDurationFromProperties:properties];
        PETPlatformImage *image = PETPlatformImageFromCGImage(cgImage, detectedCanvasSize);
        PETAnimationFrame *frame = [[PETAnimationFrame alloc] initWithImage:image duration:duration];
        [frames addObject:frame];

        CGImageRelease(cgImage);
    }

    CFRelease(source);

    if (frames.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETWebPDecoder"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: @"ImageIO could not decode any frames from this WEBP."}];
        }
        return nil;
    }

    if (canvasSize != NULL) {
        *canvasSize = detectedCanvasSize;
    }

    return frames.copy;
}

- (NSTimeInterval)animationDurationFromProperties:(NSDictionary *)properties {
    NSArray<NSString *> *containerKeys = @[@"{WebP}", @"{PNG}", @"{GIF}"];
    NSArray<NSString *> *durationKeys = @[@"UnclampedDelayTime", @"DelayTime"];

    for (NSString *containerKey in containerKeys) {
        NSDictionary *container = properties[containerKey];
        if (![container isKindOfClass:NSDictionary.class]) {
            continue;
        }

        for (NSString *durationKey in durationKeys) {
            NSNumber *value = container[durationKey];
            if (value != nil && value.doubleValue > 0.011) {
                return value.doubleValue;
            }
        }
    }

    return 0.08;
}

@end
