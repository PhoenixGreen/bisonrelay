import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_gizmo.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/marker_note.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_stage_fixups_test.dart holds small rules of the stage's pointer
// handling, each as the person pressing sees it: a press that travels is
// never also a click, however it comes back; nothing a drag showed (a snap
// mark, the closed hand, a lit gizmo part) is left on screen once it ends;
// an Option press that never travels makes no copy; the click cursor is
// not shown while dragging or drawing; the gizmo is the primary button's,
// and a middle press on a locked page only pans; parallax scenery panned
// shows the closed hand; and a synth knob's double click is its own.

const _viewport = Size(1280, 800);

void main() {
  /// pump shows [controller] on a stage and hands back its state.
  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller,
      {void Function(String url)? onButtonLink, bool settle = true}) async {
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(
            key: key, controller: controller, onButtonLink: onButtonLink))));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return key.currentState!;
  }

  /// cursor is the pointer's look over the stage's page.
  MouseCursor cursor(WidgetTester tester) => tester
      .widgetList<MouseRegion>(find.descendant(
          of: find.byType(CanvasStage), matching: find.byType(MouseRegion)))
      .firstWhere((m) => m.child is ClipRect)
      .cursor;

  /// painted is the stage's page painter as last built.
  StagePainter painted(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .expand((p) => [p.painter, p.foregroundPainter])
      .whereType<StagePainter>()
      .first;

  /// drag presses at [from] and takes the pointer [by] in two steps, then
  /// lets go there or, with [cancel], has the system take it. [during] is
  /// called with the pointer still down, after the last step.
  Future<void> drag(WidgetTester tester, Offset from, Offset by,
      {bool cancel = false,
      int buttons = kPrimaryButton,
      PointerDeviceKind kind = PointerDeviceKind.mouse,
      void Function()? during}) async {
    var g = await tester.startGesture(from, buttons: buttons, kind: kind);
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

  /// awayAndBack presses at [at], takes the pointer [by] away and brings it
  /// back to [at], and lets go there.
  Future<void> awayAndBack(WidgetTester tester, Offset at, Offset by) async {
    var g = await tester.startGesture(at);
    await tester.pump();
    await g.moveBy(by);
    await tester.pump();
    await g.moveBy(-by);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

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

  group("a press that travels and comes back is not a click", () {
    testWidgets("a button: moved and back, its link not followed",
        (tester) async {
      var e = const ButtonElement(
          ElementBase(id: "b", x: 400, y: 200, width: 240, height: 80),
          action: ButtonAction(
              kind: ButtonActionKind.openLink, url: "https://example.com"));
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("b");
      var links = <String>[];
      var stage = await pump(tester, c, onButtonLink: links.add);
      await awayAndBack(
          tester, stage.toStagePoint(e.center), const Offset(60, 0));
      expect(painted(tester).snapped, isNull, reason: "no snap mark left");
      expect(links, isEmpty, reason: "it was dragged, not clicked");
      settled(stage, c, "let go");
    });

    CanvasController chart({bool placed = false}) {
      var e = ChartElement(
        const ElementBase(id: "c", x: 40, y: 40, width: 600, height: 340),
        showLegend: true,
        data: ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
      );
      if (placed) {
        var block = chartLegendBlock(e, e.bounds);
        e = e.copyWith(
            legend: e.legend.copyWith(
          x: (block.left - e.bounds.left) / e.bounds.width,
          y: (block.top - e.bounds.top) / e.bounds.height,
        ));
      }
      return CanvasController(CanvasDocument(
          size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
          elements: [e]));
    }

    for (var placed in [false, true]) {
      var which = placed ? "a placed chart key" : "a chart key";
      testWidgets("$which: dragged and back, no series switched",
          (tester) async {
        var c = chart(placed: placed);
        addTearDown(c.dispose);
        c.selectOnly("c");
        var stage = await pump(tester, c);
        ChartElement now() => c.document.elementById("c")! as ChartElement;
        var at = stage
            .toStagePoint(chartLegendRects(now(), now().bounds)[1].$2.center);
        await awayAndBack(tester, at, const Offset(60, 0));
        expect(now().data.series[1].hidden, isFalse);
        settled(stage, c, "let go");
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(now().data.series[1].hidden, isTrue, reason: "a click still");
      });
    }

    testWidgets("a counter's loose button: dragged and back, not pressed",
        (tester) async {
      const e = CounterElement(
          ElementBase(id: "n", x: 400, y: 200, width: 300, height: 160),
          keyed: false,
          buttons: [CounterButton.input],
          looseButtons: true,
          buttonAt: [Offset(0.3, 0.2)]);
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("n");
      var stage = await pump(tester, c);
      var at =
          stage.toStagePoint(counterButtonRects(e, e.bounds).single.center);
      await awayAndBack(tester, at, const Offset(-40, 0));
      expect(find.byType(CounterInput), findsNothing);
      settled(stage, c, "let go");
    });

    testWidgets("a Code panel's code: moved and back, not opened",
        (tester) async {
      var c = CanvasController(
          const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == "web"));
      c.clearSelection();
      var stage = await pump(tester, c);
      CodeElement code() => c.document.elements.whereType<CodeElement>().single;
      var at = stage
          .toStagePoint(codeBoxes(code(), code().bounds).panes[0].code.center);
      await awayAndBack(tester, at, const Offset(60, 0));
      expect(c.codeEditing, isNull);
      settled(stage, c, "let go");
    });

    testWidgets("a reused element's copy: moved and back, not picked",
        (tester) async {
      var c = CanvasController(
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
                    ]))),
                fill: Color(0xFF000000)),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      await awayAndBack(tester, stage.toStagePoint(const Offset(400, 150)),
          const Offset(0, 40));
      expect(c.pickedCopiesOf("a"), isEmpty);
      settled(stage, c, "let go");
    });
  });

  group("the snap mark", () {
    const shape = ShapeElement(
        ElementBase(id: "s", x: 400, y: 200, width: 300, height: 200));

    for (var cancel in [false, true]) {
      var how = cancel ? "cancelled" : "let go";
      testWidgets("a move and a resize, $how, leave none", (tester) async {
        // The resize takes the right edge to just short of a guide, which
        // catches it.
        var c = CanvasController(const CanvasDocument()
            .copyWith(
                guides: const CanvasGuides(guides: [
              CanvasGuide(axis: GuideAxis.vertical, at: 730),
            ]))
            .addElement(shape));
        addTearDown(c.dispose);
        c.selectOnly("s");
        var stage = await pump(tester, c);
        await drag(
            tester, stage.toStagePoint(shape.center), const Offset(40, 0),
            cancel: cancel,
            during: () => expect(painted(tester).snapped, isNotNull));
        expect(painted(tester).snapped, isNull, reason: "moved, $how");
        c.undo();
        await tester.pump();
        var handle = stage.handleAt(StageHandle.bottomRight);
        await drag(
            tester, handle, stage.toStagePoint(const Offset(728, 400)) - handle,
            cancel: cancel,
            during: () => expect(painted(tester).snapped?.caught, isTrue));
        expect(painted(tester).snapped, isNull, reason: "resized, $how");
      });
    }
  });

  group("the cursor once a gesture ends", () {
    for (var cancel in [false, true]) {
      var how = cancel ? "cancelled" : "let go";
      testWidgets("a pan, $how: the closed hand goes", (tester) async {
        var c = CanvasController(const CanvasDocument().addElement(
            const ShapeElement(ElementBase(
                id: "s", x: 400, y: 200, width: 300, height: 200))));
        addTearDown(c.dispose);
        var stage = await pump(tester, c);
        await drag(tester, stage.toStagePoint(const Offset(100, 600)),
            const Offset(80, 0),
            buttons: kMiddleMouseButton,
            cancel: cancel,
            during: () => expect(cursor(tester), SystemMouseCursors.grabbing));
        expect(cursor(tester), SystemMouseCursors.basic);
        settled(stage, c, how);
      });
    }
  });

  group("a reused element's copy and Option", () {
    testWidgets("a still Option press makes no copy and no step",
        (tester) async {
      var c = CanvasController(
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
                    ]))),
                fill: Color(0xFF000000)),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      for (var picked in [false, true]) {
        if (picked) c.pickCopy("a", "i1");
        var stage = await pump(tester, c);
        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          await drag(
              tester, stage.toStagePoint(const Offset(400, 150)), Offset.zero);
        });
        expect(c.motionOf("a").instances!.count, 2,
            reason: "picked first: $picked");
        expect(c.canUndo, isFalse);
        settled(stage, c, "clicked");
      }
    });
  });

  group("the click cursor during a gesture", () {
    testWidgets("the held marker's note dragged over a button: not shown",
        (tester) async {
      const marker = TimelineAction(
          frame: 3, kind: TimelineActionKind.stop, label: "Press to jump");
      var doc = const CanvasDocument(frames: 40, actions: [marker]);
      var box = markerNoteLayout(doc.size.size, marker).box;
      var c = CanvasController(
          doc.addElement(ButtonElement(ElementBase(
              id: "b",
              x: box.left,
              y: box.top,
              width: box.width,
              height: box.height))),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      c.play();
      for (var i = 0; i < 3; i++) {
        c.tickForTest();
      }
      await tester.pumpAndSettle();
      expect(c.holdingMarker, isNotNull);
      c.selectOnly("b");
      await tester.pump();
      var at = stage.toStagePoint(box.center);
      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at - const Offset(1, 0));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(at);
      await tester.pump();
      expect(cursor(tester), SystemMouseCursors.click,
          reason: "hovering, a click here would press the button");
      await mouse.down(at);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await mouse.moveBy(const Offset(20, -10));
        await tester.pump();
      }
      expect(c.holdingMarker!.noteAt, isNot(marker.noteAt), reason: "dragged");
      expect(cursor(tester), isNot(SystemMouseCursors.click));
      await mouse.up();
      await tester.pumpAndSettle();
      settled(stage, c, "let go");
    });
  });

  group("a 3D stage", () {
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
    double spotX(CanvasController c) =>
        c.document.elementById("a")!.base.spot!.x;
    StageGizmoPainter gizmoPainter(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<StageGizmoPainter>()
        .single;

    testWidgets("locked, a middle drag on the gizmo pans the camera",
        (tester) async {
      var c = onStage();
      addTearDown(c.dispose);
      c.selectOnly("a");
      var s = await pump(tester, c);
      c.pageLocked = true;
      await tester.pump();
      var from = s.toStagePoint(s.gizmo!.tip(GizmoPart.x));
      await drag(tester, from, const Offset(60, 0),
          buttons: kMiddleMouseButton);
      expect(spotX(c), 0, reason: "the gizmo is not the middle button's");
      expect(camera(c).tx, isNot(0), reason: "the camera panned");
      expect(c.selection, {"a"});
      settled(s, c, "let go");
    });

    testWidgets("unlocked, a middle drag on the gizmo pans the view",
        (tester) async {
      var c = onStage();
      addTearDown(c.dispose);
      c.selectOnly("a");
      var s = await pump(tester, c);
      var from = s.toStagePoint(s.gizmo!.tip(GizmoPart.x));
      // The page fits the window, so the view has nowhere to slide: the
      // pan shows as a gesture under way that opens no undo step, as the
      // gizmo's would.
      await drag(tester, from, const Offset(60, 0), buttons: kMiddleMouseButton,
          during: () {
        expect(s.gestureUnderWay, isTrue);
        expect(c.interacting, isFalse, reason: "a pan, not a change");
      });
      expect(spotX(c), 0);
      expect(c.canUndo, isFalse);
      settled(s, c, "let go");
    });

    for (var onElement in [false, true]) {
      var where = onElement ? "on the element" : "on the stage";
      testWidgets("locked, a still middle press $where keeps the selection",
          (tester) async {
        var c = onStage();
        addTearDown(c.dispose);
        c.selectOnly("a");
        var s = await pump(tester, c);
        c.pageLocked = true;
        await tester.pump();
        var at = s.toStagePoint(
            onElement ? const Offset(200, 250) : const Offset(1200, 650));
        await drag(tester, at, Offset.zero, buttons: kMiddleMouseButton);
        expect(c.selection, {"a"}, reason: "a middle press is a pan");
        settled(s, c, "let go");
      });
    }

    testWidgets("the gizmo's part held by a touch is not lit once let go",
        (tester) async {
      var c = onStage();
      addTearDown(c.dispose);
      c.selectOnly("a");
      var s = await pump(tester, c);
      var g = s.gizmo!;
      var from = s.toStagePoint(g.tip(GizmoPart.x));
      var to =
          s.toStagePoint(g.tip(GizmoPart.x) + (g.tip(GizmoPart.x) - g.centre));
      for (var cancel in [false, true]) {
        await drag(tester, from, (to - from) * 0.25,
            cancel: cancel,
            kind: PointerDeviceKind.touch,
            during: () => expect(gizmoPainter(tester).hot, GizmoPart.x));
        expect(gizmoPainter(tester).hot, isNull,
            reason: cancel ? "cancelled" : "let go");
        c.undo();
        await tester.pump();
      }
    });

    testWidgets("a mouse lights what it is over once the gizmo is let go",
        (tester) async {
      var c = onStage();
      addTearDown(c.dispose);
      c.selectOnly("a");
      var s = await pump(tester, c);
      var at = s.toStagePoint(s.gizmo!.tip(GizmoPart.x));
      await drag(tester, at, Offset.zero);
      expect(gizmoPainter(tester).hot, GizmoPart.x, reason: "still over it");
      await drag(tester, at, const Offset(0, 300));
      expect(gizmoPainter(tester).hot, isNull, reason: "let go off it");
    });
  });

  group("a synth knob's double click", () {
    SynthModuleElement osc(CanvasController c) => c.document.elements
        .whereType<SynthModuleElement>()
        .firstWhere((e) => e.module == SynthModuleKind.osc);
    Offset on(SynthModuleElement e, Offset q) {
      var (s, at) = synthPanelFit(e.bounds, synthPanelFor(e));
      return at + q * s;
    }

    testWidgets("is not made by a click on an element and then the knob",
        (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addSynthRack();
      Rect? used;
      for (var e in c.document.elements) {
        used = used == null ? e.bounds : used.expandToInclude(e.bounds);
      }
      var page = c.document.size.size;
      var spot = used!.right + 90 < page.width
          ? Offset(used.right + 20, used.top)
          : Offset(used.left, used.bottom + 20);
      c.addElement(ShapeElement(
          ElementBase(id: "s", x: spot.dx, y: spot.dy, width: 60, height: 60)));
      c.clearSelection();
      var stage = await pump(tester, c, settle: false);
      var level = synthPanelOf(SynthModuleKind.osc).dials[2].center;
      var knob = stage.toStagePoint(on(osc(c), level));
      // Turned down first, so a reset to its start would show.
      var g = await tester.startGesture(knob);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, 5));
        await tester.pump();
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 600));
      var turned = osc(c).value("level");
      expect(turned, lessThan(0.8));

      await tester.tapAt(stage.toStagePoint(spot + const Offset(30, 30)));
      await tester.pump();
      expect(c.selection, {"s"});
      await tester.tapAt(knob);
      await tester.pump(const Duration(milliseconds: 600));
      expect(osc(c).value("level"), turned,
          reason: "one click on the knob is not its double click");

      await tester.tapAt(knob);
      await tester.pump();
      await tester.tapAt(knob);
      await tester.pump(const Duration(milliseconds: 600));
      expect(osc(c).value("level"), 0.8, reason: "two on it reset it");
    });
  });
}
