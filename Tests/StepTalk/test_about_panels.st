"Show both About panels.
 Usage: stalk Workspace Tests/StepTalk/test_about_panels.st"

| app delegate runLoop |

app := Application.
delegate := app delegate.
runLoop := NSRunLoop currentRunLoop.

Transcript show: 'Calling showAboutThisComputer:...'; cr.
delegate showAboutThisComputer: nil.
runLoop runUntilDate: (NSDate dateWithTimeIntervalSinceNow: 2).

Transcript show: 'Calling showInfo:...'; cr.
delegate showInfo: nil.
runLoop runUntilDate: (NSDate dateWithTimeIntervalSinceNow: 2).

Transcript show: 'Done. Both panels should be on screen.'; cr.
