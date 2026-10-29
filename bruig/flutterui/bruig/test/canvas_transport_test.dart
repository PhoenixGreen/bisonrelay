import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/mix/click_track.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/transport.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/transport_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_transport_test.dart is the timeline's control bar: where the
// playhead is said three ways and read back, tap tempo, the loop, Stop,
// stepping by the grid, locators, the metronome -- and the bar itself, in a
// piece of sound and in a document of scenes.

/// sound is a piece of sound at 120 BPM in 4/4, 120 steps a second: a beat
/// every sixty frames, a bar every 240.
const sound = CanvasDocument(
    kind: CanvasKind.audio, hasCanvas: false, frames: 4800, frameRate: 120);

void main() {
  group("saying where", () {
    const audio = AudioSettings();
    test("bars, beats and sixteenths count from one", () {
      expect(barsText(audio, 0, 120), "1. 1. 1");
      expect(barsText(audio, 60, 120), "1. 2. 1");
      expect(barsText(audio, 15, 120), "1. 1. 2");
      expect(barsText(audio, 240 * 4 + 60 + 30, 120), "5. 2. 3");
      // 6/8: a beat is an eighth, two sixteenths.
      var six = audio.copyWith(beatsPerBar: 6, beatUnit: 8);
      expect(barsText(six, 30, 120), "1. 2. 1");
    });

    test("a length counts from nought", () {
      expect(lengthText(audio, 960, 120), "4. 0. 0");
      expect(lengthText(audio, 1020, 120), "4. 1. 0");
    });

    test("minutes and seconds, finer at a fine rate", () {
      expect(timeText(1050, 120), "0:08.750");
      expect(timeText(288, 24), "0:12.0");
      expect(timeText(24 * 75, 24), "1:15.0");
    });

    test("a typed position is read by its shape", () {
      expect(parsePosition("5.2.3", audio, 120, bars: true), 1050);
      expect(parsePosition("5 2", audio, 120, bars: true), 1020);
      expect(parsePosition("5", audio, 120, bars: true), 960);
      expect(parsePosition("0:08.75", audio, 120, bars: true), 1050);
      expect(parsePosition("#25", audio, 120, bars: true), 24);
      expect(parsePosition("25", audio, 24, bars: false), 24);
      expect(parsePosition("1.5.1", audio, 120, bars: true), isNull,
          reason: "there is no fifth beat in 4/4");
      expect(parsePosition("soon", audio, 120, bars: true), isNull);
    });

    test("a typed length", () {
      expect(parseLength("4", audio, 120, bars: true), 960);
      expect(parseLength("4.2", audio, 120, bars: true), 1080);
      expect(parseLength("120", audio, 24, bars: false), 120);
      expect(parseLength("0", audio, 120, bars: true), isNull);
    });
  });

  group("tap tempo", () {
    test("four taps or more, the last few averaged", () {
      expect(tapTempo([0, 0.5, 1]), isNull);
      expect(tapTempo([0, 0.5, 1, 1.5]), 120);
      expect(tapTempo([0, 0.6, 1.2, 1.8, 2.4]), 100);
    });

    test("a long pause starts the count again", () {
      expect(tapTempo([0, 0.5, 1, 1.5, 9, 9.4, 9.8]), isNull);
      expect(tapTempo([0, 0.5, 1, 1.5, 9, 9.4, 9.8, 10.2]), 150);
    });

    testWidgets("the TAP button sets it", (tester) async {
      var now = 0.0;
      double? tempo;
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (c) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
            home: Scaffold(
                body: TapTempoButton(
                    clock: () => now, onTempo: (t) => tempo = t))),
      ));
      for (var i = 0; i < 4; i++) {
        now = i * 0.4;
        await tester.tap(find.byKey(const ValueKey("tapTempo")));
        await tester.pump();
      }
      expect(tempo, 150);
    });
  });

  group("the metronome's click", () {
    test("on every beat, higher on the first of the bar, quiet between", () {
      var click = ClickTrack(0.5, 4);
      var l = Float32List(mixRate * 2), r = Float32List(mixRate * 2);
      click.read(l, r, l.length);
      double peak(int from, int to) {
        var p = 0.0;
        for (var i = from; i < to; i++) {
          if (l[i].abs() > p) p = l[i].abs();
        }
        return p;
      }

      var beat = mixRate ~/ 2;
      for (var b = 0; b < 4; b++) {
        expect(peak(b * beat, b * beat + 600), greaterThan(0.2),
            reason: "a click on beat ${b + 1}");
        expect(peak(b * beat + 4000, b * beat + 20000), 0,
            reason: "and nothing between");
      }
      // Counted from the start, wherever it is read from.
      click.seek(beat);
      var again = Float32List(600), right = Float32List(600);
      click.read(again, right, 600);
      expect(again.sublist(0, 600), l.sublist(beat, beat + 600));
    });
  });

  group("the controller", () {
    test("the loop goes round from inside it, not from past it", () {
      var c = CanvasController(const CanvasDocument(frames: 100));
      addTearDown(c.dispose);
      c.looping = true;
      expect(c.loopRange, (0, 100), reason: "a scene's loop is the scene");
      c.setLoop(20, 10);
      c.frame = 28;
      c.tickForTest();
      expect(c.frame, 29);
      c.tickForTest();
      expect(c.frame, 20, reason: "round to the start");
      c.frame = 50;
      c.tickForTest();
      expect(c.frame, 51, reason: "past the loop, it plays on");
      c.looping = false;
      c.frame = 29;
      c.tickForTest();
      expect(c.frame, 30);
    });

    test("a piece of sound loops the section it is in, or four bars", () {
      var c = CanvasController(sound.copyWith(
          audio: const AudioSettings(sections: [
        SongSection("a", name: "Intro", bars: 2),
        SongSection("b", name: "Verse", bars: 8),
      ])));
      addTearDown(c.dispose);
      c.frame = 240 * 3;
      c.looping = true;
      expect(c.loopRange, (480, 1920), reason: "the verse");
      c.looping = false;
      var bare = CanvasController(sound);
      addTearDown(bare.dispose);
      bare.frame = 240 * 5 + 10;
      bare.looping = true;
      expect(bare.loopRange, (1200, 960), reason: "four bars from bar six");
    });

    test("Stop goes back to where Play started, then to the start", () {
      var c = CanvasController(const CanvasDocument(frames: 100));
      addTearDown(c.dispose);
      c.frame = 30;
      c.play();
      c.tickForTest();
      c.tickForTest();
      expect(c.frame, 32);
      c.stopPlaying();
      expect((c.playing, c.frame), (false, 30));
      c.stopPlaying();
      expect(c.frame, 0);
    });

    test("stepping by the grid lands on its lines", () {
      var c = CanvasController(sound);
      addTearDown(c.dispose);
      c.frame = 70;
      c.stepGrid(1);
      expect(c.frame, 120, reason: "on to the next quarter");
      c.stepGrid(-1);
      expect(c.frame, 60);
      c.apply(c.document
          .copyWith(audio: c.document.audio.copyWith(quantise: Quantise.bar)));
      c.stepGrid(1);
      expect(c.frame, 240);
    });

    test("locators are places, and playing goes past them", () {
      var c = CanvasController(sound.copyWith(
          audio: const AudioSettings(
              sections: [SongSection("a", bars: 4), SongSection("b")])));
      addTearDown(c.dispose);
      c.frame = 100;
      c.addLocator();
      var locator = c.document.actions.single;
      expect((locator.kind, locator.label),
          (TimelineActionKind.locator, "Locator 1"));
      c.frame = 0;
      c.goToMarker(1);
      expect(c.frame, 100);
      c.goToMarker(1);
      expect(c.frame, 960, reason: "the second section's start");
      c.goToMarker(-1);
      expect(c.frame, 100);
      c.frame = 99;
      c.play();
      c.tickForTest();
      c.tickForTest();
      expect((c.playing, c.frame), (true, 101));
      c.pause();
    });

    test("the metronome clicks while a piece of sound plays, and follows",
        () async {
      var engine = FakeEngine({});
      var c = CanvasController(sound, audioEngine: engine);
      addTearDown(c.dispose);
      c.metronome = true;
      expect(engine.clicks, isEmpty, reason: "nothing until it plays");
      c.frame = 240;
      c.play();
      // The click starts once the engine has: a few turns of the event loop,
      // more when the machine is busy.
      for (var i = 0; i < 50 && engine.voices.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(engine.clicks.single, (0.5, 4));
      var voice = engine.voices.single;
      expect(voice.at, closeTo(2, 0.01), reason: "from bar two");
      // A jump -- round a loop -- takes the click with it.
      c.looping = true;
      c.setLoop(240, 10);
      for (var i = 0; i < 10; i++) {
        c.tickForTest();
      }
      expect(c.frame, 240);
      expect(voice.at, closeTo(2, 0.01));
      c.pause();
      expect(voice.alive, isFalse, reason: "stopped with the playhead");
    });

    test("no metronome in a document of scenes", () async {
      var engine = FakeEngine({});
      var c = CanvasController(const CanvasDocument(frames: 100),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.metronome = true;
      c.play();
      await Future<void>.delayed(Duration.zero);
      expect(engine.clicks, isEmpty);
      c.pause();
    });
  });

  group("the bar", () {
    Future<void> show(WidgetTester tester, CanvasController c,
        {double width = 2200}) async {
      tester.view.physicalSize = Size(width, 600);
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
        child: MaterialApp(
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: CanvasTimeline(controller: c)))),
      ));
      await tester.pumpAndSettle();
    }

    Finder within(String key, String text) => find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.text(text));

    testWidgets("a piece of sound: tempo, metre, quantise, in bars",
        (tester) async {
      var c = CanvasController(sound);
      addTearDown(c.dispose);
      c.frame = 1050;
      await show(tester, c);
      for (var key in [
        "tapTempo",
        "audioTempo",
        "audioSignature",
        "metronome",
        "audioQuantise",
        "stopPlaying",
        "loop",
        "follow",
        "stepBack",
        "keysMenu",
        "addLocator",
        "effectsToggle",
        "mixerToggle",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const ValueKey("canvasFrames")), findsNothing);
      expect(find.byKey(const ValueKey("prevKeyframe")), findsNothing,
          reason: "folded into Keys");
      expect(within("transportPosition", "5. 2. 3"), findsOneWidget);
      // Pressed, the next way of saying it.
      await tester.tap(find.byKey(const ValueKey("transportPosition")));
      await tester.pumpAndSettle();
      expect(within("transportPosition", "0:08.750"), findsOneWidget);
      // The views say what they are.
      expect(within("mixerToggle", "Mixer"), findsOneWidget);
      expect(within("effectsToggle", "Effects"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey("metronome")));
      await tester.pump();
      expect(c.metronome, isTrue);
      await tester.tap(find.byKey(const ValueKey("stepOn")));
      await tester.pump();
      expect(c.frame, 1080);
      await tester.tap(find.byKey(const ValueKey("addLocator")));
      await tester.pumpAndSettle();
      expect(c.document.actions.single.kind, TimelineActionKind.locator);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a document of scenes keeps its frames and keyframes",
        (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 600));
      addTearDown(c.dispose);
      c.frame = 287;
      await show(tester, c);
      for (var key in [
        "canvasFrames",
        "canvasFrameRate",
        "prevKeyframe",
        "nextKeyframe",
        "previousFrame",
        "addAction",
        "loop",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      for (var key in ["audioTempo", "metronome", "keysMenu", "addLocator"]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      expect(within("transportPosition", "288 / 600"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("Loop, its fields and its brace", (tester) async {
      var c = CanvasController(sound);
      addTearDown(c.dispose);
      await show(tester, c);
      await tester.tap(find.byKey(const ValueKey("loop")));
      await tester.pump();
      expect((c.looping, c.loopRange), (true, (0, 960)));
      expect(within("loopLength", "4. 0. 0"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey("loopFrom")));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey("loopFromField")), "3");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.loopRange, (480, 960));

      // The brace's end, dragged a bar on, snaps to the grid.
      var strip = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      double xOf(int frame) =>
          strip.left + (frame + 0.5) / c.document.frames * strip.width;
      await tester.dragFrom(Offset(xOf(1440), strip.top + 3),
          Offset(xOf(1680) - xOf(1440), 0));
      await tester.pumpAndSettle();
      var (from, length) = c.loopRange;
      expect(from, 480);
      expect(length % 60, 0, reason: "on a beat: $length");
      expect(length, closeTo(1200, 60));

      // Clicked, the brace switches the loop off.
      await tester.tapAt(Offset(xOf(900), strip.top + 3));
      await tester.pumpAndSettle();
      expect(c.looping, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets("Follow off: playing leaves the view where it was",
        (tester) async {
      var c = CanvasController(sound);
      addTearDown(c.dispose);
      await show(tester, c);
      await tester.tap(find.byKey(const ValueKey("follow")));
      await tester.pump();
      expect(c.followPlayhead, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets("narrow, it scrolls rather than overflowing", (tester) async {
      var c = CanvasController(sound);
      addTearDown(c.dispose);
      await show(tester, c, width: 700);
      expect(tester.takeException(), isNull);
      var scenes = CanvasController(const CanvasDocument(frames: 144000));
      addTearDown(scenes.dispose);
      scenes.frame = 143999;
      await show(tester, scenes, width: 700);
      expect(tester.takeException(), isNull);
    });

    // Ken's log: two overflows in the app -- the position's two lines two
    // pixels too tall for their box, and a row twelve over on the right.
    // The app lets the reader scale its text (Settings > Appearance), so the
    // bar is tried at every size it offers, in every state it has.
    testWidgets("at every text size, in every state, nothing overflows",
        (tester) async {
      var failures = <String>[];
      for (var scale in [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
        for (var width in [900.0, 1200.0, 1600.0]) {
          for (var state in [
            "audio",
            "audio playing looping",
            "audio locator",
            "scenes",
            "scenes many",
            "scenes stop marker",
            "master",
          ]) {
            var doc = state.startsWith("audio")
                ? sound.copyWith(
                    audio: const AudioSettings(
                        quantise: Quantise.sixteenthTriplet,
                        beatsPerBar: 12,
                        beatUnit: 8))
                : const CanvasDocument(frames: maxFrameCount);
            var c = CanvasController(doc);
            if (state.contains("many") || state == "master") {
              c.addScene();
              c.addScene();
              if (state == "master") c.showMaster();
            }
            c.frame = c.document.frames - 1;
            if (state.contains("locator")) c.addLocator();
            if (state.contains("marker")) {
              c.apply(c.document.copyWith(actions: [
                TimelineAction(
                    frame: c.frame, kind: TimelineActionKind.loop, label: "x")
              ]));
            }
            if (state.contains("looping")) c.looping = true;
            if (state.contains("playing")) c.play();
            tester.view.physicalSize = Size(width, 600);
            tester.view.devicePixelRatio = 1.0;
            await tester.pumpWidget(MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeNotifier>(
                    create: (c) => ThemeNotifier(doLoad: false)),
                ChangeNotifierProvider<SnackBarModel>(
                    create: (c) => SnackBarModel()),
                ChangeNotifierProvider<CanvasPreferences>(
                    create: (c) => CanvasPreferences()),
              ],
              child: MaterialApp(
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: Scaffold(
                      body: Align(
                          alignment: Alignment.bottomCenter,
                          child: CanvasTimeline(controller: c)))),
            ));
            await tester.pump();
            if (tester.takeException() case var e?) {
              failures.add("$state at ${scale}x, $width wide: "
                  "${e.toString().split("\n").first}");
            }
            c.pause();
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          }
        }
      }
      tester.view.reset();
      expect(failures, isEmpty);
    });

    testWidgets("every number fits its box", (tester) async {
      // Ken: "the numbers popping out of their boxes". The longest each
      // can say, at the end of the longest document.
      var c = CanvasController(sound.copyWith(frames: maxFrameCount));
      addTearDown(c.dispose);
      c.frame = maxFrameCount - 1;
      c.looping = true;
      c.setLoop(maxFrameCount - 2000, 1990);
      await show(tester, c);
      for (var key in ["transportPosition", "loopFrom", "loopLength"]) {
        var box = tester.getRect(find.byKey(ValueKey(key)));
        for (var text in tester.widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey(key)), matching: find.byType(Text)))) {
          var rect = tester.getRect(find.byWidget(text));
          expect(rect.right, lessThanOrEqualTo(box.right + 0.5),
              reason: "$key: '${text.data}'");
          expect(rect.bottom, lessThanOrEqualTo(box.bottom + 0.5),
              reason: "$key: '${text.data}'");
        }
      }
      expect(tester.takeException(), isNull);
    });
  });
}
