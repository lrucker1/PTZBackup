//
//  PTZCamera.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//


#import "PTZCamera.h"


@implementation PTZCamera

- (instancetype)init {
    self = [super init];
    if (self) {
        _panSpeed = 5;
        _tiltSpeed = 5;
        _presetSpeed = 24; // Default, fastest
    }
    return self;
}


@end
