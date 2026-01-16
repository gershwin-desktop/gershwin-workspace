AC_PREREQ(2.52)
AC_INIT(gworkspace, 1.1.0)

if test -z "$GNUSTEP_MAKEFILES"; then
  AC_MSG_ERROR([You must run the GNUstep initialization script first!])
fi


#--------------------------------------------------------------------
# Find the compiler
#--------------------------------------------------------------------
if test "$CC" = ""; then
  CC=`gnustep-config --variable=CC`
fi
if test "$CPP" = ""; then
  CPP=`gnustep-config --variable=CPP`
fi
if test "$CXX" = ""; then
  CXX=`gnustep-config --variable=CXX`
fi
AC_PROG_CC
AC_PROG_CPP

MAKECC=`gnustep-config --variable=CC`
if test "$CC" != "$MAKECC"; then
  AC_MSG_ERROR([You are running configure with the compiler ($CC) set to a different value from that used by gnustep-make ($MAKECC).  Please run configure again with your environment set to match your gnustep-make])
  exit 1
fi

AC_SUBST(CC)
AC_SUBST(CPP)
AC_SUBST(CXX)
export CC
export CPP
export CXX

#--------------------------------------------------------------------
# Use config.guess, config.sub and install-sh provided by gnustep-make
#--------------------------------------------------------------------
AC_CONFIG_AUX_DIR([$GNUSTEP_MAKEFILES])

AC_CHECK_HEADERS(dir.h unistd.h sys/resource.h)
AC_CHECK_FUNCS(getpwnam getpwuid geteuid getlogin)

AC_CONFIG_AUX_DIR([$GNUSTEP_MAKEFILES])

AC_CONFIG_SUBDIRS([FSNode Inspector])


#--------------------------------------------------------------------
# DBus support - auto-detect, but allow manual override
#--------------------------------------------------------------------
with_dbus=no
DBUS_LIBS=""
DBUS_CFLAGS=""

# Try to find DBus using pkg-config first
pkg-config --exists dbus-1
if test $? -eq 0; then
  DBUS_CFLAGS=$(pkg-config --cflags dbus-1)
  DBUS_LIBS=$(pkg-config --libs dbus-1)
  with_dbus=yes
fi

# Allow manual override
AC_ARG_ENABLE(dbus,
  [  --enable-dbus           Force enable DBus support
  --disable-dbus          Force disable DBus support],
  [with_dbus=$enableval], [])

AC_SUBST(with_dbus)
AC_SUBST(DBUS_LIBS)
AC_SUBST(DBUS_CFLAGS)

#--------------------------------------------------------------------
# libsquashfs support (AppImage icons) - auto-detect, allow manual override
#--------------------------------------------------------------------
with_squashfs=no
SQUASHFS_LIBS=""
SQUASHFS_CFLAGS=""

# Try to find libsquashfs using pkg-config first
pkg-config --exists libsquashfs
if test $? -eq 0; then
  SQUASHFS_CFLAGS=$(pkg-config --cflags libsquashfs)
  SQUASHFS_LIBS=$(pkg-config --libs libsquashfs)
  with_squashfs=yes
else
  # Fallback to alternate pkg-config name
  pkg-config --exists squashfs
  if test $? -eq 0; then
    SQUASHFS_CFLAGS=$(pkg-config --cflags squashfs)
    SQUASHFS_LIBS=$(pkg-config --libs squashfs)
    with_squashfs=yes
  else
    # Last resort: check for headers and library without pkg-config
    AC_CHECK_HEADERS([sqfs/predef.h], [
      AC_CHECK_LIB(squashfs, sqfs_dir_reader_create,
        [SQUASHFS_LIBS="-lsquashfs"; with_squashfs=yes])
    ])
  fi
fi

# Allow manual override
AC_ARG_ENABLE(squashfs,
  [  --enable-squashfs        Force enable AppImage icon support
  --disable-squashfs       Force disable AppImage icon support],
  [with_squashfs=$enableval], [])

AC_SUBST(with_squashfs)
AC_SUBST(SQUASHFS_LIBS)
AC_SUBST(SQUASHFS_CFLAGS)

AC_ARG_ENABLE(gwmetadata,
  [  --enable-gwmetadata     Enable GWMetadata], , [enable_gwmetadata=no])

if test "x$enable_gwmetadata" = "xyes"; then
  AC_CONFIG_SUBDIRS([GWMetadata])
  BUILD_GWMETADATA=1
else
  BUILD_GWMETADATA=0
fi
AC_SUBST(BUILD_GWMETADATA)

AC_CONFIG_HEADER([Workspace/config.h])

if test "x$with_dbus" = "xyes"; then
  AC_DEFINE([HAVE_DBUS], [1], [Define if DBus support is available])
else
  AC_DEFINE([HAVE_DBUS], [0], [Define if DBus support is available])
fi

if test "x$with_squashfs" = "xyes"; then
  AC_DEFINE([HAVE_SQUASHFS], [1], [Define if libsquashfs support is available])
else
  AC_DEFINE([HAVE_SQUASHFS], [0], [Define if libsquashfs support is available])
fi


#--------------------------------------------------------------------
# Debug logging
#--------------------------------------------------------------------
AC_ARG_ENABLE(debug_log,
  [  --enable-debug-log      Enable debug logging],,
      enable_debug_log=no)

if test "$enable_debug_log" = "yes"; then
 GW_DEBUG_LOG=1
else
 GW_DEBUG_LOG=0
fi

AC_DEFINE_UNQUOTED([GW_DEBUG_LOG], [$GW_DEBUG_LOG], [debug logging])

#--------------------------------------------------------------------
# fswatcher-inotify - automatically detect and use when available
#--------------------------------------------------------------------
with_inotify=no
INOTIFY_LIBS=""

AC_CHECK_HEADERS([sys/inotify.h], [with_inotify=yes])

# Check if we need to link against libinotify (NetBSD, FreeBSD)
if test "x$with_inotify" = "xyes"; then
  AC_CHECK_FUNC(inotify_init, [],
    [AC_CHECK_LIB(inotify, inotify_init, 
      [INOTIFY_LIBS="-linotify"],
      [with_inotify=no])])
fi

# Allow manual override
AC_ARG_WITH(inotify,
  [  --with-inotify          Force enable fswatcher-inotify
  --without-inotify       Force disable fswatcher-inotify],
  [], [])
  
AC_SUBST(with_inotify)
AC_SUBST(INOTIFY_LIBS)

AC_CONFIG_FILES([
  GNUmakefile
  ])

AC_OUTPUT
