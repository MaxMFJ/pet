#import "PETAppConfig.h"

static NSString * const PETAIBaseURLDefaultsKey = @"PETAIBaseURLDefaultsKey";
static NSString * const PETCognitionEnabledDefaultsKey = @"PETCognitionEnabledDefaultsKey";
static NSString * const PETOCRDesktopEnabledDefaultsKey = @"PETOCRDesktopEnabledDefaultsKey";
static NSString * const PETMaxConcurrentPetsDefaultsKey = @"PETMaxConcurrentPetsDefaultsKey";
static NSString * const PETPetInstanceRecordsDefaultsKey = @"PETPetInstanceRecordsDefaultsKey";

@implementation PETAppConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadDefaults];
    }
    return self;
}

- (void)loadDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *registeredDefaults = @{
        PETAIBaseURLDefaultsKey: @"https://api.openai.com/v1",
        PETCognitionEnabledDefaultsKey: @NO,
        PETOCRDesktopEnabledDefaultsKey: @NO,
        PETMaxConcurrentPetsDefaultsKey: @4,
        PETPetInstanceRecordsDefaultsKey: @[]
    };
    [defaults registerDefaults:registeredDefaults];

    self.aiBaseURLString = [defaults stringForKey:PETAIBaseURLDefaultsKey] ?: @"https://api.openai.com/v1";
    self.cognitionEnabled = [defaults boolForKey:PETCognitionEnabledDefaultsKey];
    self.OCRDesktopEnabled = [defaults boolForKey:PETOCRDesktopEnabledDefaultsKey];
    self.maxConcurrentPets = [defaults integerForKey:PETMaxConcurrentPetsDefaultsKey];
    NSArray *storedPetRecords = [defaults arrayForKey:PETPetInstanceRecordsDefaultsKey];
    self.petInstanceRecords = [storedPetRecords isKindOfClass:NSArray.class] ? storedPetRecords : @[];
}

- (void)persist {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:self.aiBaseURLString forKey:PETAIBaseURLDefaultsKey];
    [defaults setBool:self.cognitionEnabled forKey:PETCognitionEnabledDefaultsKey];
    [defaults setBool:self.OCRDesktopEnabled forKey:PETOCRDesktopEnabledDefaultsKey];
    [defaults setInteger:self.maxConcurrentPets forKey:PETMaxConcurrentPetsDefaultsKey];
    [defaults setObject:self.petInstanceRecords ?: @[] forKey:PETPetInstanceRecordsDefaultsKey];
}

@end
