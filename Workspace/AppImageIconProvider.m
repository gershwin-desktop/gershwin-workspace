/*
 * AppImageIconProvider.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <string.h>
#import <stdlib.h>
#import <errno.h>

#import <sqfs/predef.h>
#import <sqfs/error.h>
#import <sqfs/super.h>
#import <sqfs/compressor.h>
#import <sqfs/dir_reader.h>
#import <sqfs/dir.h>
#import <sqfs/inode.h>
#import <sqfs/io.h>
#import <sqfs/data_reader.h>
#import <sqfs/block.h>

#import "FSNodeRep.h"
#import "FSNIcon.h"

#define APPIMAGE_ICON_LOG_PREFIX @"AppImageIconProvider"

#define APPIMAGE_EI_NIDENT 16
#define APPIMAGE_ELFCLASS32 1
#define APPIMAGE_ELFCLASS64 2
#define APPIMAGE_ELFDATA2LSB 1
#define APPIMAGE_ELFDATA2MSB 2
#define APPIMAGE_EI_CLASS 4
#define APPIMAGE_EI_DATA 5

typedef struct {
  sqfs_file_t base;
  int fd;
  off_t base_offset;
  sqfs_u64 size;
  sqfs_u64 physical_size;
} AppImageSqfsFile;


static NSMutableDictionary *appImageLoadingState = nil;

static AppImageSqfsFile *AppImageSqfsFileCreate(int fd,
                                                off_t base_offset,
                                                sqfs_u64 size);

static int AppImageSqfsFileReadAt(sqfs_file_t *file,
                                  sqfs_u64 offset,
                                  void *buffer,
                                  size_t size)
{
  AppImageSqfsFile *self = (AppImageSqfsFile *)file;
  sqfs_u64 end = offset + size;

  if (offset >= self->physical_size) {
    NSLog(@"%@: read out of bounds: offset=%llu size=%zu limit=%llu", APPIMAGE_ICON_LOG_PREFIX,
          (unsigned long long)offset, size, (unsigned long long)self->physical_size);
    return SQFS_ERROR_OUT_OF_BOUNDS;
  }

  size_t readable = size;
  if (end > self->physical_size) {
    readable = (size_t)(self->physical_size - offset);
  }

  if (readable > 0) {
    ssize_t got = pread(self->fd, buffer, readable, self->base_offset + (off_t)offset);
    if (got != (ssize_t)readable) {
      return SQFS_ERROR_IO;
    }
  }

  if (readable < size) {
    memset(((unsigned char *)buffer) + readable, 0, size - readable);
  }

  return 0;
}

static int AppImageSqfsFileWriteAt(sqfs_file_t *file,
                                   sqfs_u64 offset,
                                   const void *buffer,
                                   size_t size)
{
  (void)file;
  (void)offset;
  (void)buffer;
  (void)size;
  return SQFS_ERROR_UNSUPPORTED;
}

static sqfs_u64 AppImageSqfsFileGetSize(const sqfs_file_t *file)
{
  const AppImageSqfsFile *self = (const AppImageSqfsFile *)file;
  return self->size;
}

static int AppImageSqfsFileTruncate(sqfs_file_t *file, sqfs_u64 size)
{
  (void)file;
  (void)size;
  return SQFS_ERROR_UNSUPPORTED;
}

static void AppImageSqfsFileDestroy(sqfs_object_t *obj)
{
  AppImageSqfsFile *self = (AppImageSqfsFile *)obj;
  if (self->fd >= 0) {
    close(self->fd);
    self->fd = -1;
  }
  free(self);
}

static sqfs_object_t *AppImageSqfsFileCopy(const sqfs_object_t *obj)
{
  const AppImageSqfsFile *orig = (const AppImageSqfsFile *)obj;
  int dupfd = dup(orig->fd);
  if (dupfd < 0) {
    return NULL;
  }

  AppImageSqfsFile *copy = AppImageSqfsFileCreate(dupfd, orig->base_offset, orig->physical_size);
  if (copy == NULL) {
    close(dupfd);
    return NULL;
  }

  copy->size = orig->size;
  return (sqfs_object_t *)copy;
}

static AppImageSqfsFile *AppImageSqfsFileCreate(int fd,
                                                off_t base_offset,
                                                sqfs_u64 size)
{
  AppImageSqfsFile *file = calloc(1, sizeof(*file));
  if (!file) {
    return NULL;
  }

  file->fd = fd;
  file->base_offset = base_offset;
  file->physical_size = size;
  file->size = size + (sqfs_u64)SQFS_META_BLOCK_SIZE * 1024;
  file->base.read_at = AppImageSqfsFileReadAt;
  file->base.write_at = AppImageSqfsFileWriteAt;
  file->base.get_size = AppImageSqfsFileGetSize;
  file->base.truncate = AppImageSqfsFileTruncate;
  file->base.base.destroy = AppImageSqfsFileDestroy;
  file->base.base.copy = AppImageSqfsFileCopy;

  return file;
}

static BOOL AppImageHasType2Magic(const char *path)
{
  unsigned char ident[16];
  int fd = open(path, O_RDONLY);
  ssize_t rd;

  if (fd < 0) {
    return NO;
  }

  rd = read(fd, ident, sizeof(ident));
  close(fd);

  if (rd < (ssize_t)sizeof(ident)) {
    return NO;
  }

  if (ident[0] != 0x7f || ident[1] != 'E' || ident[2] != 'L' || ident[3] != 'F') {
    return NO;
  }

  if (ident[8] == 'A' && ident[9] == 'I' && ident[10] == 0x02) {
    return YES;
  }

  return NO;
}

static BOOL AppImageValidateSquashfsOffset(int fd, off_t offset, off_t fileSize);

typedef struct {
  unsigned char e_ident[APPIMAGE_EI_NIDENT];
  uint16_t e_type;
  uint16_t e_machine;
  uint32_t e_version;
  uint32_t e_entry;
  uint32_t e_phoff;
  uint32_t e_shoff;
  uint32_t e_flags;
  uint16_t e_ehsize;
  uint16_t e_phentsize;
  uint16_t e_phnum;
  uint16_t e_shentsize;
  uint16_t e_shnum;
  uint16_t e_shstrndx;
} AppImageElf32_Ehdr;

typedef struct {
  unsigned char e_ident[APPIMAGE_EI_NIDENT];
  uint16_t e_type;
  uint16_t e_machine;
  uint32_t e_version;
  uint64_t e_entry;
  uint64_t e_phoff;
  uint64_t e_shoff;
  uint32_t e_flags;
  uint16_t e_ehsize;
  uint16_t e_phentsize;
  uint16_t e_phnum;
  uint16_t e_shentsize;
  uint16_t e_shnum;
  uint16_t e_shstrndx;
} AppImageElf64_Ehdr;

typedef struct {
  uint32_t sh_name;
  uint32_t sh_type;
  uint32_t sh_flags;
  uint32_t sh_addr;
  uint32_t sh_offset;
  uint32_t sh_size;
  uint32_t sh_link;
  uint32_t sh_info;
  uint32_t sh_addralign;
  uint32_t sh_entsize;
} AppImageElf32_Shdr;

typedef struct {
  uint32_t sh_name;
  uint32_t sh_type;
  uint64_t sh_flags;
  uint64_t sh_addr;
  uint64_t sh_offset;
  uint64_t sh_size;
  uint32_t sh_link;
  uint32_t sh_info;
  uint64_t sh_addralign;
  uint64_t sh_entsize;
} AppImageElf64_Shdr;

static uint16_t AppImageBswap16(uint16_t value)
{
  return (uint16_t)(((value & 0xff) << 8) | (value >> 8));
}

static uint32_t AppImageBswap32(uint32_t value)
{
  return ((uint32_t)AppImageBswap16((uint16_t)(value & 0xffff)) << 16)
         | (uint32_t)AppImageBswap16((uint16_t)(value >> 16));
}

static uint64_t AppImageBswap64(uint64_t value)
{
  return ((uint64_t)AppImageBswap32((uint32_t)(value & 0xffffffff)) << 32)
         | (uint64_t)AppImageBswap32((uint32_t)(value >> 32));
}

static uint16_t AppImageElf16ToHost(uint16_t val, unsigned char data)
{
  if (data == APPIMAGE_ELFDATA2MSB) {
    return AppImageBswap16(val);
  }
  return val;
}

static uint32_t AppImageElf32ToHost(uint32_t val, unsigned char data)
{
  if (data == APPIMAGE_ELFDATA2MSB) {
    return AppImageBswap32(val);
  }
  return val;
}

static uint64_t AppImageElf64ToHost(uint64_t val, unsigned char data)
{
  if (data == APPIMAGE_ELFDATA2MSB) {
    return AppImageBswap64(val);
  }
  return val;
}

static off_t AppImageElfFileSize(const char *path)
{
  FILE *fd = fopen(path, "rb");
  unsigned char ident[APPIMAGE_EI_NIDENT];
  size_t rd;

  if (fd == NULL) {
    return -1;
  }

  rd = fread(ident, 1, sizeof(ident), fd);
  if (rd != sizeof(ident)) {
    fclose(fd);
    return -1;
  }

  if (ident[0] != 0x7f || ident[1] != 'E' || ident[2] != 'L' || ident[3] != 'F') {
    fclose(fd);
    return -1;
  }

  unsigned char elfClass = ident[APPIMAGE_EI_CLASS];
  unsigned char elfData = ident[APPIMAGE_EI_DATA];

  if (elfClass == APPIMAGE_ELFCLASS32) {
    AppImageElf32_Ehdr ehdr32;
    AppImageElf32_Shdr shdr32;
    off_t sht_end;
    off_t last_section_end;

    fseeko(fd, 0, SEEK_SET);
    rd = fread(&ehdr32, 1, sizeof(ehdr32), fd);
    if (rd != sizeof(ehdr32)) {
      fclose(fd);
      return -1;
    }

    uint32_t e_shoff = AppImageElf32ToHost(ehdr32.e_shoff, elfData);
    uint16_t e_shentsize = AppImageElf16ToHost(ehdr32.e_shentsize, elfData);
    uint16_t e_shnum = AppImageElf16ToHost(ehdr32.e_shnum, elfData);

    if (e_shoff == 0 || e_shentsize == 0 || e_shnum == 0) {
      fclose(fd);
      return -1;
    }

    sht_end = (off_t)e_shoff + ((off_t)e_shentsize * (off_t)e_shnum);

    if (fseeko(fd, e_shoff, SEEK_SET) != 0) {
      fclose(fd);
      return -1;
    }

    last_section_end = 0;
    for (uint16_t i = 0; i < e_shnum; i++) {
      rd = fread(&shdr32, 1, sizeof(shdr32), fd);
      if (rd != sizeof(shdr32)) {
        fclose(fd);
        return -1;
      }

      last_section_end = (off_t)AppImageElf32ToHost(shdr32.sh_offset, elfData)
                         + (off_t)AppImageElf32ToHost(shdr32.sh_size, elfData);
    }

    fclose(fd);
    return (last_section_end > sht_end) ? last_section_end : sht_end;
  }

  if (elfClass == APPIMAGE_ELFCLASS64) {
    AppImageElf64_Ehdr ehdr64;
    AppImageElf64_Shdr shdr64;
    off_t sht_end;
    off_t last_section_end;

    fseeko(fd, 0, SEEK_SET);
    rd = fread(&ehdr64, 1, sizeof(ehdr64), fd);
    if (rd != sizeof(ehdr64)) {
      fclose(fd);
      return -1;
    }

    uint64_t e_shoff = AppImageElf64ToHost(ehdr64.e_shoff, elfData);
    uint16_t e_shentsize = AppImageElf16ToHost(ehdr64.e_shentsize, elfData);
    uint16_t e_shnum = AppImageElf16ToHost(ehdr64.e_shnum, elfData);

    if (e_shoff == 0 || e_shentsize == 0 || e_shnum == 0) {
      fclose(fd);
      return -1;
    }

    sht_end = (off_t)e_shoff + ((off_t)e_shentsize * (off_t)e_shnum);

    if (fseeko(fd, (off_t)e_shoff, SEEK_SET) != 0) {
      fclose(fd);
      return -1;
    }

    last_section_end = 0;
    for (uint16_t i = 0; i < e_shnum; i++) {
      rd = fread(&shdr64, 1, sizeof(shdr64), fd);
      if (rd != sizeof(shdr64)) {
        fclose(fd);
        return -1;
      }

      last_section_end = (off_t)AppImageElf64ToHost(shdr64.sh_offset, elfData)
                         + (off_t)AppImageElf64ToHost(shdr64.sh_size, elfData);
    }

    fclose(fd);
    return (last_section_end > sht_end) ? last_section_end : sht_end;
  }

  fclose(fd);
  return -1;
}

static off_t AppImageFindSquashfsOffsetViaElfSize(NSString *path)
{
  struct stat st;
  int fd;
  off_t elfSize = AppImageElfFileSize([path fileSystemRepresentation]);

  if (elfSize <= 0) {
    return 0;
  }

  fd = open([path fileSystemRepresentation], O_RDONLY);
  if (fd < 0) {
    return 0;
  }

  if (fstat(fd, &st) != 0) {
    close(fd);
    return 0;
  }

  if (AppImageValidateSquashfsOffset(fd, elfSize, (off_t)st.st_size)) {
    NSLog(@"%@: found squashfs offset via ELF size at %lld", APPIMAGE_ICON_LOG_PREFIX, (long long)elfSize);
    close(fd);
    return elfSize;
  }

  close(fd);
  return 0;
}

static sqfs_u16 AppImageReadLE16(const unsigned char *ptr)
{
  return (sqfs_u16)(ptr[0] | (ptr[1] << 8));
}

static sqfs_u32 AppImageReadLE32(const unsigned char *ptr)
{
  return (sqfs_u32)(ptr[0] | (ptr[1] << 8) | (ptr[2] << 16) | (ptr[3] << 24));
}

static sqfs_u64 AppImageReadLE64(const unsigned char *ptr)
{
  sqfs_u64 lo = AppImageReadLE32(ptr);
  sqfs_u64 hi = AppImageReadLE32(ptr + 4);
  return lo | (hi << 32);
}

static BOOL AppImageSuperblockLooksValid(const unsigned char *buf,
                                         size_t len,
                                         off_t fileSize,
                                         off_t offset)
{
  if (len < sizeof(sqfs_super_t)) {
    return NO;
  }

  sqfs_u32 magic = AppImageReadLE32(buf + 0);
  if (magic != SQFS_MAGIC) {
    return NO;
  }

  sqfs_u16 version_major = AppImageReadLE16(buf + 28);
  sqfs_u16 version_minor = AppImageReadLE16(buf + 30);
  sqfs_u32 block_size = AppImageReadLE32(buf + 12);
  sqfs_u16 compression_id = AppImageReadLE16(buf + 20);
  sqfs_u16 block_log = AppImageReadLE16(buf + 22);
  sqfs_u32 inode_count = AppImageReadLE32(buf + 4);
  sqfs_u64 bytes_used = AppImageReadLE64(buf + 40);

  if (version_major != SQFS_VERSION_MAJOR || version_minor != SQFS_VERSION_MINOR) {
    return NO;
  }

  if (block_size < SQFS_MIN_BLOCK_SIZE || block_size > SQFS_MAX_BLOCK_SIZE) {
    return NO;
  }

  if ((block_size & (block_size - 1)) != 0) {
    return NO;
  }

  if (block_log < 12 || block_log > 20) {
    return NO;
  }

  if (compression_id < SQFS_COMP_MIN || compression_id > SQFS_COMP_MAX) {
    return NO;
  }

  if (inode_count == 0) {
    return NO;
  }

  if (bytes_used == 0) {
    return NO;
  }

  if (offset + (off_t)bytes_used > fileSize) {
    return NO;
  }

  return YES;
}

static NSString *AppImageCopySquashfsToTemp(NSString *appImagePath,
                                            off_t offset,
                                            sqfs_u64 size)
{
  NSString *tempDir = NSTemporaryDirectory();
  NSString *templatePath = [tempDir stringByAppendingPathComponent: @"appimage-sqfs-XXXXXX"];
  const char *tmpl = [templatePath fileSystemRepresentation];
  char *tmpPath = strdup(tmpl);
  int outfd = -1;
  int infd = -1;
  NSString *result = nil;

  if (tmpPath == NULL) {
    return nil;
  }

  outfd = mkstemp(tmpPath);
  if (outfd < 0) {
    free(tmpPath);
    return nil;
  }

  infd = open([appImagePath fileSystemRepresentation], O_RDONLY);
  if (infd < 0) {
    close(outfd);
    unlink(tmpPath);
    free(tmpPath);
    return nil;
  }

  if (lseek(infd, offset, SEEK_SET) < 0) {
    close(infd);
    close(outfd);
    unlink(tmpPath);
    free(tmpPath);
    return nil;
  }

  sqfs_u64 remaining = size;
  unsigned char buffer[8192];
  while (remaining > 0) {
    size_t toRead = (remaining > sizeof(buffer)) ? sizeof(buffer) : (size_t)remaining;
    ssize_t rd = read(infd, buffer, toRead);
    if (rd <= 0) {
      break;
    }
    ssize_t wr = write(outfd, buffer, (size_t)rd);
    if (wr != rd) {
      break;
    }
    remaining -= (sqfs_u64)rd;
  }

  close(infd);
  close(outfd);

  if (remaining != 0) {
    unlink(tmpPath);
    free(tmpPath);
    return nil;
  }

  result = [NSString stringWithUTF8String: tmpPath];
  free(tmpPath);
  return result;
}

static BOOL AppImageValidateSquashfsOffset(int fd, off_t offset, off_t fileSize)
{
  unsigned char buffer[sizeof(sqfs_super_t)];

  if (offset < 0 || offset + (off_t)sizeof(buffer) > fileSize) {
    return NO;
  }

  if (lseek(fd, offset, SEEK_SET) < 0) {
    return NO;
  }

  ssize_t rd = read(fd, buffer, sizeof(buffer));
  if (rd != (ssize_t)sizeof(buffer)) {
    return NO;
  }

  return AppImageSuperblockLooksValid(buffer, sizeof(buffer), fileSize, offset);
}

static off_t AppImageFindSquashfsOffsetByScan(NSString *path)
{
  struct stat st;
  int fd = open([path fileSystemRepresentation], O_RDONLY);
  if (fd < 0) {
    return 0;
  }

  if (fstat(fd, &st) != 0) {
    close(fd);
    return 0;
  }

  off_t fileSize = (off_t)st.st_size;
  const off_t step = 4096;
  unsigned char buffer[sizeof(sqfs_super_t)];
  off_t offset = 0;

  for (off_t candidate = 0; candidate + (off_t)sizeof(buffer) <= fileSize; candidate += step) {
    if (lseek(fd, candidate, SEEK_SET) < 0) {
      break;
    }
    ssize_t rd = read(fd, buffer, sizeof(buffer));
    if (rd != (ssize_t)sizeof(buffer)) {
      break;
    }
    if (AppImageSuperblockLooksValid(buffer, sizeof(buffer), fileSize, candidate)) {
      offset = candidate;
      NSLog(@"%@: found squashfs magic by scan at %lld", APPIMAGE_ICON_LOG_PREFIX, (long long)offset);
      break;
    }
  }

  close(fd);
  return offset;
}

static NSString *AppImageSanitizeInnerPath(NSString *path)
{
  if (path == nil) {
    return nil;
  }

  if ([path hasPrefix:@"/"]) {
    return [path substringFromIndex:1];
  }

  return path;
}

static NSData *AppImageReadFileDataFromInode(sqfs_data_reader_t *data_reader,
                                             sqfs_dir_reader_t *dir_reader,
                                             const sqfs_inode_generic_t *inode,
                                             BOOL fragmentTableReady)
{
  sqfs_u64 size = 0;

  if (inode == NULL) {
    return nil;
  }

  if (inode->base.type == SQFS_INODE_FILE) {
    NSLog(@"%@: inode file: size=%u fragment_index=%u", APPIMAGE_ICON_LOG_PREFIX,
          inode->data.file.file_size, inode->data.file.fragment_index);
    if (inode->data.file.fragment_index != 0xffffffff && !fragmentTableReady) {
      NSLog(@"%@: skipping fragment-backed file without fragment table", APPIMAGE_ICON_LOG_PREFIX);
      return nil;
    }
    size = inode->data.file.file_size;
  } else if (inode->base.type == SQFS_INODE_EXT_FILE) {
    NSLog(@"%@: inode ext file: size=%llu fragment_index=%u", APPIMAGE_ICON_LOG_PREFIX,
          (unsigned long long)inode->data.file_ext.file_size,
          inode->data.file_ext.fragment_idx);
    if (inode->data.file_ext.fragment_idx != 0xffffffff && !fragmentTableReady) {
      NSLog(@"%@: skipping fragment-backed file without fragment table", APPIMAGE_ICON_LOG_PREFIX);
      return nil;
    }
    size = inode->data.file_ext.file_size;
  } else if (inode->base.type == SQFS_INODE_SLINK ||
             inode->base.type == SQFS_INODE_EXT_SLINK) {
    sqfs_u32 target_size = (inode->base.type == SQFS_INODE_SLINK)
                           ? inode->data.slink.target_size
                           : inode->data.slink_ext.target_size;
    if (target_size > 0) {
      char *target = calloc(1, target_size + 1);
      if (target != NULL) {
        memcpy(target, inode->extra, target_size);
        target[target_size] = '\0';
        NSString *targetPath = AppImageSanitizeInnerPath([NSString stringWithUTF8String: target]);
        sqfs_inode_generic_t *resolved = NULL;
        if (targetPath && sqfs_dir_reader_find_by_path(dir_reader,
                                                       NULL,
                                                       [targetPath UTF8String],
                                                       &resolved) == 0) {
          NSLog(@"%@: resolving symlink to %@", APPIMAGE_ICON_LOG_PREFIX, targetPath);
          NSData *resolvedData = AppImageReadFileDataFromInode(data_reader,
                                                               dir_reader,
                                                               resolved,
                                                               fragmentTableReady);
          sqfs_free(resolved);
          free(target);
          return resolvedData;
        }
        free(target);
      }
    }
    return nil;
  } else {
    return nil;
  }

  if (size == 0 || size > UINT32_MAX) {
    return nil;
  }

  void *buffer = malloc((size_t)size);
  if (buffer == NULL) {
    return nil;
  }

  sqfs_s32 rd = sqfs_data_reader_read(data_reader,
                                      inode,
                                      0,
                                      buffer,
                                      (sqfs_u32)size);
  if (rd < 0 || (sqfs_u64)rd != size) {
    free(buffer);
    return nil;
  }

  return [NSData dataWithBytesNoCopy: buffer length: (NSUInteger)size freeWhenDone: YES];
}

static BOOL AppImageInodeNeedsFragmentTable(const sqfs_inode_generic_t *inode)
{
  if (inode == NULL) {
    return NO;
  }

  if (inode->base.type == SQFS_INODE_FILE) {
    return inode->data.file.fragment_index != 0xffffffff;
  }
  if (inode->base.type == SQFS_INODE_EXT_FILE) {
    return inode->data.file_ext.fragment_idx != 0xffffffff;
  }
  return NO;
}

static uint32_t AppImagePngReadBE32(const unsigned char *ptr)
{
  return ((uint32_t)ptr[0] << 24) | ((uint32_t)ptr[1] << 16)
         | ((uint32_t)ptr[2] << 8) | (uint32_t)ptr[3];
}

static BOOL AppImagePngLooksValid(NSData *data)
{
  if (data == nil || [data length] < 24) {
    return NO;
  }

  const unsigned char *bytes = [data bytes];
  if (memcmp(bytes, "\x89PNG\r\n\x1a\n", 8) != 0) {
    return NO;
  }

  size_t offset = 8;
  while (offset + 8 <= [data length]) {
    uint32_t chunkLen = AppImagePngReadBE32(bytes + offset);
    if (offset + 8 + chunkLen > [data length]) {
      return NO;
    }

    if (memcmp(bytes + offset + 4, "IHDR", 4) == 0) {
      if (chunkLen < 8) {
        return NO;
      }
      uint32_t width = AppImagePngReadBE32(bytes + offset + 8);
      uint32_t height = AppImagePngReadBE32(bytes + offset + 12);
      if (width == 0 || height == 0) {
        return NO;
      }
      return YES;
    }

    offset += 12 + chunkLen;
  }

  return NO;
}

static BOOL AppImageDataIsUsableImage(NSData *data)
{
  if (data == nil || [data length] < 4) {
    return NO;
  }

  const unsigned char *bytes = [data bytes];
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return AppImagePngLooksValid(data);
  }

  if (bytes[0] == 'i' && bytes[1] == 'c' && bytes[2] == 'n' && bytes[3] == 's') {
    return YES;
  }

  if ((bytes[0] == 'I' && bytes[1] == 'I' && bytes[2] == 0x2A) ||
      (bytes[0] == 'M' && bytes[1] == 'M' && bytes[3] == 0x2A)) {
    return YES;
  }

  return NO;
}

static void AppImageLogMagic(NSData *data, NSString *label)
{
  if (data == nil || [data length] < 4) {
    return;
  }
  const unsigned char *bytes = [data bytes];
  NSLog(@"%@: %@ magic: %02x %02x %02x %02x", APPIMAGE_ICON_LOG_PREFIX,
        label,
        bytes[0], bytes[1], bytes[2], bytes[3]);
}


static NSData *AppImageExtractIconData(NSString *appImagePath, off_t offset)
{
  AppImageSqfsFile *fallbackFile = NULL;
  int fd = -1;
  sqfs_super_t super;
  sqfs_compressor_config_t meta_cfg;
  sqfs_compressor_config_t data_cfg;
  sqfs_compressor_t *meta_compressor = NULL;
  sqfs_compressor_t *data_compressor = NULL;
  sqfs_dir_reader_t *dir_reader = NULL;
  sqfs_data_reader_t *data_reader = NULL;
  sqfs_inode_generic_t *inode = NULL;
  sqfs_file_t *file = NULL;
  NSData *iconData = nil;
  NSString *tempSqfsPath = nil;
  BOOL fragmentTableReady = NO;
  struct stat st;
  sqfs_u64 copySize = 0;

  fd = open([appImagePath fileSystemRepresentation], O_RDONLY);
  if (fd < 0) {
    NSLog(@"%@: failed to open %@", APPIMAGE_ICON_LOG_PREFIX, appImagePath);
    return nil;
  }

  if (fstat(fd, &st) != 0) {
    close(fd);
    return nil;
  }

  if ((off_t)st.st_size <= offset) {
    close(fd);
    return nil;
  }

  copySize = (sqfs_u64)(st.st_size - offset);
  tempSqfsPath = AppImageCopySquashfsToTemp(appImagePath, offset, copySize);
  if (tempSqfsPath == nil) {
    fallbackFile = AppImageSqfsFileCreate(fd, offset, (sqfs_u64)(st.st_size - offset));
    if (fallbackFile == NULL) {
      close(fd);
      return nil;
    }
    file = (sqfs_file_t *)fallbackFile;
  } else {
    file = sqfs_open_file([tempSqfsPath fileSystemRepresentation], SQFS_FILE_OPEN_READ_ONLY);
    if (file == NULL) {
      NSLog(@"%@: failed to open temp squashfs image", APPIMAGE_ICON_LOG_PREFIX);
      close(fd);
      return nil;
    }
  }

  if (sqfs_super_read(&super, file) != 0) {
    NSLog(@"%@: failed to read squashfs superblock", APPIMAGE_ICON_LOG_PREFIX);
    goto cleanup;
  }

  NSLog(@"%@: superblock: compression=%u block=%u flags=0x%04x fragments=%u", APPIMAGE_ICON_LOG_PREFIX,
        (unsigned)super.compression_id, (unsigned)super.block_size,
        (unsigned)super.flags, (unsigned)super.fragment_entry_count);
  NSLog(@"%@: superblock: bytes_used=%llu inode_table=%llu dir_table=%llu frag_table=%llu", APPIMAGE_ICON_LOG_PREFIX,
        (unsigned long long)super.bytes_used,
        (unsigned long long)super.inode_table_start,
        (unsigned long long)super.directory_table_start,
        (unsigned long long)super.fragment_table_start);
  NSLog(@"%@: superblock: root_inode_ref=%llu", APPIMAGE_ICON_LOG_PREFIX,
        (unsigned long long)super.root_inode_ref);

  memset(&meta_cfg, 0, sizeof(meta_cfg));
  if (sqfs_compressor_config_init(&meta_cfg,
                                  (SQFS_COMPRESSOR)super.compression_id,
                                  SQFS_META_BLOCK_SIZE,
                                  0) != 0) {
    NSLog(@"%@: failed to init meta compressor config", APPIMAGE_ICON_LOG_PREFIX);
    goto cleanup;
  }

  meta_cfg.flags |= SQFS_COMP_FLAG_UNCOMPRESS;
  if (sqfs_compressor_create(&meta_cfg, &meta_compressor) != 0) {
    NSLog(@"%@: failed to create meta compressor", APPIMAGE_ICON_LOG_PREFIX);
    goto cleanup;
  }

  memset(&data_cfg, 0, sizeof(data_cfg));
  if (sqfs_compressor_config_init(&data_cfg,
                                  (SQFS_COMPRESSOR)super.compression_id,
                                  super.block_size,
                                  0) != 0) {
    NSLog(@"%@: failed to init data compressor config", APPIMAGE_ICON_LOG_PREFIX);
    goto cleanup;
  }

  data_cfg.flags |= SQFS_COMP_FLAG_UNCOMPRESS;
  if (sqfs_compressor_create(&data_cfg, &data_compressor) != 0) {
    NSLog(@"%@: failed to create data compressor", APPIMAGE_ICON_LOG_PREFIX);
    goto cleanup;
  }

  if ((super.flags & SQFS_FLAG_COMPRESSOR_OPTIONS)) {
    if (meta_compressor->read_options != NULL) {
      int opt_status = meta_compressor->read_options(meta_compressor, file);
      if (opt_status != 0) {
        NSLog(@"%@: failed to read meta compressor options (continuing)", APPIMAGE_ICON_LOG_PREFIX);
      }
    }
    if (data_compressor->read_options != NULL) {
      int opt_status = data_compressor->read_options(data_compressor, file);
      if (opt_status != 0) {
        NSLog(@"%@: failed to read data compressor options (continuing)", APPIMAGE_ICON_LOG_PREFIX);
      }
    }
  }

  dir_reader = sqfs_dir_reader_create(&super, meta_compressor, file, 0);
  if (dir_reader == NULL) {
    NSLog(@"%@: failed to create dir reader", APPIMAGE_ICON_LOG_PREFIX);
    goto cleanup;
  }

  data_reader = sqfs_data_reader_create(file,
                                        super.block_size,
                                        data_compressor,
                                        0);
  if (data_reader == NULL) {
    NSLog(@"%@: failed to create data reader", APPIMAGE_ICON_LOG_PREFIX);
    goto cleanup;
  }

  if (super.fragment_entry_count > 0 && !fragmentTableReady) {
    int frag_status = sqfs_data_reader_load_fragment_table(data_reader, &super);
    if (frag_status != 0) {
      NSLog(@"%@: failed to load fragment table (err=%d); will skip fragment-backed files",
            APPIMAGE_ICON_LOG_PREFIX, frag_status);
    } else {
      fragmentTableReady = YES;
    }
  }

  if (sqfs_dir_reader_find_by_path(dir_reader, NULL, ".DirIcon", &inode) == 0) {
    if (AppImageInodeNeedsFragmentTable(inode) && !fragmentTableReady) {
      int frag_status = sqfs_data_reader_load_fragment_table(data_reader, &super);
      if (frag_status != 0) {
        NSLog(@"%@: failed to load fragment table (err=%d); skipping fragment-backed file",
              APPIMAGE_ICON_LOG_PREFIX, frag_status);
      } else {
        fragmentTableReady = YES;
      }
    }
    iconData = AppImageReadFileDataFromInode(data_reader, dir_reader, inode, fragmentTableReady);
    sqfs_free(inode);
    inode = NULL;
    if (iconData != nil) {
      AppImageLogMagic(iconData, @".DirIcon");
      if (AppImageDataIsUsableImage(iconData)) {
        NSLog(@"%@: using .DirIcon from AppImage", APPIMAGE_ICON_LOG_PREFIX);
        goto cleanup;
      }
      NSLog(@"%@: .DirIcon is not a supported image; falling back", APPIMAGE_ICON_LOG_PREFIX);
      iconData = nil;
    }
  }

cleanup:
  if (inode) {
    sqfs_free(inode);
  }
  if (data_reader) {
    sqfs_destroy(data_reader);
  }
  if (dir_reader) {
    sqfs_destroy(dir_reader);
  }
  if (data_compressor) {
    sqfs_destroy(data_compressor);
  }
  if (meta_compressor) {
    sqfs_destroy(meta_compressor);
  }
  if (file) {
    sqfs_destroy(file);
  }
  if (fallbackFile == NULL && fd >= 0) {
    close(fd);
  }
  if (tempSqfsPath != nil) {
    [[NSFileManager defaultManager] removeFileAtPath: tempSqfsPath handler: nil];
  }

  return iconData;
}

static NSData *AppImageCopyIconData(NSString *path)
{
  off_t offset = 0;
  NSData *iconData = nil;

  if (!AppImageHasType2Magic([path fileSystemRepresentation])) {
    return nil;
  }

  offset = AppImageFindSquashfsOffsetViaElfSize(path);
  if (offset == 0) {
    offset = AppImageFindSquashfsOffsetByScan(path);
  }

  if (offset == 0) {
    NSLog(@"%@: unable to locate squashfs offset in %@", APPIMAGE_ICON_LOG_PREFIX, path);
    return nil;
  }

  iconData = AppImageExtractIconData(path, offset);
  if (iconData == nil) {
    NSLog(@"%@: no icon extracted from %@", APPIMAGE_ICON_LOG_PREFIX, path);
    return nil;
  }

  if (!AppImageDataIsUsableImage(iconData)) {
    NSLog(@"%@: extracted icon is not a supported image format", APPIMAGE_ICON_LOG_PREFIX);
    return nil;
  }

  return iconData;
}

static BOOL GWAppImagePathLooksLikeAppImage(NSString *path)
{
  NSString *lower = [path lowercaseString];
  if ([lower hasSuffix: @".appimage"]) {
    return YES;
  }
  return NO;
}

@interface NSWorkspace (GWAppImageIconProvider)
+ (void)gw_installAppImageIconProvider;
- (NSImage *)gw_appImage_iconForFile: (NSString *)fullPath;
@end

@interface FSNodeRep (GWAppImageIconProvider)
+ (void)gw_installAppImageFSNodeSwizzle;
- (NSImage *)gw_appImage_iconOfSize:(int)size forNode:(FSNode *)node;
@end

@implementation FSNIcon (GWAppImageIconProvider)

+ (void)gw_installAppImageFSNIconSwizzle
{
  static BOOL installed = NO;

  if (installed) {
    return;
  }
  installed = YES;

  Class cls = NSClassFromString(@"FSNIcon");
  if (cls == Nil) {
    NSLog(@"%@: FSNIcon not available for swizzle", APPIMAGE_ICON_LOG_PREFIX);
    return;
  }

  Method original = class_getInstanceMethod(cls, @selector(drawRect:));
  Method swizzled = class_getInstanceMethod(cls, @selector(gw_appImage_drawRect:));

  if (original && swizzled) {
    method_exchangeImplementations(original, swizzled);
    NSLog(@"%@: installed FSNIcon drawRect swizzle", APPIMAGE_ICON_LOG_PREFIX);
  } else {
    NSLog(@"%@: failed to install FSNIcon swizzle", APPIMAGE_ICON_LOG_PREFIX);
  }
}

- (void)gw_appImage_drawRect:(NSRect)rect
{
  // Check if this is an AppImage and if we need to update the icon
  if (node != nil && [node isDirectory] == NO) {
    NSString *nodepath = [node path];
    NSString *realPath = [nodepath stringByResolvingSymlinksInPath];

    if (AppImageHasType2Magic([realPath fileSystemRepresentation])) {
      // Check if the proper icon is now available
      FSNodeRep *fsnodeRep = [FSNodeRep sharedInstance];
      NSImage *currentIcon = [fsnodeRep iconOfSize: iconSize forNode: node];
      
      if (currentIcon != icon && [[currentIcon name] isEqualToString: @"AppImageGeneric"] == NO) {
        // Icon has been updated, refresh our cached icon
        ASSIGN (icon, currentIcon);
        drawicon = icon;
        DESTROY (selectedicon);  // Invalidate selected icon cache too
      }
    }
  }

  // Call the original drawRect
  [self gw_appImage_drawRect: rect];
}

@end

@implementation FSNodeRep (GWAppImageIconProvider)

+ (void)gw_installAppImageFSNodeSwizzle
{
  static BOOL installed = NO;

  if (installed) {
    return;
  }
  installed = YES;

  appImageLoadingState = [[NSMutableDictionary alloc] init];

  Class cls = NSClassFromString(@"FSNodeRep");
  if (cls == Nil) {
    NSLog(@"%@: FSNodeRep not available for swizzle", APPIMAGE_ICON_LOG_PREFIX);
    return;
  }

  Method original = class_getInstanceMethod(cls, @selector(iconOfSize:forNode:));
  Method swizzled = class_getInstanceMethod(cls, @selector(gw_appImage_iconOfSize:forNode:));

  if (original && swizzled) {
    method_exchangeImplementations(original, swizzled);
    NSLog(@"%@: installed FSNodeRep iconOfSize swizzle", APPIMAGE_ICON_LOG_PREFIX);
  } else {
    NSLog(@"%@: failed to install FSNodeRep swizzle", APPIMAGE_ICON_LOG_PREFIX);
  }
}

+ (void)gw_installAppImageFSNIconSwizzle
{
  static BOOL installed = NO;

  if (installed) {
    return;
  }
  installed = YES;

  Class cls = NSClassFromString(@"FSNIcon");
  if (cls == Nil) {
    NSLog(@"%@: FSNIcon not available for swizzle", APPIMAGE_ICON_LOG_PREFIX);
    return;
  }

  Method original = class_getInstanceMethod(cls, @selector(drawRect:));
  Method swizzled = class_getInstanceMethod(cls, @selector(gw_appImage_drawRect:));

  if (original && swizzled) {
    method_exchangeImplementations(original, swizzled);
    NSLog(@"%@: installed FSNIcon drawRect swizzle", APPIMAGE_ICON_LOG_PREFIX);
  } else {
    NSLog(@"%@: failed to install FSNIcon swizzle", APPIMAGE_ICON_LOG_PREFIX);
  }
}

- (NSImage *)gw_appImage_iconOfSize:(int)size forNode:(FSNode *)node
{
  if (node != nil && [node isDirectory] == NO) {
    NSString *nodepath = [node path];
    NSString *realPath = [nodepath stringByResolvingSymlinksInPath];

    if (AppImageHasType2Magic([realPath fileSystemRepresentation])) {
      // Check if we have the proper icon cached
      NSString *key = realPath;
      NSMutableDictionary *iconDict = [iconsCache objectForKey: key];
      
      if (iconDict != nil) {
        NSNumber *sizeKey = [NSNumber numberWithInt: 48];
        NSImage *cachedIcon = [iconDict objectForKey: sizeKey];
        if (cachedIcon != nil && ![[cachedIcon name] isEqualToString: @"AppImageGeneric"]) {
          // Proper icon is cached
          NSImage *icon = cachedIcon;
          if ([node isLink]) {
            NSImage *linkIcon = [NSImage imageNamed:@"common_linkCursor"];
            icon = [icon copy];
            [icon lockFocus];
            [linkIcon compositeToPoint:NSMakePoint(0,0) operation:NSCompositeSourceOver];
            [icon unlockFocus];
            [icon autorelease];
          }
          NSSize icnsize = [icon size];
          if ((icnsize.width > size) || (icnsize.height > size)) {
            return [self resizedIcon: icon ofSize: size];
          }
          return icon;
        }
      }
      
      // Check if we're already loading this AppImage
      NSNumber *loading = [appImageLoadingState objectForKey: key];
      if (loading != nil && [loading boolValue]) {
        // Still loading, return generic icon
        NSImage *icon = [NSImage imageNamed: @"UnknownTool"];
        if (icon == nil) {
          icon = [NSImage imageNamed: @"Unknown"];
        }
        if ([node isLink]) {
          NSImage *linkIcon = [NSImage imageNamed:@"common_linkCursor"];
          icon = [icon copy];
          [icon lockFocus];
          [linkIcon compositeToPoint:NSMakePoint(0,0) operation:NSCompositeSourceOver];
          [icon unlockFocus];
          [icon autorelease];
        }
        NSSize icnsize = [icon size];
        if ((icnsize.width > size) || (icnsize.height > size)) {
          return [self resizedIcon: icon ofSize: size];
        }
        return icon;
      }
      
      // Start loading
      [appImageLoadingState setObject: [NSNumber numberWithBool: YES] forKey: key];
      
      // Start async loading
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSImage *properIcon = [[NSWorkspace sharedWorkspace] iconForFile: realPath];
        if (properIcon != nil) {
          // Update cache with proper icon on main thread
          dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *updateDict = [NSMutableDictionary dictionary];
            [updateDict setObject: properIcon forKey: [NSNumber numberWithInt: 48]];
            [iconsCache setObject: updateDict forKey: key];
            [appImageLoadingState removeObjectForKey: key];
          });
        } else {
          // Loading failed, remove loading state
          dispatch_async(dispatch_get_main_queue(), ^{
            [appImageLoadingState removeObjectForKey: key];
          });
        }
      });
      
      // Return generic icon while loading
      NSImage *icon = [NSImage imageNamed: @"UnknownTool"];
      if (icon == nil) {
        icon = [NSImage imageNamed: @"Unknown"];
      }
      if ([node isLink]) {
        NSImage *linkIcon = [NSImage imageNamed:@"common_linkCursor"];
        icon = [icon copy];
        [icon lockFocus];
        [linkIcon compositeToPoint:NSMakePoint(0,0) operation:NSCompositeSourceOver];
        [icon unlockFocus];
        [icon autorelease];
      }
      NSSize icnsize = [icon size];
      if ((icnsize.width > size) || (icnsize.height > size)) {
        return [self resizedIcon: icon ofSize: size];
      }
      return icon;
    }
  }

  return [self gw_appImage_iconOfSize: size forNode: node];
}

@end

@implementation NSWorkspace (GWAppImageIconProvider)

+ (void)load
{
  [self gw_installAppImageIconProvider];
  [FSNodeRep gw_installAppImageFSNodeSwizzle];
  [FSNIcon gw_installAppImageFSNIconSwizzle];
}

+ (void)gw_installAppImageIconProvider
{
  static BOOL installed = NO;

  if (installed) {
    return;
  }
  installed = YES;

  Method original = class_getInstanceMethod(self, @selector(iconForFile:));
  Method swizzled = class_getInstanceMethod(self, @selector(gw_appImage_iconForFile:));

  if (original && swizzled) {
    method_exchangeImplementations(original, swizzled);
    NSLog(@"%@: installed NSWorkspace iconForFile swizzle", APPIMAGE_ICON_LOG_PREFIX);
  } else {
    NSLog(@"%@: failed to install swizzle (methods missing)", APPIMAGE_ICON_LOG_PREFIX);
  }
}

- (NSImage *)gw_appImage_iconForFile: (NSString *)fullPath
{
  if (fullPath != nil) {
    NSString *resolvedPath = [fullPath stringByResolvingSymlinksInPath];
    NSDictionary *attributes = [[NSFileManager defaultManager]
      fileAttributesAtPath: resolvedPath traverseLink: NO];

    if (attributes != nil) {
      NSString *fileType = [attributes fileType];
      NSString *probePath = resolvedPath;

      if ([fileType isEqual: NSFileTypeSymbolicLink] == YES) {
        NSString *targetPath = [resolvedPath stringByResolvingSymlinksInPath];
        if (targetPath != nil && [targetPath isEqualToString: resolvedPath] == NO) {
          NSLog(@"%@: following symlink %@ -> %@", APPIMAGE_ICON_LOG_PREFIX, resolvedPath, targetPath);
          probePath = targetPath;
        }
      }

      if ([fileType isEqual: NSFileTypeRegular] == YES
          || [fileType isEqual: NSFileTypeSymbolicLink] == YES) {
        if (AppImageHasType2Magic([probePath fileSystemRepresentation])) {
          NSLog(@"%@: AppImage detected at %@", APPIMAGE_ICON_LOG_PREFIX, probePath);
          NSData *iconData = AppImageCopyIconData(probePath);
          if (iconData != nil) {
            NSImage *image = [[[NSImage alloc] initWithData: iconData] autorelease];
            if (image != nil) {
              NSLog(@"%@: returning AppImage icon for %@", APPIMAGE_ICON_LOG_PREFIX, probePath);
              return image;
            }
            NSLog(@"%@: icon data decoded but image was nil for %@", APPIMAGE_ICON_LOG_PREFIX, probePath);
          }
        } else if (GWAppImagePathLooksLikeAppImage(resolvedPath)) {
          NSLog(@"%@: not detected as AppImage by magic: %@", APPIMAGE_ICON_LOG_PREFIX, resolvedPath);
        }
      } else if (GWAppImagePathLooksLikeAppImage(resolvedPath)) {
        NSLog(@"%@: path is not a regular file: %@", APPIMAGE_ICON_LOG_PREFIX, resolvedPath);
      }
    } else if (GWAppImagePathLooksLikeAppImage(resolvedPath)) {
      NSLog(@"%@: missing file attributes for %@", APPIMAGE_ICON_LOG_PREFIX, resolvedPath);
    }
  }

  return [self gw_appImage_iconForFile: fullPath];
}

@end
