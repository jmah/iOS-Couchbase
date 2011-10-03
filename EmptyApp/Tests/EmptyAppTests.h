//
//  EmptyAppTests.h
//  Couchbase Mobile
//
//  Created by Jens Alfke on 7/8/11.
//  Copyright 2011 Couchbase, Inc. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>

@interface EmptyAppTests : SenTestCase

- (void)forciblyDeleteDatabase;

@end


@interface TestView : NSObject
+ (NSString *)couchViewVersionIdentifierForSelector:(SEL)sel;
+ (NSString *)testValuesMap:(NSString *)json;
+ (NSArray*) fauxMap:(NSDictionary*)doc;
+ (NSString *)reduceKeys:(NSString *)keysJson values:(NSString *)valsJson again:(BOOL)rereduce;
@end
