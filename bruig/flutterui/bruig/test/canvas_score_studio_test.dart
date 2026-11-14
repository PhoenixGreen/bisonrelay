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

  // Ken, 2026-11-14: "write the lyrics directly on the lyric line, pressing
  // the spacebar or hyphen to move onto the next note".
  testWidgets("lyrics typed on the score: a hyphen or a space moves on",
      (tester) async {
    var c = await studio(tester);
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    var bar = scoreOf(c).parts[1].staves[0].bars[1]; // violin bar 2: B4 G4
    var paper = tester.getTopLeft(find.byKey(const ValueKey("scorePaper")));
    var under =
        state.staffPlace("vln", 0, 1, 0.0, "E4") as Offset; // its bottom line
    var at = paper +
        Offset((state.placeOf(bar[0].id) as Offset).dx,
            under.dy + 5.2 * 8 * state.scale);
    await tester.tapAt(at);
    await tester.tapAt(at);
    await tester.pump();
    var field = find.descendant(
        of: find.byKey(const ValueKey("scoreInline")),
        matching: find.byType(TextField));
    expect(field, findsOneWidget);
    await tester.enterText(field, "Hel-");
    await tester.pump();
    await tester.enterText(field, "lo ");
    await tester.pump();
    var s = scoreOf(c);
    expect(s.event(bar[0].id)!.lyrics, ["Hel-"]);
    expect(s.event(bar[1].id)!.lyrics, ["lo"]);
    // On to the next note after it, ready to type.
    expect(field, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field, findsNothing);
    await settled(tester);
  });

  // "double click on the chord line and type the chord".
  testWidgets("a chord typed on the score: double-click the chord line, or ⌘K",
      (tester) async {
    var c = await studio(tester);
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    var e = scoreOf(c).parts[1].staves[0].bars[2][1]; // violin bar 3 G4
    var paper = tester.getTopLeft(find.byKey(const ValueKey("scorePaper")));
    var top = state.staffPlace("vln", 0, 2, 0.0, "F5") as Offset; // top line
    var at = paper +
        Offset(
            (state.placeOf(e.id) as Offset).dx, top.dy - 2.5 * 8 * state.scale);
    await tester.tapAt(at);
    await tester.tapAt(at);
    await tester.pump();
    var field = find.descendant(
        of: find.byKey(const ValueKey("scoreInline")),
        matching: find.byType(TextField));
    await tester.enterText(field, "Am7");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.chord, "Am7");
    expect(field, findsNothing);
    // ⌘K on a note picked.
    var other = scoreOf(c).parts[1].staves[0].bars[3][0];
    await tapEvent(tester, c, other.id);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump();
    await tester.enterText(field, "D7");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(scoreOf(c).event(other.id)!.chord, "D7");
    await settled(tester);
  });

  testWidgets("a strum mark clicked turns the other way", (tester) async {
    var c = await studio(tester);
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    var e = scoreOf(c).parts[2].staves[0].bars[0][0];
    expect(e.strum, Strum.down);
    var paper = tester.getTopLeft(find.byKey(const ValueKey("scorePaper")));
    await tester
        .tapAt(paper + (state.markPlace(e.id, MarkKind.strum) as Offset));
    await tester.pump(const Duration(milliseconds: 400));
    expect(scoreOf(c).event(e.id)!.strum, Strum.up);
    await settled(tester);
  });

  // "redraw/resize and place the dynamic markings".
  testWidgets(
      "a dynamic picked: sized by its handle, changed by a double-click",
      (tester) async {
    var c = await studio(tester);
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    var e = scoreOf(c).parts[0].staves[0].bars[0][0]; // the mf
    var paper = tester.getTopLeft(find.byKey(const ValueKey("scorePaper")));
    await tester
        .tapAt(paper + (state.markPlace(e.id, MarkKind.dynamic) as Offset));
    await tester.pump(const Duration(milliseconds: 400));
    var handle = paper + (state.handlePlace(0) as Offset);
    var g = await tester.startGesture(handle);
    await g.moveBy(const Offset(12, 8));
    await g.moveBy(const Offset(12, 8));
    await g.up();
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.sizeOf(MarkKind.dynamic), greaterThan(1.2));
    c.undo();
    await tester.pump();
    expect(scoreOf(c).event(e.id)!.sizes, isEmpty, reason: "one step to undo");
    // Twice on it: the dynamics to choose another from.
    var at = paper + (state.markPlace(e.id, MarkKind.dynamic) as Offset);
    await tester.tapAt(at);
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("scoreDynamicMenu-pp")));
    await tester.pumpAndSettle();
    expect(scoreOf(c).event(e.id)!.dyn, Dynamic.pp);
    await settled(tester);
  });

  testWidgets("a hairpin picked: stretched by an end, moved by its body",
      (tester) async {
    var c = await studio(tester);
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    var paper = tester.getTopLeft(find.byKey(const ValueKey("scorePaper")));
    var pin =
        scoreOf(c).spanners.firstWhere((x) => x.kind == SpannerKind.crescendo);
    expect(pin.to, (bar: 2, at: 3.0));
    await tester
        .tapAt(paper + (state.markPlace(pin.id, MarkKind.hairpin) as Offset));
    await tester.pump(const Duration(milliseconds: 400));
    // Its end pulled back to the bar's second note.
    var second = scoreOf(c).parts[0].staves[0].bars[2][1];
    var end = paper + (state.handlePlace(1) as Offset);
    var to = paper + (state.placeOf(second.id) as Offset);
    var g = await tester.startGesture(end);
    await g.moveTo(Offset(to.dx, end.dy));
    await g.up();
    await tester.pump();
    pin = scoreOf(c).spanners.firstWhere((x) => x.id == pin.id);
    expect(pin.to, (bar: 2, at: 1.0));
    // Its body dragged down.
    var body = paper + (state.markPlace(pin.id, MarkKind.hairpin) as Offset);
    g = await tester.startGesture(body);
    await g.moveBy(const Offset(0, 10));
    await g.moveBy(const Offset(0, 10));
    await g.up();
    await tester.pump();
    pin = scoreOf(c).spanners.firstWhere((x) => x.id == pin.id);
    expect(pin.offset.dy, greaterThan(5));
    await settled(tester);
  });

  testWidgets("a key typed in a field is typed, not a Studio key",
      (tester) async {
    var c = await studio(tester);
    await tester.enterText(find.byKey(const ValueKey("scoreTitle")), "Song");
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    var state = tester.state(find.byType(ScoreStudio)) as dynamic;
    expect(state.input, isFalse, reason: "N in a field is not Note input");
    expect(c.scoreById("ode"), isNotNull);
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
