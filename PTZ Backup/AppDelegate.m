//
//  AppDelegate.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/6/22.
//

// Icon <a href="https://www.flaticon.com/free-icons/ptz-camera" title="ptz camera icons">Ptz camera icons created by Freepik - Flaticon</a>

#import "AppDelegate.h"
#import "PTZCamera.h"
#import "libvisca.h"

#define PTZ_EPSILON 1 // In case it needs tweaking if the camera value doesn't return precisely the same value on repeated calls. I don't know. It's hardware!
#define PTZ_MAX_RECALL_SEC 15 // Breaks the loop after X seconds if epsilon is too small.

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

// These are the registered defaults. It can be changed by using 'defaults' command line app; I'd make an actual UI but this is not likely to change. This is just an emergency backup if for some reason the cameras change unexpectedly.
// command format: defaults write lrucker.PTZ-Backup PTZCameras -array-add '(Test, 10.0.0.1)' '(Test2, 10.0.0.2)'
// defaults delete lrucker.PTZ-Backup PTZCameras
NSArray *PTZCameras = @[@[@"1 - Altar", @"192.168.13.201"],
                        @[@"2 - Ambo", @"192.168.13.202"],
                        @[@"3 - Choir", @"192.168.13.203"]];

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
@property (strong) NSFileHandle* pipeReadHandle;
@property (strong) NSPipe *pipe;
@property (strong) PTZCamera *cameraState;

@property dispatch_queue_t recallQueue;
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

- (void)handlePipeNotification:(NSNotification *)notification {
    [_pipeReadHandle readInBackgroundAndNotify];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stdOutString = [[NSString alloc] initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
        [self writeToConsole:stdOutString];
    });
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

    [[NSUserDefaults standardUserDefaults] registerDefaults:
       @{@"PTZCameras":PTZCameras}];

    self.cameraState = [PTZCamera new];
    self.cameraState.presetSpeed = 24; // Note that this is write-only; we could save to Mac prefs but we can't read back from the camera.
    BOOL useLocalhost = NO;
    // Insert code here to initialize your application
    for (NSString *arg in [[NSProcessInfo processInfo] arguments]) {
        if ([arg isEqualToString:@"localhost"]) {
            useLocalhost = YES;
            [self writeToConsole:@"Using localhost\n"];
            // The index binding hits a range error if we remove all the items.
            [self.cameraButton addItemWithTitle:@"localhost"];
            [[self.cameraButton lastItem] setRepresentedObject:@"localhost"];
            while ([self.cameraButton numberOfItems] > 1) {
                [self.cameraButton removeItemAtIndex:0];
            }
        }
    }
    if (!useLocalhost) {
        // Load the cameras from defaults if they're different.
        NSArray *cameraDefaults = [[NSUserDefaults standardUserDefaults] arrayForKey:@"PTZCameras"];
        if ([cameraDefaults count] != [self.cameraButton numberOfItems]) {
            // Clunky yes, but the index binding hates empty menus
            [self.cameraButton addItemWithTitle:@"placeholder"];
            while ([self.cameraButton numberOfItems] > 1) {
                [self.cameraButton removeItemAtIndex:0];
            }
            for (NSArray *cameraInfo in cameraDefaults) {
                NSString *title = [cameraInfo firstObject];
                NSString *ipAddr = [cameraInfo lastObject];
                [self.cameraButton addItemWithTitle:title];
                [[self.cameraButton lastItem] setRepresentedObject:ipAddr];
            }
            [self.cameraButton removeItemAtIndex:0];
        } else {
            // Just update ipAddresses
            for (NSInteger i = 0; i < [self.cameraButton numberOfItems]; i++) {
                NSArray *cameraInfo = [cameraDefaults objectAtIndex:i];
                NSString *ipAddr = [cameraInfo lastObject];
                [[self.cameraButton itemAtIndex:i] setRepresentedObject:ipAddr];
            }
        }
    }
#if DEBUG
    [self writeToConsole:@"Debug build; log is written to stderr"];
#else
    [self configConsoleRedirect];
#endif
    self.openCamera = -1;
    self.rangeOffset = 80; // TODO: Defaults
    self.currentIndex = 1;
    self.cameraIndex = 0;
    [self updateMode:0]; // TODO: Defaults
    self.hideRestoreIcon = YES;
    self.hideRecallIcon = YES;
    // Delay to next runloop to give the window time to show
    self.busy = YES;
    [self performSelector:@selector(loadCameraIfNeeded) withObject:nil afterDelay:0];
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
    return [[self.cameraButton selectedItem] representedObject];
}

// memory_recall, memory_set
// ./visla_cli -d $IP memory_recall $recallOffset
- (NSString *)currentCommand {
    NSString *cameraIP = [self cameraIP];
    return [NSString stringWithFormat:@"./visca_cli -d %@ memory_recall %ld\n./visca_cli -d %@ memory_set %ld", cameraIP, (long)self.recallValue, cameraIP, (long)self.restoreValue];
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

- (void)loadCameraIfNeeded {
    if (self.openCamera == self.cameraIndex) {
        return;
    }
    [self loadCamera];
}

- (IBAction)reopenCamera:(id)sender {
    // Close and reload
    [self loadCamera];
}

- (IBAction)changeCamera:(id)sender {
    [self loadCameraIfNeeded];
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
        __block uint16_t zoomValue;
        __block int16_t panPosition, tiltPosition;
        __block BOOL waitForZoom = YES, waitForPT = YES;;
        if (VISCA_get_zoom_value(&iface, &camera, &zoomValue) == VISCA_SUCCESS) {
            self.cameraState.zoom = zoomValue;
        } else {
            NSLog(@"failed to get starting zoom value\n");
            waitForZoom = NO;
        }
        if (VISCA_get_pantilt_position(&iface, &camera, &panPosition, &tiltPosition) == VISCA_SUCCESS) {
            self.cameraState.pan = panPosition;
            self.cameraState.tilt = tiltPosition;
        } else {
            NSLog(@"failed to get starting pan/tilt values\n");
            waitForPT = NO;
        }
        if (VISCA_memory_recall(&iface, &camera, self.recallValue) != VISCA_SUCCESS) {
            NSLog(@"failed to recall scene %ld\n", self.recallValue);
            self.hideRecallIcon = NO;
        }
        if (!waitForZoom && !waitForPT) {
            self.recallBusy = NO;
        } else {
            dispatch_async(_recallQueue, ^{
                int16_t lastPan, lastTilt, lastZoom;
                NSDate *endTime = [NSDate dateWithTimeIntervalSinceNow:PTZ_MAX_RECALL_SEC];
                // (original)Give it time to start changing, then ping every 0.1 second.
                //nanosleep((const struct timespec[]){{0, 500000000L}}, NULL);
                // OK, I can ping it every half second, or I can do some complex "is same after X pings". Running with the simulator, I sometimes get a false-done with a 0.1sec ping. Need to make sure real camera works with a 0.5 ping. Also that PTZ_EPSILON is OK at 1.
                do {
                    nanosleep((const struct timespec[]){{0, 500000000L}}, NULL);
                    lastPan = panPosition;
                    lastTilt = tiltPosition;
                    lastZoom = zoomValue;
                    if (waitForPT) {
                        if (VISCA_get_pantilt_position(&iface, &camera, &panPosition, &tiltPosition) != VISCA_SUCCESS) {
                            waitForPT = NO;
                        } else {
                            waitForPT = (GET_EPS(lastPan, panPosition) > PTZ_EPSILON) || (GET_EPS(lastTilt, tiltPosition) > PTZ_EPSILON);
                        }
                    }
                    if (waitForZoom) {
                        if (VISCA_get_zoom_value(&iface, &camera, &zoomValue) != VISCA_SUCCESS) {
                            waitForZoom = NO;
                        } else {
                            waitForZoom = (abs(lastZoom - zoomValue) > PTZ_EPSILON);
                        }
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // main_queue because it updates the UI
                        self.cameraState.pan = panPosition;
                        self.cameraState.tilt = tiltPosition;
                        self.cameraState.zoom = zoomValue;
                    });
#if DEBUG
                    // I miss NSLog extensions.
                    NSLog(@"pan %d %d, tilt %d %d, zoom %d %d wait %d %d", lastPan, panPosition, lastTilt, tiltPosition, lastZoom, zoomValue, waitForPT, waitForZoom);
#endif
                    if ([[NSDate now] compare:endTime] == NSOrderedDescending) {
                        // Don't loop forever, even if the PTZ values aren't within epsilon.
                        break;
                    }
                } while (waitForPT || waitForZoom);
                dispatch_async(dispatch_get_main_queue(), ^{
                    // main_queue because it updates the UI
                    self.recallBusy = NO;
                });
            });
        }
    } else {
        self.hideRecallIcon = NO;
    }
}

- (IBAction)restoreScene:(id)sender {
    self.hideRestoreIcon = YES;
    [self loadCameraIfNeeded];
    if (self.cameraOpen) {
        self.busy = YES;
        if (VISCA_memory_set(&iface, &camera, self.restoreValue) != VISCA_SUCCESS) {
            NSLog(@"failed to restore scene %ld\n", self.restoreValue);
            self.hideRestoreIcon = NO;
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
