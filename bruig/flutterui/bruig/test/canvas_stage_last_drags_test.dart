import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_gizmo.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_stage_last_drags_test.dart is a drag on the stage, as the person
// doing it sees it, for the kinds that work on something other than an
// element's box: a reused element's copies moved, sized or turned on their
// own; a 3D stage's camera orbited or panned (Option held, or the page
// locked); parallax scenery panned; the 3D gizmo; and a Sprite or Tile map
// painted. Each is held as let go (what it did, and the one undo step it
// makes), as cancelled by the system (what it did is kept, the step closed,
// no click made), and, where a click rides on the press, as a still press.
// The pointer's look while each is under way is held too.

const _viewport = Size(1280, 800);

void main() {
  /// pump shows [controller] on a stage and hands back its state.
  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller) async {
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(key: key, controller: controller))));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  /// cursor is the pointer's look over the stage's page.
  MouseCursor cursor(WidgetTester tester) => tester
      .widgetList<MouseRegion>(find.descendant(
          of: find.byType(CanvasStage), matching: find.byType(MouseRegion)))
      .firstWhere((m) => m.child is ClipRect)
      .cursor;

  /// drag presses at [from] and takes the pointer [by] on the stage, in two
  /// steps, then lets go there or, with [cancel], has the system take it.
  /// [during] is called with the pointer still down, after the last step.
  Future<void> drag(WidgetTester tester, Offset from, Offset by,
      {bool cancel = false,
      int buttons = kPrimaryButton,
      void Function()? during}) async {
    var g = await tester.startGesture(from,
        buttons: buttons, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(by / 2);
    await tester.pump();
    await g.moveBy(by / 2);
    await tester.pump();
    during?.call();
    if (cancel) {
      await g.cancel();
    } else {
      await g.up();
    }
    await tester.pumpAndSettle();
  }

  /// press presses at [at] and lets go there or, with [cancel], has the
  /// system take the pointer before it has moved.
  Future<void> press(WidgetTester tester, Offset at,
          {bool cancel = false, int buttons = kPrimaryButton}) =>
      drag(tester, at, Offset.zero, cancel: cancel, buttons: buttons);

  /// withKey runs [body] with [key] held.
  Future<void> withKey(WidgetTester tester, LogicalKeyboardKey key,
      Future<void> Function() body) async {
    await tester.sendKeyDownEvent(key);
    await body();
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  /// settled is that nothing of the last press is left: no gesture under
  /// way and no undo step open.
  void settled(CanvasStageState stage, CanvasController c, String how) {
    expect(stage.gestureUnderWay, isFalse, reason: "$how: no gesture left");
    expect(c.interacting, isFalse, reason: "$how: no undo step left open");
  }

  /// underWay is that the press has begun a gesture and, if [opens], an
  /// undo step.
  void underWay(CanvasStageState stage, CanvasController c, bool opens) {
    expect(stage.gestureUnderWay, isTrue, reason: "a gesture under way");
    expect(c.interacting, opens, reason: "an undo step open: $opens");
  }

  group("a reused element's copies", () {
    CanvasController copies() => CanvasController(
        const CanvasDocument(frames: 240, frameRate: 24, elements: [
          ShapeElement(
              ElementBase(
                  id: "a",
                  x: 100,
                  y: 100,
                  width: 100,
                  height: 100,
                  motion: ElementMotion(
                      instances: InstanceSet(items: [
                    ElementInstance("i0"),
                    ElementInstance("i1", dx: 250),
                    ElementInstance("i2", dx: 500),
                  ]))),
              fill: Color(0xFF000000)),
        ]),
        audioEngine: FakeEngine(const {}));

    // The copies' middles: 150,150 · 400,150 · 650,150.
    Offset copy(int i) => Offset(150 + 250.0 * i, 150);
    InstanceSet set(CanvasController c) => c.motionOf("a").instances!;

    for (var cancel in [false, true]) {
      var how = cancel ? "cancelled" : "let go";
      testWidgets("a picked copy dragged, $how: it alone moves, one step",
          (tester) async {
        var c = copies();
        addTearDown(c.dispose);
        c.pickCopy("a", "i1");
        var stage = await pump(tester, c);
        var at = stage.toStagePoint(copy(1));
        var by = stage.toStagePoint(copy(1) + const Offset(0, 40)) - at;
        await drag(tester, at, by, cancel: cancel, during: () {
          underWay(stage, c, true);
          expect(cursor(tester), SystemMouseCursors.basic);
        });
        expect(set(c).items[1].dy, closeTo(40, 0.5), reason: "it moved");
        expect(set(c).items[0].dy, 0);
        expect(c.document.elementById("a")!.y, 100);
        settled(stage, c, how);
        c.undo();
        expect(set(c).items[1].dy, 0, reason: "one undo puts it back");
        expect(c.canUndo, isFalse, reason: "and it was one step");
      });

      testWidgets("Alt-drag on a copy, $how: a new copy moved, one step",
          (tester) async {
        var c = copies();
        addTearDown(c.dispose);
        c.pickCopy("a", "i2");
        var stage = await pump(tester, c);
        var at = stage.toStagePoint(copy(2));
        var by = stage.toStagePoint(copy(2) + const Offset(0, 50)) - at;
        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          await drag(tester, at, by, cancel: cancel, during: () {
            underWay(stage, c, true);
            expect(cursor(tester), SystemMouseCursors.basic);
          });
        });
        expect(set(c).count, 4);
        expect(set(c).items.last.dx, 500);
        expect(set(c).items.last.dy, closeTo(50, 0.5));
        expect(set(c).items[2].dy, 0, reason: "the one dragged from stays");
        expect(c.pickedCopiesOf("a"), {set(c).items.last.id});
        settled(stage, c, how);
        c.undo();
        expect(set(c).count, 3, reason: "one undo takes the new copy away");
        expect(c.canUndo, isFalse);
      });
    }

    testWidgets("a picked copy pressed and let go: nothing moves, no step",
        (tester) async {
      var c = copies();
      addTearDown(c.dispose);
      c.pickCopy("a", "i1");
      var stage = await pump(tester, c);
      await press(tester, stage.toStagePoint(copy(1)));
      expect(set(c).items.map((x) => x.dy), [0, 0, 0]);
      expect(c.pickedCopiesOf("a"), {"i1"});
      settled(stage, c, "clicked");
      expect(c.canUndo, isFalse);
      await press(tester, stage.toStagePoint(copy(1)), cancel: true);
      settled(stage, c, "cancelled");
      expect(c.canUndo, isFalse);
    });

    testWidgets("Alt and a still press: no copy made, no step", (tester) async {
      // The copy is made as the press travels, so a press that never does
      // leaves the copies as they were.
      var c = copies();
      addTearDown(c.dispose);
      c.pickCopy("a", "i1");
      var stage = await pump(tester, c);
      await withKey(tester, LogicalKeyboardKey.altLeft, () async {
        await press(tester, stage.toStagePoint(copy(1)));
        await press(tester, stage.toStagePoint(copy(1)), cancel: true);
      });
      expect(set(c).count, 3);
      expect(c.pickedCopiesOf("a"), {"i1"});
      settled(stage, c, "clicked");
      expect(c.canUndo, isFalse);
    });

    // The one copy picked has a box of its own: its corner sizes it, its
    // ring turns it, by its own values, not the element's.
    final boxes = <(
      String,
      StageHandle,
      Offset Function(CanvasStageState),
      bool Function(InstanceSet)
    )>[
      (
        "sized",
        StageHandle.bottomRight,
        (s) =>
            s.toStagePoint(const Offset(450, 200) + const Offset(50, 50)) -
            s.toStagePoint(const Offset(450, 200)),
        (set) => set.sizeOf(1) > 1.5,
      ),
      (
        "turned",
        StageHandle.rotate,
        (s) {
          var mid = s.toStagePoint(copy(1));
          var ring = s.handleAt(StageHandle.rotate);
          return mid + Offset((ring - mid).distance, 0) - ring;
        },
        (set) => set.turnOf(1) > 45,
      ),
    ];
    for (var (what, handle, by, changed) in boxes) {
      for (var cancel in [false, true]) {
        var how = cancel ? "cancelled" : "let go";
        testWidgets("the one picked copy $what, $how: one step",
            (tester) async {
          var c = copies();
          addTearDown(c.dispose);
          c.pickCopy("a", "i1");
          var stage = await pump(tester, c);
          await drag(tester, stage.handleAt(handle), by(stage), cancel: cancel,
              during: () {
            underWay(stage, c, true);
            expect(cursor(tester), SystemMouseCursors.basic);
          });
          expect(changed(set(c)), isTrue, reason: "it was $what");
          expect((set(c).sizeOf(0), set(c).turnOf(0)), (1, 0),
              reason: "the others keep theirs");
          expect(c.document.elementById("a")!.bounds,
              const Rect.fromLTWH(100, 100, 100, 100));
          settled(stage, c, how);
          c.undo();
          expect((set(c).sizeOf(1), set(c).turnOf(1)), (1, 0));
          expect(c.canUndo, isFalse);
        });
      }
    }

    testWidgets("a Code panel's copy: its code clicked, dragged, cancelled",
        (tester) async {
      // The panel is made by a lesson, then given copies, before the stage
      // and its undo history see it.
      var made = CanvasController(
          const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine(const {}));
      made.addCodeLesson(
          starter: codeStarters.firstWhere((s) => s.key == "web"));
      var panel = made.document.elements.whereType<CodeElement>().single;
      var reused = panel.rebase(panel.base.copyWith(
          motion: const ElementMotion(
              instances: InstanceSet(items: [
        ElementInstance("i0"),
        ElementInstance("i1", dy: 2000),
      ]))));
      var doc = made.document.withElement(reused);
      made.dispose();
      var c = CanvasController(doc, audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      CodeElement code() => c.document.elements.whereType<CodeElement>().single;
      var id = code().id;
      c.pickCopy(id, "i0");
      var stage = await pump(tester, c);
      expect(c.canUndo, isFalse);
      var start = code().x;
      var at = stage
          .toStagePoint(codeBoxes(code(), code().bounds).panes[0].code.center);
      InstanceSet copiesNow() => c.motionOf(id).instances!;

      await drag(tester, at, const Offset(60, 0),
          during: () => underWay(stage, c, true));
      expect(c.codeEditing, isNull, reason: "dragged, no typing");
      expect(copiesNow().items[0].dx, greaterThan(0), reason: "the copy moved");
      expect(code().x, start, reason: "the panel itself stays");
      settled(stage, c, "dragged");
      c.undo();
      expect(copiesNow().items[0].dx, 0);

      await press(tester, at, cancel: true);
      expect(c.codeEditing, isNull, reason: "cancelled, no typing");
      settled(stage, c, "cancelled");
      expect(c.canUndo, isFalse);

      await press(tester, at);
      expect(c.codeEditing, (id, 0), reason: "clicked, open for typing");
      expect(copiesNow().items[0].dx, 0);
      expect(stage.gestureUnderWay, isFalse);
      expect(c.canUndo, isFalse);
    });
  });

  group("a 3D stage's camera", () {
    CanvasController onStage() => CanvasController(const CanvasDocument()
        .addElement(BackgroundElement(
            ElementBase(id: "st", x: 0, y: 0, width: 1280, height: 720),
            backdrop: BackdropKind.stage,
            stage: StageElement(ElementBase(id: ""))))
        .addElement(const ShapeElement(ElementBase(
            id: "a",
            name: "a",
            x: 100,
            y: 50,
            width: 200,
            height: 400,
            spot: StageSpot("st")))));
    StageCamera camera(CanvasController c) =>
        c.stageOf("st")!.cameraAt(c.frame);
    // A corner of the stage nothing stands on.
    Offset corner(CanvasStageState s) =>
        s.toStagePoint(const Offset(1200, 650));

    for (var cancel in [false, true]) {
      var how = cancel ? "cancelled" : "let go";
      testWidgets("locked, a drag orbits, $how: one step, still selected",
          (tester) async {
        var c = onStage();
        addTearDown(c.dispose);
        c.selectOnly("a");
        var stage = await pump(tester, c);
        c.pageLocked = true;
        await tester.pump();
        var was = camera(c);
        await drag(tester, corner(stage), const Offset(-80, 0), cancel: cancel,
            during: () {
          underWay(stage, c, true);
          expect(cursor(tester), SystemMouseCursors.grabbing);
        });
        expect(camera(c).yaw, isNot(closeTo(was.yaw, 0.1)));
        expect(c.selection, {"a"}, reason: "a drag is not a click");
        settled(stage, c, how);
        c.undo();
        expect(camera(c).yaw, was.yaw);
        expect(c.canUndo, isFalse);
      });

      testWidgets("locked, a shifted drag pans, $how: one step",
          (tester) async {
        var c = onStage();
        addTearDown(c.dispose);
        c.selectOnly("a");
        var stage = await pump(tester, c);
        c.pageLocked = true;
        await tester.pump();
        await withKey(tester, LogicalKeyboardKey.shiftLeft, () async {
          await drag(tester, corner(stage), const Offset(40, 0), cancel: cancel,
              during: () {
            underWay(stage, c, true);
            expect(cursor(tester), SystemMouseCursors.grabbing);
          });
        });
        expect(camera(c).tx, isNot(0));
        expect(c.selection, {"a"});
        settled(stage, c, how);
        c.undo();
        expect(camera(c).tx, 0);
        expect(c.canUndo, isFalse);
      });

      testWidgets("Option-drag on the stage orbits, $how: one step",
          (tester) async {
        var c = onStage();
        addTearDown(c.dispose);
        c.selectOnly("a");
        var stage = await pump(tester, c);
        var was = camera(c);
        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          await drag(tester, corner(stage), const Offset(-80, 30),
              cancel: cancel, during: () {
            underWay(stage, c, true);
            expect(cursor(tester), SystemMouseCursors.grabbing);
          });
        });
        expect(camera(c).yaw, isNot(closeTo(was.yaw, 0.1)));
        expect(camera(c).pitch, isNot(closeTo(was.pitch, 0.1)));
        expect(c.selection, {"a"});
        settled(stage, c, how);
        c.undo();
        expect(camera(c).yaw, was.yaw);
        expect(c.canUndo, isFalse);
      });
    }

    // A still press of the primary button on the stage with the page
    // locked is a click on nothing, which clears the selection, whether the
    // camera was taken to orbit or, with Shift, to pan. The middle button
    // anywhere only pans: still, it leaves the selection.
    final stills = <(String, LogicalKeyboardKey?, int, bool)>[
      ("on the stage", null, kPrimaryButton, false),
      ("shifted", LogicalKeyboardKey.shiftLeft, kPrimaryButton, false),
      (
        "with the middle button, on the element",
        null,
        kMiddleMouseButton,
        true
      ),
    ];
    for (var (what, key, buttons, onElement) in stills) {
      var clears = buttons == kPrimaryButton;
      testWidgets(
          "locked, a still press $what "
          "${clears ? "clears" : "keeps"} the selection", (tester) async {
        var c = onStage();
        addTearDown(c.dispose);
        c.selectOnly("a");
        var stage = await pump(tester, c);
        c.pageLocked = true;
        await tester.pump();
        var at = onElement
            ? stage.toStagePoint(const Offset(200, 250))
            : corner(stage);
        var was = camera(c);
        Future<void> both() async {
          await press(tester, at, buttons: buttons, cancel: true);
          expect(c.selection, {"a"}, reason: "cancelled, not a click");
          settled(stage, c, "cancelled");
          await press(tester, at, buttons: buttons);
          expect(c.selection, clears ? isEmpty : {"a"},
              reason: clears ? "a click on nothing" : "a pan, not a click");
          settled(stage, c, "clicked");
        }

        if (key == null) {
          await both();
        } else {
          await withKey(tester, key, both);
        }
        expect(camera(c), was, reason: "the camera did not move");
        expect(c.document.elementById("a")!.x, 100);
        expect(c.canUndo, isFalse);
      });
    }

    testWidgets("unlocked, a still Option press leaves the selection",
        (tester) async {
      var c = onStage();
      addTearDown(c.dispose);
      c.selectOnly("a");
      var stage = await pump(tester, c);
      await withKey(tester, LogicalKeyboardKey.altLeft, () async {
        await press(tester, corner(stage));
      });
      expect(c.selection, {"a"});
      settled(stage, c, "clicked");
      expect(c.canUndo, isFalse);
    });

    group("the gizmo", () {
      StageGizmoPainter painter(WidgetTester tester) => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<StageGizmoPainter>()
          .single;

      for (var cancel in [false, true]) {
        var how = cancel ? "cancelled" : "let go";
        testWidgets("its arrow dragged, $how: one step, the part lit",
            (tester) async {
          var c = onStage();
          addTearDown(c.dispose);
          c.selectOnly("a");
          var s = await pump(tester, c);
          var g = s.gizmo!;
          var from = s.toStagePoint(g.tip(GizmoPart.x));
          var to = s.toStagePoint(
              g.tip(GizmoPart.x) + (g.tip(GizmoPart.x) - g.centre) * 0.5);
          await drag(tester, from, to - from, cancel: cancel, during: () {
            underWay(s, c, true);
            expect(painter(tester).hot, GizmoPart.x, reason: "held, lit");
            expect(cursor(tester), SystemMouseCursors.grabbing);
          });
          var spot = c.document.elementById("a")!.base.spot!;
          expect(spot.x, closeTo(g.length * 0.5, 0.05));
          settled(s, c, how);
          c.undo();
          expect(c.document.elementById("a")!.base.spot!.x, 0);
          expect(c.canUndo, isFalse);
        });
      }

      testWidgets("pressed and let go still: nothing moves, no step",
          (tester) async {
        var c = onStage();
        addTearDown(c.dispose);
        c.selectOnly("a");
        var s = await pump(tester, c);
        var at = s.toStagePoint(s.gizmo!.tip(GizmoPart.x));
        await press(tester, at);
        expect(c.document.elementById("a")!.base.spot!.x, 0);
        expect(c.selection, {"a"});
        settled(s, c, "clicked");
        expect(c.canUndo, isFalse);
      });
    });
  });

  group("parallax scenery", () {
    CanvasController scenery() => CanvasController(const CanvasDocument()
        .addElement(const BackgroundElement(
            ElementBase(id: "bg", x: 0, y: 0, width: 1280, height: 720),
            backdrop: BackdropKind.parallax)));
    double camX(CanvasController c) => c.parallaxOf("bg")!.cameraAt(c.frame).x;

    for (var cancel in [false, true]) {
      var how = cancel ? "cancelled" : "let go";
      testWidgets("Option-drag pans its camera against the drag, $how",
          (tester) async {
        var c = scenery();
        addTearDown(c.dispose);
        var stage = await pump(tester, c);
        var at = stage.toStagePoint(const Offset(640, 360));
        var by = stage.toStagePoint(const Offset(540, 360)) - at;
        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          await drag(tester, at, by, cancel: cancel, during: () {
            underWay(stage, c, true);
            expect(cursor(tester), SystemMouseCursors.grabbing);
          });
        });
        expect(camX(c), closeTo(100, 1),
            reason: "dragged left, it looks right");
        settled(stage, c, how);
        c.undo();
        expect(camX(c), 0);
        expect(c.canUndo, isFalse);
      });
    }

    testWidgets("a still Option press changes nothing", (tester) async {
      var c = scenery();
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      await withKey(tester, LogicalKeyboardKey.altLeft, () async {
        await press(tester, stage.toStagePoint(const Offset(640, 360)));
      });
      expect(camX(c), 0);
      settled(stage, c, "clicked");
      expect(c.canUndo, isFalse);
    });
  });

  group("painting", () {
    const set = TileSource(
        sheet: "sheet",
        name: "Two",
        sheetW: 33,
        sheetH: 16,
        tileW: 16,
        tileH: 16,
        spacing: 1);
    // Cells 32 across from 100,50: cell (c, r) is 100 + 32c across.
    CanvasController tiles() {
      var c = CanvasController(CanvasDocument(frames: 10).addElement(
          const TileMapElement(
              ElementBase(id: "m", x: 100, y: 50, width: 320, height: 160),
              sources: [set],
              layers: [TileLayer(name: "Ground")],
              cell: 32)));
      c.selectOnly("m");
      c.paintTiles("m");
      return c;
    }

    TileMapElement map(CanvasController c) =>
        c.document.elementById("m")! as TileMapElement;
    List<(int, int)> laid(CanvasController c) => [
          for (var r = 0; r < 5; r++)
            for (var col = 0; col < 10; col++)
              if (map(c).layers.single.at(col, r) != null) (col, r),
        ];

    for (var cancel in [false, true]) {
      var how = cancel ? "cancelled" : "let go";
      testWidgets("a Tile map painted across, $how: kept, one step",
          (tester) async {
        var c = tiles();
        addTearDown(c.dispose);
        var stage = await pump(tester, c);
        var at = stage.toStagePoint(const Offset(116, 66));
        var by = stage.toStagePoint(const Offset(180, 66)) - at;
        await drag(tester, at, by, cancel: cancel, during: () {
          underWay(stage, c, false);
          expect(cursor(tester), SystemMouseCursors.basic);
        });
        expect(laid(c), [(0, 0), (1, 0), (2, 0)]);
        expect(map(c).x, 100, reason: "painted, not moved");
        settled(stage, c, how);
        c.undo();
        expect(laid(c), isEmpty);
        expect(c.canUndo, isFalse);
      });
    }

    testWidgets("a Tile map waits for the drag to travel before it goes on",
        (tester) async {
      var c = tiles();
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      // Just short of the next cell, and taken over its edge by less than
      // the drag threshold: only the cell pressed is laid.
      var at = stage.toStagePoint(const Offset(131.5, 66));
      await drag(tester, at, const Offset(3, 0));
      expect(laid(c), [(0, 0)]);
      settled(stage, c, "let go");
    });

    testWidgets("a Sprite being painted takes the press, not the box",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(
          const SpriteElement(
              ElementBase(id: "s", x: 100, y: 100, width: 160, height: 160))));
      addTearDown(c.dispose);
      c.selectOnly("s");
      c.paintSprite("s");
      var stage = await pump(tester, c);
      var at = stage.toStagePoint(const Offset(180, 180));
      for (var cancel in [false, true]) {
        await drag(tester, at, const Offset(60, 0), cancel: cancel, during: () {
          underWay(stage, c, false);
          expect(cursor(tester), SystemMouseCursors.basic);
        });
        expect(c.document.elementById("s")!.x, 100, reason: "not moved");
        settled(stage, c, cancel ? "cancelled" : "let go");
      }
      expect(c.canUndo, isFalse, reason: "nothing on the sheet to keep");
    });
  });

  group("the cursor", () {
    testWidgets("a box moved shows its own cursor over the pan tool's hand",
        (tester) async {
      // Locked, the pan tool does not pan, and a press on an element moves
      // it: the pointer says what is being done, not which tool is in hand.
      var c = CanvasController(const CanvasDocument().addElement(
          const ShapeElement(
              ElementBase(id: "s", x: 400, y: 200, width: 300, height: 200))));
      addTearDown(c.dispose);
      c.selectOnly("s");
      var stage = await pump(tester, c);
      c.pageLocked = true;
      c.tool = CanvasTool.pan;
      await tester.pump();
      await drag(tester, stage.toStagePoint(const Offset(550, 300)),
          const Offset(40, 0), during: () {
        underWay(stage, c, true);
        expect(cursor(tester), SystemMouseCursors.move);
      });
      expect(c.document.elementById("s")!.x, greaterThan(400));
      settled(stage, c, "let go");
    });
  });
}
