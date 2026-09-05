import 'dart:io';

import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// canvas_video_test.dart is about the one export that needs something this
// app does not carry.
//
// Two halves. The first runs everywhere and is about behaving properly when
// there is no encoder: the size guess, the file extension, and refusing to
// produce a broken file. The second only runs where ffmpeg actually is, and
// checks the real thing end to end -- because an MP4 written with the wrong
// arguments is a file that exists, has a sensible size, and will not play.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CanvasDocument moving({int frames = 6}) {
    var document = CanvasDocument(frames: frames, elements: [
      ShapeElement(
        const ElementBase(id: "s", x: 20, y: 20, width: 200, height: 200),
        shape: ShapeKind.circle,
      ),
    ]);
    return document;
  }

  group("what an MP4 costs", () {
    test("the guess grows with the frames and the size", () {
      var short = estimateVideoBytes(moving(frames: 2));
      var long = estimateVideoBytes(moving(frames: 60));
      expect(long, greaterThan(short));
      expect(estimateVideoBytes(moving(), scale: 2),
          greaterThan(estimateVideoBytes(moving())));
    });

    test("a smaller quality guesses a smaller file", () {
      expect(estimateVideoBytes(moving(), quality: Mp4Quality.small),
          lessThan(estimateVideoBytes(moving(), quality: Mp4Quality.high)));
      // Lower is better in a CRF, which is backwards from every other quality
      // control in the app and is worth pinning down.
      expect(Mp4Quality.high.crf, lessThan(Mp4Quality.small.crf));
    });

    test("an MP4 is saved as one", () {
      expect(extensionFor("video/mp4"), ".mp4");
    });
  });

  group("without an encoder", () {
    test("a canvas with no frames is refused rather than half made", () async {
      expect(await renderMp4(moving(frames: 0)), isNull);
    });

    test("the help says how to get one, and which export needs nothing",
        () async {
      // The whole reason this route was avoidable before was failing quietly.
      expect(ffmpegHelp, contains("ffmpeg"));
      expect(ffmpegHelp, contains("GIF"));
    });
  });

  group("what ffmpeg is asked to do", () {
    // Checked against a stand-in rather than the real thing, because most
    // machines have no ffmpeg and this is the half that can go wrong without
    // one: the frames handed over, the arguments, and the clearing up.
    late Directory scratch;
    late File script;
    late File log;

    setUp(() async {
      scratch = await Directory.systemTemp.createTemp("bruig-fake-ffmpeg");
      log = File(path.join(scratch.path, "args.txt"));
      script = File(path.join(scratch.path, "ffmpeg"));
      // Records what it was called with, counts the frames it was given, and
      // writes something with an ftyp box in it where the output was asked
      // for -- which is all renderMp4 needs from it.
      await script.writeAsString("""#!/bin/sh
printf '%s\\n' "\$@" > "${log.path}"
for a in "\$@"; do out="\$a"; done
# The frames it was handed, counted before they are cleared up. Recorded here
# because by the time the test can look, the working directory is gone -- which
# is itself one of the things being checked.
frames=\$(ls "\$(dirname "\$out")"/frame-*.png 2>/dev/null | wc -l)
printf 'frames=%s\\n' "\$frames" >> "${log.path}"
printf '\\x00\\x00\\x00\\x18ftypisom' > "\$out"
head -c 4000 /dev/zero >> "\$out"
""");
      await Process.run("chmod", ["+x", script.path]);
      useFfmpegForTest(script.path);
    });

    tearDown(() async {
      useFfmpegForTest(null);
      await scratch.delete(recursive: true);
    });

    test("every frame is written out, and the encoder is told the rate",
        () async {
      var export = await renderMp4(moving(frames: 4), scale: 0.25);
      expect(export, isNotNull);
      expect(export!.mime, "video/mp4");

      var args = await log.readAsLines();
      expect(args, contains("-framerate"));
      expect(args[args.indexOf("-framerate") + 1], "${moving().frameRate}");
      expect(args, contains("libx264"));
      expect(args, contains("yuv420p"),
          reason: "without it the file plays in VLC and nowhere else");
      expect(args, contains("+faststart"));
      expect(args.any((a) => a.contains("frame-%05d.png")), isTrue,
          reason: "the sequence ffmpeg reads the order from");
      expect(args.map((a) => a.replaceAll(" ", "")), contains("frames=4"),
          reason: "one PNG per frame was actually there to be read");
    });

    test("the quality reaches the encoder as a CRF", () async {
      await renderMp4(moving(frames: 2),
          scale: 0.25, quality: Mp4Quality.small);
      var args = await log.readAsLines();
      expect(args[args.indexOf("-crf") + 1], "${Mp4Quality.small.crf}");
    });

    test("the frames are cleared up even though the file is kept", () async {
      var before = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains("bruig-canvas-mp4"))
          .length;
      var export = await renderMp4(moving(frames: 3), scale: 0.25);
      expect(export!.data.length, greaterThan(1000));
      var after = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains("bruig-canvas-mp4"))
          .length;
      expect(after, before);
    });

    test("an encoder that fails produces nothing rather than a broken file",
        () async {
      await script.writeAsString("#!/bin/sh\nexit 3\n");
      await Process.run("chmod", ["+x", script.path]);
      expect(await renderMp4(moving(frames: 2), scale: 0.25), isNull);
    });
  });

  group("with an encoder", () {
    test("a document becomes a playable MP4", () async {
      var ffmpeg = await ffmpegPath();
      if (ffmpeg == null) {
        // Not a failure: most machines have no ffmpeg, which is the entire
        // reason the feature is arranged the way it is.
        // ignore: avoid_print
        print("no ffmpeg here — skipping the end-to-end video test");
        return;
      }

      var before = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains("bruig-canvas-mp4"))
          .length;

      var seen = <int>[];
      var export = await renderMp4(moving(),
          scale: 0.25, onProgress: (done, total) => seen.add(done));

      expect(export, isNotNull);
      expect(export!.mime, "video/mp4");
      expect(seen.length, 6, reason: "progress is reported once a frame");

      // An MP4 begins with a box length and then "ftyp". Checked rather than
      // trusting the exit code, because ffmpeg will happily write a file and
      // report success for arguments that produce something no player wants.
      expect(String.fromCharCodes(export.data.sublist(4, 8)), "ftyp");
      expect(export.data.length, greaterThan(1000));

      // H.264 in 4:2:0 cannot have an odd dimension, which is why the scale
      // filter is there at all.
      expect(export.width.isEven, isTrue);
      expect(export.height.isEven, isTrue);

      var after = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains("bruig-canvas-mp4"))
          .length;
      expect(after, before,
          reason: "the frames it wrote out are not left behind");
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
