#import <Foundation/Foundation.h>

// Stand-in for the Workspace application class. FSNIcon looks up the class
// named by the DesktopApplicationName/DesktopApplicationSelName defaults when
// it is first used and calls the selector on it, so the stub has to answer
// +gworkspace as the real class does. A missing selector only shows up at run
// time, which is how this tool once broke.
@interface Workspace : NSObject
+ (Workspace *)gworkspace;
@end

@implementation Workspace

+ (Workspace *)gworkspace
{
  static Workspace *shared = nil;

  if (shared == nil)
    {
      shared = [[Workspace alloc] init];
    }
  return shared;
}

@end
