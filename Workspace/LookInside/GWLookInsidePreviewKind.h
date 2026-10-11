/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsidePreviewKind.h - which kind of preview an item gets.  Plain
 * Foundation, so the decision is covered by a headless test and shared by
 * every place that shows a preview (the Look Inside panel and the preview
 * column of the browser view).
 */

#import <Foundation/Foundation.h>

typedef enum
{
  GWLookInsidePreviewKindNone = 0, /* nothing at that path */
  GWLookInsidePreviewKindImage,
  GWLookInsidePreviewKindPlainText,
  GWLookInsidePreviewKindRichText,
  GWLookInsidePreviewKindPDF,
  GWLookInsidePreviewKindFolder,
  GWLookInsidePreviewKindAudio,
  GWLookInsidePreviewKindVideo,
  GWLookInsidePreviewKindOther     /* large icon and the item's facts */
} GWLookInsidePreviewKind;

/* `imageExtensions` are the lower-case extensions this system can decode
 * (NSImage's +imageFileTypes in the app; passed in so this stays free of
 * AppKit), `isPackage` whether a directory is shown as one item (an
 * application or other bundle), which FSNode knows. */
GWLookInsidePreviewKind GWLookInsidePreviewKindForPath(NSString *path,
                                                       NSArray *imageExtensions,
                                                       BOOL isPackage);

/* Whether the start of a file reads as text: no NUL byte and valid UTF-8,
 * allowing for a multi-byte character cut off at the end of the sample. */
BOOL GWLookInsideDataLooksLikeText(NSData *sample);
