//
//  PTZPrefCamera.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/30/22.
//

#import "PTZPrefCamera.h"

@implementation PTZPrefCamera

- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraname = @"Camera";
        _devicename = @"0.0.0.0";
        _originalDeviceName = _devicename;
    }
    return self;

}
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _cameraname = dict[@"cameraname"];
        _devicename = dict[@"devicename"];
        _originalDeviceName = dict[@"original"] ?: _devicename;
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{@"cameraname":_cameraname, @"devicename":_devicename, @"original": _originalDeviceName};
}

@end
