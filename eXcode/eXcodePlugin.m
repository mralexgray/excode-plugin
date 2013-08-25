/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2013 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "eXcodePlugin.h"
#import "EXLog.h"

#import "DevToolsCore/header-stamp.h" // Xcode dependency hack
#import "DevToolsCore/XCPluginManager.h"

@implementation eXcodePlugin

static void updated_plugin_callback (ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
    NSBundle *bundle = (__bridge NSBundle *) clientCallBackInfo;
    
    /* Avoid any race conditions with the Xcode build process; we want (at least) the executable to be in place before we reload. If it's not there,
     * wait for the FSEvent notifying us of its addition. */
    if (![[NSFileManager defaultManager] fileExistsAtPath: [bundle executablePath]])
        return;

    EXLog(@"Plugin was updated, reloading");
    
    /* TODO: Dispatch a synchronous "STOP EVERYTHING" notification */
    
    /* We'll re-register for events when the plugin reloads */
    FSEventStreamStop((FSEventStreamRef) streamRef);


    /*
     * Our code will no longer exist once the bundle is unloaded; we can't simply unload the bundle here, as the process will crash once it returns.
     * We use NSInvocationOperation operations to execute the unload,reload without relying on any code from our bundle, and use NSOperationQueue dependencies
     * to enforce the correct ordering of the operations.
     */
    NSInvocationOperation *unloadOp = [[NSInvocationOperation alloc] initWithTarget: bundle
                                                                            selector: @selector(unload)
                                                                             object: nil];
    
    NSInvocationOperation *reloadOp = [[NSInvocationOperation alloc] initWithTarget: [XCPluginManager sharedPluginManager]
                                                                           selector:@selector(findAndLoadPlugins)
                                                                             object:nil];
    [reloadOp addDependency: unloadOp];

    [[NSOperationQueue mainQueue] addOperations: @[unloadOp,reloadOp] waitUntilFinished: NO];
}

+ (void) pluginDidLoad: (NSBundle *) plugin {
    EXLog(@"Plugin is active");
    
    NSBundle *bundle = [NSBundle bundleForClass: [self class]];

    /* Watch for plugin changes, automatically reload. */
    FSEventStreamRef eventStream;
    {
        NSArray *directories = @[[bundle bundlePath]];
        FSEventStreamContext ctx = {
            .version = 0,
            .info = (__bridge void *) bundle,
            .retain = CFRetain,
            .release = CFRelease,
            .copyDescription = CFCopyDescription
        };
        eventStream = FSEventStreamCreate(NULL, &updated_plugin_callback, &ctx, (__bridge CFArrayRef) directories, kFSEventStreamEventIdSinceNow, 0.0, kFSEventStreamCreateFlagUseCFTypes);
        FSEventStreamScheduleWithRunLoop(eventStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
        FSEventStreamStart(eventStream);
    }
}

@end
