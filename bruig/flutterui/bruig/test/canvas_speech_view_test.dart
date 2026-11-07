import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/phrasing_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_speech_view_test.dart is the Speech view as Ken asked for it
// (2026-11-08): opened, it fills the Chain as the clip editor does -- no
// other device beside it, the chain the rail under it -- its side panels
// and Phrasing's loudness lane fold away and open again, and the chain's
// Speech card is the prototype's Generator: the take and its words, the
// feel as knobs, the voice as a list, Speak all and the takes at its foot.

const _words = <TimedWord>[
  (text: "one", start: 0.2, end: 0.7),
  (text: "two", start: 0.9, end: 1.4),
  (text: "three.", start: 1.6, end: 2.1),
];

/// _voice is a buzz through an "ah" for each word, silent between.
Float32List _voice() {
  const rate = 48000.0;
  var out = Float32List((2.4 * rate).round());
  for (var w in _words) {
    var phase = 0.0;
    double y1 = 0, y2 = 0;
    for (var i = (w.start * rate).round(); i < (w.end * rate).round(); i++) {
      phase += 150 / rate;
      var pulse = phase >= 1 ? 1.0 : 0.0;
      if (phase >= 1) phase -= 1;
      const r = 0.97, theta = 2 * math.pi * 700 / rate;
      var y = pulse + 2 * r * math.cos(theta) * y1 - r * r * y2;
      y2 = y1;
      y1 = y;
      out[i] = 0.02 * y;
    }
  }
  return out;
}

CanvasController _make() {
  var c = CanvasController(
      CanvasDocument(frames: 200, frameRate: 25, elements: [
        AudioElement(const ElementBase(id: "a", name: "Narrator"),
            clip: const MediaClip(
                playlist: [MediaSource(assetId: "t", length: 2)], timed: true)),
      ]),
      audioEngine: FakeEngine({"t": 2, "one.wav": 2.4, "two.wav": 2.4}));
  c.setSpeech(
      "a",
      SpeechSpec(voice: "af_heart", script: "one two three.\nfour.", lines: [
        const SpeechLine("one two three.")
            .withSlot(0, const SpeechTake("one.wav", 2.4, _words))
            .withSlot(1, const SpeechTake("two.wav", 2.4, _words)),
        const SpeechLine("four."),
      ]));
  return c;
}

Future<void> _show(WidgetTester tester, CanvasController c,
    {double scale = 1, double height = 420}) async {
  tester.view.physicalSize = const Size(1400, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(
          size: const Size(1400, 720), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
          body: ListenableBuilder(
              listenable: c,
              builder: (context, _) =>
                  Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    CanvasMixer.effects(
                        controller: c,
                        height: height,
                        onResize: (_) {},
                        onClose: () {}),
                  ]))),
    )),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  var audioWas = CanvasController.takeAudio;
  setUp(() {
    CanvasController.takeAudio = (id) async => _voice();
    var peaks = Float32List(200);
    for (var i = 0; i < peaks.length; i++) {
      peaks[i] = 0.2 + 0.6 * math.sin(i * 0.2).abs();
    }
    CanvasController.seedWaveform("one.wav", peaks);
    CanvasController.seedWaveform("two.wav", peaks);
  });
  tearDown(() => CanvasController.takeAudio = audioWas);

  for (var scale in [1.0, 1.5]) {
    testWidgets(
        "opened, it fills the Chain, the chain the rail under it "
        "-- at ${scale}x", (tester) async {
      var c = _make();
      addTearDown(c.dispose);
      c.showSpeech("a");
      await _show(tester, c, scale: scale);
      var view = find.byKey(const ValueKey("speechEditor"));
      expect(view, findsOneWidget);
      // On screen: the mixer zooms as a whole at a larger text size.
      expect(tester.getRect(view).width, greaterThan(1300),
          reason: "as wide as the panel, as the clip editor is");
      expect(find.byKey(const ValueKey("editorClose")), findsOneWidget,
          reason: "the chain as the rail under it");
      expect(find.byKey(const ValueKey("addDeviceSlot")), findsNothing,
          reason: "no other device beside it to scroll through");
      expect(find.byKey(const ValueKey("chainZone-Effects")), findsNothing);
      expect(tester.takeException(), isNull, reason: "nothing overflows");
      // Back to the chain: the Speech card in its Generator zone.
      await tester.tap(find.byKey(const ValueKey("editorClose")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.speechShown, isFalse);
      expect(find.byKey(const ValueKey("device-speechCard")), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("its side panels fold to strips and open again", (tester) async {
    var c = _make();
    addTearDown(c.dispose);
    c.showSpeech("a");
    await _show(tester, c);
    for (var kind in ["voice", "takes", "side"]) {
      expect(find.byKey(ValueKey("speechPanelOpen-$kind")), findsNothing);
      await tester.tap(find.byKey(ValueKey("speechPanel-$kind")));
      await tester.pump();
      expect(c.settingsShut("speech-$kind"), isTrue);
      expect(find.byKey(ValueKey("speechPanelOpen-$kind")), findsOneWidget,
          reason: "folded to a strip down its edge");
    }
    expect(find.byKey(const ValueKey("speechHearFeel")), findsNothing,
        reason: "the feel folded away");
    expect(tester.takeException(), isNull);
    // Its strip opens it again.
    await tester.tap(find.byKey(const ValueKey("speechPanelOpen-side")));
    await tester.pump();
    expect(c.settingsShut("speech-side"), isFalse);
    expect(find.byKey(const ValueKey("speechPanelOpen-side")), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("Phrasing's loudness lane folds away, the pitch lane taller",
      (tester) async {
    var c = _make();
    addTearDown(c.dispose);
    c.showSpeech("a");
    await _show(tester, c);
    await tester.tap(find.byKey(const ValueKey("speechPhrasing")));
    await tester.pump();
    for (var i = 0; i < 40 && c.readingOf(c.phrasingTake!) == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PhrasingLanes), findsOneWidget);
    expect(find.byKey(const ValueKey("phrasingLoud-0")), findsOneWidget);
    var tall = tester.getSize(find.byKey(const ValueKey("phrasingBox"))).height;
    var lanes = tester.getSize(find.byType(PhrasingLanes)).width;
    await tester.tap(find.byKey(const ValueKey("phrasingLoudShut")));
    await tester.pump();
    expect(c.settingsShut("phrasingLoudness"), isTrue);
    expect(find.byKey(const ValueKey("phrasingLoud-0")), findsNothing);
    expect(find.byKey(const ValueKey("phrasingLoudOpen")), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey("phrasingBox"))).height,
        greaterThanOrEqualTo(tall),
        reason: "the room the pitch lane's");
    // Phrasing's side panels fold as well: the lanes wider.
    await tester.tap(find.byKey(const ValueKey("speechPanel-takes")));
    await tester.pump();
    expect(tester.getSize(find.byType(PhrasingLanes)).width,
        greaterThan(lanes + 250));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey("phrasingLoudOpen")));
    await tester.pump();
    expect(find.byKey(const ValueKey("phrasingLoud-0")), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  for (var scale in [1.0, 1.5]) {
    testWidgets(
        "the chain's Speech card: its take, knobs, voice and foot "
        "-- at ${scale}x", (tester) async {
      var c = _make();
      addTearDown(c.dispose);
      c.openEffects("a");
      // Tall enough, at the mixer's zoom, for the card's foot.
      await _show(tester, c, scale: scale, height: 440 * scale);
      var card = find.byKey(const ValueKey("device-speechCard"));
      await tester.ensureVisible(card);
      await tester.pump();
      expect(find.text("one"), findsOneWidget, reason: "its words, shown");
      expect(find.byKey(const ValueKey("speechCard-speed")), findsOneWidget);
      expect(find.byKey(const ValueKey("speechCard-room")), findsOneWidget);
      expect(find.byKey(const ValueKey("speechCard-expression")), findsNothing,
          reason: "the built-in voices have no expression to set");
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey("speechCardTakes")))
              .data,
          "Takes: 2");
      // Stepped on to the next section: not spoken yet.
      await tester.tap(find.byKey(const ValueKey("speechCardNext")));
      await tester.pump();
      expect(find.text("one"), findsNothing);
      expect(find.textContaining("Not spoken yet"), findsOneWidget);
      // Boost switched off from the card.
      await tester.tap(find.byKey(const ValueKey("speechCardBoost")));
      await tester.pump();
      expect(c.speechOf("a")!.boost, isFalse);
      // An expressive voice from its list: its own knobs then.
      await tester.tap(find.byKey(const ValueKey("speechCardVoice")));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // A long list, built as it is scrolled.
      await tester.scrollUntilVisible(find.text("Expressive · Ryan"), 300,
          scrollable: find.byType(Scrollable).last);
      await tester.pump();
      await tester.tap(find.text("Expressive · Ryan").last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.speechOf("a")!.engine, SpeechEngineKind.expressive);
      expect(c.speechOf("a")!.voice, "ryan");
      expect(
          find.byKey(const ValueKey("speechCard-expression")), findsOneWidget);
      expect(tester.takeException(), isNull, reason: "nothing overflows");
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
