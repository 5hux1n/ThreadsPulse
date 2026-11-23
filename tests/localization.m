// Exercise the production decoder and selector with real Foundation; only preferences are stubbed.
#import <Foundation/Foundation.h>
#import "TPLocalization.h"
#import "TPPrefs.h"

NSString *const TPKeyLanguage = @"language";
static NSInteger TPTestLanguage;

@interface TPLocalizationTestDefaults : NSUserDefaults
@end
@implementation TPLocalizationTestDefaults
- (NSInteger)integerForKey:(NSString *)key {
    NSCAssert([key isEqual:TPKeyLanguage], @"Only the language preference is needed");
    return TPTestLanguage;
}
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation TPPrefs
+ (NSUserDefaults *)defaults {
    static TPLocalizationTestDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [TPLocalizationTestDefaults new]; });
    return defaults;
}
@end
#pragma clang diagnostic pop

static void TPCheckTable(NSDictionary<NSString *, NSString *> *table) {
    NSCAssert(table.count == 346, @"Exercise every existing translation");
    for (NSString *key in table) {
        NSCAssert([TPLocalized(key) isEqual:table[key]], @"Wrong translation for %@: %@", key, TPLocalized(key));
    }
    NSString *missing = @"__ThreadsPulse_missing_localization_test__";
    NSCAssert([TPLocalized(missing) isEqual:missing], @"A missing key must return the key");
    NSString *credit = [NSString stringWithFormat:TPLocalized(@"Modified and optimized: By %@"), @"Junhong"];
    NSCAssert([credit containsString:@"Junhong"], @"Preserve the modifier attribution");
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSCAssert(argc >= 2, @"Expected the independently decoded source tables");
    NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    NSDictionary *tables = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    NSArray *codes = @[@"en", @"zh-Hant", @"zh-Hans", @"ja", @"ko"];
    for (NSInteger selection = 1; selection <= 5; selection++) {
        TPTestLanguage = selection;
        TPCheckTable(tables[codes[selection - 1]]);
    }
    // Return from a manual selection to the current process's actual AppleLanguages preference.
    NSString *systemCode = NSProcessInfo.processInfo.environment[@"TP_TEST_SYSTEM_TABLE"];
    NSCAssert(tables[systemCode], @"Expected system language table");
    for (NSNumber *selection in @[@0, @(-1), @6, @3, @0]) {
        TPTestLanguage = selection.integerValue;
        TPCheckTable(tables[TPTestLanguage == 3 ? @"zh-Hans" : systemCode]);
    }
    printf("embedded localization: PASS (5 tables, system %s, dynamic selection, missing keys)\n", systemCode.UTF8String);
} return 0; }
