# setbws.py: one BrowserWindowState entry for ~/Desktop/mi/c1/sub in column view
import os
from Foundation import NSMutableDictionary, NSNumber
p = os.path.expanduser('~/Library/Preferences/com.apple.finder.plist')
d = NSMutableDictionary.dictionaryWithContentsOfFile_(p)
base = 'file://localhost/Users/user/Desktop/'
e = {'BrowserViewState': {'ColumnViewInnerScrollOrigins': ['{0, 0}', '{0, 0}', '{0, 0}', '{0, 0}'],
                          'ColumnViewOuterScrollOrigin': '{0, 0}'},
     'ShowPathbar': NSNumber.numberWithBool_(False), 'ShowSidebar': NSNumber.numberWithBool_(True),
     'ShowStatusBar': NSNumber.numberWithBool_(True), 'ShowToolbar': NSNumber.numberWithBool_(True),
     'SidebarWidth': NSNumber.numberWithInt_(150),
     'TargetPath': [base, base + 'mi/', base + 'mi/c1/', base + 'mi/c1/sub/'],
     'TargetURL': base + 'mi/c1/sub/', 'ViewStyle': 'Column',
     'WindowBounds': '{{100, 100}, {800, 300}}'}
d['BrowserWindowState'] = [e]
print d.writeToFile_atomically_(p, True)
