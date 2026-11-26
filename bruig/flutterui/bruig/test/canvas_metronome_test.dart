import 'dart:io';
import 'support/canvas_app.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';
import 'canvas_score_sheet_test.dart' as sheet;

// canvas_metronome_test.dart is the metronome: one standing alone, drawn as
// a clockwork one with a tempo to set, and the one in sheet music's
// playhead, whose speed changes with the music's and goes back to real
// time. Set METRONOME_PNG to a path for a picture of one.

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
      expect(now().beats, 5);
      c.setMetronome(now().copyWith(beats: 12));
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
      setTestScreen(tester, const Size(1600, 1000));
      await tester.pumpWidget(canvasApp(SizedBox(
          width: 1600,
          height: 1000,
          child: CanvasStage(key: key, controller: c))));
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

  group("a metronome going", () {
    // A metronome started, its click heard [heard] seconds in: the voice the
    // engine plays it on stands there, as a real one's would have got to.
    Future<(CanvasController, FakeEngine, MetronomeElement Function())> going(
        {double heard = 1.5}) async {
      var engine = FakeEngine({});
      var c = CanvasController(const CanvasDocument(), audioEngine: engine);
      addTearDown(c.dispose);
      var m = newElement(ElementKind.metronome, c.document) as MetronomeElement;
      c.addElement(m);
      MetronomeElement now() =>
          c.document.elementById(m.id) as MetronomeElement;
      c.toggleMetronome(now());
      await settle();
      engine.voices.last.at = heard;
      return (c, engine, now);
    }

    test("its swing is where its click has been heard to", () async {
      var (c, _, now) = await going(heard: 3);
      expect(c.metronomeShowFor(now()).beats, closeTo(5, 1e-9),
          reason: "three seconds at 100 a minute");
    });

    test("until its click is first heard, it waits on its first beat",
        () async {
      var engine = FakeEngine({});
      var c = CanvasController(const CanvasDocument(), audioEngine: engine);
      addTearDown(c.dispose);
      var m = newElement(ElementKind.metronome, c.document) as MetronomeElement;
      c.addElement(m);
      c.toggleMetronome(m);
      // The sound is still getting ready: nothing heard, nothing swung.
      sleep(const Duration(milliseconds: 30));
      expect(c.metronomeShowFor(m).beats, 0);
      await settle();
      expect(c.metronomeShowFor(m).beats, 0, reason: "heard from its start");
      engine.voices.last.at = 0.3;
      expect(c.metronomeShowFor(m).beats, closeTo(0.5, 1e-9));
    });

    test("with no sound to be had, it swings by the clock alone", () async {
      var engine = FakeEngine({})..works = false;
      var c = CanvasController(const CanvasDocument(), audioEngine: engine);
      addTearDown(c.dispose);
      var m = newElement(ElementKind.metronome, c.document) as MetronomeElement;
      c.addElement(m);
      c.toggleMetronome(m);
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      var show = c.metronomeShowFor(m);
      expect(show.going, isTrue);
      expect(show.beats, greaterThan(0.15));
    });

    test("a colour changed leaves its swing and its click alone", () async {
      var (c, engine, now) = await going();
      var voice = engine.voices.last;
      var clicks = engine.clicks.length;
      c.setMetronome(now().copyWith(
          body: const Color(0xFF225588), accent: const Color(0xFF33AA66)));
      await settle();
      expect(engine.voices.last, same(voice), reason: "the same click");
      expect(voice.alive, isTrue);
      expect(voice.at, 1.5, reason: "not sent back to the start");
      expect(engine.clicks, hasLength(clicks));
      expect(c.metronomeShowFor(now()).beats, closeTo(2.5, 1e-9));
    });

    test("a change of tempo goes on from the beat it is on", () async {
      var (c, engine, now) = await going();
      c.metronomeStep(now(), 20);
      await settle();
      expect(engine.clicks.last, (0.5, 4));
      expect(engine.voices.last.at, closeTo(2.5 * 0.5, 1e-9),
          reason: "two and a half beats in, at the new tempo");
      expect(c.metronomeShowFor(now()).beats, closeTo(2.5, 1e-9));
    });

    test("a change of beats in a bar goes on from the beat it is on", () async {
      var (c, engine, now) = await going();
      c.cycleMetronomeBeats(now());
      await settle();
      expect(engine.clicks.last, (0.6, 5));
      expect(engine.voices.last.at, closeTo(1.5, 1e-9));
      expect(c.metronomeShowFor(now()).beats, closeTo(2.5, 1e-9));
    });

    // What is drawn of a metronome going is asked of the window it goes
    // in: an export, and a canvas drawn after its editor has gone, draw it
    // at rest.
    Future<List<int>> drawn(CanvasDocument doc) async {
      var image = await renderFrame(doc);
      var raw = (await image.toByteData())!.buffer.asUint8List().toList();
      image.dispose();
      return raw;
    }

    test("an export draws it at rest while it goes", () async {
      var (c, _, now) = await going();
      c.toggleMetronome(now());
      var still = await drawn(c.document);
      c.toggleMetronome(now());
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.metronomeGoing(now().id), isTrue);
      expect(await drawn(c.document), still);
    });

    test("drawn once its editor has gone, it is at rest", () async {
      var engine = FakeEngine({});
      var c = CanvasController(const CanvasDocument(), audioEngine: engine);
      var m = newElement(ElementKind.metronome, c.document) as MetronomeElement;
      c.addElement(m);
      var doc = c.document;
      var still = await drawn(doc);
      c.toggleMetronome(m);
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      c.dispose();
      expect(await drawn(doc), still);
    });
  });

  group("beats in a bar", () {
    test("its beats button steps through every number it can hold", () {
      var c =
          CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var m =
          (newElement(ElementKind.metronome, c.document) as MetronomeElement)
              .copyWith(beats: 5);
      c.addElement(m);
      MetronomeElement now() =>
          c.document.elementById(m.id) as MetronomeElement;
      c.cycleMetronomeBeats(now());
      expect(now().beats, 6, reason: "on from five, not back to one");
      c.setMetronome(now().copyWith(beats: 12));
      c.cycleMetronomeBeats(now());
      expect(now().beats, 1, reason: "round from the most it holds");
    });

    for (var scale in [0.65, 1.0, 1.5]) {
      testWidgets("its settings offer every number it can hold, at $scale",
          (tester) async {
        var c = CanvasController(const CanvasDocument(),
            audioEngine: FakeEngine({}));
        addTearDown(c.dispose);
        var m =
            (newElement(ElementKind.metronome, c.document) as MetronomeElement)
                .copyWith(beats: 5);
        c.addElement(m);
        setTestScreen(tester, const Size(800, 3000));
        await tester.pumpWidget(canvasApp(MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                  child: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => Column(
                          children: elementSettings(
                              context, c, c.document.elementById(m.id)!))))),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        var beats = tester.widget<CanvasDropdown<int>>(
            find.byKey(const ValueKey("metronomeBeats")));
        expect([for (var (b, _) in beats.options) b],
            [for (var b = 1; b <= 12; b++) b]);
        expect(beats.value, 5);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey("metronomeBeats")),
                matching: find.text("5")),
            findsOneWidget,
            reason: "a five received is shown, not a blank");
        await tester.pumpWidget(const SizedBox());
      });
    }
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
