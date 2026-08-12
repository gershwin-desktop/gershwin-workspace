# GWMetadata - file indexing and full-text search

GNUstep metadata indexing and search, similar to Spotlight/Beagle. Files are
extracted, indexed into a per-user SQLite database, and made searchable from
the command line (`mdfind`), from a GUI (`MDFinder`), and programmatically
through the `MDKit` framework.

## Components

| Component | Type | Role |
|---|---|---|
| `gmds` | daemon/tool | Query server. Opens the SQLite database and answers search queries. Registered as the Distributed Objects service `gmds`. |
| `mdextractor` | daemon/tool | Indexer. Walks the configured paths, extracts metadata, and writes it into the same database. Registered as the DO service `mdextractor`. |
| `mdextractor` extractor bundles | bundles (`.extr`) | Understand one file kind each and pull its attributes/text (Abiword, App, Html, Jpeg, OpenOffice, Rtf, Text, Xml; Pdf if PDFKit is present). |
| `MDKit.framework` | framework | Client library: `MDKQuery` (query model) and `MDKQueryManager` (talks to `gmds`, auto-launches it). |
| `mdfind` | CLI tool | Command-line search over the index. |
| `MDFinder.app` | GUI app | Search window with attribute chooser, saved queries, live updates. |
| `MDIndexing.prefPane` | preference pane | SystemPreferences module to configure and start/stop indexing. |

## How the indexing works

1. `mdextractor` reads the configuration from the user defaults (see below),
   builds a tree of the indexable paths, and walks them, skipping excluded
   paths and files whose extension is in the excluded-suffix list.
2. For every file it loads the matching extractor bundle, which returns the
   file's metadata attributes (title, authors, text content, image EXIF
   fields, sizes, dates, and so on).
3. The extracted attributes are normalized into the SQLite database at
   `~/Library/gmds/.db/v4/contents.db` (`contents.db`; the version is `v4`,
   defined in `gmds/dbschema.h`). The tables are:
   - `paths` - every indexed path plus filesystem facts (size, dates,
     owner, type)
   - `words` / `postings` - the word index and the word/path postings used
     for full-text `*term*` matches
   - `attributes` - key/value metadata per path
   - `updated_paths` / `removed_paths` - change tracking
   - `user_paths` / `user_attributes` - user-defined metadata
4. `gmds` opens the same database and runs the SQL produced by `MDKQuery`
   when a client sends a query. Results are streamed back to the client as
   path (+ optional score) lines.
5. `mdextractor` keeps the index current: after the initial pass it watches
   the filesystem (via the Workspace `fswatcher` daemon) and performs
   scheduled rescans, so new/renamed/removed files are reflected in the DB.

Search works from the moment indexing starts; the database is queried while
it is still being filled.

## Starting the daemons

Both daemons accept a `--daemon` flag; run without it they re-exec themselves
as a daemon and exit the calling process.

```sh
# query server (serves mdfind / MDFinder / MDKit clients)
/System/Library/Tools/gmds --daemon

# indexer (extracts and indexes the configured paths)
/System/Library/Tools/mdextractor --daemon
```

The database is created on first run in `~/Library/gmds/.db/v4/contents.db`.

You do not normally have to start `gmds` by hand:

- `mdfind`, `MDFinder`, and any `MDKQueryManager` user auto-launch `gmds`
  when the `gmds` DO service is not reachable
  (`MDKQueryManager -connectGMDs`).
- `mdextractor` is started automatically when indexing is enabled: either by
  the SystemPreferences Indexing pane (press Apply), or by Workspace at
  startup when `GSMetadataIndexingEnabled` is `YES`
  (`Workspace -connectMDExtractor`).

## Autostart

- `gmds` - automatic: it is launched on demand by the first client
  (`mdfind`, `MDFinder`, or any app that uses `MDKit`).
- `mdextractor` - not autostarted by the system on its own. It is started
  whenever a client enables indexing (Indexing pane, or Workspace at login
  when indexing is enabled). To keep the index always up to date without
  waiting for a client, add an autostart entry, e.g. an XDG autostart file
  `~/.config/autostart/gmds-indexing.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=GWMetadata indexer
Exec=/System/Library/Tools/mdextractor --daemon
X-GNOME-Autostart-enabled=true
```

(Or add the same command to your session startup script.)

## Configuration

The preferred way is SystemPreferences -> Indexing (`MDIndexing.prefPane`):

- Indexable paths - directories that are searched for files to index. If the
  list is empty the pane proposes your home directory plus the Applications
  and the GNUstep `Headers`/`Documentation` directories.
- Excluded paths - subdirectories of indexable paths that are skipped.
- Excluded suffixes - file extensions that are never indexed.
- Enable indexing switch + Apply - starts/stops `mdextractor`.
- Show status - shows indexing progress.

The pane stores everything in the user defaults (see next section) and
notifies `mdextractor` of changes.

## Defaults

All keys live in the `NSGlobalDomain` user defaults. `mdextractor` reads them
at startup and on the `GSMetadataIndexedDirectoriesChanged` notification.

| Key | Type | Meaning | Default |
|---|---|---|---|
| `GSMetadataIndexingEnabled` | bool (`YES`/`NO`) | Master switch for indexing | absent (off) |
| `GSMetadataIndexablePaths` | array of strings | Directories whose contents are indexed | absent (empty - nothing indexed until set) |
| `GSMetadataExcludedPaths` | array of strings | Subdirectories to skip | absent (none) |
| `GSMetadataExcludedSuffixes` | array of strings | File extensions to skip | absent (built-in list: `a d dylib er1 err extinfo frag la log o out part sed so status temp tmp`) |

Set them with the GNUstep defaults tool (which understands property-list text,
not Apple's `-array`/`-bool` flags):

```sh
defaults write NSGlobalDomain GSMetadataIndexingEnabled YES
defaults write NSGlobalDomain GSMetadataIndexablePaths "(/home/user, /System/Library/Headers, /System/Library/Documentation)"
defaults write NSGlobalDomain GSMetadataExcludedPaths "()"
defaults write NSGlobalDomain GSMetadataExcludedSuffixes "(tmp, log)"
```

After changing the defaults, restart `mdextractor` so it picks them up.

## Searching the index

The query language is `attribute  operator  value`, combined with `&&` (AND),
`||` (OR), and parentheses.

Operators:
- `==` equal, `!=` not equal
- `<`, `<=`, `>`, `>=` for numeric values and dates

String modifiers:
- append `c` to the value for case-insensitive matching, e.g. `"*gnustep*"c`
- `*` matches any substring, e.g. `"*sqlite*"`

Attributes: use `mdfind -a` for the full list of 70+ `GSMDItem*` attributes
(also in `MDKit/Resources/attributes.plist`). Common ones:

- `GSMDItemTextContent` - full text of documents
- `GSMDItemFSName` - file name, `GSMDItemFSExtension`, `GSMDItemFSType`
- `GSMDItemFSSize`, `GSMDItemFSModificationDate`, `GSMDItemFSCreationDate`
- `GSMDItemAuthors`, `GSMDItemTitle`, `GSMDItemFinderComment`
- `GSMDItemKeywords`, `GSMDItemDescription`, `GSMDItemCopyrightDescription`

### a) Command line (`mdfind`)

```
mdfind [options] query

  -onlyin 'directory'   limit the search to 'directory'
  -s                    also report the score of each path
  -c                    report only the number of matches
  -a [attribute]        list attributes, or describe one
  -h                    help
```

Examples:

```sh
# full-text search for "sqlite"
mdfind 'GSMDItemTextContent == "*sqlite*"'

# case-insensitive, in one directory, with score
mdfind -s -onlyin /Local/Users/admin 'GSMDItemTextContent == "*gnustep*"c'

# count only
mdfind -c 'GSMDItemTextContent == "*sqlite*"'

# by file extension
mdfind 'GSMDItemFSExtension == "md"'

# by file name (wildcards needed for partial names)
mdfind 'GSMDItemFSName == "*GNUstep*"'

# combined queries
mdfind '(GSMDItemTextContent == "*sqlite*") && (GSMDItemFSExtension == "h")'
```

### b) Workspace GUI

Full-text index search from the desktop is done with **MDFinder**
(`/System/Applications/MDFinder.app`):

- File -> New (Cmd-N) opens a search window; pick an attribute from the popup,
  choose an operator and a value, add conditions.
- File -> Open... / Save / Save as... load and store queries.
- All open search windows refresh automatically when the index changes.

The **menu bar search box** (Action Search, opened with Cmd+Space / Alt+Space
or the magnifier icon) also falls back to the full-text index: when the typed
query matches no menu item (and few Run/Go-To suggestions), `mdfind` is run
asynchronously and file/folder hits are appended to the results menu below the
box, so they can be opened directly. Matches both file contents
(`GSMDItemTextContent`) and file names (`GSMDItemFSName`), case-insensitive.

Workspace itself does not contain a full-text search window; it integrates
with the metadata system in other ways: it registers
`GWMetadataProvider` so the file manager can show indexed metadata (Finder
labels, comments, file attributes) on nodes, and it starts/connects to
`mdextractor` when indexing is enabled so the metadata stays current.

### c) Programmatically (MDKit framework)

Link against `MDKit.framework` (installed at
`/System/Library/Frameworks/MDKit.framework`; it depends on `FSNode` and
`DBKit`):

```make
APP_LIBS += -framework MDKit
# (or: -lMDKit -lFSNode -lDBKit)
```

Create an `MDKQuery`, hand it to `MDKQueryManager`, and implement the
delegate methods:

```objc
#import <MDKit/MDKQuery.h>
#import <MDKit/MDKQueryManager.h>

@interface Searcher : NSObject
@end

@implementation Searcher
- (void)search
{
  /* Query language is the same as mdfind's. */
  MDKQuery *q = [MDKQuery queryFromString: @"GSMDItemTextContent == \"*sqlite*\""
                            inDirectories: nil];   /* nil = whole index */
  [q setDelegate: self];
  [q setReportRawResults: YES];
  if ([[MDKQueryManager queryManager] startQuery: q] == NO) {
    NSLog(@"cannot contact gmds");
  }
}

- (void)appendRawResults:(NSArray *)lines
{
  /* each line is [path, score] */
  for (NSArray *line in lines) {
    NSLog(@"%@", [line objectAtIndex: 0]);
  }
}

- (void)queryDidEndGathering:(MDKQuery *)query
{
  NSLog(@"search done");
}
@end
```

`MDKQueryManager -startQuery:` connects to `gmds` (auto-launching it), sends
the query, and streams the results to the delegate. Other useful delegate
methods: `queryDidStartGathering:`, `queryDidUpdateResults:forCategories:`,
`queryDidStartUpdating:`, `queryDidEndUpdating:` (see
`NSObject (MDKQueryDelegate)` in `MDKit/MDKQuery.h`).

Low-level alternative: connect to the `gmds` Distributed Objects service
directly and speak `GMDSProtocol` (`registerClient:`,
`unregisterClient:`, `performQuery:` with an `MDKQuery` SQL description), but
the query description is built by `MDKQuery`, so going through MDKit is the
supported path.

## Troubleshooting

- `mdfind` says it is unable to contact `gmds` - start the daemon:
  `/System/Library/Tools/gmds --daemon`.
- No results for a directory - make sure it is in `GSMetadataIndexablePaths`,
  the daemons are running, and the initial indexing has reached it (search
  works while indexing is in progress).
- Index looks stale - restart `mdextractor` after changing the defaults, and
  check the `fswatcher` daemon is running for live updates.
