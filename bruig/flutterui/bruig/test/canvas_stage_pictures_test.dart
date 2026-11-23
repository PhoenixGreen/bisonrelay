import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_transform.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';
import 'support/kept_pictures.dart';

// canvas_stage_pictures_test.dart keeps what the stage's painter draws, to
// the byte, in each of a few dozen states that between them reach every
// part of the paint: a selection, copies, a trail, every mark on elements,
// every tool's marks, the retouching brush, the guides and rulers, a facing
// page and a transition. It is the proof that a change meant only to move
// painting code (into other files, functions or helpers) draws exactly what
// it drew before.
//
// To use it, set STAGE_PICTURES to a folder and run this file on the code
// as it is: each state's picture is written there. Run it again to see
// that every picture is stable from run to run. Then make the change and
// run it after each step: a state whose picture differs fails, saying how
// many pixels changed and where, and leaves the new picture beside the
// kept one as <state>.new.png. Without STAGE_PICTURES each state is still
// drawn and checked to reach the mark it is for, and nothing is kept, so
// the test is harmless in the whole suite.
//
// Most states are set up on a real stage through the controller or a real
// gesture held part way. The marks of a tool whose session needs a decoded
// picture or a brush held (a picture's layers, a warp grid, a picture being
// reframed, the retouching preview and stroke, a drawing's text caret), the
// text being typed into, a transition being watched, a game's level and
// change of scene, a held marker's label, the page seen through the
// scene's camera and two copies picked inside the box round them all are
// given to the real stage's painter by changing that one value of its
// inputs.

const _viewport = Size(800, 600);

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

  /// painted is the stage's page painter as last built.
  StagePainter painted(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .expand((p) => [p.painter, p.foregroundPainter])
      .whereType<StagePainter>()
      .first;

  /// keep draws the stage's painter, with its inputs changed by [alter], and
  /// compares the picture with the one kept as [name], or keeps it.
  Future<void> keep(WidgetTester tester, String name,
      {StageInputs Function(StageInputs)? alter}) async {
    var inputs = painted(tester).inputs;
    if (alter != null) inputs = alter(inputs);
    var painter = StagePainter(inputs);
    late Uint8List raw;
    late Uint8List png;
    await tester.runAsync(() async {
      var recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), _viewport);
      (raw, png) = await imageBytes(await recorder
          .endRecording()
          .toImage(_viewport.width.round(), _viewport.height.round()));
    });
    expect(tester.takeException(), isNull);
    keepOrCompare("STAGE_PICTURES", name,
        raw: raw, png: png, width: _viewport.width.round());
  }

  /// withInputs is [i] with the values given in place of its own.
  StageInputs withInputs(StageInputs i,
          {StageTransform? transform,
          StageShown? shown,
          StageSelectionMarks? selection,
          StageToolMarks? tools,
          StageRetouchMarks? retouch,
          StageTextEdit? text}) =>
      (
        transform: transform ?? i.transform,
        shown: shown ?? i.shown,
        live: i.live,
        selection: selection ?? i.selection,
        elements: i.elements,
        tools: tools ?? i.tools,
        retouch: retouch ?? i.retouch,
        guides: i.guides,
        text: text ?? i.text,
      );

  /// withTools is [i]'s tool marks with the values given in place of its own.
  StageToolMarks withTools(StageToolMarks i,
          {StageLayers? layers,
          StageFraming? framing,
          (Offset, Offset)? caret}) =>
      (
        vector: i.vector,
        layers: layers ?? i.layers,
        framing: framing ?? i.framing,
        knife: i.knife,
        caret: caret ?? i.caret,
        marquee: i.marquee,
      );

  /// withShown is [i] with the values given in place of its own.
  StageShown withShown(StageShown i,
          {int? previewAt,
          (double, Offset)? camera,
          (
            CanvasDocument,
            int,
            SceneTransition,
            double,
            LiveMotion
          )? gameChange,
          TimelineAction? markerNote}) =>
      (
        document: i.document,
        frame: i.frame,
        facing: i.facing,
        previewAt: previewAt ?? i.previewAt,
        previewing: i.previewing,
        gameChange: gameChange ?? i.gameChange,
        camera: camera ?? i.camera,
        directed: i.directed,
        markerNote: markerNote ?? i.markerNote,
        markerNoteGrip: i.markerNoteGrip,
      );

  /// picture is a small picture with something in it, made afresh.
  Future<ui.Image> picture(WidgetTester tester) async {
    late ui.Image made;
    await tester.runAsync(() async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 64, 48),
          Paint()..color = const Color(0xFF2E7D32));
      canvas.drawCircle(
          const Offset(32, 24), 14, Paint()..color = const Color(0xFFFFC107));
      canvas.drawRect(const Rect.fromLTWH(0, 0, 20, 10),
          Paint()..color = const Color(0xFFD81B60));
      made = await recorder.endRecording().toImage(64, 48);
    });
    addTearDown(made.dispose);
    return made;
  }

  CanvasController controllerOf(CanvasDocument doc, {bool audio = false}) {
    var c = audio
        ? CanvasController(doc, audioEngine: FakeEngine(const {}))
        : CanvasController(doc);
    addTearDown(c.dispose);
    return c;
  }

  ShapeElement box(String id, double x, double y, double w, double h,
          {double rotation = 0,
          double skewX = 0,
          bool anchorLocked = false,
          PlaySpec play = const PlaySpec(),
          Color fill = const Color(0xFF3D7EFF)}) =>
      ShapeElement(
          ElementBase(
              id: id,
              x: x,
              y: y,
              width: w,
              height: h,
              rotation: rotation,
              skewX: skewX,
              anchorLocked: anchorLocked,
              play: play),
          fill: fill);

  CanvasDocument docOf(List<CanvasElement> elements,
      {CanvasGuides guides = const CanvasGuides()}) {
    var doc = const CanvasDocument().copyWith(guides: guides);
    for (var e in elements) {
      doc = doc.addElement(e);
    }
    return doc;
  }

  /// drawing is a drawing of a square and a curve, 300 across at (300, 200).
  VectorElement drawing() {
    var parts = importSvg('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 100 100">'
        '<path d="M10 10 L60 10 L60 60 L10 60 Z" fill="red"/>'
        '<path d="M40 80 C40 30 95 30 95 80" stroke="blue" fill="none"/>'
        '</svg>')!;
    return VectorElement(
        const ElementBase(id: "v", x: 300, y: 200, width: 300, height: 300),
        assetId: "0123456789abcdef.svg",
        viewBox: parts.viewBox,
        shapes: parts.shapes);
  }

  group("a selection", () {
    testWidgets("one element", (tester) async {
      var c = controllerOf(
          docOf([box("a", 300, 200, 400, 250), box("b", 900, 500, 200, 200)]));
      c.selectOnly("a");
      await pump(tester, c);
      expect(painted(tester).inputs.selection.bounds, isNotNull);
      await keep(tester, "selection_one");
    });

    testWidgets("one turned and slanted", (tester) async {
      var c = controllerOf(
          docOf([box("t", 500, 300, 400, 250, rotation: 25, skewX: 0.3)]));
      c.selectOnly("t");
      await pump(tester, c);
      await keep(tester, "selection_turned");
    });

    testWidgets("several, each outlined", (tester) async {
      var c = controllerOf(docOf([
        box("a", 200, 200, 300, 200),
        box("b", 400, 300, 300, 200, rotation: 15),
        box("c", 900, 500, 200, 200),
      ]));
      c.selectMany({"a", "b", "c"});
      await pump(tester, c);
      expect(painted(tester).inputs.selection.ids, hasLength(3));
      await keep(tester, "selection_several");
    });

    testWidgets("every element's box shown", (tester) async {
      var c = controllerOf(docOf([
        box("a", 200, 200, 300, 200),
        box("b", 700, 300, 300, 200, rotation: 20, skewX: 0.2),
        box("c", 1200, 500, 200, 200),
      ]));
      c.showAllBounds = true;
      c.selectOnly("a");
      await pump(tester, c);
      await keep(tester, "show_all_bounds");
    });

    testWidgets("with its anchors, one locked", (tester) async {
      var c = controllerOf(docOf([
        box("a", 200, 200, 300, 200),
        box("b", 800, 400, 300, 200, anchorLocked: true),
      ]));
      c.selectMany({"a", "b"});
      c.showAnchor("a", true);
      c.showAnchor("b", true);
      await pump(tester, c);
      expect(painted(tester).inputs.selection.anchors, hasLength(2));
      await keep(tester, "anchors");
    });

    CanvasDocument copies() =>
        CanvasDocument(frames: 240, frameRate: 24, elements: [
          ShapeElement(
              const ElementBase(
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
              fill: const Color(0xFF000000)),
        ]);

    testWidgets("a reused element's copies, all picked", (tester) async {
      var c = controllerOf(copies(), audio: true);
      c.selectOnly("a");
      c.pickAllCopies("a");
      await pump(tester, c);
      expect(painted(tester).inputs.selection.bounds, isNotNull);
      await keep(tester, "copies_all");
    });

    testWidgets("a reused element's copies, two picked", (tester) async {
      // Two picked inside the box round them all, which the stage shows
      // only once a press has picked them: given here instead.
      var c = controllerOf(copies(), audio: true);
      c.selectOnly("a");
      c.pickAllCopies("a");
      await pump(tester, c);
      await keep(tester, "copies_two", alter: (i) {
        var s = i.selection;
        return withInputs(i, selection: (
          ids: s.ids,
          bounds: s.bounds,
          frame: s.frame,
          showHandles: s.showHandles,
          showHelpers: s.showHelpers,
          pickedCopies: EqualSet({"i0", "i2"}),
          trail: s.trail,
          anchors: s.anchors,
        ));
      });
    });

    testWidgets("a reused element's copies, one picked", (tester) async {
      var c = controllerOf(copies(), audio: true);
      c.selectOnly("a");
      c.pickCopies("a", {"i1"});
      await pump(tester, c);
      expect(painted(tester).inputs.selection.pickedCopies, hasLength(1));
      await keep(tester, "copies_one");
    });

    testWidgets("its motion trail and onion skin", (tester) async {
      var c = controllerOf(
          CanvasDocument(frames: 240, frameRate: 24, elements: [
            ShapeElement(
                const ElementBase(
                    id: "a",
                    x: 50,
                    y: 300,
                    width: 40,
                    height: 40,
                    motion: ElementMotion(clips: [
                      MotionClip(
                          id: "go",
                          kind: MotionKind.action,
                          length: 4,
                          keys: {
                            MotionProp.x: [
                              MotionKey(0, MotionNumber(0)),
                              MotionKey(4, MotionNumber(600)),
                            ],
                          }),
                    ], placed: [
                      ClipPlacement(id: "p", clip: "go", length: 4)
                    ])),
                fill: const Color(0xFF000000)),
          ]),
          audio: true);
      c.selectOnly("a");
      c.frame = 48;
      c.animationOpen = true;
      await pump(tester, c);
      expect(painted(tester).inputs.selection.trail, isTrue);
      await keep(tester, "trail");
    });

    testWidgets("previewed from a join, its whole chain faint", (tester) async {
      var c = controllerOf(
          CanvasDocument(frames: 240, frameRate: 24, elements: [
            ShapeElement(
                const ElementBase(
                    id: "a",
                    x: 50,
                    y: 300,
                    width: 40,
                    height: 40,
                    motion: ElementMotion(devices: [
                      MotionDevice(MotionDeviceKind.oscillate,
                          id: "o",
                          values: {"amount": 200, "moves": 1, "phase": 0.25})
                    ])),
                fill: const Color(0xFFFF0000)),
          ]),
          audio: true);
      c.selectOnly("a");
      await pump(tester, c);
      c.previewMotionFrom("a", 0);
      await tester.pumpAndSettle();
      expect(
          painted(tester).inputs.live.liveMotion.value, isA<MotionPreview>());
      await keep(tester, "whole_chain");
    });
  });

  group("marks on elements", () {
    const lorem =
        "The quick brown fox jumps over the lazy dog while the rain in Spain "
        "falls mainly on the plain and nobody at all is watching this happen.";
    CanvasController twoBoxes({bool linked = false}) {
      var a = TextElement(
        const ElementBase(id: "a", x: 40, y: 40, width: 300, height: 60),
        text: lorem,
        flowTo: linked ? "b" : "",
        box: const BoxSpec(padding: 0),
        textSpec: const TextSpec(fontSize: 16, align: TextAlignSpec.left),
      );
      var b = TextElement(
        const ElementBase(id: "b", x: 40, y: 260, width: 300, height: 200),
        text: "Its own words",
        box: const BoxSpec(padding: 0),
        textSpec: const TextSpec(fontSize: 16, align: TextAlignSpec.left),
      );
      return controllerOf(CanvasDocument(
        size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
        elements: [a, b],
      ));
    }

    testWidgets("text boxes' flow grips and the line between", (tester) async {
      var c = twoBoxes(linked: true);
      c.selectOnly("a");
      await pump(tester, c);
      expect(painted(tester).inputs.elements.flowGrips, isNotNull);
      expect(painted(tester).inputs.elements.flowLines, isNotEmpty);
      await keep(tester, "flow_linked");
    });

    testWidgets("a flow link being dragged out", (tester) async {
      var c = twoBoxes();
      c.selectOnly("a");
      var stage = await pump(tester, c);
      var from = stage.textFlowGrips!.outAt;
      var onto = stage.toStagePoint(const Offset(190, 360));
      var carry = await tester.startGesture(from);
      await tester.pump();
      await carry.moveTo(Offset.lerp(from, onto, 0.5)!);
      await tester.pump();
      await carry.moveTo(onto);
      await tester.pump();
      expect(painted(tester).inputs.elements.flowDrag, isNotNull);
      await keep(tester, "flow_drag");
      await carry.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets("a chart's placed labels", (tester) async {
      var c = controllerOf(docOf([
        ChartElement(
          const ElementBase(id: "c", x: 200, y: 120, width: 800, height: 460),
          title: "Title",
          titleBox: const ChartLabel(x: 0.1, y: 0.1, width: 0.3, height: 0.12),
          floatingLabels: true,
          showLegend: true,
          data: ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
        )
      ]));
      c.selectOnly("c");
      await pump(tester, c);
      expect(painted(tester).inputs.elements.chartLabels, isNotEmpty);
      await keep(tester, "chart_labels");
    });

    testWidgets("a table's column rules", (tester) async {
      var c = controllerOf(docOf([
        TableElement(
          const ElementBase(id: "t", x: 200, y: 200, width: 600, height: 200),
          rows: const [
            ["One", "Two", "Three"],
            ["Four", "Five", "Six"],
          ],
          columnWidths: const [1, 2, 1],
        )
      ]));
      c.selectOnly("t");
      await pump(tester, c);
      expect(painted(tester).inputs.elements.tableColumns, hasLength(2));
      await keep(tester, "table_columns");
    });

    LayoutElement three() => LayoutElement(
        const ElementBase(id: "L", x: 300, y: 60, width: 700, height: 900),
        root: const LayoutNode.cut(
            vertical: false,
            tilt: 4,
            a: LayoutNode.leaf("a"),
            b: LayoutNode.cut(
                vertical: true,
                a: LayoutNode.leaf("b"),
                b: LayoutNode.leaf("c"))),
        cells: const [
          LayoutCell(id: "a"),
          LayoutCell(id: "b"),
          LayoutCell(id: "c")
        ],
        gutter: 30,
        rowGutter: 30);

    testWidgets("a Layout's lines, cut knobs, numbers and picked cell",
        (tester) async {
      var c = controllerOf(docOf([three()]));
      c.selectOnly("L");
      c.pickLayoutCell("L", "b");
      await pump(tester, c);
      var marks = painted(tester).inputs.elements.layout!;
      expect(marks.knobs, isNotEmpty);
      expect(marks.badges, hasLength(3));
      expect(marks.picked.value, isNotNull);
      await keep(tester, "layout");
    });

    testWidgets("a Layout's reading order being clicked", (tester) async {
      var c = controllerOf(docOf([three()]));
      c.selectOnly("L");
      c.beginReadingOrder(c.document.elementById("L") as LayoutElement);
      c.clickReadingOrder("c");
      await pump(tester, c);
      var badges = painted(tester).inputs.elements.layout!.badges;
      expect(badges.where((b) => b.number == null), hasLength(2));
      await keep(tester, "layout_ordering");
    });

    testWidgets("a selected path's points and handles", (tester) async {
      var c = controllerOf(docOf([
        const PathElement(
            ElementBase(id: "p", x: 200, y: 200, width: 600, height: 300),
            nodes: [
              PathNode(x: 0, y: 1, outDx: 0.1, outDy: -0.6),
              PathNode(x: 0.5, y: 0.2, inDx: -0.2, outDx: 0.2, outDy: 0.1),
              PathNode(x: 1, y: 0.8),
            ]),
      ]));
      c.selectOnly("p");
      await pump(tester, c);
      expect(painted(tester).inputs.elements.selectedPath, isNotNull);
      await keep(tester, "path");
    });

    testWidgets("cameras' frames, upright and rolled", (tester) async {
      var c = controllerOf(docOf([
        box("a", 300, 300, 300, 200),
        const CameraElement(ElementBase(
            id: "c1", name: "Wide", x: 100, y: 100, width: 800, height: 450)),
        const CameraElement(ElementBase(
            id: "c2",
            name: "Close",
            x: 1000,
            y: 400,
            width: 480,
            height: 270,
            rotation: 18)),
      ]));
      c.selectOnly("a");
      await pump(tester, c);
      expect(painted(tester).inputs.elements.camerasShown, isTrue);
      await keep(tester, "cameras");
    });

    testWidgets("a game's touch areas", (tester) async {
      var doc = docOf([
        box("hero", 300, 500, 80, 120,
            play: const PlaySpec(as: PlayAs.platformer)),
        box("floor", 100, 700, 1400, 60,
            play: const PlaySpec(as: PlayAs.solid)),
      ]).copyWith(game: true);
      var c = controllerOf(doc);
      c.gameTabOpen = true;
      await pump(tester, c);
      expect(painted(tester).inputs.elements.touchAreas, isNotEmpty);
      await keep(tester, "touch_areas");
    });
  });

  group("the guides", () {
    testWidgets("the grid with subdivisions, guides and every ruler",
        (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 400, 250)],
          guides: const CanvasGuides(
              showGrid: true,
              gridSize: 160,
              subdivisions: 4,
              showGuides: true,
              guides: [
                CanvasGuide(axis: GuideAxis.vertical, at: 420),
                CanvasGuide(axis: GuideAxis.horizontal, at: 610),
              ])))
        ..rulers = const CanvasRulers(
            top: true, left: true, right: true, bottom: true);
      await pump(tester, c);
      await keep(tester, "grid_guides_rulers");
    });

    testWidgets("the line a drag is caught on", (tester) async {
      var c = controllerOf(docOf([box("s", 500, 150, 100, 100)],
          guides: const CanvasGuides(
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 400)])));
      var stage = await pump(tester, c);
      var centre = c.document.elementById("s")!.center;
      var from = stage.toStagePoint(centre);
      var to = stage.toStagePoint(centre + const Offset(-97, 0));
      var g = await tester.startGesture(from);
      await tester.pump();
      await g.moveBy((to - from) / 2);
      await tester.pump();
      await g.moveBy((to - from) / 2);
      await tester.pump();
      expect(painted(tester).inputs.guides.snapped?.caught, isTrue);
      await keep(tester, "snap_line");
      await g.up();
      await tester.pumpAndSettle();
    });
  });

  group("the tools", () {
    testWidgets("a marquee", (tester) async {
      var c = controllerOf(docOf([box("a", 600, 300, 200, 200)]));
      var stage = await pump(tester, c);
      var from = stage.toStagePoint(const Offset(200, 150));
      var to = stage.toStagePoint(const Offset(1000, 700));
      var g = await tester.startGesture(from);
      await tester.pump();
      await g.moveBy((to - from) / 2);
      await tester.pump();
      await g.moveBy((to - from) / 2);
      await tester.pump();
      expect(painted(tester).inputs.tools.marquee, isNotNull);
      await keep(tester, "marquee");
      await g.up();
      await tester.pumpAndSettle();
    });

    Future<CanvasController> editing(WidgetTester tester,
        {void Function(CanvasController)? then}) async {
      var c = controllerOf(docOf([drawing()]));
      c.selectOnly("v");
      c.editVector("v");
      then?.call(c);
      await pump(tester, c);
      expect(painted(tester).inputs.tools.vector, isNotNull);
      return c;
    }

    testWidgets("a drawing's point picked, with its handles", (tester) async {
      await editing(tester,
          then: (c) => c.pickVectorPoint(const VectorPick(1, 0, 1)));
      await keep(tester, "vector_point");
    });

    testWidgets("a drawing's points picked, in their box", (tester) async {
      await editing(tester,
          then: (c) => c.pickVectorPoints(
              {const VectorPick(0, 0, 0), const VectorPick(0, 0, 2)}));
      await keep(tester, "vector_points");
    });

    testWidgets("the pencil's mirror lines", (tester) async {
      await editing(tester, then: (c) {
        c.vectorTool = VectorTool.pencil;
        c.vectorMirrorAcross = true;
        c.vectorMirrorDown = true;
        c.vectorPencilPoints = true;
      });
      expect(painted(tester).inputs.tools.vector!.mirror, isNotNull);
      await keep(tester, "vector_mirror");
    });

    testWidgets("shapes picked, their box with a turn knob", (tester) async {
      await editing(tester, then: (c) {
        c.vectorTool = VectorTool.selectShapes;
        c.pickVectorItems({(shape: 1, part: 0)});
      });
      var vector = painted(tester).inputs.tools.vector!;
      expect(vector.shapeBox, isNotNull);
      expect(vector.turnable, isTrue);
      await keep(tester, "vector_shapes_picked");
    });

    testWidgets("shapes picked to combine", (tester) async {
      await editing(tester, then: (c) {
        c.vectorTool = VectorTool.boolean;
        c.toggleCombining(1);
      });
      expect(painted(tester).inputs.tools.vector!.combining, isNotEmpty);
      await keep(tester, "vector_combining");
    });

    testWidgets("the knife's line", (tester) async {
      var c =
          await editing(tester, then: (c) => c.vectorTool = VectorTool.knife);
      var stage = tester.state<CanvasStageState>(find.byType(CanvasStage));
      expect(c.vectorTool, VectorTool.knife);
      var g =
          await tester.startGesture(stage.toStagePoint(const Offset(250, 300)));
      await tester.pump();
      for (var p in const [
        Offset(350, 340),
        Offset(450, 330),
        Offset(560, 420),
        Offset(650, 450)
      ]) {
        await g.moveTo(stage.toStagePoint(p));
        await tester.pump();
      }
      expect(painted(tester).inputs.tools.knife.length, greaterThan(1));
      await keep(tester, "knife");
      await g.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets("a picture's layers being edited", (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 600, 400)]));
      c.selectOnly("a");
      await pump(tester, c);
      List<Offset> corners(Rect r) =>
          [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      var picked = corners(const Rect.fromLTWH(400, 260, 300, 200));
      await keep(tester, "layers",
          alter: (i) => withInputs(i,
              tools: withTools(i.tools,
                  layers: StageLayers(
                    others: [corners(const Rect.fromLTWH(320, 220, 200, 150))],
                    chosen: [corners(const Rect.fromLTWH(700, 400, 150, 150))],
                    picked: picked,
                    handles: [
                      for (var p in picked) p,
                      const Offset(550, 260),
                      const Offset(550, 460),
                    ],
                    knob: const Offset(550, 200),
                    ring: (const Offset(800, 300), 40),
                    trail: (
                      const [
                        Offset(350, 500),
                        Offset(450, 540),
                        Offset(600, 520)
                      ],
                      18,
                      false
                    ),
                    marker: const Offset(360, 300),
                    lasso: const [
                      Offset(600, 250),
                      Offset(750, 260),
                      Offset(720, 380),
                      Offset(620, 360),
                    ],
                  ))));
    });

    testWidgets("a quick-select stroke of one point, taking away",
        (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 600, 400)]));
      c.selectOnly("a");
      await pump(tester, c);
      await keep(tester, "layers_dab",
          alter: (i) => withInputs(i,
              tools: withTools(i.tools,
                  layers: const StageLayers(
                      trail: ([Offset(500, 400)], 30, true)))));
    });

    testWidgets("a warp grid", (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 600, 400)]));
      c.selectOnly("a");
      await pump(tester, c);
      var points = [
        for (var y = 0; y < 3; y++)
          for (var x = 0; x < 3; x++)
            Offset(300 + x * 300.0 + (y == 1 ? 20 : 0), 200 + y * 200.0),
      ];
      await keep(tester, "warp",
          alter: (i) => withInputs(i,
              tools: withTools(i.tools,
                  layers: StageLayers(
                      warp: StageWarp(
                    lines: [
                      for (var y = 0; y < 3; y++)
                        [for (var x = 0; x < 3; x++) points[y * 3 + x]],
                      for (var x = 0; x < 3; x++)
                        [for (var y = 0; y < 3; y++) points[y * 3 + x]],
                    ],
                    points: points,
                    picks: {4, 5},
                    box: const [
                      Offset(600, 380),
                      Offset(920, 380),
                      Offset(920, 420),
                      Offset(600, 420),
                    ],
                    knob: const Offset(760, 330),
                  )))));
    });

    testWidgets("a picture being reframed", (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 600, 400)]));
      c.selectOnly("a");
      await pump(tester, c);
      var image = await picture(tester);
      await keep(tester, "framing",
          alter: (i) => withInputs(i,
              tools: withTools(i.tools, framing: (
                image: image,
                src: const Rect.fromLTWH(0, 0, 64, 48),
                dst: const Rect.fromLTWH(200, 120, 800, 600),
                frame: const Rect.fromLTWH(350, 250, 400, 300),
                rotation: 0.3,
                pivot: null,
                flipX: true,
                flipY: false,
              ))));
    });

    testWidgets("a drawing's text caret", (tester) async {
      var c = controllerOf(docOf([drawing()]));
      await pump(tester, c);
      await keep(tester, "caret",
          alter: (i) => withInputs(i,
              tools: withTools(i.tools,
                  caret: (const Offset(400, 300), const Offset(400, 360)))));
    });
  });

  group("the retouching brush", () {
    for (var keeps in [false, true]) {
      testWidgets("its preview and stroke, ${keeps ? "keeping" : "taking"}",
          (tester) async {
        var c = controllerOf(docOf([box("a", 300, 200, 600, 400)]));
        await pump(tester, c);
        var image = await picture(tester);
        var stroke = const [
          Offset(350, 300),
          Offset(450, 340),
          Offset(560, 320),
          Offset(700, 420),
        ];
        await keep(tester, keeps ? "retouch_keeps" : "retouch",
            alter: (i) => withInputs(i, retouch: (
                  preview: (
                    image: image,
                    src: const Rect.fromLTWH(8, 4, 48, 40),
                    dst: const Rect.fromLTWH(400, 250, 300, 250),
                  ),
                  stroke: NotCompared(stroke),
                  strokeLength: stroke.length,
                  radius: 14,
                  keeps: keeps,
                )));
      });
    }
  });

  group("the page", () {
    testWidgets("text being typed into, its words left out", (tester) async {
      var c = controllerOf(docOf([
        TextElement(
          const ElementBase(id: "w", x: 200, y: 200, width: 600, height: 200),
          text: "Words the editor draws itself",
          textSpec: const TextSpec(fontSize: 48),
        ),
        box("a", 900, 300, 200, 200),
      ]));
      c.selectOnly("w");
      await pump(tester, c);
      await keep(tester, "text_edit",
          alter: (i) => withInputs(i, text: (element: "w", item: null)));
    });

    CanvasDocument book() => CanvasDocument(
          kind: CanvasKind.pages,
          size: const CanvasSize(ratio: CanvasRatio.a4, width: 600),
          pages: const PagesSpec(facing: true),
          scenes: [
            const CanvasScene(id: "c", cover: PageCover.front),
            CanvasScene(id: "p1", elements: [
              box("a", 100, 200, 300, 200),
              box("x", 450, 500, 300, 150, fill: const Color(0xFFE53935)),
            ]),
            CanvasScene(id: "p2", elements: [
              box("b", 100, 300, 250, 250, fill: const Color(0xFF43A047)),
            ]),
          ],
        );

    testWidgets("a facing page", (tester) async {
      var c = controllerOf(book());
      c.goToScene(1);
      c.selectOnly("a");
      await pump(tester, c);
      expect(painted(tester).inputs.shown.facing, isNotNull);
      expect(painted(tester).inputs.transform.spread, isTrue);
      await keep(tester, "facing");
    });

    testWidgets("a spread's transition being watched", (tester) async {
      var c = controllerOf(book());
      c.goToScene(1);
      await pump(tester, c);
      await keep(tester, "preview_spread",
          alter: (i) => withInputs(i, shown: withShown(i.shown, previewAt: 2)));
    });

    CanvasDocument scenes() => CanvasDocument(
          frames: 48,
          scenes: [
            CanvasScene(
                id: "s1",
                frames: 48,
                transition: const SceneTransition(
                    kind: SceneTransitionKind.fade, frames: 24, overlap: 24),
                elements: [box("a", 200, 200, 600, 400)]),
            CanvasScene(id: "s2", frames: 48, elements: [
              box("b", 700, 300, 600, 400, fill: const Color(0xFFE53935)),
            ]),
          ],
        );

    testWidgets("a transition being watched", (tester) async {
      var c = controllerOf(scenes());
      await pump(tester, c);
      await keep(tester, "preview_scenes",
          alter: (i) =>
              withInputs(i, shown: withShown(i.shown, previewAt: 36)));
    });

    testWidgets("a game's change of scene", (tester) async {
      var c = controllerOf(scenes());
      c.goToScene(1);
      await pump(tester, c);
      var left = c.document.goToScene(0);
      await keep(tester, "game_change",
          alter: (i) => withInputs(i,
              shown: withShown(i.shown, gameChange: (
                left,
                10,
                const SceneTransition(
                    kind: SceneTransitionKind.fade, frames: 24),
                0.4,
                const MotionPreview(null, "", 0),
              ))));
    });

    testWidgets("a game's level round the screen", (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 400, 250)]));
      c.selectOnly("a");
      await pump(tester, c);
      await keep(tester, "level", alter: (i) {
        var t = i.transform;
        var size = c.document.size.size;
        return withInputs(i,
            transform: StageTransform(
                visible: t.visible,
                viewport: t.viewport,
                page: t.page,
                fit: t.fit,
                zoom: t.zoom,
                spread: t.spread,
                facingOnLeft: t.facingOnLeft,
                overspill: t.overspill,
                level: Rect.fromLTWH(-size.width / 2, -size.height / 4,
                    size.width * 2, size.height * 1.5)));
      });
    });

    testWidgets("a held marker's label", (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 400, 250)]));
      await pump(tester, c);
      await keep(tester, "marker_note",
          alter: (i) => withInputs(i,
              shown: withShown(i.shown,
                  markerNote: const TimelineAction(
                      frame: 0,
                      kind: TimelineActionKind.stop,
                      label: "Held here"))));
    });

    testWidgets("the world outside the page, shaded", (tester) async {
      var c = controllerOf(docOf([
        box("a", -200, 200, 400, 250),
        box("b", 900, 300, 300, 300),
      ]));
      c.showOverspill = true;
      c.selectOnly("a");
      await pump(tester, c);
      expect(painted(tester).inputs.transform.overspill, isTrue);
      await keep(tester, "overspill");
    });

    testWidgets("zoomed in, more canvas outside the frame", (tester) async {
      var c = controllerOf(docOf([
        box("a", 700, 400, 400, 250),
      ], guides: const CanvasGuides(showGrid: true, gridSize: 100)));
      c.selectOnly("a");
      c.zoom = 2.5;
      await pump(tester, c);
      await keep(tester, "zoomed");
    });

    testWidgets("seen through the scene's camera, the selection with it",
        (tester) async {
      var c = controllerOf(docOf([
        box("a", 700, 400, 300, 200),
        box("b", 1100, 600, 200, 200, fill: const Color(0xFFE53935)),
      ]));
      c.selectMany({"a", "b"});
      c.showAnchor("a", true);
      await pump(tester, c);
      await keep(tester, "through_camera",
          alter: (i) => withInputs(i,
              shown:
                  withShown(i.shown, camera: (1.6, const Offset(900, 550)))));
    });

    testWidgets("helpers hidden", (tester) async {
      var c = controllerOf(docOf([box("a", 300, 200, 400, 250)]));
      c.selectOnly("a");
      c.showHelpers = false;
      await pump(tester, c);
      await keep(tester, "helpers_hidden");
    });
  });
}
