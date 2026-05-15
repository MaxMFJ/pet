#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

typedef UIImage PETPlatformImage;
typedef UIColor PETPlatformColor;
typedef CGSize PETPlatformSize;
typedef UIView PETPlatformView;

NS_INLINE PETPlatformImage *PETPlatformImageFromCGImage(CGImageRef imageRef, PETPlatformSize size) {
    (void)size;
    return [UIImage imageWithCGImage:imageRef];
}

NS_INLINE PETPlatformSize PETPlatformImagePixelSize(PETPlatformImage *image) {
    return CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
}

NS_INLINE NSValue *PETPlatformValueWithRect(CGRect rect) {
    return [NSValue valueWithCGRect:rect];
}

NS_INLINE CGRect PETPlatformRectValue(NSValue *value) {
    return value.CGRectValue;
}

#else
#import <Cocoa/Cocoa.h>

typedef NSImage PETPlatformImage;
typedef NSColor PETPlatformColor;
typedef NSSize PETPlatformSize;
typedef NSView PETPlatformView;

NS_INLINE PETPlatformImage *PETPlatformImageFromCGImage(CGImageRef imageRef, PETPlatformSize size) {
    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithCGImage:imageRef];
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:representation];
    return image;
}

NS_INLINE PETPlatformSize PETPlatformImagePixelSize(PETPlatformImage *image) {
    return image.size;
}

NS_INLINE NSValue *PETPlatformValueWithRect(CGRect rect) {
    return [NSValue valueWithRect:NSRectFromCGRect(rect)];
}

NS_INLINE CGRect PETPlatformRectValue(NSValue *value) {
    return NSRectToCGRect(value.rectValue);
}

#endif
