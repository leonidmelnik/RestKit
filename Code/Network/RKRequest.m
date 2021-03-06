//
//  RKRequest.m
//  RestKit
//
//  Created by Jeremy Ellison on 7/27/09.
//  Copyright 2009 Two Toasters. All rights reserved.
//

#import "RKRequest.h"
#import "RKRequestQueue.h"
#import "RKResponse.h"
#import "NSDictionary+RKRequestSerialization.h"
#import "NSString+RKRequestSerialization.h"
#import "RKNotifications.h"
#import "RKClient.h"
#import "../Support/Support.h"
#import "RKURL.h"
#import <UIKit/UIKit.h>

@implementation RKRequest

@synthesize URL = _URL, URLRequest = _URLRequest, delegate = _delegate, additionalHTTPHeaders = _additionalHTTPHeaders,
			params = _params, userData = _userData, username = _username, password = _password, method = _method, logRequest, successHandler, failHandler, headersReceiver;

+ (RKRequest*)requestWithURL:(NSURL*)URL delegate:(id)delegate client:(RKClient*)client {
	return [[[RKRequest alloc] initWithURL:URL delegate:delegate client:client] autorelease];
}

- (id)initWithURL:(NSURL*)URL {
	if (self = [self init]) {
		self.logRequest = YES;
		_URL = [URL retain];
		_URLRequest = [[NSMutableURLRequest alloc] initWithURL:_URL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
		_connection = nil;
		_isLoading = NO;
		_isLoaded = NO;
		
		NSArray* cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:_URL];
		[_URLRequest setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];
	}
	return self;
}

- (id)initWithURL:(NSURL*)URL delegate:(id)delegate client:(RKClient*)client {
	if (self = [self initWithURL:URL]) {
		_delegate = delegate;
		self.client = client;
	}
	return self;
}

- (void)dealloc {
	self.delegate = nil;
	[_connection cancel];
	[_connection release];
	_connection = nil;
	[_userData release];
	_userData = nil;
	[_URL release];
	_URL = nil;
	[_URLRequest release];
	_URLRequest = nil;
	[_params release];
	_params = nil;
	[_additionalHTTPHeaders release];
	_additionalHTTPHeaders = nil;
	[_username release];
	_username = nil;
	[_password release];
	_password = nil;
	
	self.successHandler = nil;
	self.failHandler = nil;
	self.resourseUrl = nil;
	
	[super dealloc];
}

- (void)setRequestBody {
	if (_params) {
		// Prefer the use of a stream over a raw body
		if ([_params respondsToSelector:@selector(HTTPBodyStream)]) {
			[_URLRequest setHTTPBodyStream:[_params HTTPBodyStream]];
		} else {
			[_URLRequest setHTTPBody:[_params HTTPBody:self.client.bodyType]];
		}
	}
}

- (void)addHeadersToRequest {
	NSString* header;
	for (header in _additionalHTTPHeaders) {
		[_URLRequest setValue:[_additionalHTTPHeaders valueForKey:header] forHTTPHeaderField:header];
	}

	if (_params != nil) {
		// Temporarily support older RKRequestSerializable implementations
		if ([_params respondsToSelector:@selector(HTTPHeaderValueForContentType)]) {
			[_URLRequest setValue:[_params HTTPHeaderValueForContentType] forHTTPHeaderField:@"Content-Type"];
		} else if ([_params respondsToSelector:@selector(ContentTypeHTTPHeader)]) {
			[_URLRequest setValue:[_params performSelector:@selector(ContentTypeHTTPHeader)] forHTTPHeaderField:@"Content-Type"];
		}
		if ([_params respondsToSelector:@selector(HTTPHeaderValueForContentLength)]) {
			[_URLRequest setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[_params HTTPHeaderValueForContentLength]] forHTTPHeaderField:@"Content-Length"];
		}
	}
	
#if !TARGET_OS_WATCH
	if (_username != nil) {
		// Add authentication headers so we don't have to deal with an extra cycle for each message requiring basic auth.
		CFHTTPMessageRef dummyRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, (CFStringRef)[self HTTPMethod], (CFURLRef)[self URL], kCFHTTPVersion1_1);
		CFHTTPMessageAddAuthentication(dummyRequest, nil, (CFStringRef)_username, (CFStringRef)_password, kCFHTTPAuthenticationSchemeBasic, FALSE);
		CFStringRef authorizationString = CFHTTPMessageCopyHeaderFieldValue(dummyRequest, CFSTR("Authorization"));

		[_URLRequest setValue:(NSString *)authorizationString forHTTPHeaderField:@"Authorization"];

		CFRelease(dummyRequest);
		CFRelease(authorizationString);
	}
#endif
//	if(logRequest)
//		NSLog(@"Headers: %@", [_URLRequest allHTTPHeaderFields]);
}

// Setup the NSURLRequest. The request must be prepared right before dispatching
- (void)prepareURLRequest {
	[_URLRequest setHTTPMethod:[self HTTPMethod]];
	[self setRequestBody];
	[self addHeadersToRequest];
}

- (NSString*)HTTPMethod {
	switch (_method) {
		case RKRequestMethodGET:
			return @"GET";
			break;
		case RKRequestMethodPOST:
			return @"POST";
			break;
		case RKRequestMethodPUT:
			return @"PUT";
			break;
		case RKRequestMethodDELETE:
			return @"DELETE";
			break;
		default:
			return nil;
			break;
	}
}

- (void)send {
	[[RKRequestQueue sharedQueue] sendRequest:self];
}

- (void)fireAsynchronousRequest {
	if ([[RKClient sharedClient] isNetworkAvailable]) {
		[self prepareURLRequest];
		NSString* body = [[NSString alloc] initWithData:[_URLRequest HTTPBody] encoding:NSUTF8StringEncoding];
		if(logRequest)
			NSLog(@"Sending %@ request to URL %@. HTTP Body: %@", [self HTTPMethod], [[[self URLRequest] URL] absoluteString], body);
		[body release];
		NSDate* sentAt = [NSDate date];
		NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[self HTTPMethod], @"HTTPMethod", [self URL], @"URL", sentAt, @"sentAt", nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:kRKRequestSentNotification object:self userInfo:userInfo];

		_isLoading = YES;
		NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:_URLRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response_, NSError * _Nullable error_) {
			
			RKResponse* response = [[[RKResponse alloc] initWithSynchronousRequest:self URLResponse:response_ body:data error:error_] autorelease];
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[self didFinishLoad:response];
			});
			
		}];
		[task resume];
	} else {
		NSString* errorMessage = [NSString stringWithFormat:@"The client is unable to contact the resource at %@", [[self URL] absoluteString]];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  errorMessage, NSLocalizedDescriptionKey,
								  nil];
		NSError* error = [NSError errorWithDomain:RKRestKitErrorDomain code:RKRequestBaseURLOfflineError userInfo:userInfo];
		[self performSelector:@selector(didFailLoadWithError:) withObject:error afterDelay:0.01];
		_isLoaded = YES;
	}
}

- (void)cancel {
	[_connection cancel];
	[_connection release];
	_connection = nil;
	_isLoading = NO;
}

- (void)disable
{
	self.successHandler = nil;
	self.failHandler = nil;
	[self setDelegate:nil];
	
	[[RKRequestQueue sharedQueue] cancelRequest:self];
}

- (void)didFailLoadWithError:(NSError*)error {
	_isLoading = NO;

	if ([_delegate respondsToSelector:@selector(request:didFailLoadWithError:)]) {
		[_delegate request:self didFailLoadWithError:error];
	}
	if(self.failHandler)
		self.failHandler(self, error);

	NSDate* receivedAt = [NSDate date];
	NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[self HTTPMethod], @"HTTPMethod",
							  [self URL], @"URL", receivedAt, @"receivedAt", error, @"error", nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:kRKRequestFailedWithErrorNotification object:self userInfo:userInfo];
}

- (void)didFinishLoad:(RKResponse*)response {
	_isLoading = NO;
	_isLoaded = YES;
	
	[self.headersReceiver headersDidReceive:[response allHeaderFields]];

	if ([_delegate respondsToSelector:@selector(request:didLoadResponse:)]) {
		[_delegate request:self didLoadResponse:response];
	}
	if(self.successHandler)
		self.successHandler(self, response);

	NSDate* receivedAt = [NSDate date];
	NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[self HTTPMethod], @"HTTPMethod", [self URL], @"URL", receivedAt, @"receivedAt", nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:kRKResponseReceivedNotification object:response userInfo:userInfo];

#if !TARGET_OS_WATCH
	if ([response isServiceUnavailable] && [[RKClient sharedClient] serviceUnavailableAlertEnabled]) {
		UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:[[RKClient sharedClient] serviceUnavailableAlertTitle]
															message:[[RKClient sharedClient] serviceUnavailableAlertMessage]
														   delegate:nil
												  cancelButtonTitle:NSLocalizedString(@"OK", nil)
												  otherButtonTitles:nil];
		[alertView show];
		[alertView release];
	}
#endif
}

- (void)request:(RKRequest*)request didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
	if ([self.delegate respondsToSelector:@selector(request:didSendBodyData:totalBytesWritten:totalBytesExpectedToWrite:)])
		[self.delegate request:self didSendBodyData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
	if(self.progressHandler)
		self.progressHandler(self, totalBytesWritten, totalBytesExpectedToWrite);
}

- (BOOL)isGET {
	return _method == RKRequestMethodGET;
}

- (BOOL)isPOST {
	return _method == RKRequestMethodPOST;
}

- (BOOL)isPUT {
	return _method == RKRequestMethodPUT;
}

- (BOOL)isDELETE {
	return _method == RKRequestMethodDELETE;
}

- (BOOL)isLoading {
	return _isLoading;
}

- (BOOL)isLoaded {
	return _isLoaded;
}

- (NSString*)resourcePath {
	NSString* resourcePath = nil;
	if ([self.URL isKindOfClass:[RKURL class]]) {
		RKURL* url = (RKURL*)self.URL;
		resourcePath = url.resourcePath;
	}
	return resourcePath;
}

- (BOOL)wasSentToResourcePath:(NSString*)resourcePath {
	return [[self resourcePath] isEqualToString:resourcePath];
}

- (NSString*)description
{
	NSMutableString* result = [NSMutableString string];
	[result appendFormat:@"%@ request to URL %@", [self HTTPMethod], [self.URL absoluteString]];
	
	NSDictionary* headers = [self.URLRequest allHTTPHeaderFields];
	if([[headers allKeys] count])
		[result appendFormat:@"\nHeaders: %@", headers];
	
	NSString* body = [[NSString alloc] initWithData:[_URLRequest HTTPBody] encoding:NSUTF8StringEncoding];
	if([body length] && [body length] < 2048)
		[result appendFormat:@"\nBody:\n%@", body];
	[body release];
	
	return result;
}

@end
