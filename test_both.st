"Show both info panels and close them.
 Usage: stalk Workspace test_both.st"

| app runLoop p1 p2 |

app := Application.
runLoop := NSRunLoop currentRunLoop.

"Panel 1: Standard Info panel (Eau swizzles title to 'About Workspace')"
p1 := GSInfoPanel alloc initWithDictionary: nil.
p1 setTitle: 'Info'.
p1 orderFront: nil.
runLoop runUntilDate: (NSDate dateWithTimeIntervalSinceNow: 2).

"Panel 2: About Workspace panel"
p2 := GSInfoPanel alloc initWithDictionary: nil.
p2 setTitle: 'About Workspace'.
p2 orderFront: nil.
runLoop runUntilDate: (NSDate dateWithTimeIntervalSinceNow: 2).

p1 close.
p2 close.
runLoop runUntilDate: (NSDate dateWithTimeIntervalSinceNow: 1).
