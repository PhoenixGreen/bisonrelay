import 'dart:ui' show Canvas, PictureRecorder;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_views_test.dart is the views a sketch is drawn from:
// front, side and back to start, others added as wanted, and the nearest
// one -- or its mirror -- drawn however it turns.

CharacterElement _sketch({double turn = 0}) {
  var e = CharacterElement(
      const ElementBase(id: "c", x: 20, y: 20, width: 160, height: 340),
      dna: characterCast.first.dna);
  return e.copyWith(pose: e.pose.withTurn(turn));
}

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(200, 380);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  test("the nearest view, or its mirror", () {
    var start = CharacterView.start;
    expect(nearestView(start, 30, 0), (0.0, 0.0));
    expect(nearestView(start, -100, 0), (-90.0, 0.0), reason: "the side's mirror");
    expect(nearestView(start, 150, 0), (180.0, 0.0));
    expect(nearestView(start, 0, 40), (0.0, 0.0), reason: "only level views");
    var more = [...start, const CharacterView(45, 0), const CharacterView(0, 45)];
    expect(nearestView(more, 40, 0), (45.0, 0.0));
    expect(nearestView(more, -50, 0), (-45.0, 0.0));
    expect(nearestView(more, 0, 40), (0.0, 45.0));
    expect(CharacterView.of(-90, 3), CharacterView.side);
    expect(viewLabel(135, -45), "¾ back from below");
  });

  test("three views to start; more added, removed and kept", () {
    var e = _sketch();
    expect(e.views, CharacterView.start);
    var more = e.withView(const CharacterView(45, 0));
    expect(more.views, [CharacterView.front, const CharacterView(45, 0), CharacterView.side, CharacterView.back]);
    expect(more.withView(CharacterView.side, on: false).views.length, 3);
    var saved = elementFromJson(more.toJson()) as CharacterElement;
    expect(saved.views, more.views);
    // Never none.
    var one = e
        .withView(CharacterView.side, on: false)
        .withView(CharacterView.back, on: false)
        .withView(CharacterView.front, on: false);
    expect(one.views, [CharacterView.front]);
  });

  test("a character saved before views keeps every view drawn on", () {
    var json = _sketch().withDrawing(-135, 45, CharacterDrawing.empty.copyWith(
        hidden: {CharacterRegion.head})).toJson();
    (json["props"] as Map? ?? json).remove("views");
    json.remove("views");
    var back = elementFromJson(json) as CharacterElement;
    expect(back.views, containsAll([...CharacterView.start, const CharacterView(135, 45)]));
  });

  test("drawn from the views it has: turned three-quarters, the front", () async {
    var e = _sketch(turn: 40);
    expect(await _pixels(e), await _pixels(_sketch(turn: 0)));
    var three = e.withView(const CharacterView(45, 0));
    expect(await _pixels(three), isNot(await _pixels(_sketch(turn: 0))));
    // Turned the other way: the mirror of the side.
    expect(await _pixels(_sketch(turn: -95)), await _pixels(_sketch(turn: -90)));
  });

  test("drawn on, it goes on the view it is seen from", () {
    var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch(turn: 30)));
    c.drawOnCharacter("c");
    var dot = const VectorShape(paths: [
      VectorPath([VectorNode(80, 60), VectorNode(84, 60), VectorNode(84, 64)], closed: true)
    ], fill: Color(0xFFFF0000));
    c.replaceElement(c.editingVector!.copyWith(shapes: [dot]));
    var e = c.document.elementById("c") as CharacterElement;
    expect(e.drawings.keys, [panelKey(0, 0)]);
  });

  testWidgets("the bar picks a view, or adds one", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
    addTearDown(c.dispose);
    c.selectOnly("c");
    tester.view.physicalSize = const Size(1600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: CharacterDrawBar(controller: c))),
    ));
    await tester.pumpAndSettle();
    CharacterElement get() => c.document.elementById("c") as CharacterElement;
    var views = tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("characterDrawPanel")));
    var keys = views.options.map((o) => o.$1).toList();
    expect(keys.take(4), [panelKey(0, 0), panelKey(90, 0), panelKey(-90, 0), panelKey(180, 0)]);
    expect(keys, contains("add:${panelKey(45, 0)}"));
    views.onChanged("add:${panelKey(45, 0)}");
    await tester.pumpAndSettle();
    expect(get().views, contains(const CharacterView(45, 0)));
    expect(get().inView(get().pose).turn, 45);
    expect(tester.takeException(), isNull);
  });
}
