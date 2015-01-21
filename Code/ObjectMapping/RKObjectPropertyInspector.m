//
//  RKObjectPropertyInspector.m
//  RestKit
//
//  Created by Blake Watters on 3/4/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#import <objc/message.h>

#import "RKObjectPropertyInspector.h"

@implementation RKObjectPropertyInspector

- (id)init {
	if (self = [super init]) {
		_cachedPropertyNamesAndTypes = [[NSMutableDictionary alloc] init];
	}
	
	return self;
}

- (void)dealloc {
	[_cachedPropertyNamesAndTypes release];
	[super dealloc];
}

- (NSString*)propertyTypeFromAttributeString:(NSString*)attributeString {
	NSString *type = [NSString string];
	NSScanner *typeScanner = [NSScanner scannerWithString:attributeString];
	[typeScanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@"] intoString:NULL];
	
	// we are not dealing with an object
	if([typeScanner isAtEnd]) {
		return @"NULL";
	}
	[typeScanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"@"] intoString:NULL];
	// this gets the actual object type
	[typeScanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\""] intoString:&type];
	return type;
}

- (RKPropertyType)getPropertyTypeFromAttributes:(NSString*)attributes
{
	if([attributes length] > 1)
	{
		NSString* two = [attributes substringToIndex:2];
		
		if([two isEqualToString:@"T@"])
			return RKPropertyTypeClass;
		
		if([two isEqualToString:@"TB"] || [two isEqualToString:@"Tb"])
			return RKPropertyTypeBool;
		if([two isEqualToString:@"Ti"])
			return RKPropertyTypeInt;
		if([two isEqualToString:@"TB"])
			return RKPropertyTypeInt;
		if([two isEqualToString:@"TI"])
			return RKPropertyTypeUInt;
		if([two isEqualToString:@"Tc"])
			return RKPropertyTypeChar;
		if([two isEqualToString:@"TC"])
			return RKPropertyTypeUChar;
		if([two isEqualToString:@"Ts"])
			return RKPropertyTypeShort;
		if([two isEqualToString:@"TS"])
			return RKPropertyTypeUShort;
		
		if([two isEqualToString:@"Tl"])
			return RKPropertyTypeLong;
		if([two isEqualToString:@"TL"])
			return RKPropertyTypeULong;
		if([two isEqualToString:@"Tq"])
			return RKPropertyTypeLongLong;
		if([two isEqualToString:@"TQ"])
			return RKPropertyTypeULongLong;
		
		if([two isEqualToString:@"Tf"])
			return RKPropertyTypeFloat;
		if([two isEqualToString:@"Td"])
			return RKPropertyTypeDouble;
	}
	
	return RKPropertyTypeUnknown;
}

- (NSDictionary *)propertyNamesAndTypesForClass:(Class)class {
	NSMutableDictionary* propertyNames = [_cachedPropertyNamesAndTypes objectForKey:class];
	if (propertyNames) {
		return propertyNames;
	}
	propertyNames = [NSMutableDictionary dictionary];
	
	//include superclass properties
	Class currentClass = class;
	while (currentClass != nil) {
		// Get the raw list of properties
		unsigned int outCount;
		objc_property_t *propList = class_copyPropertyList(currentClass, &outCount);
		
		// Collect the property names
		int i;
		NSString *propName;
		for (i = 0; i < outCount; i++) {
			// TODO: Add support for custom getter and setter methods
			// property_getAttributes() returns everything we need to implement this...
			// See: http://developer.apple.com/mac/library/DOCUMENTATION/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW5
			objc_property_t* prop = propList + i;
			NSString* attributeString = [NSString stringWithCString:property_getAttributes(*prop) encoding:NSUTF8StringEncoding];			
			propName = [NSString stringWithCString:property_getName(*prop) encoding:NSUTF8StringEncoding];
			
			if (![propName isEqualToString:@"_mapkit_hasPanoramaID"]) {
				
				RKPropertyType type = [self getPropertyTypeFromAttributes:attributeString];
				
				if(type == RKPropertyTypeClass)
				{
					const char* className = [[self propertyTypeFromAttributeString:attributeString] cStringUsingEncoding:NSUTF8StringEncoding];
					Class class = objc_getClass(className);
					// TODO: Use an id type if unable to get the class??
					if (class) {
						[propertyNames setObject:@{@"type" : @(type), @"class" : class} forKey:propName];
					}
				}
				else if(type != RKPropertyTypeUnknown)
					[propertyNames setObject:@{@"type" : @(type)} forKey:propName];
				else
				{
					static NSArray* props = nil;
					if(!props)
						props = [@[@"accessibilityFrame", @"accessibilityActivationPoint", @"classForKeyedArchiver", @"observationInfo", @"superclass"] retain];
					if(![[props filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%@ in SELF", propName]] count])
						NSLog(@"UNKNOWN: %@ (%@)", propName, attributeString);
				}
			}
		}
		
		free(propList);
		currentClass = [currentClass superclass];
	}
	
	if(propertyNames && class)
		[_cachedPropertyNamesAndTypes setObject:propertyNames forKey:(id<NSCopying>)class];
	return propertyNames;
}

@end
