//
//  PTZCameraStateViewController.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/29/22.
//

#import "PTZCameraStateViewController.h"
#import "PTZCamera.h"
#import "NSWindowAdditions.h"

@interface PTZCameraStateViewController ()

@end

@implementation PTZCameraStateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
 }

- (IBAction)applyRecallSpeed:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    [self.cameraState applyPantiltPresetSpeed:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
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

- (IBAction)changePresetSpeed:(id)sender {
    if (self.cameraState.presetSpeed > 0x18) {
        self.cameraState.presetSpeed = 0x18;
    } else if (self.cameraState.presetSpeed < 1) {
        self.cameraState.presetSpeed = 1;
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


- (IBAction)applyPanTilt:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
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
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
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

@end
