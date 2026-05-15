#import "PETAnimationExporter.h"

#import <ImageIO/ImageIO.h>

#import "../Models/PETAnimationFrame.h"
#import "../Models/PETPetProfile.h"

@implementation PETAnimationExporter

- (BOOL)exportPNGSequenceForProfile:(PETPetProfile *)profile
                              state:(NSString *)state
                       directoryURL:(NSURL *)directoryURL
                              scale:(CGFloat)scale
                              error:(NSError **)error {
    NSArray<PETAnimationFrame *> *frames = [profile framesForState:state];
    if (frames.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationExporter"
                                         code:7201
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected animation does not contain any frames."}];
        }
        return NO;
    }

    NSString *folderName = [self sanitizedNameForString:[NSString stringWithFormat:@"%@-%@", profile.displayName ?: @"animation", state ?: @"clip"]];
    NSURL *exportDirectoryURL = [directoryURL URLByAppendingPathComponent:folderName isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:exportDirectoryURL withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    __block BOOL succeeded = YES;
    __block NSError *writeError = nil;
    [frames enumerateObjectsUsingBlock:^(PETAnimationFrame *frame, NSUInteger index, BOOL *stop) {
        CGImageRef cgImage = [self newCGImageFromImage:frame.image canvasSize:profile.canvasSize scale:scale];
        if (cgImage == NULL) {
            succeeded = NO;
            writeError = [NSError errorWithDomain:@"PETAnimationExporter"
                                             code:7202
                                         userInfo:@{NSLocalizedDescriptionKey: @"A frame could not be rasterized for PNG export."}];
            *stop = YES;
            return;
        }

        NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
        CGImageRelease(cgImage);
        NSData *data = [representation representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (data == nil) {
            succeeded = NO;
            writeError = [NSError errorWithDomain:@"PETAnimationExporter"
                                             code:7203
                                         userInfo:@{NSLocalizedDescriptionKey: @"A frame could not be encoded as PNG."}];
            *stop = YES;
            return;
        }

        NSString *filename = [NSString stringWithFormat:@"%@_%04lu.png", [self sanitizedNameForString:state ?: @"clip"], (unsigned long)(index + 1)];
        NSURL *fileURL = [exportDirectoryURL URLByAppendingPathComponent:filename];
        if (![data writeToURL:fileURL options:NSDataWritingAtomic error:&writeError]) {
            succeeded = NO;
            *stop = YES;
        }
    }];

    if (!succeeded && error != NULL) {
        *error = writeError;
    }
    return succeeded;
}

- (BOOL)exportGIFForProfile:(PETPetProfile *)profile
                      state:(NSString *)state
                    fileURL:(NSURL *)fileURL
                      scale:(CGFloat)scale
                  loopCount:(NSInteger)loopCount
                      error:(NSError **)error {
    NSArray<PETAnimationFrame *> *frames = [profile framesForState:state];
    if (frames.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationExporter"
                                         code:7204
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected animation does not contain any frames."}];
        }
        return NO;
    }

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)fileURL,
                                                                        CFSTR("com.compuserve.gif"),
                                                                        frames.count,
                                                                        NULL);
    if (destination == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETAnimationExporter"
                                         code:7205
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to create the GIF destination file."}];
        }
        return NO;
    }

    NSDictionary *gifProperties = @{
        (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                (__bridge NSString *)kCGImagePropertyGIFLoopCount: @(MAX(0, loopCount))
        }
    };
    CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)gifProperties);

    for (PETAnimationFrame *frame in frames) {
        CGImageRef cgImage = [self newCGImageFromImage:frame.image canvasSize:profile.canvasSize scale:scale];
        if (cgImage == NULL) {
            CFRelease(destination);
            if (error != NULL) {
                *error = [NSError errorWithDomain:@"PETAnimationExporter"
                                             code:7206
                                         userInfo:@{NSLocalizedDescriptionKey: @"A frame could not be rasterized for GIF export."}];
            }
            return NO;
        }

        NSTimeInterval duration = MAX(0.02, frame.duration);
        NSDictionary *frameProperties = @{
            (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                    (__bridge NSString *)kCGImagePropertyGIFDelayTime: @(duration)
            }
        };
        CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)frameProperties);
        CGImageRelease(cgImage);
    }

    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    if (!success && error != NULL) {
        *error = [NSError errorWithDomain:@"PETAnimationExporter"
                                     code:7207
                                 userInfo:@{NSLocalizedDescriptionKey: @"The GIF file could not be finalized."}];
    }
    return success;
}

- (CGImageRef)newCGImageFromImage:(NSImage *)image canvasSize:(NSSize)canvasSize scale:(CGFloat)scale CF_RETURNS_RETAINED {
    CGFloat safeScale = MAX(0.1, scale);
    NSSize sourceSize = canvasSize.width > 0.0 && canvasSize.height > 0.0 ? canvasSize : image.size;
    NSInteger width = MAX(1, (NSInteger)llround(sourceSize.width * safeScale));
    NSInteger height = MAX(1, (NSInteger)llround(sourceSize.height * safeScale));

    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                                pixelsWide:width
                                                                                pixelsHigh:height
                                                                             bitsPerSample:8
                                                                           samplesPerPixel:4
                                                                                  hasAlpha:YES
                                                                                  isPlanar:NO
                                                                            colorSpaceName:NSCalibratedRGBColorSpace
                                                                               bytesPerRow:0
                                                                              bitsPerPixel:0];
    if (representation == nil) {
        return NULL;
    }

    NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:representation];
    if (graphicsContext == nil) {
        return NULL;
    }

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphicsContext];
    graphicsContext.imageInterpolation = NSImageInterpolationHigh;
    [image drawInRect:NSMakeRect(0, 0, width, height)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [graphicsContext flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    CGImageRef cgImage = representation.CGImage;
    return cgImage != NULL ? CGImageCreateCopy(cgImage) : NULL;
}

- (NSString *)sanitizedNameForString:(NSString *)string {
    NSCharacterSet *invalidCharacters = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet];
    NSString *sanitized = [[string componentsSeparatedByCharactersInSet:invalidCharacters] componentsJoinedByString:@"-"];
    while ([sanitized containsString:@"--"]) {
        sanitized = [sanitized stringByReplacingOccurrencesOfString:@"--" withString:@"-"];
    }
    sanitized = [sanitized stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-"]];
    return sanitized.length > 0 ? sanitized : @"animation";
}

@end
