//
//  NSDictionary+RKRequestSerialization.m
//  RestKit
//
//  Created by Blake Watters on 7/28/09.
//  Copyright 2009 Two Toasters. All rights reserved.
//

#import "NSDictionary+RKRequestSerialization.h"

// private helper function to convert any object to its string representation
static NSString *toString(id object) {
	return [NSString stringWithFormat: @"%@", object];
}

// private helper function to convert string to UTF-8 and URL encode it
static NSString *urlEncode(id object) {
	NSString *string = toString(object);
#if TARGET_OS_WATCH
	NSString *encodedString = [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
#else
	NSString *encodedString = [((NSString*)CFURLCreateStringByAddingPercentEscapes(NULL,
																				   (CFStringRef)string,
																				   NULL,
																				   (CFStringRef)@"!*'();:@&=+$,/?%#[]",
																				   kCFStringEncodingUTF8)) autorelease];
#endif
	return encodedString;
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
				{
					NSData* jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
					NSString* jsonString = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
					[result addObject:[NSString stringWithFormat:@"%@=%@", urlEncode(key), urlEncode(jsonString)]];
				}
				else
					[result addObject:[NSString stringWithFormat:@"%@=%@", urlEncode(key), urlEncode(obj)]];
			}
			
			return [result componentsJoinedByString:@"&"];	
		}
		case RKBodyLevels:
		{
			NSMutableArray* result = [NSMutableArray array];
			
			for(NSString* key in self)
			{
				NSArray* additionalElements = [self URLEncodedElement:[self objectForKey:key]];
				for(NSString* additionalEl in additionalElements)
					[result addObject:[NSString stringWithFormat:@"%@%@", key, additionalEl]];
			}
			
			return [result componentsJoinedByString:@"&"];
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
