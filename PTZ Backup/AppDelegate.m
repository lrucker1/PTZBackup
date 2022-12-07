//
//  AppDelegate.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/6/22.
//

#import "AppDelegate.h"
#import "libvisca.h"

// yeah, yeah, globals bad.
VISCAInterface_t iface;
VISCACamera_t camera;

BOOL open_interface(const char *ttydev);
void close_interface(void);

typedef enum {
    PTZRestore = 0,
    PTZCheck = 1,
    PTZBackup = 2
} PTZMode;

NSString *PTZCameraIPs[3] = {
    @"192.168.13.201",
    @"192.168.13.202",
    @"192.168.13.203"
};
@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property NSInteger rangeOffset, currentIndex;
@property NSInteger openCamera, cameraIndex;
@property NSInteger recallOffset, restoreOffset;
@property (readonly) NSInteger recallValue, restoreValue;
@property NSInteger currentMode;
@property BOOL autoRecall;
@property BOOL testMode;
@end

@implementation AppDelegate

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
{
   NSMutableSet *keyPaths = [NSMutableSet set];

  if (   [key isEqualToString:@"recallValue"]
      || [key isEqualToString:@"restoreValue"]
      || [key isEqualToString:@"currentCommand"]) {
      [keyPaths addObject:@"rangeOffset"];
      [keyPaths addObject:@"recallOffset"];
      [keyPaths addObject:@"restoreOffset"];
      [keyPaths addObject:@"currentIndex"];
      [keyPaths addObject:@"cameraIndex"];

   }
   [keyPaths unionSet:[super keyPathsForValuesAffectingValueForKey:key]];

   return keyPaths;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    self.openCamera = -1;
    self.rangeOffset = 80; // TODO: Defaults
    self.currentIndex = 1;
    self.cameraIndex = 0;
    [self updateMode:0]; // TODO: Defaults
    [self loadCameraIfNeeded];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    if (self.openCamera == self.cameraIndex) {
        close_interface();
        self.openCamera = -1;
    }
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (NSString *)cameraIP {
    NSAssert(self.cameraIndex >= 0 && self.cameraIndex < 3, @"Camera index %ld out of range (0-3)", (long)self.cameraIndex);
    return PTZCameraIPs[self.cameraIndex];
}

// memory_recall, memory_set
// ./visla_cli -d $IP memory_recall $recallOffset
- (NSString *)currentCommand {
    NSString *cameraIP = [self cameraIP];
    return [NSString stringWithFormat:@"./visca_cli -d %@ memory_recall %ld\n./visca_cli -d %@ memory_set %ld", cameraIP, (long)self.recallValue, cameraIP, (long)self.restoreValue];
}

- (void)loadCameraIfNeeded {
    if (self.openCamera == self.cameraIndex) {
        return;
    }
    if (self.openCamera != -1) {
        close_interface();
        self.openCamera = -1;
    }
    if (!self.testMode) {
        BOOL success = open_interface([[self cameraIP] UTF8String]);
        if (success) {
            self.openCamera = self.cameraIndex;
        } else {
            self.testMode = YES;
        }
    }
}

- (void)nextCamera {
    if (self.cameraIndex < 2) {
        self.cameraIndex = self.cameraIndex + 1;
    } else {
        self.cameraIndex = 0;
    }
    [self loadCameraIfNeeded];
}

- (void)updateMode:(NSInteger)mode {
    switch (mode) {
        case PTZRestore:
            self.recallOffset = self.rangeOffset;
            self.restoreOffset = 0;
            break;
        case PTZCheck:
            self.recallOffset = self.restoreOffset = 0;
            break;
        case PTZBackup:
            self.recallOffset = 0;
            self.restoreOffset = self.rangeOffset;
            break;
    }
    self.currentMode = mode;
}

- (IBAction)changeMode:(id)sender {
    NSSegmentedControl *seg = (NSSegmentedControl *)sender;
    if (![seg isMemberOfClass:[NSSegmentedControl class]]) {
        return;
    }
    NSInteger mode = seg.selectedSegment;
    if (mode != self.currentMode) {
        [self updateMode:mode];
    }
}

- (IBAction)recallScene:(id)sender {
    NSLog(@"./visca_cli -d %@ memory_recall %ld", [self cameraIP], (long)self.recallValue);
    if (!self.testMode) {
        [self loadCameraIfNeeded];
        if (VISCA_memory_recall(&iface, &camera, self.recallValue) != VISCA_SUCCESS) {
            NSLog(@"failed to recall scene %ld\n", self.recallValue);
        }

    }
}

- (IBAction)restoreScene:(id)sender {
    NSLog(@"./visca_cli -d %@ memory_set %ld", [self cameraIP], (long)self.restoreValue);
    if (!self.testMode) {
        [self loadCameraIfNeeded];
        if (VISCA_memory_set(&iface, &camera, self.restoreValue) != VISCA_SUCCESS) {
            NSLog(@"failed to restore scene %ld\n", self.restoreValue);
        }

    }
}

// NSTextField actions are required so we don't propagate return to the button, because it increments. But we may stil want to load the scene.

- (IBAction)changeRangeOffset:(id)sender {
    // TODO: Should we enforce the multiple of 10 rule?
    if (self.rangeOffset < 10) {
        self.rangeOffset = 10;
    }
    // TODO: What is the upper bound?
    if (self.rangeOffset > 110) {
        self.rangeOffset = 110;
    }
    [self updateMode:self.currentMode];
    if (self.autoRecall) {
        [self recallScene:sender];
    }
}

- (IBAction)changeCurrentIndex:(id)sender {
    if (self.autoRecall) {
        [self recallScene:sender];
    }
}

- (IBAction)nextSetting:(id)sender {
    if (self.currentIndex < 9) {
        self.currentIndex += 1;
    } else {
        [self nextCamera];
        self.currentIndex = 1;
    }
    if (self.autoRecall) {
        [self recallScene:sender];
    }
}

- (NSInteger)recallValue {
    return _recallOffset + _currentIndex;
}


- (NSInteger)restoreValue {
    return _restoreOffset + _currentIndex;
}

@end

BOOL open_interface(const char *ttydev)
{
    int camera_num;
    int port = 5678;
    if (VISCA_open_tcp(&iface, ttydev, port) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to open tcp device %s:%d\n", ttydev, port);
        return NO;
    }

    iface.broadcast = 0;
    if (VISCA_set_address(&iface, &camera_num) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to set address\n");
        VISCA_close(&iface);
        return NO;
    }

    camera.address = 1;

    if (VISCA_clear(&iface, &camera) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to clear interface\n");
        VISCA_close(&iface);
        return NO;
    }

    NSLog(@"Camera %s initialisation successful.\n", ttydev);
    return YES;
}

void close_interface(void)
{
    //VISCA_usleep(2000); // calls usleep. doesn't appear to actually sleep.

    VISCA_close(&iface);
}
