#import "PETAIService.h"

@implementation PETAIService

- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    self = [super init];
    if (self) {
        _baseURL = [baseURL copy];
    }
    return self;
}

- (void)sendInteraction:(NSString *)interaction completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    (void)interaction;
    NSError *error = [NSError errorWithDomain:@"PETAIService"
                                         code:3001
                                     userInfo:@{NSLocalizedDescriptionKey: @"AI interaction pipeline is scaffolded. Wire your provider SDK or HTTP client here."}];
    completion(nil, error);
}

@end
