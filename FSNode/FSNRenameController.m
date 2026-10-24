/*
 * FSNRenameController.m - the one place that runs renaming an item in place,
 * for the icon, list and column views and the desktop.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "FSNRenameController.h"
#import "FSNRenamePolicy.h"
#import "FSNodeRep.h"
#import "FSNode.h"
#import "FSNFunctions.h"

static FSNRenameController *sharedController = nil;

/* Renaming goes on while a panel is open next to the window (Workspace
   shows some alerts in a modal run loop mode without blocking its other
   windows), so its timers run in those modes too. */
static NSArray *FSNRenameRunLoopModes(void)
{
  return [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                                    NSEventTrackingRunLoopMode, nil];
}

/* Localized from FSNode's own tables, so every host shows the same words. */
static NSString *FSNRenameText(NSString *key)
{
  return NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleForClass: [FSNRenameController class]], @"");
}

@interface FSNRenameController (Private)
- (void)pendingTimerFired:(NSTimer *)timer;
- (void)windowDidResignKey:(NSNotification *)notification;
- (void)endSession;
- (void)finishEditingCommitting:(BOOL)commit;
- (void)fileSystemDidChange:(NSNotification *)notification;
- (void)selectRenamedItem;
@end

@implementation FSNRenameController

+ (FSNRenameController *)sharedController
{
  if (sharedController == nil)
    sharedController = [FSNRenameController new];
  return sharedController;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSString *appName = [defaults stringForKey: @"DesktopApplicationName"];
      NSString *selName = [defaults stringForKey: @"DesktopApplicationSelName"];

      if (appName && selName)
        {
          Class desktopAppClass = [[NSBundle mainBundle] classNamed: appName];
          SEL sel = NSSelectorFromString(selName);

          _desktopApp = [desktopAppClass performSelector: sel];
        }

      /* Workspace's own notice that a file operation has gone through; the
	 renamed item is selected again once its view shows the new name. */
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(fileSystemDidChange:)
                                                   name: @"GWFileSystemDidChangeNotification"
                                                 object: nil];
    }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [self cancelScheduledRename];
  [self endSession];
  RELEASE(_renamedSource);
  RELEASE(_renamedPath);
  RELEASE(_selectPath);
  RELEASE(_renamedHost);
  [super dealloc];
}

- (void)scheduleRenameOfRep:(id)rep inHost:(id<FSNRenameHost>)host
{
  [self cancelScheduledRename];
  ASSIGN(_pendingRep, rep);
  _pendingHost = host;
  /* The reference waits the double-click interval: a second click within
     it opens the item instead. */
  ASSIGN(_pendingTimer, [NSTimer timerWithTimeInterval: [NSEvent doubleClickInterval]
                                                target: self
                                              selector: @selector(pendingTimerFired:)
                                              userInfo: nil
                                               repeats: NO]);
  {
    NSArray *modes = FSNRenameRunLoopModes();
    NSUInteger i;

    for (i = 0; i < [modes count]; i++)
      [[NSRunLoop currentRunLoop] addTimer: _pendingTimer forMode: [modes objectAtIndex: i]];
  }
}

- (void)cancelScheduledRename
{
  [_pendingTimer invalidate];
  DESTROY(_pendingTimer);
  DESTROY(_pendingRep);
  _pendingHost = nil;
}

- (BOOL)beginRenameOfRep:(id)rep inHost:(id<FSNRenameHost>)host
{
  NSTextField *editor;
  FSNode *node;
  NSText *fieldEditor;
  BOOL plainFolder;

  [self cancelScheduledRename];
  [self commitActiveEditing];

  editor = [host nameEditorForRenamingRep: rep];
  if (editor == nil || [editor window] == nil || [editor respondsToSelector: @selector(node)] == NO)
    return NO;
  node = [(id)editor node];
  if (node == nil)
    return NO;

  ASSIGN(_editor, editor);
  ASSIGN(_node, node);
  _host = host;

  /* While editing, the name sits in a text field of the theme, as in the
     reference, wherever it is shown. */
  ASSIGN(_savedBackground, [editor backgroundColor]);
  ASSIGN(_savedTextColor, [editor textColor]);
  _savedBordered = [editor isBordered];
  _savedBezeled = [editor isBezeled];
  _savedDrawsBackground = [editor drawsBackground];
  [editor setDrawsBackground: YES];
  [editor setBackgroundColor: [NSColor textBackgroundColor]];
  [editor setTextColor: [NSColor textColor]];
  [editor setBezeled: YES];

  /* Tab and Shift-Tab move the focus from the field to its neighbors in
     the key view loop (the theme does that for every field), which ends
     editing; pointing both at the view keeps the focus there, so Tab only
     renames, as in the reference. */
  ASSIGN(_savedNextKeyView, [editor nextKeyView]);
  ASSIGN(_savedViewNextKeyView, [[editor superview] nextKeyView]);
  [editor setNextKeyView: [editor superview]];
  [[editor superview] setNextKeyView: editor];

  [editor setEditable: YES];
  [editor setSelectable: YES];
  [[editor window] makeFirstResponder: editor];

  plainFolder = ([node isDirectory] && [node isPackage] == NO);
  fieldEditor = [editor currentEditor];
  [fieldEditor setSelectedRange:
                 [FSNRenamePolicy initialSelectionForText: [editor stringValue]
                                                     name: [node name]
                                              plainFolder: plainFolder]];

  /* Switching to another window or application keeps the new name. */
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(windowDidResignKey:)
                                               name: NSWindowDidResignKeyNotification
                                             object: [editor window]];
  return YES;
}

- (BOOL)isEditing
{
  return (_editor != nil);
}

- (BOOL)isEditingInHost:(id<FSNRenameHost>)host
{
  return (_editor != nil && _host == host);
}

- (BOOL)commitActiveEditing
{
  BOOL editing = (_editor != nil);

  [self finishEditingCommitting: YES];
  return editing;
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)command
{
  if (control != _editor)
    return NO;

  /* Selectors are compared by name: the runtime can hand a typed copy of
     one that is not the same pointer. */

  /* Escape (which the key bindings send as complete:) keeps the old name. */
  if (sel_isEqual(command, @selector(cancelOperation:))
      || sel_isEqual(command, @selector(complete:)))
    {
      [self finishEditingCommitting: NO];
      return YES;
    }

  /* Return, Enter and Tab rename and leave the item selected; Tab does not
     move on to the next field or item. */
  if (sel_isEqual(command, @selector(insertNewline:))
      || sel_isEqual(command, @selector(insertTab:))
      || sel_isEqual(command, @selector(insertBacktab:))
      || sel_isEqual(command, @selector(insertLineBreak:)))
    {
      [self finishEditingCommitting: YES];
      return YES;
    }
  return NO;
}

- (void)editorDidEndEditing:(NSNotification *)notification
                       node:(FSNode *)node
                       host:(id<FSNRenameHost>)host
{
  NSInteger movement = [[[notification userInfo] objectForKey: @"NSTextMovement"] integerValue];

  /* Editing ended some other way than through this controller (the focus
     went to another field). */
  if ([notification object] == _editor)
    [self finishEditingCommitting: [FSNRenamePolicy textMovementCommits: movement]];
}

- (void)renameNode:(FSNode *)node toEditedText:(NSString *)text
{
  NSString *oldName = [node name];
  NSString *newName = GSRenamedFilename(text, oldName, GSCurrentExtensionDisplayMode());
  BOOL plainFolder = ([node isDirectory] && [node isPackage] == NO);
  NSMutableDictionary *opinfo;

  if (newName == nil)
    return;

  if ([FSNRenamePolicy isValidName: newName] == NO)
    {
      NSRunAlertPanel([NSString stringWithFormat: FSNRenameText(@"The name \"%@\" can't be used."), newName],
                      FSNRenameText(@"Try using a name with fewer characters or no punctuation marks."),
                      FSNRenameText(@"OK"), nil, nil);
      return;
    }

  if ([node isParentWritable] == NO)
    {
      NSRunAlertPanel([NSString stringWithFormat:
                                  FSNRenameText(@"You don't have the necessary permission to rename \"%@\"."),
                                oldName],
                      @"", FSNRenameText(@"OK"), nil, nil);
      return;
    }

  if (_desktopApp != nil && [node isSubnodeOfPath: [_desktopApp trashPath]])
    {
      NSRunAlertPanel(FSNRenameText(@"You can't rename an object that is in the Recycler"),
                      @"", FSNRenameText(@"OK"), nil, nil);
      return;
    }

  if ([FSNRenamePolicy needsHiddenNameConfirmation: newName oldName: oldName])
    {
      if (NSRunAlertPanel(FSNRenameText(@"Are you sure you want to use a name that begins with a dot \".\"?"),
                          FSNRenameText(@"These names are reserved for the system. If you continue, the item will be hidden."),
                          FSNRenameText(@"OK"), FSNRenameText(@"Cancel"), nil) != NSAlertDefaultReturn)
        return;
    }

  if ([FSNRenamePolicy needsExtensionConfirmation: newName oldName: oldName plainFolder: plainFolder])
    {
      NSString *oldExt = [oldName pathExtension];
      NSString *newExt = [newName pathExtension];
      NSString *question;
      NSString *useButton;

      if ([newExt length] > 0)
        {
          question = [NSString stringWithFormat:
                                 FSNRenameText(@"Are you sure you want to change the extension from \".%@\" to \".%@\"?"),
                               oldExt, newExt];
          useButton = [NSString stringWithFormat: FSNRenameText(@"Use .%@"), newExt];
        }
      else
        {
          question = [NSString stringWithFormat:
                                 FSNRenameText(@"Are you sure you want to remove the extension \".%@\"?"),
                               oldExt];
          useButton = FSNRenameText(@"Remove");
        }

      /* Keeping is the default, as in the reference. */
      if (NSRunAlertPanel(question,
                          FSNRenameText(@"If you make this change, your document may open in a different application."),
                          [NSString stringWithFormat: FSNRenameText(@"Keep .%@"), oldExt],
                          useButton, nil) == NSAlertDefaultReturn)
        {
          newName = [FSNRenamePolicy name: newName keepingExtensionOf: oldName];
          if ([newName isEqualToString: oldName])
            return;
        }
    }
  else if (plainFolder && [[newName pathExtension] length] > 0
           && [[newName pathExtension] isEqualToString: [oldName pathExtension]] == NO)
    {
      /* Some extensions turn a folder into a package that shows as one
         file; the user is asked before that happens. */
      if (NSRunAlertPanel(@"",
                          [NSString stringWithFormat: @"%@\"%@\" %@%@",
                                    FSNRenameText(@"Are you sure you want to add the extension"),
                                    [newName pathExtension],
                                    FSNRenameText(@"to the end of the name?"),
                                    FSNRenameText(@"\nif you make this change, your folder may appear as a single file.")],
                          FSNRenameText(@"Cancel"), FSNRenameText(@"OK"), nil) == NSAlertDefaultReturn)
        return;
    }

  if ([FSNRenamePolicy name: newName isTakenAmong: [node subNodeNamesOfParent] oldName: oldName])
    {
      NSRunAlertPanel([NSString stringWithFormat:
                                  FSNRenameText(@"The name \"%@\" is already taken. Please choose a different name."),
                                newName],
                      @"", FSNRenameText(@"OK"), nil, nil);
      return;
    }

  opinfo = [NSMutableDictionary dictionary];
  [opinfo setObject: @"WorkspaceRenameOperation" forKey: @"operation"];
  [opinfo setObject: [node path] forKey: @"source"];
  [opinfo setObject: [[node parentPath] stringByAppendingPathComponent: newName]
             forKey: @"destination"];
  [opinfo setObject: [NSArray arrayWithObject: @""] forKey: @"files"];

  /* The reference keeps the renamed item selected, also through Undo. */
  ASSIGN(_renamedSource, [opinfo objectForKey: @"source"]);
  ASSIGN(_renamedPath, [opinfo objectForKey: @"destination"]);
  ASSIGN(_renamedHost, _committingHost);
  [_desktopApp performFileOperation: opinfo];
}

@end

@implementation FSNRenameController (Private)

- (void)pendingTimerFired:(NSTimer *)timer
{
  id rep = AUTORELEASE(RETAIN(_pendingRep));
  id<FSNRenameHost> host = _pendingHost;

  DESTROY(_pendingTimer);
  DESTROY(_pendingRep);
  _pendingHost = nil;
  if (rep != nil && host != nil)
    [self beginRenameOfRep: rep inHost: host];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
  [self commitActiveEditing];
}

- (void)fileSystemDidChange:(NSNotification *)notification
{
  NSDictionary *info = [notification object];
  NSString *source;
  NSString *destination;

  if (_renamedPath == nil || [info isKindOfClass: [NSDictionary class]] == NO
      || [[info objectForKey: @"operation"] isEqual: @"WorkspaceRenameOperation"] == NO)
    return;

  source = [info objectForKey: @"source"];
  destination = [info objectForKey: @"destination"];
  /* The rename itself or its redo, or its undo. */
  if (([source isEqual: _renamedSource] && [destination isEqual: _renamedPath])
      || ([source isEqual: _renamedPath] && [destination isEqual: _renamedSource]))
    {
      ASSIGN(_selectPath, destination);
      /* After every view has taken the change in. */
      [self performSelector: @selector(selectRenamedItem) withObject: nil afterDelay: 0.0
                    inModes: FSNRenameRunLoopModes()];
    }
}

- (void)selectRenamedItem
{
  NSString *path = AUTORELEASE(RETAIN(_selectPath));
  id host = _renamedHost;

  DESTROY(_selectPath);
  if (path == nil || host == nil)
    return;
  if ([host respondsToSelector: @selector(selectRepsOfPaths:)])
    [host selectRepsOfPaths: [NSArray arrayWithObject: path]];
  if ([host respondsToSelector: @selector(scrollSelectionToVisible)])
    [host scrollSelectionToVisible];
}

/* Ends the editing session: takes the editor away, gives the keyboard back
   to the view, and renames when "commit". The field editor is aborted
   rather than asked to resign, which it refuses from inside its own key
   handling (Return, Escape). */
- (void)finishEditingCommitting:(BOOL)commit
{
  NSTextField *editor = AUTORELEASE(RETAIN(_editor));
  FSNode *node = AUTORELEASE(RETAIN(_node));
  id<FSNRenameHost> host = _host;
  NSView *view = [editor superview];
  NSString *text;

  if (editor == nil)
    return;

  if ([editor currentEditor] != nil)
    [editor validateEditing];
  text = [[[editor stringValue] copy] autorelease];

  /* The session is over before the field editor goes: taking it away
     reports the end of editing, which must not come back as a commit. */
  [self endSession];
  [editor abortEditing];
  [host stopRepNameEditing];

  if (view != nil && [view window] != nil && [[view window] firstResponder] != view)
    [[view window] makeFirstResponder: view];

  if (commit && node != nil)
    {
      _committingHost = host;
      [self renameNode: node toEditedText: text];
      _committingHost = nil;
    }
}

- (void)endSession
{
  if (_editor != nil)
    {
      [[NSNotificationCenter defaultCenter] removeObserver: self
                                                      name: NSWindowDidResignKeyNotification
                                                    object: [_editor window]];
      [[_editor superview] setNextKeyView: _savedViewNextKeyView];
      [_editor setNextKeyView: _savedNextKeyView];
      [_editor setBezeled: _savedBezeled];
      [_editor setBordered: _savedBordered];
      [_editor setDrawsBackground: _savedDrawsBackground];
      if (_savedBackground != nil)
        [_editor setBackgroundColor: _savedBackground];
      if (_savedTextColor != nil)
        [_editor setTextColor: _savedTextColor];
      [_editor setNeedsDisplay: YES];
    }
  DESTROY(_savedNextKeyView);
  DESTROY(_savedViewNextKeyView);
  DESTROY(_savedBackground);
  DESTROY(_savedTextColor);
  DESTROY(_editor);
  DESTROY(_node);
  _host = nil;
}

@end
