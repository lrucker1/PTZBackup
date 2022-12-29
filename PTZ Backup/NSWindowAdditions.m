//
//  NSWindowAdditions.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/29/22.
//

#import <AppKit/AppKit.h>
#import "NSWindowAdditions.h"

@implementation NSWindow (PTZAdditions)


- (NSView *)ptz_currentEditingView {
    NSView *fieldEditor = [self fieldEditor:NO forObject:nil];
    NSView *first = nil;
    if (fieldEditor != nil) {
        first = fieldEditor;
        do {
            first = [first superview];
        } while (first != nil && ![first isKindOfClass:[NSTextField class]]);
    }
    return first;
}


@end
