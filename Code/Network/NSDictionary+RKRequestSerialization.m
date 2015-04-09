//
//  NSDictionary+RKRequestSerialization.m
//  RestKit
//
//  Created by Blake Watters on 7/28/09.
//  Copyright 2009 Two Toasters. All rights reserved.
//

#import "NSDictionary+RKRequestSerialization.h"
#import <RestKit/JSONParser+SBJSON/JSON.h>

// private helper function to convert any object to its string representation
static NSString *toString(id object) {
	return [NSString stringWithFormat: @"%@", object];
}

// private helper function to convert string to UTF-8 and URL encode it
static NSString *urlEncode(id object) {
	NSString *string = toString(object);
	NSString *encodedString = (NSString*)CFURLCreateStringByAddingPercentEscapes(NULL,
																				 (CFStringRef)string,
																				 NULL,
																				 (CFStringRef)@"!*'();:@&=+$,/?%#[]",
																				 kCFStringEncodingUTF8);
	return [encodedString autorelease];
}


@implementation NSDictionary (RKRequestSerialization)

- (NSArray*)URLEncodedElement:(id)element
{
	NSMutableArray* result = [NSMutableArray array];
	
	if([element isKindOfClass:[NSDictionary class]])
	{
		[element enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			NSString* encKey = urlEncode(key);
			NSArray* additionalElements = [self URLEncodedElement:obj];
			[additionalElements enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				[result addObject:[NSString stringWithFormat:@"[%@]%@", encKey, obj]];
			}];
		}];
	}
	else if([element isKindOfClass: [NSArray class]])
	{
		[element enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			NSArray* additionalElements = [self URLEncodedElement:obj];
			for(NSString* additionalEl in additionalElements)
				[result addObject:[NSString stringWithFormat:@"[%lu]%@", (unsigned long)idx, additionalEl]];
		}];
	}
	else
		[result addObject:[NSString stringWithFormat:@"=%@", urlEncode(element)]];
	
	return result;
}

- (NSString*)URLEncodedString:(RKBodyType)bodyType
{
	switch(bodyType)
	{
		case RKBodyJson:
		{
			NSMutableArray* result = [NSMutableArray array];
			
			for(NSString* key in self)
			{
				id obj = [self objectForKey:key];
				if([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]])
					[result addObject:[NSString stringWithFormat:@"%@=%@", key, [obj JSONRepresentation]]];
				else
					[result addObject:[NSString stringWithFormat:@"%@=%@", key, obj]];
			}
			
			return [result componentsJoinedByString:@"&"];	
		}
		case RKBodyLevels:
		{
			NSMutableArray *parts = [NSMutableArray array];
			for (id key in self)
			{
				id value = [self objectForKey:key];
				if ([value isKindOfClass:[NSArray class]])
				{
					for (id item in value)
					{
						NSString *part = [NSString stringWithFormat: @"%@[]=%@",
										  urlEncode(key), urlEncode(item)];
						[parts addObject:part];
					}
				}
				else
				{
					NSString *part = [NSString stringWithFormat: @"%@=%@",
									  urlEncode(key), urlEncode(value)];
					[parts addObject:part];
				}
			}

			return [parts componentsJoinedByString: @"&"];
		}
	}
}

- (NSString*)HTTPHeaderValueForContentType {
	return @"application/x-www-form-urlencoded";
}

- (NSData*)HTTPBody:(RKBodyType)bodyType {
	return [[self URLEncodedString:bodyType] dataUsingEncoding:NSUTF8StringEncoding];
}

@end
