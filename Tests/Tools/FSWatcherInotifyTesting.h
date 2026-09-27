/* FSWatcherInotifyTesting.h - test-only category on FSWatcher shared by the
 * fswatcher-inotify test tools.
 *
 * Interface and implementation live together because each test tool is its
 * own translation unit that #includes fswatcher-inotify.m (in-process unit
 * under test); include this header right after that include.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* FSWatcher's watch-descriptor maps are @protected ivars; a category's
 * methods have the same access as the class's own, so this reaches them
 * without touching production code and without driving the full
 * NSConnection/client machinery that -client:addWatcherForPath: needs
 * (it would also collide with a real "fswatcher" DO name already
 * registered on this machine). */
@interface FSWatcher (SprintToolsTesting)
- (void)test_setUpForTesting;
- (void)test_installWatcher:(Watcher *)watcher forPath:(NSString *)path wd:(int)wd;
- (BOOL)test_hasWatcherForPath:(NSString *)path;
- (BOOL)test_hasWatchDescriptor:(int)wd;
@end

@implementation FSWatcher (SprintToolsTesting)

- (void)test_setUpForTesting
{
  /* Only the state -inotifyDataReady:, -removeWatcher: and -dealloc actually
   * read; skipping the designated -init avoids registering a real
   * "fswatcher" NSConnection name, which would collide with a daemon
   * already running on the test host. */
  clientsInfo = [NSMutableArray new];
  watchers = NSCreateMapTable(NSObjectMapKeyCallBacks,
                               NSObjectMapValueCallBacks, 0);
  watchDescrMap = NSCreateMapTable(NSIntMapKeyCallBacks,
                                    NSNonOwnedPointerMapValueCallBacks, 0);
  includePathsTree = newTreeWithIdentifier(@"t_incl");
  excludePathsTree = newTreeWithIdentifier(@"t_excl");
  excludedSuffixes = [[NSMutableSet alloc] initWithCapacity: 1];
  inotifyPendingData = [[NSMutableData alloc] initWithCapacity: 4096];
}

- (void)test_installWatcher:(Watcher *)watcher forPath:(NSString *)path wd:(int)wd
{
  NSMapInsert(watchers, path, watcher);
  NSMapInsert(watchDescrMap, (void *)(intptr_t)wd, (void *)watcher);
}

- (BOOL)test_hasWatcherForPath:(NSString *)path
{
  return NSMapGet(watchers, path) != NULL;
}

- (BOOL)test_hasWatchDescriptor:(int)wd
{
  return NSMapGet(watchDescrMap, (void *)(intptr_t)wd) != NULL;
}

@end
