/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#include <math.h>

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "GWLookInsidePreviewView.h"
#import "GWLookInsideGeometry.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "AppearanceMetrics.h"

#define LIString(key, comment) NSLocalizedStringFromTable(key, @"LookInside", comment)

NSString * const GWLookInsideInfoName = @"name";
NSString * const GWLookInsideInfoKind = @"kind";
NSString * const GWLookInsideInfoSize = @"size";
NSString * const GWLookInsideInfoItems = @"items";
NSString * const GWLookInsideInfoModified = @"modified";

/* A text file is shown from its start; past this a preview would only
 * cost time and memory for lines nobody scrolls to in a preview. */
static const NSUInteger kTextPreviewLength = 512 * 1024;

/* Pages of a PDF rendered for the preview; a preview is for recognising a
 * document, the application is for reading all of it. */
static const NSUInteger kPDFPreviewPages = 20;

/* Picture sizes of the info layout. */
static const CGFloat kFullPictureMaximum = 256.0;

/* Text in the small picture of a preview column: smaller than a text
 * view's own, so a column shows a page rather than a few words. */
static const CGFloat kCompactTextSize = 9.0;
static const CGFloat kPictureMinimum = 16.0;
static const CGFloat kFactLineHeight = 17.0;
static const CGFloat kNameHeight = 18.0;

static NSArray *
RunLoopModes(void)
{
  return [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                  NSEventTrackingRunLoopMode, nil];
}


/* ------------------------------------------------------------------ */
/* A folder's size, added up on a thread of its own so that a big tree
 * never stalls the preview; the result is dropped when the view has
 * moved on to another item in the meantime. */

@interface GWLookInsideFolderSizer : NSObject
{
  NSString *_path;
  id _target;                /* not retained: the view cancels before it goes */
  volatile BOOL _cancelled;
}
- (id)initWithPath:(NSString *)path target:(id)target;
- (void)start;
- (void)cancel;
@end

@interface NSObject (GWLookInsideFolderSizerTarget)
- (void)folderSizer:(GWLookInsideFolderSizer *)sizer didFinishWithSize:(unsigned long long)size;
@end

@implementation GWLookInsideFolderSizer

- (id)initWithPath:(NSString *)path target:(id)target
{
  self = [super init];
  if (self != nil)
    {
      ASSIGN(_path, path);
      _target = target;
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_path);
  [super dealloc];
}

- (void)start
{
  [NSThread detachNewThreadSelector: @selector(run) toTarget: self withObject: nil];
}

- (void)cancel
{
  _cancelled = YES;
  _target = nil;
}

- (void)run
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  /* NSFileManager's shared instance belongs to the main thread. */
  NSFileManager *fm = [[NSFileManager new] autorelease];
  NSDirectoryEnumerator *e = [fm enumeratorAtPath: _path];
  unsigned long long total = 0;
  NSUInteger n = 0;

  while (!_cancelled && [e nextObject] != nil)
    {
      NSDictionary *attrs = [e fileAttributes];

      if ([[attrs fileType] isEqual: NSFileTypeRegular])
        {
          total += [attrs fileSize];
        }
      if (++n % 512 == 0)
        {
          [pool release];
          pool = [NSAutoreleasePool new];
        }
    }

  if (!_cancelled)
    {
      [self performSelectorOnMainThread: @selector(finish:)
                             withObject: [NSNumber numberWithUnsignedLongLong: total]
                          waitUntilDone: NO
                                  modes: RunLoopModes()];
    }
  [pool release];
}

- (void)finish:(NSNumber *)size
{
  if (!_cancelled)
    {
      [_target folderSizer: self didFinishWithSize: [size unsignedLongLongValue]];
    }
}

@end


/* ------------------------------------------------------------------ */
/* The first pages of a PDF as pictures, made by poppler's pdftoppm, which
 * this AppKit cannot do itself (NSImage reads no PDF here).  Without
 * pdftoppm on the PATH a PDF keeps the icon-and-facts preview. */

@interface GWLookInsidePDFRenderer : NSObject
{
  NSTask *_task;
  NSString *_outputDir;
  id _target;                /* not retained: the view cancels before it goes */
}
- (id)initWithTarget:(id)target;
- (BOOL)startWithPath:(NSString *)path;
- (void)cancel;
@end

@interface NSObject (GWLookInsidePDFRendererTarget)
- (void)pdfRenderer:(GWLookInsidePDFRenderer *)renderer didRenderPages:(NSArray *)pages;
@end

@implementation GWLookInsidePDFRenderer

static NSString *
PdftoppmPath(void)
{
  NSString *pathVar = [[[NSProcessInfo processInfo] environment] objectForKey: @"PATH"];
  NSEnumerator *e = [[pathVar componentsSeparatedByString: @":"] objectEnumerator];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir;

  while ((dir = [e nextObject]) != nil)
    {
      NSString *candidate = [dir stringByAppendingPathComponent: @"pdftoppm"];

      if ([dir length] > 0 && [fm isExecutableFileAtPath: candidate])
        {
          return candidate;
        }
    }
  return nil;
}

- (id)initWithTarget:(id)target
{
  self = [super init];
  if (self != nil)
    {
      _target = target;
    }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  RELEASE(_task);
  RELEASE(_outputDir);
  [super dealloc];
}

- (BOOL)startWithPath:(NSString *)path
{
  static unsigned long counter = 0;
  NSString *tool = PdftoppmPath();
  NSFileManager *fm = [NSFileManager defaultManager];

  if (tool == nil)
    {
      return NO;
    }

  {
    NSString *name = [NSString stringWithFormat: @"GWLookInside-%d-%lu", [[NSProcessInfo processInfo] processIdentifier], ++counter];

    ASSIGN(_outputDir, [NSTemporaryDirectory() stringByAppendingPathComponent: name]);
  }
  if (![fm createDirectoryAtPath: _outputDir withIntermediateDirectories: YES
                      attributes: nil error: NULL])
    {
      return NO;
    }

  _task = [NSTask new];
  [_task setLaunchPath: tool];
  [_task setArguments: [NSArray arrayWithObjects:
    @"-png", @"-r", @"96", @"-f", @"1",
    @"-l", [NSString stringWithFormat: @"%lu", (unsigned long)kPDFPreviewPages],
    path, [_outputDir stringByAppendingPathComponent: @"page"], nil]];
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(taskDidTerminate:)
                                               name: NSTaskDidTerminateNotification
                                             object: _task];
  [_task launch];
  return YES;
}

- (void)removeOutput
{
  if (_outputDir != nil)
    {
      [[NSFileManager defaultManager] removeFileAtPath: _outputDir handler: nil];
      DESTROY(_outputDir);
    }
}

- (void)taskDidTerminate:(NSNotification *)note
{
  NSMutableArray *pages = [NSMutableArray array];
  NSArray *names;
  NSUInteger i;

  [[NSNotificationCenter defaultCenter] removeObserver: self];
  if (_target == nil)
    {
      [self removeOutput];
      return;
    }

  /* pdftoppm pads the page number to the width of the last page number,
   * so the names sort in page order. */
  names = [[[NSFileManager defaultManager] directoryContentsAtPath: _outputDir]
            sortedArrayUsingSelector: @selector(compare:)];
  for (i = 0; [_task terminationStatus] == 0 && i < [names count]; i++)
    {
      NSString *file = [_outputDir stringByAppendingPathComponent: [names objectAtIndex: i]];
      NSImage *page = [[NSImage alloc] initWithData: [NSData dataWithContentsOfFile: file]];

      if (page != nil)
        {
          [pages addObject: page];
          RELEASE(page);
        }
    }
  [self removeOutput];

  if ([pages count] > 0)
    {
      [_target pdfRenderer: self didRenderPages: pages];
    }
}

- (void)cancel
{
  _target = nil;
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  if ([_task isRunning])
    {
      [_task terminate];
      [_task waitUntilExit];
    }
  [self removeOutput];
}

@end


/* ------------------------------------------------------------------ */

/* Document view of the PDF pages: flipped so the first page is at the
 * top and the scroll view starts there. */
@interface GWLookInsidePageStack : NSView
@end

@implementation GWLookInsidePageStack

- (BOOL)isFlipped
{
  return YES;
}

/* Pages centered in the clip view's width, one below the other, scaled
 * down only when wider than that width. */
- (void)layoutPagesForWidth:(CGFloat)width
{
  NSEnumerator *e = [[self subviews] objectEnumerator];
  NSImageView *pageView;
  CGFloat y = METRICS_SPACE_12;

  while ((pageView = [e nextObject]) != nil)
    {
      NSSize size = [[pageView image] size];
      CGFloat w = MIN(size.width, MAX(width - 2 * METRICS_SPACE_12, 1));
      CGFloat h = floor(size.height * w / MAX(size.width, 1));

      [pageView setFrame: NSMakeRect(floor((width - w) / 2), y, w, h)];
      y += h + METRICS_SPACE_12;
    }
  [self setFrameSize: NSMakeSize(width, y)];
}

@end


/* ------------------------------------------------------------------ */

static NSTextField *
MakeLabel(NSFont *font, NSTextAlignment alignment, NSColor *color)
{
  NSTextField *field = [[NSTextField alloc] initWithFrame: NSZeroRect];

  [field setEditable: NO];
  [field setSelectable: NO];
  [field setBezeled: NO];
  [field setBordered: NO];
  [field setDrawsBackground: NO];
  [field setFont: font];
  [field setAlignment: alignment];
  [field setTextColor: color];
  [[field cell] setLineBreakMode: NSLineBreakByTruncatingMiddle];
  return field;
}

/* sizeDescription() pads its number for the right-aligned size column of
 * a list; left-aligned here, the padding would show. */
static NSString *
SizeString(unsigned long long size)
{
  return [sizeDescription(size) stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceCharacterSet]];
}

static NSString *
DecodeText(NSData *data)
{
  NSString *text;
  NSUInteger cut;

  /* The read may end inside a multi-byte character; dropping up to three
   * trailing bytes recovers the UTF-8 text in front of it. */
  for (cut = 0; cut < 4 && cut <= [data length]; cut++)
    {
      NSData *head = [data subdataWithRange: NSMakeRange(0, [data length] - cut)];

      text = [[NSString alloc] initWithData: head encoding: NSUTF8StringEncoding];
      if (text != nil)
        {
          return AUTORELEASE(text);
        }
    }
  /* Every byte sequence is Latin-1; text that is not UTF-8 is most often
   * one of its western relatives. */
  return AUTORELEASE([[NSString alloc] initWithData: data encoding: NSISOLatin1StringEncoding]);
}

@implementation GWLookInsidePreviewView

+ (NSArray *)imageExtensions
{
  static NSArray *extensions = nil;

  if (extensions == nil)
    {
      NSMutableArray *lower = [NSMutableArray array];
      NSEnumerator *e = [[NSImage imageFileTypes] objectEnumerator];
      NSString *type;

      while ((type = [e nextObject]) != nil)
        {
          [lower addObject: [type lowercaseString]];
        }
      extensions = [lower copy];
    }
  return extensions;
}

+ (NSDictionary *)infoForPath:(NSString *)path
{
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  FSNode *node = [FSNode nodeWithPath: path];
  NSDateFormatter *formatter;
  NSDate *date;

  if (node == nil || ![node hasValidPath])
    {
      return info;
    }

  [info setObject: [node name] forKey: GWLookInsideInfoName];
  if ([node typeDescription] != nil)
    {
      [info setObject: [node typeDescription] forKey: GWLookInsideInfoKind];
    }

  if ([node isDirectory] && ![node isPackage])
    {
      NSArray *names = [[NSFileManager defaultManager] directoryContentsAtPath: path];
      NSUInteger visible = 0, i;

      for (i = 0; i < [names count]; i++)
        {
          /* A folder window does not show dot files either. */
          if (![[names objectAtIndex: i] hasPrefix: @"."])
            {
              visible++;
            }
        }
      [info setObject: (visible == 1)
            ? LIString(@"1 item", @"Number of items in a folder, singular")
            : [NSString stringWithFormat: LIString(@"%lu items", @"Number of items in a folder"),
                        (unsigned long)visible]
               forKey: GWLookInsideInfoItems];
    }
  else
    {
      [info setObject: SizeString([node fileSize]) forKey: GWLookInsideInfoSize];
    }

  date = [node modificationDate];
  if (date != nil)
    {
      formatter = [[[NSDateFormatter alloc] init] autorelease];
      [formatter setFormatterBehavior: NSDateFormatterBehavior10_4];
      [formatter setDateStyle: NSDateFormatterMediumStyle];
      [formatter setTimeStyle: NSDateFormatterShortStyle];
      [info setObject: [formatter stringFromDate: date] forKey: GWLookInsideInfoModified];
    }

  return info;
}

- (id)initWithFrame:(NSRect)frame
{
  return [self initWithFrame: frame style: GWLookInsidePreviewStyleFull];
}

- (id)initWithFrame:(NSRect)frame style:(GWLookInsidePreviewStyle)style
{
  self = [super initWithFrame: frame];
  if (self != nil)
    {
      _style = style;
      _labelFields = [NSMutableArray new];
      _valueFields = [NSMutableArray new];
    }
  return self;
}

- (void)dealloc
{
  [self stopTasks];
  RELEASE(_path);
  RELEASE(_content);
  RELEASE(_picture);
  RELEASE(_nameField);
  RELEASE(_labelFields);
  RELEASE(_valueFields);
  RELEASE(_playButton);
  [super dealloc];
}

- (NSString *)path
{
  return _path;
}

- (GWLookInsidePreviewKind)kind
{
  return _kind;
}

- (GWLookInsidePreviewStyle)style
{
  return _style;
}

- (void)stopTasks
{
  [_sizer cancel];
  DESTROY(_sizer);
  [_pdfRenderer cancel];
  DESTROY(_pdfRenderer);
  if (_sound != nil)
    {
      [_sound setDelegate: nil];
      [_sound stop];
      DESTROY(_sound);
    }
}

- (void)removeContent
{
  [self stopTasks];
  while ([[self subviews] count] > 0)
    {
      [[[self subviews] lastObject] removeFromSuperview];
    }
  DESTROY(_content);
  DESTROY(_picture);
  DESTROY(_nameField);
  DESTROY(_playButton);
  [_labelFields removeAllObjects];
  [_valueFields removeAllObjects];
  _sizeValueField = nil;
}

- (void)setContent:(NSView *)view
{
  ASSIGN(_content, view);
  [view setFrame: [self bounds]];
  [view setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [self addSubview: view];
}

/* ---- the kinds with a picture of their own content ---- */

- (void)updateImageScaling
{
  NSImageView *imageView = (NSImageView *)_content;
  NSSize size = [[imageView image] size];
  NSSize room = [self bounds].size;

  /* Shown at its own size when it fits, so small pictures stay sharp;
   * only larger ones are scaled down. */
  [imageView setImageScaling: (size.width <= room.width && size.height <= room.height)
                               ? NSScaleNone : NSScaleProportionally];
}

- (BOOL)showImage
{
  NSImage *image = [[[NSImage alloc] initWithContentsOfFile: _path] autorelease];
  NSImageView *imageView;

  if (image == nil)
    {
      return NO;
    }
  imageView = [[[NSImageView alloc] initWithFrame: [self bounds]] autorelease];
  [imageView setImage: image];
  [imageView setImageFrameStyle: NSImageFrameNone];
  [imageView setEditable: NO];
  [self setContent: imageView];
  [self updateImageScaling];
  return YES;
}

- (NSTextView *)showTextScroller
{
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: [self bounds]] autorelease];
  NSSize contentSize;
  NSTextView *textView;

  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: NO];
  [scroll setBorderType: NSNoBorder];
  [self setContent: scroll];
  contentSize = [scroll contentSize];

  textView = [[[NSTextView alloc] initWithFrame:
    NSMakeRect(0, 0, contentSize.width, contentSize.height)] autorelease];
  /* Left at its defaults the text view grows to its container and paints
   * outside the clip view (gnustep-code-built-ui). */
  [textView setMinSize: NSMakeSize(0.0, contentSize.height)];
  [textView setMaxSize: NSMakeSize(1.0e7, 1.0e7)];
  [textView setVerticallyResizable: YES];
  [textView setHorizontallyResizable: NO];
  [textView setAutoresizingMask: NSViewWidthSizable];
  [[textView textContainer] setWidthTracksTextView: YES];
  [[textView textContainer] setContainerSize: NSMakeSize(contentSize.width, 1.0e7)];
  [textView setEditable: NO];
  [textView setSelectable: YES];
  [textView setRichText: YES];
  [textView setDrawsBackground: YES];
  [textView setBackgroundColor: [NSColor textBackgroundColor]];
  [textView setTextContainerInset: NSMakeSize(METRICS_SPACE_8, METRICS_SPACE_8)];
  [scroll setDocumentView: textView];
  return textView;
}

- (BOOL)showPlainText
{
  NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath: _path];
  NSData *data = [handle readDataOfLength: kTextPreviewLength];
  NSString *text;
  NSDictionary *attrs;
  NSTextView *textView;

  [handle closeFile];
  text = (data != nil) ? DecodeText(data) : nil;
  if (text == nil)
    {
      return NO;
    }

  attrs = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont userFixedPitchFontOfSize:
      (_style == GWLookInsidePreviewStyleCompact) ? kCompactTextSize : 0], NSFontAttributeName,
    [NSColor textColor], NSForegroundColorAttributeName, nil];
  textView = [self showTextScroller];
  [[textView textStorage] setAttributedString:
    [[[NSAttributedString alloc] initWithString: text attributes: attrs] autorelease]];
  [textView scrollRangeToVisible: NSMakeRange(0, 0)];
  return YES;
}

- (BOOL)showRichText
{
  NSAttributedString *text = [[[NSAttributedString alloc] initWithPath: _path
                                                     documentAttributes: NULL] autorelease];
  NSTextView *textView;

  if (text == nil)
    {
      return NO;
    }
  textView = [self showTextScroller];
  [[textView textStorage] setAttributedString: text];
  [textView scrollRangeToVisible: NSMakeRange(0, 0)];
  return YES;
}

- (void)pdfRenderer:(GWLookInsidePDFRenderer *)renderer didRenderPages:(NSArray *)pages
{
  NSScrollView *scroll;
  GWLookInsidePageStack *stack;
  NSUInteger i;

  if (renderer != _pdfRenderer)
    {
      return;
    }
  DESTROY(_pdfRenderer);

  /* The icon-and-facts layout shown while rendering gives way to the
   * pages. */
  [self removeContent];
  scroll = [[[NSScrollView alloc] initWithFrame: [self bounds]] autorelease];
  [scroll setHasVerticalScroller: YES];
  [scroll setBorderType: NSNoBorder];
  [scroll setBackgroundColor: [NSColor controlBackgroundColor]];
  stack = [[[GWLookInsidePageStack alloc] initWithFrame: NSZeroRect] autorelease];
  for (i = 0; i < [pages count]; i++)
    {
      NSImageView *pageView = [[[NSImageView alloc] initWithFrame: NSZeroRect] autorelease];

      [pageView setImage: [pages objectAtIndex: i]];
      [pageView setImageScaling: NSScaleProportionally];
      [pageView setImageFrameStyle: NSImageFramePhoto];
      [pageView setEditable: NO];
      [stack addSubview: pageView];
    }
  [scroll setDocumentView: stack];
  [self setContent: scroll];
  [stack layoutPagesForWidth: [scroll contentSize].width];
  [[scroll contentView] scrollToPoint: NSZeroPoint];
  [scroll reflectScrolledClipView: [scroll contentView]];
}

/* ---- the info layout: picture, name and facts ---- */

- (NSImage *)pictureForInfo
{
  FSNode *node = [FSNode nodeWithPath: _path];
  int side = (int)MIN(GWLookInsideIconMaximumSide, MAX(NSWidth([self bounds]), kPictureMinimum));

  if (_kind == GWLookInsidePreviewKindImage)
    {
      NSImage *image = [[[NSImage alloc] initWithContentsOfFile: _path] autorelease];

      if (image != nil)
        {
          return image;
        }
    }
  return [[FSNodeRep sharedInstance] iconOfSize: side forNode: node];
}

- (void)addFact:(NSString *)value label:(NSString *)label
{
  NSFont *font = METRICS_FONT_SYSTEM_REGULAR_13;
  NSTextField *labelField = MakeLabel(font, NSRightTextAlignment, [NSColor grayColor]);
  NSTextField *valueField = MakeLabel(font, NSLeftTextAlignment, [NSColor controlTextColor]);

  [labelField setStringValue: label];
  [valueField setStringValue: (value != nil) ? value : @""];
  [self addSubview: labelField];
  [self addSubview: valueField];
  [_labelFields addObject: labelField];
  [_valueFields addObject: valueField];
  RELEASE(labelField);
  RELEASE(valueField);
}

- (void)showInfo
{
  NSDictionary *info = [[self class] infoForPath: _path];
  BOOL compact = (_style == GWLookInsidePreviewStyleCompact);

  _picture = [[NSImageView alloc] initWithFrame: NSZeroRect];
  [_picture setImage: [self pictureForInfo]];
  [_picture setImageScaling: NSScaleProportionally];
  [_picture setImageFrameStyle: NSImageFrameNone];
  [_picture setEditable: NO];
  [self addSubview: _picture];

  if (compact)
    {
      /* The host lists the facts itself next to the picture. */
      [self layoutInfo];
      return;
    }

  _nameField = MakeLabel(METRICS_FONT_SYSTEM_BOLD_13,
                         NSCenterTextAlignment, [NSColor controlTextColor]);
  [_nameField setStringValue: [info objectForKey: GWLookInsideInfoName]];
  [self addSubview: _nameField];

  [self addFact: [info objectForKey: GWLookInsideInfoKind]
          label: LIString(@"Kind", @"Label of an item's kind in a preview")];
  if (_kind == GWLookInsidePreviewKindFolder)
    {
      [self addFact: [info objectForKey: GWLookInsideInfoItems]
              label: LIString(@"Contents", @"Label of a folder's item count in a preview")];
      [self addFact: LIString(@"Calculating...", @"A folder's size while it is added up")
              label: LIString(@"Size", @"Label of an item's size in a preview")];
      _sizeValueField = [_valueFields lastObject];
      _sizer = [[GWLookInsideFolderSizer alloc] initWithPath: _path target: self];
      [_sizer start];
    }
  else
    {
      [self addFact: [info objectForKey: GWLookInsideInfoSize]
              label: LIString(@"Size", @"Label of an item's size in a preview")];
    }
  [self addFact: [info objectForKey: GWLookInsideInfoModified]
          label: LIString(@"Modified", @"Label of an item's modification date in a preview")];

  if (_kind == GWLookInsidePreviewKindAudio
      && [[NSSound soundUnfilteredFileTypes]
           containsObject: [[_path pathExtension] lowercaseString]])
    {
      _playButton = [[NSButton alloc] initWithFrame: NSZeroRect];
      [_playButton setButtonType: NSMomentaryPushInButton];
      [_playButton setBezelStyle: NSRoundedBezelStyle];
      [_playButton setTitle: LIString(@"Play", @"Button that plays a sound file in a preview")];
      [_playButton setTarget: self];
      [_playButton setAction: @selector(togglePlay:)];
      [self addSubview: _playButton];
    }

  [self layoutInfo];
}

- (void)folderSizer:(GWLookInsideFolderSizer *)sizer didFinishWithSize:(unsigned long long)size
{
  if (sizer == _sizer)
    {
      [_sizeValueField setStringValue: SizeString(size)];
      DESTROY(_sizer);
      [self layoutInfo];
    }
}

- (void)togglePlay:(id)sender
{
  if (_sound != nil)
    {
      [self stopTasks];
      [_playButton setTitle: LIString(@"Play", @"Button that plays a sound file in a preview")];
      return;
    }

  _sound = [[NSSound alloc] initWithContentsOfFile: _path byReference: YES];
  if (_sound == nil || ![_sound play])
    {
      DESTROY(_sound);
      /* The format is one this system should play but this file is not:
       * say so once by disabling the button rather than retrying. */
      [_playButton setEnabled: NO];
      NSBeep();
      return;
    }
  [_sound setDelegate: self];
  [_playButton setTitle: LIString(@"Stop", @"Button that stops a playing sound in a preview")];
}

- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finished
{
  if (sound == _sound)
    {
      DESTROY(_sound);
      [_playButton setTitle: LIString(@"Play", @"Button that plays a sound file in a preview")];
    }
}

static CGFloat
WidestString(NSArray *fields)
{
  NSEnumerator *e = [fields objectEnumerator];
  NSTextField *field;
  CGFloat widest = 0;

  while ((field = [e nextObject]) != nil)
    {
      NSDictionary *attrs = [NSDictionary dictionaryWithObject: [field font]
                                                        forKey: NSFontAttributeName];

      widest = MAX(widest, ceil([[field stringValue] sizeWithAttributes: attrs].width) + 4);
    }
  return widest;
}

/* Full style: the block of picture, name and facts centered in the view.
 * Compact style: the picture alone, as large as the view allows. */
- (void)layoutInfo
{
  NSRect bounds = [self bounds];
  NSUInteger lines = [_labelFields count], i;
  CGFloat textH = kNameHeight + METRICS_SPACE_8 + lines * kFactLineHeight
    + ((_playButton != nil) ? METRICS_SPACE_12 + METRICS_BUTTON_HEIGHT : 0);
  CGFloat side, labelW, valueW, left, top, y;

  if (_picture == nil)
    {
      return;
    }

  if (_style == GWLookInsidePreviewStyleCompact)
    {
      side = floor(MAX(MIN(NSWidth(bounds), NSHeight(bounds)), kPictureMinimum));
      if (_kind != GWLookInsidePreviewKindImage)
        {
          side = MIN(side, GWLookInsideIconMaximumSide);
        }
      [_picture setFrame: NSMakeRect(floor(NSMidX(bounds) - side / 2),
                                     floor(NSMidY(bounds) - side / 2), side, side)];
      [self setNeedsDisplay: YES];
      return;
    }

  side = floor(MIN(MIN((_kind == GWLookInsidePreviewKindImage) ? kFullPictureMaximum : GWLookInsideIconMaximumSide,
                       NSWidth(bounds) - 2 * METRICS_CONTENT_SIDE_MARGIN),
                   NSHeight(bounds) - textH - 2 * METRICS_CONTENT_SIDE_MARGIN - METRICS_SPACE_16));
  side = MAX(side, kPictureMinimum);
  top = NSMinY(bounds) + floor((NSHeight(bounds) + side + METRICS_SPACE_16 + textH) / 2);

  [_picture setFrame: NSMakeRect(floor(NSMidX(bounds) - side / 2), top - side, side, side)];
  y = top - side - METRICS_SPACE_16 - kNameHeight;
  [_nameField setFrame: NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, y,
                                   MAX(NSWidth(bounds) - 2 * METRICS_CONTENT_SIDE_MARGIN, 0),
                                   kNameHeight)];
  y -= METRICS_SPACE_8;

  labelW = WidestString(_labelFields);
  valueW = MIN(WidestString(_valueFields),
               MAX(NSWidth(bounds) - 2 * METRICS_CONTENT_SIDE_MARGIN - labelW - METRICS_SPACE_8, 0));
  left = MAX(floor(NSMidX(bounds) - (labelW + METRICS_SPACE_8 + valueW) / 2),
             METRICS_CONTENT_SIDE_MARGIN);

  for (i = 0; i < lines; i++)
    {
      y -= kFactLineHeight;
      [[_labelFields objectAtIndex: i] setFrame: NSMakeRect(left, y, labelW, kFactLineHeight)];
      [[_valueFields objectAtIndex: i] setFrame:
        NSMakeRect(left + labelW + METRICS_SPACE_8, y, valueW, kFactLineHeight)];
    }

  if (_playButton != nil)
    {
      y -= METRICS_SPACE_12 + METRICS_BUTTON_HEIGHT;
      [_playButton setFrame: NSMakeRect(floor(NSMidX(bounds) - METRICS_BUTTON_MIN_WIDTH / 2), y,
                                        METRICS_BUTTON_MIN_WIDTH, METRICS_BUTTON_HEIGHT)];
    }
  [self setNeedsDisplay: YES];
}

/* ---- showing a path ---- */

- (void)showPath:(NSString *)path
{
  FSNode *node;
  BOOL shown = NO;

  [self removeContent];
  ASSIGN(_path, path);
  node = (path != nil) ? [FSNode nodeWithPath: path] : nil;
  _kind = GWLookInsidePreviewKindForPath(path, [[self class] imageExtensions],
                                         (node != nil) && [node isPackage]);

  if (_kind == GWLookInsidePreviewKindNone)
    {
      [self setNeedsDisplay: YES];
      return;
    }

  switch (_kind)
    {
    case GWLookInsidePreviewKindImage:
      shown = [self showImage];
      break;
    case GWLookInsidePreviewKindPlainText:
      shown = [self showPlainText];
      break;
    case GWLookInsidePreviewKindRichText:
      shown = [self showRichText];
      break;
    case GWLookInsidePreviewKindPDF:
      /* The info layout stays up until the pages arrive. */
      _pdfRenderer = [[GWLookInsidePDFRenderer alloc] initWithTarget: self];
      if (![_pdfRenderer startWithPath: path])
        {
          DESTROY(_pdfRenderer);
        }
      break;
    default:
      break;
    }

  if (!shown)
    {
      [self showInfo];
    }
  [self setNeedsDisplay: YES];
}

/* ---- relayout on every size change (gnustep-code-built-ui) ---- */

- (void)relayout
{
  if (_picture != nil)
    {
      [self layoutInfo];
    }
  else if ([_content isKindOfClass: [NSImageView class]])
    {
      [self updateImageScaling];
    }
  else if ([_content isKindOfClass: [NSScrollView class]]
           && [[(NSScrollView *)_content documentView]
                isKindOfClass: [GWLookInsidePageStack class]])
    {
      NSScrollView *scroll = (NSScrollView *)_content;

      [(GWLookInsidePageStack *)[scroll documentView]
        layoutPagesForWidth: [scroll contentSize].width];
    }
}

- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize: size];
  [self relayout];
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame: frame];
  [self relayout];
}

@end
