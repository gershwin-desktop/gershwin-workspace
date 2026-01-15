#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "AppImageThumbnailer.h"

static NSString *CreateTempFileWithBytes(const unsigned char *bytes, size_t length)
{
  NSString *tempDir = NSTemporaryDirectory();
  if (tempDir == nil) {
    tempDir = @"/tmp";
  }

  NSString *path = [tempDir stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"appimage-test-%u.bin", arc4random()]];
  NSData *data = [NSData dataWithBytes: bytes length: length];
  if (![data writeToFile: path atomically: YES]) {
    return nil;
  }

  return path;
}

static BOOL TestMagicDetection(void)
{
  unsigned char elfType2[16] = {
    0x7f, 'E', 'L', 'F',
    2, 1, 1, 0,
    'A', 'I', 0x02, 0, 0, 0, 0, 0
  };
  unsigned char notElf[16] = {
    0x00, 0x01, 0x02, 0x03,
    0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f
  };

  NSString *validPath = CreateTempFileWithBytes(elfType2, sizeof(elfType2));
  NSString *invalidPath = CreateTempFileWithBytes(notElf, sizeof(notElf));
  if (validPath == nil || invalidPath == nil) {
    NSLog(@"Failed to create temp files");
    return NO;
  }

  AppImageThumbnailer *thumb = [[AppImageThumbnailer alloc] init];
  BOOL validResult = [thumb canProvideThumbnailForPath: validPath];
  BOOL invalidResult = [thumb canProvideThumbnailForPath: invalidPath];
  [thumb release];

  [[NSFileManager defaultManager] removeFileAtPath: validPath handler: nil];
  [[NSFileManager defaultManager] removeFileAtPath: invalidPath handler: nil];

  if (!validResult) {
    NSLog(@"Expected type-2 AppImage to be detected");
    return NO;
  }

  if (invalidResult) {
    NSLog(@"Expected non-ELF file to be rejected");
    return NO;
  }

  return YES;
}

static BOOL TestThumbnailFailureOnMissingSquashfs(void)
{
  unsigned char elfType2[16] = {
    0x7f, 'E', 'L', 'F',
    2, 1, 1, 0,
    'A', 'I', 0x02, 0, 0, 0, 0, 0
  };
  NSString *path = CreateTempFileWithBytes(elfType2, sizeof(elfType2));
  if (path == nil) {
    NSLog(@"Failed to create temp file");
    return NO;
  }

  AppImageThumbnailer *thumb = [[AppImageThumbnailer alloc] init];
  NSData *data = [thumb makeThumbnailForPath: path];
  [thumb release];

  [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];

  if (data != nil) {
    NSLog(@"Expected nil thumbnail data for missing squashfs");
    return NO;
  }

  return YES;
}

static NSString *ThumbnailOutputPathForInput(NSString *inputPath, NSString *extension)
{
  NSString *tempDir = NSTemporaryDirectory();
  if (tempDir == nil) {
    tempDir = @"/tmp";
  }

  NSString *baseName = [[inputPath lastPathComponent] stringByDeletingPathExtension];
  if (baseName == nil || [baseName length] == 0) {
    baseName = [NSString stringWithFormat:@"appimage-%u", arc4random()];
  }

    NSString *ext = (extension != nil && [extension length] > 0) ? extension : @"dat";
    return [tempDir stringByAppendingPathComponent:
      [NSString stringWithFormat:@"%@.%@", baseName, ext]];
}

static BOOL ProcessAppImageAtPath(NSString *path)
{
  AppImageThumbnailer *thumb = [[AppImageThumbnailer alloc] init];
  NSData *data = [thumb makeThumbnailForPath: path];
  NSString *extension = [[thumb fileNameExtension] copy];
  [thumb release];

  if (data == nil) {
    NSLog(@"Failed to extract icon for %@", path);
    return NO;
  }

  NSString *outPath = ThumbnailOutputPathForInput(path, extension);
  [extension release];
  if (![data writeToFile: outPath atomically: YES]) {
    NSLog(@"Failed to write thumbnail for %@", path);
    return NO;
  }

  NSLog(@"Wrote thumbnail for %@ -> %@", path, outPath);
  return YES;
}

int main(int argc, const char **argv)
{
  @autoreleasepool {
    BOOL ok = YES;
    int i;
    NSUInteger processed = 0;
    NSUInteger failures = 0;

    if (!TestMagicDetection()) {
      ok = NO;
    }

    if (!TestThumbnailFailureOnMissingSquashfs()) {
      ok = NO;
    }

    if (argc > 1) {
      for (i = 1; i < argc; i++) {
        NSString *path = [NSString stringWithUTF8String: argv[i]];
        if (path == nil) {
          continue;
        }
        processed++;
        if (!ProcessAppImageAtPath(path)) {
          failures++;
        }
      }
    }

    if (processed > 0) {
      if (failures > 0) {
        NSLog(@"Processed %lu AppImages with %lu failures", (unsigned long)processed, (unsigned long)failures);
        return 2;
      }
      NSLog(@"Processed %lu AppImages successfully", (unsigned long)processed);
    }

    if (!ok) {
      NSLog(@"AppImageThumbnailer tests FAILED");
      return 1;
    }

    NSLog(@"AppImageThumbnailer tests PASSED");
  }
  return 0;
}
