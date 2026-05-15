#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETOCRService : NSObject

- (void)captureDesktopAndRecognizeWithCompletion:(void (^)(NSArray<NSString *> *recognizedLines, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
