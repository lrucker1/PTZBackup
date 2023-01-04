//
//  AppDelegate.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/6/22.
//

#import <Cocoa/Cocoa.h>

#define PTZ_LocalCamerasKey @"LocalCameras"
#define PTZ_BatchDelayKey @"BatchDelay"

void PTZLog(NSString *format, ...);

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSWindowRestoration>

@property NSString *ptzopticsSettingsFilePath;

- (NSString *)ptzopticsSettingsDirectory;
- (NSString *)ptzopticsDownloadsDirectory;

- (NSArray *)cameraList;

- (void)applyPrefChanges;

@end

