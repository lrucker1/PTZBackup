//
//  NSWindowAdditions.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/29/22.
//

#ifndef NSWindowAdditions_h
#define NSWindowAdditions_h

@interface NSWindow (PTZAdditions)
- (NSView *)ptz_currentEditingView;
@end

#endif /* NSWindowAdditions_h */
