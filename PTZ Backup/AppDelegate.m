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
#import "NSWindowAdditions.h"


typedef enum {
    PTZRestore = 0,
    PTZCheck = 1,
    PTZBackup = 2
} PTZMode;

typedef enum {
    TabSingle = 0,
    TabBatch
} CurrentTab;

static NSString *PTZ_SettingsPathKey = @"PTZSettingsPath";
static NSString *PTZ_SettingsFilePathKey = @"PTZSettingsFilePath";
static NSString *PTZ_BatchDelayKey = @"BatchDelay";
static NSString *PTZ_RangeOffsetKey = @"RangeOffset";
static NSString *PTZ_UseLocalCamerasKey = @"UseLocalCameraSettings";
static NSString *PTZ_MaxRangeOffsetKey = @"MaxRangeOffset";


@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSWindow *stateWindow;
@property (strong) IBOutlet NSTextView *console;
@property (strong) IBOutlet NSPopUpButton *cameraButton;
@property (strong) IBOutlet PTZCameraStateViewController *stateViewController;

@property NSInteger rangeOffset, currentIndex;
@property NSInteger openCamera, cameraIndex;
@property NSInteger recallOffset, restoreOffset;
@property (readonly) NSInteger recallValue, restoreValue;
@property NSInteger batchDelay;
@property NSInteger currentMode;
@property NSInteger currentTab;
@property BOOL autoRecall;
@property BOOL hideRecallIcon, hideRestoreIcon;
@property BOOL batchIsBackup;
@property BOOL batchCancelPending, batchOperationInProgress;
@property (strong) NSFileHandle* pipeReadHandle;
@property (strong) NSPipe *pipe;
@property (strong) PTZCamera *cameraState;
@property PTZPrefsController *prefsController;
@property (strong) PTZSettingsFile *sourceSettings;
@property (strong) PTZSettingsFile *backupSettings;

@end

@implementation AppDelegate

+ (void)initialize {
    [super initialize];
    // Has to happen here so it's set before window restoration happens. There are all sorts of side effects, like end-editing on textfields which triggers validation before all the values are set.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{PTZ_BatchDelayKey:@(5),PTZ_RangeOffsetKey:@(80),PTZ_MaxRangeOffsetKey:@(80)}];
}

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
    if (   [key isEqualToString:@"sceneName"]) {
        [keyPaths addObject:@"sourceSettings"];
        [keyPaths addObject:@"currentIndex"];
        [keyPaths addObject:@"cameraIndex"];
        [keyPaths addObject:@"cameraList"];
    }
    if (   [key isEqualToString:@"backupName"]) {
        [keyPaths addObject:@"backupSettings"];
        [keyPaths addObject:@"currentIndex"];
        [keyPaths addObject:@"cameraIndex"];
    }
    if (   [key isEqualToString:@"recallName"]
        || [key isEqualToString:@"restoreName"]) {
        [keyPaths addObject:@"backupName"];
        [keyPaths addObject:@"sceneName"];
        [keyPaths addObject:@"currentMode"];
    }
    if (   [key isEqualToString:@"cameraName"]
        || [key isEqualToString:@"cameraIP"]) {
        [keyPaths addObject:@"cameraIndex"];
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

- (void)handlePipeNotification:(NSNotification *)notification {
    [_pipeReadHandle readInBackgroundAndNotify];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stdOutString = [[NSString alloc] initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
        [self writeToConsole:stdOutString];
    });
}

- (NSInteger)batchDelay {
    return [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_BatchDelayKey];
}

- (void)setBatchDelay:(NSInteger)value {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:PTZ_BatchDelayKey];
}

- (NSInteger)rangeOffset {
    return [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_RangeOffsetKey];
}

- (void)setRangeOffset:(NSInteger)value {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:PTZ_RangeOffsetKey];
}

- (NSString *)ptzopticsSettingsFilePath {
    return [[NSUserDefaults standardUserDefaults] stringForKey:PTZ_SettingsFilePathKey];
}

// path/to/settings.ini. Should be a subdir of PTZOptics, not OBS - that's the wrong format!
- (void)setPtzopticsSettingsFilePath:(NSString *)newPath {
    NSString *oldPath = self.ptzopticsSettingsFilePath;
    if (![oldPath isEqualToString:newPath]) {
        [[NSUserDefaults standardUserDefaults] setObject:newPath forKey:PTZ_SettingsFilePathKey];
    }
}

// should contain settings.ini, downloads folder, and backup settingsXX.ini
// I saw an entry for a custom downloads path in settings.ini once, but I can't see where the actual app is using it. So I'm not checking for it; if you use a custom downloads folder this is your todo note.
- (NSString *)ptzopticsSettingsDirectory {
    return [[self ptzopticsSettingsFilePath] stringByDeletingLastPathComponent];
}

- (void)applyPrefChanges {
    [self willChangeValueForKey:@"cameraList"];
    [self updateCameraPopup];
    [self didChangeValueForKey:@"cameraList"];
}

- (void)configConsoleRedirect {
    _pipe = [NSPipe pipe];
    _pipeReadHandle = [_pipe fileHandleForReading];
    dup2([[_pipe fileHandleForWriting] fileDescriptor], fileno(stderr));
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePipeNotification:) name:NSFileHandleReadCompletionNotification object:_pipeReadHandle];
    [_pipeReadHandle readInBackgroundAndNotify];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    self.openCamera = -1;
    
    self.cameraState = [PTZCamera new];
    self.stateViewController.cameraState = self.cameraState;
    BOOL useLocalhost = NO;
    // Insert code here to initialize your application
    for (NSString *arg in [[NSProcessInfo processInfo] arguments]) {
        if ([arg isEqualToString:@"localhost"]) {
            useLocalhost = YES;
            [self writeToConsole:@"Using localhost\n"];
            [self.cameraButton removeAllItems];
            [self.cameraButton addItemWithTitle:@"localhost"];
            [[self.cameraButton lastItem] setRepresentedObject:@[@"localhost", @"localhost"]];
            [self loadCamera];
        }
    }
    if (useLocalhost) {
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
    self.currentIndex = 1;
    self.cameraIndex = 0;
    [self updateMode:0]; // TODO: Defaults
    self.hideRestoreIcon = YES;
    self.hideRecallIcon = YES;
    NSString *iniPath = [self ptzopticsSettingsFilePath];
    if (iniPath == nil || [[NSFileManager defaultManager] fileExistsAtPath:iniPath]) {
        [self showPrefs:nil];
    }
    [self loadBackupSettings];
}

- (BOOL)recallBusy {
    return self.cameraState.recallBusy;
}

- (BOOL)connectingBusy {
    return self.cameraState.connectingBusy;
}

- (NSArray *)cameraList {
    NSString *path = [self ptzopticsSettingsFilePath];
    if (path == nil) {
        NSLog(@"PTZOptics settings.ini file path not set");
        return nil;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"%@ not found", path);
        return nil;
    }

    self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
    NSArray *cameras = [self.sourceSettings cameraInfo];
    if ([cameras count] > 0) {
        return cameras;
    }

    NSLog(@"No valid cameras found in %@", path);
    [self.sourceSettings logDictionary];
    return nil;
}

- (void)updateCameraPopup {
    NSArray *cameraList = nil;
    [self closeCamera];
    BOOL useLocal = [[NSUserDefaults standardUserDefaults] boolForKey:PTZ_UseLocalCamerasKey];
    
    if (useLocal) {
        cameraList = [[NSUserDefaults standardUserDefaults] arrayForKey:@"LocalCameras"];
    } else {
        cameraList = [self cameraList];
    }
    [self.cameraButton removeAllItems];
    int i = 1;
    for (NSDictionary *cameraInfo in cameraList) {
        NSString *cameraname = [cameraInfo objectForKey:@"cameraname"];
        NSString *title = [NSString stringWithFormat:@"%d - %@", i++, cameraname];
        NSString *ipAddr = [cameraInfo objectForKey:@"devicename"];
        NSString *originalIP = [cameraInfo objectForKey:@"original"] ?: ipAddr;
        [self.cameraButton addItemWithTitle:title];
        [[self.cameraButton lastItem] setRepresentedObject:@[ipAddr, originalIP]];
    }
    if ([cameraList count] > 0) {
        [self cameraDidChange];
    }
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
}

- (NSString *)cameraName {
    return [[self.cameraButton selectedItem] title];
}

// Current camera address
- (NSString *)cameraIP {
    return [[[self.cameraButton selectedItem] representedObject] firstObject];
}

// Address as used in settings.ini
- (NSString *)settingsFileCameraIP {
    return [[[self.cameraButton selectedItem] representedObject] lastObject];
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
    return [self.sourceSettings nameForScene:self.currentIndex camera:self.settingsFileCameraIP];
}

- (NSString *)backupName {
    return [self.backupSettings nameForScene:self.currentIndex camera:self.settingsFileCameraIP];
}

// memory_recall, memory_set
// ./visla_cli -d $IP memory_recall $recallOffset
- (NSString *)currentCommand {
    NSString *cameraIP = [self cameraIP];
    return [NSString stringWithFormat:@"./visca_cli -d %@ memory_recall %ld\n./visca_cli -d %@ memory_set %ld", cameraIP, (long)self.recallValue, cameraIP, (long)self.restoreValue];
}

- (void)closeCamera {
    if (self.openCamera != -1) {
        [self.cameraState closeCamera];
        self.openCamera = -1;
    }
}

- (void)loadCamera {
    if (self.openCamera != -1) {
        self.openCamera = -1;
    }
    // Close and reload
    [self.cameraState closeAndReload:^(BOOL success) {
        if (success) {
            self.openCamera = self.cameraIndex;
        }
    }];
}

- (void)loadBackupSettings {
    self.backupSettings = nil;
    NSString *rootPath = [self ptzopticsSettingsDirectory];
    if (rootPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:rootPath]) {
        NSString *filename = [NSString stringWithFormat:@"settings%d.ini", (int)self.recallOffset];
        NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
        
        if (path != nil && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            self.backupSettings = [[PTZSettingsFile alloc] initWithPath:path];
        }
    }
}

- (IBAction)settingsIniCopyToBackup:(id)sender {
    NSString *rootPath = [self ptzopticsSettingsDirectory];
    if (rootPath != nil) {
        NSString *filename = [NSString stringWithFormat:@"settings%d.ini", (int)self.recallOffset];
        NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
        [self.sourceSettings writeToFile:path];
        [self loadBackupSettings];
    } else {
        NSLog(@"Unable to copy: settings directory not found");
    }
}

- (IBAction)settingsIniCopyFromBackup:(id)sender {
    if (self.backupSettings != nil) {
        NSString *rootPath = [self ptzopticsSettingsDirectory];
        if (rootPath != nil) {
            NSString *path = [NSString pathWithComponents:@[rootPath, @"settings.ini"]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                NSLog(@"Copying old settings.ini to settings_backup.ini");
                NSString *backupPath = [NSString pathWithComponents:@[rootPath, @"settings_backup.ini"]];
                NSError *error;
                if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:backupPath error:&error]) {
                    NSLog(@"Failed to make settings_backup: %@", error);
                    [[NSAlert alertWithError:error] runModal];
                    return;
                }
            }
            [self.backupSettings writeToFile:path];
            self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
        } else {
            NSLog(@"Unable to copy: settings directory not found");
        }
    }
}

- (IBAction)reopenCamera:(id)sender {
    [self loadCamera];
}

- (IBAction)changeCamera:(id)sender {
    if (self.openCamera != self.cameraIndex) {
        [self cameraDidChange];
    }
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
        [window makeFirstResponder:window.contentView];
    }
    [self.cameraState applyPantiltPresetSpeed:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)applyBatchDelay:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [self currentEditingViewForWindow:window];
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

    [self.cameraState applyPantiltAbsolutePosition:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)applyZoom:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [self currentEditingViewForWindow:window];
    [self.cameraState applyZoom:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)updateCameraState:(id)sender {
    [self.cameraState updateCameraState];
}

- (IBAction)cameraHome:(id)sender {
    [self.cameraState pantiltHome:nil];
}

- (IBAction)cameraReset:(id)sender {
    [self.cameraState pantiltReset:nil];
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

- (void)batchRecallCamera:(NSString *)cameraIP {
    [self.cameraState backupRestoreWithAddress:cameraIP offset:self.rangeOffset delay:self.batchDelay isBackup:self.batchIsBackup onDone:nil];
}

- (IBAction)batchAction:(id)sender {
    NSInteger cameraCount = [self.cameraButton numberOfItems];
    for (NSInteger i = 0; i < cameraCount; i++) {
        self.cameraIndex = i;
        [self batchRecallCamera:self.cameraIP];
    }
}

- (IBAction)batchOneAction:(id)sender {
    [self batchRecallCamera:self.cameraIP];
}

- (NSString *)batchOneButtonLabel {
    return self.batchIsBackup ? @"Backup One Camera" : @"Restore One Camera";
}

- (NSString *)batchAllButtonLabel {
    return self.batchIsBackup ? @"Backup All" : @"Restore All";
}

- (IBAction)recallScene:(id)sender {
    self.hideRecallIcon = YES;
    [self.cameraState memoryRecall:self.recallValue onDone:^(BOOL success) {
        if (success) {
            [self.cameraState updateCameraState];
        } else {
            self.hideRecallIcon = NO;
        }
    }];
}

- (void)cameraDidChange {
    [self.cameraState changeCamera:self.cameraIP];
}

- (IBAction)restoreScene:(id)sender {
    self.hideRestoreIcon = YES;
    NSInteger recallValue = self.recallValue;
    [self.cameraState memorySet:recallValue onDone:^(BOOL success) {
        if (success) {
            [self.cameraState fetchSnapshotAtIndex:recallValue];
        } else {
            self.hideRestoreIcon = NO;
        }
    }];
}

// NSTextField actions are required so we don't propagate return to the button, because it increments. But we may stil want to load the scene.

- (IBAction)changeRangeOffset:(id)sender {
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
    //NSLog(@"Selector method is (%@)", NSStringFromSelector( commandSelector ) );
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

- (NSInteger)recallValue {
    return _recallOffset + _currentIndex;
}


- (NSInteger)restoreValue {
    return _restoreOffset + _currentIndex;
}

- (IBAction)commandCancel:(id)sender {
    [self.cameraState cancelCommand];
}

- (void)writeToConsole:(NSString *)string // IN
{
    NSTextStorage *textStorage = [self.console textStorage];
    [textStorage beginEditing];
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:@{NSFontAttributeName:[NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]]}];

    [textStorage appendAttributedString:attributedString];
    [textStorage endEditing];
    NSRange range = NSMakeRange([[self.console string] length], 0);
    [self.console scrollRangeToVisible:range];
}

@end

