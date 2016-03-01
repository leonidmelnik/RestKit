//
//  NSString+RKRequestSerialization.m
//  RestKit
//
//  Created by Leonid on 01.03.16.
//  Copyright © 2016 Two Toasters. All rights reserved.
//

#import "NSString+RKRequestSerialization.h"

@implementation NSString (RKRequestSerialization)

- (NSString*)HTTPHeaderValueForContentType
{
	return @"application/x-www-form-urlencoded";
}

- (NSData*)HTTPBody:(RKBodyType)bodyType
{
	return [self dataUsingEncoding:NSUTF8StringEncoding];
}

@end
