//
//  EmptyAppDelegate.m
//  Couchbase Empty App
//
//  Created by Jens Alfke on 7/8/11.
//  Copyright 2011 CouchBase, Inc. All rights reserved.
//

#import "EmptyAppDelegate.h"
#import <SenTestingKit/SenTestingKit.h>
#import <ifaddrs.h>
#import <netinet/in.h>
#import <net/if.h>


@implementation EmptyAppDelegate


BOOL sUnitTesting;
CouchbaseMobile* sCouchbase;  // Used by the unit tests


@synthesize window = _window;
@synthesize serverURL = _serverURL;


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    NSLog(@"------ Empty App: application:didFinishLaunchingWithOptions:");
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self.window makeKeyAndVisible];
    
    // Initialize CouchDB:
    CouchbaseMobile* cb = [[CouchbaseMobile alloc] init];
    cb.delegate = self;
    NSString* iniPath = [[NSBundle mainBundle] pathForResource: @"app" ofType: @"ini"];
    if (iniPath) {
        NSLog(@"Registering custom .ini file %@", iniPath);
        cb.iniFilePath = iniPath;
    }
    NSAssert([cb start], @"Couchbase couldn't start! Error = %@", cb.error);
    sCouchbase = cb;
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    NSLog(@"------ Empty App: applicationWillResignActive");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"------ Empty App: applicationDidEnterBackground");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    NSLog(@"------ Empty App: applicationWillEnterForeground");
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    NSLog(@"------ Empty App: applicationDidBecomeActive");
}

- (void)applicationWillTerminate:(UIApplication *)application {
    NSLog(@"------ Empty App: applicationWillTerminate");
}


-(void)couchbaseMobile:(CouchbaseMobile*)couchbase didStart:(NSURL*)serverURL {
	NSLog(@"CouchDB is Ready, go!");
    NSLog(@"My local IP address is %@", self.localIPAddress);
    self.serverURL = serverURL;
    
    if (sUnitTesting)
        return;  // Unit tests have already started
    
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleID hasSuffix: @"Empty-App"]) {
        NSLog(@"*** EMPTYAPP IS NOW STARTING UNIT TESTS ***\n\n\n");
        SenTestSuite* tests = [SenTestSuite defaultTestSuite];
        SenTestRun* result = [tests run];
        if (!result.hasSucceeded) abort();
        exit(0);
    }
}


-(void)couchbaseMobile:(CouchbaseMobile*)couchbase failedToStart:(NSError*)error {
    NSAssert(NO, @"Couchbase failed to initialize: %@", error);
}


- (NSString*)localIPAddress {
    // getifaddrs returns a linked list of interface entries;
    // find the first active non-loopback interface with IPv4:
    UInt32 address = 0;
    struct ifaddrs *interfaces;
    if( getifaddrs(&interfaces) == 0 ) {
        struct ifaddrs *interface;
        for( interface=interfaces; interface; interface=interface->ifa_next ) {
            if( (interface->ifa_flags & IFF_UP) && ! (interface->ifa_flags & IFF_LOOPBACK) ) {
                const struct sockaddr_in *addr = (const struct sockaddr_in*) interface->ifa_addr;
                if( addr && addr->sin_family==AF_INET ) {
                    address = addr->sin_addr.s_addr;
                    break;
                }
            }
        }
        freeifaddrs(interfaces);
    }

    const UInt8* b = (const UInt8*)&address;
    return [NSString stringWithFormat: @"%u.%u.%u.%u",
            (unsigned)b[0],(unsigned)b[1],(unsigned)b[2],(unsigned)b[3]];
}


@end
