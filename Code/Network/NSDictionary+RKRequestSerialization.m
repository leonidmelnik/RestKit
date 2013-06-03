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
		for(NSString* key in element)
		{
			NSArray* additionalElements = [self URLEncodedElement:[element objectForKey:key]];
			for(NSString* additionalEl in additionalElements)
				[result addObject:[NSString stringWithFormat:@"[%@]%@", urlEncode(key), additionalEl]];
		}
	}
	else if([element isKindOfClass: [NSArray class]])
	{
		for(id value in element)
		{
			NSArray* additionalElements = [self URLEncodedElement:value];
			for(NSString* additionalEl in additionalElements)
				[result addObject:[NSString stringWithFormat:@"[%d]%@", [element indexOfObject:value], additionalEl]];
		}
	}
	else
		[result addObject:[NSString stringWithFormat:@"=%@", urlEncode(element)]];
	
	return result;
}

- (NSString*)URLEncodedString
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

//- (NSString*)URLEncodedString
//{
//	NSMutableArray *parts = [NSMutableArray array];
//	for (id key in self)
//	{
//		id value = [self objectForKey:key];
//		if ([value isKindOfClass:[NSArray class]])
//		{
//			for (id item in value)
//			{
//				NSString *part = [NSString stringWithFormat: @"%@[]=%@",
//								  urlEncode(key), urlEncode(item)];
//				[parts addObject:part];
//			}
//		}
//		else
//		{
//			NSString *part = [NSString stringWithFormat: @"%@=%@",
//							  urlEncode(key), urlEncode(value)];
//			[parts addObject:part];
//		}
//	}
//
//	return [parts componentsJoinedByString: @"&"];
//}

- (NSString*)HTTPHeaderValueForContentType {
	return @"application/x-www-form-urlencoded";
}

- (NSData*)HTTPBody {
	return [[self URLEncodedString] dataUsingEncoding:NSUTF8StringEncoding];
}

@end
