
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

# The application to be compiled
TOOL_NAME = fswatcher

# The Objective-C source files to be compiled

# Use configure-substituted value when available; default driver selection
WITH_INOTIFY ?= @with_inotify@
INOTIFY_LIBS ?= @INOTIFY_LIBS@
WITH_FAM=@with_fam@

# If configure didn't substitute these placeholders, clear them so the
# auto-detection below can run and so we never pass literal '@...@' tokens
# to the compiler/linker.
ifeq ($(WITH_INOTIFY),@with_inotify@)
  WITH_INOTIFY =
endif
ifeq ($(INOTIFY_LIBS),@INOTIFY_LIBS@)
  INOTIFY_LIBS =
endif

# If WITH_INOTIFY wasn't explicitly set to yes/no, detect inotify at make time.
# Try compiling a tiny program: first without -linotify, then with -linotify.
ifneq ($(WITH_INOTIFY),yes)
ifneq ($(WITH_INOTIFY),no)
  INOTIFY_DETECT_RESULT := $(shell printf "#include <sys/inotify.h>\nint main(){inotify_init();return 0;}\n" | $(CC) -x c - -o /dev/null 2>/dev/null && echo yes || (printf "#include <sys/inotify.h>\nint main(){inotify_init();return 0;}\n" | $(CC) -x c - -o /dev/null -linotify 2>/dev/null && echo libinotify || echo no))
  ifeq ($(INOTIFY_DETECT_RESULT),yes)
    WITH_INOTIFY = yes
    INOTIFY_LIBS =
  else ifeq ($(INOTIFY_DETECT_RESULT),libinotify)
    WITH_INOTIFY = yes
    INOTIFY_LIBS = -linotify
  else
    WITH_INOTIFY = no
    INOTIFY_LIBS =
  endif
endif
endif
ifeq ($(WITH_INOTIFY),yes)
  fswatcher_OBJC_FILES = fswatcher-inotify.m
else
  ifeq ($(WITH_FAM),yes)
    fswatcher_OBJC_FILES = fswatcher-fam.m
  else
    fswatcher_OBJC_FILES = fswatcher.m
  endif
endif

fswatcher_TOOL_LIBS += -lDBKit

# The Resource files to be copied into the app's resources directory

-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/tool.make

-include GNUmakefile.postamble

