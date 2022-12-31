//
//  PTZCamera.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PTZDoneBlock)(BOOL success);

@interface PTZCamera : NSObject

// R/W camera values
@property NSInteger tilt;
@property NSInteger pan;
@property NSInteger zoom;

// Write-only camera values
@property NSInteger tiltSpeed;
@property NSInteger panSpeed;
@property NSInteger presetSpeed;

@property (readonly) NSString *cameraIP;

@property BOOL cameraOpen;
@property (strong) NSImage *snapshotImage;
@property BOOL connectingBusy, recallBusy;

- (instancetype)initWithIP:(NSString *)ipAddr;

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

- (void)isCameraReachable:(PTZDoneBlock)doneBlock;
- (void)fetchSnapshotAtIndex:(NSInteger)index;
- (void)updateCameraState;
- (void)backupRestoreWithOffset:(NSInteger)rangeOffset delay:(NSInteger)batchDelay isBackup:(BOOL)isBackup onDone:(PTZDoneBlock _Nullable)doneBlock;

@end


NS_ASSUME_NONNULL_END
