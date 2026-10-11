/* FileOpInfo.m
 *  
 * Copyright (C) 2004-2018 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola <rm@gnu.org>
 * Date: March 2004
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#ifndef _WIN32
#import <dispatch/dispatch.h>
#endif

#import "FSNAlias.h"

#import "FileOpInfo.h"
#import "Operation.h"
#import "Functions.h"
#import "GWMetadataCopier.h"
#import "GWFileUndoRecord.h"
#import "GWFileUndoStack.h"


#define PROGR_STEPS (100.0)
static BOOL stopped = NO;
static BOOL paused = NO;

static NSString *nibName = @"FileOperationWin";

@implementation FileOpInfo

- (NSString *)description
{
  return [NSString stringWithFormat: @"%@ from: %@ to: %@", type, source, destination];
}

- (void)dealloc
{
  [nc removeObserver: self];

  RELEASE (operationDict);
  RELEASE (type);
  RELEASE (source);
  RELEASE (destination);
  RELEASE (files);
  RELEASE (procFiles);
  RELEASE (cachedProcessedFilesData);
  RELEASE (completedItems);
  RELEASE (undoRole);
  RELEASE (dupfiles);
  RELEASE (notifNames);
  RELEASE (win);
  
  DESTROY (executor);
  DESTROY (execconn);
  
  [super dealloc];
}

+ (id)operationOfType:(NSString *)tp
                  ref:(int)rf
               source:(NSString *)src
          destination:(NSString *)dst
                files:(NSArray *)fls
         confirmation:(BOOL)conf
            usewindow:(BOOL)uwnd
              winrect:(NSRect)wrect
           controller:(id)cntrl
{
  return AUTORELEASE ([[self alloc] initWithOperationType: tp ref: rf
                                source: src destination: dst files: fls 
                                      confirmation: conf usewindow: uwnd 
                                        winrect: wrect controller: cntrl]);
}

- (id)initWithOperationType:(NSString *)tp
                        ref:(int)rf
                     source:(NSString *)src
                destination:(NSString *)dst
                      files:(NSArray *)fls
               confirmation:(BOOL)conf
                  usewindow:(BOOL)uwnd
                    winrect:(NSRect)wrect
                 controller:(id)cntrl
{
  self = [super init];

  if (self)
    {
      win = nil;
      showwin = uwnd;
  
      if (showwin)
	{
	  if ([NSBundle loadNibNamed: nibName owner: self] == NO)
	    {
	      DESTROY (self);
	      return self;
	    }
      
	  if (NSEqualRects(wrect, NSZeroRect) == NO)
	    {
	      [win setFrame: wrect display: NO];
	    }
	  else if ([win setFrameUsingName: @"fopinfo"] == NO)
	    {
	      [win setFrame: NSMakeRect(300, 300, 282, 102) display: NO];
	    }

	  [fromLabel setStringValue: NSLocalizedString(@"From:", @"")];
	  [toLabel setStringValue: NSLocalizedString(@"To:", @"")];
	  [pauseButt setTitle: NSLocalizedString(@"Pause", @"")];
	  [stopButt setTitle: NSLocalizedString(@"Stop", @"")];
	}
 
      ref = rf;
      controller = cntrl;
      fm = [NSFileManager defaultManager];
      nc = [NSNotificationCenter defaultCenter];
      dnc = [NSDistributedNotificationCenter defaultCenter];
    
      ASSIGN (type, tp);
      ASSIGN (source, src);
      ASSIGN (destination, dst);
      files = [[NSMutableArray arrayWithArray:fls] retain];
      procFiles = [[NSMutableArray alloc] init];
      completedItems = [NSMutableArray new];
    
      dupfiles = [NSMutableArray new];
    
      if ([type isEqual: NSWorkspaceDuplicateOperation])
	{
	  NSString *copystr = NSLocalizedString(@"_copy", @"");
	  unsigned i;

	  for (i = 0; i < [files count]; i++)
	    {
	      NSDictionary *fdict = [files objectAtIndex: i];
	      NSString *fname = [fdict objectForKey: @"name"];
	      NSString *newname = [NSString stringWithString: fname];
	      NSString *ext = [newname pathExtension];
	      NSString *base = [newname stringByDeletingPathExtension];
	      NSString *ntmp;
	      NSString *destpath;
	      NSUInteger count = 1;

	      while (1)
		{
		  if (count == 1)
		    {
		      ntmp = [NSString stringWithFormat: @"%@%@", base, copystr];
		      if ([ext length])
			{
			  ntmp = [ntmp stringByAppendingPathExtension: ext];
			}
		    }
		  else
		    {
		      ntmp = [NSString stringWithFormat: @"%@%@%lu", base, copystr, (unsigned long)count];
		      if ([ext length])
			{
			  ntmp = [ntmp stringByAppendingPathExtension: ext];
			}
		    }
		  destpath = [destination stringByAppendingPathComponent: ntmp];

		  if ([fm fileExistsAtPath: destpath] == NO)
		    {
		      newname = ntmp;
		      break;
		    }
		  else
		    {
		      count++;
		    }
		}
        
	      [dupfiles addObject: newname];
	    }
	}
    
      operationDict = [NSMutableDictionary new];
      [operationDict setObject: type forKey: @"operation"];
      [operationDict setObject: [NSNumber numberWithInt: ref] forKey: @"ref"];
      [operationDict setObject: source forKey: @"source"];
      if (destination != nil)
	[operationDict setObject: destination forKey: @"destination"];
      [operationDict setObject: files forKey: @"files"];

      confirm = conf;
      executor = nil;
      opdone = NO;
    }
  
  return self;
}

- (void)startOperation
{
  if (confirm)
    {    
      NSString *title = nil;
      NSString *msg = nil;
      NSString *msg1 = nil;
      NSString *msg2 = nil;
      NSString *items;

      if ([files count] > 1)
        {
          items = [NSString stringWithFormat: @"%lu %@", (unsigned long)[files count], NSLocalizedString(@"items", @"")];
        }
      else
        {
          items = NSLocalizedString(@"one item", @"");
        }
    
      if ([type isEqual: NSWorkspaceMoveOperation])
        {
          title = NSLocalizedString(@"Move", @"");
          msg1 = [NSString stringWithFormat: @"%@ %@ %@: ", 
                           NSLocalizedString(@"Move", @""), 
                           items, 
                           NSLocalizedString(@"from", @"")];
          msg2 = NSLocalizedString(@"\nto: ", @"");
          msg = [NSString stringWithFormat: @"%@%@%@%@?", msg1, source, msg2, destination];
        }
      else if ([type isEqual: NSWorkspaceCopyOperation])
        {
          title = NSLocalizedString(@"Copy", @"");
          msg1 = [NSString stringWithFormat: @"%@ %@ %@: ", 
                           NSLocalizedString(@"Copy", @""), 
                           items, 
                           NSLocalizedString(@"from", @"")];
          msg2 = NSLocalizedString(@"\nto: ", @"");
          msg = [NSString stringWithFormat: @"%@%@%@%@?", msg1, source, msg2, destination];
        }
      else if ([type isEqual: NSWorkspaceLinkOperation])
        {
          title = NSLocalizedString(@"Link", @"");
          msg1 = [NSString stringWithFormat: @"%@ %@ %@: ", 
                           NSLocalizedString(@"Link", @""), 
                           items, 
                           NSLocalizedString(@"from", @"")];
          msg2 = NSLocalizedString(@"\nto: ", @"");
          msg = [NSString stringWithFormat: @"%@%@%@%@?", msg1, source, msg2, destination];
        }
      else if ([type isEqual: NSWorkspaceRecycleOperation])
        {
          title = NSLocalizedString(@"Recycler", @"");
          msg1 = [NSString stringWithFormat: @"%@ %@ %@: ", 
                           NSLocalizedString(@"Move", @""), 
                           items, 
                           NSLocalizedString(@"from", @"")];
          msg2 = NSLocalizedString(@"\nto the Recycler", @"");
          msg = [NSString stringWithFormat: @"%@%@%@?", msg1, source, msg2];
        }
      else if ([type isEqual: @"WorkspaceRecycleOutOperation"])
        {
          title = NSLocalizedString(@"Recycler", @"");
          msg1 = [NSString stringWithFormat: @"%@ %@ %@ ", 
                           NSLocalizedString(@"Move", @""), 
                           items, 
                           NSLocalizedString(@"from the Recycler", @"")];
          msg2 = NSLocalizedString(@"\nto: ", @"");
          msg = [NSString stringWithFormat: @"%@%@%@?", msg1, msg2, destination];
        }
      else if ([type isEqual: @"WorkspaceemptyTrashOperation"])
        {
          title = NSLocalizedString(@"Recycler", @"");
          msg = NSLocalizedString(@"Empty the Recycler?", @"");
        }
      else if ([type isEqual: NSWorkspaceDestroyOperation])
        {
          title = NSLocalizedString(@"Delete", @"");
          msg = NSLocalizedString(@"Delete the selected objects?", @"");
        }
      else if ([type isEqual: NSWorkspaceDuplicateOperation])
        {
          title = NSLocalizedString(@"Duplicate", @"");
          msg = NSLocalizedString(@"Duplicate the selected objects?", @"");
        }
      else if ([type isEqual: FSNWorkspaceCreateAliasOperation])
        {
          title = NSLocalizedString(@"Make Alias", @"");
          msg = NSLocalizedString(@"Create aliases of the selected objects?", @"");
        }
      
      if (NSRunAlertPanel(title, msg, 
                          NSLocalizedString(@"OK", @""), 
                          NSLocalizedString(@"Cancel", @""), 
                          nil) != NSAlertDefaultReturn) {
        [self endOperation];
        return;
      }
    }
  [self detachOperationThread];
}

- (void) threadWillExit: (NSNotification *)notification
{
  [nc removeObserver: self
                name: NSConnectionDidDieNotification 
              object: execconn];

  executor = nil;
}

-(void)detachOperationThread
{
  NSPort *port[2];
  NSArray *ports;

  port[0] = (NSPort *)[NSPort port];
  port[1] = (NSPort *)[NSPort port];
  
  ports = [NSArray arrayWithObjects: port[1], port[0], nil];

  execconn = [[NSConnection alloc] initWithReceivePort: port[0]
                                              sendPort: port[1]];
  [execconn setRootObject: self];
  [execconn setDelegate: self];
  
  [nc addObserver: self
         selector: @selector(connectionDidDie:)
             name: NSConnectionDidDieNotification
           object: execconn];  

  NS_DURING
    {
#ifdef _WIN32
      [NSThread detachNewThreadSelector: @selector(setPorts:)
                               toTarget: [FileOpExecutor class]
                             withObject: ports];
#else
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [FileOpExecutor setPorts:ports];
      });
#endif
    }
  NS_HANDLER
    {
      NSRunAlertPanel(nil, 
                      NSLocalizedString(@"A fatal error occurred while dispatching the task!", @""),
                      NSLocalizedString(@"Continue", @""), 
                      nil, 
                      nil);
      [self endOperation];
    }
  NS_ENDHANDLER
}

- (NSInteger)requestUserConfirmationWithMessage:(NSString *)message 
                                    title:(NSString *)title
{  
  return NSRunAlertPanel(NSLocalizedString(title, @""),
			 NSLocalizedString(message, @""),
			 NSLocalizedString(@"OK", @""), 
			 NSLocalizedString(@"Cancel", @""), 
                         nil);       
}

- (NSInteger)showErrorAlertWithMessage:(NSString *)message
{  
  return NSRunAlertPanel(nil, 
                         NSLocalizedString(message, @""), 
			 NSLocalizedString(@"OK", @""), 
                         nil, 
                         nil);
}

- (IBAction)pause:(id)sender
{
  if (paused == NO)
    {
      [pauseButt setTitle: NSLocalizedString(@"Continue", @"")];	
      paused = YES;
    }
  else
    {
      [self detachOperationThread];
      [pauseButt setTitle: NSLocalizedString(@"Pause", @"")];	
      paused = NO;
    }
}

- (IBAction)stop:(id)sender
{
  if (paused)
    {
      [self endOperation];
    }
  stopped = YES;   
}

- (void)cacheProcessedFiles:(NSData *)data
{
  ASSIGN(cachedProcessedFilesData, data);
}

- (void)cacheCompletedItems:(NSData *)data
{
  [completedItems addObjectsFromArray: [NSUnarchiver unarchiveObjectWithData: data]];
}

- (NSArray *)completedItems
{
  return completedItems;
}

- (void)setUndoRole:(NSString *)role
{
  ASSIGN (undoRole, role);
}

- (void)removeProcessedFiles
{
  NSData *pFData;
  NSArray *pFiles;
  NSUInteger i;

  pFData = cachedProcessedFilesData;
  if (pFData == nil)
    {
      return;
    }
  pFiles = [NSUnarchiver unarchiveObjectWithData: pFData];

  for (i = 0; i < [pFiles count]; i++)
    {
      NSDictionary *fi;
      NSUInteger j;
      BOOL found;

      j = 0;
      found = NO;
      while (j < [files count] && !found)
        {
          fi = [files objectAtIndex:j];

          if ([[pFiles objectAtIndex:i] isEqualTo:[fi objectForKey:@"name"]])
            found = YES;
          else
            /* Advance the SEARCH index (j), not the outer per-processed-name
             * index (i): incrementing i here left j stuck at 0 whenever the
             * first pending file was not a match, so the scan never moved
             * through `files' and i alone ran past the end of pFiles,
             * raising NSRangeException the next time a user paused a
             * multi-file operation partway through. */
            j++;
        }
      if (found)
        {
          [procFiles addObject:[files objectAtIndex:j]];
          [files removeObjectAtIndex:j];
        }
    }
}

- (void)showProgressWin
{  
  if ([win isVisible] == NO) {
    if ([type isEqual: NSWorkspaceMoveOperation])
      {
	[win setTitle: NSLocalizedString(@"Move", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"From:", @"")];
	[fromField setStringValue: relativePathFittingInField(fromField, source)];
	[toLabel setStringValue: NSLocalizedString(@"To:", @"")];
	[toField setStringValue: relativePathFittingInField(fromField, destination)];
      }
    else if ([type isEqual: NSWorkspaceCopyOperation])
      {
	[win setTitle: NSLocalizedString(@"Copy", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"From:", @"")];
	[fromField setStringValue: relativePathFittingInField(fromField, source)];
	[toLabel setStringValue: NSLocalizedString(@"To:", @"")];
	[toField setStringValue: relativePathFittingInField(fromField, destination)];
      }
    else if ([type isEqual: NSWorkspaceLinkOperation])
      {
	[win setTitle: NSLocalizedString(@"Link", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"From:", @"")];
	[fromField setStringValue: relativePathFittingInField(fromField, source)];
	[toLabel setStringValue: NSLocalizedString(@"To:", @"")];
	[toField setStringValue: relativePathFittingInField(fromField, destination)];
      }
    else if ([type isEqual: NSWorkspaceDuplicateOperation])
      {
	[win setTitle: NSLocalizedString(@"Duplicate", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"In:", @"")];
	[fromField setStringValue: relativePathFittingInField(fromField, destination)];
	[toLabel setStringValue: @""];
	[toField setStringValue: @""];
      }
    else if ([type isEqual: NSWorkspaceDestroyOperation])
      {
	[win setTitle: NSLocalizedString(@"Destroy", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"In:", @"")];
	[fromField setStringValue: relativePathFittingInField(fromField, destination)];
	[toLabel setStringValue: @""];
	[toField setStringValue: @""];
      }
    else if ([type isEqual: NSWorkspaceRecycleOperation])
      {
	[win setTitle: NSLocalizedString(@"Move", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"From:", @"")];
	[fromField setStringValue: relativePathFittingInField(fromField, source)];
	[toLabel setStringValue: NSLocalizedString(@"To:", @"")];
	[toField setStringValue: NSLocalizedString(@"the Recycler", @"")];
      }
    else if ([type isEqual: @"WorkspaceRecycleOutOperation"])
      {
	[win setTitle: NSLocalizedString(@"Move", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"From:", @"")];
	[fromField setStringValue: NSLocalizedString(@"the Recycler", @"")];
	[toLabel setStringValue: NSLocalizedString(@"To:", @"")];
	[toField setStringValue: relativePathFittingInField(fromField, destination)];
      }
    else if ([type isEqual: @"WorkspaceemptyTrashOperation"])
      {
	[win setTitle: NSLocalizedString(@"Destroy", @"")];
	[fromLabel setStringValue: NSLocalizedString(@"In:", @"")];
	[fromField setStringValue: NSLocalizedString(@"the Recycler", @"")];
	[toLabel setStringValue: @""];
	[toField setStringValue: @""];
      }

    [progInd setIndeterminate: YES];
    [progInd startAnimation: self];
  }
  
  [win orderFront: nil];
  showwin = YES;
}

- (void)setNumFiles:(int)n
{
  [progInd stopAnimation: self];
  [progInd setIndeterminate: NO];
  [progInd setMinValue: 0.0];
  [progInd setMaxValue: n];
  [progInd setDoubleValue: 0.0];
}

- (void)setProgIndicatorValue:(int)n
{
  [progInd setDoubleValue: n];
}

- (void)cleanUpExecutor
{
  if (executor)
    {
      [nc removeObserver: self
                    name: NSConnectionDidDieNotification 
                  object: execconn];
      [execconn setRootObject:nil];
      DESTROY (executor);
      DESTROY (execconn);
    }
}

- (void)endOperation
{
  if (showwin)
    {
      if ([progInd isIndeterminate])
        [progInd stopAnimation:self];

      [win saveFrameUsingName: @"fopinfo"];
      [win close];
    }

  /* The executor's error handlers end an operation early, before its run
   * has reported what it did, and the run ends it again afterwards: the
   * history gets the first end that has something to undo, once. */
  if (undoReported == NO && [completedItems count] > 0)
    {
      undoReported = YES;
      [[GWFileUndoStack sharedStack] fileOperation: type
                                didFinishWithItems: completedItems
                                              role: undoRole];
    }

  [controller endOfFileOperation: self];
  [execconn setRootObject:nil];
}

- (void)sendWillChangeNotification
{
  CREATE_AUTORELEASE_POOL(arp);
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];	
  NSUInteger i;

  notifNames = [NSMutableArray new];

  for (i = 0; i < [files count]; i++)
    {
      NSDictionary *fdict = [files objectAtIndex: i];
      NSString *name = [fdict objectForKey: @"name"];
      [notifNames addObject: name];
    }

  [dict setObject: type forKey: @"operation"];	
  [dict setObject: source forKey: @"source"];	
  if (destination != nil)
    [dict setObject: destination forKey: @"destination"];	
  [dict setObject: notifNames forKey: @"files"];	

  [nc postNotificationName: @"GWFileSystemWillChangeNotification" object: dict];

  [dnc postNotificationName: @"GWFileSystemWillChangeNotification" object: nil userInfo: dict];
  RELEASE (arp);
}

- (void)sendDidChangeNotification
{
  CREATE_AUTORELEASE_POOL(arp);
  NSMutableDictionary *notifObj = [NSMutableDictionary dictionary];		

  [notifObj setObject: type forKey: @"operation"];	
  [notifObj setObject: source forKey: @"source"];	
  if (destination != nil)
    [notifObj setObject: destination forKey: @"destination"];	
  
  if (cachedProcessedFilesData) {
    NSData *data = cachedProcessedFilesData;
    NSArray *processedFiles = [NSUnarchiver unarchiveObjectWithData: data];
    
    [notifObj setObject: processedFiles forKey: @"files"];	
    [notifObj setObject: notifNames forKey: @"origfiles"];	
  } else {
    [notifObj setObject: notifNames forKey: @"files"];
    [notifObj setObject: notifNames forKey: @"origfiles"];	
  }
  
  opdone = YES;			

  [nc postNotificationName: @"GWFileSystemDidChangeNotification" object: notifObj];

  [dnc postNotificationName: @"GWFileSystemDidChangeNotification" object: nil userInfo: notifObj];  
  RELEASE (arp);
}

- (void)registerExecutor:(id)anObject
{
  NSData *opinfo = [NSArchiver archivedDataWithRootObject: operationDict];
  BOOL samename;

  [anObject setProtocolForProxy: @protocol(FileOpExecutorProtocol)];
  executor = (id <FileOpExecutorProtocol>)[anObject retain];
  
  [executor setOperation: opinfo];

  if ([procFiles count] == 0)
    {
      samename = [executor checkSameName];
      
      if (samename)
        {
          NSString *msg = nil;
          NSString *title = nil;
          int result;
    
          onlyOlder = NO;
          if ([type isEqual: NSWorkspaceMoveOperation])
            {	
              msg = @"Some items have the same name;\ndo you want to replace them?";
              title = @"Move";		
            }
          else if ([type isEqual: NSWorkspaceCopyOperation])
            {
              msg = @"Some items have the same name;\ndo you want to replace them?";
              title = @"Copy";
            }
          else if ([type isEqual: NSWorkspaceLinkOperation]) 
            {
              msg = @"Some items have the same name;\ndo you want to replace them?";
              title = @"Link";
            }
          else if ([type isEqual: NSWorkspaceRecycleOperation])
            {
              msg = @"Some items have the same name;\ndo you want to replace them?";
              title = @"Recycle";
            }
          else if ([type isEqual: @"WorkspaceRecycleOutOperation"])
            {
              msg = @"Some items have the same name;\ndo you want to replace them?";
              title = @"Recycle";
            }
      
          result = NSRunAlertPanel(NSLocalizedString(title, @""),							 NSLocalizedString(msg, @""),
                                   NSLocalizedString(@"OK", @""), 
                                   NSLocalizedString(@"Cancel", @""), 
                                   NSLocalizedString(@"Only older", @"")); 
      
          if (result == NSAlertAlternateReturn)
            {
              [controller endOfFileOperation: self];
              return;   
            }
          else if (result == NSAlertOtherReturn) 
            {  
              onlyOlder = YES;
            }
        }
    }

  [executor setOnlyOlder:onlyOlder];
      
  if (showwin)
    [self showProgressWin];

  [self sendWillChangeNotification]; 
  
  stopped = NO;
  paused = NO;   
  [executor calculateNumFiles:[procFiles count]];
}

- (BOOL)connection:(NSConnection*)ancestor 
shouldMakeNewConnection:(NSConnection*)newConn
{
  if (ancestor == execconn)
    {
      [newConn setDelegate: self];
      [nc addObserver: self 
	  selector: @selector(connectionDidDie:)
	  name: NSConnectionDidDieNotification 
	  object: newConn];
      return YES;
    }
  
  return NO;
}

- (void)connectionDidDie:(NSNotification *)notification
{
  [nc removeObserver: self
	              name: NSConnectionDidDieNotification 
              object: [notification object]];

  if (opdone == NO)
    {
      NSRunAlertPanel(nil,
		      NSLocalizedString(@"executor connection died!", @""),
		      NSLocalizedString(@"Continue", @""),
		      nil,
		      nil);
      [self sendDidChangeNotification];
      [self endOperation];
    }
}

- (NSString *)type
{
  return type;
}

- (NSString *)source
{
  return source;
}

- (NSString *)destination
{
  return destination;
}

- (NSArray *)files
{
  return files;
}

- (NSArray *)dupfiles
{
  return dupfiles;
}

- (int)ref
{
  return ref;
}

- (BOOL)showsWindow
{
  return showwin;
}

- (NSWindow *)win
{
  return win;
}

- (void) getWinRect: (NSRect*)rptr
{
  *rptr = NSZeroRect;
  if (win && [win isVisible])
    {
      *rptr = [win frame];
    }
}

@end


@implementation FileOpExecutor

+ (void)setPorts:(NSArray *)thePorts
{
  CREATE_AUTORELEASE_POOL(pool);
  NSPort *port[2];
  NSConnection *conn;
  FileOpExecutor *executor;

  port[0] = [thePorts objectAtIndex: 0];             
  port[1] = [thePorts objectAtIndex: 1];             

  conn = [NSConnection connectionWithReceivePort: (NSPort *)port[0]
                                        sendPort: (NSPort *)port[1]];
  
  executor = [[self alloc] init];
  [executor setFileop: thePorts];
  [(id)[conn rootProxy] registerExecutor: executor];
  RELEASE (executor);
  
  RELEASE (pool);
}

- (void)dealloc
{
  RELEASE (operation);
  RELEASE (source);
  RELEASE (destination);
  RELEASE (files);
  RELEASE (procfiles);
  RELEASE (doneitems);
  RELEASE (metaCopier);
  [super dealloc];
}

- (id)init
{
  self = [super init];
  
  if (self) {
    fm = [NSFileManager defaultManager];
    metaCopier = [GWMetadataCopier new];
		samename = NO;
    onlyolder = NO;
  }
  
  return self;
}

- (void)setFileop:(NSArray *)thePorts
{
  NSPort *port[2];
  NSConnection *conn;
  id anObject;
  
  port[0] = [thePorts objectAtIndex: 0];             
  port[1] = [thePorts objectAtIndex: 1];             

  conn = [NSConnection connectionWithReceivePort: (NSPort *)port[0]
                                        sendPort: (NSPort *)port[1]];

  anObject = (id)[conn rootProxy];
  [anObject setProtocolForProxy: @protocol(FileOpInfoProtocol)];
  fileOp = (id <FileOpInfoProtocol>)anObject;
}

- (BOOL)setOperation:(NSData *)opinfo
{
  NSDictionary *opDict = [NSUnarchiver unarchiveObjectWithData: opinfo];
  id dictEntry;

  dictEntry = [opDict objectForKey: @"operation"];
  if (dictEntry) {
    ASSIGN (operation, dictEntry);   
  } 

  dictEntry = [opDict objectForKey: @"source"];
  if (dictEntry) {
    ASSIGN (source, dictEntry);
  }  

  dictEntry = [opDict objectForKey: @"destination"];
  if (dictEntry) {
    ASSIGN (destination, dictEntry);
  }  

  files = [NSMutableArray new];
  dictEntry = [opDict objectForKey: @"files"];
  if (dictEntry) {
    [files addObjectsFromArray: dictEntry];
  }		
  
  procfiles = [NSMutableArray new];
  doneitems = [NSMutableArray new];
  
  return YES;
}

- (BOOL)checkSameName
{
  NSArray *dirContents;
  NSUInteger i;

  samename = NO;

  if (([operation isEqual: @"WorkspaceRenameOperation"])
        || ([operation isEqual: @"WorkspaceCreateDirOperation"])
        || ([operation isEqual: @"WorkspaceCreateFileOperation"])) {
    /* already checked by Workspace */
	  return NO;
  }
  
  if (destination && [files count])
    {
      dirContents = [fm directoryContentsAtPath: destination];
      for (i = 0; i < [files count]; i++)
        {
          NSDictionary *dict = [files objectAtIndex: i];
          NSString *name = [dict objectForKey: @"name"]; 
    
          if ([dirContents containsObject: name])
            {
              samename = YES;
              break;
            }
        }
    }
	
  if (samename)
    {
      if (([operation isEqual: NSWorkspaceMoveOperation]) 
          || ([operation isEqual: NSWorkspaceCopyOperation])
          || ([operation isEqual: NSWorkspaceLinkOperation])
          || ([operation isEqual: @"WorkspaceRecycleOutOperation"]))
        {
          return YES;
        }
      else if (([operation isEqual: NSWorkspaceDestroyOperation]) 
               || ([operation isEqual: NSWorkspaceDuplicateOperation])
               || ([operation isEqual: NSWorkspaceRecycleOperation])
               || ([operation isEqual: @"WorkspaceemptyTrashOperation"]))
        {
          return NO;
        } 
    }
  
  return NO;
}

- (void)setOnlyOlder:(BOOL)flag
{
  onlyolder = flag;
}

- (oneway void)calculateNumFiles:(NSUInteger)continueFrom
{
  NSUInteger i;
  NSUInteger fnum = 0;

  if (continueFrom == 0)
    {
      for (i = 0; i < [files count]; i++)
        {
          CREATE_AUTORELEASE_POOL (arp);
          NSDictionary *dict = [files objectAtIndex: i];
          NSString *name = [dict objectForKey: @"name"]; 
          NSString *path = [source stringByAppendingPathComponent: name];       
          BOOL isDir = NO;
          
          [fm fileExistsAtPath: path isDirectory: &isDir];
          
          if (isDir)
            {
              NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath: path];
              
              while (1)
                {
                  CREATE_AUTORELEASE_POOL (arp2);
                  NSString *dirEntry = [enumerator nextObject];
                  
                  if (dirEntry)
                    {
                      if (stopped)
                        {
                          RELEASE (arp2);
                          break;
                        }
                      fnum++;
                    }
                  else
                    {
                      RELEASE (arp2);
                      break;
                    }
                  RELEASE (arp2);
                }
            }
          else
            {
              fnum++;
            }
          
          if (stopped)
            {
              RELEASE (arp);
              break;
            }
          RELEASE (arp);
        }
      
      if (stopped)
        {
          [fileOp endOperation];
          [fileOp cleanUpExecutor];
        }
      
      fcount = 0;
      stepcount = 0;
      
      if (fnum < PROGR_STEPS)
        {
          progstep = 1.0;
        }
      else
        {
          progstep = fnum / PROGR_STEPS;
        }
      [fileOp setNumFiles: fnum];
    }
  else
    {
      fcount = continueFrom;
      stepcount = continueFrom;
    }
  [self performOperation];
}

- (oneway void)performOperation
{
  canupdate = YES; 

  if ([operation isEqual: NSWorkspaceMoveOperation]
      || [operation isEqual: @"WorkspaceRecycleOutOperation"])
    {
      [self doMove];
    }
  else if ([operation isEqual: NSWorkspaceCopyOperation])
    {  
      [self doCopy];
    }
  else if ([operation isEqual: NSWorkspaceLinkOperation])
    {
      [self doLink];
    }
  else if ([operation isEqual: FSNWorkspaceCreateAliasOperation])
    {
      [self doAlias];
    }
  else if ([operation isEqual: NSWorkspaceDestroyOperation]
	   || [operation isEqual: @"WorkspaceemptyTrashOperation"])
    {
      [self doRemove];
    }
  else if ([operation isEqual: NSWorkspaceDuplicateOperation])
    {
      [self doDuplicate];
    }
  else if ([operation isEqual: NSWorkspaceRecycleOperation])
    {
      [self doTrash];
    }
  else if ([operation isEqual: @"WorkspaceRenameOperation"])
    {
      [self doRename];
    }
  else if ([operation isEqual: @"WorkspaceCreateDirOperation"])
    {
      [self doNewFolder];
    }
  else if ([operation isEqual: @"WorkspaceCreateFileOperation"])
    {
      [self doNewFile];
    }
}

- (NSData *)processedFiles
{
  return [NSArchiver archivedDataWithRootObject: procfiles];
}

- (NSData *)completedItemsData
{
  return [NSArchiver archivedDataWithRootObject: doneitems];
}

/* Where each item went is what undo needs; the processed names alone do
 * not say it once the Trash or Duplicate picked another name. */
- (void)noteDone:(NSString *)name from:(NSString *)src to:(NSString *)dst
{
  NSMutableDictionary *item = [NSMutableDictionary dictionaryWithCapacity: 2];

  if (src != nil)
    [item setObject: src forKey: GWFileUndoFromKey];
  [item setObject: dst forKey: GWFileUndoToKey];
  [procfiles addObject: name];
  [doneitems addObject: item];
}

- (void)reportProgress
{
  [fileOp cacheProcessedFiles: [self processedFiles]];
  [fileOp cacheCompletedItems: [self completedItemsData]];
  [fileOp sendDidChangeNotification];
}

/* End of a run over many files, which may also end in a pause. */
- (void)finishBatch
{
  [self reportProgress];
  if (([files count] == 0) || stopped)
    {
      [fileOp endOperation];
    }
  else if (paused)
    {
      [fileOp removeProcessedFiles];
    }
  [fileOp cleanUpExecutor];
}

- (void)finishSingle
{
  [self reportProgress];
  [fileOp endOperation];
  [fileOp cleanUpExecutor];
}

#define CHECK_DONE \
if (([files count] == 0) || stopped || paused) break

#define GET_FILENAME \
fileinfo = [files objectAtIndex: 0]; \
RETAIN (fileinfo); \
filename = [fileinfo objectForKey: @"name"];

- (void)doMove
{
  while (1)
    {
      CHECK_DONE;	
      GET_FILENAME;    

      if ((samename == NO) || (samename && [self removeExisting: fileinfo]))
	{
	  NSString *src = [source stringByAppendingPathComponent: filename];
	  NSString *dst = [destination stringByAppendingPathComponent: filename];
	  
	  if ([self moveItem: src to: dst])
	    {
	      [self noteDone: filename from: src to: dst];
	    }
	  else
	    {
	      /* check for broken symlink */
	      NSDictionary *attributes = [fm fileAttributesAtPath: src traverseLink: NO];
	      
	      if (attributes && ([attributes fileType] == NSFileTypeSymbolicLink) && ([fm fileExistsAtPath: src] == NO))
		{
		  if ([fm copyPath: src toPath: dst handler: self] && [fm removeFileAtPath: src handler: self])
		    {
		      [self noteDone: filename from: src to: dst];
		    }
		}
	    }
	}
      
      [files removeObject: fileinfo];	
      RELEASE (fileinfo);
    }

  [self finishBatch];
}

- (void)doCopy
{
  while (1)
    {
      CHECK_DONE;	
      GET_FILENAME;
      
      if ((samename == NO) || (samename && [self removeExisting: fileinfo]))
        {
          NSString *src = [source stringByAppendingPathComponent: filename];
          NSString *dst = [destination stringByAppendingPathComponent: filename];

          if ([self copyItem: src to: dst])
            {
              [self noteDone: filename from: src to: dst];
            }
        }
      [files removeObject: fileinfo];
      RELEASE (fileinfo); 
    }
  
  [self finishBatch];
}

- (void)doLink
{
  while (1)
    {
      CHECK_DONE;
      GET_FILENAME;

      if ((samename == NO) || (samename && [self removeExisting: fileinfo]))
	{
	  NSString *dst = [destination stringByAppendingPathComponent: filename];
	  NSString *src = [source stringByAppendingPathComponent: filename];

	  if ([fm createSymbolicLinkAtPath: dst pathContent: src])
	    {
	      [procfiles addObject: filename];
	    }
	}
      [files removeObject: fileinfo];
      RELEASE (fileinfo);
    }

  [self finishBatch];
}

/* Create Alias records (not symlinks) for each dropped/menu-selected
 * file.  Alias creation writes one small record per file, so unlike the
 * copy/move executors there is no per-byte progress to report. */
- (void)doAlias
{
  while (1)
    {
      CHECK_DONE;
      GET_FILENAME;

      if ((samename == NO) || (samename && [self removeExisting: fileinfo]))
	{
	  NSString *src = [source stringByAppendingPathComponent: filename];
	  NSString *aliasPath = [FSNAlias writeAliasFileForPath: src
						    inDirectory: destination];

	  if (aliasPath != nil)
	    {
	      [self noteDone: [aliasPath lastPathComponent] from: src to: aliasPath];
	    }
	}
      [files removeObject: fileinfo];
      RELEASE (fileinfo);
    }

  [self finishBatch];
}

- (void)doRemove
{
  while (1)
    {
      CHECK_DONE;
      GET_FILENAME;

      NSString *srcpath = [source stringByAppendingPathComponent: filename];

      if ([fm removeFileAtPath: srcpath handler: self])
        {
          /* Remove AppleDouble sidecar (._filename) if present */
          NSString *scpath = [GWMetadataCopier sidecarPathForPath: srcpath];
          if ([fm fileExistsAtPath: scpath])
            [fm removeFileAtPath: scpath handler: self];

          [procfiles addObject: filename];
        }
      [files removeObject: fileinfo];
      RELEASE (fileinfo);
    }

  [self finishBatch];
}

- (void)doDuplicate
{
  NSString *copystr = NSLocalizedString(@"_copy", @"");
  NSString *base;
  NSString *ext;
  NSString *destpath;
  NSString *newname;
  NSString *ntmp;

  while (1) {
    int count = 1;

	  CHECK_DONE;    
	  GET_FILENAME;  

	  newname = [NSString stringWithString: filename];
    ext = [newname pathExtension]; 
    base = [newname stringByDeletingPathExtension];
    
	  while (1) {
      if (count == 1) {
        ntmp = [NSString stringWithFormat: @"%@%@", base, copystr];
        if ([ext length]) {
          ntmp = [ntmp stringByAppendingPathExtension: ext];
        }
      } else {
        ntmp = [NSString stringWithFormat: @"%@%@%i", base, copystr, count];
        if ([ext length]) {
          ntmp = [ntmp stringByAppendingPathExtension: ext];
        }
      }
      
		  destpath = [destination stringByAppendingPathComponent: ntmp];

		  if ([fm fileExistsAtPath: destpath] == NO) {
        newname = ntmp;
			  break;
      } else {
        count++;
      }
	  }

	  if ([self copyItem: [destination stringByAppendingPathComponent: filename]
				      to: destpath]) {
      [self noteDone: newname
                from: [destination stringByAppendingPathComponent: filename]
                  to: destpath];
    }
	  [files removeObject: fileinfo];
    RELEASE (fileinfo);	       
  }

  [self finishBatch];
}

- (void)doRename
{
  GET_FILENAME;    
  
  /* Through the metadata copier like every other move, so that the "._"
   * sidecar keeps following the item to its new name. */
  if ([self moveItem: source to: destination])
    {
      [self noteDone: filename from: source to: destination];
    }
  else
    {
      /* check for broken symlink */
      NSDictionary *attributes = [fm fileAttributesAtPath: source traverseLink: NO];
  
      if (attributes && ([attributes fileType] == NSFileTypeSymbolicLink)
	  && ([fm fileExistsAtPath: source] == NO)) {
	if ([fm copyPath: source toPath: destination handler: self]
	    && [fm removeFileAtPath: source handler: self]) {
	  [self noteDone: filename from: source to: destination];
	}
      }
    }
  
  [files removeObject: fileinfo];
  RELEASE (fileinfo);	

  [self finishSingle];
}

- (void)doNewFolder
{
  GET_FILENAME;  

  NSString *dirpath = [destination stringByAppendingPathComponent: filename];

  if ([fm createDirectoryAtPath: dirpath attributes: nil]) {
    [self noteDone: filename from: nil to: dirpath];
  }
  [files removeObject: fileinfo];	
  RELEASE (fileinfo);

  [self finishSingle];
}

- (void)doNewFile
{
  GET_FILENAME;  

  if ([fm createFileAtPath: [destination stringByAppendingPathComponent: filename]
		  contents: nil
                attributes: nil]) {
    [procfiles addObject: filename];
  }
  [files removeObject: fileinfo];	
  RELEASE (fileinfo);
  
  [self finishSingle];
}

- (void)doTrash
{
  NSString *copystr = NSLocalizedString(@"_copy", @"");
  NSString *srcpath;
  NSString *destpath;
  NSString *newname;
  NSString *ntmp;

  while (1)
    {
      CHECK_DONE;      
      GET_FILENAME;  
      
    newname = [NSString stringWithString: filename];
    srcpath = [source stringByAppendingPathComponent: filename];
    destpath = [destination stringByAppendingPathComponent: newname];
    
    if ([fm fileExistsAtPath: destpath]) {
      NSString *ext = [filename pathExtension]; 
      NSString *base = [filename stringByDeletingPathExtension]; 
      NSUInteger count = 1;
      
	    while (1) {
        if (count == 1) {
          ntmp = [NSString stringWithFormat: @"%@%@", base, copystr];
          if ([ext length]) {
            ntmp = [ntmp stringByAppendingPathExtension: ext];
          }
        } else {
          ntmp = [NSString stringWithFormat: @"%@%@%lu", base, copystr, (unsigned long)count];
          if ([ext length]) {
            ntmp = [ntmp stringByAppendingPathExtension: ext];
          }
        }

		    destpath = [destination stringByAppendingPathComponent: ntmp];

		    if ([fm fileExistsAtPath: destpath] == NO) {
          newname = ntmp;
			    break;
        } else {
          count++;
        }
	    }
    }

	  if ([self moveItem: srcpath to: destpath]) {
      [self noteDone: newname from: srcpath to: destpath];
    } else {
      /* check for broken symlink */
      NSDictionary *attributes = [fm fileAttributesAtPath: srcpath traverseLink: NO];
    
      if (attributes && ([attributes fileType] == NSFileTypeSymbolicLink)
                                  && ([fm fileExistsAtPath: srcpath] == NO)) {
        if ([fm copyPath: srcpath toPath: destpath handler: self]
                          && [fm removeFileAtPath: srcpath handler: self]) {
          [self noteDone: newname from: srcpath to: destpath];
        }
      }
    }
    
	  [files removeObject: fileinfo];	 
    RELEASE (fileinfo);  
  }

  [self finishBatch];
}

/* Copying and moving go through GWMetadataCopier because NSFileManager
 * leaves behind everything a Mac keeps beside the data: extended attributes
 * (quarantine, resource fork, tags, other programs' own) and the sidecar. */
- (BOOL)moveItem:(NSString *)src to:(NSString *)dst
{
  NSError *error = nil;
  BOOL moved = [metaCopier moveItemAtPath: src
                                   toPath: dst
                                  handler: self
                            metadataError: &error];

  if (error != nil && ![self continueAfterMetadataError: error])
    stopped = YES;
  return moved;
}

- (BOOL)copyItem:(NSString *)src to:(NSString *)dst
{
  NSError *error = nil;
  BOOL copied = [metaCopier copyItemAtPath: src
                                    toPath: dst
                                   handler: self
                             metadataError: &error];

  if (error != nil && ![self continueAfterMetadataError: error])
    stopped = YES;
  return copied;
}

- (BOOL)continueAfterMetadataError:(NSError *)error
{
  NSString *msg = [NSString stringWithFormat: @"%@ %@\n%@ %@\n",
                     NSLocalizedString(@"File operation error:", @""),
                     [error localizedDescription],
                     NSLocalizedString(@"with file:", @""),
                     [[error userInfo] objectForKey: NSFilePathErrorKey]];

  return [fileOp requestUserConfirmationWithMessage: msg title: @"Error"]
           == NSAlertDefaultReturn;
}

- (BOOL)removeExisting:(NSDictionary *)info
{
  NSString *fname =  [info objectForKey: @"name"];
  NSString *destpath = [destination stringByAppendingPathComponent: fname]; 
  BOOL isdir;
    
  canupdate = NO; 
  
  if ([fm fileExistsAtPath: destpath isDirectory: &isdir])
    {
      if (onlyolder)
	{
	  NSDictionary *attributes = [fm fileAttributesAtPath: destpath traverseLink: NO];
	  NSDate *dstdate = [attributes objectForKey: NSFileModificationDate];
	  NSDate *srcdate = [info objectForKey: @"date"];
    
	  if ([srcdate isEqual: dstdate] == NO)
	    {
	      if ([[srcdate earlierDate: dstdate] isEqual: srcdate])
		{
		  canupdate = YES;
		  return NO;
		}
	    }
	  else
	    {
	      canupdate = YES;
	      return NO;
	    }
	}
  
      [fm removeFileAtPath: destpath handler: self]; 
    }
  
  canupdate = YES;
  
  return YES;
}

- (NSDictionary *)infoForFilename:(NSString *)name
{
  int i;

  for (i = 0; i < [files count]; i++) {
    NSDictionary *info = [files objectAtIndex: i];

    if ([[info objectForKey: @"name"] isEqual: name]) {
      return info;
    }
  }
  
  return nil;
}


- (BOOL)fileManager:(NSFileManager *)manager 
              shouldProceedAfterError:(NSDictionary *)errorDict
{  
  NSString *path;
  NSString *error;
  NSString *msg;
  int result;

  error = [errorDict objectForKey: @"Error"];

  if ([error hasPrefix: @"Unable to change NSFileOwnerAccountID to to"]
        || [error hasPrefix: @"Unable to change NSFileOwnerAccountName to"]
        || [error hasPrefix: @"Unable to change NSFileGroupOwnerAccountID to"]
        || [error hasPrefix: @"Unable to change NSFileGroupOwnerAccountName to"]
        || [error hasPrefix: @"Unable to change NSFilePosixPermissions to"]
        || [error hasPrefix: @"Unable to change NSFileModificationDate to"]) {
    return YES;
  }

  path = [NSString stringWithString: [errorDict objectForKey: @"NSFilePath"]];
  
  msg = [NSString stringWithFormat: @"%@ %@\n%@ %@\n",
							NSLocalizedString(@"File operation error:", @""),
							error,
							NSLocalizedString(@"with file:", @""),
							path];

  result = [fileOp requestUserConfirmationWithMessage: msg title: @"Error"];
    
  if (result != NSAlertDefaultReturn)
    {
      [fileOp endOperation];
      [fileOp cleanUpExecutor];
    }
  else
    {  
      BOOL found = NO;
    
      while (1)
	{ 
	  NSDictionary *info = [self infoForFilename: [path lastPathComponent]];
          
	  if ([path isEqual: source])
	    break;      
     
	  if (info)
	    {
	      [files removeObject: info];
	      found = YES;
	      break;
	    }
         
	  path = [path stringByDeletingLastPathComponent];
	}   
    
    if ([files count])
      {
        if (found)
          {
            [self performOperation]; 
          }
        else
          {
            [fileOp showErrorAlertWithMessage: @"File Operation Error!"];
            [fileOp endOperation];
            [fileOp cleanUpExecutor];
          }
      }
    else
      {
        [fileOp endOperation];
        [fileOp cleanUpExecutor];
    }
  }
  
  return YES;
}

- (void)fileManager:(NSFileManager *)manager willProcessPath:(NSString *)path
{
  if (canupdate) {
    fcount++;
    stepcount++;
    
    if (stepcount >= progstep) {
      stepcount = 0;
      [fileOp setProgIndicatorValue: fcount];
    }
  }
  
  if (stopped)
    {
      [fileOp endOperation];
      [fileOp cleanUpExecutor];
    }                                             
}

@end

