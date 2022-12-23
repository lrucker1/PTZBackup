//
//  PTZPrefsController.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/22/22.
//

#import "PTZPrefsController.h"
#import "AppDelegate.h"

@interface PTZPrefsController ()

@property IBOutlet NSPathControl *iniFilePathControl;

@end

@implementation PTZPrefsController

- (NSString *)windowNibName {
    return @"PTZPrefsController";
}

- (void)windowDidLoad {
    [super windowDidLoad];
//    self.window.backgroundColor = NSColor.whiteColor;
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    NSString *path = [(AppDelegate *)[NSApp delegate] obsSettingsDirectory];
    if (path) {
        self.iniFilePathControl.URL = [NSURL fileURLWithPath:path];
    }
}

- (void)pathControl:(NSPathControl *)pathControl willDisplayOpenPanel:(NSOpenPanel *)openPanel {
    if (pathControl.URL == nil) {
        // NSApplicationSupportDirectory
        openPanel.directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:NULL create:NO error:NULL];
    }
    openPanel.canChooseFiles = NO;
    openPanel.canChooseDirectories = YES;
    openPanel.allowsMultipleSelection = NO;
}

- (IBAction)applyChanges:(id)sender {
    NSURL *url = self.iniFilePathControl.URL;
    NSString *path = [url path];
    [(AppDelegate *)[NSApp delegate] setObsSettingsDirectory:path];
}

@end
