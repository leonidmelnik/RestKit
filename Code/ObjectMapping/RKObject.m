//
//  RKObject.m
//  RestKit
//
//  Created by Blake Watters on 7/20/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#import "RKObject.h"
#import "RKObjectManager.h"

@implementation RKObject

+ (NSDictionary*)elementToPropertyMappings {
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

+ (NSDictionary*)elementToRelationshipMappings {
	return [NSDictionary dictionary];
}

+ (NSDictionary*)classesForRelationshipMappings {
	return [NSDictionary dictionary];
}

+ (id)object {
	return [[self new] autorelease];
}

- (NSDictionary*)propertiesForSerialization {
	return RKObjectMappableGetPropertiesByElement(self);
}

#pragma mark -
#pragma mark NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if(self)
	{
		NSMutableDictionary* dic = [NSMutableDictionary dictionaryWithDictionary:[[self class] elementToPropertyMappings]];
		
		for(NSString* key in [dic allKeys])
			[self setValue:[aDecoder decodeObjectForKey:key] forKey:[dic objectForKey:key]];
		
		if([[self class] respondsToSelector:@selector(elementToRelationshipMappings)])
			for(NSString* key in [[[self class] elementToRelationshipMappings] allKeys])
				if([[[[self class] classesForRelationshipMappings] objectForKey:key] conformsToProtocol:@protocol(NSCoding)])
				{
					id obj = [NSKeyedUnarchiver unarchiveObjectWithData:[aDecoder decodeObjectForKey:key]];
					if(obj)
						[self setValue:obj forKey:[[[self class] elementToRelationshipMappings] objectForKey:key]];
				}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	NSMutableDictionary* dic = [NSMutableDictionary dictionaryWithDictionary:[[self class] elementToPropertyMappings]];
	
	for(NSString* key in [dic allKeys])
		if([self valueForKey:[dic objectForKey:key]])
			[aCoder encodeObject:[self valueForKey:[dic objectForKey:key]] forKey:key];
	
	if([[self class] respondsToSelector:@selector(elementToRelationshipMappings)])
		for(NSString* key in [[[self class] elementToRelationshipMappings] allKeys])
			if([[[[self class] classesForRelationshipMappings] objectForKey:key] conformsToProtocol:@protocol(NSCoding)])
				if([self valueForKey:[[[self class] elementToRelationshipMappings] objectForKey:key]])
					[aCoder encodeObject:[NSKeyedArchiver archivedDataWithRootObject:[self valueForKey:[[[self class] elementToRelationshipMappings] objectForKey:key]]] forKey:key];
}

#pragma mark -
#pragma mark Methods

+ (id)objectFromResponse:(RKResponse*)response
{
	return [self objectFromJsonString:[response bodyAsString]];
}

+ (id)objectFromJsonString:(NSString*)json
{
	return [[[RKObjectManager sharedManager] mapper] mapFromString:json toClass:self keyPath:nil];
}

+ (id)objectFromDictionary:(NSDictionary*)dic
{
	return [[[RKObjectManager sharedManager] mapper] mapObjectFromDictionary:dic toClass:self];
}

+ (NSArray*)arrayOfObjectsFromDictionaries:(NSArray*)dictionaries
{
	NSMutableArray* result = [NSMutableArray array];
	for(NSDictionary* dic in dictionaries)
		[result addObject:[self objectFromDictionary:dic]];
	return [NSArray arrayWithArray:result];
}

@end
