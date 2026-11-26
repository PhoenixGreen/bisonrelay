import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/counter_input.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_box_drag_test.dart is a press on what is selected, as the person
// doing it sees it: the box moved, resized, slanted or turned, each one undo
// step whether it is let go or the system cancels it; and the clicks that
// ride on such a press. A press on a selected button, a video's or a
// speaker's controls, a sheet's playbar, a counter's button, a chart's key,
// an instrument's key, a Code panel's code or a reused element's copy moves
// the element if it travels and clicks it if it does not. Each of those is
// held here three ways: let go where it began, it clicks; dragged, it does
// not; cancelled, it does not, and nothing of the press is left behind.
// A square or a circle resized stays square because of what it is, its
// outline and words their size unless the person holds its proportions.

const _viewport = Size(1200, 800);

/// _NoFrames is a video source with nothing in it: a link plays nothing
/// here, and no decoder is started for it.
class _NoFrames implements FrameSource {
  @override
  Future<FrameReader?> open(String path,
          {required double from,
          required int width,
          required int height,
          required double fps}) async =>
      null;
}

void main() {
  /// pump shows [controller] on a stage and hands back its state.
  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller,
      {void Function(String url)? onButtonLink}) async {
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(
            key: key, controller: controller, onButtonLink: onButtonLink))));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  /// drag presses at [from] and takes the pointer [by] on the stage, in two
  /// steps, then lets go there or, with [cancel], has the system take it.
  Future<void> drag(WidgetTester tester, Offset from, Offset by,
      {bool cancel = false}) async {
    var g = await tester.startGesture(from);
    await tester.pump();
    await g.moveBy(by / 2);
    await tester.pump();
    await g.moveBy(by / 2);
    await tester.pump();
    if (cancel) {
      await g.cancel();
    } else {
      await g.up();
    }
    await tester.pumpAndSettle();
  }

  /// pressAndCancel presses at [at] and has the system take the pointer
  /// before it has moved.
  Future<void> pressAndCancel(WidgetTester tester, Offset at) async {
    var g = await tester.startGesture(at);
    await tester.pump();
    await g.cancel();
    await tester.pumpAndSettle();
  }

  /// settled is that nothing of the last press is left: no gesture under
  /// way and no undo step open.
  void settled(CanvasStageState stage, CanvasController c, String how) {
    expect(stage.gestureUnderWay, isFalse, reason: "$how: no gesture left");
    expect(c.interacting, isFalse, reason: "$how: no undo step left open");
  }

  group("the selection's box", () {
    const shape = ShapeElement(
        ElementBase(id: "s", x: 400, y: 200, width: 300, height: 200),
        fill: Color(0xFFCC2200));

    Future<(CanvasController, CanvasStageState)> one(
        WidgetTester tester) async {
      var c = CanvasController(const CanvasDocument().addElement(shape));
      addTearDown(c.dispose);
      c.selectOnly("s");
      var stage = await pump(tester, c);
      return (c, stage);
    }

    CanvasElement now(CanvasController c) => c.document.elementById("s")!;

    // Each way of taking hold of the box: where it is pressed, how far it
    // is dragged, and whether the element changed.
    final ways = <(
      String,
      void Function(CanvasController),
      Offset Function(CanvasStageState),
      Offset,
      bool Function(CanvasElement),
    )>[
      (
        "moved",
        (c) {},
        (stage) => stage.toStagePoint(shape.center),
        const Offset(60, 40),
        (e) => e.x > shape.x && e.y > shape.y && e.width == shape.width,
      ),
      (
        "resized",
        (c) {},
        (stage) => stage.handleAt(StageHandle.bottomRight),
        const Offset(40, 30),
        (e) => e.width > shape.width && e.x == shape.x,
      ),
      (
        "turned",
        (c) {},
        (stage) => stage.handleAt(StageHandle.rotate),
        const Offset(80, 0),
        (e) => e.rotation != 0,
      ),
      (
        "slanted",
        (c) => c.skewHandles = true,
        (stage) => stage.handleAt(StageHandle.topCenter),
        const Offset(40, 0),
        (e) => e.base.skewX != 0,
      ),
    ];

    for (var (what, prepare, from, by, changed) in ways) {
      testWidgets("$what, it is one undo step", (tester) async {
        var (c, stage) = await one(tester);
        prepare(c);
        await tester.pump();
        await drag(tester, from(stage), by);
        expect(changed(now(c)), isTrue, reason: "it was $what");
        settled(stage, c, "let go");
        c.undo();
        expect(now(c), shape, reason: "one undo puts it back");
        expect(c.canUndo, isFalse, reason: "and it was one step");
      });

      testWidgets("$what and cancelled, what it did is kept as one step",
          (tester) async {
        var (c, stage) = await one(tester);
        prepare(c);
        await tester.pump();
        var g = await tester.startGesture(from(stage));
        await tester.pump();
        await g.moveBy(by);
        await tester.pump();
        expect(stage.gestureUnderWay, isTrue);
        expect(c.interacting, isTrue, reason: "a change, an undo step");
        await g.cancel();
        await tester.pumpAndSettle();
        expect(changed(now(c)), isTrue, reason: "the drag is kept");
        settled(stage, c, "cancelled");
        c.undo();
        expect(now(c), shape);
        expect(c.canUndo, isFalse);
      });
    }

    testWidgets("several selected move together, one undo step",
        (tester) async {
      const a = ShapeElement(
          ElementBase(id: "a", x: 100, y: 100, width: 150, height: 150));
      const b = ShapeElement(
          ElementBase(id: "b", x: 500, y: 400, width: 100, height: 100));
      var c =
          CanvasController(const CanvasDocument().addElement(a).addElement(b));
      addTearDown(c.dispose);
      c.selectOnly("a");
      c.toggleSelected("b");
      var stage = await pump(tester, c);

      await drag(tester, stage.toStagePoint(a.center), const Offset(60, 0));
      var movedA = c.document.elementById("a")!.x - a.x;
      var movedB = c.document.elementById("b")!.x - b.x;
      expect(movedA, greaterThan(0));
      expect(movedB, closeTo(movedA, 0.01), reason: "by the same amount");
      settled(stage, c, "let go");
      c.undo();
      expect(c.document.elementById("a"), a);
      expect(c.document.elementById("b"), b);
      expect(c.canUndo, isFalse);
    });

    testWidgets("a move snaps to another element", (tester) async {
      // b's left edge is dragged to 253, within reach of a's right edge at
      // 250 and of nothing else.
      const a = ShapeElement(
          ElementBase(id: "a", x: 100, y: 100, width: 150, height: 150));
      const b = ShapeElement(
          ElementBase(id: "b", x: 600, y: 420, width: 100, height: 100));
      var c =
          CanvasController(const CanvasDocument().addElement(a).addElement(b));
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      var from = stage.toStagePoint(b.center);
      var to = stage.toStagePoint(b.center - const Offset(347, 0));
      await drag(tester, from, to - from);
      expect(c.document.elementById("b")!.x, closeTo(250, 0.01));
      settled(stage, c, "let go");
    });

    testWidgets("a move snaps to a guide", (tester) async {
      const s = ShapeElement(
          ElementBase(id: "s", x: 500, y: 300, width: 100, height: 100));
      var c = CanvasController(const CanvasDocument()
          .copyWith(
              guides: const CanvasGuides(guides: [
            CanvasGuide(axis: GuideAxis.vertical, at: 400),
          ]))
          .addElement(s));
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      var from = stage.toStagePoint(s.center);
      var to = stage.toStagePoint(s.center - const Offset(97, 0));
      await drag(tester, from, to - from);
      expect(c.document.elementById("s")!.x, closeTo(400, 0.01));
      settled(stage, c, "let go");
    });

    testWidgets("a press let go where it began selects and moves nothing",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(shape));
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      await tester.tapAt(stage.toStagePoint(shape.center));
      await tester.pumpAndSettle();
      expect(c.selection, {"s"});
      expect(now(c), shape, reason: "not moved");
      settled(stage, c, "clicked");
      expect(c.canUndo, isFalse, reason: "nothing to take back");
    });
  });

  group("a click riding on a press", () {
    // Each kind: what the press is on, what shows the click was made, and
    // whether the element moved.

    testWidgets("a button's link", (tester) async {
      var e = const ButtonElement(
          ElementBase(id: "b", x: 400, y: 200, width: 240, height: 80),
          action: ButtonAction(
              kind: ButtonActionKind.openLink, url: "https://example.com"));
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("b");
      var links = <String>[];
      var stage = await pump(tester, c, onButtonLink: links.add);
      var at = stage.toStagePoint(e.center);

      await drag(tester, at, const Offset(60, 0));
      expect(links, isEmpty, reason: "dragged, it moves");
      expect(c.document.elementById("b")!.x, greaterThan(e.x));
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      expect(links, isEmpty, reason: "cancelled, nothing");
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(links, ["https://example.com"], reason: "clicked, it runs");
      expect(c.document.elementById("b")!.x, e.x);
      settled(stage, c, "clicked");
    });

    testWidgets("a video's link", (tester) async {
      var e = const VideoElement(
          ElementBase(id: "v", x: 300, y: 150, width: 480, height: 270),
          clip: MediaClip(),
          link: "https://vimeo.com/5",
          controls: [VideoControl.clickToggle]);
      var c = CanvasController(const CanvasDocument().addElement(e),
          audioEngine: FakeEngine(const {}), frameSource: _NoFrames());
      addTearDown(c.dispose);
      c.selectOnly("v");
      var links = <String>[];
      var stage = await pump(tester, c, onButtonLink: links.add);
      var at = stage.toStagePoint(e.bounds.topLeft + const Offset(60, 60));

      await drag(tester, at, const Offset(60, 0));
      expect(links, isEmpty);
      expect(c.document.elementById("v")!.x, greaterThan(e.x));
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      expect(links, isEmpty);
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(links, ["https://vimeo.com/5"]);
      expect(c.document.elementById("v")!.x, e.x);
      settled(stage, c, "clicked");
    });

    testWidgets("a speaker's mute", (tester) async {
      var e = const AudioElement(
          ElementBase(id: "a", x: 300, y: 200, width: 400, height: 80),
          controls: [AudioControl.playPause, AudioControl.mute]);
      var c = CanvasController(const CanvasDocument().addElement(e),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.selectOnly("a");
      var stage = await pump(tester, c);
      var mute = audioParts(e, e.bounds).mute!;
      var at = stage.toStagePoint(mute.center);
      bool muted() =>
          c.audio.view(c.document.elementById("a")! as AudioElement).muted;

      await drag(tester, at, const Offset(60, 0));
      expect(muted(), isFalse);
      expect(c.document.elementById("a")!.x, greaterThan(e.x));
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      expect(muted(), isFalse);
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(muted(), isTrue);
      expect(c.document.elementById("a")!.x, e.x);
      settled(stage, c, "clicked");
    });

    testWidgets("a sheet's playbar", (tester) async {
      const box = Rect.fromLTWH(40, 40, 1200, 420);
      var c = CanvasController(
          const CanvasDocument(frames: 24 * 60, frameRate: 24),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var sheet = SheetElement(ElementBase(
          id: "sheet",
          x: box.left,
          y: box.top,
          width: box.width,
          height: box.height));
      c.addElement(sheet);
      c.newScoreFor(sheet, score: odeToJoy());
      c.selectOnly("sheet");
      SheetElement sheetNow() =>
          c.document.elementById("sheet")! as SheetElement;
      var stage = await pump(tester, c);
      var on = sheetBarParts(sheetBarRect(sheetNow(), box)!)[SheetBarPart.on]!;
      var at = stage.toStagePoint(on.center);
      c.sheetToStart(sheetNow());
      var start = c.frame;

      await drag(tester, at, const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.frame, start, reason: "dragged, the playhead stays");
      expect(sheetNow().y, greaterThan(box.top));
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.frame, start);
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(c.frame, greaterThan(start), reason: "clicked, a note on");
      expect(sheetNow().y, box.top);
      settled(stage, c, "clicked");
    });

    testWidgets("a counter's button", (tester) async {
      const e = CounterElement(
          ElementBase(id: "n", x: 400, y: 200, width: 300, height: 120),
          keyed: false,
          buttons: [CounterButton.input]);
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("n");
      var stage = await pump(tester, c);
      var at =
          stage.toStagePoint(counterButtonRects(e, e.bounds).single.center);

      await drag(tester, at, const Offset(60, 0));
      expect(find.byType(CounterInput), findsNothing);
      expect(c.document.elementById("n")!.x, greaterThan(e.x));
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      expect(find.byType(CounterInput), findsNothing);
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.byType(CounterInput), findsOneWidget);
      expect(c.document.elementById("n")!.x, e.x);
      settled(stage, c, "clicked");
    });

    testWidgets("a counter's loose button, dragged as a piece", (tester) async {
      // A loose button is both a piece to place and a button: dragged, the
      // piece moves inside the counter; clicked, the button is pressed.
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
      CounterElement counter() =>
          c.document.elementById("n")! as CounterElement;

      await drag(tester, at, const Offset(-40, 0));
      expect(find.byType(CounterInput), findsNothing);
      expect(counter().placedButton(0).dx, lessThan(0.3), reason: "moved");
      expect(counter().x, e.x, reason: "the counter itself stays");
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      expect(find.byType(CounterInput), findsNothing);
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.byType(CounterInput), findsOneWidget);
      settled(stage, c, "clicked");
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
      var which = placed ? "a placed chart key's entry" : "a chart key's entry";
      testWidgets(which, (tester) async {
        // Placed, the key is a label of the chart, dragged by itself; laid
        // out by the chart, a drag on it moves the chart.
        var c = chart(placed: placed);
        addTearDown(c.dispose);
        c.selectOnly("c");
        var stage = await pump(tester, c);
        ChartElement now() => c.document.elementById("c")! as ChartElement;
        var at = stage
            .toStagePoint(chartLegendRects(now(), now().bounds)[1].$2.center);

        await drag(tester, at, const Offset(60, 0));
        expect(now().data.series[1].hidden, isFalse);
        if (placed) {
          expect(now().x, 40, reason: "the key moved, not the chart");
        } else {
          expect(now().x, greaterThan(40));
        }
        settled(stage, c, "dragged");
        c.undo();

        await pressAndCancel(tester, at);
        expect(now().data.series[1].hidden, isFalse);
        settled(stage, c, "cancelled");

        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(now().data.series[1].hidden, isTrue);
        expect(now().x, 40);
        settled(stage, c, "clicked");
      });
    }

    testWidgets("a chart key's entry held, then cancelled", (tester) async {
      // Held, the press takes the key instead; cancelled then, it is ended
      // as a key dragged is, its undo step closed.
      var c = chart();
      addTearDown(c.dispose);
      c.selectOnly("c");
      var stage = await pump(tester, c);
      ChartElement now() => c.document.elementById("c")! as ChartElement;
      var at = stage
          .toStagePoint(chartLegendRects(now(), now().bounds)[1].$2.center);

      var g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(now().legend.hasPlace, isTrue, reason: "the hold took the key");
      await g.cancel();
      await tester.pumpAndSettle();
      expect(now().data.series[1].hidden, isFalse);
      settled(stage, c, "cancelled");
    });

    testWidgets("an instrument's key, sounding while held", (tester) async {
      var made =
          newInstrument(const CanvasDocument(frames: 240, frameRate: 24));
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [made]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.selectOnly(made.id);
      var stage = await pump(tester, c);
      var layout = keyboardLayout(made.instrument!, made.bounds);
      var white = layout.keys.where((k) => !k.black).elementAt(3);
      // Low on a white key, below the black ones and clear of the handles.
      var at = stage.toStagePoint(Offset(
          white.rect.center.dx, white.rect.bottom - white.rect.height * 0.15));
      double x() => c.document.elementById(made.id)!.x;

      // Dragged: the note stops as the press travels, and the keys move.
      var g = await tester.startGesture(at);
      await tester.pump();
      expect(c.heldKeys(made.id), {white.key}, reason: "sounding");
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(c.heldKeys(made.id), isEmpty, reason: "let go on travelling");
      await g.moveBy(const Offset(30, 0));
      await g.up();
      await tester.pumpAndSettle();
      expect(x(), greaterThan(made.x));
      settled(stage, c, "dragged");
      c.undo();

      g = await tester.startGesture(at);
      await tester.pump();
      expect(c.heldKeys(made.id), {white.key});
      await g.cancel();
      await tester.pumpAndSettle();
      expect(c.heldKeys(made.id), isEmpty, reason: "cancelled, let go");
      settled(stage, c, "cancelled");

      g = await tester.startGesture(at);
      await tester.pump();
      expect(c.heldKeys(made.id), {white.key});
      await g.up();
      await tester.pumpAndSettle();
      expect(c.heldKeys(made.id), isEmpty, reason: "clicked, let go");
      expect(x(), made.x);
      settled(stage, c, "clicked");
      expect(c.canUndo, isFalse, reason: "a key played is not a change");
    });

    testWidgets("a Code panel's code, opened for typing", (tester) async {
      var c = CanvasController(
          const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == "web"));
      c.clearSelection();
      var stage = await pump(tester, c);
      CodeElement code() => c.document.elements.whereType<CodeElement>().single;
      var start = code().x;
      var at = stage
          .toStagePoint(codeBoxes(code(), code().bounds).panes[0].code.center);

      await drag(tester, at, const Offset(60, 0));
      expect(c.codeEditing, isNull);
      expect(code().x, greaterThan(start));
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      expect(c.codeEditing, isNull);
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(c.codeEditing, (code().id, 0));
      expect(code().x, start);
      settled(stage, c, "clicked");
    });

    testWidgets("a reused element's copy, picked", (tester) async {
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
                      ElementInstance("i2", dx: 500),
                    ]))),
                fill: Color(0xFF000000)),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      var at = stage.toStagePoint(const Offset(400, 150));

      await drag(tester, at, const Offset(0, 40));
      expect(c.pickedCopiesOf("a"), isEmpty);
      expect(c.document.elementById("a")!.y, greaterThan(100),
          reason: "dragged, all of them move");
      settled(stage, c, "dragged");
      c.undo();

      await pressAndCancel(tester, at);
      expect(c.pickedCopiesOf("a"), isEmpty);
      settled(stage, c, "cancelled");

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(c.pickedCopiesOf("a"), {"i1"});
      expect(c.document.elementById("a")!.y, 100);
      settled(stage, c, "clicked");
    });
  });

  group("a square or a circle resized", () {
    // Outlined, rounded, padded and worded, so a resize that scaled its
    // inside would show in each.
    ShapeElement regular(ShapeKind kind, {bool held = false}) => ShapeElement(
        ElementBase(
            id: "s", x: 400, y: 200, width: 200, height: 200, lockAspect: held),
        shape: kind,
        strokeWidth: 6,
        cornerRadius: 10,
        padding: 8,
        text: "Hi",
        textSpec: const TextSpec(fontSize: 20));

    /// resized pulls [e]'s bottom-right corner 100 right and 20 down, with
    /// Shift held where [shift] says, and hands back what it is then.
    Future<ShapeElement> resized(WidgetTester tester, ShapeElement e,
        {bool shift = false}) async {
      var c = CanvasController(CanvasDocument(
          guides: const CanvasGuides(snap: false), elements: [e]));
      addTearDown(c.dispose);
      c.selectOnly("s");
      var stage = await pump(tester, c);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      var scale = stage.pageRect.width / c.document.size.width;
      await drag(tester, stage.handleAt(StageHandle.bottomRight),
          const Offset(100, 20) * scale);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      settled(stage, c, "resized");
      return c.document.elementById("s") as ShapeElement;
    }

    void expectInsideAsItWas(ShapeElement s) {
      expect(s.strokeWidth, 6, reason: "its outline its own weight");
      expect(s.cornerRadius, 10);
      expect(s.padding, 8);
      expect(s.textSpec.fontSize, 20);
    }

    void expectInsideScaled(ShapeElement s) {
      var by = s.width / 200;
      expect(by, greaterThan(1.1), reason: "it grew");
      expect(s.strokeWidth, closeTo(6 * by, 1e-6));
      expect(s.cornerRadius, closeTo(10 * by, 1e-6));
      expect(s.padding, closeTo(8 * by, 1e-6));
      expect(s.textSpec.fontSize, closeTo(20 * by, 1e-6));
    }

    for (var kind in [ShapeKind.square, ShapeKind.circle]) {
      testWidgets("a ${kind.name} stays square, its inside its own size",
          (tester) async {
        var s = await resized(tester, regular(kind));
        expect(s.width, greaterThan(250), reason: "it grew");
        expect(s.height, closeTo(s.width, 1e-6), reason: "and stayed square");
        expectInsideAsItWas(s);
      });

      testWidgets("a ${kind.name} with Shift held stays square, inside scaled",
          (tester) async {
        var s = await resized(tester, regular(kind), shift: true);
        expect(s.height, closeTo(s.width, 1e-6), reason: "square still");
        expectInsideScaled(s);
      });

      testWidgets("a ${kind.name} the person holds scales its inside",
          (tester) async {
        var s = await resized(tester, regular(kind, held: true));
        expect(s.height, closeTo(s.width, 1e-6));
        expectInsideScaled(s);
      });

      testWidgets(
          "a ${kind.name} the person holds, with Shift, keeps its inside",
          (tester) async {
        var s = await resized(tester, regular(kind, held: true), shift: true);
        expect(s.height, closeTo(s.width, 1e-6), reason: "square still");
        expectInsideAsItWas(s);
      });
    }

    testWidgets("a rectangle the person holds still scales its inside",
        (tester) async {
      var s = await resized(tester, regular(ShapeKind.rectangle, held: true));
      expect(s.height, closeTo(s.width, 1e-6));
      expectInsideScaled(s);
    });

    testWidgets("a rectangle let go is stretched, its inside its own size",
        (tester) async {
      var s = await resized(tester, regular(ShapeKind.rectangle));
      expect(s.width - s.height, greaterThan(50), reason: "pulled oblong");
      expectInsideAsItWas(s);
    });

    testWidgets("a rectangle let go, with Shift, is held and scaled inside",
        (tester) async {
      var s = await resized(tester, regular(ShapeKind.rectangle), shift: true);
      expect(s.height, closeTo(s.width, 1e-6));
      expectInsideScaled(s);
    });
  });

  group("the box resized on a frame part-way through a move", () {
    // Keyed from rest on frame 0 to 200 across and 100 down on frame 20, and
    // selected on frame 10, where it is drawn 100 across and 50 down.
    var moved = ShapeElement(
        ElementBase(
            id: "s",
            x: 400,
            y: 200,
            width: 300,
            height: 200,
            track: ElementTrack(const [
              Keyframe(frame: 0),
              Keyframe(frame: 20, dx: 200, dy: 100),
            ])),
        fill: const Color(0xFFCC2200));

    testWidgets("keeps the corner opposite the one pulled where it is drawn",
        (tester) async {
      var c = CanvasController(CanvasDocument(
          frames: 24,
          guides: const CanvasGuides(snap: false),
          elements: [moved]));
      addTearDown(c.dispose);
      c.frame = 10;
      c.selectOnly("s");
      var stage = await pump(tester, c);
      Rect drawn() =>
          c.document.elementById("s")!.movedBoundsAt(10, c.document);
      var before = drawn();
      expect(before.topLeft, const Offset(500, 250));
      await drag(tester, stage.handleAt(StageHandle.bottomRight),
          const Offset(60, 40));
      var after = drawn();
      expect(after.topLeft.dx, closeTo(before.left, 0.5),
          reason: "the held corner stays where it is drawn");
      expect(after.topLeft.dy, closeTo(before.top, 0.5));
      expect(after.width, greaterThan(before.width), reason: "it grew");
      expect(c.document.elementById("s")!.track, moved.track,
          reason: "a resize sizes the element, not its pose");
      settled(stage, c, "resized");
    });
  });
}
