//
//  AppDelegate.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/6/22.
//

#import <Cocoa/Cocoa.h>

#define PTZ_LocalCamerasKey @"LocalCameras"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property NSString *ptzopticsSettingsFilePath;

- (NSArray *)cameraList;

- (void)applyPrefChanges;

@end

