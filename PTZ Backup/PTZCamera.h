//
//  PTZCamera.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>
#import "libvisca.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^PTZDoneBlock)(BOOL success);

@interface PTZCamera : NSObject

// R/W on the camera
@property NSInteger tilt;
@property NSInteger pan;
@property NSInteger zoom;

// Write-only on the camera
@property NSInteger tiltSpeed;
@property NSInteger panSpeed;
@property NSInteger presetSpeed;

@property BOOL cameraOpen;
@property (strong) NSImage *snapshotImage;

@property VISCAInterface_t iface;
@property VISCACamera_t camera;

- (void)changeCamera:(NSString *)cameraIP;
- (void)closeCamera;
- (void)closeAndReload:(PTZDoneBlock _Nullable)doneBlock;

- (void)applyPantiltPresetSpeed:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyPantiltAbsolutePosition:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyZoom:(PTZDoneBlock _Nullable)doneBlock;
- (void)pantiltHome:(PTZDoneBlock _Nullable)doneBlock;
- (void)pantiltReset:(PTZDoneBlock _Nullable)doneBlock;
- (void)memoryRecall:(NSInteger)scene onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)memorySet:(NSInteger)scene onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)cancelCommand;

- (void)isCameraReachable:(NSString *)address onDone:(PTZDoneBlock)doneBlock;
- (void)fetchSnapshotAtIndex:(NSInteger)index;
- (void)updateCameraState;
- (void)backupRestoreWithAddress:(NSString *)cameraIP offset:(NSInteger)rangeOffset delay:(NSInteger)batchDelay isBackup:(BOOL)isBackup onDone:(PTZDoneBlock _Nullable)doneBlock;

@end


NS_ASSUME_NONNULL_END
