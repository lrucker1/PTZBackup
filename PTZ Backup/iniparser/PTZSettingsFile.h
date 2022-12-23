//
//  PTZSettingsFile.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/22/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTZSettingsFile : NSObject

- (instancetype)initWithPath:(NSString *)path;
- (void)logDictionary;
- (NSString *)stringForKey:(NSString *)aKey;
- (BOOL)writeToFile:(NSString *)file;

- (NSArray *)cameraInfo;
- (NSString *)nameForScene:(NSInteger)scene camera:(NSString *)ipAddr;

@end

NS_ASSUME_NONNULL_END
