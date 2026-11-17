import 'dart:io';

/// deleteTempDir deletes a test's temporary folder. Work a test started and
/// did not wait for -- a sound's waveform measured, an asset noted in the
/// library -- can still be writing into it as the test ends, and a delete
/// that meets a file being written fails with "Directory not empty". It is
/// tried again for a moment, then given up on quietly: the folder is in the
/// system's temporary directory either way.
Future<void> deleteTempDir(Directory dir) async {
  for (var i = 0; i < 20; i++) {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}
