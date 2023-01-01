//
//  PTZSettingsFile.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/22/22.
//

#import "PTZSettingsFile.h"
#import "dictionary.h"
#import "iniparser.h"
#import "ObjCUtils.h"

@interface PTZSettingsFile ()

@property dictionary * ini;
@property NSString *path;

@end

static char _last_error[1024];
static int _error_callback(const char *format, ...)
{
    int ret;
    va_list argptr;
    va_start(argptr, format);
    ret = vsprintf(_last_error, format, argptr);
    fprintf(stderr, "%s", _last_error); // Just dump to the log window.
    va_end(argptr);
    return ret;
}

@implementation PTZSettingsFile

+ (void)initialize {
    /* Specify our custom error_callback */
    iniparser_set_error_callback(_error_callback);
}

+ (BOOL)validateFileWithPath:(NSString *)path error:(NSError * _Nullable *)error {
    PTZSettingsFile *testFile = [[PTZSettingsFile alloc] initWithPath:path];
    if (testFile == nil) {
        if (error != nil) {
            *error = OCUtilErrorWithDescription(NSLocalizedString(@"Failed to open or parse file", @"failed to open file"), NSLocalizedString(@"See Log window for details", @"See Log window"), @"PTZSettingsFile", 100);
        }
        return NO;
    }
    return [testFile validateDictionary:error];
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _last_error[0] = '\0';
        _ini = iniparser_load([path UTF8String]);
        _path = path;
        if (_ini == NULL) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    iniparser_freedict(_ini);
    _ini = NULL;
}

- (BOOL)writeToFile:(NSString *)file {
    FILE * fd;
    if ((fd=fopen([file UTF8String], "w"))==NULL) {
        return NO;
    }

    iniparser_dump_ini(self.ini, fd);
    fclose(fd);
    return YES;
}

- (void)logDictionary {
    iniparser_dump(self.ini, stdout);
}

- (BOOL)validateDictionary:(NSError * _Nullable *)error {
    // Check for missing required keys - nil result from stringForKeyValidation:
    NSString *sizeObj = [self stringForKeyValidation:@"cameraslist:size"];
    NSString *checkVersion = NSLocalizedString(@"The PTZOptics settings.ini file may be damaged, or the format might not be compatible with this version of PTZ Backup", @"Bad file or incompatible versions");
    if (sizeObj == nil) {
        if (error != nil) {
            *error = OCUtilErrorWithDescription(NSLocalizedString(@"cameraslist:size missing from dictionary", @"cameraslist:size missing"), checkVersion, @"PTZSettingsFile", 102);
        }
        return NO;
    }
    
    int size = [sizeObj intValue];
    if (size <= 0) {
        if (error != nil) {
            NSString *formatStr = NSLocalizedString(@"cameraslist:size unexpected value %@", @"cameralist:size has a bad value");
             *error = OCUtilErrorWithDescription([NSString localizedStringWithFormat:formatStr, sizeObj], checkVersion, @"PTZSettingsFile", 103);
        }
        return NO;
    }

    size = MIN(size, 8); // 8 is the current value but could change. 8 is enough for detecting a bad file.
    for (int i = 1; i <= size; i++) {
        // Empty values should be fine. nil values imply PTZ has changed formats again.
        NSString *devicename = [self stringForKeyValidation:[NSString stringWithFormat:@"cameraslist:%d\\devicename", i]];
        NSString *cameraname = [self stringForKeyValidation:[NSString stringWithFormat:@"cameraslist:%d\\cameraname", i]];
        if (devicename == nil || cameraname == nil) {
            if (error != nil) {
                *error = OCUtilErrorWithDescription(NSLocalizedString(@"cameraslist devicename or cameraname information missing from dictionary", @"cameraslist camera info missing"), checkVersion, @"PTZSettingsFile", 104);
            }
            return NO;
        }
    }
    return YES;
}

// Returns @"" if key is missing. @"" is also a valid result.
- (NSString *)stringForKey:(NSString *)aKey {
    const char *result = iniparser_getstring(self.ini, [aKey UTF8String], "");
    return [NSString stringWithUTF8String:result];
}

// Returns nil if key is missing.
- (NSString *)stringForKeyValidation:(NSString *)aKey {
    const char *result = iniparser_getstring(self.ini, [aKey UTF8String], NULL);
    if (result == NULL) {
        return nil;
    }
    return [NSString stringWithUTF8String:result];
}

- (NSString *)stringFromList:(NSString *)list key:(NSString *)key {
    NSString *iniKey = [NSString stringWithFormat:@"%@:%@", list, key];
    return [self stringForKey:iniKey];
}

- (void)setName:(NSString *)name forScene:(NSInteger)scene camera:(NSString *)ipAddr {
    // list General "mem" + index + ip
    NSString *key = [NSString stringWithFormat:@"%@:mem%d%@", @"General", (int)scene, ipAddr];
    if (iniparser_set(self.ini, [key UTF8String], [name UTF8String]) == 0) {
        [self writeToFile:self.path];
    }
}

- (NSString *)nameForScene:(NSInteger)scene camera:(NSString *)ipAddr {
    // list General "mem" + index + ip
    NSString *key = [NSString stringWithFormat:@"mem%d%@", (int)scene, ipAddr];
    return [self stringFromList:@"General" key:key];
}

- (NSArray *)cameraInfo {
    static NSString *noCamera = @"0.0.0.0";

    NSMutableArray *cameras = [NSMutableArray new];
    int size = [[self stringForKey:@"cameraslist:size"] intValue];
    for (int i = 1; i <= size; i++) {
        NSString *devicename = [self stringForKey:[NSString stringWithFormat:@"cameraslist:%d\\devicename", i]];
        if ([devicename length] > 0 && ![devicename isEqualToString:noCamera]) {
            NSString *cameraname = [self stringForKey:[NSString stringWithFormat:@"cameraslist:%d\\cameraname", i]];
            [cameras addObject:@{@"cameraname":cameraname, @"devicename":devicename, @"original":devicename}];
        }
    }
    return cameras;
}

@end
