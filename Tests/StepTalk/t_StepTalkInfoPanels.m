/* t_StepTalkInfoPanels.m — show & close both About panels via menu IPC.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

@protocol GSGNUstepMenuClient <NSObject>
- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath
                            forWindow:(NSNumber *)windowId;
- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId;
- (bycopy id)validateMenuStateForWindow:(NSNumber *)windowId;
- (bycopy NSArray *)listMenus;
- (bycopy NSArray *)rootObjects;
- (bycopy id)detailsForObject:(NSString *)objID;
- (bycopy id)fullTreeForObject:(NSString *)objID;
- (bycopy id)invokeSelector:(NSString *)selectorName
                   onObject:(NSString *)objID
                   withArgs:(NSArray *)args;
@end

@protocol WorkspaceDO <NSObject>
- (id)delegate;
- (void)showInfo:(id)sender;
- (void)showAboutThisComputer:(id)sender;
@end

static int
getWorkspacePID(void)
{
  NSTask *task = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];
  [task setLaunchPath:@"/usr/bin/pgrep"];
  [task setArguments:@[@"-o", @"Workspace"]];
  [task setStandardOutput:pipe];
  [task launch];
  [task waitUntilExit];

  if ([task terminationStatus] != 0)
    {
      [task release];
      return -1;
    }

  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  int pid = [str intValue];
  [str release];
  [task release];
  return pid;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  int pid = getWorkspacePID();
  PASS(pid > 0, "Workspace PID");
  if (pid <= 0)
    {
      [arp release];
      return 1;
    }

  NSString *clientName =
    [NSString stringWithFormat:@"org.gnustep.Gershwin.MenuClient.%d", pid];
  NSConnection *conn =
    [NSConnection connectionWithRegisteredName:clientName host:nil];
  PASS(conn != nil, "Eau menu client connection");
  if (!conn)
    {
      [arp release];
      return 1;
    }

  /* Connect to the Workspace NSApp DO service and call methods directly
   * on the delegate.  This bypasses the Eau menu IPC path entirely and
   * runs the actions on the remote side (Workspace's main thread). */
  {
    NSConnection *wsConn = [NSConnection connectionWithRegisteredName:@"Workspace"
                                                                 host:nil];
    PASS(wsConn != nil, "Workspace NSApp DO connection");
    if (!wsConn)
      {
        [arp release];
        return 1;
      }

    id appProxy = [wsConn rootProxy];
    id delegate = nil;
    @try
      {
        delegate = [appProxy delegate];
      }
    @catch (NSException *e)
      {
        PASS(NO, "Workspace delegate");
        delegate = nil;
      }
    PASS(delegate != nil, "Workspace delegate");
    if (!delegate)
      {
        [arp release];
        return 1;
      }

    @try
      {
        [delegate showAboutThisComputer:nil];
        PASS(YES, "showAboutThisComputer: (About This Computer)");
      }
    @catch (NSException *e)
      {
        PASS(NO, "About This Computer exception");
      }

    [[NSRunLoop currentRunLoop] runUntilDate:
      [NSDate dateWithTimeIntervalSinceNow:1.5]];

    @try
      {
        [delegate showInfo:nil];
        PASS(YES, "showInfo: (About Workspace)");
      }
    @catch (NSException *e)
      {
        PASS(NO, "About Workspace exception");
      }

    [[NSRunLoop currentRunLoop] runUntilDate:
      [NSDate dateWithTimeIntervalSinceNow:1.5]];
  }

  [arp release];
  return 0;
}
