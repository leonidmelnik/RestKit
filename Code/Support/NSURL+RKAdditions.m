//
//  NSURL+RKAdditions.m
//  RestKit
//
//  Created by Leonid on 24.03.15.
//  Copyright (c) 2015 Two Toasters. All rights reserved.
//

#import "NSURL+RKAdditions.h"

@implementation NSURL (RKAdditions)

- (BOOL)isEqualToUrl:(NSURL*)url
{
	return [[self absoluteString] isEqualToString:[url absoluteString]];
}

@end
