//
//  AppDelegate.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/6/22.
//

#import "AppDelegate.h"

typedef enum {
    PTZRestore = 0,
    PTZCheck = 1,
    PTZBackup = 2
} PTZMode;

NSString *cameraIPs[3] = {
    @"192.168.13.201",
    @"192.168.13.202",
    @"192.168.13.203"
};
@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property NSInteger rangeOffset, currentIndex, cameraIndex;
@property NSInteger recallOffset, restoreOffset;
@property (readonly) NSInteger recallValue, restoreValue;
@property NSInteger currentMode;
@property BOOL autoRecall;
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
    self.rangeOffset = 80; // TODO: Defaults
    self.currentIndex = 1;
    self.cameraIndex = 0;
    [self updateMode:0]; // TODO: Defaults
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (NSString *)cameraIP {
    NSAssert(self.cameraIndex >= 0 && self.cameraIndex < 3, @"Camera index %ld out of range (0-3)", (long)self.cameraIndex);
    return cameraIPs[self.cameraIndex];
}

// memory_recall, memory_set
// ./visla_cli -d $IP memory_recall $recallOffset
- (NSString *)currentCommand {
    NSString *cameraIP = [self cameraIP];
    return [NSString stringWithFormat:@"./visca_cli -d %@ memory_recall %ld\n./visca_cli -d %@ memory_set %ld", cameraIP, (long)self.recallValue, cameraIP, (long)self.restoreValue];
}

- (void)nextCamera {
    if (self.cameraIndex < 2) {
        self.cameraIndex = self.cameraIndex + 1;
    } else {
        self.cameraIndex = 0;
    }
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
    NSString *cameraIP = [self cameraIP];
    NSLog(@"./visca_cli -d %@ memory_recall %ld", cameraIP, (long)self.recallValue);

}

- (IBAction)restoreScene:(id)sender {
    NSString *cameraIP = [self cameraIP];
    NSLog(@"./visca_cli -d %@ memory_set %ld", cameraIP, (long)self.restoreValue);

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
