//
//  EmptyAppTests.m
//  Couchbase Mobile
//
//  Created by Jens Alfke on 7/8/11.
//  Copyright 2011 Couchbase, Inc. All rights reserved.
//

#import "EmptyAppTests.h"
#import <Couchbase/CouchbaseMobile.h>
#import <Couchbase/CouchbaseCallbacks.h>

extern BOOL sUnitTesting;
extern CouchbaseMobile* sCouchbase;  // Defined in EmptyAppDelegate.m

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
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    if (body) {
        request.HTTPBody = [body dataUsingEncoding: NSUTF8StringEncoding];
        [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    }
    return request;
}


- (NSString*)send: (NSString*)method
           toPath: (NSString*)relativePath
             body: (NSString*)body
  responseHeaders: (NSDictionary**)outResponseHeaders
{
    NSLog(@"%@ %@", method, relativePath);
    NSURLRequest* request = [self request:method path:relativePath body:body];
    NSHTTPURLResponse* response = nil;
    NSError* error = nil;
    
    // This is for testing only! In a real app you would not want to send URL requests synchronously.
    NSData* responseBody = [NSURLConnection sendSynchronousRequest: request
                                                 returningResponse: (NSURLResponse**)&response
                                                             error: &error];
    STAssertTrue(responseBody != nil && response != nil,
             @"Request to <%@> failed: %@", request.URL.absoluteString, error);
    int statusCode = response.statusCode;
    STAssertTrue(statusCode < 300,
             @"Request to <%@> failed: HTTP error %i", request.URL.absoluteString, statusCode);
    
    if (outResponseHeaders)
        *outResponseHeaders = response.allHeaderFields;
    NSString* responseStr = [[NSString alloc] initWithData: responseBody
                                                  encoding: NSUTF8StringEncoding];
    NSLog(@"Response (%d):\n%@", statusCode, responseStr);
    return [responseStr autorelease];
}

- (NSString*)send: (NSString*)method
           toPath: (NSString*)relativePath
             body: (NSString*)body {
    return [self send:method toPath:relativePath body:body responseHeaders:NULL];
}


- (void)forciblyDeleteDatabase {
    // No error checking, since this may return a 404
    [NSURLConnection sendSynchronousRequest: [self request:@"DELETE" path:@"/unittestdb" body:nil]
                          returningResponse: NULL
                                      error: NULL];
}


- (void)test1_BasicOps
{
    [self send: @"GET" toPath: @"/" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"GET" toPath: @"/unittestdb" body: nil];
    [self send: @"POST" toPath: @"/unittestdb/" body: @"{\"txt\":\"foobar\"}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"txt\":\"O HAI\"}"];
    [self send: @"GET" toPath: @"/unittestdb/doc1" body: nil];
    [self send: @"DELETE" toPath: @"/unittestdb" body: nil];
}


- (void)test2_JSException
{
    // Make sure that if a JS exception is thrown by a view function, it doesn't crash Erlang.
    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"txt\":\"O HAI\"}"];
    [self send: @"PUT" toPath: @"/unittestdb/_design/exception"
          body: @"{\"views\":{\"oops\":{\"map\":\"function(){throw 'oops';}\"}}}"];
    [self send: @"GET" toPath: @"/unittestdb/_design/exception/_view/oops" body: nil];
    [self send: @"DELETE" toPath: @"/unittestdb" body: nil];
}


- (void)test3_UpdateViews {
    // Test that the ETag in a view response changes after the view contents change.
    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"txt\":\"O HAI\"}"];

    [self send: @"PUT" toPath: @"/unittestdb/_design/updateviews"
          body: @"{\"views\":{\"simple\":{\"map\":\"function(doc){emit(doc._id,null);}\"}}}"];

    NSDictionary* headers;
    [self send: @"GET" toPath: @"/unittestdb/_design/updateviews/_view/simple"
          body: nil responseHeaders: &headers];
    NSString* eTag = [headers objectForKey: @"Etag"];
    NSLog(@"ETag: %@", eTag);
    STAssertNotNil(eTag, nil);
    [self send: @"GET" toPath: @"/unittestdb/_design/updateviews/_view/simple"
          body: nil responseHeaders: &headers];
    NSLog(@"ETag: %@", [headers objectForKey: @"Etag"]);
    STAssertEqualObjects([headers objectForKey: @"Etag"], eTag, @"View eTag isn't stable");

    [self send: @"PUT" toPath: @"/unittestdb/doc2" body: @"{\"txt\":\"KTHXBYE\"}"];

    [self send: @"GET" toPath: @"/unittestdb/_design/updateviews/_view/simple"
          body: nil responseHeaders: &headers];
    NSLog(@"ETag: %@", [headers objectForKey: @"Etag"]);
    STAssertFalse([eTag isEqualToString: [headers objectForKey: @"Etag"]], @"View didn't update");
}


- (void)test3_BigNums {
    // Test that large integers in documents don't break JS views [Issue CBMI-34]
    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"n\":1234}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc2" body: @"{\"n\":1313684610751}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc3" body: @"{\"n\":1313684610751.1234}"];

    [self send: @"PUT" toPath: @"/unittestdb/_design/updateviews"
          body: @"{\"views\":{\"simple\":{\"map\":\"function(doc){emit(doc._id,null);}\"}}}"];

    NSDictionary* headers;
    NSString* result = [self send: @"GET" toPath: @"/unittestdb/_design/updateviews/_view/simple"
          body: nil responseHeaders: &headers];
    NSLog(@"Result of view = %@", result);
    STAssertEqualObjects(result, @"{\"total_rows\":3,\"offset\":0,\"rows\":[\r\n"
                                  "{\"id\":\"doc1\",\"key\":\"doc1\",\"value\":null},\r\n"
                                  "{\"id\":\"doc2\",\"key\":\"doc2\",\"value\":null},\r\n"
                                  "{\"id\":\"doc3\",\"key\":\"doc3\",\"value\":null}\r\n"
                                  "]}\n",
                         nil);
}


- (void)test4_Collation {
    // Test string collation order -- this is important because it's implemented in platform
    // specific code, couch_icu_driver.m.
    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"str\":\"a\"}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc2" body: @"{\"str\":\"A\"}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc3" body: @"{\"str\":\"aa\"}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc4" body: @"{\"str\":\"b\"}"];
    [self send: @"PUT" toPath: @"/unittestdb/doc5" body: @"{\"str\":\"B\"}"];

    [self send: @"PUT" toPath: @"/unittestdb/_design/collation"
          body: @"{\"views\":{\"simple\":{\"map\":\"function(doc){emit(doc.str,null);}\"}}}"];

    NSString* result = [self send: @"GET" toPath: @"/unittestdb/_design/collation/_view/simple"
                             body: nil responseHeaders: NULL];
    STAssertEqualObjects(result, @"{\"total_rows\":5,\"offset\":0,\"rows\":[\r\n"
                         "{\"id\":\"doc1\",\"key\":\"a\",\"value\":null},\r\n"
                         "{\"id\":\"doc2\",\"key\":\"A\",\"value\":null},\r\n"
                         "{\"id\":\"doc3\",\"key\":\"aa\",\"value\":null},\r\n"
                         "{\"id\":\"doc4\",\"key\":\"b\",\"value\":null},\r\n"
                         "{\"id\":\"doc5\",\"key\":\"B\",\"value\":null}\r\n"
                         "]}\n",
                         nil);
}


- (void)test5_ObjCViews {
    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"txt\":\"O HAI MR Obj-C!\","
        "\"numbers\": {\"int\": 1234567, \"float\": 1234.5678, \"zero\": 0},"
        "\"bignum\": 12345678901234567890,"
        "\"special\": [false, null, true],"
        "\"empty array\":[],"
        "\"empty dict\": {}}"];
    
    [[CouchbaseCallbacks sharedInstance] registerMapBlock:
     CouchVersionedBlock((^(NSDictionary *doc, CouchEmitBlock emit) {
         NSString* txt = [doc objectForKey: @"txt"];
         NSLog(@"In map block: txt=%@", txt);
         NSAssert(txt != nil, @"Missing txt key");
         if ([txt isEqualToString: @"O HAI MR Obj-C!"]) {
             // this is the doc with test values:
             NSDictionary* numbers = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithInt: 1234567], @"int",
                                      [NSNumber numberWithDouble: 1234.5678], @"float",
                                      [NSNumber numberWithInt: 0], @"zero", nil];
             STAssertEqualObjects(numbers, [doc objectForKey: @"numbers"], nil);
             STAssertEqualsWithAccuracy([[doc objectForKey: @"bignum"] doubleValue],
                                        12345678901234567890.0, 1.0, nil);
             NSArray* special = [NSArray arrayWithObjects: (id)kCFBooleanFalse,
                                 [NSNull null], kCFBooleanTrue, nil];
             STAssertEqualObjects(special, [doc objectForKey: @"special"], nil);
             STAssertEqualObjects([NSArray array], [doc objectForKey: @"empty array"], nil);
             STAssertEqualObjects([NSDictionary dictionary], [doc objectForKey: @"empty dict"], nil);
         }
         emit(txt, nil);
     })) forKey: @"testValuesMap"];
    
    [[CouchbaseCallbacks sharedInstance] registerMapBlock:
     CouchVersionedBlock((^(NSDictionary *doc, CouchEmitBlock emit) {
         NSLog(@"In faux map block");
         emit(@"objc", nil);
     })) forKey: @"fauxMap"];

    
    [[CouchbaseCallbacks sharedInstance] registerReduceBlock:
     CouchVersionedBlock((^ id (NSArray *keys, NSArray *values, BOOL rereduce) {
         NSLog(@"In reduce block");
         return [NSNumber numberWithUnsignedInteger:values.count];
     })) forKey:@"count"];

    [self send: @"PUT" toPath: @"/unittestdb/_design/objcview"
          body: @"{\"language\":\"objc\", \"views\":"
                @"{\"testobjc\":{\"map\":\"testValuesMap\","
                @"\"reduce\":\"count\"},"
                @"\"testmap2\":{\"map\":\"fauxMap\","
                @"\"reduce\":\"count\"}}}"];

    NSDictionary* headers;
    [self send: @"GET" toPath: @"/unittestdb/_design/objcview/_view/testobjc"
          body: nil responseHeaders: &headers];
    NSString* eTag = [headers objectForKey: @"Etag"];
    NSLog(@"ETag: %@", eTag);
    STAssertNotNil(eTag, nil);
    [self send: @"GET" toPath: @"/unittestdb/_design/objcview/_view/testobjc"
          body: nil responseHeaders: &headers];
    NSLog(@"ETag: %@", [headers objectForKey: @"Etag"]);
    STAssertEqualObjects([headers objectForKey: @"Etag"], eTag, @"View eTag isn't stable");

    [self send: @"PUT" toPath: @"/unittestdb/doc2" body: @"{\"txt\":\"KTHXBYE\"}"];

    [self send: @"GET" toPath: @"/unittestdb/_design/objcview/_view/testobjc"
          body: nil responseHeaders: &headers];
    NSLog(@"ETag: %@", [headers objectForKey: @"Etag"]);
    STAssertFalse([eTag isEqualToString: [headers objectForKey: @"Etag"]], @"View didn't update");
}


- (void) test6_ObjCValidation {
    [[CouchbaseCallbacks sharedInstance] registerValidateUpdateBlock:
     ^BOOL(NSDictionary *doc, id<CouchbaseValidationContext> context) {
         STAssertEqualObjects(context.databaseName, @"unittestdb", nil);
         STAssertNil(context.userName, nil);
         STAssertTrue(context.isAdmin, nil);
         STAssertNotNil(context.security, nil);
         BOOL ok = [doc objectForKey: @"valid"] != nil;
         NSLog(@"In validation block; returning %i", ok);
         if (!ok)
             context.errorMessage = @"totally bogus";
         return ok;
     } forKey: @"VALIDATE"];

    [self send: @"PUT" toPath: @"/unittestdb" body: nil];
    [self send: @"PUT" toPath: @"/unittestdb/_design/objcvalidation"
          body: @"{\"language\":\"objc\","
                @"\"validate_doc_update\":\"VALIDATE\"}"];
    
    [self send: @"PUT" toPath: @"/unittestdb/doc1" body: @"{\"valid\":true}"];
    
    NSURLRequest* request = [self request:@"PUT" path:@"/unittestdb/doc2"
                                     body:@"{\"something\":\"O HAI\"}"];
    NSHTTPURLResponse* response = nil;
    NSData* output = [NSURLConnection sendSynchronousRequest: request
                          returningResponse: (NSURLResponse**)&response
                                      error: NULL];
    STAssertEquals(response.statusCode, 403, @"Unexpected HTTP status (should be forbidden)");
    NSString* outputStr = [[[NSString alloc] initWithData: output encoding: NSUTF8StringEncoding] autorelease];
    STAssertEqualObjects(outputStr, @"{\"error\":\"forbidden\",\"reason\":\"totally bogus\"}\n", nil);
}


@end
