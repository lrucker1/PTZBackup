//
//  PTZCamera.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/14/22.
//


#import "PTZCamera.h"
#import "AppDelegate.h"

// It doesn't, but the unrecognized message interrupts the running one.
#define CAMERA_SUPPORTS_CANCEL 1

typedef void (^PTZCommandBlock)(void);

BOOL open_interface(VISCAInterface_t *iface, VISCACamera_t *camera, const char *hostname);
void close_interface(VISCAInterface_t *iface);
void backupRestore(VISCAInterface_t *iface, VISCACamera_t *camera, uint32_t inOffset, uint32_t delaySecs, bool isBackup, PTZCamera *ptzCamera, PTZDoneBlock doneBlock);

@interface PTZCamera ()

@property NSString *cameraIP;
@property BOOL batchCancelPending, batchOperationInProgress;
@property BOOL ptzStateValid;
@property dispatch_queue_t cameraQueue;

@end

@implementation PTZCamera

- (instancetype)init {
    self = [super init];
    if (self) {
        _panSpeed = 5;
        _tiltSpeed = 5;
        _presetSpeed = 24; // Default, fastest
        NSString *name = [NSString stringWithFormat:@"cameraQueue_0x%p", self];
        _cameraQueue = dispatch_queue_create([name UTF8String], NULL);
    }
    return self;
}

- (instancetype)initWithIP:(NSString *)ipAddr {
    self = [self init];
    if (self) {
        _cameraIP = ipAddr;
    }
    return self;
}

- (void)dealloc {
    if (_cameraOpen) {
        close_interface(&_iface);
        _cameraOpen = NO;
    }
}

- (void)closeAndReload:(PTZDoneBlock _Nullable)doneBlock {
    [self closeCamera];
    [self loadCameraWithCompletionHandler:^() {
        [self callDoneBlock:doneBlock success:self.cameraOpen];
    }];
}

- (void)changeCamera:(NSString *)cameraIP {
    if (![cameraIP isEqualToString:self.cameraIP]) {
        [self closeCamera];
        self.cameraIP = cameraIP;
    }
    // Don't open, that's async. Wait for loadCameraWithCompletionHandler.
}

- (void)loadCameraWithCompletionHandler:(PTZCommandBlock)handler {
    if (self.cameraOpen) {
        handler();
        return;
    }
    dispatch_async(self.cameraQueue, ^{
        BOOL success = open_interface(&self->_iface, &self->_camera, [self.cameraIP UTF8String]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                self.cameraOpen = YES;
            }
            handler();
        });
    });
}

- (void)closeCamera {
    if (self.cameraOpen) {
        close_interface(&_iface);
        self.cameraOpen = NO;
    }
}

- (void)applyPantiltPresetSpeed:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_set_pantilt_preset_speed(&self->_iface, &self->_camera, (uint32_t)self.presetSpeed) == VISCA_SUCCESS;
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyPantiltAbsolutePosition:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_pantilt_absolute_position(&self->_iface, &self->_camera, (uint32_t)self.panSpeed, (uint32_t)self.tiltSpeed, (int)self.pan, (int)self.tilt) == VISCA_SUCCESS) {
                VISCA_set_pantilt_stop(&self->_iface, &self->_camera, (uint32_t)self.panSpeed, (uint32_t)self.tiltSpeed);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyZoom:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_zoom_value(&self->_iface, &self->_camera, (uint32_t)self.zoom) == VISCA_SUCCESS) {
                VISCA_set_zoom_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)pantiltHome:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_set_pantilt_home(&self->_iface, &self->_camera) == VISCA_SUCCESS;
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)pantiltReset:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_set_pantilt_reset(&self->_iface, &self->_camera) == VISCA_SUCCESS;
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)callDoneBlock:(PTZDoneBlock)doneBlock success:(BOOL)success {
    if (doneBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            doneBlock(success);
        });
    }
}

- (void)memoryRecall:(NSInteger)scene onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_memory_recall(&self->_iface, &self->_camera, scene) == VISCA_SUCCESS;
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self callDoneBlock:doneBlock success:success];
            });
        });
    }];
}

- (void)memorySet:(NSInteger)scene onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_memory_set(&self->_iface, &self->_camera, scene) == VISCA_SUCCESS;
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self callDoneBlock:doneBlock success:success];
            });
        });
    }];
}

- (void)cancelCommand {
    if (!self.cameraOpen) {
        return;
    }
    // Signal to the batch that it needs to cancel.
    if (self.batchOperationInProgress) {
        self.batchCancelPending = YES;
    }
#if CAMERA_SUPPORTS_CANCEL
    // Send from main thread to interrupt camera operation. Reply will be handled by the operation being cancelled.
    VISCA_cancel(&self->_iface, &self->_camera);
#endif
}

// PTZCLEANUP: when we have multiple instances of this class we won't need to pass cameraIPs around.
- (void)backupRestoreWithAddress:(NSString *)cameraIP offset:(NSInteger)rangeOffset delay:(NSInteger)batchDelay isBackup:(BOOL)isBackup onDone:( PTZDoneBlock)doneBlock {
    
    [self changeCamera:cameraIP];
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            backupRestore(&self->_iface, &self->_camera, (uint32_t)rangeOffset, (uint32_t)batchDelay, isBackup, self, doneBlock);
        });
    }];
}

- (NSString *)snapshotURL {
    // I do know this is not the recommended way to make an URL! :)
    return [NSString stringWithFormat:@"http://%@:80/snapshot.jpg", [self cameraIP]];
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (void)fetchSnapshotAtIndex:(NSInteger)index {
    NSString *url = [self snapshotURL];
    NSString *cameraIP = [self cameraIP];
    NSString *rootPath = [self.appDelegate ptzopticsSettingsDirectory];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.snapshotImage = [[NSImage alloc] initWithData:data];
            });
            // PTZ app only shows 6, but being able to see what got saved is useful.
            if ([rootPath length] > 0) {
                NSString *filename = [NSString stringWithFormat:@"snapshot_%@%d.jpg", cameraIP, (int)index];
                NSString *path = [NSString pathWithComponents:@[rootPath, @"downloads", filename]];
                //NSLog(@"saving snapshot to %@", path);
                [data writeToFile:path atomically:YES];
            }
        } else {
            NSLog(@"Failed to get snapshot: error %@", error);
        }
    }] resume];
}

- (void)isCameraReachable:(NSString *)address onDone:(PTZDoneBlock)doneBlock {
    self.cameraIP = address;
    NSString *url = [self snapshotURL];
    // This will work even if there's no snapshot.jpg yet.
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            doneBlock(data != nil);
        });
    }] resume];

}

- (void)batchSetFinishedAtIndex:(int)index {
    [self fetchSnapshotAtIndex:index];
}

- (void)updateCameraState {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            uint16_t zoomValue;
            int16_t panPosition, tiltPosition;
            BOOL ptSuccess = VISCA_get_pantilt_position(&self->_iface, &self->_camera, &panPosition, &tiltPosition) == VISCA_SUCCESS;
            BOOL zSuccess = VISCA_get_zoom_value(&self->_iface, &self->_camera, &zoomValue) == VISCA_SUCCESS;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.ptzStateValid = ptSuccess && zSuccess;
                if (ptSuccess) {
                    self.pan = panPosition;
                    self.tilt = tiltPosition;
                }
                if (zSuccess) {
                    self.zoom = zoomValue;
                }
            });
        });
    }];
}

@end

BOOL open_interface(VISCAInterface_t *iface, VISCACamera_t *camera, const char *hostname)
{
    int port = 5678; // True for PTZOptics. YMMV.
    if (VISCA_open_tcp(iface, hostname, port) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to open tcp device %s:%d\n", hostname, port);
        return NO;
    }

    iface->broadcast = 0;
    camera->address = 1; // Because we are using IP

    if (VISCA_clear(iface, camera) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to clear interface\n");
        VISCA_close(iface);
        return NO;
    }

    NSLog(@"Camera %s initialization successful.\n", hostname);
    return YES;
}

void close_interface(VISCAInterface_t *iface)
{
    //VISCA_usleep(2000); // calls usleep. doesn't appear to actually sleep.

    VISCA_close(iface);
}

void backupRestore(VISCAInterface_t *iface, VISCACamera_t *camera, uint32_t inOffset, uint32_t delaySecs, bool isBackup, PTZCamera *ptzCamera, PTZDoneBlock doneBlock)
{
    uint32_t fromOffset = isBackup ? 0 : inOffset;
    uint32_t toOffset = isBackup ? inOffset : 0;

    uint32_t sceneIndex;
    dispatch_sync(dispatch_get_main_queue(), ^{
        ptzCamera.batchCancelPending = NO;
        ptzCamera.batchOperationInProgress = YES;
    });
    __block BOOL cancel = NO;
    for (sceneIndex = 1; sceneIndex < 10; sceneIndex++) {
        fprintf(stderr, "recall %d", sceneIndex + fromOffset);
        if (VISCA_memory_recall(iface, camera, sceneIndex + fromOffset) != VISCA_SUCCESS) {
            fprintf(stderr, "\nfailed to send recall command %d\n", sceneIndex + fromOffset);
            continue;
        } else if (iface->type == VISCA_RESPONSE_ERROR) {
            fprintf(stderr, "\nCancelled recall at scene %d\n", sceneIndex + fromOffset);
            break;
        }
        fprintf(stderr, " set %d", sceneIndex + toOffset);
        if (VISCA_memory_set(iface, camera, sceneIndex + toOffset) != VISCA_SUCCESS) {
            fprintf(stderr, "\nfailed to send set command %d\n", sceneIndex + toOffset);
            continue;
        } else if (iface->type == VISCA_RESPONSE_ERROR) {
            fprintf(stderr, "\nCancelled set at scene %d\n", sceneIndex + toOffset);
            break;
        }
        fprintf(stderr, " copied scene %d to %d\n", sceneIndex + fromOffset, sceneIndex + toOffset);
        dispatch_sync(dispatch_get_main_queue(), ^{
            [ptzCamera batchSetFinishedAtIndex:sceneIndex+toOffset];
            cancel = ptzCamera.batchCancelPending;
        });
        if (cancel) {
            break;
        }
        // You can recall all 9 scenes in a row with no delay. You can set 9 scenes without a delay!
        // But if you are doing a recall/set combo, the delay is required. Otherwise it just sits there in 'send' starting around recall 3. Might just be a bug in our cameras - well, PTZOptics says no. I don't believe them. They said I'm overloading the camera with commands, but these *are* waiting for the previous one to finish.
        // Also 'usleep' doesn't seem to sleep, so we're stuck with integer seconds. And the firmware version affects the required delay. Latest one only needs 1 sec; older ones needed 5.
        sleep(delaySecs);
    }
    // DO NOT DO AN EARLY RETURN! We must get here.
    dispatch_sync(dispatch_get_main_queue(), ^{
        ptzCamera.batchCancelPending = NO;
        ptzCamera.batchOperationInProgress = NO;
        if (doneBlock) {
            doneBlock(!cancel);
        }
    });
}
