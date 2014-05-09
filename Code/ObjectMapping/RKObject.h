//
//  RKObject.h
//  RestKit
//
//  Created by Blake Watters on 7/20/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#import "RKObjectMappable.h"

@class RKResponse;

/**
 * Base class for non-managed RestKit mappable objects.
 */
@interface RKObject : NSObject <RKObjectMappable, NSCoding> {

}

+ (id)objectFromResponse:(RKResponse*)response;
+ (id)objectFromJsonString:(NSString*)json;
+ (id)objectFromDictionary:(NSDictionary*)dic;
+ (NSArray*)arrayOfObjectsFromDictionaries:(NSArray*)dictionaries;

- (void)mapFromDictionary:(NSDictionary*)dic;

- (void)copyPropertiesFromObject:(RKObject*)object;

@end
