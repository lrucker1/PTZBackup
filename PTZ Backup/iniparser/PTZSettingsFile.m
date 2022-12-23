//
//  PTZSettingsFile.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/22/22.
//

#import "PTZSettingsFile.h"
#import "dictionary.h"
#import "iniparser.h"

@interface PTZSettingsFile ()

@property dictionary * ini;

@end

@implementation PTZSettingsFile

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _ini = iniparser_load([path UTF8String]);
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

- (NSString *)stringForKey:(NSString *)aKey {
    const char *result = iniparser_getstring(self.ini, [aKey UTF8String], "");
    return [NSString stringWithUTF8String:result];
}

- (NSString *)stringFromList:(NSString *)list key:(NSString *)key {
    NSString *iniKey = [NSString stringWithFormat:@"%@:%@", list, key];
    return [self stringForKey:iniKey];
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
        if (![devicename isEqualToString:noCamera]) {
            NSString *cameraname = [self stringForKey:[NSString stringWithFormat:@"cameraslist:%d\\cameraname", i]];
            [cameras addObject:@[cameraname, devicename]];
        }
    }
    return cameras;
}

@end
