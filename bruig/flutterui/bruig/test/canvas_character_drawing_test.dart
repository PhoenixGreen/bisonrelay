import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_character_drawing_test.dart is what is drawn by hand on a
// sketched character: kept on the part of the body it was drawn on, moving
// with it when posed, mirrored onto the other side's panel, kept in the
// saved canvas, and taking the generated drawing's place where asked.

const _box = Rect.fromLTWH(0, 0, 160, 340);

/// _dot is a small square drawn at [at] on the page.
VectorShape _dot(Offset at, {Color colour = const Color(0xFFD02020)}) =>
    VectorShape(
      paths: [
        VectorPath([
          for (var (dx, dy) in [
            (-3.0, -3.0),
            (3.0, -3.0),
            (3.0, 3.0),
            (-3.0, 3.0)
          ])
            VectorNode(at.dx + dx, at.dy + dy),
        ], closed: true),
      ],
      fill: colour,
    );

Future<List<int>> _pixels(CharacterDna dna, CharacterPose pose,
    {CharacterDrawing? drawing}) async {
  var rec = PictureRecorder();
  paintCharacterFigure(Canvas(rec), _box, dna, pose, drawing: drawing);
  var img = await rec.endRecording().toImage(160, 340);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  var dna = characterCast.first.dna;
  var rest = CharacterElement.restPose;

  test("a shape drawn on the forearm is kept on it", () {
    var rig = CharacterRig.of(dna, rest, _box);
    var on = Offset.lerp(rig.elbowR, rig.wristR, 0.5)!;
    var drawn = shapesOnParts([_dot(on)], rig);
    expect(drawn.parts.single, CharacterPart.foreArmR);
    // Drawn back where it was, unposed.
    var back = drawingOnPage(drawn, partFrames(rig)).single;
    expect((shapeCentre(back) - on).distance, lessThan(0.01));
  });

  test("and moves with it when the arm is raised", () {
    var rig = CharacterRig.of(dna, rest, _box);
    var on = Offset.lerp(rig.elbowR, rig.wristR, 0.5)!;
    var drawn = shapesOnParts([_dot(on)], rig);
    var raised = CharacterRig.of(
        dna, rest.withAngle(CharacterBone.upperArmR, -120), _box);
    var moved = shapeCentre(drawingOnPage(drawn, partFrames(raised)).single);
    var forearm = Offset.lerp(raised.elbowR, raised.wristR, 0.5)!;
    expect((moved - forearm).distance, lessThan(1),
        reason: "still mid-forearm");
    expect(moved.dy, lessThan(on.dy - 20), reason: "carried up with the arm");
  });

  test("a panel seen from the other side is its mirror until drawn", () {
    var e = CharacterElement(
        const ElementBase(id: "c", width: 160, height: 340),
        dna: dna);
    var rig = CharacterRig.of(dna, rest.withTurn(45), _box);
    var hand = Offset.lerp(rig.elbowL, rig.wristL, 0.5)!;
    var drawn = shapesOnParts([_dot(hand)], rig);
    e = e.withDrawing(45, 0, drawn);
    var (own, mirrored) = e.drawingFor(45, 0);
    expect(mirrored, isFalse);
    expect(own.parts, drawn.parts);
    var (other, isMirror) = e.drawingFor(-45, 0);
    expect(isMirror, isTrue);
    expect(other.parts.single, drawn.parts.single.mirrored);
    expect(e.drawingFor(0, 0).$1.isEmpty, isTrue, reason: "the front has none");
    // Drawn itself, it is its own.
    e = e.withDrawing(-45, 0,
        CharacterDrawing.empty.copyWith(hidden: {CharacterRegion.head}));
    expect(e.drawingFor(-45, 0).$2, isFalse);
  });

  test("is kept in the saved canvas", () {
    var rig = CharacterRig.of(dna, rest, _box);
    var drawn = shapesOnParts([_dot(rig.headCentre)], rig,
        hidden: {CharacterRegion.armL});
    var e = CharacterElement(
            const ElementBase(id: "c", width: 160, height: 340),
            dna: dna)
        .withDrawing(0, 0, drawn);
    var back = elementFromJson(e.toJson()) as CharacterElement;
    var (d, _) = back.drawingFor(0, 0);
    expect(d.parts, [CharacterPart.head]);
    expect(d.hidden, {CharacterRegion.armL});
    expect(d.shapes.single.paths.single.nodes.length, 4);
  });

  test("drawn over the sketch, and where asked, in place of it", () async {
    var plain = await _pixels(dna, rest);
    var rig = CharacterRig.of(dna, rest, _box);
    var drawn = shapesOnParts([_dot(rig.chest + const Offset(0, 30))], rig);
    var over = await _pixels(dna, rest, drawing: drawn);
    expect(over, isNot(plain), reason: "the shape is drawn");
    var noArm = await _pixels(dna, rest,
        drawing:
            CharacterDrawing.empty.copyWith(hidden: {CharacterRegion.armR}));
    expect(noArm, isNot(plain), reason: "the right arm is left out");
  });

  group("drawn on the canvas", () {
    CharacterElement sketch() => CharacterElement(
        const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
        dna: dna);

    test("through a drawing laid over it, kept in the character", () {
      var c = CanvasController(CanvasDocument(frames: 24).addElement(sketch()));
      c.drawOnCharacter("c");
      expect(c.drawingOn, "c");
      var proxy = c.editingVector!;
      expect(proxy.id, drawingProxyId("c"));
      expect(c.document.indexOf(proxy.id), c.document.indexOf("c") + 1,
          reason: "laid just over it");
      expect(proxy.shapes, isEmpty);

      var (rig, _, _) =
          drawnRig(c.document.elementById("c") as CharacterElement, 0, 24);
      var on = rig.headCentre;
      c.replaceElement(proxy.copyWith(shapes: [_dot(on)]));
      var e = c.document.elementById("c") as CharacterElement;
      var (d, mirrored) = e.drawingFor(0, 0);
      expect(mirrored, isFalse);
      expect(d.parts, [CharacterPart.head]);

      // Put down: the stand-in goes, what was drawn stays.
      c.stopDrawingOnCharacter();
      expect(c.drawingOn, isNull);
      expect(c.document.elementById(drawingProxyId("c")), isNull);
      expect(c.selection, {"c"});
      expect(
          (c.document.elementById("c") as CharacterElement)
              .drawingFor(0, 0)
              .$1
              .parts,
          [CharacterPart.head]);
    });

    test("is undone stroke by stroke, and never saved", () {
      var c = CanvasController(CanvasDocument(frames: 24).addElement(sketch()));
      c.drawOnCharacter("c");
      var proxy = c.editingVector!;
      var (rig, _, _) = drawnRig(sketch(), 0, 24);
      c.replaceElement(proxy.copyWith(shapes: [_dot(rig.chest)]));
      var saved = c.document.toJson();
      expect([for (var e in saved["elements"] as List) e["id"]], ["c"]);
      c.undo();
      expect(
          (c.document.elementById("c") as CharacterElement).drawings, isEmpty);
    });

    test("turned to another panel, it shows that panel's drawing", () {
      var c = CanvasController(CanvasDocument(frames: 24).addElement(sketch()));
      c.drawOnCharacter("c");
      var (rig, _, _) = drawnRig(sketch(), 0, 24);
      c.replaceElement(c.editingVector!.copyWith(shapes: [_dot(rig.chest)]));
      var e = c.document.elementById("c") as CharacterElement;
      c.replaceElement(e.copyWith(pose: e.pose.withTurn(90)));
      expect(c.drawingOn, "c");
      expect(c.editingVector!.shapes, isEmpty,
          reason: "the side has nothing drawn");
    });

    test("not a 3D body", () {
      var c = CanvasController(CanvasDocument(frames: 24).addElement(sketch()
          .copyWith(body: const CharacterBody(kind: BodyKind.mannequin))));
      c.drawOnCharacter("c");
      expect(c.drawingOn, isNull);
    });
  });

  group("the bar and the Drawing section", () {
    Widget host(CanvasController c) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: Column(children: [
            CharacterDrawBar(controller: c),
            Expanded(child: SizedBox(width: 420, child: CanvasDesignPanel(controller: c))),
          ]))),
        );

    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    testWidgets("a tool on the bar draws on the character; again puts it down",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(CharacterElement(
          const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
          dna: dna)));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey("characterDrawBar")), findsOneWidget);
      expect(find.byKey(const ValueKey("elementSection-drawing")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("characterDrawTool-pencil")));
      await tester.pumpAndSettle();
      expect(c.drawingOn, "c");
      expect(c.vectorTool, VectorTool.pencil);
      // The character's own settings are still shown, the tools in them.
      expect(find.byKey(const ValueKey("elementSection-drawing")), findsOneWidget);
      expect(find.byKey(const ValueKey("vectorTools")), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey("characterDrawTool-pencil")));
      await tester.pumpAndSettle();
      expect(c.drawingOn, isNull);
      expect(c.selection, {"c"});
    });

    testWidgets("a narrow canvas takes the bar onto two lines, not past its edge",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(CharacterElement(
          const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
          dna: dna)));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(520, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      var bar = tester.getRect(find.byKey(const ValueKey("characterDrawBar")));
      expect(bar.right, lessThanOrEqualTo(520));
      for (var tool in drawBarTools) {
        var r = tester.getRect(find.byKey(ValueKey("characterDrawTool-${tool.name}")));
        expect(bar.contains(r.center), isTrue, reason: "${tool.name} is on the bar");
      }
      await tester.tap(find.byKey(const ValueKey("characterDrawPuppet")));
      await tester.pump();
      expect(c.showPuppet, isTrue);
    });

    testWidgets("a region hidden on one panel only", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(CharacterElement(
          const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
          dna: dna)));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      var f = find.byKey(const ValueKey("characterDrawingHide-head"));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
      var e = c.document.elementById("c") as CharacterElement;
      expect(e.drawingFor(0, 0).$1.hidden, {CharacterRegion.head});
      expect(e.drawingFor(90, 0).$1.hidden, isEmpty);
    });

    testWidgets("zoom onto the head", (tester) async {
      var c = CanvasController(CanvasDocument(frames: 24).addElement(CharacterElement(
          const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
          dna: dna)));
      addTearDown(c.dispose);
      c.zoomToCharacter("c", CharacterZoom.head);
      var head = c.zoom;
      c.zoomToCharacter("c", CharacterZoom.fullBody);
      expect(head, greaterThan(c.zoom * 2));
    });
  });

  test("what is drawn through the stand-in is painted where it was drawn", () async {
    var c = CanvasController(CanvasDocument(frames: 24).addElement(CharacterElement(
        const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
        dna: dna)));
    c.drawOnCharacter("c");
    var (rig, _, _) = drawnRig(c.document.elementById("c") as CharacterElement, 0, 24);
    // Beside the hip, out on the page, in the stand-in's own measure.
    var at = rig.hips + Offset(rig.unit * 1.6, 0);
    c.replaceElement(c.editingVector!.copyWith(
        shapes: [_dot(at, colour: const Color(0xFF00FF00))]));
    c.stopDrawingOnCharacter();
    var rec = PictureRecorder();
    paintElement(Canvas(rec), c.document.elementById("c")!, 0);
    var img = await rec.endRecording().toImage(400, 420);
    var px = (await img.toByteData())!.buffer.asUint8List();
    int green(Offset p) {
      var i = (p.dy.round() * 400 + p.dx.round()) * 4;
      return px[i + 1] - px[i];
    }

    var page = at + const Offset(100, 40);
    expect(green(page), greaterThan(200), reason: "drawn at $page");
  });
}
