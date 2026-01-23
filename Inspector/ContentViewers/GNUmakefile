
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

PDFKIT=no
SH_PATH=/bin/sh
# Prefer configure-provided value or environment; otherwise detect at make time:
FILE_PATH ?= $(shell command -v file 2>/dev/null || echo file)


ifneq ($(PDFKIT),no)
SUBPROJECTS = \
  FolderViewer \
  ImageViewer \
  SoundViewer \
  AppViewer \
  RtfViewer \
  PdfViewer \
  NSTIFFViewer \
  NSRTFViewer \
  NSColorViewer \
  IBViewViewer
else
SUBPROJECTS = \
  FolderViewer \
  ImageViewer \
  SoundViewer \
  AppViewer \
  RtfViewer \
  NSTIFFViewer \
  NSRTFViewer \
  NSColorViewer \
  IBViewViewer
endif

-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/aggregate.make

include GNUmakefile.postamble

