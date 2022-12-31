//
//  PTZPrefCamera.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/30/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZCamera;

@interface PTZPrefCamera : NSObject
@property NSString *cameraname;
@property NSString *devicename;
@property NSString *originalDeviceName;
@property PTZCamera *camera;

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;

@end

NS_ASSUME_NONNULL_END
