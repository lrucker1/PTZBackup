//
//  ObjCUtils.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/25/22.
//

#import <Foundation/Foundation.h>

NSError *
OCUtilErrorWithDescription(NSString *errorDescription,
                           NSString *errorRecovery,
                           NSString *errorDomain,
                           int code)
{
   if (!errorDescription || !errorDomain) {
      /*
       * This shouldn't happen, so throw a generic error rather than
       * letting an exception happen.
       */
      return [NSError errorWithDomain:@"ObjCUtil"
                                 code:code
                             userInfo:nil];
   }

   NSMutableDictionary *userInfo =
      [NSMutableDictionary
         dictionaryWithObject:errorDescription
                       forKey:NSLocalizedDescriptionKey];

   if (errorRecovery) {
      [userInfo setObject:errorRecovery
                   forKey:NSLocalizedRecoverySuggestionErrorKey];
   }

   return [NSError errorWithDomain:errorDomain
                              code:code
                          userInfo:userInfo];
}
