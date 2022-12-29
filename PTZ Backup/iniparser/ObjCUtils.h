//
//  ObjCUtils.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/25/22.
//

#ifndef ObjCUtils_h
#define ObjCUtils_h

NSError *
OCUtilErrorWithDescription(NSString *errorDescription,
                           NSString *errorRecovery,
                           NSString *errorDomain,
                           int code);

#endif /* ObjCUtils_h */
