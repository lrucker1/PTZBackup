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
#import "PTZPrefsController.h"
#import "PTZCameraStateViewController.h"
#import "PTZPrefCamera.h"
#import "NSWindowAdditions.h"

static AppDelegate *selfType;

typedef enum {
    PTZRestore = 0,
    PTZCheck = 1,
    PTZBackup = 2
} PTZMode;

typedef enum {
    TabSingle = 0,
    TabBatch
} CurrentTab;

static NSString *PTZ_SettingsFilePathKey = @"PTZSettingsFilePath";
static NSString *PTZ_RangeOffsetKey = @"RangeOffset";
static NSString *PTZ_UseLocalCamerasKey = @"UseLocalCameraSettings";
static NSString *PTZ_MaxRangeOffsetKey = @"MaxRangeOffset";
static NSString *PTZ_BatchIsBackupKey = @"BatchIsBackup";
static NSString *PTZ_SingleModeKey = @"SingleMode";

void PTZLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    s = [s stringByAppendingString:@"\n"];
    fprintf(stdout, "%s", [s UTF8String]);
}

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSWindow *stateWindow;
@property (strong) IBOutlet NSWindow *consoleWindow;
@property (strong) IBOutlet NSTextView *console;
@property (strong) IBOutlet NSPopUpButton *cameraButton;
@property (strong) IBOutlet PTZCameraStateViewController *stateViewController;
@property (strong) IBOutlet NSSegmentedControl *singleModeControl;

@property NSInteger rangeOffset, currentIndex;
@property NSInteger cameraIndex;
@property NSInteger sceneRecallOffset, sceneSetOffset;
@property (readonly) NSInteger sceneRecallValue, sceneSetValue;
@property NSString *editableSceneSetName;
@property NSInteger currentMode;
@property (readonly) BOOL isCheckMode, isRestoreMode, isBackupMode;
@property NSInteger currentTab;
@property BOOL autoRecall;
@property BOOL hideRecallIcon, hideRestoreIcon;
@property BOOL batchIsBackup;
@property BOOL batchOperationInProgress;
@property (strong) NSFileHandle *pipeReadHandle, *stdoutPipeReadHandle;
@property (strong) NSPipe *pipe, *stdoutPipe;
@property (strong) PTZCamera *cameraState;
@property PTZPrefsController *prefsController;
@property (strong) PTZSettingsFile *sourceSettings;
@property (strong) PTZSettingsFile *backupSettings;
@property BOOL applicationIsReady;

@end

@implementation AppDelegate

+ (void)initialize {
    [super initialize];
    // Has to happen here so it's set before window restoration happens. There are all sorts of side effects, like end-editing on textfields which triggers validation before all the values are set.
    [[NSUserDefaults standardUserDefaults] registerDefaults:
        @{PTZ_BatchDelayKey:@(5),
          PTZ_RangeOffsetKey:@(80),
          PTZ_MaxRangeOffsetKey:@(80),
          PTZ_BatchIsBackupKey:@(YES),
          PTZ_SingleModeKey:@(0)
        }];
    // Registering defaults has to happen every time, so if we find the right file go ahead and set it so we don't have to keep checking existence if it doesn't get set through the UI.
    // If useLocal is set and there's no FilePath, then presumably they are aware they have no settings.ini file and we don't need to look for one.
    BOOL useLocal = [[NSUserDefaults standardUserDefaults] boolForKey:PTZ_UseLocalCamerasKey];

    if (!useLocal && [[NSUserDefaults standardUserDefaults] objectForKey:PTZ_SettingsFilePathKey] == nil) {
        NSString *path = [@"~/Library/Application Support/PTZOptics/settings.ini" stringByExpandingTildeInPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSUserDefaults standardUserDefaults] setObject:path forKey:PTZ_SettingsFilePathKey];
        }
    }
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
{
    NSMutableSet *keyPaths = [NSMutableSet set];
    
    if (   [key isEqualToString:@"sceneRecallValue"]
        || [key isEqualToString:@"sceneSetValue"]) {
        [keyPaths addObject:@"rangeOffset"];
        [keyPaths addObject:@"sceneRecallOffset"];
        [keyPaths addObject:@"sceneSetOffset"];
        [keyPaths addObject:@"currentIndex"];
        [keyPaths addObject:@"cameraState"];
    }
    if (   [key isEqualToString:@"sceneName"]) {
        [keyPaths addObject:@"sourceSettings"];
        [keyPaths addObject:@"currentIndex"];
        [keyPaths addObject:@"cameraState"];
        [keyPaths addObject:@"cameraList"];
    }
    if (   [key isEqualToString:@"backupName"]) {
        [keyPaths addObject:@"backupSettings"];
        [keyPaths addObject:@"currentIndex"];
        [keyPaths addObject:@"cameraState"];
    }
    if (   [key isEqualToString:@"currentMode"]) {
        [keyPaths addObject:@"applicationIsReady"];
    }
    if (   [key isEqualToString:@"sceneRecallName"]
        || [key isEqualToString:@"sceneSetName"]) {
        [keyPaths addObject:@"backupName"];
        [keyPaths addObject:@"sceneName"];
        [keyPaths addObject:@"currentMode"];
        [keyPaths addObject:@"backupSettings"];
    }
    if (   [key isEqualToString:@"isCheckMode"]
        || [key isEqualToString:@"isRestoreMode"]
        || [key isEqualToString:@"isBackupMode"]) {
        [keyPaths addObject:@"currentMode"];
    }
    if (   [key isEqualToString:@"cameraName"]
        || [key isEqualToString:@"cameraIP"]) {
        [keyPaths addObject:@"cameraState"];
        [keyPaths addObject:@"cameraList"];
    }
    // batchAllButtonLabel
    if (   [key isEqualToString:@"batchAllButtonLabel"]
        || [key isEqualToString:@"batchOneButtonLabel"]) {
        [keyPaths addObject:@"batchIsBackup"];
    }
    if (   [key isEqualToString:@"recallBusy"]) {
        [keyPaths addObject:@"cameraState.recallBusy"];
    }
    if (   [key isEqualToString:@"connectingBusy"]) {
        [keyPaths addObject:@"cameraState.connectingBusy"];
    }
   [keyPaths unionSet:[super keyPathsForValuesAffectingValueForKey:key]];

   return keyPaths;
}

- (void)handleStdoutPipeNotification:(NSNotification *)notification {
    [_stdoutPipeReadHandle readInBackgroundAndNotify];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stdOutString = [[NSString alloc] initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
        [self writeToConsole:stdOutString];
    });
}

- (void)handlePipeNotification:(NSNotification *)notification {
    [_pipeReadHandle readInBackgroundAndNotify];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stdOutString = [[NSString alloc] initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
        [self writeToConsole:stdOutString color:[NSColor systemRedColor]];
    });
}

- (NSInteger)batchDelay {
    return [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_BatchDelayKey];
}

- (NSInteger)rangeOffset {
    return [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_RangeOffsetKey];
}

- (void)setRangeOffset:(NSInteger)value {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:PTZ_RangeOffsetKey];
}

- (NSInteger)currentMode {
    return [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_SingleModeKey];
}

- (void)setCurrentMode:(NSInteger)value {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:PTZ_SingleModeKey];
}

- (BOOL)batchIsBackup {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PTZ_BatchIsBackupKey];
}

- (void)setBatchIsBackup:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:PTZ_BatchIsBackupKey];
}

- (NSString *)ptzopticsSettingsFilePath {
    return [[NSUserDefaults standardUserDefaults] stringForKey:PTZ_SettingsFilePathKey];
}

// path/to/settings.ini. Should be a subdir of ~/Library/Application Support/PTZOptics, not OBS - that's the wrong format!
- (void)setPtzopticsSettingsFilePath:(NSString *)newPath {
    NSString *oldPath = self.ptzopticsSettingsFilePath;
    if (![oldPath isEqualToString:newPath]) {
        [[NSUserDefaults standardUserDefaults] setObject:newPath forKey:PTZ_SettingsFilePathKey];
    }
}

// should contain settings.ini, downloads folder, and backup settingsXX.ini
- (NSString *)ptzopticsSettingsDirectory {
    return [[self ptzopticsSettingsFilePath] stringByDeletingLastPathComponent];
}

// Although you can set a custom downloads path in PTZOptics ("General:snapshotpath"), the app ignores it and always uses the hardcoded #define value.
- (NSString *)ptzopticsDownloadsDirectory {
    NSString *rootPath = self.ptzopticsSettingsDirectory;
    if (rootPath != nil) {
        return [NSString pathWithComponents:@[rootPath, @"downloads"]];
    }
    return nil;
}

- (void)applyPrefChanges {
    [self willChangeValueForKey:@"cameraList"];
    [self loadSourceSettings];
    [self loadBackupSettings];
    [self updateCameraPopup];
    [self didChangeValueForKey:@"cameraList"];
}

- (void)configConsoleRedirect {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowStderrInLog"]) {
        _pipe = [NSPipe pipe];
        _pipeReadHandle = [_pipe fileHandleForReading];
        dup2([[_pipe fileHandleForWriting] fileDescriptor], fileno(stderr));
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePipeNotification:) name:NSFileHandleReadCompletionNotification object:_pipeReadHandle];
        [_pipeReadHandle readInBackgroundAndNotify];
    }
    _stdoutPipe = [NSPipe pipe];
    _stdoutPipeReadHandle = [_stdoutPipe fileHandleForReading];
    dup2([[_stdoutPipe fileHandleForWriting] fileDescriptor], fileno(stdout));
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleStdoutPipeNotification:) name:NSFileHandleReadCompletionNotification object:_stdoutPipeReadHandle];
    [_stdoutPipeReadHandle readInBackgroundAndNotify];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Seriously, restoration? Why are you making textfields first responder, then resigning it, which triggers the action before we're ready?
    self.applicationIsReady = YES;
    [self configConsoleRedirect];
    [self addObserver:self
           forKeyPath:@"sceneSetName"
              options:0
              context:&selfType];

    BOOL useLocalhost = NO;
    for (NSString *arg in [[NSProcessInfo processInfo] arguments]) {
        // You can also set 'localhost' as a temporary address in app preferences; this is left from early testing before that was added, when cameras got loaded at startup. It still might be useful for testing.
        if ([arg isEqualToString:@"localhost"]) {
            useLocalhost = YES;
            [self writeToConsole:@"Using localhost\n"];
            [self.cameraButton removeAllItems];
            [self.cameraButton addItemWithTitle:@"localhost"];
            PTZPrefCamera *prefCamera = [[PTZPrefCamera alloc] initWithDictionary:@{@"cameraname":@"localhost", @"devicename":@"localhost"}];
            prefCamera.camera = [[PTZCamera alloc] initWithIP:prefCamera.devicename];
            [[self.cameraButton lastItem] setRepresentedObject:prefCamera];
            // We can open localhost now. Real cameras wait until needed.
            [self reopenCamera:nil];
        }
    }
    if (useLocalhost) {
        if (self.sourceSettings == nil) {
            // Use the bundle resource for testing.
            NSString *path = [[NSBundle mainBundle] pathForResource:@"settings" ofType:@"ini"];
            if (path) {
                self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
            }
        }
    } else {
        [self updateCameraPopup];
    }
    self.currentIndex = 1;
    self.cameraIndex = 0;
    self.hideRestoreIcon = YES;
    self.hideRecallIcon = YES;
    // If you use bindings on the segmented control the action won't be called, and the dependent values won't be updated. KVO could also be used but this is simpler.
    self.singleModeControl.selectedSegment = self.currentMode;
    [self updateMode:self.currentMode];
    NSString *iniPath = [self ptzopticsSettingsFilePath];
    // Show the prefs at launch if we don't have a settings file and we're not using local (prefs) camera info.
    BOOL useLocal = [[NSUserDefaults standardUserDefaults] boolForKey:PTZ_UseLocalCamerasKey];
    if (iniPath == nil || ![[NSFileManager defaultManager] fileExistsAtPath:iniPath]) {
        if (!useLocal) {
            [self showPrefs:nil];
        }
    } else {
        // Even if useLocal is true, there's info in the settings file we want to use.
        if (self.sourceSettings == nil) {
            [self loadSourceSettings];
        }
        if (!useLocal && self.sourceSettings == nil) {
            // We tried, it's not there, and the user hasn't opted to use local info: make sure prefs are visible so users know where to set it.
            [self showPrefs:nil];
        }
    }
    // If loadBackupSettings fails, it just means there's no backup file, which is fine.
    [self loadBackupSettings];
    self.consoleWindow.restorationClass = [self class]; // "console"
    self.stateWindow.restorationClass = [self class]; // "camerastate"
}

// Autosave frame saves the frame, but doesn't save the open state; we have to do restoration for that.
+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
    NSWindow *window = nil;
    if ([identifier isEqualToString:@"camerastate"]) {
        window = delegate.stateWindow;
    } else if ([identifier isEqualToString:@"console"]) {
        window = delegate.consoleWindow;
    } else if ([identifier isEqualToString:@"main"]) {
        window = delegate.window;
    } else if ([identifier isEqualToString:@"prefswindow"]) {
        [delegate showPrefs:nil];
        window = delegate.prefsController.window;
    }
    [window makeKeyAndOrderFront:nil];
    completionHandler(window, nil);
}

- (BOOL)recallBusy {
    return self.cameraState.recallBusy;
}

- (BOOL)connectingBusy {
    return self.cameraState.connectingBusy;
}

- (NSArray *)cameraList {
    if (self.sourceSettings == nil) {
        [self loadSourceSettings];
    }
    NSArray *cameras = [self.sourceSettings cameraInfo];
    if ([cameras count] > 0) {
        return cameras;
    }

    PTZLog(@"No valid cameras found in %@", [self ptzopticsSettingsFilePath]);
    [self.sourceSettings logDictionary];
    return nil;
}

- (void)updateCameraPopup {
    NSArray *cameraList = nil;
    BOOL useLocal = [[NSUserDefaults standardUserDefaults] boolForKey:PTZ_UseLocalCamerasKey];
    
    if (useLocal) {
        cameraList = [[NSUserDefaults standardUserDefaults] arrayForKey:@"LocalCameras"];
    } else {
        cameraList = [self cameraList];
    }
    [self.cameraButton removeAllItems];
    int i = 1;
    for (NSDictionary *cameraInfo in cameraList) {
        PTZPrefCamera *prefCamera = [[PTZPrefCamera alloc] initWithDictionary:cameraInfo];
        NSString *title = [NSString stringWithFormat:@"%d - %@", i++, prefCamera.cameraname];
        [self.cameraButton addItemWithTitle:title];
        prefCamera.camera = [[PTZCamera alloc] initWithIP:prefCamera.devicename];
        [[self.cameraButton lastItem] setRepresentedObject:prefCamera];
    }
    [self cameraDidChange];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (IBAction)showPrefs:(id)sender {
    if (self.prefsController == nil) {
        self.prefsController = [PTZPrefsController new];
    }
    [self.prefsController.window orderFront:sender];
    self.prefsController.window.restorationClass = [self class];
}

- (NSString *)cameraName {
    return [[[self.cameraButton selectedItem] representedObject] cameraname];
}

// Current camera address (used in nib bindings)
- (NSString *)cameraIP {
    return [[[self.cameraButton selectedItem] representedObject] devicename];
}

// Address as used in settings.ini
- (NSString *)settingsFileCameraIP {
    return [[[self.cameraButton selectedItem] representedObject] originalDeviceName];
}

- (BOOL)isCheckMode {
    return self.currentMode == PTZCheck;
}

- (BOOL)isRestoreMode {
    return self.currentMode == PTZRestore;
}

- (BOOL)isBackupMode {
    return self.currentMode == PTZBackup;
}


- (NSString *)sceneRecallName {
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

- (NSString *)sceneSetName {
    switch (self.currentMode) {
        case PTZRestore:
            return self.sceneName;
        case PTZCheck:
            return self.sceneName;
        case PTZBackup:
            return self.backupName;
    }
    return @"";
}

- (NSString *)sceneName {
    return [self.sourceSettings nameForScene:self.currentIndex camera:self.settingsFileCameraIP];
}

- (NSString *)backupName {
    return [self.backupSettings nameForScene:self.currentIndex camera:self.settingsFileCameraIP];
}

- (void)loadSourceSettings {
    NSString *path = [self ptzopticsSettingsFilePath];
    if (path == nil) {
        PTZLog(@"PTZOptics settings.ini file path not set");
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        PTZLog(@"%@ not found", path);
        return;
    }

    self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
}

- (void)loadBackupSettings {
    self.backupSettings = nil;
    NSString *rootPath = [self ptzopticsSettingsDirectory];
    if (rootPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:rootPath]) {
        NSString *filename = [NSString stringWithFormat:@"settings%d.ini", (int)self.rangeOffset];
        NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
        
        if (path != nil && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            self.backupSettings = [[PTZSettingsFile alloc] initWithPath:path];
        } else {
            PTZLog(@"%@ not found", path);
        }
    }
}

- (IBAction)settingsIniCopyToBackup:(id)sender {
    NSString *rootPath = [self ptzopticsSettingsDirectory];
    if (rootPath != nil) {
        NSString *filename = [NSString stringWithFormat:@"settings%d.ini", (int)self.rangeOffset];
        NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
        [self.sourceSettings writeToFile:path];
        [self loadBackupSettings];
    } else {
        PTZLog(@"Unable to copy: settings directory not found");
    }
}

/*
 * This is going to replace the entire original settings.ini
 * It moves the original to settings_backup.ini first, just in case they're completely incompatible.
 * We could just copy the scene names, and we could verify the IP addresses are the same.
 * But this is a power user tool; the UI does provide a warning, and I am trusting the users to know that their camera states are compatible, and to be able to move the file back or update settings in PTZOptics if they're wrong.
 */
- (IBAction)settingsIniCopyFromBackup:(id)sender {
    if (self.backupSettings != nil) {
        NSString *path = [self ptzopticsSettingsFilePath];
        if (path != nil) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                PTZLog(@"Moving old settings.ini to settings_backup.ini");
                NSString *rootPath = [self ptzopticsSettingsDirectory];
                NSString *backupPath = [NSString pathWithComponents:@[rootPath, @"settings_backup.ini"]];
                NSError *error;
                if ([[NSFileManager defaultManager] fileExistsAtPath:backupPath]) {
                    BOOL result = [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:backupPath] resultingItemURL:nil error:&error];
                    if (result == NO) {
                        PTZLog(@"Unable to copy: could not remove old settings_backup.ini");
                        return;
                    }
                }
                if (![[NSFileManager defaultManager] moveItemAtPath:path toPath:backupPath error:&error]) {
                    PTZLog(@"Failed to move settings.ini to settings_backup.ini: %@", error);
                    [[NSAlert alertWithError:error] runModal];
                    return;
                }
            }
            [self.backupSettings writeToFile:path];
            self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
        } else {
            PTZLog(@"Unable to copy: settings directory not found");
        }
    }
}

- (IBAction)reopenCamera:(id)sender {
    // Force close and reload.
    [self.cameraState closeAndReload:nil];
}

- (IBAction)changeCamera:(id)sender {
    [self cameraDidChange];
}

- (void)nextCamera {
    NSInteger cameraCount = [self.cameraButton numberOfItems];
    if (self.cameraIndex < cameraCount-1) {
        self.cameraIndex = self.cameraIndex + 1;
    } else {
        self.cameraIndex = 0;
    }
    [self cameraDidChange];
}

- (void)updateMode:(NSInteger)mode {
    switch (mode) {
        case PTZRestore:
            self.sceneRecallOffset = self.rangeOffset;
            self.sceneSetOffset = 0;
            break;
        case PTZCheck:
            self.sceneRecallOffset = self.sceneSetOffset = 0;
            break;
        case PTZBackup:
            self.sceneRecallOffset = 0;
            self.sceneSetOffset = self.rangeOffset;
            break;
    }
    self.currentMode = mode;
}


// In Restore mode, we can copy the backup name to the restore name.
// In Check and Restore we can edit and save it.
// That's all disabled in Backup as you can just copy the whole settings.ini file on the Batch pane and the code logic would get so much more difficult.
- (IBAction)restoreSceneName:(id)sender {
    if (self.currentMode == PTZRestore) {
        self.editableSceneSetName = self.backupName;
    }
}

- (IBAction)saveSceneName:(id)sender {
    if (self.currentMode == PTZBackup) {
        return;
    }
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if ([self.editableSceneSetName length] == 0) {
        NSBeep();
    } else {
        [self.sourceSettings setName:self.editableSceneSetName forScene:self.currentIndex camera:self.settingsFileCameraIP];
    }
    if (first != nil) {
        [window makeFirstResponder:first];
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

- (IBAction)takeSnapshot:(id)sender {
    [self.cameraState fetchSnapshot];
}

- (IBAction)saveSnapshot:(id)sender {
    NSImage *image = self.cameraState.snapshotImage;
    if (image == nil) {
        NSBeep();
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:[NSString stringWithFormat:@"snapshot_%@.jpg", self.cameraIP]];
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL *url = [panel URL];
            NSArray *representations;
            NSData *bitmapData;

            representations = [image representations];

            bitmapData = [NSBitmapImageRep representationOfImageRepsInArray:representations usingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor:@(1.0)}];

            [bitmapData writeToFile:[url path] atomically:YES];
        }
    }];
}

- (IBAction)generateHTML:(id)sender {
    // https://ptzoptics.com/wp-content/uploads/2020/11/PTZOptics-HTTP-CGI-Commands-Rev-1_4-8-20.pdf
    // Check the doc; some parameters use hex, some use decimal.
/*
 http://[Camera IP]/cgi-bin/ptzctrl.cgi?ptzcmd&[Mode]&[Pan Speed]&[Tilt Speed]&[Pan Position]&[Tilt Position]
 [Mode]: ABS, REL
 [Pan Speed]: 1 (Slowest) – 24 (Fastest)
 [Tilt Speed]: 1 (Slowest) – 20 (Fastest)
 [Pan Position]: 0001 (First step pan right), 0990 (Last step pan right), FFFE (First step pan left), F670 (Last step pan left)
 [Tilt Position]: 0001 (First step tilt up), 0510 (Last step tilt up), FFFE (First step tilt down), FE51 (Last step tilt down)
 */
    PTZCamera *cam = self.cameraState;
    NSString *camIP = cam.cameraIP;
    NSString *ptz_abs = [NSString stringWithFormat:@"http://%@/cgi-bin/ptzctrl.cgi?ptzcmd&ABS&%d&%d&%04hX&%04hX",
                          camIP, (int)cam.panSpeed, (int)cam.tiltSpeed, (short)cam.pan, (short)cam.tilt];
/*
 http://[Camera IP]/cgi-bin/ptzctrl.cgi?ptzcmd&zoomto&[Zoom Speed]&[Zoom Position]
 [Zoom Speed]: 1 (Slowest) – 7 (Fastest)
 [Zoom Position]: 0000 (Full wide), 4000 (Full tele)
 */
    NSString *ptz_zoomto = [NSString stringWithFormat:@"http://%@/cgi-bin/ptzctrl.cgi?ptzcmd&zoomto&%d&%hX",
                          camIP, (int)cam.zoomSpeed, (short)cam.zoom];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    if ([NSEvent modifierFlags] & NSEventModifierFlagOption) {
        // Include reset and home. There's no HTML for preset speed.
        /*
         http://[camera ip]/cgi-bin/ptzctrl.cgi?ptzcmd&home
         http://[camera ip]/cgi-bin/param.cgi?pan_tiltdrive_reset
         */
        NSString *ptz_home = [NSString stringWithFormat:@"http://%@/cgi-bin/ptzctrl.cgi?ptzcmd&home", camIP];
        NSString *ptz_reset = [NSString stringWithFormat:@"http://%@/cgi-bin/ptzctrl.cgi?pan_tiltdrive_reset", camIP];
        [pasteboard writeObjects:@[ptz_abs, ptz_zoomto, ptz_home, ptz_reset]];
    } else {
        [pasteboard writeObjects:@[ptz_abs, ptz_zoomto]];
    }
}

- (PTZCamera *)cameraAtIndex:(NSInteger)index {
    return [[[self.cameraButton itemAtIndex:index] representedObject] camera];
}

- (void)batchRecallCamera:(PTZCamera *)camera {
    self.batchOperationInProgress = YES;
    [camera backupRestoreWithOffset:self.rangeOffset delay:self.batchDelay isBackup:self.batchIsBackup onDone:^(BOOL success) {
        BOOL stillBusy = NO;
        NSInteger cameraCount = [self.cameraButton numberOfItems];
        for (NSInteger i = 0; i < cameraCount; i++) {
            stillBusy = stillBusy || [self cameraAtIndex:i].recallBusy;
        }
        self.batchOperationInProgress = stillBusy;
    }];
}

- (IBAction)batchAction:(id)sender {
    NSInteger cameraCount = [self.cameraButton numberOfItems];
    for (NSInteger i = 0; i < cameraCount; i++) {
        PTZCamera *camera = [self cameraAtIndex:i];
        [self batchRecallCamera:camera];
    }
}

- (IBAction)batchOneAction:(id)sender {
    [self batchRecallCamera:self.cameraState];
}

- (NSString *)batchOneButtonLabel {
    return self.batchIsBackup ? @"Backup One Camera" : @"Restore One Camera";
}

- (NSString *)batchAllButtonLabel {
    return self.batchIsBackup ? @"Backup All" : @"Restore All";
}

- (IBAction)recallScene:(id)sender {
    self.hideRecallIcon = YES;
    [self.cameraState memoryRecall:self.sceneRecallValue onDone:^(BOOL success) {
        if (success) {
            [self.cameraState updateCameraState];
            [self.cameraState fetchSnapshot]; // Fetch without saving.
        } else {
            self.hideRecallIcon = NO;
        }
    }];
}

- (void)cameraDidChange {
    self.cameraState = [[[self.cameraButton selectedItem] representedObject] camera];
    self.stateViewController.cameraState = self.cameraState;
}

// It's the "Set" command, but that's a special prefix in AppKit.

- (IBAction)restoreScene:(id)sender {
    self.hideRestoreIcon = YES;
    NSInteger sceneRecallValue = self.sceneRecallValue;
    [self.cameraState memorySet:sceneRecallValue onDone:^(BOOL success) {
        if (success) {
            [self.cameraState fetchSnapshotAtIndex:sceneRecallValue];
        } else {
            self.hideRestoreIcon = NO;
        }
    }];
}

// NSTextField actions are required so we don't propagate return to the button, because it increments. But we may stil want to load the scene.

- (IBAction)changeRangeOffset:(id)sender {
    if (!self.applicationIsReady) {
        return;
    }
    // Usually a multiple of 10 when doing batches, but can be other values for one-off saves. It's up to the user to choose wisely. I only protect you from tromping on the PTZOptics default 9.
    if (self.rangeOffset < 9) {
        self.rangeOffset = 9;
    }
    // PTZOptics doc says range for the memory commands is (0 to 127). Testing shows the real max is 89. Oddly, the command to toggle the OSD/Menu is the same as recall scene 95.
    // But other brands have different ranges, plus they could change in the future.
    NSInteger maxOffset = [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_MaxRangeOffsetKey];
    if (self.rangeOffset > maxOffset) {
        self.rangeOffset = maxOffset;
    }
    [self updateMode:self.currentMode];
    if (self.autoRecall && self.currentTab == TabSingle) {
        [self recallScene:sender];
    }
    [self loadBackupSettings];
}

- (IBAction)changeCurrentIndex:(id)sender {
    if (!self.applicationIsReady) {
        return;
    }
    if (self.currentIndex > 9) {
        self.currentIndex = 9;
    } else if (self.currentIndex < 1) {
        self.currentIndex = 1;
    }
    if (self.autoRecall) {
        [self recallScene:sender];
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector
{
    if (!self.applicationIsReady) {
        return NO;
    }
    if (commandSelector == @selector(insertNewline:)) {
        //Do something against ENTER key
        // Force the field to do an "apply". Seriously, guys, this code is ancient and there's still no better way?
        NSWindow *window = fieldEditor.window;
        NSView *first = [window ptz_currentEditingView];
        if (first != nil) {
            [window makeFirstResponder:window.contentView];
        }
        if (first != nil) {
            [window makeFirstResponder:first];
        }
        return YES;

    }
#if 0
    else if (commandSelector == @selector(deleteForward:)) {
        //Do something against DELETE key

    } else if (commandSelector == @selector(deleteBackward:)) {
        //Do something against BACKSPACE key

    } else if (commandSelector == @selector(insertTab:)) {
        //Do something against TAB key

    } else if (commandSelector == @selector(cancelOperation:)) {
        //Do something against Escape key
    }
#endif
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

- (NSInteger)sceneRecallValue {
    return _sceneRecallOffset + _currentIndex;
}


- (NSInteger)sceneSetValue {
    return _sceneSetOffset + _currentIndex;
}

- (IBAction)showLogWindow:(id)sender {
    [self.consoleWindow makeKeyAndOrderFront:nil];
}

- (IBAction)showCameraStateWindow:(id)sender {
    [self.stateWindow makeKeyAndOrderFront:nil];
}

- (IBAction)commandCancel:(id)sender {
    [self.cameraState cancelCommand];
}

- (void)writeToConsole:(NSString *)string {
    [self writeToConsole:string color:nil];
}

- (void)writeToConsole:(NSString *)string color:(NSColor *)color
{
    NSTextStorage *textStorage = [self.console textStorage];
    [textStorage beginEditing];
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:
          @{NSFontAttributeName:[NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]],
            NSForegroundColorAttributeName:(color ?: [NSColor systemGreenColor])}];

    [textStorage appendAttributedString:attributedString];
    [textStorage endEditing];
    NSRange range = NSMakeRange([[self.console string] length], 0);
    [self.console scrollRangeToVisible:range];
}

- (void)observeValueForKeyPath: (NSString *)keyPath    // IN
                      ofObject: (id)object             // IN
                        change: (NSDictionary *)change // IN
                       context: (void *)context        // IN
{
   if (context != &selfType) {
      [super observeValueForKeyPath:keyPath
                           ofObject:object
                             change:change
                            context:context];
   } else if ([keyPath isEqualToString:@"sceneSetName"]) {
       // In Backup mode it shows the backup name and is not editable.
       self.editableSceneSetName = self.sceneSetName;
   }
}

@end

