import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/ui/character_guide.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_guide_test.dart is the puppet laid over a sketch to draw
// over: each of its handles moves the proportion it names, as far as it is
// dragged, and the change is the character's -- on every panel.

CharacterElement _sketch() => CharacterElement(
    const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
    dna: characterCast.first.dna);

void main() {
  for (var handle in GuideHandle.values) {
    test("${handle.label} goes where it is dragged", () {
      var e = _sketch();
      var placed = CharacterPlacement.of(e, 0);
      var at = placed.toPage(guidePoint(placed.rig, handle));
      // A little way, in whichever direction the handle moves.
      var probe = CharacterPlacement.of(
          withGuide(e, handle, guideValue(e, handle) + 0.1), 0);
      var way = probe.toPage(guidePoint(probe.rig, handle)) - at;
      expect(way.distance, greaterThan(0.05), reason: "it moves the figure");
      var to = at + way / way.distance * 1.5;
      var next = guided(e, handle, at, to, 0);
      expect(guideValue(next, handle), isNot(guideValue(e, handle)));
      var after = CharacterPlacement.of(next, 0);
      var landed = after.toPage(guidePoint(after.rig, handle));
      expect((landed - to).distance, lessThan(0.6),
          reason: "landed at $landed, not $to");
    });
  }

  test("a change on one panel is the character's on every one", () {
    var e = _sketch();
    var placed = CharacterPlacement.of(e, 0);
    var at = placed.toPage(guidePoint(placed.rig, GuideHandle.shoulders));
    var next = guided(e, GuideHandle.shoulders, at, at + const Offset(4, 0), 0);
    var turned = next.copyWith(pose: next.pose.withTurn(90));
    expect(turned.dna.look, next.dna.look);
    expect(next.dna.look[GuideHandle.shoulders.look!], greaterThan(0));
  });

  group("on the stage", () {
    Future<(CanvasController, Offset Function(Offset))> stage(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.showPuppet = true;
      tester.view.physicalSize = const Size(1600, 1200);
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
                body: CanvasStage(key: const ValueKey("stage"), controller: c))),
      ));
      await tester.pumpAndSettle();
      var view = tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      var page = view.pageRect;
      var scale = page.width / c.document.size.size.width;
      return (
        c,
        (Offset doc) =>
            tester.getTopLeft(find.byKey(const ValueKey("stage"))) +
            page.topLeft +
            doc * scale
      );
    }

    CharacterElement get(CanvasController c) =>
        c.document.elementById("c")! as CharacterElement;

    testWidgets("a handle dragged changes the proportion, in one undo", (tester) async {
      var (c, onScreen) = await stage(tester);
      var placed = CharacterPlacement.of(get(c), 0);
      var at = placed.toPage(guidePoint(placed.rig, GuideHandle.shoulders));
      await tester.dragFrom(onScreen(at), const Offset(12, 0));
      await tester.pumpAndSettle();
      expect(get(c).dna.look[GuideHandle.shoulders.look!], greaterThan(0.05));
      expect(get(c).bounds, _sketch().bounds, reason: "changed, not moved");
      c.undo();
      expect(get(c).dna.look[GuideHandle.shoulders.look!], 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets("hidden, it is not taken hold of", (tester) async {
      var (c, onScreen) = await stage(tester);
      c.showPuppet = false;
      await tester.pump();
      var placed = CharacterPlacement.of(get(c), 0);
      var at = placed.toPage(guidePoint(placed.rig, GuideHandle.headSize));
      await tester.dragFrom(onScreen(at), const Offset(10, -10));
      await tester.pumpAndSettle();
      expect(get(c).dna.headsTall, _sketch().dna.headsTall);
    });

    testWidgets("the pen draws across it; the points tool takes hold",
        (tester) async {
      var (c, onScreen) = await stage(tester);
      c.drawOnCharacter("c");
      c.vectorTool = VectorTool.pencil;
      await tester.pump();
      var placed = CharacterPlacement.of(get(c), 0);
      var at = placed.toPage(guidePoint(placed.rig, GuideHandle.hips));
      await tester.dragFrom(onScreen(at), const Offset(14, 6));
      await tester.pumpAndSettle();
      expect(get(c).dna.look[GuideHandle.hips.look!], 0, reason: "drawn, not changed");
      expect(get(c).drawingFor(0, 0).$1.shapes, isNotEmpty);

      c.vectorTool = VectorTool.select;
      await tester.pump();
      await tester.dragFrom(onScreen(at), const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(get(c).dna.look[GuideHandle.hips.look!], isNot(0));
      expect(c.drawingOn, "c", reason: "still drawing");
    });
  });
}
