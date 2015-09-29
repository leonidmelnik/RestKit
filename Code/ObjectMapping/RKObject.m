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

- (void)before
{
	
}

- (void)after
{
	
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
		{
			id obj = [aDecoder decodeObjectForKey:key];
			if(obj)
				[self setValue:obj forKey:[dic objectForKey:key]];
		}
		
		if([[self class] respondsToSelector:@selector(elementToRelationshipMappings)])
			for(NSString* key in [[[self class] elementToRelationshipMappings] allKeys])
				if([[[[self class] classesForRelationshipMappings] objectForKey:key] conformsToProtocol:@protocol(NSCoding)])
				{
					NSData* data = [aDecoder decodeObjectForKey:key];
					if(data)
					{
						id obj = [NSKeyedUnarchiver unarchiveObjectWithData:data];
						if(obj)
							[self setValue:obj forKey:[[[self class] elementToRelationshipMappings] objectForKey:key]];
					}
				}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	NSMutableDictionary* dic = [NSMutableDictionary dictionaryWithDictionary:[[self class] elementToPropertyMappings]];
	
	for(NSString* key in [dic allKeys])
	{
		NSString* _key = [dic objectForKey:key];
		if([_key length] && [self valueForKey:_key])
			[aCoder encodeObject:[self valueForKey:[dic objectForKey:key]] forKey:key];
	}
	
	if([[self class] respondsToSelector:@selector(elementToRelationshipMappings)])
	{
		NSArray* allKeys = [[[self class] elementToRelationshipMappings] allKeys];
		for(NSString* key in allKeys)
		{
			if([key length])
			{
				Class class = [[[self class] classesForRelationshipMappings] objectForKey:key];
				if([class conformsToProtocol:@protocol(NSCoding)])
				{
					NSString* _key = [[[self class] elementToRelationshipMappings] objectForKey:key];
					if([_key length] && [self valueForKey:_key])
						[aCoder encodeObject:[NSKeyedArchiver archivedDataWithRootObject:[self valueForKey:_key]] forKey:key];
				}
			}
		}
	}
}

#pragma mark -
#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
	RKObject* result = [[[self class] allocWithZone:zone] init];
	
	NSMutableDictionary* dic = [NSMutableDictionary dictionaryWithDictionary:[[self class] elementToPropertyMappings]];
	
	for(NSString* key in [dic allKeys])
	{
		NSString* _key = [dic objectForKey:key];
		if([_key length] && [[self valueForKey:_key] conformsToProtocol:@protocol(NSCopying)])
			[result setValue:[[[self valueForKey:_key] copy] autorelease] forKey:_key];
	}
	
	if([[self class] respondsToSelector:@selector(elementToRelationshipMappings)])
	{
		NSArray* allKeys = [[[self class] elementToRelationshipMappings] allKeys];
		for(NSString* key in allKeys)
		{
			if([key length])
			{
				NSString* _key = [[[self class] elementToRelationshipMappings] objectForKey:key];
				if([_key length] && [[self valueForKey:_key] conformsToProtocol:@protocol(NSCopying)])
					[result setValue:[[[self valueForKey:_key] copy] autorelease] forKey:_key];
			}
		}
	}
	
	return result;
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

- (void)mapFromDictionary:(NSDictionary*)dic
{
	[[[RKObjectManager sharedManager] mapper] mapObject:self fromDictionary:dic];
}

#pragma mark -
#pragma mark Properties copying

- (void)copyPropertiesFromObject:(RKObject*)object
{
	NSMutableDictionary* dic = [NSMutableDictionary dictionaryWithDictionary:[[self class] elementToPropertyMappings]];
	[dic addEntriesFromDictionary:[[self class] elementToRelationshipMappings]];
	NSString* _key;
	for(NSString* key in [dic allKeys])
	{
		_key = [dic objectForKey:key];
		id obj = [object valueForKey:_key];
		if(obj)
			[self setValue:obj forKey:_key];
	}
}

@end
