//
//  RKReachabilityObserver.h
//  RestKit
//
//  Created by Blake Watters on 9/14/10.
//  Copyright 2010 RestKit. All rights reserved.
//

#import <Foundation/Foundation.h>
#if !TARGET_OS_WATCH
#import <SystemConfiguration/SystemConfiguration.h>
#endif

/**
 * Posted when the network state has changed
 */
extern NSString* const RKReachabilityStateChangedNotification;

typedef enum {
	RKReachabilityIndeterminate,
	RKReachabilityNotReachable,
	RKReachabilityReachableViaWiFi,
	RKReachabilityReachableViaWWAN
} RKReachabilityNetworkStatus;

/**
 * Provides a notification based interface for monitoring changes
 * to network status
 */
@interface RKReachabilityObserver : NSObject {
#if !TARGET_OS_WATCH
	SCNetworkReachabilityRef _reachabilityRef;	
#endif
}

@property (nonatomic, copy) NSString* hostName;

@property (nonatomic, assign) BOOL hasNetworkAvailabilityBeenDetermined;

/**
 * Create a new reachability observer against a given hostname. The observer
 * will monitor the ability to reach the specified hostname and emit notifications
 * when its reachability status changes. 
 *
 * Note that the observer will be scheduled in the current run loop.
 */
+ (RKReachabilityObserver*)reachabilityObserverWithHostName:(NSString*)hostName;

/**
 * Returns the current network status
 */
- (RKReachabilityNetworkStatus)networkStatus;

/**
 * Returns YES when the Internet is reachable (via WiFi or WWAN)
 */
- (BOOL)isNetworkReachable;

/**
 * Returns YES when WWAN may be available, but not active until a connection has been established.
 */
- (BOOL)isConnectionRequired;

@end
