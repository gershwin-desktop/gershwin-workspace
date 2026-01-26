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
    NSTextField *manufacturerField;
    NSTextField *modelField;
    NSTextField *processorField;
    NSTextField *memoryField;
    NSTextField *kernelField;
    NSTextField *x11Field;
    NSTextField *serialNumberField;
    NSImageView *computerImageView;
}

+ (AboutController *)sharedController;
- (void)showAboutWindow:(id)sender;

@end
