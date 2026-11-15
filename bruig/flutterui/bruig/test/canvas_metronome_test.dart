import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';
import 'canvas_score_sheet_test.dart' as sheet;

// canvas_metronome_test.dart is the metronome (Ken, 2026-11-15: "a stand
// alone metronome, that looks like a metronome and has an adjustable bpm
// ... and a metronome that is built into the sheetmusic playhead ... change
// the speed of the sheet music and it's metronome and a reset button to go
// back to real time"). Set METRONOME_PNG to a path for a picture of one.

Future<void> _font(String family, List<String> files) async {
  var loader = FontLoader(family);
  for (var f in files) {
    loader.addFont(File("assets/fonts/$f")
        .readAsBytes()
        .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await loader.load();
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUpAll(() async {
    await _font("Inter", ["Inter-Regular.otf", "Inter-ExtraBold.otf"]);
    await _font("RobotoMono", ["RobotoMono-VariableFont_wght.ttf"]);
  });

  group("a metronome on the canvas", () {
    test("kept; a tempo's word; as fast as a clockwork one goes", () {
      var e = const MetronomeElement(ElementBase(id: "m"), bpm: 72, beats: 3);
      var back = elementFromJson(e.toJson()) as MetronomeElement;
      expect((back.bpm, back.beats), (72, 3));
      expect(tempoWord(60), "Adagio");
      expect(tempoWord(120), "Allegro");
      expect(e.copyWith(bpm: 400).bpm, metronomeFastest);
      expect(e.copyWith(bpm: 72.4).bpm, 72, reason: "whole beats a minute");
    });

    test("started, it clicks on a click of its own; faster, slower, tapped",
        () async {
      var engine = FakeEngine({});
      var c = CanvasController(const CanvasDocument(), audioEngine: engine);
      addTearDown(c.dispose);
      var m = newElement(ElementKind.metronome, c.document) as MetronomeElement;
      c.addElement(m);
      MetronomeElement now() =>
          c.document.elementById(m.id) as MetronomeElement;
      c.toggleMetronome(now());
      await settle();
      expect(c.metronomeGoing(m.id), isTrue);
      expect(engine.clicks.last, (0.6, 4), reason: "100 a minute, in fours");
      c.metronomeStep(now(), 20);
      await settle();
      expect(now().bpm, 120);
      expect(engine.clicks.last, (0.5, 4), reason: "going on at the new speed");
      c.cycleMetronomeBeats(now());
      expect(now().beats, 6);
      c.cycleMetronomeBeats(now());
      expect(now().beats, 1, reason: "round to every beat alike");
      for (var t in [10.0, 10.75, 11.5, 12.25]) {
        c.tapMetronome(now(), at: t);
      }
      expect(now().bpm, 80, reason: "taps three quarters of a second apart");
      c.toggleMetronome(now());
      expect(c.metronomeGoing(m.id), isFalse);
      // The canvas's own click is another: the metronome's is not it.
      c.metronome = true;
      expect(c.metronome, isTrue);
    });

    test("its pendulum: at one side on a beat, the other on the next", () {
      expect(metronomeAngle(0), lessThan(-0.3));
      expect(metronomeAngle(1), greaterThan(0.3));
      expect(metronomeAngle(0.5).abs(), lessThan(1e-9), reason: "upright");
    });

    testWidgets("its buttons on the stage, pressed without picking it",
        (tester) async {
      var c =
          CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var m = newElement(ElementKind.metronome, c.document) as MetronomeElement;
      c.addElement(m, select: false);
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
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
                body: SizedBox(
                    width: 1600,
                    height: 1000,
                    child: CanvasStage(key: key, controller: c)))),
      ));
      await tester.pumpAndSettle();
      var page = key.currentState!.pageRect;
      var scale = page.width / c.document.size.width;
      Offset at(MetronomePart p) {
        var (s, o) = metronomeFit(m.bounds);
        return page.topLeft +
            (o + metronomeLayout.buttons[p]!.center * s) * scale;
      }

      await tester.tapAt(at(MetronomePart.faster));
      await tester.pump(const Duration(milliseconds: 400));
      expect((c.document.elementById(m.id) as MetronomeElement).bpm, 104);
      await tester.tapAt(at(MetronomePart.play));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.metronomeGoing(m.id), isTrue);
      await tester.tapAt(at(MetronomePart.play));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.metronomeGoing(m.id), isFalse);
      await tester.pump(const Duration(seconds: 1));
    });

    test("drawn", () async {
      var m =
          const MetronomeElement(ElementBase(id: "m", width: 200, height: 320));
      var rec = ui.PictureRecorder();
      paintMetronome(ui.Canvas(rec), m.bounds, m,
          show: const MetronomeShow(going: true, beats: 4.1));
      var img = await rec.endRecording().toImage(200, 320);
      var raw = (await img.toByteData())!;
      // Its lamp lit on the bar's first beat, in its accent.
      var i = (22 * 200 + 100) * 4;
      expect(raw.getUint8(i), greaterThan(180));
      if (Platform.environment["METRONOME_PNG"] case var path?) {
        var png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
  });

  group("a sheet's speed and click", () {
    test("its playbar: slower, faster, back to real time, its click", () {
      var c = sheet.lesson();
      addTearDown(c.dispose);
      SheetElement s() => sheet.sheetOf(c);
      var bar = sheetBarRect(s(), sheet.sheetBox)!;
      var parts = sheetBarParts(bar);
      void press(SheetBarPart p) =>
          c.sheetPressed(s(), sheet.sheetBox, parts[p]!.center);
      press(SheetBarPart.slower);
      press(SheetBarPart.slower);
      expect(s().tempo, closeTo(0.9, 1e-9));
      press(SheetBarPart.faster);
      expect(s().tempo, closeTo(0.95, 1e-9));
      press(SheetBarPart.reset);
      expect(s().tempo, 1, reason: "back to real time");
      press(SheetBarPart.click);
      expect(s().click, isTrue);
      // A book's playbar has none of them: its sound is made at its speed.
      expect(sheetBarParts(bar, practice: false).keys,
          isNot(contains(SheetBarPart.click)));
      expect(sheetBarParts(bar, practice: false)[SheetBarPart.track]!.width,
          greaterThan(parts[SheetBarPart.track]!.width));
    });

    test("slowed, its notes play live at its speed, and its click with them",
        () async {
      var engine = FakeEngine({});
      // The lesson's own engine is a fake too; this one counts.
      var c = sheet.lesson();
      c.dispose();
      var d = CanvasController(c.document, audioEngine: engine);
      addTearDown(d.dispose);
      var s0 = d.document.elementById("sheet") as SheetElement;
      d.setSheetClick(s0, true);
      d.setSheetSpeed(d.document.elementById("sheet") as SheetElement, 0.5);
      var s = d.document.elementById("sheet") as SheetElement;
      expect(s.tempo, 0.5);
      var t = 0;
      d.clockForTest = () => t;
      d.playSheet(s);
      // A second of the clock: half a second of the piece.
      for (var i = 1; i <= 24; i++) {
        t = i * 1000000 ~/ 24;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await settle();
      var frame = d.frame;
      d.pause();
      expect(frame, inInclusiveRange(10, 14),
          reason: "half speed: about 12 frames in a second, not 24");
      expect(engine.notes.where((n) => n.$3 > 0), isNotEmpty,
          reason: "its notes sounded live, not its part's sound");
      // The score's beat (112 a minute) at half speed.
      expect(engine.clicks.last.$1, closeTo(60 / 112 / 0.5, 1e-6));
    });
  });
}
