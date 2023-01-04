//
//  PTZPrefsController.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/22/22.
//

#import "PTZPrefsController.h"
#import "PTZSettingsFile.h"
#import "PTZPrefCamera.h"
#import "AppDelegate.h"
#import "NSWindowAdditions.h"


@interface PTZPrefsController ()

@property IBOutlet NSPathControl *iniFilePathControl;
@property NSMutableArray *cameras;

@end

@implementation PTZPrefsController

- (NSString *)windowNibName {
    return @"PTZPrefsController";
}

- (void)windowDidLoad {
    [super windowDidLoad];
//    self.window.backgroundColor = NSColor.whiteColor;
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    NSString *path = [(AppDelegate *)[NSApp delegate] ptzopticsSettingsFilePath];
    if (path) {
        self.iniFilePathControl.URL = [NSURL fileURLWithPath:path];
    }
    NSMutableArray *prefCams = [NSMutableArray array];
    NSArray *defCams = [[NSUserDefaults standardUserDefaults] objectForKey:PTZ_LocalCamerasKey];
    for (NSDictionary *cam in defCams) {
        [prefCams addObject:[[PTZPrefCamera alloc] initWithDictionary:cam]];
    }
    self.cameras = prefCams;
}

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    // Wouldn't it be nice if we didn't have to check directories, given that we've only enabled canChooseFiles?
    BOOL isDirectory;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDirectory] && isDirectory) {
        return YES;
    }
    if ([[url lastPathComponent] isEqualToString:@"settings.ini"]) {
        return YES;
    }
    return NO;
}

- (BOOL)panel:(id)sender
  validateURL:(NSURL *)url
        error:(NSError * _Nullable *)outError {
    return [PTZSettingsFile validateFileWithPath:[url path] error:outError];
}

- (void)pathControl:(NSPathControl *)pathControl willDisplayOpenPanel:(NSOpenPanel *)openPanel {
    if (pathControl.URL == nil) {
        // NSApplicationSupportDirectory
        openPanel.directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:NULL create:NO error:NULL];
    }
    openPanel.delegate = self;
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (IBAction)showIniFileInFinder:(id)sender {
    NSURL *url = self.iniFilePathControl.URL;
    [[NSWorkspace sharedWorkspace] selectFile:[url path]
                     inFileViewerRootedAtPath:[url path]];
}

- (IBAction)applyChanges:(id)sender {
    NSURL *url = self.iniFilePathControl.URL;
    NSString *path = [url path];
    [self.appDelegate setPtzopticsSettingsFilePath:path];
    NSMutableArray *prefCams = [NSMutableArray array];
    for (PTZPrefCamera *cam in self.cameras) {
        [prefCams addObject:[cam dictionaryValue]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:prefCams forKey:PTZ_LocalCamerasKey];
    [self.appDelegate applyPrefChanges];
}

- (IBAction)loadFromSettingsFile:(id)sender {
    NSArray *iniCameras = self.appDelegate.cameraList;
    NSMutableArray *cams = [NSMutableArray array];
    for (NSDictionary *cam in iniCameras) {
        [cams addObject:[[PTZPrefCamera alloc] initWithDictionary:cam]];
    }
    self.cameras = cams;
}


- (NSInteger)batchDelay {
    return [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_BatchDelayKey];
}

- (void)setBatchDelay:(NSInteger)value {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:PTZ_BatchDelayKey];
}

- (IBAction)applyBatchDelay:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

@end
