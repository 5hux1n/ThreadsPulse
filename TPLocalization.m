#import "TPLocalization.h"
#import "TPPrefs.h"
#import ".generated/TPLocalizationData.h"

static NSDictionary *TPLocalizationCatalog(void) {
    static NSDictionary *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSData dataWithBytesNoCopy:(void *)TPLocalizationData
                                          length:sizeof(TPLocalizationData) freeWhenDone:NO];
        id decoded = [NSPropertyListSerialization propertyListWithData:data
            options:NSPropertyListImmutable format:NULL error:NULL];
        catalog = [decoded isKindOfClass:NSDictionary.class] ? decoded : @{};
    });
    return catalog;
}

NSString *TPLocalized(NSString *key) {
    static NSString *const codes[] = { nil, @"en", @"zh-Hant", @"zh-Hans", @"ja", @"ko" };
    NSDictionary *catalog = TPLocalizationCatalog();
    NSInteger language = [[TPPrefs defaults] integerForKey:TPKeyLanguage];
    NSString *code;
    if (language >= 1 && language <= 5) {
        code = codes[language];
    } else {
        // Resolve on each lookup so choosing Follow System never retains a manual override.
        code = [NSBundle preferredLocalizationsFromArray:catalog[@"localizations"] ?: @[]
            forPreferences:NSLocale.preferredLanguages].firstObject;
        if (!code) code = catalog[@"developmentRegion"] ?: @"en";
    }
    NSDictionary *table = catalog[@"tables"][code];
    return table[key] ?: key;
}
