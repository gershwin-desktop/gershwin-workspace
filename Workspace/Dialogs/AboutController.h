/* AboutController.h
 *
 * Date: January 2026
 */

#import <AppKit/AppKit.h>

@interface AboutController : NSObject <NSWindowDelegate>
{
    NSWindow *aboutWindow;
    NSTextField *osNameField;
    NSTextField *osVersionField;
    NSTextField *osField;
    NSTextField *processorField;
    NSTextField *memoryField;
    NSTextField *modelNumberField;
    NSTextField *kernelField;
    NSTextField *x11Field;
    NSImageView *computerImageView;
    NSString *systemProfilerPath;
}

+ (AboutController *)sharedController;
- (void)showAboutWindow:(id)sender;
- (void)moreInfo:(id)sender;

@end
