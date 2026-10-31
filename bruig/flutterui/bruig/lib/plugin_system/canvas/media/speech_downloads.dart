import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// speech_downloads.dart is how our own voices arrive: a list of files, each
// pinned to its size and SHA-256, fetched once into a folder of the library
// and checked as it comes. Shared by Kokoro and the expressive voices.

/// PinnedFile is one file to fetch: where from, where to in the folder,
/// how big it is and what its SHA-256 is; [executable] for a program.
typedef PinnedFile = ({
  String url,
  String path,
  int bytes,
  String sha256,
  bool executable,
});

/// pinnedReady is whether every one of [files] is in [dir], at its size.
Future<bool> pinnedReady(String dir, List<PinnedFile> files) async =>
    await pinnedMissing(dir, files) == 0;

/// pinnedMissing is how many bytes of [files] are not yet in [dir].
Future<int> pinnedMissing(String dir, List<PinnedFile> files) async {
  var out = 0;
  for (var f in files) {
    var file = File(path.join(dir, f.path));
    if (!await file.exists() || await file.length() != f.bytes) out += f.bytes;
  }
  return out;
}

/// downloadPinned fetches those of [files] not yet in [dir], telling
/// [progress] how much has arrived, nought to one. Answers why not, or null
/// once all are there. [stop] is asked between pieces, to give up.
Future<String?> downloadPinned(String dir, List<PinnedFile> files,
    {void Function(double share)? progress, bool Function()? stop}) async {
  await Directory(dir).create(recursive: true);
  var client = HttpClient();
  var done = 0;
  try {
    var total = files.fold(0, (n, f) => n + f.bytes);
    for (var f in files) {
      var target = File(path.join(dir, f.path));
      await target.parent.create(recursive: true);
      if (await target.exists() && await target.length() == f.bytes) {
        done += f.bytes;
        progress?.call(done / total);
        continue;
      }
      var partial = File("${target.path}.part");
      var response = await (await client.getUrl(Uri.parse(f.url))).close();
      if (response.statusCode != 200) {
        return "The voices could not be downloaded "
            "(${response.statusCode}).";
      }
      var sink = partial.openWrite();
      var hashed = AccumulatorSink<Digest>();
      var hash = sha256.startChunkedConversion(hashed);
      var got = 0;
      try {
        await for (var chunk in response) {
          if (stop?.call() ?? false) {
            await sink.close();
            await partial.delete();
            return "The download was stopped.";
          }
          sink.add(chunk);
          hash.add(chunk);
          got += chunk.length;
          progress?.call(math.min(1.0, (done + got) / total));
        }
      } finally {
        await sink.close();
      }
      hash.close();
      if (got != f.bytes || hashed.events.single.toString() != f.sha256) {
        if (await partial.exists()) await partial.delete();
        return "The voices arrived damaged: try again.";
      }
      await partial.rename(target.path);
      if (f.executable && !Platform.isWindows) {
        await Process.run("chmod", ["755", target.path]);
      }
      done += f.bytes;
      progress?.call(done / total);
    }
    return null;
  } catch (exception) {
    debugPrint("Unable to download the voices: $exception");
    return "The voices could not be downloaded: is the computer online?";
  } finally {
    client.close(force: true);
  }
}

/// AccumulatorSink keeps what a chunked conversion makes.
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}

/// PinnedDownload is a set of voices' download, one for every Speech
/// device: whether they are here, how far a download has got, and why it
/// stopped.
class PinnedDownload extends ChangeNotifier {
  final Future<String> Function() dir;
  final List<PinnedFile> Function() files;
  PinnedDownload(this.dir, this.files);

  /// ready is whether the voices are here: null until it has been looked.
  bool? ready;

  /// share is how much has arrived, nought to one, while it is downloading.
  double? share;
  String? problem;
  bool _stop = false;

  bool get downloading => share != null;

  /// check looks whether the voices are here, once. Where it cannot look,
  /// they are not.
  Future<void> check() async {
    if (ready != null) return;
    try {
      ready = await pinnedReady(await dir(), files());
    } catch (exception) {
      debugPrint("Unable to look for the voices: $exception");
      ready = false;
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (downloading) return;
    _stop = false;
    problem = null;
    share = 0;
    notifyListeners();
    var into = await dir();
    problem = await downloadPinned(into, files(),
        progress: (v) {
          share = v;
          notifyListeners();
        },
        stop: () => _stop);
    share = null;
    ready = await pinnedReady(into, files());
    notifyListeners();
  }

  void stop() => _stop = true;

  /// missingBytes is how much is still to be downloaded.
  Future<int> missingBytes() async => pinnedMissing(await dir(), files());
}
