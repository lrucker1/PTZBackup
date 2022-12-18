//
//  PTZCamera.h
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTZCamera : NSObject

@property NSInteger tilt;
@property NSInteger pan;
@property NSInteger zoom;

@property NSInteger tiltSpeed;
@property NSInteger panSpeed;
@property NSInteger presetSpeed;

@end

NS_ASSUME_NONNULL_END
