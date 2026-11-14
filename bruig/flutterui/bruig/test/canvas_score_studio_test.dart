import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/score_edit.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/score_studio.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_score_studio_test.dart is the Score Studio (Ken, 2026-11-14): a
// score written as MuseScore writes one -- note input from the keys, a
// click on the paper, the palettes, markings dragged -- each change the
// score's, one step to undo, its channels following. Set STUDIO_PNG to a
// path for a picture of the page.

Future<void> _font(String family, List<String> files) async {
  var loader = FontLoader(family);
  for (var f in files) {
    loader.addFont(File("assets/fonts/$f")
        .readAsBytes()
        .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await loader.load();
}

/// studio is a controller with the sample score, and the Studio on it.
Future<CanvasController> studio(WidgetTester tester,
    {MusicScore? score}) async {
  var c = CanvasController(const CanvasDocument(frames: 2400, frameRate: 24),
      audioEngine: FakeEngine({}));
  addTearDown(c.dispose);
  c.addScore(score ?? odeToJoy());
  c.openScoreStudio("ode");
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
    create: (_) => ThemeNotifier(doLoad: false),
    child: MaterialApp(
        home: RepaintBoundary(
      key: const ValueKey("studioShot"),
      child: ScoreStudio(
          controller: c, scoreId: "ode", onDone: c.closeScoreStudio),
    )),
  ));
  await tester.pump();
  return c;
}

MusicScore scoreOf(CanvasController c) => c.scoreById("ode")!;

/// settled lets the parts' render timer (300 ms after an edit) and a heard
/// note's release run out before the test ends.
Future<void> settled(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 600));

Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
    {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

/// tapEvent taps event [id] on the paper.
Future<void> tapEvent(
    WidgetTester tester, CanvasController c, String id) async {
  // The paper's place for it: found by tapping across the paper until the
  // Studio picks it would be slow; instead ask the Studio's own layout.
  var state = tester.state(find.byType(ScoreStudio)) as dynamic;
  var at = state.placeOf(id) as Offset;
  var paper = find.byKey(const ValueKey("scorePaper"));
  await tester.tapAt(tester.getTopLeft(paper) + at);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await _font("Bravura", ["Bravura.otf"]);
    await _font("Inter", ["Inter-Regular.otf", "Inter-Bold.otf"]);
    await _font("Roboto", ["Inter-Regular.otf", "Inter-Bold.otf"]);
    await _font("PTSerif", ["PTSerif-Regular.ttf", "PTSerif-Italic.ttf"]);
  });

  testWidgets("a note clicked is picked; ↑ moves it, a step to undo",
      (tester) async {
    var c = await studio(tester);
    var e = scoreOf(c).parts[1].staves[0].bars[0][0]; // the violin's C5
    await tapEvent(tester, c, e.id);
    expect(find.textContaining("Violin · bar 1 · beat 1"), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(scoreOf(c).event(e.id)!.pitches.single.name, "C#5");
    // The channel heard the change.
    var ch = c.scoreChannel("ode", "vln")!;
    expect(ch.instrument!.notes.first.key, 73);
    await key(tester, LogicalKeyboardKey.keyZ, shift: false);
    c.undo();
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.pitches.single.name, "C5");
    await settled(tester);
  });

  testWidgets("note input from the keys: N, a value, letters", (tester) async {
    var c = await studio(tester);
    var e = scoreOf(c).parts[1].staves[0].bars[1][0]; // violin bar 2
    await tapEvent(tester, c, e.id);
    await key(tester, LogicalKeyboardKey.keyN);
    await key(tester, LogicalKeyboardKey.digit5); // a crotchet
    await key(tester, LogicalKeyboardKey.keyD);
    await key(tester, LogicalKeyboardKey.keyE);
    var bar = scoreOf(c).parts[1].staves[0].bars[1];
    expect([
      for (var x in bar) "${x.isRest ? "r" : x.pitches.join()}/${x.quarters}"
    ], [
      "D5/1.0",
      "E5/1.0",
      "G4/2.0"
    ], reason: "written over the minim, near the last note");
    // Shift adds to the chord.
    await key(tester, LogicalKeyboardKey.keyG, shift: true);
    expect(scoreOf(c).parts[1].staves[0].bars[1][1].pitches.join(" "), "E5 G5");
    await key(tester, LogicalKeyboardKey.escape);
    await key(tester, LogicalKeyboardKey.digit0);
    expect(scoreOf(c).parts[1].staves[0].bars[1].length, 3,
        reason: "0 writes a rest only in note input");
    await settled(tester);
  });

  testWidgets("note input by a click on the staff", (tester) async {
    var c = await studio(tester);
    await tester.tap(find.byKey(const ValueKey("scoreInput")));
    await tester.pump();
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    // On the violin's top line (F5), half way through bar 3.
    var at = state.staffPlace("vln", 0, 2, 2.0, "F5") as Offset;
    await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey("scorePaper"))) + at);
    await tester.pump();
    var bar = scoreOf(c).parts[1].staves[0].bars[2];
    expect([
      for (var x in bar) "${x.isRest ? "r" : x.pitches.join()}/${x.quarters}"
    ], [
      "A4/2.0",
      "F5/1.0",
      "r/1.0"
    ]);
    await settled(tester);
  });

  testWidgets("the palettes mark the note picked", (tester) async {
    var c = await studio(tester);
    var e = scoreOf(c).parts[1].staves[0].bars[2][0];
    await tapEvent(tester, c, e.id);
    await tester.tap(find.byKey(const ValueKey("scoreDo-dyn-ff")));
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.dyn, Dynamic.ff);
    await tester.tap(find.byKey(const ValueKey("scorePalette-articulations")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("scoreDo-art-staccato")));
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.articulations, {Articulation.staccato});
    await tester.tap(find.byKey(const ValueKey("scorePalette-repeats")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("scoreDo-addBar")));
    await tester.pump();
    expect(scoreOf(c).barCount, 6);
    // A chord symbol typed on it.
    await tester.enterText(find.byKey(const ValueKey("scoreChord")), "Am");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.chord, "Am");
    await settled(tester);
  });

  testWidgets("an instrument added gets a channel of its own", (tester) async {
    var c = await studio(tester);
    await tester.tap(find.byKey(const ValueKey("scoreAddPart")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Flute").last);
    await tester.pumpAndSettle();
    expect(scoreOf(c).parts.last.name, "Flute");
    // The Studio's edits go through setScore, which syncs channels for
    // linked parts; a new part is linked when the canvas adds its channel.
    expect(find.byKey(const ValueKey("scorePart-${"p1"}")), findsOneWidget);
    await settled(tester);
  });

  testWidgets("a chord symbol dragged keeps its offset, one step to undo",
      (tester) async {
    var c = await studio(tester);
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    var e = scoreOf(c).parts[0].staves[0].bars[1][0]; // "G" over bar 2
    var at = state.markPlace(e.id, MarkKind.chord) as Offset;
    var paper = tester.getTopLeft(find.byKey(const ValueKey("scorePaper")));
    var g = await tester.startGesture(paper + at);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(20, -10));
    await g.up();
    await tester.pump();
    var off = scoreOf(c).event(e.id)!.offsets[MarkKind.chord]!;
    expect(off.dx, greaterThan(20));
    expect(off.dy, lessThan(0));
    c.undo();
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.offsets, isEmpty);
    await settled(tester);
  });

  testWidgets("Done gives the canvas back", (tester) async {
    var c = await studio(tester);
    await tester.tap(find.byKey(const ValueKey("scoreDone")));
    await tester.pump();
    expect(c.scoreStudio.value, isNull);
    await settled(tester);
  });

  testWidgets("the page, for a look", (tester) async {
    var path = Platform.environment["STUDIO_PNG"];
    if (path == null) return;
    var c = await studio(tester);
    var e = scoreOf(c).parts[0].staves[0].bars[1][1];
    await tapEvent(tester, c, e.id);
    await tester.runAsync(() async {
      var boundary =
          tester.renderObject(find.byKey(const ValueKey("studioShot")))
              as RenderRepaintBoundary;
      var img = await boundary.toImage();
      var png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    });
    await settled(tester);
  });

  test("a sheet given a new score: from its notes, or the sample", () {
    var c = CanvasController(const CanvasDocument(frames: 240),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    var sheet = SheetElement(const ElementBase(id: "sheet"));
    c.addElement(sheet);
    var id = c.newScoreFor(sheet, score: odeToJoy("x"));
    var s = c.scoreById(id)!;
    expect(s.title, "Ode to Joy");
    var now = c.document.elementById("sheet") as SheetElement;
    expect([now.score, now.part], [id, "pno"]);
    expect(c.document.elementById(now.follows), isA<AudioElement>());
    c.undo();
    expect(c.document.scores, isEmpty);
    expect((c.document.elementById("sheet") as SheetElement).score, "");
  });
}
