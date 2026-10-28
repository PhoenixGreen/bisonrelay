import 'dart:ui' show Canvas, PictureRecorder;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
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

  testWidgets("the bar picks among its views, and no others", (tester) async {
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
    expect(keys, [panelKey(0, 0), panelKey(90, 0), panelKey(-90, 0), panelKey(180, 0)],
        reason: "only the views it has: more are added in its Layers");
    views.onChanged(panelKey(180, 0));
    await tester.pumpAndSettle();
    expect(get().inView(get().pose).turn, 180);
    expect(tester.takeException(), isNull);
  });

  group("views of a pose", () {
    var wave = posePresets.firstWhere((p) => p.name == "Wave");
    CharacterElement waving(CharacterElement e) => e.copyWith(pose: wave.pose);
    var view = CharacterView(0, 0, pose: "Wave", posed: wave.pose);
    var dot = const VectorShape(paths: [
      VectorPath([VectorNode(60, 40), VectorNode(70, 40), VectorNode(70, 50)], closed: true)
    ], fill: Color(0xFFFF0000));

    test("drawn from when it is in that pose, from there", () {
      var e = _sketch().withView(view);
      expect(e.viewKey(e.pose), panelKey(0, 0), reason: "not waving");
      expect(e.viewKey(wave.pose), "0,0@Wave");
      expect(e.viewKey(wave.pose.withTurn(90)), panelKey(90, 0), reason: "no view of it side on");
      // Its own pose's drawing first; until there is one, its view's.
      var plain = CharacterDrawing(shapes: [dot], parts: const [CharacterPart.head]);
      e = e.withDrawing(0, 0, plain);
      expect(e.drawingAt("0,0@Wave").$1.shapes.length, 1);
      var own = e.withDrawingAt("0,0@Wave", CharacterDrawing.empty.copyWith(hidden: {CharacterRegion.head}));
      expect(own.drawingAt("0,0@Wave").$1.hidden, {CharacterRegion.head});
      expect(own.drawingAt(panelKey(0, 0)).$1.hidden, isEmpty);
      // Turned the other way: its mirror.
      var side = _sketch().withDrawingAt("90,0@Wave", plain);
      expect(side.drawingAt("-90,0@Wave").$2, isTrue);
      expect(oppositeKey("45,45@Wave"), "-45,45@Wave");
      expect(oppositeKey("180,0@Wave"), isNull);
      // Saved and loaded.
      var saved = elementFromJson(own.toJson()) as CharacterElement;
      expect(saved.views, contains(view));
      expect(saved.viewKey(wave.pose), "0,0@Wave");
    });

    test("drawn on in that pose, it shows in that pose alone", () async {
      var c = CanvasController(CanvasDocument(frames: 24)
          .addElement(waving(_sketch()).withView(view)));
      c.drawOnCharacter("c");
      c.replaceElement(c.editingVector!.copyWith(shapes: [dot]));
      var e = c.document.elementById("c") as CharacterElement;
      expect(e.drawings.keys, ["0,0@Wave"]);
      var standing = e.copyWith(pose: CharacterElement.restPose);
      expect(await _pixels(standing), await _pixels(_sketch()), reason: "standing: as made");
      expect(await _pixels(e), isNot(await _pixels(waving(_sketch()).withView(view))));
    });

    testWidgets("added from the Layers' views, in that pose; a view added there",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      CanvasSection.openAll = true;
      addTearDown(() => CanvasSection.openAll = false);
      var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(900, 14000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      tester.widget<CanvasDropdown<String?>>(find.byKey(const ValueKey("characterDrawingPoseView")))
          .onChanged("Wave");
      await tester.pumpAndSettle();
      var e = c.document.elementById("c") as CharacterElement;
      expect(e.views, contains(view));
      expect(e.viewKey(e.poseAtFrame(0)), "0,0@Wave", reason: "in the pose, seen from its view");
      // A view of an angle, added: turned to it.
      var add = tester.widget<CanvasDropdown<String>>(
          find.byKey(const ValueKey("characterViewAdd")));
      expect(add.options.map((o) => o.$1), isNot(contains(panelKey(0, 0))),
          reason: "only views it has not got");
      add.onChanged(panelKey(45, 0));
      await tester.pumpAndSettle();
      e = c.document.elementById("c") as CharacterElement;
      expect(e.views, contains(const CharacterView(45, 0)));
      expect(e.inView(e.poseAtFrame(0)).turn, 45);
      expect(tester.takeException(), isNull);
    });
  });
}
