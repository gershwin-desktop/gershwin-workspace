# Assertions: P-smart (Spotlight smart folders, .savedSearch)

Status: [S] public docs (Apple "File Metadata Query Expression Syntax", Finder smart folder format as widely documented), [F] fixture, [M] needs a Mac (OPEN for Scout). No E35 fixture existed when this was written: every [S] row is to be replaced by [F] when the Finder files arrive.

## File format
- S1 [S] A .savedSearch is an XML plist. Read keys: RawQuery (else RawQueryDict.RawQuery), RawQueryDict.SearchScopes (else SearchCriteria.FXScopeArrayOfPaths), RawQueryDict.FinderFilesOnly / UserFilesOnly, CompatibleVersion (a value above 1 is refused with a message, not guessed). SearchCriteria.FXCriteriaSlices is the Finder's editor model; it is neither read nor needed to run the search. Test: t_SavedSearch "files and scopes".
- S2 [S] Written keys: CompatibleVersion 1, RawQuery, RawQueryDict {RawQuery, SearchScopes, FinderFilesOnly, UserFilesOnly}, SearchCriteria {FXScopeArrayOfPaths, FXCriteriaSlices = empty}. OPEN [M]/E35: does 10.6 Finder open a file whose FXCriteriaSlices is empty (shows it with no editable rows?) or does it need slices; which of RawQuery / RawQueryDict.RawQuery wins when they differ.
- S3 [S] Scopes: kMDQueryScopeComputer (and ComputerIndexed) = search everywhere indexed; kMDQueryScopeHome = home; absolute path = that folder. kMDQueryScopeNetwork and anything else are listed as unsupported. FinderFilesOnly / UserFilesOnly are reported in the notes as not applied.

## Query language (RawQuery -> MDKit)
- Q1 [S] Grammar: comparisons `attr op value` with == = != < > <= >=, && || ! and parentheses, InRange(attr,lo,hi), strings in "..." or '...' followed by modifier letters, numbers, $time.* functions. Test: t_SavedSearch.
- Q2 [S] String modifier c = case insensitive (MDKit "c"); no c = case sensitive, as in Spotlight. d (diacritics) and w (word) are NOT applied and are reported in the notes. `*` is the only wildcard; values with %, ?, [ (and _ when case insensitive) are unsupported because MDKit passes the text to SQLite LIKE/GLOB where these are wildcards that Spotlight does not have.
- Q3 [S] ! is pushed to the comparisons (De Morgan, inverted operator) because MDKit has no NOT. != stays != (for multi-valued attributes the two are not the same in Spotlight; only single-valued attributes are in the table).
- Q4 [S] Attributes translated (exact MDKit name checked against attributes.plist by test): kMDItemFSName, kMDItemDisplayName (note: searched as file name), kMDItemFSSize, kMDItemFSContentChangeDate -> GSMDItemFSModificationDate, kMDItemFSCreationDate, kMDItemTextContent, kMDItemFinderComment, Title, Authors, Keywords, Description, Album, Composer, MusicalGenre, PixelHeight, PixelWidth, NumberOfPages, DurationSeconds.
- Q5 [S] kMDItemContentTypeTree / kMDItemContentType with a UTI from a fixed table: public.folder/directory -> file type directory, com.apple.application(-bundle) -> file type application, the others by lower case file name extension list (public.image, public.audio, public.movie, public.plain-text, public.source-code, com.adobe.pdf, a few leaf types). Reported in the notes as "matched by file name extension". Unknown UTIs are unsupported. A container UTI with kMDItemContentType (leaf match) is unsupported.
- Q6 [S] Dates: $time.now(secs), $time.today(days), $time.yesterday, $time.this_week(weeks), this_month(months), this_year(years), $time.iso(...), resolved when the search is opened (noted); MDKit stores seconds since the reference date. OPEN [M]/E35: the offset unit of $time.today(-7) (days assumed from the documentation) and whether this_week starts on the locale's first weekday.
- Q7 [S] Never guess: any unsupported term (unindexed attribute such as kMDItemFSLabel, kMDItemKind, kMDItemLastUsedDate; text ordering; malformed text) means NO MDKit query is produced, every unsupported term is listed (GWSavedSearch -unsupportedTerms, -statusText), and the search is not run. Dropping a term would silently return other files than the Finder shows.
- Q8 [S] kMDItemFSLabel: the label lives in Finder Info / xattr and is not in the gmds index, so it is unsupported until the extractor indexes it (not in P-smart's files).

## Saving (MDKit -> RawQuery)
- W1 [S] +savedSearchWithMDKitQuery:searchPaths:error: converts MDKit text with the inverse table (GSMDItemFSExtension x -> kMDItemFSName == "*.x"c, file type directory/application -> kMDItemContentTypeTree 'public.folder' / 'com.apple.application', dates -> $time.iso(...Z)). An attribute without a Spotlight spelling gives nil and a message, no guess. Test: t_SavedSearch "writing" (round trip through the forward translation).
- W2 OPEN [M]/E35: 10.6 Finder opening our written file; kMDItemFSName vs kMDItemDisplayName for names; $time.iso accepted.

## MDKit fixes found on the way (t_MDKParse)
- M1 MDKQueryScanner treated "<=" as "<" and ">=" as ">" (the shorter operator was tried first), so every <= / >= query failed to parse. Fixed: longer operator first.
- M2 The parser's state was a function static, so after any query in a process the next query's first comparison raised "subquery without compound operator". Fixed: per scanner instance.

## Run
- R1 GWSavedSearchRunner runs the translation through MDKQuery (raw results) and reports result paths to a delegate; it does not start a search that has unsupported terms. Verified to start and finish against a live gmds; NOT verified to return paths: the gmds index on the build machine was empty. OPEN: the raw result line format (assumed one path per line) needs a run on a machine with an index.
