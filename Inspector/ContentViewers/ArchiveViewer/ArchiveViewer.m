/*
 * ArchiveViewer.m
 *
 * Contents Inspector viewer that lists the files inside an archive file
 * using libarchive.  Supports all archive formats libarchive does (tar,
 * zip, gzip, bzip2, xz, lzma, 7zip, ar, cpio, ISO, etc.) and all
 * compression filters, via archive_read_support_format_all() and
 * archive_read_support_filter_all().
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This file is part of the GNUstep Inspector application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <AppKit/AppKit.h>
#import "ArchiveViewer.h"
#import <archive.h>
#import <archive_entry.h>

#define ONE_KB 1024LLU
#define ONE_MB (ONE_KB * ONE_KB)
#define ONE_GB (ONE_KB * ONE_MB)
#define ONE_TB (ONE_KB * ONE_GB)

#define NAMESIZE 270
#define TYPESIZE 80
#define SIZESIZE 80
#define DATESIZE 120

@implementation ArchiveViewer

- (void)dealloc
{
  RELEASE (entries);
  RELEASE (currentPath);
  [super dealloc];
}

- (id)initWithFrame:(NSRect)frameRect
          inspector:(id)insp
{
  self = [super initWithFrame: frameRect];

  if (self)
    {
      NSRect r = [self bounds];

      scrollView = [[NSScrollView alloc] initWithFrame: r];
      [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      [scrollView setBorderType: NSBezelBorder];
      [scrollView setHasHorizontalScroller: YES];
      [scrollView setHasVerticalScroller: YES];
      [[scrollView contentView] setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      [self addSubview: scrollView];
      RELEASE (scrollView);

      tableView = [[NSTableView alloc] initWithFrame: r];
      [tableView setAllowsColumnReordering: YES];
      [tableView setAllowsColumnResizing: YES];
      [tableView setAllowsMultipleSelection: NO];
      [tableView setAutoresizesAllColumnsToFit: YES];
      [tableView setAutoresizingMask: NSViewWidthSizable];
      [tableView setDataSource: self];

      [tableView addTableColumn: [self nameColumn]];
      [tableView addTableColumn: [self typeColumn]];
      [tableView addTableColumn: [self sizeColumn]];
      [tableView addTableColumn: [self dateColumn]];

      [scrollView setDocumentView: tableView];
      RELEASE (tableView);

      entries = [NSMutableArray new];
      currentPath = nil;
      inspector = insp;
      fm = [NSFileManager defaultManager];
    }

  return self;
}

- (NSTableColumn *)nameColumn
{
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier: @"name"];
  NSTableHeaderCell *hcell = [[NSTableHeaderCell alloc] initTextCell:
                                NSLocalizedString(@"Name", @"")];
  [col setHeaderCell: hcell];
  [col setMinWidth: 40];
  [col setWidth: NAMESIZE];
  [col setEditable: NO];
  RELEASE (hcell);
  return AUTORELEASE (col);
}

- (NSTableColumn *)typeColumn
{
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier: @"type"];
  NSTableHeaderCell *hcell = [[NSTableHeaderCell alloc] initTextCell:
                                NSLocalizedString(@"Type", @"")];
  [col setHeaderCell: hcell];
  [col setMinWidth: 30];
  [col setWidth: TYPESIZE];
  [col setEditable: NO];
  RELEASE (hcell);
  return AUTORELEASE (col);
}

- (NSTableColumn *)sizeColumn
{
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier: @"size"];
  NSTableHeaderCell *hcell = [[NSTableHeaderCell alloc] initTextCell:
                                NSLocalizedString(@"Size", @"")];
  [col setHeaderCell: hcell];
  [col setMinWidth: 30];
  [col setWidth: SIZESIZE];
  [col setEditable: NO];
  RELEASE (hcell);
  return AUTORELEASE (col);
}

- (NSTableColumn *)dateColumn
{
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier: @"date"];
  NSTableHeaderCell *hcell = [[NSTableHeaderCell alloc] initTextCell:
                                NSLocalizedString(@"Date", @"")];
  [col setHeaderCell: hcell];
  [col setMinWidth: 60];
  [col setWidth: DATESIZE];
  [col setEditable: NO];
  RELEASE (hcell);
  return AUTORELEASE (col);
}

- (NSString *)sizeDescription:(unsigned long long)size
{
  NSString *sizeStr;

  if (size == 1)
    {
      sizeStr = @"1 byte";
    }
  else if (size < (ONE_KB))
    {
      sizeStr = [NSString stringWithFormat: @"%llu bytes", size];
    }
  else if (size < (ONE_MB))
    {
      sizeStr = [NSString stringWithFormat: @"%.2f KB", ((double)size / (double)(ONE_KB))];
    }
  else if (size < (ONE_GB))
    {
      sizeStr = [NSString stringWithFormat: @"%.2f MB", ((double)size / (double)(ONE_MB))];
    }
  else if (size < (ONE_TB))
    {
      sizeStr = [NSString stringWithFormat: @"%.2f GB", ((double)size / (double)(ONE_GB))];
    }
  else
    {
      sizeStr = [NSString stringWithFormat: @"%.2f TB", ((double)size / (double)(ONE_TB))];
    }

  return sizeStr;
}

- (NSString *)typeNameForEntry:(struct archive_entry *)entry
{
  mode_t mode = archive_entry_filetype (entry);
  NSString *name = nil;

  if (S_ISDIR (mode))
    {
      name = NSLocalizedString(@"Directory", @"");
    }
  else if (S_ISLNK (mode))
    {
      name = NSLocalizedString(@"Link", @"");
    }
  else if (S_ISCHR (mode))
    {
      name = NSLocalizedString(@"Char Device", @"");
    }
  else if (S_ISBLK (mode))
    {
      name = NSLocalizedString(@"Block Device", @"");
    }
  else if (S_ISFIFO (mode))
    {
      name = NSLocalizedString(@"FIFO", @"");
    }
  else if (S_ISSOCK (mode))
    {
      name = NSLocalizedString(@"Socket", @"");
    }
  else
    {
      name = NSLocalizedString(@"File", @"");
    }

  return name;
}

- (BOOL)readArchiveFromFile:(NSString *)path
{
  struct archive *a;
  struct archive_entry *entry;
  int r;

  [entries removeAllObjects];

  a = archive_read_new ();
  archive_read_support_filter_all (a);
  archive_read_support_format_all (a);

  r = archive_read_open_filename (a, [path fileSystemRepresentation], 10240);
  if (r != ARCHIVE_OK)
    {
      const char *err = archive_error_string (a);
      NSLog(@"[ArchiveViewer] readArchiveFromFile: open failed for %@: %s (r=%d)",
            path, err ? err : "unknown error", r);
      archive_read_free (a);
      return NO;
    }

  while ((r = archive_read_next_header (a, &entry)) == ARCHIVE_OK)
    {
      NSString *name;
      NSMutableDictionary *dict;
      NSDate *date;

      name = [NSString stringWithUTF8String: archive_entry_pathname (entry)];
      if (name == nil)
        {
          const char *p = archive_entry_pathname_utf8 (entry);
          name = [NSString stringWithUTF8String: p];
        }
      if (name == nil)
        {
          name = @"";
        }

      dict = [NSMutableDictionary dictionary];
      [dict setObject: name forKey: @"name"];
      [dict setObject: [self typeNameForEntry: entry] forKey: @"type"];

      if (archive_entry_size_is_set (entry))
        {
          [dict setObject: [self sizeDescription: archive_entry_size (entry)]
                   forKey: @"size"];
        }
      else
        {
          [dict setObject: @"" forKey: @"size"];
        }

      if (archive_entry_mtime_is_set (entry))
        {
          date = [NSDate dateWithTimeIntervalSince1970: archive_entry_mtime (entry)];
          [dict setObject: date forKey: @"date"];
        }

      [entries addObject: dict];

      archive_read_data_skip (a);
      if ([entries count] > 100000)
        {
          break;
        }
    }

  archive_read_free (a);

  return ([entries count] > 0);
}

- (BOOL)readArchiveFromData:(NSData *)data
{
  struct archive *a;
  struct archive_entry *entry;
  int r;

  [entries removeAllObjects];

  a = archive_read_new ();
  archive_read_support_filter_all (a);
  archive_read_support_format_all (a);

  r = archive_read_open_memory (a, [data bytes], [data length]);
  if (r != ARCHIVE_OK)
    {
      archive_read_free (a);
      return NO;
    }

  while ((r = archive_read_next_header (a, &entry)) == ARCHIVE_OK)
    {
      NSString *name;
      NSMutableDictionary *dict;
      NSDate *date;

      name = [NSString stringWithUTF8String: archive_entry_pathname (entry)];
      if (name == nil)
        {
          const char *p = archive_entry_pathname_utf8 (entry);
          name = [NSString stringWithUTF8String: p];
        }
      if (name == nil)
        {
          name = @"";
        }

      dict = [NSMutableDictionary dictionary];
      [dict setObject: name forKey: @"name"];
      [dict setObject: [self typeNameForEntry: entry] forKey: @"type"];

      if (archive_entry_size_is_set (entry))
        {
          [dict setObject: [self sizeDescription: archive_entry_size (entry)]
                   forKey: @"size"];
        }
      else
        {
          [dict setObject: @"" forKey: @"size"];
        }

      if (archive_entry_mtime_is_set (entry))
        {
          date = [NSDate dateWithTimeIntervalSince1970: archive_entry_mtime (entry)];
          [dict setObject: date forKey: @"date"];
        }

      [entries addObject: dict];

      archive_read_data_skip (a);
      if ([entries count] > 100000)
        {
          break;
        }
    }

  archive_read_free (a);

  return ([entries count] > 0);
}

- (void)displayPath:(NSString *)path
{
  if ([self superview])
    {
      [inspector contentsReadyAt: path];
    }

  ASSIGN (currentPath, path);

  if ([self readArchiveFromFile: currentPath] == NO)
    {
      [entries removeAllObjects];
    }

  [tableView reloadData];
}

- (void)displayData:(NSData *)data
             ofType:(NSString *)type
{
  DESTROY (currentPath);

  if ([self readArchiveFromData: data] == NO)
    {
      [entries removeAllObjects];
    }

  [tableView reloadData];
}

- (NSString *)path
{
  return currentPath;
}

- (void)stopTasks
{
}

- (BOOL)isArchiveAtPath:(NSString *)path
{
  struct archive *a;
  struct archive_entry *entry;
  BOOL ok = NO;

  a = archive_read_new ();
  archive_read_support_filter_all (a);
  archive_read_support_format_all (a);

  if (archive_read_open_filename (a, [path fileSystemRepresentation], 10240)
      == ARCHIVE_OK)
    {
      /* A real archive yields at least its first header.  This reads only
       * the first entry, so probing is cheap even for huge archives. */
      ok = (archive_read_next_header (a, &entry) == ARCHIVE_OK);
    }
  else
    {
      const char *err = archive_error_string (a);
      NSLog(@"[ArchiveViewer] isArchiveAtPath: open failed for %@: %s",
            path, err ? err : "unknown error");
    }

  archive_read_free (a);
  return ok;
}

- (BOOL)canDisplayPath:(NSString *)path
{
  BOOL isDir = NO;

  if ([fm fileExistsAtPath: path isDirectory: &isDir] && (isDir == NO))
    {
      return [self isArchiveAtPath: path];
    }
  return NO;
}

- (BOOL)canDisplayDataOfType:(NSString *)type
{
  /* The Inspector does not tell us the raw bytes are an archive via type
   * alone; probe the data instead. */
  return NO;
}

- (NSString *)winname
{
  return NSLocalizedString(@"Archive Inspector", @"");
}

- (NSString *)description
{
  return NSLocalizedString(@"Displays the contents of an archive file", @"");
}

/* NSTableViewDataSource */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
  return [entries count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex
{
  NSDictionary *entry = [entries objectAtIndex: rowIndex];

  if ([[aTableColumn identifier] isEqual: @"name"])
    {
      return [entry objectForKey: @"name"];
    }
  else if ([[aTableColumn identifier] isEqual: @"type"])
    {
      return [entry objectForKey: @"type"];
    }
  else if ([[aTableColumn identifier] isEqual: @"size"])
    {
      return [entry objectForKey: @"size"];
    }
  else if ([[aTableColumn identifier] isEqual: @"date"])
    {
      NSDate *date = [entry objectForKey: @"date"];
      if (date)
        {
          return [date descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M"
                                           timeZone: nil
                                             locale: nil];
        }
      return @"";
    }
  return @"";
}

@end
