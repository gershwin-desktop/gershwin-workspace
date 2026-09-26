/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWURLSchemeRegistry.h"

NSString * const GWURLSchemeRegistryErrorDomain = @"GWURLSchemeRegistryErrorDomain";

static NSString * const DesktopEntryGroup = @"Desktop Entry";

@interface GWURLHandler ()
- (instancetype)initWithApplicationPath:(NSString *)appPath
                              arguments:(NSArray *)args
                        desktopFilePath:(NSString *)deskPath;
@end

@implementation GWURLHandler

- (instancetype)initWithApplicationPath:(NSString *)appPath
                              arguments:(NSArray *)args
                        desktopFilePath:(NSString *)deskPath
{
  if ((self = [super init]) != nil)
    {
      applicationPath = [appPath copy];
      arguments = [args copy];
      desktopFilePath = [deskPath copy];
    }
  return self;
}

- (void)dealloc
{
  [applicationPath release];
  [arguments release];
  [desktopFilePath release];
  [super dealloc];
}

- (NSString *)applicationPath { return applicationPath; }
- (NSArray *)arguments { return arguments; }
- (NSString *)desktopFilePath { return desktopFilePath; }

- (NSString *)description
{
  if (applicationPath != nil)
    {
      return [NSString stringWithFormat: @"<%@ app %@>",
        NSStringFromClass([self class]), applicationPath];
    }
  return [NSString stringWithFormat: @"<%@ %@ from %@>",
    NSStringFromClass([self class]), arguments, desktopFilePath];
}

@end

/* Splits "a;b;;c;" into its non-empty items, as mimeapps.list and
 * mimeinfo.cache values are written. */
static NSArray *listItems(NSString *value)
{
  NSMutableArray *items = [NSMutableArray array];
  NSEnumerator *e = [[value componentsSeparatedByString: @";"] objectEnumerator];
  NSString *item;

  while ((item = [e nextObject]) != nil)
    {
      item = [item stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
      if ([item length] > 0)
        {
          [items addObject: item];
        }
    }
  return items;
}

/* Undoes the value escapes of the desktop entry specification.  An escape
 * it does not define is kept as written: Exec lines in the wild rely on
 * "\"" reaching the quoting rules, which is also what GLib hands on. */
static NSString *unescapeValue(NSString *value)
{
  NSMutableString *out = [NSMutableString stringWithCapacity: [value length]];
  NSUInteger i, n = [value length];

  for (i = 0; i < n; i++)
    {
      unichar c = [value characterAtIndex: i];

      if (c == '\\' && i + 1 < n)
        {
          unichar e = [value characterAtIndex: ++i];

          switch (e)
            {
              case 's': [out appendString: @" "]; break;
              case 'n': [out appendString: @"\n"]; break;
              case 't': [out appendString: @"\t"]; break;
              case 'r': [out appendString: @"\r"]; break;
              case '\\': [out appendString: @"\\"]; break;
              default:
                [out appendFormat: @"\\%C", e];
                break;
            }
        }
      else
        {
          [out appendFormat: @"%C", c];
        }
    }
  return out;
}

@interface GWURLSchemeRegistry (Private)
- (NSString *)envValue:(NSString *)key;
- (NSString *)homeRelative:(NSString *)rel;
- (NSArray *)pathList:(NSString *)key defaultValue:(NSString *)def;
- (NSString *)dataHome;
- (NSArray *)dataDirectories;
- (NSArray *)applicationDirectories;
- (NSArray *)associationSources;
- (NSString *)executablePathFor:(NSString *)program;
- (GWURLHandler *)nativeHandlerForScheme:(NSString *)scheme;
- (GWURLHandler *)handlerForDesktopID:(NSString *)desktopID
                                  url:(NSURL *)url
                                error:(NSError **)error;
- (GWURLHandler *)handlerForDesktopFile:(NSString *)path
                                    url:(NSURL *)url
                                  error:(NSError **)error;
- (NSArray *)argumentsForExec:(NSString *)exec
                        entry:(NSDictionary *)entry
                  desktopFile:(NSString *)path
                          url:(NSURL *)url
                      problem:(NSString **)problem;
@end

/* Parses a key file into group name -> (key -> raw value).  Desktop files
 * are read strictly because a handler that is launched from a misread line
 * would run the wrong command; the association lists are read leniently,
 * a stray line there only loses that line. */
static NSDictionary *parseKeyFile(NSString *path, BOOL strict,
  NSString **problem)
{
  NSMutableDictionary *groups = [NSMutableDictionary dictionary];
  NSMutableDictionary *current = nil;
  NSString *text;
  NSEnumerator *e;
  NSString *line;
  NSUInteger lineNo = 0;

  text = [NSString stringWithContentsOfFile: path
                                   encoding: NSUTF8StringEncoding
                                      error: NULL];
  if (text == nil)
    {
      *problem = @"it is not readable UTF-8 text";
      return nil;
    }

  e = [[text componentsSeparatedByString: @"\n"] objectEnumerator];
  while ((line = [e nextObject]) != nil)
    {
      NSRange eq;
      NSString *key;

      lineNo++;
      if ([line hasSuffix: @"\r"])
        {
          line = [line substringToIndex: [line length] - 1];
        }
      if ([line length] == 0 || [line hasPrefix: @"#"])
        {
          continue;
        }
      if ([line hasPrefix: @"["])
        {
          NSString *name;

          if ([line hasSuffix: @"]"] == NO || [line length] < 3)
            {
              if (strict)
                {
                  *problem = [NSString stringWithFormat:
                    @"line %lu is not a valid group header", (unsigned long)lineNo];
                  return nil;
                }
              current = nil;
              continue;
            }
          name = [line substringWithRange: NSMakeRange(1, [line length] - 2)];
          if (strict && [groups objectForKey: name] != nil)
            {
              *problem = [NSString stringWithFormat:
                @"group [%@] appears twice", name];
              return nil;
            }
          current = [groups objectForKey: name];
          if (current == nil)
            {
              current = [NSMutableDictionary dictionary];
              [groups setObject: current forKey: name];
            }
          continue;
        }

      eq = [line rangeOfString: @"="];
      key = (eq.location == NSNotFound) ? nil
        : [[line substringToIndex: eq.location] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
      if (current == nil || key == nil || [key length] == 0)
        {
          if (strict)
            {
              *problem = [NSString stringWithFormat:
                @"line %lu is neither a group, a comment nor a key", (unsigned long)lineNo];
              return nil;
            }
          continue;
        }
      if (strict && [current objectForKey: key] != nil)
        {
          *problem = [NSString stringWithFormat: @"key %@ appears twice", key];
          return nil;
        }
      [current setObject: [[line substringFromIndex: NSMaxRange(eq)]
                            stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]]
                  forKey: key];
    }
  return groups;
}

/* Returns 1 for true, 0 for false or absent, -1 for anything else. */
static int booleanValue(NSDictionary *entry, NSString *key)
{
  NSString *v = [entry objectForKey: key];

  if (v == nil || [v isEqualToString: @"false"])
    {
      return 0;
    }
  if ([v isEqualToString: @"true"])
    {
      return 1;
    }
  return -1;
}

static BOOL plistDeclaresScheme(NSDictionary *info, NSString *scheme)
{
  id schemes = [info objectForKey: @"GSSchemes"];
  NSArray *typeKeys = [NSArray arrayWithObjects: @"NSURLTypes",
                                                 @"CFBundleURLTypes", nil];
  NSEnumerator *ke = [typeKeys objectEnumerator];
  NSString *typeKey;

  if ([schemes isKindOfClass: [NSArray class]])
    {
      NSEnumerator *se = [schemes objectEnumerator];
      id s;

      while ((s = [se nextObject]) != nil)
        {
          if ([s isKindOfClass: [NSString class]]
              && [[s lowercaseString] isEqualToString: scheme])
            {
              return YES;
            }
        }
    }

  while ((typeKey = [ke nextObject]) != nil)
    {
      id types = [info objectForKey: typeKey];
      NSEnumerator *te;
      id type;

      if ([types isKindOfClass: [NSArray class]] == NO)
        {
          continue;
        }
      te = [types objectEnumerator];
      while ((type = [te nextObject]) != nil)
        {
          id list;
          NSEnumerator *se;
          id s;

          if ([type isKindOfClass: [NSDictionary class]] == NO)
            {
              continue;
            }
          list = [type objectForKey: @"CFBundleURLSchemes"];
          if ([list isKindOfClass: [NSArray class]] == NO)
            {
              continue;
            }
          se = [list objectEnumerator];
          while ((s = [se nextObject]) != nil)
            {
              if ([s isKindOfClass: [NSString class]]
                  && [[s lowercaseString] isEqualToString: scheme])
                {
                  return YES;
                }
            }
        }
    }
  return NO;
}

@implementation GWURLSchemeRegistry

- (instancetype)initWithEnvironment:(NSDictionary *)env
                  applicationSource:(id<GWSchemeApplicationSource>)source
{
  if ((self = [super init]) != nil)
    {
      environment = [env copy];
      applicationSource = [source retain];
    }
  return self;
}

- (void)dealloc
{
  [environment release];
  [applicationSource release];
  [super dealloc];
}

- (GWURLHandler *)handlerForURL:(NSURL *)url error:(NSError **)error
{
  NSString *scheme = [[url scheme] lowercaseString];
  NSString *mimeType;
  NSArray *sources;
  NSMutableSet *removed;
  NSEnumerator *e;
  NSDictionary *source;
  GWURLHandler *handler;
  NSError *localError = nil;

  if (error == NULL)
    {
      error = &localError;
    }
  *error = nil;
  if ([scheme length] == 0)
    {
      return nil;
    }

  handler = [self nativeHandlerForScheme: scheme];
  if (handler != nil)
    {
      return handler;
    }

  mimeType = [@"x-scheme-handler/" stringByAppendingString: scheme];
  sources = [self associationSources];

  /* Every [Default Applications] list is consulted before any association:
   * the user's explicit choice outranks whatever was merely installed. */
  e = [sources objectEnumerator];
  while ((source = [e nextObject]) != nil)
    {
      NSDictionary *defaults;
      NSEnumerator *ie;
      NSString *desktopID;

      if ([[source objectForKey: @"cache"] boolValue])
        {
          continue;
        }
      defaults = [[source objectForKey: @"groups"]
                   objectForKey: @"Default Applications"];
      ie = [listItems([defaults objectForKey: mimeType]) objectEnumerator];
      while ((desktopID = [ie nextObject]) != nil)
        {
          handler = [self handlerForDesktopID: desktopID url: url error: error];
          if (handler != nil || *error != nil)
            {
              return handler;
            }
        }
    }

  /* A removal only hides associations of files with lower precedence,
   * so the set grows as the walk goes down. */
  removed = [NSMutableSet set];
  e = [sources objectEnumerator];
  while ((source = [e nextObject]) != nil)
    {
      NSDictionary *groups = [source objectForKey: @"groups"];
      BOOL isCache = [[source objectForKey: @"cache"] boolValue];
      NSString *group = isCache ? @"MIME Cache" : @"Added Associations";
      NSEnumerator *ie;
      NSString *desktopID;

      ie = [listItems([[groups objectForKey: group] objectForKey: mimeType])
             objectEnumerator];
      while ((desktopID = [ie nextObject]) != nil)
        {
          if ([removed containsObject: desktopID])
            {
              continue;
            }
          handler = [self handlerForDesktopID: desktopID url: url error: error];
          if (handler != nil || *error != nil)
            {
              return handler;
            }
        }
      if (isCache == NO)
        {
          [removed addObjectsFromArray: listItems([[groups objectForKey:
            @"Removed Associations"] objectForKey: mimeType])];
        }
    }
  return nil;
}

@end

@implementation GWURLSchemeRegistry (Private)

- (NSString *)envValue:(NSString *)key
{
  NSString *v = [environment objectForKey: key];

  return ([v length] > 0) ? v : nil;
}

- (NSString *)homeRelative:(NSString *)rel
{
  NSString *home = [self envValue: @"HOME"];

  return (home == nil) ? nil : [home stringByAppendingPathComponent: rel];
}

- (NSArray *)pathList:(NSString *)key defaultValue:(NSString *)def
{
  NSString *v = [self envValue: key];
  NSMutableArray *dirs = [NSMutableArray array];
  NSEnumerator *e;
  NSString *dir;

  e = [[(v != nil ? v : def) componentsSeparatedByString: @":"]
        objectEnumerator];
  while ((dir = [e nextObject]) != nil)
    {
      if ([dir isAbsolutePath])
        {
          [dirs addObject: dir];
        }
    }
  return dirs;
}

- (NSString *)dataHome
{
  NSString *v = [self envValue: @"XDG_DATA_HOME"];

  return (v != nil) ? v : [self homeRelative: @".local/share"];
}

- (NSArray *)dataDirectories
{
  NSMutableArray *dirs = [NSMutableArray array];
  NSString *home = [self dataHome];

  if (home != nil)
    {
      [dirs addObject: home];
    }
  [dirs addObjectsFromArray: [self pathList: @"XDG_DATA_DIRS"
                               defaultValue: @"/usr/local/share:/usr/share"]];
  return dirs;
}

- (NSArray *)applicationDirectories
{
  NSMutableArray *dirs = [NSMutableArray array];
  NSEnumerator *e = [[self dataDirectories] objectEnumerator];
  NSString *dir;

  while ((dir = [e nextObject]) != nil)
    {
      [dirs addObject: [dir stringByAppendingPathComponent: @"applications"]];
    }
  return dirs;
}

/* The association files in the precedence order of the mime-apps
 * specification, each as {groups, cache}.  A directory's mimeinfo.cache
 * comes right after its own mimeapps.list files. */
- (NSArray *)associationSources
{
  NSMutableArray *sources = [NSMutableArray array];
  NSMutableArray *listDirs = [NSMutableArray array];
  NSMutableArray *names = [NSMutableArray array];
  NSString *configHome = [self envValue: @"XDG_CONFIG_HOME"];
  NSString *desktops = [self envValue: @"XDG_CURRENT_DESKTOP"];
  NSEnumerator *de;
  NSString *dir;

  if (configHome == nil)
    {
      configHome = [self homeRelative: @".config"];
    }
  if (configHome != nil)
    {
      [listDirs addObject: configHome];
    }
  [listDirs addObjectsFromArray: [self pathList: @"XDG_CONFIG_DIRS"
                                   defaultValue: @"/etc/xdg"]];
  [listDirs addObjectsFromArray: [self applicationDirectories]];

  if (desktops != nil)
    {
      NSEnumerator *ne = [[desktops componentsSeparatedByString: @":"]
                           objectEnumerator];
      NSString *name;

      while ((name = [ne nextObject]) != nil)
        {
          if ([name length] > 0)
            {
              [names addObject: [[name lowercaseString]
                stringByAppendingString: @"-mimeapps.list"]];
            }
        }
    }
  [names addObject: @"mimeapps.list"];

  de = [listDirs objectEnumerator];
  while ((dir = [de nextObject]) != nil)
    {
      NSEnumerator *ne = [names objectEnumerator];
      NSString *name;
      NSString *cache;
      NSDictionary *groups;
      NSString *ignored;

      while ((name = [ne nextObject]) != nil)
        {
          groups = parseKeyFile([dir stringByAppendingPathComponent: name],
                                NO, &ignored);
          if (groups != nil)
            {
              [sources addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                groups, @"groups", [NSNumber numberWithBool: NO], @"cache", nil]];
            }
        }
      cache = [dir stringByAppendingPathComponent: @"mimeinfo.cache"];
      if ([[dir lastPathComponent] isEqualToString: @"applications"]
          && (groups = parseKeyFile(cache, NO, &ignored)) != nil)
        {
          [sources addObject: [NSDictionary dictionaryWithObjectsAndKeys:
            groups, @"groups", [NSNumber numberWithBool: YES], @"cache", nil]];
        }
    }
  return sources;
}

- (NSString *)executablePathFor:(NSString *)program
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *e;
  NSString *dir;

  if ([program rangeOfString: @"/"].location != NSNotFound)
    {
      return ([program isAbsolutePath] && [fm isExecutableFileAtPath: program])
        ? program : nil;
    }
  e = [[self pathList: @"PATH" defaultValue: @"/usr/local/bin:/usr/bin:/bin"]
        objectEnumerator];
  while ((dir = [e nextObject]) != nil)
    {
      NSString *candidate = [dir stringByAppendingPathComponent: program];
      BOOL isDir = NO;

      if ([fm fileExistsAtPath: candidate isDirectory: &isDir] && isDir == NO
          && [fm isExecutableFileAtPath: candidate])
        {
          return candidate;
        }
    }
  return nil;
}

- (GWURLHandler *)nativeHandlerForScheme:(NSString *)scheme
{
  NSArray *plists = [NSArray arrayWithObjects: @"Resources/Info-gnustep.plist",
    @"Resources/Info.plist", @"Contents/Info.plist", nil];
  NSEnumerator *ae = [[applicationSource applicationPathsForScheme: scheme]
                       objectEnumerator];
  NSString *appPath;

  while ((appPath = [ae nextObject]) != nil)
    {
      NSEnumerator *pe = [plists objectEnumerator];
      NSString *rel;

      while ((rel = [pe nextObject]) != nil)
        {
          NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
            [appPath stringByAppendingPathComponent: rel]];

          if (info == nil)
            {
              continue;
            }
          if (plistDeclaresScheme(info, scheme))
            {
              return [[[GWURLHandler alloc] initWithApplicationPath: appPath
                                                          arguments: nil
                                                    desktopFilePath: nil]
                       autorelease];
            }
          /* The first Info.plist found is the one the bundle uses. */
          break;
        }
    }
  return nil;
}

- (GWURLHandler *)handlerForDesktopID:(NSString *)desktopID
                                  url:(NSURL *)url
                                error:(NSError **)error
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *e = [[self applicationDirectories] objectEnumerator];
  NSString *dir;

  if ([desktopID hasSuffix: @".desktop"] == NO
      || [desktopID rangeOfString: @"/"].location != NSNotFound)
    {
      return nil;
    }
  /* The first directory holding the ID shadows all later ones, even when
   * its entry turns out to be unusable. */
  while ((dir = [e nextObject]) != nil)
    {
      NSString *path = [dir stringByAppendingPathComponent: desktopID];

      if ([fm fileExistsAtPath: path])
        {
          return [self handlerForDesktopFile: path url: url error: error];
        }
    }
  return nil;
}

- (GWURLHandler *)handlerForDesktopFile:(NSString *)path
                                    url:(NSURL *)url
                                  error:(NSError **)error
{
  NSString *problem = nil;
  NSDictionary *groups = parseKeyFile(path, YES, &problem);
  NSDictionary *entry = [groups objectForKey: DesktopEntryGroup];
  NSString *exec = nil;
  NSString *tryExec;
  NSArray *args = nil;
  int terminal = 0;
  int hidden = 0;

  if (groups != nil && entry == nil)
    {
      problem = @"it has no [Desktop Entry] group";
    }
  if (problem == nil
      && [[entry objectForKey: @"Type"] isEqualToString: @"Application"] == NO)
    {
      problem = @"its Type is not Application";
    }
  if (problem == nil)
    {
      hidden = booleanValue(entry, @"Hidden");
      terminal = booleanValue(entry, @"Terminal");
      if (hidden < 0 || terminal < 0)
        {
          problem = @"Hidden or Terminal is neither true nor false";
        }
    }
  if (problem == nil && hidden == 1)
    {
      /* Hidden=true is how a user deletes an installed entry. */
      return nil;
    }
  if (problem == nil)
    {
      exec = unescapeValue([entry objectForKey: @"Exec"]);
      if ([exec length] == 0)
        {
          problem = @"it has no Exec line";
        }
    }
  if (problem == nil)
    {
      args = [self argumentsForExec: exec entry: entry desktopFile: path
                                url: url problem: &problem];
    }
  if (problem != nil)
    {
      *error = [NSError errorWithDomain: GWURLSchemeRegistryErrorDomain
                                   code: 1
                               userInfo: [NSDictionary dictionaryWithObject:
        [NSString stringWithFormat: @"The desktop file %@ is malformed: %@.",
          path, problem] forKey: NSLocalizedDescriptionKey]];
      return nil;
    }

  /* Without a terminal emulator of our own to run it in, a terminal
   * handler would run invisibly with no one to talk to. */
  if (terminal == 1 || args == nil)
    {
      return nil;
    }
  tryExec = [entry objectForKey: @"TryExec"];
  if (tryExec != nil && [self executablePathFor: unescapeValue(tryExec)] == nil)
    {
      return nil;
    }
  return [[[GWURLHandler alloc] initWithApplicationPath: nil
                                              arguments: args
                                        desktopFilePath: path] autorelease];
}

/* Expands an Exec line into the argument vector for url.  Returns nil with
 * no problem when the entry cannot take this URL or its program is not
 * installed, and nil with a problem when the line itself is malformed. */
- (NSArray *)argumentsForExec:(NSString *)exec
                        entry:(NSDictionary *)entry
                  desktopFile:(NSString *)path
                          url:(NSURL *)url
                      problem:(NSString **)problem
{
  NSMutableArray *args = [NSMutableArray array];
  NSMutableString *arg = [NSMutableString string];
  NSString *icon = unescapeValue([entry objectForKey: @"Icon"]);
  NSString *name = unescapeValue([entry objectForKey: @"Name"]);
  NSString *urlString = [url absoluteString];
  NSString *program;
  unichar urlCode = 0;
  BOOL inArg = NO;
  BOOL inQuote = NO;
  BOOL literal = NO;
  BOOL standaloneCode = NO;
  BOOL iconCode = NO;
  NSUInteger codes = 0;
  NSUInteger i, n = [exec length];

  for (i = 0; i <= n; i++)
    {
      unichar c = (i < n) ? [exec characterAtIndex: i] : 0;

      if (i == n || (inQuote == NO && (c == ' ' || c == '\t')))
        {
          if (i == n && inQuote)
            {
              *problem = @"a quoted argument in Exec is not terminated";
              return nil;
            }
          if (inArg)
            {
              if ((standaloneCode || iconCode) && (literal || codes > 1))
                {
                  *problem = @"%U, %F or %i in Exec is not an argument of its own";
                  return nil;
                }
              if (iconCode)
                {
                  if ([icon length] > 0)
                    {
                      [args addObject: @"--icon"];
                      [args addObject: icon];
                    }
                }
              else if (literal || [arg length] > 0)
                {
                  [args addObject: [NSString stringWithString: arg]];
                }
            }
          [arg setString: @""];
          inArg = literal = standaloneCode = iconCode = NO;
          codes = 0;
          continue;
        }

      inArg = YES;
      if (c == '"')
        {
          inQuote = !inQuote;
          if (inQuote)
            {
              literal = YES;
            }
          continue;
        }
      if (c == '\\')
        {
          unichar e = (i + 1 < n) ? [exec characterAtIndex: i + 1] : 0;

          if (inQuote && e != '"' && e != '`' && e != '$' && e != '\\')
            {
              *problem = @"a quoted argument in Exec has an invalid escape";
              return nil;
            }
          if (e == 0)
            {
              *problem = @"Exec ends in a backslash";
              return nil;
            }
          [arg appendFormat: @"%C", e];
          literal = YES;
          i++;
          continue;
        }
      if (c != '%')
        {
          [arg appendFormat: @"%C", c];
          literal = YES;
          continue;
        }

      c = (i + 1 < n) ? [exec characterAtIndex: ++i] : 0;
      switch (c)
        {
          case '%':
            [arg appendString: @"%"];
            literal = YES;
            break;
          case 'u': case 'U': case 'f': case 'F':
            if (urlCode != 0)
              {
                *problem = @"Exec has more than one of %f, %F, %u and %U";
                return nil;
              }
            urlCode = c;
            codes++;
            standaloneCode = (c == 'U' || c == 'F');
            if (c == 'f' || c == 'F')
              {
                /* A file-only handler cannot take a remote URL. */
                if ([url isFileURL] == NO)
                  {
                    return nil;
                  }
                [arg appendString: [url path]];
              }
            else
              {
                [arg appendString: urlString];
              }
            break;
          case 'i':
            iconCode = YES;
            codes++;
            break;
          case 'c':
            [arg appendString: (name != nil) ? name : @""];
            codes++;
            break;
          case 'k':
            [arg appendString: path];
            codes++;
            break;
          case 'd': case 'D': case 'n': case 'N': case 'v': case 'm':
            /* Deprecated codes expand to nothing. */
            codes++;
            break;
          default:
            *problem = (c == 0) ? @"Exec ends in a lone %"
              : [NSString stringWithFormat: @"Exec has the unknown field code %%%C", c];
            return nil;
        }
    }

  if ([args count] == 0)
    {
      *problem = @"Exec names no program";
      return nil;
    }
  if (urlCode == 0)
    {
      /* An Exec line without a URL field code gets the URL appended, as
       * GIO does, so such a handler still sees what it was opened for. */
      [args addObject: urlString];
    }

  program = [self executablePathFor: [args objectAtIndex: 0]];
  if (program == nil)
    {
      return nil;
    }
  [args replaceObjectAtIndex: 0 withObject: program];
  return args;
}

@end
