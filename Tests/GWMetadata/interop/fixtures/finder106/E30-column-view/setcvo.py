# setcvo.py key=value ...: write typed StandardViewOptions.ColumnViewOptions into
# com.apple.finder.plist (Finder must be stopped); ints, true/false, else strings
import sys, os
from Foundation import NSMutableDictionary, NSNumber
p = os.path.expanduser('~/Library/Preferences/com.apple.finder.plist')
d = NSMutableDictionary.dictionaryWithContentsOfFile_(p)
svo = NSMutableDictionary.dictionaryWithDictionary_(d.get('StandardViewOptions') or {})
cvo = NSMutableDictionary.dictionaryWithDictionary_(svo.get('ColumnViewOptions') or {})
for kv in sys.argv[1:]:
    k, v = kv.split('=', 1)
    if v in ('true', 'false'): cvo[k] = NSNumber.numberWithBool_(v == 'true')
    elif v.isdigit(): cvo[k] = NSNumber.numberWithInt_(int(v))
    else: cvo[k] = v
svo['ColumnViewOptions'] = cvo
d['StandardViewOptions'] = svo
print d.writeToFile_atomically_(p, True)
