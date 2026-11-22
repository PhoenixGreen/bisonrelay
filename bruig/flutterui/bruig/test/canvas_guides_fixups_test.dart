import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_rulers.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_parts.dart';

import 'support/canvas_app.dart';

// canvas_guides_fixups_test.dart holds the rules of the marks drawn over the
// page, each as the person pressing sees them: what is pressed is what is
// drawn on top, a guide is taken only where it is drawn, a click on a ruler
// or a guide pulled out and dropped back changes nothing, a guide follows
// the pointer however slowly it moves, a chart's labels show a grip only
// where one sizes them, a table's rules are taken only where their grips
// are drawn, a camera is caught where its frame is drawn and nowhere else,
// and the grid and guides keep out of the way while the canvas plays or is
// seen through its camera.

const _viewport = Size(1280, 800);

void main() {
  /// pump shows [controller] on a stage and hands back its state.
  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller,
      {bool settle = true}) async {
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(key: key, controller: controller))));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return key.currentState!;
  }

  /// painted is the stage's page painter as last built.
  StagePainter painted(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .expand((p) => [p.painter, p.foregroundPainter])
      .whereType<StagePainter>()
      .first;

  /// shot is the pixels the stage's page painter draws, as RGBA.
  Future<ByteData> shot(WidgetTester tester) async {
    var painter = painted(tester);
    late ByteData data;
    await tester.runAsync(() async {
      var recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), _viewport);
      var image = await recorder
          .endRecording()
          .toImage(_viewport.width.round(), _viewport.height.round());
      data = (await image.toByteData())!;
    });
    return data;
  }

  int pixel(ByteData data, int x, int y) =>
      data.getUint32((y * _viewport.width.round() + x) * 4);

  /// lineAt is whether an upright line is drawn through [at]: a pixel
  /// beside it differs from one well clear of it.
  bool lineAt(ByteData data, Offset at) {
    var y = at.dy.round();
    var clear = pixel(data, at.dx.round() + 8, y);
    for (var x = at.dx.round() - 1; x <= at.dx.round() + 1; x++) {
      if (pixel(data, x, y) != clear) return true;
    }
    return false;
  }

  /// cursor is the pointer's look over the stage's page.
  MouseCursor cursor() =>
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

  // Where the left ruler is: against the page's left edge, half a strip in
  // from it, and never off the screen.
  Offset leftStrip(CanvasStageState stage) => Offset(
      math.max(rulerThickness / 2, stage.pageRect.left - rulerThickness / 2),
      stage.pageRect.center.dy);

  // The rulers are the person's, set on the controller as the page sets
  // them from the preferences.
  const ruled = CanvasRulers(top: true, left: true);

  CanvasController guided(CanvasGuides guides,
      [List<CanvasElement> elements = const []]) {
    var doc = const CanvasDocument().copyWith(guides: guides);
    for (var e in elements) {
      doc = doc.addElement(e);
    }
    var c = CanvasController(doc);
    addTearDown(c.dispose);
    return c;
  }

  double scaleOf(CanvasStageState stage, CanvasController c) =>
      stage.pageRect.width / c.document.size.width;

  group("a guide dragged", () {
    testWidgets("in small steps, follows the pointer", (tester) async {
      // Snapping to its own last place, each step a few pixels long fell back
      // onto where it was, so the guide lagged and jumped.
      var c = guided(const CanvasGuides(
          guides: [CanvasGuide(axis: GuideAxis.vertical, at: 400)]));
      var stage = await pump(tester, c);
      var scale = scaleOf(stage, c);
      var g = await tester.startGesture(
          stage.toStagePoint(Offset(400, c.document.size.height / 2)));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(3, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(c.document.guides.guides.single.at, closeTo(400 + 60 / scale, 1));
    });
  });

  group("a press where a guide is drawn", () {
    testWidgets("on a selected element's handle, takes the handle",
        (tester) async {
      // An edge snapped to a guide puts its handles on it. The handles are
      // drawn over the guide, so they are what a press there takes.
      const shape = ShapeElement(
          ElementBase(id: "s", x: 400, y: 200, width: 300, height: 200));
      var c = guided(
          const CanvasGuides(
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 400)]),
          [shape]);
      c.selectOnly("s");
      var stage = await pump(tester, c);
      await tester.dragFrom(
          stage.toStagePoint(const Offset(400, 300)), const Offset(-40, 0));
      await tester.pumpAndSettle();
      var after = c.document.elementById("s")!;
      expect(after.width, greaterThan(shape.width + 20),
          reason: "the left handle sized the element");
      expect(c.document.guides.guides.single.at, 400,
          reason: "and the guide stayed");
    });

    testWidgets("off the page, where it is not drawn, does not take it",
        (tester) async {
      var c = guided(const CanvasGuides(
          guides: [CanvasGuide(axis: GuideAxis.vertical, at: 400)]));
      var stage = await pump(tester, c);
      expect(stage.pageRect.top, greaterThan(16),
          reason: "the test needs room above the page");
      var above = Offset(
          stage.toStagePoint(const Offset(400, 0)).dx, stage.pageRect.top - 12);
      await tester.dragFrom(above, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(c.document.guides.guides.single.at, 400);
    });

    testWidgets("by two guides, takes the nearer", (tester) async {
      var c = guided(const CanvasGuides(guides: [
        CanvasGuide(axis: GuideAxis.vertical, at: 400),
        CanvasGuide(axis: GuideAxis.vertical, at: 403),
      ]));
      var stage = await pump(tester, c);
      await tester.dragFrom(
          stage.toStagePoint(const Offset(403, 300)), const Offset(60, 0));
      await tester.pumpAndSettle();
      var at = c.document.guides.guides.map((g) => g.at).toList();
      expect(at.first, 400, reason: "the further one stayed");
      expect(at.last, greaterThan(430), reason: "the nearer one moved");
    });
  });

  group("a ruler", () {
    testWidgets("dragged from with guides hidden, shows them and makes one",
        (tester) async {
      var c = guided(const CanvasGuides(showGuides: false))..rulers = ruled;
      var stage = await pump(tester, c);
      await tester.dragFrom(leftStrip(stage), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(c.document.guides.guides.single.axis, GuideAxis.vertical);
      expect(c.document.guides.showGuides, isTrue);
      expect(c.selection, isEmpty);
      c.undo();
      expect(c.document.guides.guides, isEmpty,
          reason: "one undo takes back the guide");
      expect(c.document.guides.showGuides, isFalse, reason: "and the showing");
    });

    for (var shown in [true, false]) {
      var how = shown ? "shown" : "hidden";
      testWidgets(
          "pulled out and dropped back on it, with guides $how, changes "
          "nothing", (tester) async {
        var c = guided(CanvasGuides(showGuides: shown))..rulers = ruled;
        var stage = await pump(tester, c);
        expect(stage.pageRect.left, greaterThan(rulerThickness),
            reason: "the test needs the ruler off the page");
        var g = await tester.startGesture(leftStrip(stage));
        await tester.pump();
        await g.moveBy(const Offset(120, 0));
        await tester.pump();
        expect(c.document.guides.guides, hasLength(1),
            reason: "a guide is pulled out");
        await g.moveBy(const Offset(-120, 0));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
        expect(c.document.guides.guides, isEmpty);
        expect(c.document.guides.showGuides, shown);
        expect(c.canUndo, isFalse, reason: "no undo step");
      });

      testWidgets("clicked, with guides $how, changes nothing", (tester) async {
        var c = guided(CanvasGuides(showGuides: shown))..rulers = ruled;
        var stage = await pump(tester, c);
        expect(c.canUndo, isFalse);
        expect(c.dirty, isFalse);
        await tester.tapAt(leftStrip(stage));
        await tester.pumpAndSettle();
        expect(c.document.guides.guides, isEmpty);
        expect(c.document.guides.showGuides, shown);
        expect(c.canUndo, isFalse, reason: "no undo step");
        expect(c.dirty, isFalse, reason: "the canvas is not changed");
      });
    }
  });

  group("a chart's labels", () {
    /// chart is a floating-labelled chart with a title and a key, inset in
    /// the page so its labels' corners are clear of its own handles.
    ChartElement chart({bool locked = false}) => ChartElement(
          ElementBase(
              id: "c", x: 200, y: 120, width: 800, height: 460, locked: locked),
          title: "Title",
          titleBox: const ChartLabel(x: 0.1, y: 0.1, width: 0.3, height: 0.12),
          floatingLabels: true,
          showLegend: true,
          data: ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
        );

    testWidgets("show a resize grip only on a label that resizes",
        (tester) async {
      // The key is moved but never sized: a grip on it did nothing.
      var e = chart();
      var c = guided(const CanvasGuides(), [e]);
      c.selectOnly("c");
      var stage = await pump(tester, c);
      var places = chartLabelPlaces(e, e.bounds);
      var data = await shot(tester);
      // Inside the grip's square, outside the label's own outline.
      int at(Rect r) {
        var p = stage.toStagePoint(r.bottomRight) + const Offset(1.5, 1.5);
        return pixel(data, p.dx.floor(), p.dy.floor());
      }

      const grip = 0x3D7EFFFF;
      expect(at(places[ChartLabelPart.title]!), grip,
          reason: "the title has its grip");
      expect(at(places[ChartLabelPart.legend]!), isNot(grip),
          reason: "the key has none");
    });

    testWidgets("are not outlined on a locked chart, which cannot take them",
        (tester) async {
      var c = guided(const CanvasGuides(), [chart(locked: true)]);
      c.selectOnly("c");
      await pump(tester, c);
      expect(painted(tester).inputs.elements.chartLabels, isEmpty);
    });

    testWidgets("with helpers hidden, are neither drawn nor taken",
        (tester) async {
      var e = chart();
      var c = guided(const CanvasGuides(), [e]);
      c.selectOnly("c");
      c.showHelpers = false;
      var stage = await pump(tester, c);
      expect(painted(tester).inputs.elements.chartLabels, isEmpty);
      var title = chartLabelPlaces(e, e.bounds)[ChartLabelPart.title]!;
      await tester.dragFrom(
          stage.toStagePoint(title.center), const Offset(60, 40));
      await tester.pumpAndSettle();
      var after = c.document.elementById("c") as ChartElement;
      expect(after.titleBox.x, e.titleBox.x, reason: "the title was not taken");
    });
  });

  group("a table's column rules", () {
    /// table is two even columns, their rule at x 400.
    TableElement table() => TableElement(
          const ElementBase(id: "t", x: 200, y: 200, width: 400, height: 200),
          rows: const [
            ["One", "Two"],
            ["Three", "Four"],
          ],
          columnWidths: const [1, 1],
        );

    double rule(CanvasController c) {
      var e = c.document.elementById("t") as TableElement;
      return tableColumnDividers(e, e.bounds).single;
    }

    testWidgets("with helpers hidden, are neither drawn nor taken",
        (tester) async {
      var c = guided(const CanvasGuides(), [table()]);
      c.selectOnly("t");
      c.showHelpers = false;
      var stage = await pump(tester, c);
      expect(painted(tester).inputs.elements.tableColumns, isEmpty);
      var at = rule(c);
      await tester.dragFrom(
          stage.toStagePoint(Offset(at, 300)), const Offset(60, 0));
      await tester.pumpAndSettle();
      var after = c.document.elementById("t") as TableElement;
      expect(after.columnWidths, [1, 1], reason: "the rule was not taken");
    });
  });

  group("a mark drawn over a guide", () {
    testWidgets("a table column rule's grip takes the press", (tester) async {
      // The rule a quarter across, clear of the table's own top handle.
      var e = TableElement(
        const ElementBase(id: "t", x: 200, y: 200, width: 400, height: 200),
        rows: const [
          ["One", "Two"],
        ],
        columnWidths: const [1, 3],
      );
      var at = tableColumnDividers(e, e.bounds).single;
      var c = guided(
          CanvasGuides(guides: [CanvasGuide(axis: GuideAxis.vertical, at: at)]),
          [e]);
      c.selectOnly("t");
      var stage = await pump(tester, c);
      // The grip drawn just inside the rule's top end.
      var grip = stage.toStagePoint(Offset(at, 200)) + const Offset(0, 5);
      await tester.dragFrom(grip, const Offset(60, 0));
      await tester.pumpAndSettle();
      var after = c.document.elementById("t") as TableElement;
      var [left, right] = after.columnWidths;
      expect(left / (left + right), greaterThan(0.3), reason: "the rule moved");
      expect(c.document.guides.guides.single.at, at,
          reason: "and the guide stayed");
    });

    testWidgets("a chart label's resize grip takes the press", (tester) async {
      var e = ChartElement(
        const ElementBase(id: "c", x: 200, y: 120, width: 800, height: 460),
        title: "Title",
        titleBox: const ChartLabel(x: 0.1, y: 0.1, width: 0.3, height: 0.12),
        floatingLabels: true,
        data: ChartData.parse("Cat\tOne\n2019\t10\n2020\t20"),
      );
      var title = chartLabelPlaces(e, e.bounds)[ChartLabelPart.title]!;
      var corner = title.bottomRight;
      var c = guided(
          CanvasGuides(
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: corner.dx)]),
          [e]);
      c.selectOnly("c");
      var stage = await pump(tester, c);
      await tester.dragFrom(stage.toStagePoint(corner), const Offset(60, 40));
      await tester.pumpAndSettle();
      var after = c.document.elementById("c") as ChartElement;
      expect(after.titleBox.width, greaterThan(e.titleBox.width),
          reason: "the title was sized");
      expect(c.document.guides.guides.single.at, corner.dx,
          reason: "and the guide stayed");
    });

    testWidgets("a Layout's cut knob takes the press", (tester) async {
      var l = LayoutElement(
          const ElementBase(id: "L", x: 100, y: 100, width: 600, height: 500),
          root: LayoutNode.cut(
              vertical: true,
              a: const LayoutNode.leaf("a"),
              b: const LayoutNode.leaf("b")),
          cells: const [LayoutCell(id: "a"), LayoutCell(id: "b")],
          gutter: 20,
          rowGutter: 20);
      var line = layoutCutLines(l, l.bounds).single;
      // The ring that tilts the cut, near its end.
      var knob = Offset.lerp(line.from, line.to, 0.88)!;
      var c = guided(
          CanvasGuides(
              guides: [CanvasGuide(axis: GuideAxis.horizontal, at: knob.dy)]),
          [l]);
      c.selectOnly("L");
      var stage = await pump(tester, c);
      await tester.dragFrom(stage.toStagePoint(knob), const Offset(100, 40));
      await tester.pumpAndSettle();
      var after = c.document.elementById("L") as LayoutElement;
      expect(after.root.tilt, isNot(0), reason: "the cut tilted");
      expect(c.document.guides.guides.single.at, knob.dy,
          reason: "and the guide stayed");
    });
  });

  group("a camera whose frame is not drawn", () {
    // A camera is taken by its frame, so where the frame is not drawn there
    // is nothing to take.
    const cam = CameraElement(
        ElementBase(id: "cam", x: 320, y: 180, width: 640, height: 360));
    // The middle of its top edge.
    const edge = Offset(640, 180);

    testWidgets("with helpers hidden, is not taken", (tester) async {
      var c = guided(const CanvasGuides(), [cam]);
      c.showHelpers = false;
      var stage = await pump(tester, c);
      await tester.tapAt(stage.toStagePoint(edge));
      await tester.pumpAndSettle();
      expect(c.selection, isNot(contains("cam")));
    });

    testWidgets("on a 3D stage, is not taken", (tester) async {
      var c = guided(const CanvasGuides(), [
        BackgroundElement(
            const ElementBase(id: "st", x: 0, y: 0, width: 1280, height: 720),
            backdrop: BackdropKind.stage,
            stage: StageElement(const ElementBase(id: ""))),
        cam,
      ]);
      var stage = await pump(tester, c);
      await tester.tapAt(stage.toStagePoint(edge));
      await tester.pumpAndSettle();
      expect(c.selection, isNot(contains("cam")));
    });
  });

  group("a turned camera", () {
    testWidgets("is caught on its frame as drawn, turned", (tester) async {
      // The frame is drawn turned by the camera's roll; a press on that
      // drawn edge, away from where the unturned edge would be, takes it.
      var c = guided(const CanvasGuides(), [
        const CameraElement(ElementBase(
            id: "cam", x: 320, y: 180, width: 640, height: 360, rotation: 30)),
      ]);
      var stage = await pump(tester, c);
      // The top edge's middle, turned 30 degrees clockwise about the centre.
      const centre = Offset(640, 360);
      var turn = 30 * math.pi / 180;
      var edge = centre + Offset(180 * math.sin(turn), -180 * math.cos(turn));
      await tester.tapAt(stage.toStagePoint(edge));
      await tester.pumpAndSettle();
      expect(c.selection, {"cam"}, reason: "on the drawn edge");

      // Where the unturned edge would be is inside the turned frame.
      c.clearSelection();
      await tester.tapAt(stage.toStagePoint(const Offset(560, 180)));
      await tester.pumpAndSettle();
      expect(c.selection, isEmpty, reason: "not on the drawn edge");
    });
  });

  group("while the canvas plays", () {
    // The grid and guides are fixed to the page as edited, which the
    // scene's camera moves while it plays, so they keep out of the way.
    const shape = ShapeElement(
        ElementBase(id: "s", x: 900, y: 500, width: 100, height: 100));
    const scaffolding = CanvasGuides(
        showGrid: true,
        gridSize: 100,
        guides: [CanvasGuide(axis: GuideAxis.vertical, at: 330)]);

    CanvasController playable() {
      var doc = const CanvasDocument()
          .copyWith(guides: scaffolding, frames: 96, frameRate: 24, game: true)
          .addElement(shape);
      var c = CanvasController(doc)..rulers = ruled;
      addTearDown(c.dispose);
      return c;
    }

    Future<void> stop(WidgetTester tester, CanvasController c) async {
      c.gaming = false;
      c.pause();
      c.stopPreview();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    final modes = <String, void Function(CanvasController)>{
      "playing": (c) => c.play(),
      "in a game": (c) => c.gaming = true,
      "previewing an element": (c) => c.previewElement("s"),
      "previewing a transition": (c) {
        c.addScene();
        c.previewTransitionAfter(0);
      },
    };

    for (var mode in modes.entries) {
      testWidgets("${mode.key}, no grid or guide is drawn", (tester) async {
        var c = playable();
        var stage = await pump(tester, c, settle: false);
        Offset onPage(double x) => Offset(
            stage.toStagePoint(Offset(x, 0)).dx, stage.pageRect.center.dy);
        var editing = await shot(tester);
        expect(lineAt(editing, onPage(330)), isTrue,
            reason: "editing, the guide is drawn");
        expect(lineAt(editing, onPage(200)), isTrue,
            reason: "editing, the grid is drawn");

        mode.value(c);
        await tester.pump(const Duration(milliseconds: 50));
        var playing = await shot(tester);
        expect(lineAt(playing, onPage(330)), isFalse,
            reason: "${mode.key}, no guide");
        expect(lineAt(playing, onPage(200)), isFalse,
            reason: "${mode.key}, no grid");
        await stop(tester, c);
      });
    }

    testWidgets("in camera view, no grid or guide is drawn", (tester) async {
      // Looking through the camera while editing draws the page moved, as
      // playing does.
      var doc = const CanvasDocument().copyWith(guides: scaffolding).addElement(
          const CameraElement(
              ElementBase(id: "cam", x: 320, y: 180, width: 640, height: 360)));
      var c = CanvasController(doc)..rulers = ruled;
      addTearDown(c.dispose);
      var stage = await pump(tester, c);
      Offset onPage(double x) =>
          Offset(stage.toStagePoint(Offset(x, 0)).dx, stage.pageRect.center.dy);
      var editing = await shot(tester);
      expect(lineAt(editing, onPage(330)), isTrue,
          reason: "editing, the guide is drawn");
      expect(lineAt(editing, onPage(200)), isTrue,
          reason: "editing, the grid is drawn");

      c.cameraView = true;
      await tester.pumpAndSettle();
      var looking = await shot(tester);
      expect(lineAt(looking, onPage(330)), isFalse, reason: "no guide");
      expect(lineAt(looking, onPage(200)), isFalse, reason: "no grid");
    });

    for (var mode in ["playing", "in a game"]) {
      testWidgets("$mode, a ruler makes no guide and a guide is not taken",
          (tester) async {
        var c = playable();
        var stage = await pump(tester, c, settle: false);
        modes[mode]!(c);
        await tester.pump(const Duration(milliseconds: 50));

        var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: stage.pageRect.center);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(leftStrip(stage));
        await tester.pump(const Duration(milliseconds: 20));
        expect(cursor(), isNot(SystemMouseCursors.resizeLeftRight),
            reason: "no drag is offered");

        var g = await tester.startGesture(leftStrip(stage));
        await g.moveBy(const Offset(90, 0));
        await tester.pump(const Duration(milliseconds: 20));
        await g.moveBy(const Offset(90, 0));
        await tester.pump(const Duration(milliseconds: 20));
        await g.up();
        await tester.pump(const Duration(milliseconds: 20));
        expect(c.document.guides.guides.length, 1, reason: "no new guide");

        g = await tester
            .startGesture(stage.toStagePoint(const Offset(330, 300)));
        await g.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 20));
        await g.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 20));
        await g.up();
        await tester.pump(const Duration(milliseconds: 20));
        expect(c.document.guides.guides.single.at, 330,
            reason: "the guide was not taken");
        await stop(tester, c);
      });
    }
  });
}
