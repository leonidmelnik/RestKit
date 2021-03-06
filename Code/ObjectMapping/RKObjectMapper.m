//
//  RKObjectMapper.m
//  RestKit
//
//  Created by Blake Watters on 3/4/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#import <objc/message.h>

// TODO: Factor out Core Data...
#import "../CoreData/RKCoreData.h"

#import "RKObjectMapper.h"
#import "NSDictionary+RKAdditions.h"
#import "RKJSONParser.h"
#import "Errors.h"

// Default format string for date and time objects from Rails
// TODO: Rails specifics should probably move elsewhere...
static const NSString* kRKModelMapperRailsDateTimeFormatString = @"yyyy-MM-dd'T'HH:mm:ss'Z'"; // 2009-08-08T17:23:59Z
static const NSString* kRKModelMapperRailsDateFormatString = @"MM/dd/yyyy";
static const NSString* kRKModelMapperMappingFormatParserKey = @"RKMappingFormatParser";

@interface RKObjectMapper (Private)

- (id)parseString:(NSString*)string;
- (void)updateModel:(id)model fromElements:(NSDictionary*)elements;

- (NSDictionary*)typeClassForProperty:(NSString*)property ofClass:(Class)class;
- (NSDictionary*)elementToPropertyMappingsForModel:(id)model;

- (id)findOrCreateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements;
- (id)createOrUpdateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements;

- (void)updateModel:(id)model ifNewPropertyValue:(id)propertyValue forPropertyNamed:(NSString*)propertyName; // Rename!
- (void)setPropertiesOfModel:(id)model fromElements:(NSDictionary*)elements;
- (void)setRelationshipsOfModel:(id)object fromElements:(NSDictionary*)elements;
- (void)updateModel:(id)model fromElements:(NSDictionary*)elements;

- (NSDate*)parseDateFromString:(NSString*)string;
- (NSDate*)dateInLocalTime:(NSDate*)date;

@end

@implementation RKObjectMapper

@synthesize format = _format;
@synthesize missingElementMappingPolicy = _missingElementMappingPolicy;
@synthesize remoteTimeZone = _remoteTimeZone;
@synthesize localTimeZone = _localTimeZone;
@synthesize errorsKeyPath = _errorsKeyPath;
@synthesize errorsConcatenationString = _errorsConcatenationString;
@synthesize inspector=_inspector;

- (NSArray*)dateFormats
{
	return [NSArray arrayWithArray:_dateFormats];
}


///////////////////////////////////////////////////////////////////////////////
// public

- (id)init {
	if ((self = [super init])) {
		_elementToClassMappings = [[NSMutableDictionary alloc] init];
		_format = RKMappingFormatJSON;
		_missingElementMappingPolicy = RKIgnoreMissingElementMappingPolicy;
		_inspector = [[RKObjectPropertyInspector alloc] init];
		_dateFormats = [[NSMutableArray alloc] initWithObjects:kRKModelMapperRailsDateTimeFormatString, kRKModelMapperRailsDateFormatString, nil];
		self.remoteTimeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		self.localTimeZone = [NSTimeZone localTimeZone];
		self.errorsKeyPath = @"errors";
		self.errorsConcatenationString = @", ";
	}
	return self;
}

- (void)dealloc {
	[_elementToClassMappings release];
	[_inspector release];
	[_dateFormats release];
	[_errorsKeyPath release];
	[_errorsConcatenationString release];
	[super dealloc];
}

- (void)addDateFormat:(NSString*)dateFormat;
{
	[_dateFormats insertObject:dateFormat atIndex:0];
}

- (void)registerClass:(Class<RKObjectMappable>)aClass forElementNamed:(NSString*)elementName {
	[_elementToClassMappings setObject:aClass forKey:elementName];
}

- (void)setFormat:(RKMappingFormat)format {
	if (format == RKMappingFormatXML) {
		[NSException raise:@"No XML parser is available" format:@"RestKit does not currently have XML support. Use JSON."];
	}
	_format = format;
}

///////////////////////////////////////////////////////////////////////////////
// Mapping from a string

- (id)parseString:(NSString*)string {
	NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
	NSObject<RKParser>* parser = [threadDictionary objectForKey:kRKModelMapperMappingFormatParserKey];
	if (!parser) {
		if (_format == RKMappingFormatJSON) {
			parser = [[RKJSONParser alloc] init];
			[threadDictionary setObject:parser forKey:kRKModelMapperMappingFormatParserKey];
			[parser release];
		}
	}
	
	id result = nil;
	@try {
		result = [parser objectFromString:string];
	}
	@catch (NSException* e) {
		NSLog(@"[RestKit] RKObjectMapper:parseString: Exception (%@) parsing error from string: %@", [e reason], string);
	}
	return result;
}

- (NSError*)parseErrorFromString:(NSString*)string {
	NSString* errorMessage = [[[self parseString:string] valueForKeyPath:_errorsKeyPath] componentsJoinedByString:_errorsConcatenationString];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  errorMessage, NSLocalizedDescriptionKey,
							  nil];
	NSError *error = [NSError errorWithDomain:RKRestKitErrorDomain code:RKObjectLoaderRemoteSystemError userInfo:userInfo];
	
	return error;
}

// Primary entry point for RKObjectLoader
- (id)mapFromString:(NSString*)string toClass:(Class)class keyPath:(NSString*)keyPath {
	id object = [self parseString:string];
	if (keyPath) {
		object = [object valueForKeyPath:keyPath];
	}
	
	if ([object isKindOfClass:[NSDictionary class]]) {
		if (class) {
			return [self mapObjectFromDictionary:(NSDictionary*)object toClass:class];
		} else {
			return [self mapObjectFromDictionary:(NSDictionary*)object];
		}
	} else if ([object isKindOfClass:[NSArray class]]) {
		if (class) {
			return [self mapObjectsFromArrayOfDictionaries:(NSArray*)object toClass:class];
		} else {
			return [self mapObjectsFromArrayOfDictionaries:(NSArray*)object];
		}
	} else if (nil == object) {
		NSLog(@"[RestKit] RKModelMapper: mapObject:fromString: attempted to map from a nil payload. Skipping...");
		return nil;
	} else {
		[NSException raise:@"Unable to map from requested string" 
					format:@"The object was deserialized into a %@. A dictionary or array of dictionaries was expected.", [object class]];
		return nil;
	}
}

- (id)mapFromString:(NSString*)string {
	return [self mapFromString:string toClass:nil keyPath:nil];
}

- (void)mapObject:(id)model fromString:(NSString*)string {
	id object = [self parseString:string];
	if ([object isKindOfClass:[NSDictionary class]]) {
		[self mapObject:model fromDictionary:object];
	} else if (nil == object) {
		NSLog(@"[RestKit] RKModelMapper: mapObject:fromString: attempted to map from a nil payload. Skipping...");
		return;
	} else {
		[NSException raise:@"Unable to map from requested string"
					format:@"The object was serialized into a %@. A dictionary of elements was expected. (Object: %@) [Payload: %@]", [object class], object, string];
	}
}

///////////////////////////////////////////////////////////////////////////////
// Mapping from objects

// TODO: Should accept RKObjectMappable instead of id...
- (void)mapObject:(id)model fromDictionary:(NSDictionary*)dictionary {
	Class class = [model class];
	
	NSArray* elementNames = [_elementToClassMappings allKeysForObject:class];
	if ([elementNames count] == 0) {
		if ([model conformsToProtocol:@protocol(RKObjectMappable)]) {
			[self updateModel:model fromElements:dictionary];
		} else {
			[NSException raise:@"Unable to map from requested dictionary"
						format:@"There was no mappable element found for objects of type %@", class];
		}
	} else {
		for (NSString* elementName in elementNames) {
			if ([[dictionary allKeys] containsObject:elementName]) {
				NSDictionary* elements = [dictionary objectForKey:elementName];
				[self updateModel:model fromElements:elements];
				return;
			}
		}
		// If the dictionary is not namespaced, attempt mapping its properties directly...
		[self updateModel:model fromElements:dictionary];
	}
}

- (id)mapObjectFromDictionary:(NSDictionary*)dictionary toClass:(Class)class {
	return [self createOrUpdateInstanceOfModelClass:class fromElements:dictionary];
}

- (id)mapObjectFromDictionary:(NSDictionary*)dictionary {
	// TODO: Makes assumptions about the structure of the JSON...
	NSString* elementName = [[dictionary allKeys] objectAtIndex:0];
	Class class = [_elementToClassMappings objectForKey:elementName];
	NSDictionary* elements = [dictionary objectForKey:elementName];
	
	id model = [self findOrCreateInstanceOfModelClass:class fromElements:elements];
	[self updateModel:model fromElements:elements];
	return model;
}

- (NSArray*)mapObjectsFromArrayOfDictionaries:(NSArray*)array {
	NSMutableArray* objects = [NSMutableArray array];
	for (NSDictionary* dictionary in array) {
		if (![dictionary isKindOfClass:[NSNull class]]) {
			// TODO: Makes assumptions about the structure of the JSON...
			NSString* elementName = [[dictionary allKeys] objectAtIndex:0];
			Class class = [_elementToClassMappings objectForKey:elementName];
			NSAssert(class != nil, @"Unable to perform object mapping without a destination class");
			NSDictionary* elements = [dictionary objectForKey:elementName];
			id object = [self createOrUpdateInstanceOfModelClass:class fromElements:elements];
			[objects addObject:object];
		}
	}
	
	return (NSArray*)objects;
}

- (NSArray*)mapObjectsFromArrayOfDictionaries:(NSArray*)array toClass:(Class)class {
	NSMutableArray* objects = [NSMutableArray array];
	for (NSDictionary* dictionary in array) {
		if (![dictionary isKindOfClass:[NSNull class]]) {
			id object = [self createOrUpdateInstanceOfModelClass:class fromElements:dictionary];
			[objects addObject:object];
		}
	}
	
	return (NSArray*)objects;
}

///////////////////////////////////////////////////////////////////////////////
// Utility Methods

- (NSDictionary*)typeClassForProperty:(NSString*)property ofClass:(Class)class {
	return [[_inspector propertyNamesAndTypesForClass:class] objectForKey:property];
}

- (NSDictionary*)elementToPropertyMappingsForModel:(id)model {
	return [[model class] elementToPropertyMappings];
}

///////////////////////////////////////////////////////////////////////////////
// Persistent Instance Finders

// TODO: This version does not update properties. Should probably be realigned.
- (id)findOrCreateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements {
	id object = nil;
	if ([class isSubclassOfClass:[RKManagedObject class]]) {
		NSString* primaryKeyElement = [class performSelector:@selector(primaryKeyElement)];
		id primaryKeyValue = [elements objectForKey:primaryKeyElement];
		object = [[[RKObjectManager sharedManager] objectStore] findOrCreateInstanceOfManagedObject:class
																				withPrimaryKeyValue:primaryKeyValue];
	}
	// instantiate if object is nil
	if (object == nil) {
		if ([class conformsToProtocol:@protocol(RKObjectMappable)] && [class respondsToSelector:@selector(object)]) {
			object = [class object];
		} else {
			// Allow non-RKObjectMappable objecs to pass through to alloc/init. Do we need this?
			object = [[[class alloc] init] autorelease];
		}
	}
	
	return object;
}

- (id)createOrUpdateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements {
	id model = [self findOrCreateInstanceOfModelClass:class fromElements:elements];
	[self updateModel:model fromElements:elements];
	return model;
}

///////////////////////////////////////////////////////////////////////////////
// Property & Relationship Manipulation

- (void)updateModel:(id)model ifNewPropertyValue:(id)propertyValue forPropertyNamed:(NSString*)propertyName {	
	id currentValue = [model valueForKeyPath:propertyName];
	if (nil == currentValue && nil == propertyValue) {
		// Don't set the property, both are nil
	} else if (nil == propertyValue || [propertyValue isKindOfClass:[NSNull class]]) {
		// Clear out the value to reset it
		[model setValue:nil forKeyPath:propertyName];
	} else if (currentValue == nil || [currentValue isKindOfClass:[NSNull class]]) {
		// Existing value was nil, just set the property and be happy
		[model setValue:propertyValue forKeyPath:propertyName];
	} else {
		SEL comparisonSelector;
		if ([propertyValue isKindOfClass:[NSString class]]) {
			comparisonSelector = @selector(isEqualToString:);
		} else if ([propertyValue isKindOfClass:[NSNumber class]]) {
			comparisonSelector = @selector(isEqualToNumber:);
		} else if ([propertyValue isKindOfClass:[NSDate class]]) {
			comparisonSelector = @selector(isEqualToDate:);
		} else if ([propertyValue isKindOfClass:[NSArray class]]) {
			comparisonSelector = @selector(isEqualToArray:);
		} else if ([propertyValue isKindOfClass:[NSDictionary class]]) {
			comparisonSelector = @selector(isEqualToDictionary:);
		} else if ([propertyValue isKindOfClass:[NSURL class]]) {
			comparisonSelector = @selector(isEqualToUrl:);
		} else {
			[NSException raise:@"NoComparisonSelectorFound" format:@"You need a comparison selector for %@ (%@)", propertyName, [propertyValue class]];
		}
		
		// Comparison magic using function pointers. See this page for details: http://www.red-sweater.com/blog/320/abusing-objective-c-with-class
		// Original code courtesy of Greg Parker
		// This is necessary because isEqualToNumber will return negative integer values that aren't coercable directly to BOOL's without help [sbw]
		BOOL (*ComparisonSender)(id, SEL, id) = (BOOL (*)(id, SEL, id)) objc_msgSend;		
		BOOL areEqual = NO;
		if([currentValue respondsToSelector:comparisonSelector] && [propertyName respondsToSelector:comparisonSelector])
			areEqual = ComparisonSender(currentValue, comparisonSelector, propertyValue);
		
		if (NO == areEqual) {
			[model setValue:propertyValue forKeyPath:propertyName];
		}
	}
}

- (NSDictionary*)getPropertyTypeOfPropertyName:(NSString*)propertyName onModelClass:(Class)class
{
	NSArray* path = [propertyName componentsSeparatedByString:@"."];
	Class _class = class;
	int i = 0;
	NSDictionary* result = nil;
	do
	{
		// get name
		NSString* _propertyName = [path objectAtIndex:i];
		// get type dictionary
		result = [self typeClassForProperty:_propertyName ofClass:_class];
		// get property class
		_class = [result objectForKey:@"class"];
		i++;
	} while (i < [path count]);
	
	return result;
}

- (id)convertValue:(id)value forClass:(Class)class
{
	id result = value;
	if ([class isEqual:[NSDate class]])
	{
		// seems is bug: when date in ISO 8601 then we don't need convert time to local time zone, because time have +0000
//		NSDate* date = [self parseDateFromString:(propertyValue)];
//		propertyValue = [self dateInLocalTime:date];
		
		result = [self parseDateFromString:value];
	}
	else if([class isEqual:[NSURL class]] && value)
		result = [NSURL URLWithString:value];
	else if([class isEqual:[NSString class]] && ([[value class] isEqual:[NSNumber class]] || [[value class] isSubclassOfClass:[NSNumber class]]))
		result = [value stringValue];
	
	if([result class] != class && ![[result class] isSubclassOfClass:class] && ![class isSubclassOfClass:[result class]])
		return nil;
	
	return result;
}

- (void)setPropertiesOfModel:(id)model fromElements:(NSDictionary*)elements
{
	NSDictionary* elementToPropertyMappings = [self elementToPropertyMappingsForModel:model];
	for (NSString* elementKeyPath in elementToPropertyMappings)
	{		
		id elementValue = nil;		
		BOOL setValue = YES;
		
		@try
		{
			elementValue = [elements valueForKeyPath:elementKeyPath];
		}
		@catch (NSException* e)
		{
			NSLog(@"[RestKit] RKModelMapper: Unable to find element at keyPath %@ in elements dictionary for %@. Skipping...", elementKeyPath, [model class]);
			setValue = NO;
		}
		
		// TODO: Need a way to differentiate between a keyPath that exists, but contains a nil
		// value and one that is not present in the payload. Causes annoying problems!
		if(nil == elementValue)
			setValue = (_missingElementMappingPolicy == RKSetNilForMissingElementMappingPolicy);
		
		if (setValue)
		{
			id propertyValue = elementValue;
			NSString* propertyName = [elementToPropertyMappings objectForKey:elementKeyPath];
			NSDictionary* dic = [self getPropertyTypeOfPropertyName:propertyName onModelClass:[model class]];
			RKPropertyType pType = (RKPropertyType)[[dic objectForKey:@"type"] integerValue];
			if(pType == RKPropertyTypeClass)
			{
				Class class = [dic objectForKey:@"class"];
				if (elementValue != (id)kCFNull && nil != elementValue)
					propertyValue = [self convertValue:propertyValue forClass:class];
			}
			else if([propertyValue isKindOfClass:[NSString class]])
			{
				switch(pType)
				{
					case RKPropertyTypeBool:
					case RKPropertyTypeChar:
					case RKPropertyTypeUChar:
					case RKPropertyTypeShort:
					case RKPropertyTypeUShort:
					case RKPropertyTypeInt:
					case RKPropertyTypeUInt:
						propertyValue = [NSNumber numberWithInt:[propertyValue intValue]];
						break;
					case RKPropertyTypeLong:
					case RKPropertyTypeULong:
					case RKPropertyTypeLongLong:
					case RKPropertyTypeULongLong:
						propertyValue = [NSNumber numberWithLongLong:[propertyValue longLongValue]];
						break;
					case RKPropertyTypeFloat:
						propertyValue = [NSNumber numberWithFloat:[propertyValue floatValue]];
						break;
					case RKPropertyTypeDouble:
						propertyValue = [NSNumber numberWithFloat:[propertyValue doubleValue]];
						break;
					default:
						break;
				}
			}
			else if([propertyValue isKindOfClass:[NSNull class]])
			{
				switch(pType)
				{
					case RKPropertyTypeBool:
					case RKPropertyTypeChar:
					case RKPropertyTypeUChar:
					case RKPropertyTypeShort:
					case RKPropertyTypeUShort:
					case RKPropertyTypeInt:
					case RKPropertyTypeUInt:
					case RKPropertyTypeLong:
					case RKPropertyTypeULong:
					case RKPropertyTypeLongLong:
					case RKPropertyTypeULongLong:
					case RKPropertyTypeFloat:
					case RKPropertyTypeDouble:
						propertyValue = [NSNumber numberWithInt:0];
						break;
					default:
						break;
				}
			}
			
			[self updateModel:model ifNewPropertyValue:propertyValue forPropertyNamed:propertyName];
		}
	}
}

- (void)setRelationshipsOfModel:(id)object fromElements:(NSDictionary*)elements {
	NSDictionary* elementToRelationshipMappings = [[object class] elementToRelationshipMappings];
	for (NSString* elementKeyPath in elementToRelationshipMappings) {
		NSString* propertyName = [elementToRelationshipMappings objectForKey:elementKeyPath];
		
		id relationshipElements = nil;
		@try {
			relationshipElements = [elements valueForKeyPath:elementKeyPath];
		}
		@catch (NSException* e) {
			NSLog(@"Caught exception:%@ when trying valueForKeyPath with path:%@ for elements:%@", e, elementKeyPath, elements);
		}
		
		// TODO: Need to send NSSet or NSArray depending on what the property type is...
		NSDictionary* dic = [self typeClassForProperty:propertyName ofClass:[object class]];
		RKPropertyType pType = (RKPropertyType)[[dic objectForKey:@"type"] integerValue];
		if(pType == RKPropertyTypeClass)
		{
			Class collectionClass = [dic objectForKey:@"class"];
			if ([collectionClass isSubclassOfClass:[NSSet class]] || [collectionClass isSubclassOfClass:[NSArray class]]) {
				// NOTE: The last part of the keyPath contains the elementName for the mapped destination class of our children
				NSArray* componentsOfKeyPath = [elementKeyPath componentsSeparatedByString:@"."];
				Class class = [[[object class] classesForRelationshipMappings] objectForKey:[componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1]];
				if(!class)
					class = [_elementToClassMappings objectForKey:[componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1]];
				id children = nil;
				if ([collectionClass isSubclassOfClass:[NSSet class]]) {
					children = [NSMutableSet setWithCapacity:[relationshipElements count]];
				} else if ([collectionClass isSubclassOfClass:[NSArray class]]) {
					children = [NSMutableArray arrayWithCapacity:[relationshipElements count]];
				}
				
				for (id childElements in relationshipElements) {	
					id child = nil;	
					if([class conformsToProtocol:@protocol(RKObjectMappable)] && [childElements isKindOfClass:[NSDictionary class]])
						child = [self createOrUpdateInstanceOfModelClass:class fromElements:childElements];
					else
						child = [self convertValue:childElements forClass:class];
					if (child) {
						[(NSMutableArray*)children addObject:child];
					}
				}
				
				[object setValue:children forKey:propertyName];
			} else if ([relationshipElements isKindOfClass:[NSDictionary class]]) {
				NSArray* componentsOfKeyPath = [elementKeyPath componentsSeparatedByString:@"."];
				Class class = [[[object class] classesForRelationshipMappings] objectForKey:[componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1]];
				if(!class)
					class = [_elementToClassMappings objectForKey:[componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1]];
				id child = [object valueForKeyPath:propertyName];
				if(!child)
					child = [self createOrUpdateInstanceOfModelClass:class fromElements:relationshipElements];
				else
					[self mapObject:child fromDictionary:relationshipElements];
				[object setValue:child forKey:propertyName];
			}
		}
	}
	
	if ([object isKindOfClass:[RKManagedObject class]]) {
		RKManagedObject* managedObject = (RKManagedObject*)object;
		NSDictionary* relationshipToPkPropertyMappings = [[managedObject class] relationshipToPrimaryKeyPropertyMappings];
		for (NSString* relationship in relationshipToPkPropertyMappings) {
			NSString* primaryKeyPropertyString = [relationshipToPkPropertyMappings objectForKey:relationship];
			
			NSNumber* objectPrimaryKeyValue = nil;
			@try {
				objectPrimaryKeyValue = [managedObject valueForKeyPath:primaryKeyPropertyString];
			} @catch (NSException* e) {
				NSLog(@"Caught exception:%@ when trying valueForKeyPath with path:%@ for object:%@", e, primaryKeyPropertyString, managedObject);
			}
			
			NSDictionary* relationshipsByName = [[managedObject entity] relationshipsByName];
			NSEntityDescription* relationshipDestinationEntity = [[relationshipsByName objectForKey:relationship] destinationEntity];
			id relationshipDestinationClass = objc_getClass([[relationshipDestinationEntity managedObjectClassName] cStringUsingEncoding:NSUTF8StringEncoding]);
			RKManagedObject* relationshipValue = [[[RKObjectManager sharedManager] objectStore] findOrCreateInstanceOfManagedObject:relationshipDestinationClass
																												withPrimaryKeyValue:objectPrimaryKeyValue];			
			if (relationshipValue) {
				[managedObject setValue:relationshipValue forKey:relationship];
			}
		}
	}
}

- (void)updateModel:(id)model fromElements:(NSDictionary*)elements {
	[model before];
	[self setPropertiesOfModel:model fromElements:elements];
	[self setRelationshipsOfModel:model fromElements:elements];
	[model after];
}

///////////////////////////////////////////////////////////////////////////////
// Date & Time Helpers

- (NSDate*)parseDateFromString:(NSString*)string {
	NSDate* date = nil;
	if([string isKindOfClass:[NSString class]])
	{
		NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
		// TODO: I changed this to local time and it fixes my date issues. wtf?
		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		for (NSString* formatString in self.dateFormats) {
			[formatter setTimeZone:[NSTimeZone localTimeZone]];
			[formatter setDateFormat:formatString];
			date = [formatter dateFromString:string];
			if (date) {
				break;
			}
		}
		
		[formatter release];
		
		if(!date) // try to detect unix timestamp
		{
			NSString* str1 = [string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789."]];
			if([str1 length] == 0) // string contains just digits and '.'
				date = [NSDate dateWithTimeIntervalSince1970:[(NSNumber*)string doubleValue]];
		}
	}
	else if([string isKindOfClass:[NSNumber class]])
		date = [NSDate dateWithTimeIntervalSince1970:[(NSNumber*)string doubleValue]];
	
	return date;
}

- (NSString*)stringfromDate:(NSDate*)date {
	NSString* result = nil;
	NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	// TODO: I changed this to local time and it fixes my date issues. wtf?
	[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	for (NSString* formatString in self.dateFormats) {
		[formatter setDateFormat:formatString];
		result = [formatter stringFromDate:date];
		if([result length])
			break;
	}
	
	[formatter release];
	return result;
}

- (NSDate*)dateInLocalTime:(NSDate*)date {
	NSDate* destinationDate = nil;
	if (date) {
		NSInteger remoteGMTOffset = [self.remoteTimeZone secondsFromGMTForDate:date];
		NSInteger localGMTOffset = [self.localTimeZone secondsFromGMTForDate:date];
		NSTimeInterval interval = localGMTOffset - remoteGMTOffset;		
		destinationDate = [[[NSDate alloc] initWithTimeInterval:interval sinceDate:date] autorelease];
	}	
	return destinationDate;
}

@end
