//
//  Couchbase.m
//  Couchbase Mobile
//
//  Created by J Chris Anderson on 3/2/11.
//  Copyright 2011 Couchbase, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.

#import "CouchbaseEmbeddedServer.h"

#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netdb.h>

// Erlang entry point
void erl_start(int, char**);

static NSString* const kInternalCouchStartedNotification = @"couchStarted";

static const NSTimeInterval kWaitTimeout = 10.0;    // How long to wait for CouchDB to start


@interface CouchbaseEmbeddedServer ()
@property (readwrite, retain) NSURL* serverURL;
@property (readwrite, retain) NSError* error;
- (BOOL)createDir:(NSString*)dirName;
- (BOOL)createFile:(NSString*)path contents: (NSString*)contents;
- (BOOL)installItemNamed:(NSString*)name
                 fromDir:(NSString*)fromDir
                   toDir:(NSString*)toDir
                 replace:(BOOL)replace;
- (BOOL)installTemplateNamed:(NSString*)name
                     fromDir:(NSString*)fromDir
                       toDir:(NSString*)toDir;
- (BOOL)deleteFile:(NSString*)filename fromDir: (NSString*)fromDir;
@end


@implementation CouchbaseEmbeddedServer


+ (CouchbaseEmbeddedServer*) startCouchbase: (id<CouchbaseDelegate>)delegate {
    static CouchbaseEmbeddedServer* sCouchbase;
    NSAssert(!sCouchbase, @"+startCouchbase has already been called");

    sCouchbase = [[self alloc] init];
    sCouchbase.delegate = delegate;
    if (![sCouchbase start]) {
        [sCouchbase release];
        sCouchbase = nil;
    }
    return sCouchbase;
}


- (id) initWithBundlePath: (NSString*)bundlePath {
    NSParameterAssert(bundlePath);
    self = [super init];
    if (self) {
        _bundlePath = [bundlePath copy];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask,
                                                             YES);
        _documentsDirectory = [[paths objectAtIndex:0] copy];
    }
    return self;
}


- (id)init {
    NSString* bundlePath = [[NSBundle mainBundle] pathForResource:@"CouchbaseResources" ofType:nil];
    NSAssert(bundlePath, @"Couldn't find CouchbaseResources bundle in app's Resources directory");
    return [self initWithBundlePath: bundlePath];
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_documentsDirectory release];
    [_bundlePath release];
    [_iniFilePath release];
    [_serverURL release];
    [_error release];
    [super dealloc];
}


@synthesize delegate = _delegate, iniFilePath=_iniFilePath, serverURL = _serverURL, error = _error;


- (NSString*) logDirectory {
    return [_documentsDirectory stringByAppendingPathComponent:@"log"];
}

- (NSString*) databaseDirectory {
    return [_documentsDirectory stringByAppendingPathComponent:@"couchdb"];
}

- (NSString*) localIniFilePath {
    return [_documentsDirectory stringByAppendingPathComponent:@"couchdb_local.ini"];
}


- (BOOL) installDefaultDatabase: (NSString*)databasePath {
    NSString* dbDir = self.databaseDirectory;
    return [self createDir: dbDir] &&
    [self installItemNamed: databasePath fromDir:nil toDir: dbDir replace: NO];
}


#pragma mark STARTING COUCHDB:

- (BOOL)start
{
    if (_erlangThread)
        return YES;

    _timeStarted = CFAbsoluteTimeGetCurrent();
	NSLog(@"Couchbase: Starting CouchDB, using runtime files at: %@ (built %s, %s)",
          _bundlePath, __DATE__, __TIME__);

    if(![self createDir: self.logDirectory]
           || ![self createDir: self.databaseDirectory]
           || ![self createFile:self.localIniFilePath contents: @""]
           || ![self deleteFile:@"couch.uri" fromDir:_documentsDirectory])
    {
        return NO;
    }
    
    // Customize & install default_ios.ini:
    if (![self installTemplateNamed: @"default_ios.ini"
                            fromDir: _bundlePath
                              toDir: _documentsDirectory])
        return NO;

    [self performSelector: @selector(startupTimeout) withObject: nil afterDelay: kWaitTimeout];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(couchStarted:)
                                                 name:kInternalCouchStartedNotification object:nil];
    [self performSelectorInBackground: @selector(erlangThread) withObject: nil];
    return YES;
}


#pragma mark LAUNCHING ERLANG:

// Body of the pthread that runs Erlang (and CouchDB)
- (void)erlangThread {
	char* erlang_args[15] = {"beam", "--", "-noinput",
        "-sasl", "errlog_type", "error",  // Change "error" to "all" to re-enable progress reports
		"-eval", "R = application:start(couch), io:format(\"~w~n\",[R]).",
		"-root", NULL, "-couch_ini", NULL, NULL, NULL, NULL};
    int erlang_argc;
    {
        // Alloc some paths to pass in as args to erl_start:
        NSAutoreleasePool* pool = [NSAutoreleasePool new];
        char* erl_root = strdup([[_bundlePath stringByAppendingPathComponent:@"erlang"]
                                            fileSystemRepresentation]);
        erlang_args[9] = erl_root;
        // Yes, there are up to four layers of .ini files: Default, iOS, app, local.
        erlang_args[11] = strdup([[_bundlePath stringByAppendingPathComponent:@"default.ini"]
                                            fileSystemRepresentation]);
        erlang_args[12] = strdup([[_documentsDirectory stringByAppendingPathComponent:
                                            @"default_ios.ini"] fileSystemRepresentation]);
        erlang_argc = 13;
        if (_iniFilePath)
            erlang_args[erlang_argc++] = strdup([_iniFilePath fileSystemRepresentation]);
        erlang_args[erlang_argc++] = strdup([self.localIniFilePath fileSystemRepresentation]);

        // Set some environment variables for Erlang:
        char erl_bin[1024];
        char erl_inetrc[1024];
        sprintf(erl_bin, "%s/erts-5.7.5/bin", erl_root);
        sprintf(erl_inetrc, "%s/erl_inetrc", erl_root);

        setenv("ROOTDIR", erl_root, 1);
        setenv("BINDIR", erl_bin, 1);
        setenv("ERL_INETRC", erl_inetrc, 1);
        
        [pool drain];
    }

	erl_start(erlang_argc, erlang_args);     // This never returns (unless Erlang exits)
}


#pragma mark WAITING FOR COUCHDB TO START:

- (void)couchStarted:(NSNotification*)n
{
    // Runs on the Erlang thread, so do as little as possible and return
    [self performSelectorOnMainThread:@selector(notifyCouchStarted:)
                           withObject:n.userInfo
                        waitUntilDone:NO];
}


- (void)notifyCouchStarted:(NSDictionary*)info {
    // Runs on the main thread after the notification that the server has started
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(startupTimeout)
                                               object:nil];
    NSString* urlStr = [info objectForKey:@"uri"];
    NSURL* serverURL = urlStr ? [NSURL URLWithString:urlStr] : nil;
    NSError* error = nil;
    if (serverURL) {
        NSLog(@"Couchbase: CouchDB is up and running after %.3f sec at <%@>",
              (CFAbsoluteTimeGetCurrent() - _timeStarted), serverURL);
    } else {
        NSLog(@"Couchbase: Error: CouchDB returned invalid server URL");
        error = [NSError errorWithDomain:@"Couchbase" code:1 userInfo:nil]; //TODO: Real error
    }

    self.error = error;
    self.serverURL = serverURL; // Will trigger KVO notification
    [_delegate couchbaseDidStart:_serverURL];
}


- (void)startupTimeout {
    NSLog(@"Couchbase: Error: No startup notification from server engine");
    self.error = [NSError errorWithDomain:@"Couchbase" code:2 userInfo:nil]; //TODO: Real error
    [_delegate couchbaseDidStart:nil];
}


#pragma mark UTILITIES:

- (BOOL)createDir:(NSString*)dirName {
	BOOL isDir=YES;
	NSFileManager *fm= [NSFileManager defaultManager];
	if(![fm fileExistsAtPath:dirName isDirectory:&isDir]) {
        NSError* createError = nil;
		if([fm createDirectoryAtPath:dirName withIntermediateDirectories:YES
                          attributes:nil error:&createError]) {
            NSLog(@"Couchbase: Created dir %@", dirName);
        } else {
			NSLog(@"Couchbase: Error creating dir '%@': %@", dirName, createError);
            self.error = createError;
            return NO;
        }
    } else if (!isDir) {
        NSLog(@"Couchbase: Error creating dir '%@': already exists as file", dirName);
        return NO;
    }
    return YES;
}

- (BOOL)createFile:(NSString*)path contents: (NSString*)contents {
    BOOL isDir;
	if(![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        NSError* error = nil;
        if (![contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error: &error]) {
			NSLog(@"Couchbase: Error creating file '%@': %@", path, error);
            self.error = error;
            return NO;
        }
    } else if (isDir) {
        NSLog(@"Couchbase: Error creating file '%@': already exists as dir", path);
        return NO;
    }
    return YES;
}

// Copies the item if the destination does not exist; _or_ if it's outdated (if 'replace' is true)
- (BOOL)installItemNamed:(NSString*)name
                 fromDir:(NSString*)fromDir
                   toDir:(NSString*)toDir
                 replace:(BOOL)replace 
{
	NSString *source = fromDir ? [fromDir stringByAppendingPathComponent: name] : name;
	NSString *target = [toDir stringByAppendingPathComponent: [name lastPathComponent]];
    
    NSError* error;
	NSFileManager *fm= [NSFileManager defaultManager];
    NSDate* targetModDate = [[fm attributesOfItemAtPath: target error:NULL] fileModificationDate];
    if (targetModDate) {
        if (!replace)
            return YES;     // Told not to overwrite, so return immediately
        
        NSDate* sourceModDate = [[fm attributesOfItemAtPath: source error:&error]
                                        fileModificationDate];
        if (!sourceModDate) {
            NSLog(@"Couchbase: Unable to read %@: %@", source, error);
            self.error = error;
            return NO;
        }
        if ([targetModDate compare: sourceModDate] >= 0)
            return YES;     // target exists and is at least as new as the source
        
        // Need to delete target first, or -copyItemAtPath will fail
        if (![fm removeItemAtPath: target error: &error]) {
            NSLog(@"Couchbase: Error installing to %@: %@", target, error);
            self.error = error;
            return NO;
        }
    }
    
    // OK, do the copy:
    if ([fm copyItemAtPath: source toPath: target error: &error]) {
        NSLog(@"Couchbase: Installed %@ into %@", [name lastPathComponent], target);
        return YES;
    } else {
        NSLog(@"Couchbase: Error installing to %@: %@", target, error);
        self.error = error;
        return NO;
    }
}

- (BOOL)deleteFile:(NSString*)filename fromDir: (NSString*)fromDir {
    NSString* path = [fromDir stringByAppendingPathComponent: filename];
	NSFileManager *fm= [NSFileManager defaultManager];
	if([fm fileExistsAtPath:path]) {
        NSError* removeError = nil;
		if (![fm removeItemAtPath:path error:&removeError]) {
            NSLog(@"Couchbase: Error deleting %@: %@", path, removeError);
            self.error = removeError;
            return NO;
        }
	}
    return YES;
}

- (BOOL)installTemplateNamed:(NSString*)name
                     fromDir:(NSString*)fromDir
                       toDir:(NSString*)toDir
{
	NSString *source = fromDir ? [fromDir stringByAppendingPathComponent: name] : name;
	NSString *target = [toDir stringByAppendingPathComponent: [name lastPathComponent]];

    // Get the template contents:
    NSError* error;
    NSMutableString* contents = [NSMutableString stringWithContentsOfFile: source
                                                                 encoding:NSUTF8StringEncoding
                                                                    error: &error];
    if (!contents) {
        NSLog(@"Couchbase: Error installing %@: %@", source, error);
        self.error = error;
        return NO;
    }

    [contents replaceOccurrencesOfString: @"$BUNDLEDIR"
                              withString: _bundlePath
                                 options: 0
                                   range: NSMakeRange(0, contents.length)];
    [contents replaceOccurrencesOfString: @"$INSTALLDIR"
                              withString: _documentsDirectory
                                 options: 0
                                   range: NSMakeRange(0, contents.length)];
    NSData* newData = [contents dataUsingEncoding: NSUTF8StringEncoding];

    // Read the destination file:
    NSData* oldData = [NSData dataWithContentsOfFile: target options: 0 error: nil];
    if (oldData && [oldData isEqualToData: newData])
        return YES;   // No need to copy

    if ([newData writeToFile: target options: NSDataWritingFileProtectionNone error: &error]) {
        NSLog(@"Couchbase: Installed customized %@ into %@", [name lastPathComponent], target);
        return YES;
    } else {
        NSLog(@"Couchbase: Error installing to %@: %@", target, error);
        self.error = error;
        return NO;
    }
}

@end
