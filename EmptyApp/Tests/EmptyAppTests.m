//
//  EmptyAppTests.m
//  Couchbase Mobile
//
//  Created by Jens Alfke on 7/8/11.
//  Copyright 2011 Couchbase, Inc. All rights reserved.
//

#import "EmptyAppTests.h"
#import <Couchbase/CouchbaseEmbeddedServer.h>

extern BOOL sUnitTesting;
extern CouchbaseEmbeddedServer* sCouchbase;  // Defined in EmptyAppDelegate.m

@implementation EmptyAppTests

- (void)setUp
{
    [super setUp];

    sUnitTesting = YES;
    STAssertNotNil(sCouchbase, nil);
    if (!sCouchbase.serverURL) {
        NSLog(@"Waiting for Couchbase server to start up...");
        NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
        while (!sCouchbase.serverURL && !sCouchbase.error && [timeout timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
        }

        NSLog(@"===== EmptyAppTests: Server URL = %@", sCouchbase.serverURL);
    }
    STAssertNil(sCouchbase.error, nil);
    STAssertNotNil(sCouchbase.serverURL, nil);

    [self forciblyDeleteDatabase];
}

- (void)tearDown
{
    [super tearDown];
}


- (NSURLRequest*)request: (NSString*)method path: (NSString*)relativePath body: (NSString*)body {
    NSURL* url = [NSURL URLWithString: relativePath relativeToURL: sCouchbase.serverURL];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    if (body) {
        request.HTTPBody = [body dataUsingEncoding: NSUTF8StringEncoding];
        [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    }
    return request;
}


- (NSString*)send: (NSString*)method toPath: (NSString*)relativePath body: (NSString*)body {
    NSLog(@"%@ %@", method, relativePath);
    NSURLRequest* request = [self request:method path:relativePath body:body];
    NSURLResponse* response = nil;
    NSError* error = nil;
    
    // This is for testing only! In a real app you would not want to send URL requests synchronously.
    NSData* responseBody = [NSURLConnection sendSynchronousRequest: request
                                                 returningResponse: &response
                                                             error: &error];
    STAssertTrue(responseBody != nil && response != nil,
             @"Request to <%@> failed: %@", request.URL.absoluteString, error);
    int statusCode = ((NSHTTPURLResponse*)response).statusCode;
    STAssertTrue(statusCode < 300,
             @"Request to <%@> failed: HTTP error %i", request.URL.absoluteString, statusCode);
    
    NSString* responseStr = [[NSString alloc] initWithData: responseBody
                                                  encoding: NSUTF8StringEncoding];
    NSLog(@"Response (%d):\n%@", statusCode, responseStr);
    return [responseStr autorelease];
}


- (void)forciblyDeleteDatabase {
    // No error checking, since this may return a 404
    [NSURLConnection sendSynchronousRequest: [self request:@"DELETE" path:@"/unittestdb" body:nil]
                          returningResponse: NULL
                                      error: NULL];
}


- (void)testBasicOps
{
    [self send: @"GET" toPath: @"/" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"GET" toPath: @"/unittestdb" body: nil];
    [self send: @"POST" toPath: @"/unittestdb/" body: @"{\"txt\":\"foobar\"}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"txt\":\"O HAI\"}"];
    [self send: @"GET" toPath: @"/unittestdb/doc1" body: nil];
}

@end
