import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/audio_tools.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_ducking_test.dart is a voice turning the music down while it
// speaks: set on the voice's channel in the mixer, worked out from where the
// voice is speaking in its own recording, and the same while playing and in
// the export.

AudioElement _clip(String id, String asset, double length, String channel,
        {Ducking duck = const Ducking(), int at = 0}) =>
    AudioElement(ElementBase(id: id, name: id, visible: false),
        clip: MediaClip(
            timed: true,
            volume: 1,
            at: at,
            channel: channel,
            channelName: channel,
            mix: ChannelMix(duck: duck),
            playlist: [MediaSource(assetId: asset, length: length)]));

/// _voicePeaks is ten seconds that speak from 2s to 4s and nowhere else.
Float32List _voicePeaks() {
  var p = Float32List(100);
  for (var i = 20; i < 40; i++) {
    p[i] = 0.9;
  }
  return p;
}

CanvasDocument _doc({List<String> except = const []}) => CanvasDocument(
      frameRate: 10,
      masterOn: true,
      master: CanvasScene(id: "m", elements: [
        _clip("vo", "voice.mp3", 10, "voice",
            duck: Ducking(on: true, depthDb: -12, except: except)),
        _clip("music", "music.mp3", 10, "music"),
        _clip("fx", "fx.mp3", 10, "fx"),
      ]),
      scenes: const [
        CanvasScene(id: "a", frames: 100),
        CanvasScene(id: "b", frames: 100),
      ],
    );

void main() {
  group("the arithmetic", () {
    test("every other channel sinks while the voice speaks, and not itself",
        () {
      var ducks = duckEnvelopes(
          _doc(), (id) => id == "voice.mp3" ? _voicePeaks() : null);
      expect(ducks.keys.toSet(), {"music", "fx"});
      expect(envelopeAt(ducks["music"]!, 3), closeTo(dbToGain(-12), 1e-6));
      expect(envelopeAt(ducks["music"]!, 7), 1);
    });

    test("a channel left alone is not ducked", () {
      var ducks = duckEnvelopes(_doc(except: ["fx"]),
          (id) => id == "voice.mp3" ? _voicePeaks() : null);
      expect(ducks.keys, ["music"]);
    });

    test("nothing is ducked until the voice's shape has been read", () {
      expect(duckEnvelopes(_doc(), (_) => null), isEmpty);
    });

    test("the setting is saved on the channel", () {
      var mix = const ChannelMix(
          duck: Ducking(on: true, depthDb: -8, except: ["fx"]));
      var back = ChannelMix.fromJson(mix.toJson());
      expect(back.duck.on, isTrue);
      expect(back.duck.depthDb, -8);
      expect(back.duck.except, ["fx"]);
    });
  });

  group("the curve", () {
    // A dip from 2s to 4s, sinking over a second and rising over two.
    List<GainPoint> dip(DuckCurve curve) => duckEnvelope(const [(2, 4)],
        gain: 0.25, attack: 1, release: 2, curve: curve);

    test("hard is down and up at once", () {
      var env = dip(DuckCurve.hard);
      expect(envelopeAt(env, 1.9), closeTo(1, 0.01));
      expect(envelopeAt(env, 2), 0.25);
      expect(envelopeAt(env, 4.1), closeTo(1, 0.01));
    });

    test("linear is halfway down halfway through", () {
      expect(envelopeAt(dip(DuckCurve.linear), 1.5), closeTo(0.625, 1e-6));
      expect(envelopeAt(dip(DuckCurve.linear), 5), closeTo(0.625, 1e-6));
    });

    test("smooth starts and ends gently, but is halfway in the middle", () {
      var env = dip(DuckCurve.smooth);
      expect(envelopeAt(env, 1.5), closeTo(0.625, 1e-6));
      // A tenth of the way in, an S has barely moved; a line has.
      expect(1 - envelopeAt(env, 1.1),
          lessThan((1 - envelopeAt(dip(DuckCurve.linear), 1.1)) / 2));
      expect(envelopeAt(env, 3), 0.25);
    });

    test("natural is even in decibels", () {
      var env = dip(DuckCurve.natural);
      // Halfway in time is halfway in dB: -6 of -12.
      expect(gainToDb(envelopeAt(env, 1.5)), closeTo(gainToDb(0.25) / 2, 0.1));
    });

    test("is saved, and old settings read as smooth", () {
      var mix =
          const ChannelMix(duck: Ducking(on: true, curve: DuckCurve.natural));
      expect(ChannelMix.fromJson(mix.toJson()).duck.curve, DuckCurve.natural);
      expect(
          ChannelMix.fromJson(const {
            "duck": {"on": true}
          }).duck.curve,
          DuckCurve.smooth);
    });

    test("reaches the dips the channels get", () {
      var doc = _doc();
      var hard = doc.copyWith(
          master: doc.master!.copyWith(elements: [
        _clip("vo", "voice.mp3", 10, "voice",
            duck: const Ducking(
                on: true, depthDb: -12, attack: 1, curve: DuckCurve.hard)),
        _clip("music", "music.mp3", 10, "music"),
      ]));
      var env = duckEnvelopes(
          hard, (id) => id == "voice.mp3" ? _voicePeaks() : null)["music"]!;
      expect(envelopeAt(env, 1.5), closeTo(1, 0.01),
          reason: "a second's attack, but hard ignores it");
    });
  });

  test("playing, the music is turned down where the voice speaks", () {
    CanvasController.seedWaveform("voice.mp3", _voicePeaks());
    var c = CanvasController(_doc(), audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    var env = c.duckEnvelopeOf("music")!;
    expect(envelopeAt(env, 3), closeTo(dbToGain(-12), 1e-6));
    expect(c.duckEnvelopeOf("voice"), isNull);
  });

  test("exported, the music carries the dips", () async {
    var which = await Process.run("which", ["ffmpeg"]);
    if (which.exitCode != 0) {
      markTestSkipped("ffmpeg is not installed");
      return;
    }
    var dir = await Directory.systemTemp.createTemp("canvas-duck");
    addTearDown(() => dir.delete(recursive: true));
    // Two seconds of quiet, two of tone, six of quiet.
    var voice = "${dir.path}/voice.wav";
    var r = await Process.run("ffmpeg", [
      "-y", "-f", "lavfi", "-i", "sine=frequency=300:duration=2", //
      "-af", "adelay=2000,apad=pad_dur=6", "-t", "10", voice
    ]);
    expect(r.exitCode, 0, reason: "${r.stderr}");
    var media = ExportMedia.of(_doc(), locate: (kind, id) async => voice)!;
    var sounds = await media.sounds();
    media.dispose();
    var music = sounds[1];
    expect(music.envelope, isNotEmpty, reason: "the export knows the dips");
    expect(envelopeAt(music.envelope, 3), closeTo(dbToGain(-12), 0.02));
    expect(envelopeAt(music.envelope, 8), closeTo(1, 1e-6));
    expect(sounds.first.envelope, isEmpty, reason: "the voice is not ducked");
  });

  group("the settings", () {
    Future<CanvasController> pane(WidgetTester tester,
        {double width = 1400}) async {
      var c = CanvasController(_doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.pickClip("music");
      tester.view.physicalSize = const Size(1400, 2400);
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
        child: MaterialApp(home: Scaffold(body: _screen(c, width))),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      return c;
    }

    testWidgets("are called Audio settings, and hold the channel's mixer",
        (tester) async {
      var c = await pane(tester);
      expect(elementSettingsTitle(c), "Audio settings");
      expect(find.byType(CanvasMixer), findsOneWidget);
      expect(find.byKey(const ValueKey("strip-music")), findsOneWidget);
      expect(find.byKey(const ValueKey("strip-master")), findsOneWidget);
      expect(find.byKey(const ValueKey("strip-voice")), findsNothing,
          reason: "only this sound's channel beside the master");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the duck shape is chosen on the voice's Duck slot",
        (tester) async {
      var c = CanvasController(_doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.pickClip("vo");
      tester.view.physicalSize = const Size(1400, 2400);
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
        child: MaterialApp(home: Scaffold(body: _screen(c, 1400))),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.byKey(const ValueKey("duckSlot")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("duckSlot")));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.effectsOpen, isTrue, reason: "in the effects panel");
      expect(find.byKey(const ValueKey("duckOn")), findsOneWidget);
      for (var curve in DuckCurve.values) {
        expect(find.byKey(ValueKey("duckCurve-${curve.name}")), findsOneWidget);
      }
      expect(find.byKey(const ValueKey("duckShape")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byKey(const ValueKey("duckCurve-hard")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("duckCurve-hard")));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          (c.document.master!.elements.first as AudioElement)
              .clip
              .mix
              .duck
              .curve,
          DuckCurve.hard);
      // The voice is on the master, picked from a scene: still its own to
      // change here.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byKey(const ValueKey("duckOn")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("duckOn")));
      await tester.pump(const Duration(milliseconds: 100));
      var vo = c.document.master!.elements.first as AudioElement;
      expect(vo.clip.mix.duck.on, isFalse, reason: "it was on; now off");
      expect(vo.clip.mix.duck.curve, DuckCurve.hard);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the master's Loudness opens in the effects panel, and fits",
        (tester) async {
      // The width of the sidebar it was reported overflowing in.
      var c = await pane(tester, width: 300);
      await tester.ensureVisible(find.byKey(const ValueKey("loudnessSlot")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("loudnessSlot")));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.effectsOf, mixerMasterKey);
      expect(c.effectsFocus, "loudness");
      expect(find.byKey(const ValueKey("measure")), findsOneWidget);
      expect(tester.takeException(), isNull, reason: "no overflow");
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// _screen is the sound's settings as the screen has them: the sidebar, and
/// the effects panel along the bottom when it is open.
Widget _screen(CanvasController c, double width) => ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(children: [
        Expanded(
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: width, child: CanvasDesignPanel(controller: c))),
        ),
        if (c.effectsOpen)
          SizedBox(
            width: width,
            child: CanvasMixer.effects(
                controller: c, height: 340, onResize: (_) {}, onClose: () {}),
          ),
      ]),
    );
