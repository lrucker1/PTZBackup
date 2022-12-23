//
//  AppDelegate.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/6/22.
//

// Icon <a href="https://www.flaticon.com/free-icons/ptz-camera" title="ptz camera icons">Ptz camera icons created by Freepik - Flaticon</a>

#import "AppDelegate.h"
#import "PTZCamera.h"
#import "PTZSettingsFile.h"
#import "libvisca.h"
#import "PTZPrefsController.h"

//  downloadDestination[reply] = new QFile(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QString::asprintf("%s" , (DOWNLOAD_FILE_DEST_PREFIX)) + currentCamIp + QString::number(1) + ".jpg");
//
// AppDataLocation is
// \li "~/Library/Application Support/<APPNAME>", "/Library/Application Support/<APPNAME>". "<APPDIR>/../Resources"

#define DEFAULT_SETTINGS_PATH "/ptzoptics-controller/settings.ini"
#define DOWNLOAD_FILE_DEST_PREFIX "/ptzoptics-controller/downloads/snapshot_"
#define DOWNLOAD_FILE_URI "/snapshot.jpg"
//     settings->setValue(QString::asprintf("mem%d", presetNum) + currentCamIp, presetText);

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

typedef enum {
    ReachableUnknown = 0,
    ReachableYes,
    ReachableNo
} Reachable;

@interface NSAttributedString (PTZAdditions)
+ (id)attributedStringWithString: (NSString *)string;
@end

@implementation NSAttributedString (PTZAdditions)

+ (id)attributedStringWithString: (NSString *)string
{
   // Use self, so we get NSMutableAttributedStrings when called on that class.
   NSAttributedString *attributedString = [[self alloc] initWithString:string];
   return attributedString;
}

@end

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSWindow *stateWindow;
@property (strong) IBOutlet NSTextView *console;
@property (strong) IBOutlet NSPopUpButton *cameraButton;

@property NSInteger rangeOffset, currentIndex;
@property NSInteger openCamera, cameraIndex;
@property NSInteger recallOffset, restoreOffset;
@property (readonly) NSInteger recallValue, restoreValue;
@property NSInteger currentMode;
@property BOOL autoRecall;
@property BOOL cameraOpen;
@property BOOL busy, recallBusy;
@property BOOL hideRecallIcon, hideRestoreIcon;
@property BOOL useOBSSettings;
@property Reachable reachable;
@property (strong) NSFileHandle* pipeReadHandle;
@property (strong) NSPipe *pipe;
@property (strong) PTZCamera *cameraState;
@property (strong) NSImage *snapshotImage;
@property PTZPrefsController *prefsController;
@property (strong) PTZSettingsFile *sourceSettings;
@property (strong) PTZSettingsFile *backupSettings;

@property dispatch_queue_t recallQueue;
@end

@implementation AppDelegate

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
{
   NSMutableSet *keyPaths = [NSMutableSet set];

  if (   [key isEqualToString:@"recallValue"]
      || [key isEqualToString:@"restoreValue"]
      || [key isEqualToString:@"currentCommand"]
      || [key isEqualToString:@"sceneName"]) {
      [keyPaths addObject:@"rangeOffset"];
      [keyPaths addObject:@"recallOffset"];
      [keyPaths addObject:@"restoreOffset"];
      [keyPaths addObject:@"currentIndex"];
      [keyPaths addObject:@"cameraIndex"];
   }
   [keyPaths unionSet:[super keyPathsForValuesAffectingValueForKey:key]];

   return keyPaths;
}

- (void)handlePipeNotification:(NSNotification *)notification {
    [_pipeReadHandle readInBackgroundAndNotify];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stdOutString = [[NSString alloc] initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
        [self writeToConsole:stdOutString];
    });
}

static NSString *PTZ_SettingsPathKey = @"PTZSettingsPath";

- (NSString *)obsSettingsDirectory {
    return [[NSUserDefaults standardUserDefaults] stringForKey:PTZ_SettingsPathKey];
}

- (void)setObsSettingsDirectory:(NSString *)newPath {
    NSString *oldPath = self.obsSettingsDirectory;
    if (![oldPath isEqualToString:newPath]) {
        [[NSUserDefaults standardUserDefaults] setObject:newPath forKey:PTZ_SettingsPathKey];
        [self updateCameraPopup];
    }
}

- (void)configConsoleRedirect {
    _pipe = [NSPipe pipe];
    _pipeReadHandle = [_pipe fileHandleForReading];
    dup2([[_pipe fileHandleForWriting] fileDescriptor], fileno(stderr));
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePipeNotification:) name:NSFileHandleReadCompletionNotification object:_pipeReadHandle];
    [_pipeReadHandle readInBackgroundAndNotify];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _recallQueue = dispatch_queue_create("recallQueue", NULL);
    
    self.openCamera = -1;
    
    self.cameraState = [PTZCamera new];
    self.cameraState.presetSpeed = 24; // Note that this is write-only; we could save to Mac prefs but we can't read back from the camera.
    BOOL useLocalhost = NO;
    // Insert code here to initialize your application
    for (NSString *arg in [[NSProcessInfo processInfo] arguments]) {
        if ([arg isEqualToString:@"localhost"]) {
            useLocalhost = YES;
            [self writeToConsole:@"Using localhost\n"];
            [self.cameraButton removeAllItems];
            [self.cameraButton addItemWithTitle:@"localhost"];
            [[self.cameraButton lastItem] setRepresentedObject:@"localhost"];
            [self loadCamera];
        }
    }
    if (useLocalhost) {
        self.reachable = ReachableYes;
        // Use the bundle resource for testing.
        NSString *path = [[NSBundle mainBundle] pathForResource:@"settings" ofType:@"ini"];
        if (path) {
            self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
        }
    } else {
        [self updateCameraPopup];
    }
#if DEBUG
    [self writeToConsole:@"Debug build; log is written to stderr"];
#else
    [self configConsoleRedirect];
#endif
    self.rangeOffset = 80; // TODO: Defaults
    self.currentIndex = 1;
    self.cameraIndex = 0;
    [self updateMode:0]; // TODO: Defaults
    self.hideRestoreIcon = YES;
    self.hideRecallIcon = YES;
    NSString *rootPath = [self obsSettingsDirectory];
    if (rootPath == nil || [[NSFileManager defaultManager] fileExistsAtPath:rootPath]) {
        [self showPrefs:nil];
    }
}

- (NSArray *)cameraList {
    NSString *rootPath = [self obsSettingsDirectory];
    if (rootPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:rootPath]) {
        NSString *path = [NSString pathWithComponents:@[rootPath, @"settings.ini"]];
        
        if (path != nil && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
            NSArray *cameras = [self.sourceSettings cameraInfo];
            if ([cameras count] > 0) {
                return cameras;
            }
        }
    }

    return nil;
}

- (void)updateCameraPopup {
    [self closeCamera];
    NSArray *cameraList = [self cameraList];
    [self.cameraButton removeAllItems];
    int i = 1;
    for (NSArray *cameraInfo in cameraList) {
        NSString *cameraname = [cameraInfo firstObject];
        NSString *title = [NSString stringWithFormat:@"%d - %@", i++, cameraname];
        NSString *ipAddr = [cameraInfo lastObject];
        [self.cameraButton addItemWithTitle:title];
        [[self.cameraButton lastItem] setRepresentedObject:ipAddr];
    }
    if ([cameraList count] > 0) {
        [self loadCameraIfReachable];
    }
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

- (IBAction)showPrefs:(id)sender {
    if (self.prefsController == nil) {
        self.prefsController = [PTZPrefsController new];
    }
    [self.prefsController.window orderFront:sender];
}

- (NSString *)cameraIP {
    return [[self.cameraButton selectedItem] representedObject];
}

- (NSString *)recallName {
    switch (self.currentMode) {
        case PTZRestore:
            return self.backupName;
        case PTZCheck:
            return self.sceneName;
        case PTZBackup:
            return self.sceneName;
    }
    return @"";
}

- (NSString *)restoreName {
    switch (self.currentMode) {
        case PTZRestore:
            return self.sceneName;
        case PTZCheck:
            return @"";
        case PTZBackup:
            return self.backupName;
    }
    return @"";
}

- (NSString *)sceneName {
    return [self.sourceSettings nameForScene:self.currentIndex camera:self.cameraIP];
}

- (NSString *)backupName {
    return [self.backupSettings nameForScene:self.currentIndex camera:self.cameraIP];
}

// memory_recall, memory_set
// ./visla_cli -d $IP memory_recall $recallOffset
- (NSString *)currentCommand {
    NSString *cameraIP = [self cameraIP];
    return [NSString stringWithFormat:@"./visca_cli -d %@ memory_recall %ld\n./visca_cli -d %@ memory_set %ld", cameraIP, (long)self.recallValue, cameraIP, (long)self.restoreValue];
}

- (void)closeCamera {
    if (self.openCamera != -1) {
        close_interface();
        self.openCamera = -1;
        self.cameraOpen = NO;
    }
}

- (void)loadCamera {
    self.busy = YES;
    if (self.openCamera != -1) {
        close_interface();
        self.openCamera = -1;
        self.cameraOpen = NO;
    }
    BOOL success = open_interface([[self cameraIP] UTF8String]);
    if (success) {
        self.openCamera = self.cameraIndex;
        self.cameraOpen = YES;
    }
    self.busy = NO;
}

// This will not test reachability because that is async.
- (void)loadCameraIfNeeded {
    if (self.openCamera == self.cameraIndex || self.reachable == ReachableNo) {
        return;
    }
    [self loadCamera];
}

- (IBAction)reopenCamera:(id)sender {
    // Close and reload
    if (self.reachable == ReachableYes) {
        [self loadCamera];
    } else {
        [self loadCameraIfReachable];
    }
}

- (IBAction)changeCamera:(id)sender {
    if (self.openCamera != self.cameraIndex) {
        [self loadCameraIfReachable];
    }
}

- (void)nextCamera {
    NSInteger cameraCount = [self.cameraButton numberOfItems];
    if (self.cameraIndex < cameraCount-1) {
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

- (NSView *)currentEditingViewForWindow:(NSWindow *)window {
    NSView *fieldEditor = [window fieldEditor:NO forObject:nil];
    NSView *first = nil;
    if (fieldEditor != nil) {
        first = fieldEditor;
        do {
            first = [first superview];
        } while (first != nil && ![first isKindOfClass:[NSTextField class]]);
    }
    return first;
}

- (IBAction)applyRecallSpeed:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [self currentEditingViewForWindow:window];
    if (first != nil) {
        [self.stateWindow makeFirstResponder:self.stateWindow.contentView];
    }
    if (VISCA_set_pantilt_preset_speed(&iface, &camera, (uint32_t)self.cameraState.presetSpeed) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to set speed\n");
    }
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}


- (IBAction)applyPanTilt:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [self currentEditingViewForWindow:window];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    // VISCA_set_pantilt_absolute_position(VISCAInterface_t *iface, VISCACamera_t *camera, uint32_t pan_speed, uint32_t tilt_speed, int pan_position, int tilt_position)

    if (VISCA_set_pantilt_absolute_position(&iface, &camera, (uint32_t)self.cameraState.panSpeed, (uint32_t)self.cameraState.tiltSpeed, (int)self.cameraState.pan, (int)self.cameraState.tilt) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to set pan/tilt\n");
    } else {
        VISCA_set_pantilt_stop(&iface, &camera, (uint32_t)self.cameraState.panSpeed, (uint32_t)self.cameraState.tiltSpeed);
    }
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)applyZoom:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [self currentEditingViewForWindow:window];
    if (first != nil) {
        [self.stateWindow makeFirstResponder:self.stateWindow.contentView];
    }
    if (VISCA_set_zoom_value(&iface, &camera, (uint32_t)self.cameraState.zoom) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to set zoom\n");
    } else {
        VISCA_set_zoom_stop(&iface, &camera);
    }
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)updateCameraState:(id)sender {
    [self loadCameraIfNeeded];
    if (self.cameraOpen) {
        uint16_t zoomValue;
        int16_t panPosition, tiltPosition;
        if (VISCA_get_pantilt_position(&iface, &camera, &panPosition, &tiltPosition) == VISCA_SUCCESS) {
            self.cameraState.pan = panPosition;
            self.cameraState.tilt = tiltPosition;
        } else {
            NSLog(@"failed to get pan/tilt values\n");
        }
        if (VISCA_get_zoom_value(&iface, &camera, &zoomValue) == VISCA_SUCCESS) {
            self.cameraState.zoom = zoomValue;
        } else {
            NSLog(@"failed to get zoom value\n");
        }
    }
}

- (IBAction)cameraHome:(id)sender {
    [self loadCameraIfNeeded];
    if (self.cameraOpen) {
        if (VISCA_set_pantilt_home(&iface, &camera) != VISCA_SUCCESS) {
            NSLog(@"failed to home camera\n");
        }
    }
}

- (IBAction)cameraReset:(id)sender {
    [self loadCameraIfNeeded];
    if (self.cameraOpen) {
        if (VISCA_set_pantilt_reset(&iface, &camera) != VISCA_SUCCESS) {
            NSLog(@"failed to reset camera\n");
        }
    }
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

#define GET_EPS(x, y) abs(abs(x) - abs(y))
- (IBAction)recallScene:(id)sender {
    self.hideRecallIcon = YES;
    [self loadCameraIfNeeded];
    if (self.cameraOpen) {
        self.recallBusy = YES;
        // We want the spinner to start spinning so the run loop needs to run.
        dispatch_async(_recallQueue, ^{
            uint16_t zoomValue;
            int16_t panPosition, tiltPosition;
            if (VISCA_get_zoom_value(&iface, &camera, &zoomValue) == VISCA_SUCCESS) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.cameraState.zoom = zoomValue;
                });
            }
            if (VISCA_get_pantilt_position(&iface, &camera, &panPosition, &tiltPosition) == VISCA_SUCCESS) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.cameraState.pan = panPosition;
                    self.cameraState.tilt = tiltPosition;
                });
            }
            if (VISCA_memory_recall(&iface, &camera, self.recallValue) != VISCA_SUCCESS) {
                NSLog(@"failed to recall scene %ld\n", self.recallValue);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.hideRecallIcon = NO;
                });
            } else if (iface.type == VISCA_RESPONSE_ERROR && iface.errortype == VISCA_ERROR_CMD_CANCELLED) {
                NSLog(@"command cancelled\n");
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.recallBusy = NO;
            });
            if (VISCA_get_zoom_value(&iface, &camera, &zoomValue) == VISCA_SUCCESS) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.cameraState.zoom = zoomValue;
                });
            }
            if (VISCA_get_pantilt_position(&iface, &camera, &panPosition, &tiltPosition) == VISCA_SUCCESS) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.cameraState.pan = panPosition;
                    self.cameraState.tilt = tiltPosition;
                });
            }
        });
    } else {
        self.hideRecallIcon = NO;
    }
}

- (NSString *)snapshotURL {
    // I do know this is not the recommended way to make an URL! :)
    return [NSString stringWithFormat:@"http://%@:80/snapshot.jpg", [self cameraIP]];
}

- (void)fetchSnapshot {
    // I do know this is not the recommended way to make an URL! :)
    NSString *url = [self snapshotURL];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data != nil) {
            self.snapshotImage = [[NSImage alloc] initWithData:data];
            NSString *rootPath = [self obsSettingsDirectory];
            if ([rootPath length] > 0) {
                NSString *filename = [NSString stringWithFormat:@"snapshot_%@%d.jpg", self.cameraIP, (int)self.currentIndex];
                
                NSString *path = [NSString pathWithComponents:@[rootPath, @"downloads", filename]];
                NSLog(@"saving snapshot to %@", path);
                [data writeToFile:path atomically:NO];
            }
        } else {
            NSLog(@"Failed to get snapshot: error %@", error);
        }
    }] resume];
}

- (void)loadCameraIfReachable {
    NSString *url = [self snapshotURL];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data != nil) {
            self.reachable = ReachableYes;
            [self loadCameraIfNeeded];
        } else {
            self.reachable = ReachableNo;
        }
    }] resume];

}

- (IBAction)restoreScene:(id)sender {
    self.hideRestoreIcon = YES;
    [self loadCameraIfNeeded];
    if (self.cameraOpen) {
        self.busy = YES;
        if (VISCA_memory_set(&iface, &camera, self.restoreValue) != VISCA_SUCCESS) {
            NSLog(@"failed to restore scene %ld\n", self.restoreValue);
            self.hideRestoreIcon = NO;
        } else {
            [self fetchSnapshot];
        }
        self.busy = NO;
    } else {
        self.hideRestoreIcon = NO;
    }
}

// NSTextField actions are required so we don't propagate return to the button, because it increments. But we may stil want to load the scene.

- (IBAction)changeRangeOffset:(id)sender {
    // Usually a multiple of 10 when doing batches, but can be other values for one-off saves. It's up to the user to choose wisely. I only protect you from tromping on the OBS default 9
    if (self.rangeOffset < 10) {
        self.rangeOffset = 10;
    }
    // PTZOptics doc says range for the memory commands is (0 to 127), IIRC Chris said reality was lower. If your offset is 126 and index > 1, the failure is all yours.
    if (self.rangeOffset > 126) {
        self.rangeOffset = 126;
    }
    [self updateMode:self.currentMode];
    if (self.autoRecall) {
        [self recallScene:sender];
    }
}

- (IBAction)changeCurrentIndex:(id)sender {
    if (self.currentIndex > 9) {
        self.currentIndex = 9;
    } else if (self.currentIndex < 1) {
        self.currentIndex = 1;
    }
    if (self.autoRecall) {
        [self recallScene:sender];
    }
}

- (IBAction)changePresetSpeed:(id)sender {
    if (self.cameraState.presetSpeed > 0x18) {
        self.cameraState.presetSpeed = 0x18;
    } else if (self.cameraState.presetSpeed < 1) {
        self.cameraState.presetSpeed = 1;
    }
}

- (IBAction)changePanSpeed:(id)sender {
    if (self.cameraState.panSpeed > 0x18) {
        self.cameraState.panSpeed = 0x18;
    } else if (self.cameraState.panSpeed < 1) {
        self.cameraState.panSpeed = 1;
    }
}

- (IBAction)changeTiltSpeed:(id)sender {
    if (self.cameraState.tiltSpeed > 0x14) {
        self.cameraState.tiltSpeed = 0x14;
    } else if (self.cameraState.tiltSpeed < 1) {
        self.cameraState.tiltSpeed = 1;
    }
}

- (IBAction)changeZoom:(id)sender {
    // 0x4000 max for PTZOptics
    if (self.cameraState.zoom > 0x4000) {
        self.cameraState.zoom = 0x4000;
    } else if (self.cameraState.zoom < 0) {
        self.cameraState.zoom = 0;
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector
{
    //NSLog(@"Selector method is (%@)", NSStringFromSelector( commandSelector ) );
    if (commandSelector == @selector(insertNewline:)) {
        //Do something against ENTER key
        // Should the speed field do an "apply"?
        return YES;

    } else if (commandSelector == @selector(deleteForward:)) {
        //Do something against DELETE key

    } else if (commandSelector == @selector(deleteBackward:)) {
        //Do something against BACKSPACE key

    } else if (commandSelector == @selector(insertTab:)) {
        //Do something against TAB key

    } else if (commandSelector == @selector(cancelOperation:)) {
        //Do something against Escape key
    }
    // return YES if the action was handled; otherwise NO
    return NO;
}

- (IBAction)nextSetting:(id)sender {
    if (self.currentIndex < 9) {
        self.currentIndex += 1;
    } else {
        self.currentIndex = 1;
        [self nextCamera];
    }
    self.hideRecallIcon = self.hideRestoreIcon = YES;
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

- (IBAction)commandCancel:(id)sender {
    if (VISCA_cancel(&iface, &camera) != VISCA_SUCCESS) {
        NSLog(@"visca: cancel attempt failed\n");
    }
}

- (void)writeToConsole:(NSString *)string // IN
{
   NSTextStorage *textStorage = [self.console textStorage];
   [textStorage beginEditing];
   [textStorage appendAttributedString:
      [NSAttributedString attributedStringWithString:string]];
   [textStorage endEditing];
   NSRange range = NSMakeRange([[self.console string] length], 0);
   [self.console scrollRangeToVisible:range];
}

@end

BOOL open_interface(const char *ttydev)
{
    int port = 5678; // True for PTZOptics. YMMV.
    if (VISCA_open_tcp(&iface, ttydev, port) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to open tcp device %s:%d\n", ttydev, port);
        return NO;
    }

    iface.broadcast = 0;
    camera.address = 1; // Because we are using IP

    if (VISCA_clear(&iface, &camera) != VISCA_SUCCESS) {
        NSLog(@"visca: unable to clear interface\n");
        VISCA_close(&iface);
        return NO;
    }

    NSLog(@"Camera %s initialization successful.\n", ttydev);
    return YES;
}

void close_interface(void)
{
    //VISCA_usleep(2000); // calls usleep. doesn't appear to actually sleep.

    VISCA_close(&iface);
}
