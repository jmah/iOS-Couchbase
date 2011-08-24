//
//  EmptyAppDelegate.m
//  Couchbase Empty App
//
//  Created by Jens Alfke on 7/8/11.
//  Copyright 2011 CouchBase, Inc. All rights reserved.
//

#import "EmptyAppDelegate.h"
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


// This is for testing only! In a real app you would not want to send URL requests synchronously.
- (void)send: (NSString*)method toPath: (NSString*)relativePath body: (NSString*)body {
    NSLog(@"%@ %@", method, relativePath);
    NSURL* url = [NSURL URLWithString: relativePath relativeToURL: self.serverURL];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    if (body) {
        request.HTTPBody = [body dataUsingEncoding: NSUTF8StringEncoding];
        [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    }
    NSURLResponse* response = nil;
    NSError* error = nil;
    
    NSData* responseBody = [NSURLConnection sendSynchronousRequest: request
                                         returningResponse: &response
                                                     error: &error];
    NSAssert(responseBody != nil && response != nil,
             @"Request to <%@> failed: %@", url.absoluteString, error);
    int statusCode = ((NSHTTPURLResponse*)response).statusCode;
    NSAssert(statusCode < 300,
             @"Request to <%@> failed: HTTP error %i", url.absoluteString, statusCode);
    
    NSString* responseStr = [[NSString alloc] initWithData: responseBody
                                                  encoding: NSUTF8StringEncoding];
    NSLog(@"Response (%d):\n%@", statusCode, responseStr);
    [responseStr release];
}


-(void)couchbaseMobile:(CouchbaseMobile*)couchbase didStart:(NSURL*)serverURL {
	NSLog(@"CouchDB is Ready, go!");
    NSLog(@"My local IP address is %@", self.localIPAddress);
    self.serverURL = serverURL;
    
    if (!sUnitTesting) {
        [self send: @"GET" toPath: @"/" body: nil];
        NSLog(@"Couchbase is alive! Run the unit tests to be sure everything works.");
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
