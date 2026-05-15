#import "PETStructuredCognitionEngine.h"

#import "../Models/PETCharacterSnapshot.h"
#import "../Models/PETStructuredCognitionSuggestion.h"
#import "PETAIService.h"

@interface PETStructuredCognitionEngine ()

@property (nonatomic, strong) PETAIService *aiService;

@end

@implementation PETStructuredCognitionEngine

- (instancetype)initWithAIService:(PETAIService *)aiService {
    self = [super init];
    if (self) {
        _aiService = aiService;
    }
    return self;
}

- (void)requestSuggestionForSnapshot:(PETCharacterSnapshot *)snapshot
                          completion:(void (^)(PETStructuredCognitionSuggestion *, NSError *))completion {
    NSString *prompt = [self cognitionPromptForSnapshot:snapshot];
    __weak typeof(self) weakSelf = self;
    [self.aiService sendInteraction:prompt completion:^(NSString * _Nullable reply, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (reply.length == 0 || error != nil) {
            completion(nil, error);
            return;
        }
        PETStructuredCognitionSuggestion *suggestion = [strongSelf parseSuggestionFromReply:reply];
        if (suggestion == nil) {
            NSError *parseError = [NSError errorWithDomain:@"PETStructuredCognitionEngine"
                                                      code:3201
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Cognition reply did not match the structured protocol."}];
            completion(nil, parseError);
            return;
        }
        completion(suggestion, nil);
    }];
}

- (NSString *)cognitionPromptForSnapshot:(PETCharacterSnapshot *)snapshot {
    NSDictionary<NSString *, id> *payload = @{
        @"protocol": @"character_os.structured_cognition.v1",
        @"instructions": @{
            @"role": @"Return one structured cognition suggestion.",
            @"rules": @[
                @"Respond with JSON only.",
                @"Do not set animation state directly.",
                @"Use actionKey values under the cognition.* namespace.",
                @"Keep the suggestion compatible with the existing semantic runtime."
            ],
            @"schema": @{
                @"actionKey": @"string",
                @"summary": @"string",
                @"goalHint": @"string",
                @"confidence": @"number 0..1",
                @"context": @"object"
            }
        },
        @"snapshot": [snapshot serializedRepresentation] ?: @{}
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

- (PETStructuredCognitionSuggestion *)parseSuggestionFromReply:(NSString *)reply {
    NSData *data = [reply dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary<NSString *, id> *dictionary = [object isKindOfClass:NSDictionary.class] ? object : nil;
    PETStructuredCognitionSuggestion *suggestion = [PETStructuredCognitionSuggestion suggestionFromDictionary:dictionary];
    if (suggestion == nil) {
        return nil;
    }
    if (![suggestion.actionKey hasPrefix:@"cognition."]) {
        return nil;
    }
    return suggestion;
}

@end
