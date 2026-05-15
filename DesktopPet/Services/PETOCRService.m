#import "PETOCRService.h"

#import <ApplicationServices/ApplicationServices.h>
#import <Vision/Vision.h>

@implementation PETOCRService

- (void)captureDesktopAndRecognizeWithCompletion:(void (^)(NSArray<NSString *> *, NSError * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CGImageRef imageRef = CGDisplayCreateImage(CGMainDisplayID());
        if (imageRef == nil) {
            NSError *error = [NSError errorWithDomain:@"PETOCRService"
                                                 code:2001
                                             userInfo:@{NSLocalizedDescriptionKey: @"Unable to capture the main display. Screen Recording permission may be required."}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], error);
            });
            return;
        }

        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:imageRef options:@{}];
        NSError *recognitionError = nil;
        BOOL success = [handler performRequests:@[request] error:&recognitionError];
        CGImageRelease(imageRef);

        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], recognitionError);
            });
            return;
        }

        NSMutableArray<NSString *> *recognizedLines = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            NSString *line = [candidate.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length > 0) {
                [recognizedLines addObject:line];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(recognizedLines.copy, nil);
        });
    });
}

@end
