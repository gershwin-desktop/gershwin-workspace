/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWSavedSearch.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { NodeAnd, NodeOr, NodeNot, NodeCompare, NodeRange };
enum { ValString, ValNumber, ValTime };
enum { AttrString, AttrNumber, AttrDate };

/* ---- syntax tree ------------------------------------------------------ */

@interface GWSSValue : NSObject
{
@public
  int type;
  NSString *string;   /* string text, or the function name of a time */
  NSString *arg;      /* argument text of a time function, may be nil */
  NSString *mods;     /* trailing modifier letters of a string */
  double number;
}
@end

@implementation GWSSValue
- (void)dealloc
{
  [string release];
  [arg release];
  [mods release];
  [super dealloc];
}
@end

@interface GWSSNode : NSObject
{
@public
  int kind;
  NSMutableArray *kids;
  NSString *attr;
  NSString *op;
  GWSSValue *value;
  GWSSValue *value2;
}
@end

@implementation GWSSNode
- (void)dealloc
{
  [kids release];
  [attr release];
  [op release];
  [value release];
  [value2 release];
  [super dealloc];
}
@end

/* ---- parser ----------------------------------------------------------- */

@interface GWSSParser : NSObject
{
  NSString *text;
  NSUInteger pos;
  NSString *error;
}
- (id)initWithString:(NSString *)s;
- (GWSSNode *)parse;
- (NSString *)error;
@end

@implementation GWSSParser

- (id)initWithString:(NSString *)s
{
  self = [super init];
  text = [s copy];
  return self;
}

- (void)dealloc
{
  [text release];
  [error release];
  [super dealloc];
}

- (NSString *)error
{
  return error;
}

- (void)fail:(NSString *)what
{
  if (error == nil) {
    error = [[NSString stringWithFormat: @"%@ at position %lu",
              what, (unsigned long)pos] retain];
  }
}

- (unichar)peek
{
  return (pos < [text length]) ? [text characterAtIndex: pos] : 0;
}

- (void)skipSpace
{
  while (pos < [text length]
         && [[NSCharacterSet whitespaceAndNewlineCharacterSet]
             characterIsMember: [text characterAtIndex: pos]]) {
    pos++;
  }
}

- (BOOL)accept:(NSString *)token
{
  [self skipSpace];
  if ([text length] - pos >= [token length]
      && [[text substringWithRange: NSMakeRange(pos, [token length])]
          isEqualToString: token]) {
    pos += [token length];
    return YES;
  }
  return NO;
}

- (GWSSNode *)parse
{
  GWSSNode *n = [self parseOr];

  [self skipSpace];
  if (error == nil && pos < [text length]) {
    [self fail: @"unexpected text"];
  }
  return error ? nil : n;
}

- (GWSSNode *)parseList:(int)kind separator:(NSString *)sep
{
  GWSSNode *first = (kind == NodeOr) ? [self parseAnd] : [self parseUnary];
  GWSSNode *list;

  if (first == nil || [self peekSeparator: sep] == NO) {
    return first;
  }
  list = [[GWSSNode new] autorelease];
  list->kind = kind;
  list->kids = [[NSMutableArray alloc] initWithObjects: first, nil];
  while (error == nil && [self accept: sep]) {
    GWSSNode *next = (kind == NodeOr) ? [self parseAnd] : [self parseUnary];

    if (next == nil) {
      return nil;
    }
    [list->kids addObject: next];
  }
  return error ? nil : list;
}

- (BOOL)peekSeparator:(NSString *)sep
{
  NSUInteger save = pos;
  BOOL r = [self accept: sep];

  pos = save;
  return r;
}

- (GWSSNode *)parseOr
{
  return [self parseList: NodeOr separator: @"||"];
}

- (GWSSNode *)parseAnd
{
  return [self parseList: NodeAnd separator: @"&&"];
}

- (GWSSNode *)parseUnary
{
  [self skipSpace];
  if ([self peek] == '!' && pos + 1 < [text length]
      && [text characterAtIndex: pos + 1] != '=') {
    GWSSNode *n = [[GWSSNode new] autorelease];
    GWSSNode *kid;

    pos++;
    kid = [self parseUnary];
    if (kid == nil) {
      return nil;
    }
    n->kind = NodeNot;
    n->kids = [[NSMutableArray alloc] initWithObjects: kid, nil];
    return n;
  }
  if ([self accept: @"("]) {
    GWSSNode *n = [self parseOr];

    if (n && [self accept: @")"] == NO) {
      [self fail: @"missing )"];
      return nil;
    }
    return n;
  }
  return [self parseComparison];
}

- (NSString *)scanIdentifier
{
  NSUInteger start;

  [self skipSpace];
  start = pos;
  while (pos < [text length]) {
    unichar c = [text characterAtIndex: pos];

    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember: c]
        || c == '_' || c == '.') {
      pos++;
    } else {
      break;
    }
  }
  return (pos > start)
    ? [text substringWithRange: NSMakeRange(start, pos - start)] : nil;
}

- (GWSSNode *)parseComparison
{
  GWSSNode *n = [[GWSSNode new] autorelease];
  NSString *attr = [self scanIdentifier];
  static NSString *ops[] = { @"==", @"!=", @"<=", @">=", @"=", @"<", @">" };
  unsigned i;

  if (attr == nil) {
    [self fail: @"expected an attribute name"];
    return nil;
  }
  if ([attr isEqualToString: @"InRange"] && [self accept: @"("]) {
    n->kind = NodeRange;
    n->attr = [[self scanIdentifier] retain];
    if (n->attr == nil || [self accept: @","] == NO) {
      [self fail: @"malformed InRange"];
      return nil;
    }
    n->value = [[self parseValue] retain];
    if (n->value == nil || [self accept: @","] == NO) {
      [self fail: @"malformed InRange"];
      return nil;
    }
    n->value2 = [[self parseValue] retain];
    if (n->value2 == nil || [self accept: @")"] == NO) {
      [self fail: @"malformed InRange"];
      return nil;
    }
    return n;
  }
  n->kind = NodeCompare;
  n->attr = [attr retain];
  for (i = 0; i < sizeof(ops) / sizeof(ops[0]); i++) {
    if ([self accept: ops[i]]) {
      n->op = [([ops[i] isEqualToString: @"="] ? @"==" : ops[i]) retain];
      break;
    }
  }
  if (n->op == nil) {
    [self fail: @"expected a comparison operator"];
    return nil;
  }
  n->value = [[self parseValue] retain];
  return n->value ? n : nil;
}

- (GWSSValue *)parseValue
{
  GWSSValue *v = [[GWSSValue new] autorelease];
  unichar c;

  [self skipSpace];
  c = [self peek];
  if (c == '"' || c == '\'') {
    NSMutableString *s = [NSMutableString string];
    NSUInteger start;

    pos++;
    while (pos < [text length] && [text characterAtIndex: pos] != c) {
      unichar d = [text characterAtIndex: pos];

      if (d == '\\' && pos + 1 < [text length]) {
        pos++;
        d = [text characterAtIndex: pos];
      }
      [s appendFormat: @"%C", d];
      pos++;
    }
    if (pos >= [text length]) {
      [self fail: @"unterminated string"];
      return nil;
    }
    pos++;
    start = pos;
    while (pos < [text length]
           && [[NSCharacterSet letterCharacterSet]
               characterIsMember: [text characterAtIndex: pos]]) {
      pos++;
    }
    v->type = ValString;
    v->string = [s copy];
    v->mods = [[text substringWithRange: NSMakeRange(start, pos - start)]
               retain];
    return v;
  }
  if (c == '$') {
    NSString *name;

    pos++;
    name = [self scanIdentifier];
    if (name == nil || [name hasPrefix: @"time."] == NO) {
      [self fail: @"unknown variable"];
      return nil;
    }
    v->type = ValTime;
    v->string = [[name substringFromIndex: 5] retain];
    if ([self peek] == '(') {
      NSUInteger close;

      pos++;
      close = pos;
      while (close < [text length] && [text characterAtIndex: close] != ')') {
        close++;
      }
      if (close >= [text length]) {
        [self fail: @"missing ) after time function"];
        return nil;
      }
      v->arg = [[text substringWithRange: NSMakeRange(pos, close - pos)]
                retain];
      pos = close + 1;
    }
    return v;
  }
  if (c == '-' || c == '+' || (c >= '0' && c <= '9')) {
    NSUInteger start = pos;

    pos++;
    while (pos < [text length]) {
      unichar d = [text characterAtIndex: pos];

      if ((d >= '0' && d <= '9') || d == '.') {
        pos++;
      } else {
        break;
      }
    }
    v->type = ValNumber;
    v->number = [[text substringWithRange: NSMakeRange(start, pos - start)]
                 doubleValue];
    return v;
  }
  [self fail: @"expected a value"];
  return nil;
}

@end

/* ---- attribute tables ------------------------------------------------- */

typedef struct {
  const char *spotlight;
  const char *mdk;
  int type;
  const char *note;
} AttrMap;

/* Every row names an attribute that exists in MDKit's attributes.plist
 * (the test suite checks that). The note, if any, is a known difference. */
static const AttrMap attrMap[] = {
  { "kMDItemFSName", "GSMDItemFSName", AttrString, NULL },
  { "kMDItemDisplayName", "GSMDItemFSName", AttrString,
    "the display name is searched as the file name" },
  { "kMDItemFSSize", "GSMDItemFSSize", AttrNumber, NULL },
  { "kMDItemFSContentChangeDate", "GSMDItemFSModificationDate", AttrDate,
    NULL },
  { "kMDItemFSCreationDate", "GSMDItemFSCreationDate", AttrDate, NULL },
  { "kMDItemTextContent", "GSMDItemTextContent", AttrString, NULL },
  { "kMDItemFinderComment", "GSMDItemFinderComment", AttrString, NULL },
  { "kMDItemTitle", "GSMDItemTitle", AttrString, NULL },
  { "kMDItemAuthors", "GSMDItemAuthors", AttrString, NULL },
  { "kMDItemKeywords", "GSMDItemKeywords", AttrString, NULL },
  { "kMDItemDescription", "GSMDItemDescription", AttrString, NULL },
  { "kMDItemAlbum", "GSMDItemAlbum", AttrString, NULL },
  { "kMDItemComposer", "GSMDItemComposer", AttrString, NULL },
  { "kMDItemMusicalGenre", "GSMDItemMusicalGenre", AttrString, NULL },
  { "kMDItemPixelHeight", "GSMDItemPixelHeight", AttrNumber, NULL },
  { "kMDItemPixelWidth", "GSMDItemPixelWidth", AttrNumber, NULL },
  { "kMDItemNumberOfPages", "GSMDItemNumberOfPages", AttrNumber, NULL },
  { "kMDItemDurationSeconds", "GSMDItemDurationSeconds", AttrNumber, NULL },
};

#define ATTR_COUNT (sizeof(attrMap) / sizeof(attrMap[0]))

static const AttrMap *
attrForSpotlight(NSString *name)
{
  unsigned i;

  for (i = 0; i < ATTR_COUNT; i++) {
    if (strcmp(attrMap[i].spotlight, [name UTF8String]) == 0) {
      return &attrMap[i];
    }
  }
  return NULL;
}

/* First row per MDKit name is the canonical Spotlight spelling. */
static const AttrMap *
attrForMDK(NSString *name)
{
  unsigned i;

  for (i = 0; i < ATTR_COUNT; i++) {
    if (strcmp(attrMap[i].mdk, [name UTF8String]) == 0) {
      return &attrMap[i];
    }
  }
  return NULL;
}

typedef struct {
  const char *uti;
  BOOL tree;           /* matches the whole branch, not one leaf type */
  const char *fstype;  /* MDKit file type, or NULL */
  const char *exts;    /* space separated lower case extensions */
} UTIMap;

static const UTIMap utiMap[] = {
  { "public.folder", YES, "NSDirectoryFileType", NULL },
  { "public.directory", YES, "NSDirectoryFileType", NULL },
  { "com.apple.application", YES, "NSApplicationFileType", NULL },
  { "com.apple.application-bundle", YES, "NSApplicationFileType", NULL },
  { "public.image", YES, NULL,
    "png jpg jpeg jpe gif tif tiff bmp ico icns svg webp xpm xbm tga psd" },
  { "public.jpeg", NO, NULL, "jpg jpeg jpe" },
  { "public.png", NO, NULL, "png" },
  { "public.tiff", NO, NULL, "tif tiff" },
  { "com.compuserve.gif", NO, NULL, "gif" },
  { "com.microsoft.bmp", NO, NULL, "bmp" },
  { "public.audio", YES, NULL,
    "mp3 m4a aac wav aif aiff aifc flac ogg oga opus wma mid midi" },
  { "public.mp3", NO, NULL, "mp3" },
  { "public.movie", YES, NULL,
    "mov mp4 m4v avi mkv mpg mpeg webm ogv wmv flv 3gp" },
  { "public.mpeg-4", NO, NULL, "mp4 m4v" },
  { "com.apple.quicktime-movie", NO, NULL, "mov" },
  { "com.adobe.pdf", NO, NULL, "pdf" },
  { "public.plain-text", YES, NULL, "txt text" },
  { "public.source-code", YES, NULL,
    "c h m mm cpp cc cxx hpp java py rb pl sh js ts swift go rs" },
};

#define UTI_COUNT (sizeof(utiMap) / sizeof(utiMap[0]))

/* ---- time ------------------------------------------------------------- */

static NSDate *
dateAdding(NSDate *d, int years, int months, int days)
{
  NSDateComponents *c = [[NSDateComponents new] autorelease];

  [c setYear: years];
  [c setMonth: months];
  [c setDay: days];
  return [[NSCalendar currentCalendar] dateByAddingComponents: c
                                                       toDate: d
                                                      options: 0];
}

static NSDate *
startOf(NSDate *d, unsigned unitsKept)
{
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDateComponents *c = [cal components: unitsKept fromDate: d];

  return [cal dateFromComponents: c];
}

/* ISO 8601 date or date and time; a missing zone means local time. */
static BOOL
parseISO(NSString *s, double *out)
{
  int y = 0, mo = 0, d = 0, h = 0, mi = 0, sec = 0;
  const char *p = [[s stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]] UTF8String];
  int n = 0, zoneSecs = 0;
  BOOL utc = NO, haveZone = NO;
  NSDateComponents *c;
  NSCalendar *cal;
  NSDate *date;

  if (sscanf(p, "%d-%d-%d%n", &y, &mo, &d, &n) < 3) {
    return NO;
  }
  p += n;
  if (*p == 'T' || *p == ' ') {
    p++;
    if (sscanf(p, "%d:%d:%d%n", &h, &mi, &sec, &n) < 2) {
      return NO;
    }
    if (sscanf(p, "%d:%d%n", &h, &mi, &n) == 2 && p[n] == ':') {
      sscanf(p, "%d:%d:%d%n", &h, &mi, &sec, &n);
    }
    p += n;
  }
  if (*p == 'Z') {
    utc = YES;
    p++;
  } else if (*p == '+' || *p == '-') {
    int zh = 0, zm = 0;

    if (sscanf(p + 1, "%d:%d", &zh, &zm) < 1) {
      return NO;
    }
    zoneSecs = (zh * 3600 + zm * 60) * (*p == '-' ? -1 : 1);
    haveZone = YES;
    p = "";
  }
  if (*p != 0) {
    return NO;
  }
  c = [[NSDateComponents new] autorelease];
  [c setYear: y]; [c setMonth: mo]; [c setDay: d];
  [c setHour: h]; [c setMinute: mi]; [c setSecond: sec];
  cal = [[[NSCalendar alloc] initWithCalendarIdentifier: NSGregorianCalendar]
         autorelease];
  if (utc || haveZone) {
    [cal setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT:
                       utc ? 0 : zoneSecs]];
  } else {
    [cal setTimeZone: [NSTimeZone defaultTimeZone]];
  }
  date = [cal dateFromComponents: c];
  if (date == nil) {
    return NO;
  }
  *out = [date timeIntervalSinceReferenceDate];
  return YES;
}

/* Seconds since the reference date, which is what MDKit stores. The offset
 * unit follows the function: seconds for now, days for today and yesterday,
 * weeks, months and years for this_week, this_month and this_year. */
static BOOL
evalTime(GWSSValue *v, NSDate *now, double *out)
{
  NSString *f = v->string;
  double off = v->arg ? [v->arg doubleValue] : 0;
  NSDate *d;

  if ([f isEqualToString: @"iso"]) {
    return v->arg && parseISO(v->arg, out);
  }
  if ([f isEqualToString: @"now"]) {
    *out = [now timeIntervalSinceReferenceDate] + off;
    return YES;
  }
  if ([f isEqualToString: @"today"] || [f isEqualToString: @"yesterday"]) {
    d = startOf(now, NSYearCalendarUnit | NSMonthCalendarUnit
                | NSDayCalendarUnit);
    d = dateAdding(d, 0, 0, (int)off - ([f isEqualToString: @"yesterday"]
                                        ? 1 : 0));
  } else if ([f isEqualToString: @"this_week"]) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger wd = [[cal components: NSWeekdayCalendarUnit fromDate: now]
                    weekday];
    NSInteger back = (wd - (NSInteger)[cal firstWeekday] + 7) % 7;

    d = startOf(now, NSYearCalendarUnit | NSMonthCalendarUnit
                | NSDayCalendarUnit);
    d = dateAdding(d, 0, 0, (int)(off * 7 - back));
  } else if ([f isEqualToString: @"this_month"]) {
    d = startOf(now, NSYearCalendarUnit | NSMonthCalendarUnit);
    d = dateAdding(d, 0, (int)off, 0);
  } else if ([f isEqualToString: @"this_year"]) {
    d = startOf(now, NSYearCalendarUnit);
    d = dateAdding(d, (int)off, 0, 0);
  } else {
    return NO;
  }
  *out = [d timeIntervalSinceReferenceDate];
  return YES;
}

static NSString *
numberText(double n)
{
  if (n == (double)(long long)n) {
    return [NSString stringWithFormat: @"%lld", (long long)n];
  }
  return [NSString stringWithFormat: @"%.15g", n];
}

/* ---- translation ------------------------------------------------------ */

@interface GWSavedSearch (Translation)
- (NSString *)translate:(GWSSNode *)n negated:(BOOL)neg at:(NSDate *)now;
- (NSString *)translateCompare:(GWSSNode *)n negated:(BOOL)neg at:(NSDate *)now;
- (NSString *)translateRange:(GWSSNode *)n negated:(BOOL)neg at:(NSDate *)now;
- (NSString *)translateContentType:(GWSSNode *)n negated:(BOOL)neg;
- (void)refuse:(NSString *)what;
- (void)note:(NSString *)what;
@end

static NSString *
inverseOp(NSString *op)
{
  if ([op isEqualToString: @"=="]) return @"!=";
  if ([op isEqualToString: @"!="]) return @"==";
  if ([op isEqualToString: @"<"]) return @">=";
  if ([op isEqualToString: @">="]) return @"<";
  if ([op isEqualToString: @">"]) return @"<=";
  return @">";
}

@implementation GWSavedSearch (Translation)

- (void)refuse:(NSString *)what
{
  if ([unsupported containsObject: what] == NO) {
    [unsupported addObject: what];
  }
}

- (void)note:(NSString *)what
{
  if ([notes containsObject: what] == NO) {
    [notes addObject: what];
  }
}

- (NSString *)translate:(GWSSNode *)n negated:(BOOL)neg at:(NSDate *)now
{
  NSMutableArray *parts;
  BOOL failed = NO;
  NSUInteger i;

  switch (n->kind) {
    case NodeNot:
      return [self translate: [n->kids objectAtIndex: 0]
                     negated: !neg at: now];
    case NodeCompare:
      return [self translateCompare: n negated: neg at: now];
    case NodeRange:
      return [self translateRange: n negated: neg at: now];
    default:
      break;
  }
  parts = [NSMutableArray array];
  for (i = 0; i < [n->kids count]; i++) {
    NSString *s = [self translate: [n->kids objectAtIndex: i]
                          negated: neg at: now];

    if (s == nil) {
      failed = YES;
    } else {
      [parts addObject: s];
    }
  }
  if (failed) {
    return nil;
  }
  /* De Morgan: MDKit has no NOT, only inverted comparisons. */
  return [NSString stringWithFormat: @"(%@)",
          [parts componentsJoinedByString:
           ((n->kind == NodeAnd) != neg) ? @" && " : @" || "]];
}

- (NSString *)translateContentType:(GWSSNode *)n negated:(BOOL)neg
{
  BOOL leafOnly = [n->attr isEqualToString: @"kMDItemContentType"];
  NSString *op = neg ? inverseOp(n->op) : n->op;
  NSString *shown = [NSString stringWithFormat: @"%@ %@ '%@'", n->attr,
                     n->op, n->value->string];
  unsigned i;

  if (n->value->type != ValString
      || ([n->op isEqualToString: @"=="] == NO
          && [n->op isEqualToString: @"!="] == NO)) {
    [self refuse: shown];
    return nil;
  }
  for (i = 0; i < UTI_COUNT; i++) {
    if (strcmp(utiMap[i].uti, [n->value->string UTF8String]) == 0
        && (utiMap[i].tree == NO || leafOnly == NO
            || strcmp(utiMap[i].uti, "public.folder") == 0
            || strcmp(utiMap[i].uti, "com.adobe.pdf") == 0)) {
      NSMutableArray *parts = [NSMutableArray array];
      BOOL eq = [op isEqualToString: @"=="];

      if (utiMap[i].fstype) {
        return [NSString stringWithFormat: @"GSMDItemFSType %@ \"%s\"", op,
                utiMap[i].fstype];
      }
      for (NSString *e in [[NSString stringWithUTF8String: utiMap[i].exts]
                           componentsSeparatedByString: @" "]) {
        [parts addObject: [NSString stringWithFormat:
                           @"GSMDItemFSExtension %@ \"%@\"", op, e]];
      }
      [self note: @"content types are matched by file name extension"];
      return [NSString stringWithFormat: @"(%@)",
              [parts componentsJoinedByString: eq ? @" || " : @" && "]];
    }
  }
  [self refuse: shown];
  return nil;
}

- (NSString *)translateCompare:(GWSSNode *)n negated:(BOOL)neg at:(NSDate *)now
{
  const AttrMap *m;
  NSString *op = neg ? inverseOp(n->op) : n->op;
  GWSSValue *v = n->value;
  NSString *desc;

  if ([n->attr isEqualToString: @"kMDItemContentTypeTree"]
      || [n->attr isEqualToString: @"kMDItemContentType"]) {
    return [self translateContentType: n negated: neg];
  }
  desc = [NSString stringWithFormat: @"%@ %@ %@", n->attr, n->op,
          v->type == ValString ? [NSString stringWithFormat: @"\"%@\"",
                                  v->string]
          : v->type == ValNumber ? numberText(v->number)
          : [NSString stringWithFormat: @"$time.%@", v->string]];
  m = attrForSpotlight(n->attr);
  if (m == NULL) {
    [self refuse: [NSString stringWithFormat:
                   @"%@ (attribute not indexed)", desc]];
    return nil;
  }
  if (m->note) {
    [self note: [NSString stringWithUTF8String: m->note]];
  }
  if (m->type == AttrString) {
    BOOL insens;
    NSString *s = v->string;

    if (v->type != ValString) {
      [self refuse: desc];
      return nil;
    }
    if ([op isEqualToString: @"=="] == NO
        && [op isEqualToString: @"!="] == NO) {
      [self refuse: [NSString stringWithFormat:
                     @"%@ (text cannot be ordered)", desc]];
      return nil;
    }
    insens = ([v->mods rangeOfString: @"c"].location != NSNotFound);
    /* MDKit hands the text to SQLite LIKE/GLOB, where these are wildcards
     * of their own that Spotlight does not have. */
    if ([s rangeOfString: @"\""].location != NSNotFound
        || [s rangeOfString: @"%"].location != NSNotFound
        || [s rangeOfString: @"?"].location != NSNotFound
        || [s rangeOfString: @"["].location != NSNotFound
        || (insens && [s rangeOfString: @"_"].location != NSNotFound)) {
      [self refuse: [NSString stringWithFormat:
                     @"%@ (character not searchable)", desc]];
      return nil;
    }
    if ([v->mods rangeOfString: @"d"].location != NSNotFound
        || [v->mods rangeOfString: @"w"].location != NSNotFound) {
      [self note: @"diacritic and word matching modifiers are not applied"];
    }
    return [NSString stringWithFormat: @"%s %@ \"%@\"%@", m->mdk, op, s,
            insens ? @"c" : @""];
  }
  if (m->type == AttrNumber) {
    if (v->type != ValNumber) {
      [self refuse: desc];
      return nil;
    }
    return [NSString stringWithFormat: @"%s %@ %@", m->mdk, op,
            numberText(v->number)];
  }
  {
    double secs = 0;

    if (v->type == ValNumber) {
      secs = v->number;
    } else if (v->type != ValTime || evalTime(v, now, &secs) == NO) {
      [self refuse: [NSString stringWithFormat:
                     @"%@ (date not understood)", desc]];
      return nil;
    }
    if (v->type == ValTime && [v->string isEqualToString: @"iso"] == NO) {
      [self note: @"relative dates are resolved when the search is opened"];
    }
    return [NSString stringWithFormat: @"%s %@ %.0f", m->mdk, op, secs];
  }
}

- (NSString *)translateRange:(GWSSNode *)n negated:(BOOL)neg at:(NSDate *)now
{
  GWSSNode *lo = [[GWSSNode new] autorelease];
  GWSSNode *hi = [[GWSSNode new] autorelease];
  GWSSNode *both = [[GWSSNode new] autorelease];

  lo->kind = hi->kind = NodeCompare;
  lo->attr = [n->attr retain];
  hi->attr = [n->attr retain];
  lo->op = [@">=" retain];
  hi->op = [@"<=" retain];
  lo->value = [n->value retain];
  hi->value = [n->value2 retain];
  both->kind = NodeAnd;
  both->kids = [[NSMutableArray alloc] initWithObjects: lo, hi, nil];
  return [self translate: both negated: neg at: now];
}

@end

/* ---- writing ---------------------------------------------------------- */

static NSString *
spotlightValue(GWSSValue *v, const AttrMap *m, NSString **why)
{
  if (m->type == AttrString) {
    NSString *mods = [v->mods rangeOfString: @"c"].location != NSNotFound
      ? @"c" : @"";

    if (v->type != ValString) {
      *why = @"text expected";
      return nil;
    }
    return [NSString stringWithFormat: @"\"%@\"%@", v->string, mods];
  }
  if (v->type != ValNumber) {
    *why = @"number expected";
    return nil;
  }
  if (m->type == AttrNumber) {
    return numberText(v->number);
  }
  {
    time_t t = (time_t)(v->number + NSTimeIntervalSince1970);
    struct tm tmv;
    char buf[40];

    gmtime_r(&t, &tmv);
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tmv);
    return [NSString stringWithFormat: @"$time.iso(%s)", buf];
  }
}

static NSString *
spotlightForNode(GWSSNode *n, NSString **why)
{
  const AttrMap *m;
  NSString *val;

  if (n->kind == NodeAnd || n->kind == NodeOr) {
    NSMutableArray *parts = [NSMutableArray array];
    GWSSNode *k;

    for (k in n->kids) {
      NSString *s = spotlightForNode(k, why);

      if (s == nil) {
        return nil;
      }
      [parts addObject: s];
    }
    return [NSString stringWithFormat: @"(%@)", [parts
            componentsJoinedByString: n->kind == NodeAnd ? @" && " : @" || "]];
  }
  if (n->kind != NodeCompare) {
    *why = @"negation";
    return nil;
  }
  if ([n->attr isEqualToString: @"GSMDItemFSType"]) {
    NSString *uti = [n->value->string isEqualToString: @"NSDirectoryFileType"]
      ? @"public.folder"
      : [n->value->string isEqualToString: @"NSApplicationFileType"]
      ? @"com.apple.application" : nil;

    if (uti == nil || n->value->type != ValString) {
      *why = [NSString stringWithFormat: @"file type %@", n->value->string];
      return nil;
    }
    return [NSString stringWithFormat: @"kMDItemContentTypeTree %@ '%@'",
            n->op, uti];
  }
  if ([n->attr isEqualToString: @"GSMDItemFSExtension"]) {
    if (n->value->type != ValString) {
      *why = @"file name extension";
      return nil;
    }
    return [NSString stringWithFormat: @"kMDItemFSName %@ \"*.%@\"c", n->op,
            n->value->string];
  }
  m = attrForMDK(n->attr);
  if (m == NULL) {
    *why = [NSString stringWithFormat: @"attribute %@", n->attr];
    return nil;
  }
  val = spotlightValue(n->value, m, why);
  if (val == nil) {
    *why = [NSString stringWithFormat: @"%@: %@", n->attr, *why];
    return nil;
  }
  return [NSString stringWithFormat: @"%s %@ %@",
          m->type == AttrString && strcmp(m->spotlight, "kMDItemDisplayName") == 0
          ? "kMDItemFSName" : m->spotlight, n->op, val];
}

/* ---- scopes ----------------------------------------------------------- */

@implementation GWSavedSearch

- (void)dealloc
{
  [rawQuery release];
  [scopes release];
  [unsupported release];
  [notes release];
  [paths release];
  [super dealloc];
}

- (id)initWithRawQuery:(NSString *)raw scopes:(NSArray *)sc
{
  self = [super init];
  rawQuery = [raw copy];
  scopes = [(sc ? sc : [NSArray array]) copy];
  unsupported = [NSMutableArray new];
  notes = [NSMutableArray new];
  return self;
}

+ (GWSavedSearch *)savedSearchWithRawQuery:(NSString *)raw
                                    scopes:(NSArray *)sc
{
  return [[[self alloc] initWithRawQuery: raw scopes: sc] autorelease];
}

+ (GWSavedSearch *)savedSearchWithContentsOfFile:(NSString *)path
                                           error:(NSString **)error
{
  NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile: path];
  NSDictionary *rqd;
  NSDictionary *crit;
  NSString *raw;
  NSArray *sc;
  GWSavedSearch *s;
  id ver;

  if ([plist isKindOfClass: [NSDictionary class]] == NO) {
    if (error) {
      *error = @"not a property list dictionary";
    }
    return nil;
  }
  ver = [plist objectForKey: @"CompatibleVersion"];
  if (ver && [ver intValue] > 1) {
    if (error) {
      *error = [NSString stringWithFormat:
                @"saved search format version %@ is newer than supported",
                ver];
    }
    return nil;
  }
  rqd = [plist objectForKey: @"RawQueryDict"];
  if ([rqd isKindOfClass: [NSDictionary class]] == NO) {
    rqd = nil;
  }
  crit = [plist objectForKey: @"SearchCriteria"];
  if ([crit isKindOfClass: [NSDictionary class]] == NO) {
    crit = nil;
  }
  raw = [plist objectForKey: @"RawQuery"];
  if ([raw isKindOfClass: [NSString class]] == NO) {
    raw = [rqd objectForKey: @"RawQuery"];
  }
  if ([raw isKindOfClass: [NSString class]] == NO) {
    if (error) {
      *error = @"the file has no RawQuery";
    }
    return nil;
  }
  sc = [rqd objectForKey: @"SearchScopes"];
  if ([sc isKindOfClass: [NSArray class]] == NO) {
    sc = [crit objectForKey: @"FXScopeArrayOfPaths"];
  }
  if ([sc isKindOfClass: [NSArray class]] == NO) {
    sc = nil;
  }
  s = [self savedSearchWithRawQuery: raw scopes: sc];
  s->finderFilesOnly = [[rqd objectForKey: @"FinderFilesOnly"] boolValue];
  s->userFilesOnly = [[rqd objectForKey: @"UserFilesOnly"] boolValue];
  return s;
}

- (NSString *)rawQuery { return rawQuery; }
- (NSArray *)scopes { return scopes; }
- (BOOL)finderFilesOnly { return finderFilesOnly; }
- (BOOL)userFilesOnly { return userFilesOnly; }

- (void)resolveScopes
{
  NSMutableArray *dirs = [NSMutableArray array];
  BOOL everywhere = ([scopes count] == 0);
  NSString *sc;

  for (sc in scopes) {
    if ([sc isEqualToString: @"kMDQueryScopeComputer"]
        || [sc isEqualToString: @"kMDQueryScopeComputerIndexed"]) {
      everywhere = YES;
    } else if ([sc isEqualToString: @"kMDQueryScopeHome"]) {
      [dirs addObject: NSHomeDirectory()];
    } else if ([sc hasPrefix: @"/"]) {
      [dirs addObject: [sc stringByStandardizingPath]];
    } else {
      [self refuse: [NSString stringWithFormat:
                     @"search location %@", sc]];
    }
  }
  [paths release];
  paths = everywhere ? nil : [dirs copy];
  if (finderFilesOnly) {
    [self note: @"the Finder-files-only option is not applied"];
  }
  if (userFilesOnly) {
    [self note: @"the user-files-only option is not applied"];
  }
}

- (NSArray *)searchPaths
{
  [self mdkQueryStringAtDate: [NSDate date]];
  return paths;
}

- (NSString *)mdkQueryStringAtDate:(NSDate *)date
{
  GWSSParser *p;
  GWSSNode *root;
  NSString *q;

  [unsupported removeAllObjects];
  [notes removeAllObjects];
  [self resolveScopes];
  p = [[[GWSSParser alloc] initWithString: rawQuery] autorelease];
  root = [p parse];
  if (root == nil) {
    [self refuse: [NSString stringWithFormat: @"query not understood (%@)",
                   [p error]]];
    return nil;
  }
  q = [self translate: root negated: NO at: date];
  if ([unsupported count]) {
    return nil;
  }
  return q;
}

- (NSArray *)unsupportedTerms
{
  [self mdkQueryStringAtDate: [NSDate date]];
  return unsupported;
}

- (NSArray *)notes
{
  [self mdkQueryStringAtDate: [NSDate date]];
  return notes;
}

- (NSString *)statusText
{
  NSArray *u = [self unsupportedTerms];
  NSArray *n = [self notes];

  if ([u count]) {
    return [NSString stringWithFormat:
            NSLocalizedString(@"This smart folder cannot be searched here. "
                              @"Not supported: %@", @""),
            [u componentsJoinedByString: @"; "]];
  }
  if ([n count]) {
    return [NSString stringWithFormat:
            NSLocalizedString(@"Approximated: %@", @""),
            [n componentsJoinedByString: @"; "]];
  }
  return nil;
}

+ (GWSavedSearch *)savedSearchWithMDKitQuery:(NSString *)mdkQuery
                                 searchPaths:(NSArray *)searchPaths
                                       error:(NSString **)error
{
  GWSSParser *p = [[[GWSSParser alloc] initWithString: mdkQuery] autorelease];
  GWSSNode *root = [p parse];
  NSString *why = nil;
  NSString *raw;

  if (root == nil) {
    if (error) {
      *error = [p error];
    }
    return nil;
  }
  raw = spotlightForNode(root, &why);
  if (raw == nil) {
    if (error) {
      *error = [NSString stringWithFormat:
                @"no Spotlight equivalent for %@", why];
    }
    return nil;
  }
  return [self savedSearchWithRawQuery: raw
                                scopes: [searchPaths count] ? searchPaths
                                : [NSArray arrayWithObject:
                                   @"kMDQueryScopeComputer"]];
}

- (NSDictionary *)propertyList
{
  NSDictionary *inner = [NSDictionary dictionaryWithObjectsAndKeys:
    rawQuery, @"RawQuery",
    scopes, @"SearchScopes",
    [NSNumber numberWithBool: finderFilesOnly], @"FinderFilesOnly",
    [NSNumber numberWithBool: userFilesOnly], @"UserFilesOnly", nil];
  NSDictionary *crit = [NSDictionary dictionaryWithObjectsAndKeys:
    scopes, @"FXScopeArrayOfPaths",
    [NSArray array], @"FXCriteriaSlices", nil];

  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 1], @"CompatibleVersion",
    rawQuery, @"RawQuery",
    inner, @"RawQueryDict",
    crit, @"SearchCriteria", nil];
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)flag
{
  return [[self propertyList] writeToFile: path atomically: flag];
}

@end
