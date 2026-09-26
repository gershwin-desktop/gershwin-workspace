/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_GWURLSchemeRegistry.m - a URL such as claude://... handed to Workspace
 * ended in the manual "Open with" panel because Workspace knew nothing of
 * the x-scheme-handler associations every freedesktop tool reads.  These
 * cases pin the lookup against fixture XDG directories.  Headless. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWURLSchemeRegistry.m"

#include <sys/stat.h>
#include <unistd.h>

static NSString *root = nil;

/* A URL as a site hands back an SSO result: & and = must reach the handler
 * as part of one argument, untouched. */
static NSString * const callbackURL = @"test://callback?code=a1&state=b=c&x=%20y";

@interface FixtureSource : NSObject <GWSchemeApplicationSource>
{
  NSArray *paths;
}
- (id)initWithPaths:(NSArray *)p;
@end

@implementation FixtureSource
- (id)initWithPaths:(NSArray *)p
{
  if ((self = [super init]) != nil)
    {
      paths = [p retain];
    }
  return self;
}
- (void)dealloc
{
  [paths release];
  [super dealloc];
}
- (NSArray *)applicationPathsForScheme:(NSString *)scheme
{
  return paths;
}
@end

static NSString *fixturePath(NSString *rel)
{
  return [root stringByAppendingPathComponent: rel];
}

/* Starts every case from an empty tree so no case sees another's files. */
static void setUpFiles(NSDictionary *files)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *e = [files keyEnumerator];
  NSString *rel;

  [fm removeFileAtPath: root handler: nil];
  while ((rel = [e nextObject]) != nil)
    {
      NSString *full = fixturePath(rel);
      NSString *content = [files objectForKey: rel];

      [fm createDirectoryAtPath: [full stringByDeletingLastPathComponent]
    withIntermediateDirectories: YES
                     attributes: nil
                          error: NULL];
      [content writeToFile: full atomically: NO
                  encoding: NSUTF8StringEncoding error: NULL];
      if ([rel hasPrefix: @"bin/"])
        {
          chmod([full fileSystemRepresentation], 0755);
        }
    }
}

static NSMutableDictionary *baseFiles(void)
{
  NSMutableDictionary *files = [NSMutableDictionary dictionary];

  [files setObject: @"#!/bin/sh\nexit 0\n" forKey: @"bin/handler"];
  [files setObject: @"#!/bin/sh\nexit 0\n" forKey: @"bin/other"];
  [files setObject: @"[Desktop Entry]\nType=Application\nName=Handler\n"
                    @"Exec=handler --open %u\nTerminal=false\n"
            forKey: @"data/applications/handler.desktop"];
  [files setObject: @"[Desktop Entry]\nType=Application\nName=Added\n"
                    @"Exec=other %u\n"
            forKey: @"data/applications/added.desktop"];
  return files;
}

static GWURLSchemeRegistry *registry(NSArray *nativePaths)
{
  NSDictionary *env = [NSDictionary dictionaryWithObjectsAndKeys:
    fixturePath(@"home"), @"HOME",
    fixturePath(@"bin"), @"PATH",
    fixturePath(@"config"), @"XDG_CONFIG_HOME",
    fixturePath(@"etcxdg"), @"XDG_CONFIG_DIRS",
    fixturePath(@"data"), @"XDG_DATA_HOME",
    fixturePath(@"sys"), @"XDG_DATA_DIRS",
    @"Gershwin", @"XDG_CURRENT_DESKTOP",
    nil];
  FixtureSource *src = [[[FixtureSource alloc] initWithPaths: nativePaths]
                         autorelease];

  return [[[GWURLSchemeRegistry alloc] initWithEnvironment: env
                                         applicationSource: src] autorelease];
}

static GWURLHandler *resolve(NSString *url, NSArray *nativePaths, NSError **err)
{
  *err = nil;
  return [registry(nativePaths) handlerForURL: [NSURL URLWithString: url]
                                        error: err];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSMutableDictionary *files;
  GWURLHandler *h;
  NSError *err;
  NSArray *want;

  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_GWURLSchemeRegistry.%d", (int)getpid()]]
    retain];

  START_SET("user default resolves and %u gets the exact URL")
    files = baseFiles();
    [files setObject: @"[Default Applications]\nx-scheme-handler/test=handler.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    want = [NSArray arrayWithObjects: fixturePath(@"bin/handler"),
      @"--open", callbackURL, nil];
    PASS_EQUAL([h arguments], want,
      "argv is the program found in PATH, its option and the URL as one argument");
    PASS_EQUAL([h desktopFilePath], fixturePath(@"data/applications/handler.desktop"),
      "the desktop file comes from XDG_DATA_HOME");
    PASS([h applicationPath] == nil, "a freedesktop handler is no GNUstep app");
    PASS(err == nil, "no error");
  END_SET("user default resolves and %u gets the exact URL")

  START_SET("the user default wins over an added association")
    files = baseFiles();
    [files setObject: @"[Added Associations]\nx-scheme-handler/test=added.desktop;\n\n"
                      @"[Default Applications]\nx-scheme-handler/test=handler.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS_EQUAL([[h arguments] objectAtIndex: 0], fixturePath(@"bin/handler"),
      "the [Default Applications] entry is chosen");
  END_SET("the user default wins over an added association")

  START_SET("an added association is used when there is no default")
    files = baseFiles();
    [files setObject: @"[Added Associations]\nx-scheme-handler/test=added.desktop;\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS_EQUAL([[h arguments] objectAtIndex: 0], fixturePath(@"bin/other"),
      "the [Added Associations] entry is chosen");
  END_SET("an added association is used when there is no default")

  START_SET("an unknown scheme resolves to nothing")
    files = baseFiles();
    [files setObject: @"[Default Applications]\nx-scheme-handler/test=handler.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(@"nope://x", nil, &err);
    PASS(h == nil, "no handler for an unregistered scheme");
    PASS(err == nil, "and no error either");
  END_SET("an unknown scheme resolves to nothing")

  START_SET("Terminal=true entries are rejected")
    files = baseFiles();
    [files setObject: @"[Desktop Entry]\nType=Application\nName=Term\n"
                      @"Exec=handler %u\nTerminal=true\n"
              forKey: @"data/applications/term.desktop"];
    [files setObject: @"[Default Applications]\nx-scheme-handler/test=term.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS(h == nil && err == nil, "a terminal-only handler is not used");

    [files setObject: @"[Default Applications]\nx-scheme-handler/test=term.desktop\n"
                      @"[Added Associations]\nx-scheme-handler/test=added.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS_EQUAL([[h arguments] objectAtIndex: 0], fixturePath(@"bin/other"),
      "the next candidate is used instead");
  END_SET("Terminal=true entries are rejected")

  START_SET("TryExec naming a missing program skips the entry")
    files = baseFiles();
    [files setObject: @"[Desktop Entry]\nType=Application\nName=Gone\n"
                      @"TryExec=/nonexistent/gone\nExec=handler %u\n"
              forKey: @"data/applications/gone.desktop"];
    [files setObject: @"[Default Applications]\nx-scheme-handler/test=gone.desktop;added.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS_EQUAL([[h arguments] objectAtIndex: 0], fixturePath(@"bin/other"),
      "the uninstalled entry is skipped");
  END_SET("TryExec naming a missing program skips the entry")

  START_SET("mimeinfo.cache of XDG_DATA_DIRS and removed associations")
    files = baseFiles();
    [files setObject: @"[MIME Cache]\nx-scheme-handler/test=sysh.desktop;\n"
              forKey: @"sys/applications/mimeinfo.cache"];
    [files setObject: @"[Desktop Entry]\nType=Application\nName=Sys\n"
                      @"Exec=handler %U\n"
              forKey: @"sys/applications/sysh.desktop"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS_EQUAL([h desktopFilePath], fixturePath(@"sys/applications/sysh.desktop"),
      "the system cache names the handler");
    want = [NSArray arrayWithObjects: fixturePath(@"bin/handler"), callbackURL, nil];
    PASS_EQUAL([h arguments], want, "%%U gets the URL");

    [files setObject: @"[Removed Associations]\nx-scheme-handler/test=sysh.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS(h == nil && err == nil, "a removed association is not used");
  END_SET("mimeinfo.cache of XDG_DATA_DIRS and removed associations")

  START_SET("Exec quoting and escapes")
    files = baseFiles();
    [files setObject: @"[Desktop Entry]\nType=Application\nName=Q\n"
                      @"Exec=\"handler\" --name \"a b\\\\\\\\c \\\\$HOME\" --url=%u\n"
              forKey: @"data/applications/q.desktop"];
    [files setObject: @"[Default Applications]\nx-scheme-handler/test=q.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    want = [NSArray arrayWithObjects: fixturePath(@"bin/handler"), @"--name",
      @"a b\\c $HOME", [@"--url=" stringByAppendingString: callbackURL], nil];
    PASS_EQUAL([h arguments], want,
      "quoted arguments are unescaped and no shell expansion happens");
  END_SET("Exec quoting and escapes")

  START_SET("a malformed desktop file fails hard")
    files = baseFiles();
    [files setObject: @"[Desktop Entry]\nType=Application\nName=Bad\n"
              forKey: @"data/applications/bad.desktop"];
    [files setObject: @"[Default Applications]\nx-scheme-handler/test=bad.desktop;added.desktop\n"
              forKey: @"config/mimeapps.list"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS(h == nil, "no handler from a desktop file without Exec");
    PASS([[err domain] isEqual: GWURLSchemeRegistryErrorDomain],
      "an error names the malformed file");

    [files setObject: @"[Desktop Entry]\nType=Application\nName=Bad\n"
                      @"Exec=handler \"--open %u\n"
              forKey: @"data/applications/bad.desktop"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS(h == nil && err != nil, "an unterminated quote is an error");

    [files setObject: @"[Desktop Entry]\nType=Application\nName=Bad\n"
                      @"Exec=handler %z\n"
              forKey: @"data/applications/bad.desktop"];
    setUpFiles(files);
    h = resolve(callbackURL, nil, &err);
    PASS(h == nil && err != nil, "an unknown field code is an error");
  END_SET("a malformed desktop file fails hard")

  START_SET("a GNUstep application declaring the scheme comes first")
    files = baseFiles();
    [files setObject: @"[Default Applications]\nx-scheme-handler/test=handler.desktop\n"
              forKey: @"config/mimeapps.list"];
    [files setObject: @"{ NSURLTypes = ( { CFBundleURLSchemes = ( Test ); } ); }"
              forKey: @"Apps/Native.app/Resources/Info-gnustep.plist"];
    [files setObject: @"{ GSSchemes = ( test ); }"
              forKey: @"Apps/Schemes.app/Resources/Info-gnustep.plist"];
    [files setObject: @"{ NSExecutable = Other; }"
              forKey: @"Apps/Other.app/Resources/Info-gnustep.plist"];
    setUpFiles(files);

    h = resolve(callbackURL,
      [NSArray arrayWithObject: fixturePath(@"Apps/Native.app")], &err);
    PASS_EQUAL([h applicationPath], fixturePath(@"Apps/Native.app"),
      "an NSURLTypes declaration beats the freedesktop default");
    PASS([h arguments] == nil, "a GNUstep app gets no command line");

    h = resolve(callbackURL,
      [NSArray arrayWithObject: fixturePath(@"Apps/Schemes.app")], &err);
    PASS_EQUAL([h applicationPath], fixturePath(@"Apps/Schemes.app"),
      "a GSSchemes declaration is honoured");

    h = resolve(callbackURL,
      [NSArray arrayWithObject: fixturePath(@"Apps/Other.app")], &err);
    PASS_EQUAL([[h arguments] objectAtIndex: 0], fixturePath(@"bin/handler"),
      "an app that does not declare the scheme is passed over");
  END_SET("a GNUstep application declaring the scheme comes first")

  [[NSFileManager defaultManager] removeFileAtPath: root handler: nil];
  [root release];
  [arp release];
  return 0;
}
