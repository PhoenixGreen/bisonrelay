import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/spectrogram.dart';
import 'package:bruig/plugin_system/canvas/media/warp.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_clip_tools_test.dart is an audio clip's further tools in its
// editor: fades as long as wanted and the way they go, slicing it into
// clips of its own, and its sound as a spectrogram.

const String id = "loop.wav";

CanvasController make(FakeEngine engine) {
  var c = CanvasController(
      CanvasDocument(
          frames: 120 * 60,
          frameRate: 120,
          audio: const AudioSettings(tempo: 120),
          elements: [
            AudioElement(const ElementBase(id: "a", name: "a"),
                clip: const MediaClip(playlist: [
                  MediaSource(assetId: id, name: "Loop", length: 16)
                ], timed: true)),
          ]),
      audioEngine: engine);
  c.setSessionClip(
      "a",
      0,
      const SessionClip(
          id: "one",
          name: "Beat",
          sound: MediaSource(assetId: id, name: "Loop", length: 16),
          bars: 1));
  return c;
}

void main() {
  group("fades", () {
    test("each curve from nothing to all", () {
      for (var c in FadeCurve.values) {
        expect(c.level(0), 0, reason: c.name);
        expect(c.level(1), 1, reason: c.name);
      }
      expect(FadeCurve.slow.level(0.5), lessThan(FadeCurve.fast.level(0.5)));
    });

    test("kept; a clip with one is rendered, and again when it changes", () {
      const clip = SessionClip(id: "x", fadeIn: 0.5, fadeOut: 1);
      var back = SessionClip.fromJson(
          clip.copyWith(fadeCurve: FadeCurve.fast).toJson())!;
      expect((back.fadeIn, back.fadeOut, back.fadeCurve),
          (0.5, 1.0, FadeCurve.fast));
      expect(const SessionClip(id: "x").needsRender, isFalse);
      expect(clip.needsRender, isTrue);
      expect(clip.warpSignature(0.5),
          isNot(clip.copyWith(fadeIn: 0.25).warpSignature(0.5)));
    });

    test("faded over as long as asked, the way asked", () {
      var l = Float32List(48000)..fillRange(0, 48000, 1);
      var r = Float32List.fromList(l);
      fadeEdges(l, r,
          ins: const [(0.0, 0.5)],
          outs: const [(1.0, 0.25)],
          curve: FadeCurve.linear.level);
      expect(l[0], 0);
      expect(l[12000], closeTo(0.5, 0.01), reason: "half way in");
      expect(l[30000], 1, reason: "between the fades");
      expect(l[47999], closeTo(0, 0.01));
      expect(l[48000 - 6000], closeTo(0.5, 0.01), reason: "half way out");
    });
  });

  group("slices", () {
    test("every beat: four clips under it, a stretch of the sound each",
        () async {
      var c = make(FakeEngine({id: 16}));
      addTearDown(c.dispose);
      c.openClipEditor("a", 0);
      expect(await c.sliceClip(SliceBy.beat), isNull);
      var slices = [for (var r = 1; r <= 4; r++) c.session.at("a", r)!];
      expect(slices.map((s) => (s.sound!.start, s.sound!.end)),
          [(0.0, 0.5), (0.5, 1.0), (1.0, 1.5), (1.5, 2.0)],
          reason: "half a second a beat at 120");
      expect(
          slices.map((s) => s.name), ["Beat 1", "Beat 2", "Beat 3", "Beat 4"]);
      expect(slices.first.bars, closeTo(0.25, 1e-9));
      expect(slices.every((s) => s.sound!.assetId == id), isTrue,
          reason: "no new files: stretches of the same one");
      expect(c.session.at("a", 0)!.id, "one", reason: "the clip itself kept");
      c.undo();
      expect(c.session.at("a", 1), isNull, reason: "one step to undo");
    });

    test("at its hits: where it is struck", () async {
      var was = CanvasController.clipAudio;
      addTearDown(() => CanvasController.clipAudio = was);
      // A click every half second and a quarter, from silence.
      CanvasController.clipAudio = (_) async {
        var l = Float32List(48000 * 2);
        for (var hit in [0.0, 0.75, 1.25]) {
          var at = (hit * 48000).round();
          for (var i = 0; i < 2400; i++) {
            l[at + i] = 0.9 * math.exp(-i / 400) * math.sin(i * 0.3);
          }
        }
        return (l, Float32List.fromList(l));
      };
      var c = make(FakeEngine({id: 16}));
      addTearDown(c.dispose);
      c.openClipEditor("a", 0);
      expect(await c.sliceClip(SliceBy.hits), isNull);
      var starts = [
        for (var r = 1; c.session.at("a", r) != null; r++)
          c.session.at("a", r)!.sound!.start
      ];
      expect(starts.length, 3, reason: "$starts");
      expect(starts[1], closeTo(0.75, 0.03));
      expect(starts[2], closeTo(1.25, 0.03));
    });
  });

  test("a spectrogram: a tone a bright row where it is, dark elsewhere", () {
    var x = Float32List.fromList([
      for (var i = 0; i < 48000; i++)
        0.5 * math.sin(2 * math.pi * 1000 * i / 48000)
    ]);
    var s = spectrogramOf(x, columns: 20, rows: 64);
    expect(s.rgba.length, 20 * 64 * 4);
    // The brightest row of the middle column: 1kHz on the log scale.
    var best = 0, bestV = -1;
    for (var r = 0; r < 64; r++) {
      var o = (r * 20 + 10) * 4;
      var v = s.rgba[o] + s.rgba[o + 1] + s.rgba[o + 2];
      if (v > bestV) {
        bestV = v;
        best = r;
      }
    }
    var want =
        64 - 1 - (math.log(1000 / 40) / math.log(16000 / 40) * 64).floor();
    expect(best, closeTo(want, 2));
    // As loud as it is: a sine at -6dB near the top of the scale, and
    // nothing well away from it.
    var tone = (best * 20 + 10) * 4, quiet = (2 * 20 + 10) * 4;
    expect(s.rgba[tone], greaterThan(230), reason: "bright");
    expect(s.rgba[quiet], lessThan(40), reason: "dark");
  });
}
