import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/score_edit.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart'
    show MarkKind;
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show InstrumentLook;
import 'package:bruig/plugin_system/canvas/model/text_spec.dart' show BoxSpec;
import 'package:bruig/plugin_system/canvas/render/score_engraver.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_score_sheet_test.dart is a Sheet music element showing a part of a
// score (Ken, 2026-11-14): engraved from the score, a page at a time; the
// playhead the canvas's own, put on a note by a press on the sheet, stepped
// a note at a time, drawn or left as the highlight alone; the part's
// keyboard under it lit with what is under the playhead.

const sheetBox = Rect.fromLTWH(40, 40, 1200, 420);

/// lesson is a controller with the sample score and a sheet on its piano
/// part, at 24 frames a second.
CanvasController lesson({int lines = 2, bool playhead = true}) {
  var c = CanvasController(
      const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.wide, width: 1280),
          frames: 24 * 60,
          frameRate: 24),
      audioEngine: FakeEngine({}));
  var sheet = SheetElement(
      ElementBase(
          id: "sheet",
          x: sheetBox.left,
          y: sheetBox.top,
          width: sheetBox.width,
          height: sheetBox.height),
      lines: lines,
      playhead: playhead);
  c.addElement(sheet);
  c.newScoreFor(sheet, score: odeToJoy());
  c.selectOnly("sheet");
  return c;
}

SheetElement sheetOf(CanvasController c) =>
    c.document.elementById("sheet") as SheetElement;

/// frameOf is the frame of [seconds] into the part's playing.
int frameOf(CanvasController c, double seconds) {
  var ch = c.sheetKeyboard(sheetOf(c))!;
  return ch.clip.at + (seconds * 24 - 1e-6).ceil();
}

/// placeOf is where on the canvas [sheet] draws event [id] at [frame].
Offset placeOf(CanvasController c, String id, {int? frame}) {
  var view = sheetViewOf(sheetOf(c), sheetBox, c.document, frame ?? c.frame)!;
  var hit = view.engraved.hits
      .firstWhere((h) => h.kind == ScoreHitKind.event && h.event == id);
  return view.origin + hit.rect.center * view.scale;
}

void main() {
  test("kept: the playhead's setting", () {
    var e = elementFromJson(
            SheetElement(const ElementBase(id: "s"), playhead: false).toJson())
        as SheetElement;
    expect(e.playhead, isFalse);
    expect(
        (elementFromJson(SheetElement(const ElementBase(id: "s")).toJson())
                as SheetElement)
            .playhead,
        isTrue);
  });

  test("a page at a time, turned to the one the playhead is on", () {
    var c = lesson(lines: 1);
    addTearDown(c.dispose);
    var e = sheetOf(c);
    // Eight more bars: more than one system of the piano part alone.
    c.setScore(c.scoreById(e.score)!.insertBars(5, 8));
    var first = sheetViewOf(e, sheetBox, c.document, frameOf(c, 0))!;
    expect(first.place!.bar, 0);
    var s = c.scoreById(e.score)!;
    var order = s.playOrder();
    var at = s.secondsAt(order, order.last.start + 1);
    var late = sheetViewOf(e, sheetBox, c.document, frameOf(c, at))!;
    expect(late.place!.bar, 12);
    expect(late.window.top, greaterThan(first.window.top),
        reason: "turned to the page with bar 5");
  });

  test("one hand: only its staff", () {
    var c = lesson();
    addTearDown(c.dispose);
    var right = sheetOf(c).copyWith(hands: PracticeHands.right);
    var view = sheetViewOf(right, sheetBox, c.document, 0)!;
    expect({for (var h in view.engraved.hits) h.staff}, {0});
    expect(sheetStaves(view.part, PracticeHands.left), {1});
  });

  test("stepped a note at a time, and back to the start", () async {
    var c = lesson();
    addTearDown(c.dispose);
    var e = sheetOf(c);
    c.sheetToStart(e);
    var start = c.frame;
    expect(start, frameOf(c, 0));
    // Crotchets at 112: a beat is 60/112 s.
    c.stepSheet(e, 1);
    expect(c.frame, frameOf(c, 60 / 112));
    // Stepped onto, a note is under the playhead at once: lit and heard
    // (bar 2's F4 starts 2.68 s in, between frames 64 and 65).
    var ch = c.sheetKeyboard(e)!;
    var back = c.frame;
    for (var i = 0; i < 4; i++) {
      c.stepSheet(e, 1);
    }
    // What is under the playhead, not what a step is still holding.
    expect(ch.instrument!.sounding((c.frame - ch.clip.at) / 24), contains(65));
    // Stepped quickly, only the last step's notes are held.
    expect(c.heldKeys(ch.id), {65, 43, 50});
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(c.heldKeys(ch.id), isEmpty, reason: "let go after a moment");
    c.frame = back;
    c.stepSheet(e, 1);
    expect(c.frame, frameOf(c, 2 * 60 / 112));
    c.stepSheet(e, -1);
    expect(c.frame, frameOf(c, 60 / 112));
    c.sheetToStart(e);
    expect(c.frame, start);
    c.stepSheet(e, -1);
    expect(c.frame, start, reason: "nothing before the first");
  });

  test("a press on a note: the playhead goes to it", () {
    var c = lesson();
    addTearDown(c.dispose);
    var s = c.scoreById(sheetOf(c).score)!;
    var third = s.parts[0].staves[0].bars[1][2]; // bar 2, beat 3
    expect(c.sheetPressed(sheetOf(c), sheetBox, placeOf(c, third.id)), isTrue);
    expect(c.frame, frameOf(c, 6 * 60 / 112));
    // Off the staves, nothing.
    var was = c.frame;
    expect(
        c.sheetPressed(
            sheetOf(c), sheetBox, sheetBox.bottomRight - const Offset(2, 2)),
        isFalse);
    expect(c.frame, was);
  });

  test("a repeated bar: the time round nearest where the playhead is", () {
    var c = lesson();
    addTearDown(c.dispose);
    var s = c.scoreById(sheetOf(c).score)!;
    var order = s.playOrder();
    // Second time through bar 1.
    var second = order.indexWhere((p) => p.bar == 0 && p.pass == 2);
    c.frame = frameOf(c, s.secondsAt(order, order[second].start + 0.5));
    var first = s.parts[0].staves[0].bars[0][0];
    c.sheetPressed(sheetOf(c), sheetBox, placeOf(c, first.id));
    expect(c.frame, frameOf(c, s.secondsAt(order, order[second].start)));
  });

  Future<int> orangeIn(CanvasController c) async {
    var rec = ui.PictureRecorder();
    paintSheetElement(
        ui.Canvas(rec), sheetBox, sheetOf(c), c.document, c.frame);
    var img = await rec.endRecording().toImage(1280, 720);
    var raw = (await img.toByteData())!;
    var n = 0;
    for (var i = 0; i < raw.lengthInBytes; i += 4) {
      var r = raw.getUint8(i), g = raw.getUint8(i + 1), b = raw.getUint8(i + 2);
      if (r > 200 && g > 80 && g < 120 && b < 70) n++;
    }
    return n;
  }

  test("drawn from the score: the playhead, or the highlight alone", () async {
    var c = lesson();
    addTearDown(c.dispose);
    c.frame = frameOf(c, 60 / 112 * 1.5);
    var shown = await orangeIn(c);
    c.replaceElement(sheetOf(c).copyWith(playhead: false));
    var lit = await orangeIn(c);
    expect(shown, greaterThan(lit + 50), reason: "the line is drawn");
    expect(lit, greaterThan(0), reason: "the note under it is still lit");
  });

  test("its keyboard under it, lit with what is under the playhead", () {
    var c = lesson();
    addTearDown(c.dispose);
    var e = sheetOf(c);
    expect(c.sheetKeyboard(e)!.base.visible, isFalse);
    c.showSheetKeyboard(e, true);
    var keys = c.sheetKeyboard(e)!;
    expect(keys.base.visible, isTrue);
    expect(keys.base.y, greaterThanOrEqualTo(sheetBox.bottom));
    expect(keys.base.width, sheetBox.width);
    // Its keys reach the part's lowest note (G2) and highest (G4).
    expect(keys.instrument!.lowKey, 36);
    expect(keys.instrument!.highKey, greaterThanOrEqualTo(67));
    c.sheetToStart(e);
    // Bar 1 beat 1: E4 in the right hand, C3 G3 in the left.
    expect(c.audioState(keys).keys, {64, 48, 55});
    c.showSheetKeyboard(e, false);
    expect(c.sheetKeyboard(e)!.base.visible, isFalse);
  });

  test("practice marks fall on the score's events", () {
    var c = lesson();
    addTearDown(c.dispose);
    var view = sheetViewOf(sheetOf(c), sheetBox, c.document, 0)!;
    var notes = view.channel.instrument!.notes;
    var i = notes.indexWhere((n) => n.key == 64 && n.start == 0);
    var marks = sheetEventMarks(view, {i: const Color(0xFF00FF00)});
    var first = view.score.parts[0].staves[0].bars[0][0];
    expect(marks, {first.id: const Color(0xFF00FF00)});
  });

  testWidgets("on the stage: the sheet picked, a press puts the playhead",
      (tester) async {
    var c = lesson();
    addTearDown(c.dispose);
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
    var scale = page.width / 1280;
    var s = c.scoreById(sheetOf(c).score)!;
    var target = s.parts[0].staves[0].bars[2][1]; // bar 3, beat 2
    await tester.tapAt(page.topLeft + placeOf(c, target.id) * scale);
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.frame, frameOf(c, 9 * 60 / 112));
    expect(sheetOf(c).base.x, sheetBox.left, reason: "a press, not a move");
  });

  testWidgets("its settings step the playhead, turn the line off, show keys",
      (tester) async {
    var c = lesson();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1200, 2400);
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
              body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: CanvasControlScope(
              maxWidth: 280,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: elementSettings(context, c, c.selected!)),
            ),
          ),
        ),
      ))),
    ));
    await tester.pump();
    Future<void> press(String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pump();
    }

    await press("sheetStart");
    var start = c.frame;
    await press("sheetStepOn");
    expect(c.frame, greaterThan(start));
    await press("sheetStepBack");
    expect(c.frame, start);
    await press("sheetKeyboard");
    expect(c.sheetKeyboard(sheetOf(c))!.base.visible, isTrue);
    var line = find.byKey(const ValueKey("sheetPlayhead"));
    await tester.ensureVisible(line);
    await tester.tap(line);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Highlight only").last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(sheetOf(c).playhead, isFalse);
  });

  // Ken, 2026-11-14: "when I export as video ... the notes on the piano
  // don't show". A frame made with nothing live lights the keys as the
  // editor does while it plays.
  test("made into a video, its keyboard lights the notes under the playhead",
      () async {
    var c = lesson();
    addTearDown(c.dispose);
    c.showSheetKeyboard(sheetOf(c), true);
    var keys = c.sheetKeyboard(sheetOf(c))!;
    Future<int> amber(int frame) async {
      var img = await renderFrame(c.document, frame: frame);
      var raw = (await img.toByteData())!;
      var w = img.width;
      var scale = w / 1280;
      var box = Rect.fromLTWH(
          keys.base.x, keys.base.y, keys.base.width, keys.base.height);
      var n = 0;
      for (var y = (box.top * scale).toInt();
          y < box.bottom * scale && y < img.height;
          y++) {
        for (var x = (box.left * scale).toInt(); x < box.right * scale; x++) {
          var i = (y * w + x) * 4;
          var r = raw.getUint8(i),
              g = raw.getUint8(i + 1),
              b = raw.getUint8(i + 2);
          // The accent's amber, lightened on a white key, darkened on a black.
          if (r > 170 && r > g + 25 && g > b + 40) n++;
        }
      }
      img.dispose();
      return n;
    }

    // The first chord sounds at the start; long after the last, nothing.
    var playing = await amber(frameOf(c, 0.1));
    var after = await amber(24 * 50);
    expect(playing, greaterThan(after + 200));
  });

  // Ken, 2026-11-14: "changing the Paper colour only changes the head of
  // the sheet music ... not possible to make the paper transparent ... the
  // Ink colour isn't working".
  Future<(ByteData, int)> drawn(SheetElement e, CanvasDocument doc) async {
    var rec = ui.PictureRecorder();
    paintSheetElement(ui.Canvas(rec), sheetBox, e, doc, 0);
    var img = await rec.endRecording().toImage(1280, 720);
    var raw = (await img.toByteData())!;
    return (raw, img.width);
  }

  test("its paper and ink: the whole sheet's, the paper down to none",
      () async {
    var c = lesson();
    addTearDown(c.dispose);
    var e = sheetOf(c);
    var view = sheetViewOf(e, sheetBox, c.document, 0)!;
    // A blank place inside the engraving: right of the last bar line's
    // end, on the first system's height between its staves.
    var blank = view.origin +
        Offset(view.engraved.options.width - 4,
                view.engraved.systems.first.top + 8) *
            view.scale;
    int at(ByteData raw, int w, Offset p, int ch) =>
        raw.getUint8((p.dy.toInt() * w + p.dx.toInt()) * 4 + ch);

    var green = e.copyWith(paper: const Color(0xFF20C060));
    var (raw, w) = await drawn(green, c.document);
    expect([
      at(raw, w, blank, 0),
      at(raw, w, blank, 1),
      at(raw, w, blank, 2)
    ], [
      0x20,
      0xC0,
      0x60
    ], reason: "the paper under the music too");

    var none = e.copyWith(paper: const Color(0x00FFFFFF));
    (raw, w) = await drawn(none, c.document);
    expect(at(raw, w, blank, 3), 0, reason: "no paper: nothing drawn there");

    int reds(ByteData raw) {
      var n = 0;
      for (var i = 0; i < raw.lengthInBytes; i += 4) {
        if (raw.getUint8(i) > 200 &&
            raw.getUint8(i + 1) < 60 &&
            raw.getUint8(i + 2) < 60) {
          n++;
        }
      }
      return n;
    }

    var (plain, _) = await drawn(e.copyWith(playhead: false), c.document);
    var (red, _) = await drawn(
        e.copyWith(ink: const Color(0xFFFF0000), playhead: false), c.document);
    expect(reds(red), greaterThan(reds(plain) + 500),
        reason: "the music in red ink");
  });

  // "the title, subtitle and composer information isn't being shown in
  // the canvas ... a hide/show button for each".
  test("its heading: title, subtitle, composer and tempo, each shown or not",
      () {
    var c = lesson();
    addTearDown(c.dispose);
    var e = sheetOf(c);
    // How far down the first staff is: below whatever heading is shown.
    double headed(SheetElement x) => sheetViewOf(x, sheetBox, c.document, 0)!
        .engraved
        .hits
        .firstWhere((h) => h.kind == ScoreHitKind.staff)
        .bottom;
    var all = headed(e);
    var none = headed(e.copyWith(
        showTitle: false,
        showSubtitle: false,
        showComposer: false,
        showTempo: false));
    expect(all, greaterThan(none + 8 * 8), reason: "room made for the heading");
    // Each on its own takes its row away.
    for (var off in [
      e.copyWith(showTitle: false),
      e.copyWith(showSubtitle: false),
      e.copyWith(showComposer: false),
      e.copyWith(showTempo: false),
    ]) {
      expect(headed(off), lessThan(all));
    }
    var back = elementFromJson(e.copyWith(showComposer: false).toJson())
        as SheetElement;
    expect([back.showTitle, back.showComposer], [true, false]);
  });

  // Ken, 2026-11-14: "the ability for the sheet music canvas to have a
  // playbar over the top of the sheet music ... to hide or show this play
  // bar as for things like video export it won't be needed."
  group("its playbar", () {
    test("over the music: the music laid out under it, or not there at all",
        () {
      var c = lesson();
      addTearDown(c.dispose);
      var e = sheetOf(c);
      var bar = sheetBarRect(e, sheetBox)!;
      expect(bar.top, sheetBox.top);
      var under = sheetViewOf(e, sheetBox, c.document, 0)!;
      var top = under.origin.dy + under.window.top * under.scale;
      expect(top, greaterThanOrEqualTo(bar.bottom - 0.01));
      var off = e.copyWith(playbar: false);
      expect(sheetBarRect(off, sheetBox), isNull);
      var round = elementFromJson(off.toJson()) as SheetElement;
      expect(round.playbar, isFalse);
    });

    test("its buttons: to the start, a note back and on, play and pause", () {
      var c = lesson();
      addTearDown(c.dispose);
      var e = sheetOf(c);
      var parts = sheetBarParts(sheetBarRect(e, sheetBox)!);
      Offset at(SheetBarPart p) => parts[p]!.center;
      c.sheetPressed(e, sheetBox, at(SheetBarPart.start));
      var start = c.frame;
      c.sheetPressed(e, sheetBox, at(SheetBarPart.on));
      expect(c.frame, frameOf(c, 60 / 112));
      c.sheetPressed(e, sheetBox, at(SheetBarPart.back));
      expect(c.frame, start);
      c.sheetPressed(e, sheetBox, at(SheetBarPart.play));
      expect(c.playing, isTrue);
      expect(sheetPlaying!(), isTrue, reason: "the button shows pause");
      c.sheetPressed(e, sheetBox, at(SheetBarPart.play));
      expect(c.playing, isFalse);
    });

    test("its track: pressed along it, the playhead goes that far", () {
      var c = lesson();
      addTearDown(c.dispose);
      var e = sheetOf(c);
      var track =
          sheetBarParts(sheetBarRect(e, sheetBox)!)[SheetBarPart.track]!;
      c.sheetPressed(
          e, sheetBox, Offset(track.left + track.width / 2, track.center.dy));
      var s = c.scoreById(e.score)!;
      var total = s.secondsAt(s.playOrder(), s.lengthQuarters());
      expect(c.frame, closeTo(frameOf(c, total / 2), 1));
    });

    testWidgets("on the stage, pressed without picking the sheet first",
        (tester) async {
      var c = lesson();
      addTearDown(c.dispose);
      c.clearSelection();
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
      var scale = page.width / 1280;
      var on =
          sheetBarParts(sheetBarRect(sheetOf(c), sheetBox)!)[SheetBarPart.on]!;
      c.sheetToStart(sheetOf(c));
      var start = c.frame;
      await tester.tapAt(page.topLeft + on.center * scale);
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.frame, greaterThan(start));
      expect(c.selection, {"sheet"});
    });

    test("drawn over the music, and gone when switched off", () async {
      var c = lesson();
      addTearDown(c.dispose);
      var e = sheetOf(c);
      var bar = sheetBarRect(e, sheetBox)!;
      Future<int> marked(SheetElement x) async {
        var rec = ui.PictureRecorder();
        paintSheetElement(ui.Canvas(rec), sheetBox, x, c.document, 0);
        var img = await rec.endRecording().toImage(1280, 720);
        var raw = (await img.toByteData())!;
        var n = 0;
        for (var y = bar.top.toInt(); y < bar.bottom; y++) {
          for (var x = bar.left.toInt(); x < bar.right; x++) {
            var i = (y * img.width + x) * 4;
            if (raw.getUint8(i) < 120 && raw.getUint8(i + 3) > 200) n++;
          }
        }
        return n;
      }

      expect(await marked(e), greaterThan(150), reason: "its buttons");
      var none = await marked(e.copyWith(
          playbar: false,
          showTitle: false,
          showSubtitle: false,
          showComposer: false,
          showTempo: false));
      expect(none, lessThan(await marked(e)));
    });
  });

  test("its instrument names, shown or not", () {
    var c = lesson();
    addTearDown(c.dispose);
    var e = sheetOf(c);
    double left(SheetElement x) => sheetViewOf(x, sheetBox, c.document, 0)!
        .engraved
        .hits
        .firstWhere((h) => h.kind == ScoreHitKind.staff)
        .rect
        .left;
    expect(left(e.copyWith(showNames: false)), lessThan(left(e)));
    var back =
        elementFromJson(e.copyWith(showNames: false).toJson()) as SheetElement;
    expect(back.showNames, isFalse);
  });

  // Ken, 2026-11-14: "the ability to pick a range of bars to display and
  // playback on canvas" -- "show bars 5 to 8".
  group("a range of bars", () {
    test("only those bars shown, and its span where they play", () {
      var c = lesson();
      addTearDown(c.dispose);
      var e = sheetOf(c).copyWith(fromBar: 2, toBar: 3);
      var view = sheetViewOf(e, sheetBox, c.document, 0)!;
      expect({
        for (var h in view.engraved.hits)
          if (h.kind == ScoreHitKind.staff) h.bar
      }, {
        1,
        2
      });
      var s = c.scoreById(e.score)!;
      var (from, to) = sheetSpan(e, s);
      // Bars 2 and 3, the first time through: beats 4 to 12 at 112.
      expect(from, closeTo(4 * 60 / 112, 1e-9));
      expect(to, closeTo(12 * 60 / 112, 1e-9));
      var back = elementFromJson(e.toJson()) as SheetElement;
      expect([back.fromBar, back.toBar], [2, 3]);
    });

    test("its Play starts at its first bar and stops at its last's end", () {
      var c = lesson();
      addTearDown(c.dispose);
      c.replaceElement(sheetOf(c).copyWith(fromBar: 2, toBar: 3));
      var e = sheetOf(c);
      var (start, end) = sheetFrames(e, c.document)!;
      c.frame = 0;
      var play = sheetBarParts(sheetBarRect(e, sheetBox)!)[SheetBarPart.play]!;
      c.sheetPressed(e, sheetBox, play.center);
      expect(c.playing, isTrue);
      expect(c.frame, start, reason: "from the range's first bar");
      for (var i = 0; i < end - start + 5 && c.playing; i++) {
        c.tickForTest();
      }
      expect(c.playing, isFalse, reason: "stopped at its end");
      expect(c.frame, end - 1);
      // Its steps keep within it.
      c.sheetToStart(e);
      expect(c.frame, start);
      for (var i = 0; i < 40; i++) {
        c.stepSheet(e, 1);
      }
      expect(c.frame, lessThan(end));
    });

    test("its rehearsal marks hidden, and the room for them", () async {
      var c = lesson();
      addTearDown(c.dispose);
      var e = sheetOf(c);
      Future<SheetView> painted(SheetElement x) async {
        var rec = ui.PictureRecorder();
        paintSheetElement(ui.Canvas(rec), sheetBox, x, c.document, 0);
        rec.endRecording().dispose();
        return sheetViewOf(x, sheetBox, c.document, 0)!;
      }

      var shown = await painted(e);
      expect(shown.engraved.hits.where((h) => h.mark == MarkKind.rehearsal),
          hasLength(1));
      var hidden = await painted(e.copyWith(showMarks: false));
      expect(hidden.engraved.hits.where((h) => h.mark == MarkKind.rehearsal),
          isEmpty);
    });
  });

  test("its frame: room round the music, corners and a border", () async {
    var c = lesson();
    addTearDown(c.dispose);
    var e = sheetOf(c).copyWith(
        playbar: false,
        box: const BoxSpec(
            padding: 30,
            borderWidth: 6,
            borderColor: Color(0xFF0000FF),
            borderRadius: 12));
    var view = sheetViewOf(e, sheetBox, c.document, 0)!;
    expect(view.origin.dy + view.window.top * view.scale,
        greaterThanOrEqualTo(sheetBox.top + 30 - 0.01),
        reason: "the music inside the room");
    var rec = ui.PictureRecorder();
    paintSheetElement(ui.Canvas(rec), sheetBox, e, c.document, 0);
    var img = await rec.endRecording().toImage(1280, 720);
    var raw = (await img.toByteData())!;
    int at(int x, int y) => (y * img.width + x) * 4;
    // The border on the left edge, half way down.
    var i = at(sheetBox.left.toInt() + 2, sheetBox.center.dy.toInt());
    expect([raw.getUint8(i), raw.getUint8(i + 1), raw.getUint8(i + 2)],
        [0, 0, 255]);
    var back = elementFromJson(e.toJson()) as SheetElement;
    expect(back.box.padding, 30);
  });

  testWidgets("its instrument shown as another: a guitar's neck",
      (tester) async {
    var c = lesson();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1200, 3000);
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
              body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: CanvasControlScope(
              maxWidth: 280,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: elementSettings(context, c, c.selected!)),
            ),
          ),
        ),
      ))),
    ));
    await tester.pump();
    var look = find.byKey(const ValueKey("sheetInstrumentLook"));
    await tester.ensureVisible(look);
    await tester.tap(look);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Guitar").last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
        c.sheetKeyboard(sheetOf(c))!.instrument!.look, InstrumentLook.guitar);
    expect(find.text("Show its instrument"), findsOneWidget);
  });
}
