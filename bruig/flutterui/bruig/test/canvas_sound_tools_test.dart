import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/audio_tools.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_sound_tools_test.dart is the timeline's sound tools: a volume
// envelope on a clip, ducking music under a voice, fitting a track to the
// length of a film, and the sound a transition carries.

AudioElement _clip(String id, String asset, double length,
        {int at = 0, String channel = "", List<GainPoint> envelope = const []}) =>
    AudioElement(ElementBase(id: id, visible: false),
        clip: MediaClip(
            timed: true,
            at: at,
            volume: 1,
            channel: channel,
            channelName: channel,
            envelope: envelope,
            playlist: [MediaSource(assetId: asset, length: length)]));

void main() {
  group("the envelope", () {
    const dip = [GainPoint(1, 1), GainPoint(2, 0.2), GainPoint(3, 0.2), GainPoint(4, 1)];

    test("joins its points with straight lines, flat past the ends", () {
      expect(envelopeAt(const [], 5), 1);
      expect(envelopeAt(dip, 0), 1);
      expect(envelopeAt(dip, 1.5), closeTo(0.6, 1e-9));
      expect(envelopeAt(dip, 2.5), 0.2);
      expect(envelopeAt(dip, 9), 1);
    });

    test("is a clip's gain, on top of its fades, and is saved", () {
      var clip = const MediaClip(
          envelope: dip, playlist: [MediaSource(assetId: "a", length: 10)]);
      expect(clip.momentAt(2.5)!.gain, closeTo(0.2, 1e-9));
      var faded = clip.copyWith(fadeIn: 5);
      expect(faded.momentAt(2.5)!.gain, closeTo(0.1, 1e-9),
          reason: "half way through a five second fade, and the dip");
      expect(MediaClip.fromJson(clip.toJson()).envelope, dip);
    });

    test("an export plays it, as ffmpeg hears it", () async {
      var ffmpeg = await Process.run("which", ["ffmpeg"]);
      if (ffmpeg.exitCode != 0) {
        markTestSkipped("ffmpeg is not installed");
        return;
      }
      var dir = await Directory.systemTemp.createTemp("canvas-envelope");
      addTearDown(() => dir.delete(recursive: true));
      var tone = "${dir.path}/tone.wav";
      await Process.run("ffmpeg", [
        "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=5", tone //
      ]);
      var (inputs, graph) = mixArgs([
        ExportSound(path: tone, at: 0, from: 0, length: 5, envelope: dip),
      ], pad: false);
      var out = "${dir.path}/out.wav";
      var run = await Process.run("ffmpeg", [
        "-y", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", //
        ...inputs, "-filter_complex", graph, "-map", "[mix]", "-t", "5", out
      ]);
      expect(run.exitCode, 0, reason: "${run.stderr}");
      // Loudness of each second: full, falling, low, rising, full.
      var levels = <double>[];
      for (var s = 0; s < 5; s++) {
        var stats = await Process.run("ffmpeg", [
          "-ss", "$s.2", "-t", "0.6", "-i", out, //
          "-af", "volumedetect", "-f", "null", "-"
        ]);
        var m = RegExp(r"mean_volume: (-?[\d.]+) dB")
            .firstMatch("${stats.stderr}")!;
        levels.add(double.parse(m.group(1)!));
      }
      expect(levels[0] - levels[2], closeTo(-20 * math.log(0.2) / math.ln10, 1.5),
          reason: "the dip is 0.2 -- about 14 dB down: $levels");
      expect((levels[0] - levels[4]).abs(), lessThan(1),
          reason: "and back up after: $levels");
    });
  });

  group("ducking", () {
    test("each stretch of speech is found, with breaths bridged", () {
      var peaks = Float32List(100); // ten seconds
      for (var i = 0; i < 100; i++) {
        peaks[i] = (i >= 10 && i < 30 && i != 20) || (i >= 60 && i < 70)
            ? 0.7
            : 0.0;
      }
      var spans = speechSpans(peaks, 10);
      expect(spans, hasLength(2), reason: "the gap at 2s is a breath");
      expect(spans[0].$1, closeTo(1, 1e-9));
      expect(spans[0].$2, closeTo(3, 1e-9));
      expect(spans[1].$1, closeTo(6, 1e-9));
    });

    test("lines close together are one dip", () {
      var env = duckEnvelope(const [(1, 2), (2.3, 3), (8, 9)], gain: 0.25);
      expect(env, hasLength(8), reason: "two dips, four points each");
      expect(envelopeAt(env, 2.15), 0.25, reason: "no bob between lines");
      expect(envelopeAt(env, 5), 1);
    });

    test("the music channel is ducked wherever the voice channel speaks",
        () async {
      var peaks = Float32List(100);
      for (var i = 40; i < 60; i++) {
        peaks[i] = 0.9;
      }
      CanvasController.seedWaveform("voice.mp3", peaks);
      var doc = CanvasDocument(frameRate: 10, frames: 200, elements: [
        _clip("v", "voice.mp3", 10, at: 20, channel: "voice"), // from 2s
        _clip("m", "music.mp3", 20, channel: "music"),
      ]);
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      var music = c.timelineChannels.firstWhere((x) => x.key == "music");
      expect(await c.duckUnder(music, "voice", depthDb: -12), 1);
      var m = c.document.elements.firstWhere((e) => e.id == "m") as AudioElement;
      // The voice speaks 4s to 6s into itself, 6s to 8s into the run.
      expect(m.clip.momentAt(7)!.gain, closeTo(0.251, 0.001));
      expect(m.clip.momentAt(3)!.gain, 1);
      c.clearDucking(c.timelineChannels.firstWhere((x) => x.key == "music"));
      var cleared =
          c.document.elements.firstWhere((e) => e.id == "m") as AudioElement;
      expect(cleared.clip.envelope, isEmpty);
    });
  });

  group("fitting a track", () {
    test("too long, it is cut and faded on the end", () {
      var p = fitTrack(at: 0, length: 60, end: 240, rate: 24);
      expect(p, hasLength(1));
      expect(p.single.end, 10);
      expect(p.single.fadeOut, greaterThan(0));
    });

    test("too short, its ending is laid on the end over copies", () {
      for (var length in [100.0, 40.0, 13.0]) {
        var p = fitTrack(at: 24, length: length, end: 24 * 194, rate: 24);
        var last = p.last;
        expect(last.at + (last.end - last.start) * 24, closeTo(24 * 194, 1),
            reason: "the last copy plays whole and ends on the end");
        expect(p.first.at, 24, reason: "and the first starts where it did");
        for (var i = 0; i < p.length - 1; i++) {
          var a = p[i], b = p[i + 1];
          var aEnds = a.at + (a.end - a.start) * 24;
          expect(aEnds, greaterThan(b.at),
              reason: "each overlaps the next, for its crossfade ($length)");
        }
      }
    });

    test("the controller lays the copies on the clip's own canvas", () {
      var master = CanvasScene(id: "m", elements: [_clip("song", "s.mp3", 100)]);
      var doc = CanvasDocument(
          frameRate: 10,
          masterOn: true,
          master: master,
          scenes: const [CanvasScene(id: "a", frames: 1500)]);
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.fitToEnd(c.document.master!.elements.single as AudioElement, 1500);
      var songs = c.document.master!.elements.cast<AudioElement>();
      expect(songs.length, greaterThan(1));
      var last = songs.last;
      expect(last.clip.at + last.clip.runLength * 10, closeTo(1500, 1));
      c.undo();
      expect(c.document.master!.elements, hasLength(1), reason: "one change");
    });
  });

  group("a transition's sound", () {
    const whoosh = SceneTransition(
        kind: SceneTransitionKind.fade,
        sound: "whoosh.mp3",
        soundName: "Whoosh",
        soundLength: 2,
        soundLead: 4);

    CanvasDocument three() => const CanvasDocument(scenes: [
          CanvasScene(id: "a", frames: 100, transition: whoosh),
          CanvasScene(id: "b", frames: 100, transition: whoosh),
          CanvasScene(id: "c", frames: 100),
        ]);

    test("is heard where its transition starts, less its lead", () {
      var d = three();
      var sounds = d.transitionSounds;
      expect(sounds, hasLength(2));
      expect(sounds[0].clip.at, d.startOfScene(1) - 4);
      expect(sounds[1].clip.at, d.startOfScene(2) - 4);
    });

    test("goes with its transition when a scene is made longer", () {
      var d = three();
      var longer = d.withScene(0, d.allScenes[0].copyWith(frames: 160));
      expect(longer.transitionSounds[1].clip.at,
          d.transitionSounds[1].clip.at + 60);
    });

    test("is on the timeline and in the export, but not editable there", () {
      var c = CanvasController(three());
      addTearDown(c.dispose);
      var lane = c.timedLanes
          .where((l) => l.element.id.startsWith(transitionSoundPrefix));
      expect(lane, isNotEmpty);
      expect(lane.every((l) => !l.editable), isTrue);
      expect(ExportMedia.of(c.document), isNotNull,
          reason: "the export has sound to place");
    });

    test("can be put on every transition at once", () {
      var c = CanvasController(const CanvasDocument(scenes: [
        CanvasScene(id: "a", frames: 100),
        CanvasScene(
            id: "b",
            frames: 100,
            transition: SceneTransition(kind: SceneTransitionKind.zoomIn)),
        CanvasScene(id: "c", frames: 100),
      ]));
      addTearDown(c.dispose);
      c.setDefaultTransition(const SceneTransition(kind: SceneTransitionKind.fade));
      c.soundEveryTransition(whoosh);
      expect(c.document.transitionSounds, hasLength(2),
          reason: "the default's scene and the one with its own");
    });
  });

  testWidgets("a timeline sound's settings have the tools, and they work",
      (tester) async {
    var doc = CanvasDocument(frameRate: 10, frames: 600, elements: [
      _clip("song", "s.mp3", 100, channel: "music"),
      _clip("vo", "v.mp3", 30, channel: "voice"),
    ]);
    var c = CanvasController(doc);
    addTearDown(c.dispose);
    c.selectOnly("song");
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("soundTools")), findsOneWidget);
    expect(find.byKey(const ValueKey("soundDuckUnder")), findsOneWidget,
        reason: "there is another channel to duck under");
    await tester.ensureVisible(find.byKey(const ValueKey("soundFit")));
    await tester.tap(find.byKey(const ValueKey("soundFit")));
    await tester.pumpAndSettle();
    var song = c.document.elements.firstWhere((e) => e.id == "song") as AudioElement;
    expect(song.clip.runLength, closeTo(60, 0.01),
        reason: "cut to the canvas's 600 frames at 10 a second");
  });
}
