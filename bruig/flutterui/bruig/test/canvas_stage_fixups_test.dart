import 'dart:async';
import 'dart:ui' as ui;

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
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart';
import 'package:bruig/plugin_system/canvas/render/play_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:bruig/plugin_system/canvas/render/synth_task_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/code/code_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/carried_synth_cable.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/counter_input.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_gizmo.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_keys.dart';
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
      expect(painted(tester).inputs.guides.snapped, isNull,
          reason: "no snap mark left");
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
            during: () =>
                expect(painted(tester).inputs.guides.snapped, isNotNull));
        expect(painted(tester).inputs.guides.snapped, isNull,
            reason: "moved, $how");
        c.undo();
        await tester.pump();
        var handle = stage.handleAt(StageHandle.bottomRight);
        await drag(
            tester, handle, stage.toStagePoint(const Offset(728, 400)) - handle,
            cancel: cancel,
            during: () =>
                expect(painted(tester).inputs.guides.snapped?.caught, isTrue));
        expect(painted(tester).inputs.guides.snapped, isNull,
            reason: "resized, $how");
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

    testWidgets("is not made by a click on one knob and then another",
        (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addSynthRack();
      c.clearSelection();
      var stage = await pump(tester, c, settle: false);
      var dials = synthPanelOf(SynthModuleKind.osc).dials;
      var level = stage.toStagePoint(on(osc(c), dials[2].center));
      var mod = stage.toStagePoint(on(osc(c), dials[3].center));
      var g = await tester.startGesture(level);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, 5));
        await tester.pump();
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 600));
      var turned = osc(c).value("level");
      expect(turned, lessThan(0.8));

      await tester.tapAt(mod);
      await tester.pump();
      await tester.tapAt(level);
      await tester.pump(const Duration(milliseconds: 600));
      expect(osc(c).value("level"), turned,
          reason: "a click on another knob first is not its double click");
    });
  });

  group("copy, cut, paste, undo and Space in the table of keys", () {
    /// linesFor is every line for [key] with [command] and [shift] that
    /// always applies, outside a drawing being edited.
    List<CanvasShortcut> linesFor(LogicalKeyboardKey key,
            {bool command = true, bool? shift}) =>
        [
          for (var line in canvasShortcuts)
            if (line.keys.contains(key) &&
                identical(line.when, always) &&
                line.command == command &&
                (shift == null || line.shift == shift))
              line,
        ];

    test("each is one line, heard on the whole page", () {
      for (var (key, shift, held) in [
        (LogicalKeyboardKey.keyC, null, KeyHeld.once),
        (LogicalKeyboardKey.keyX, null, KeyHeld.once),
        (LogicalKeyboardKey.keyV, null, KeyHeld.once),
        (LogicalKeyboardKey.keyZ, false, KeyHeld.again),
        (LogicalKeyboardKey.keyZ, true, KeyHeld.again),
      ]) {
        var lines = linesFor(key, shift: shift);
        var what = "${key.keyLabel}${shift == true ? " with Shift" : ""}";
        expect(lines, hasLength(1), reason: what);
        expect(lines.single.reach, ShortcutReach.page, reason: what);
        expect(lines.single.held, held, reason: what);
      }
    });

    test("a drawing's own copy, cut and paste do it once a press", () {
      for (var key in [
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyV,
      ]) {
        var drawing = canvasShortcuts.where((line) =>
            line.keys.contains(key) &&
            line.command == true &&
            !identical(line.when, always));
        expect(drawing.single.held, KeyHeld.once, reason: key.keyLabel);
        expect(drawing.single.does, contains("drawing"));
      }
    });

    test("Space plays with or without Alt wherever the page hears it", () {
      var lines = linesFor(LogicalKeyboardKey.space, command: false);
      expect(lines, hasLength(1));
      expect(lines.single.reach, ShortcutReach.page);
      expect(lines.single.alt, isNull);
      expect(lines.single.held, KeyHeld.taken);
    });
  });

  group("a carried synth cable's repaint", () {
    test("follows its colour and its panel's scale", () {
      const was = CarriedSynthCable(
          Offset(10, 10), Offset(50, 50), Color(0xFFFF0000), 1, 1, Offset.zero);
      const same = CarriedSynthCable(
          Offset(10, 10), Offset(50, 50), Color(0xFFFF0000), 1, 1, Offset.zero);
      const recoloured = CarriedSynthCable(
          Offset(10, 10), Offset(50, 50), Color(0xFF00FF00), 1, 1, Offset.zero);
      const resized = CarriedSynthCable(
          Offset(10, 10), Offset(50, 50), Color(0xFFFF0000), 2, 1, Offset.zero);
      expect(same.shouldRepaint(was), isFalse);
      expect(recoloured.shouldRepaint(was), isTrue, reason: "its colour");
      expect(resized.shouldRepaint(was), isTrue, reason: "its panel's scale");
    });
  });

  group("a retouching stroke being drawn", () {
    testWidgets("is repainted as it grows", (tester) async {
      var document = const CanvasDocument();
      var c = CanvasController(document.addElement(ImageElement(
        ElementBase(
            id: "i",
            width: document.size.width.toDouble(),
            height: document.size.height.toDouble()),
        assetId: "abcdefghijklmnop",
      )));
      addTearDown(c.dispose);
      c.selectOnly("i");
      c.retouch = RetouchBrush.erase;
      var stage = await pump(tester, c);
      var pixels = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 200);
      await tester.runAsync(() async {
        var done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, 64, 64, ui.PixelFormat.rgba8888, done.complete);
        c.images.putForTest("abcdefghijklmnop", await done.future);
      });
      await tester.pumpAndSettle();

      var g = await tester.startGesture(stage.pageRect.center);
      await tester.pump();
      var before = painted(tester);
      expect(before.inputs.retouch.stroke.value, hasLength(1));
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      var after = painted(tester);
      expect(after.inputs.retouch.stroke.value.length, greaterThan(1));
      expect(after.shouldRepaint(before), isTrue,
          reason: "the stroke has grown, so it is drawn again");
      await g.up();
      await tester.pumpAndSettle();
    });
  });

  group("a live counter's button under the pointer", () {
    testWidgets("is drawn lit as the pointer comes onto it", (tester) async {
      const e = CounterElement(
          ElementBase(id: "n", x: 400, y: 200, width: 300, height: 160),
          keyed: false,
          buttons: [CounterButton.input],
          looseButtons: true,
          buttonAt: [Offset(0.3, 0.2)]);
      expect(e.mode, CounterMode.run);
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      var at =
          stage.toStagePoint(counterButtonRects(e, e.bounds).single.center);
      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
          location: stage.toStagePoint(const Offset(20, 20)));
      addTearDown(mouse.removePointer);
      await tester.pump();
      var before = painted(tester);
      await mouse.moveTo(at);
      await tester.pump();
      var after = painted(tester);
      expect(identical(after, before), isFalse, reason: "the stage rebuilt");
      expect(after.shouldRepaint(before), isTrue,
          reason: "the button under the pointer is drawn lit");
    });
  });

  group("a Code panel's playbar", () {
    testWidgets("pressed, scrubs and leaves the selection as it is",
        (tester) async {
      var c = CanvasController(
          const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == "web"));
      c.clearSelection();
      var stage = await pump(tester, c);
      var e = c.document.elements.whereType<CodeElement>().single;
      var track =
          codePlaybar(e, codeBoxes(e, e.bounds).bar)[CodePlayPart.track]!;
      await tester.tapAt(stage.toStagePoint(track.center));
      await tester.pumpAndSettle();
      expect(c.frame, greaterThan(0), reason: "it scrubbed");
      expect(c.selection, isEmpty, reason: "it plays, as its buttons do");
      settled(stage, c, "let go");
    });
  });

  group("controls on an element its motion has moved", () {
    /// moved is [e] with a move that takes it 300 to the right by frame 20
    /// and holds it there.
    T moved<T extends CanvasElement>(T e) => e.withBase(
            track: ElementTrack(const [
          Keyframe(frame: 0),
          Keyframe(frame: 20, dx: 300),
        ])) as T;

    /// shown is a stage of [e], moved, at frame 20, and where it is drawn.
    Future<(CanvasController, CanvasStageState, Rect)> shown(
        WidgetTester tester, CanvasElement e) async {
      var c = CanvasController(
          CanvasDocument(frames: 240, elements: [moved(e)]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.frame = 20;
      var stage = await pump(tester, c);
      var drawn = e.bounds.shift(const Offset(300, 0));
      return (c, stage, drawn);
    }

    testWidgets("a metronome's button", (tester) async {
      const e = MetronomeElement(
          ElementBase(id: "m", x: 100, y: 100, width: 200, height: 320),
          bpm: 100);
      var (c, stage, drawn) = await shown(tester, e);
      var (s, at) = metronomeFit(drawn);
      var faster = metronomeLayout.buttons[MetronomePart.faster]!.center;
      await tester.tapAt(stage.toStagePoint(at + faster * s));
      await tester.pumpAndSettle();
      expect((c.document.elementById("m")! as MetronomeElement).bpm, 104);
    });

    testWidgets("a play task's step", (tester) async {
      const e = PlayTaskElement(
          ElementBase(id: "p", x: 100, y: 100, width: 600, height: 400),
          checks: [
            PlayCheck(PlayCheckKind.self, "Say the finger numbers"),
          ]);
      var (c, stage, drawn) = await shown(tester, e);
      var row = playTaskLayout(e, e.width).rows[0].center;
      await tester.tapAt(stage.toStagePoint(drawn.topLeft + row));
      await tester.pumpAndSettle();
      expect(c.playTaskShowFor(e).done, [true]);
    });

    testWidgets("a synth task's button: a drag on it does not move the card",
        (tester) async {
      const e = SynthTaskElement(
          ElementBase(id: "s", x: 100, y: 100, width: 210, height: 200));
      var (c, stage, drawn) = await shown(tester, e);
      var before = c.document.elementById("s");
      var hear = synthTaskLayout(e, null).hear.center;
      await drag(
          tester,
          stage.toStagePoint(drawn.topLeft + hear * synthTaskScale(drawn)),
          const Offset(0, 80));
      expect(c.document.elementById("s"), before);
      expect(c.selection, {"s"}, reason: "the button picks its card");
    });

    testWidgets("a code task's button: a drag on it does not move the card",
        (tester) async {
      const e = CodeTaskElement(
          ElementBase(id: "t", x: 100, y: 100, width: 400, height: 300));
      var (c, stage, drawn) = await shown(tester, e);
      var before = c.document.elementById("t");
      var button = codeTaskLayout(e, e.width).button.shift(drawn.topLeft);
      await drag(
          tester, stage.toStagePoint(button.center), const Offset(0, 80));
      expect(c.document.elementById("t"), before);
    });

    /// lesson is a Code lesson whose Code panel has been moved, at frame 20:
    /// its Run panel taken away, as the move takes the Code panel over it.
    Future<(CanvasController, CanvasStageState, CodeElement Function())> lesson(
        WidgetTester tester) async {
      var c = CanvasController(
          const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == "web"));
      c.deleteElement(
          c.document.elements.whereType<CodeRunElement>().single.id);
      c.clearSelection();
      CodeElement code() => c.document.elements.whereType<CodeElement>().single;
      c.replaceElement(moved(code()));
      c.frame = 20;
      var stage = await pump(tester, c);
      return (c, stage, code);
    }

    testWidgets("a Code panel's tab, carried to another pane", (tester) async {
      var (c, stage, code) = await lesson(tester);
      var e = code();
      var b = codeBoxes(e, e.bounds.shift(const Offset(300, 0)));
      var from = stage.toStagePoint(b.panes[2].tabs.single.rect.center);
      var row = b.panes[1].tabRow;
      var to = stage.toStagePoint(Offset(row.right - 10, row.center.dy));
      await drag(tester, from, to - from);
      expect(code().panes[2].tabs, isEmpty);
    });

    testWidgets("a Code panel's divider, dragged", (tester) async {
      var (c, stage, code) = await lesson(tester);
      var e = code();
      // Between columns: a row divider moved sideways is still on its line.
      var d = codeBoxes(e, e.bounds.shift(const Offset(300, 0)))
          .dividers
          .firstWhere((d) => d.columns);
      var was = e.columns;
      await drag(tester, stage.toStagePoint(d.hit.center), const Offset(80, 0));
      var columns = code().columns;
      expect(columns[0] / (columns[0] + columns[1]),
          greaterThan(was[0] / (was[0] + was[1]) + 0.02));
      expect(code().x, e.x, reason: "the panel did not move");
    });

    testWidgets("a Code panel's code, clicked, opens where it is drawn",
        (tester) async {
      var (c, stage, code) = await lesson(tester);
      var e = code();
      var drawn = e.bounds.shift(const Offset(300, 0));
      var pane = codeBoxes(e, drawn).panes[0].code;
      await tester.tapAt(stage.toStagePoint(pane.center));
      await tester.pumpAndSettle();
      expect(c.codeEditing, (e.id, 0));
      var editor = tester.widget<CodePaneEditor>(find.byType(CodePaneEditor));
      expect(editor.rect.center.dx,
          closeTo(stage.toStagePoint(pane.center).dx, 1));
    });

    testWidgets("a Code panel's playbar, scrubbed", (tester) async {
      var (c, stage, code) = await lesson(tester);
      var e = code();
      var drawn = e.bounds.shift(const Offset(300, 0));
      var track = codePlaybar(e, codeBoxes(e, drawn).bar)[CodePlayPart.track]!;
      var end = lessonSpan(e)!.$2;
      await tester.tapAt(stage
          .toStagePoint(Offset(track.left + track.width / 2, track.center.dy)));
      await tester.pumpAndSettle();
      expect(c.frame / 24, closeTo(end / 2, 0.1));
    });
  });

  group("a reused Code panel's copy", () {
    // The press is tested against the panel's own place, so on a copy away
    // from it the code is not pressed. Testing it against the copy's place
    // alone would open the editor over the panel, not the copy: the editor
    // has to be told which copy it is on first.
    testWidgets("a still press on the copy's code lands on its pane",
        skip: true, (tester) async {
      var c = CanvasController(
          const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == "web"));
      c.clearSelection();
      CodeElement code() => c.document.elements.whereType<CodeElement>().single;
      var e = code();
      var away = e.width + 40;
      c.replaceElement(e.withBase(
          motion: ElementMotion(
              instances: InstanceSet(items: [
        const ElementInstance("i0"),
        ElementInstance("i1", dx: away),
      ]))));
      var stage = await pump(tester, c);
      var pane =
          codeBoxes(e, e.bounds.shift(Offset(away, 0))).panes[0].code.center;
      await tester.tapAt(stage.toStagePoint(pane));
      await tester.pumpAndSettle();
      expect(c.codeEditing, (e.id, 0));
    });
  });
}
