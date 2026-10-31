import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_garment_drawing_test.dart is clothing drawn by hand on a
// sketch: a garment knows the parts of the body it covers, what is drawn on
// it goes on the one of those under it and is worn -- it moves with the
// body -- and a garment can be only what is drawn on it.

VectorShape _dot(Offset at, {Color colour = const Color(0xFF20C040)}) => VectorShape(
      paths: [
        VectorPath([
          for (var (dx, dy) in [(-4.0, -4.0), (4.0, -4.0), (4.0, 4.0), (-4.0, 4.0)])
            VectorNode(at.dx + dx, at.dy + dy),
        ], closed: true),
      ],
      fill: colour,
    );

CharacterElement _sketch({List<Garment>? wardrobe}) {
  var dna = characterCast.first.dna;
  return CharacterElement(
      const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
      dna: wardrobe == null ? dna : dna.copyWith(wardrobe: wardrobe));
}

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(400, 420);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  test("each garment covers its own parts of the body", () {
    expect(GarmentKind.trainers.covers,
        containsAll([CharacterPart.footL, CharacterPart.footR]));
    expect(GarmentKind.trainers.covers, isNot(contains(CharacterPart.torso)));
    expect(GarmentKind.cap.covers, {CharacterPart.head});
    expect(GarmentKind.tee.covers, contains(CharacterPart.upperArmL));
    expect(GarmentKind.jeans.covers, isNot(contains(CharacterPart.footL)));
    for (var k in GarmentKind.values) {
      expect(k.covers, isNotEmpty, reason: k.label);
    }
  });

  test("what is drawn goes on the part it covers nearest, not any part", () {
    var e = _sketch();
    var (rig, _, _) = drawnRig(e, 0, 24);
    // Over the knee: a leg's, on its own; a shoe's, the shin.
    var knee = rig.kneeL;
    expect(partAt(rig, knee), anyOf(CharacterPart.thighL, CharacterPart.shinL));
    expect(partAt(rig, knee, among: GarmentKind.trainers.covers), CharacterPart.shinL);
    // A hat drawn above the head goes on the head.
    expect(partAt(rig, rig.headCentre - Offset(0, rig.unit),
            among: GarmentKind.cap.covers),
        CharacterPart.head);
  });

  test("drawn on a garment through the drawing laid over it", () {
    var e = _sketch();
    var shoes = e.dna.wardrobe.indexWhere((g) => g.kind.slot == GarmentSlot.feet);
    expect(shoes, greaterThanOrEqualTo(0), reason: "the cast member wears shoes");
    var c = CanvasController(CanvasDocument(frames: 24).addElement(e));
    c.drawOnCharacter("c", garment: shoes);
    expect(c.drawingGarment, shoes);
    var (rig, _, _) = drawnRig(e, 0, 24);
    c.replaceElement(c.editingVector!.copyWith(shapes: [_dot(rig.ankleR)]));
    var after = c.document.elementById("c") as CharacterElement;
    var (d, _) = after.dna.wardrobe[shoes].drawingFor(0, 0);
    expect(d.parts.single, anyOf(CharacterPart.footR, CharacterPart.shinR));
    expect(after.drawings, isEmpty, reason: "on the shoes, not the character");
    // Seen from the other side, mirrored; saved and loaded, kept.
    expect(after.dna.wardrobe[shoes].drawingFor(0, 0).$2, isFalse);
    var saved = elementFromJson(after.toJson()) as CharacterElement;
    expect(saved.dna.wardrobe[shoes].drawings.keys, ["0,0"]);
    // Put down, the character is picked again.
    c.stopDrawingOnCharacter();
    expect(c.drawingGarment, isNull);
    expect(c.selection, {"c"});
  });

  test("worn: what is drawn on a shoe goes with the foot", () {
    var e = _sketch();
    var shoes = e.dna.wardrobe.indexWhere((g) => g.kind.slot == GarmentSlot.feet);
    var (rig, _, _) = drawnRig(e, 0, 24);
    var on = rig.ankleL + Offset(0, rig.unit * 0.1);
    var drawn = shapesOnParts([_dot(on)], rig, among: GarmentKind.trainers.covers);
    var lifted = e.copyWith(pose: e.pose.withAngle(CharacterBone.thighL, -60));
    var (r2, _, _) = drawnRig(lifted, 0, 24);
    var moved = shapeCentre(drawingOnPage(drawn, partFrames(r2)).single);
    expect((moved - on).distance, greaterThan(rig.unit * 0.3), reason: "lifted with the leg");
    expect(shoes, greaterThanOrEqualTo(0));
  });

  test("only what is drawn leaves its own drawing out", () async {
    var e = _sketch();
    var shoes = e.dna.wardrobe.indexWhere((g) => g.kind.slot == GarmentSlot.feet);
    var bare = [...e.dna.wardrobe]..removeAt(shoes);
    var drawnOnly = [...e.dna.wardrobe];
    drawnOnly[shoes] = drawnOnly[shoes].copyWith(drawnOnly: true);
    expect(await _pixels(_sketch(wardrobe: drawnOnly)),
        await _pixels(_sketch(wardrobe: bare)));
    // With something drawn on it, that is what is worn.
    var (rig, _, _) = drawnRig(e, 0, 24);
    drawnOnly[shoes] = drawnOnly[shoes].withDrawing(
        0, 0, shapesOnParts([_dot(rig.ankleL)], rig, among: GarmentKind.trainers.covers));
    expect(await _pixels(_sketch(wardrobe: drawnOnly)),
        isNot(await _pixels(_sketch(wardrobe: bare))));
  });

  test("a top drawn by hand is worn under an arm held across it", () async {
    var e = _sketch();
    var top = e.dna.wardrobe.indexWhere((g) => g.kind.slot == GarmentSlot.top);
    expect(top, greaterThanOrEqualTo(0), reason: "the cast member wears a top");
    // The right forearm brought across the chest, in front of it.
    var posed = e.copyWith(pose: e.pose.withAngle(CharacterBone.foreArmR, 100));
    var (rig, _, _) = drawnRig(posed, 0, 24);
    var arm = Offset.lerp(rig.elbowR, rig.wristR, 0.5)!;
    // A patch drawn on the chest, under where the forearm crosses.
    var patch = VectorShape(
      paths: [
        VectorPath([
          for (var (dx, dy) in [(-30.0, -30.0), (30.0, -30.0), (30.0, 30.0), (-30.0, 30.0)])
            VectorNode(arm.dx + dx, arm.dy + dy),
        ], closed: true),
      ],
      fill: const Color(0xFF20C040),
    );
    var drawn = shapesOnParts([patch], rig, among: e.dna.wardrobe[top].kind.covers);
    expect(drawn.parts.single, CharacterPart.torso);
    var wardrobe = [...e.dna.wardrobe];
    wardrobe[top] = wardrobe[top].withDrawing(0, 0, drawn);
    var worn = posed.copyWith(dna: posed.dna.copyWith(wardrobe: wardrobe));
    var px = await _pixels(worn);
    // The rig is the character's own; the page has it where it is put.
    var onPage = arm + Offset(e.x, e.y);
    var i = (onPage.dy.round() * 400 + onPage.dx.round()) * 4;
    var green = px[i] == 0x20 && px[i + 1] == 0xC0 && px[i + 2] == 0x40;
    expect(green, isFalse, reason: "the forearm over the patch, not under it");
    // Under the arm, on the chest, the patch shows.
    var j = ((onPage.dy + 24).round() * 400 + onPage.dx.round()) * 4;
    expect((px[j], px[j + 1], px[j + 2]), (0x20, 0xC0, 0x40));
  });

  group("the wardrobe", () {
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

    testWidgets("New, drawn by hand puts one on and draws it on the canvas",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();

      var slot = tester.widget<CanvasDropdown<GarmentSlot>>(
          find.byKey(const ValueKey("characterSlot")));
      slot.onChanged(GarmentSlot.feet);
      await tester.pumpAndSettle();
      var button = find.byKey(const ValueKey("characterGarmentNew"));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      var e = c.document.elementById("c") as CharacterElement;
      var mine = e.dna.wardrobe.indexWhere((g) => g.name == "My shoes");
      expect(mine, greaterThanOrEqualTo(0));
      expect(e.dna.wardrobe[mine].drawnOnly, isTrue);
      expect(e.dna.wardrobe.where((g) => g.kind.slot == GarmentSlot.feet).length, 1,
          reason: "in place of the shoes worn");
      expect(c.drawingOn, "c");
      expect(c.drawingGarment, mine);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("characterDrawGarment")),
              matching: find.text("My shoes")),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
