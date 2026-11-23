import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/scene_transition.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/controller/view_types.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_transform.dart';

// canvas_stage_painter_inputs_test.dart holds the stage painter to its
// repaint rule: every input it draws from, changed alone, makes it draw
// again, and the same inputs made afresh do not.
//
// _make below builds a StageInputs with every field named. Each value is a
// record, so a field added to one does not compile here until it is given,
// and is given through pick, which this test then changes alone. A field
// whose equality would be by identity on something made at each build
// (a plain list, a closure) fails the first test instead, since _make makes
// everything afresh except what is kept by identity on purpose: the
// documents, pictures and elements, which the document keeps, and the
// picture's layers, which say they repaint while shown.

class _Pictures extends CanvasImageSource {
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Kept by identity on purpose (see above): one of each, and another.
  const document = CanvasDocument();
  const otherDocument = CanvasDocument(frameRate: 30);
  final pictures = _Pictures(), otherPictures = _Pictures();
  final backgrounds = ProceduralCache(), otherBackgrounds = ProceduralCache();
  final between = ValueNotifier(0.0), otherBetween = ValueNotifier(0.0);
  const path = PathElement(ElementBase(id: "p"));
  const otherPath = PathElement(ElementBase(id: "q"));
  const drawing = VectorElement(ElementBase(id: "v"));
  const otherDrawing = VectorElement(ElementBase(id: "w"));
  const guides = CanvasGuides();
  const otherGuides = CanvasGuides(showGrid: true);
  const layers = StageLayers();
  const otherLayers = StageLayers(knob: Offset(1, 1));
  const marker = TimelineAction(frame: 0, kind: TimelineActionKind.stop);
  const otherMarker = TimelineAction(frame: 1, kind: TimelineActionKind.stop);
  const transition = SceneTransition();
  const otherTransition = SceneTransition(frames: 4);
  const live = PointerLive(null);
  const otherLive = PointerLive(Offset(1, 1));
  late ui.Image picture, otherPicture;

  setUpAll(() async {
    picture = await createTestImage(width: 2, height: 2);
    otherPicture = await createTestImage(width: 3, height: 3);
  });

  var names = <String>[];

  /// make is the inputs with [vary] alone changed, or none.
  StageInputs make([String? vary]) {
    T pick<T>(String name, T same, T other) {
      names.add(name);
      return name == vary ? other : same;
    }

    return (
      transform: StageTransform(
        visible: pick(
            "transform.visible", const Size(1000, 800), const Size(1001, 800)),
        viewport: pick(
            "transform.viewport", const Size(1000, 800), const Size(1400, 800)),
        page: pick(
            "transform.page", const Size(1280, 720), const Size(1280, 721)),
        fit: pick("transform.fit", CanvasFit.whole, CanvasFit.width),
        zoom: pick("transform.zoom", 1.0, 2.0),
        spread: pick("transform.spread", false, true),
        facingOnLeft: pick("transform.facingOnLeft", false, true),
        overspill: pick("transform.overspill", false, true),
        level: pick("transform.level", null, const Rect.fromLTWH(0, 0, 9, 9)),
      ),
      shown: (
        document: pick("shown.document", document, otherDocument),
        frame: pick("shown.frame", 0, 1),
        facing: pick(
            "shown.facing",
            (
              index: pick("shown.facing.index", 1, 2),
              frame: pick("shown.facing.frame", 3, 4),
            ),
            null),
        previewAt: pick("shown.previewAt", null, 5),
        previewing: pick(
            "shown.previewing",
            (
              id: pick("shown.previewing.id", "a", "b"),
              frame: pick("shown.previewing.frame", 0, 1),
            ),
            null),
        gameChange: pick(
            "shown.gameChange",
            (
              pick("shown.gameChange.document", document, otherDocument),
              pick("shown.gameChange.frame", 0, 1),
              pick("shown.gameChange.transition", transition, otherTransition),
              pick("shown.gameChange.through", 0.5, 0.6),
              pick("shown.gameChange.live", live, otherLive),
            ),
            null),
        camera: pick(
            "shown.camera",
            (
              pick("shown.camera.zoom", 1.0, 2.0),
              pick("shown.camera.focus", Offset.zero, const Offset(1, 0)),
            ),
            null),
        directed: pick("shown.directed", false, true),
        markerNote: pick("shown.markerNote", marker, otherMarker),
        markerNoteGrip: pick("shown.markerNoteGrip", false, true),
      ),
      live: (
        images: pick("live.images", pictures, otherPictures),
        backgrounds: pick("live.backgrounds", backgrounds, otherBackgrounds),
        between: pick("live.between", between, otherBetween),
        drafting: pick("live.drafting", false, true),
        hoveredButton: pick("live.hoveredButton", null, "b"),
        counterHover: (
          id: pick("live.counterHover.id", null, "n"),
          button: pick("live.counterHover.button", -1, 0),
        ),
        // Made afresh, so never the same closure: the ticks stand in.
        liveMotion: NotCompared<LiveMotion?>(live),
        motionTick: pick("live.motionTick", 0, 1),
        counterValue: NotCompared((CounterElement e) => 0.0),
        counterRunning: NotCompared((CounterElement e) => false),
        counterTick: pick("live.counterTick", 0, 1),
        audioState: NotCompared((AudioElement e) => throw UnimplementedError()),
        videoShow: NotCompared((VideoElement e) => throw UnimplementedError()),
        audioRevision: pick("live.audioRevision", 0, 1),
        keysTick: pick("live.keysTick", 0, 1),
        spritePaintTick: pick("live.spritePaintTick", -1, 0),
        tilePaintTick: pick("live.tilePaintTick", -1, 0),
      ),
      selection: (
        ids: EqualSet(pick("selection.ids", ["a", "b"], ["a"])),
        bounds: pick("selection.bounds", const Rect.fromLTWH(0, 0, 10, 10),
            const Rect.fromLTWH(0, 0, 10, 11)),
        frame: BoxFrame(
            pick("selection.frame.rotation", 0.0, 10.0),
            pick("selection.frame.skewX", 0.0, 5.0),
            pick("selection.frame.skewY", 0.0, 5.0)),
        showHandles: pick("selection.showHandles", true, false),
        showHelpers: pick("selection.showHelpers", true, false),
        pickedCopies:
            EqualSet(pick("selection.pickedCopies", <String>[], ["i0"])),
        trail: pick("selection.trail", false, true),
        anchors: EqualList([
          (
            at: pick("selection.anchors.at", Offset.zero, const Offset(1, 1)),
            locked: pick("selection.anchors.locked", false, true),
          ),
        ]),
      ),
      elements: (
        showAllBounds: pick("elements.showAllBounds", false, true),
        camerasShown: pick("elements.camerasShown", true, false),
        touchAreas: EqualList(pick("elements.touchAreas",
            [const Rect.fromLTWH(0, 0, 1, 1)], <Rect>[])),
        flowGrips: TextFlowGrips(
          inAt:
              pick("elements.flowGrips.inAt", Offset.zero, const Offset(1, 0)),
          outAt:
              pick("elements.flowGrips.outAt", Offset.zero, const Offset(1, 0)),
          overflowing: pick("elements.flowGrips.overflowing", false, true),
          receiving: pick("elements.flowGrips.receiving", false, true),
          linked: pick("elements.flowGrips.linked", false, true),
        ),
        flowLines: EqualList([
          FlowLine(
              pick("elements.flowLines.from", Offset.zero, const Offset(1, 0)),
              const Offset(5, 5),
              overflowing: pick("elements.flowLines.overflowing", false, true)),
        ]),
        flowDrag: pick("elements.flowDrag", null,
            const FlowLine(Offset.zero, Offset(1, 1))),
        chartLabels: EqualList([
          (
            rect: pick(
                "elements.chartLabels.rect",
                const Rect.fromLTWH(0, 0, 4, 4),
                const Rect.fromLTWH(0, 0, 5, 4)),
            grip: pick("elements.chartLabels.grip", false, true),
          ),
        ]),
        layout: pick(
            "elements.layout",
            (
              lines: EqualList([
                pick("elements.layout.lines", (Offset.zero, const Offset(1, 0)),
                    (Offset.zero, const Offset(2, 0))),
              ]),
              picked: NotCompared<Path?>(Path()),
              pickedCell: pick("elements.layout.pickedCell", "a", "b"),
              knobs: EqualList([
                (
                  turn: pick("elements.layout.knobs.turn", Offset.zero,
                      const Offset(1, 0)),
                  gutter: pick("elements.layout.knobs.gutter", Offset.zero,
                      const Offset(1, 0)),
                  edgeA: pick(
                      "elements.layout.knobs.edgeA",
                      (Offset.zero, Offset.zero),
                      (Offset.zero, const Offset(1, 0))),
                  edgeB: pick(
                      "elements.layout.knobs.edgeB",
                      (Offset.zero, Offset.zero),
                      (Offset.zero, const Offset(1, 0))),
                ),
              ]),
              badges: EqualList([
                (
                  at: pick("elements.layout.badges.at", Offset.zero,
                      const Offset(1, 0)),
                  number: pick("elements.layout.badges.number", 1, null),
                  ordering:
                      pick("elements.layout.badges.ordering", false, true),
                ),
              ]),
            ),
            null),
        tableColumns: EqualList([
          pick("elements.tableColumns", (1.0, 0.0, 10.0), (2.0, 0.0, 10.0)),
        ]),
        selectedPath: pick("elements.selectedPath", path, otherPath),
        pathPlace: pick("elements.pathPlace", path.placedBy(Keyframe.rest),
            path.placedBy(const Keyframe(frame: 0, dx: 4))),
      ),
      tools: (
        vector: pick(
            "tools.vector",
            (
              element: pick("tools.vector.element", drawing, otherDrawing),
              shape: pick("tools.vector.shape", 0, 1),
              pick: pick("tools.vector.pick", null, const VectorPick(0, 0, 0)),
              picks: EqualSet(pick("tools.vector.picks",
                  [const VectorPick(0, 0, 1)], <VectorPick>[])),
              boxing: pick("tools.vector.boxing", false, true),
              boxed: EqualSet(pick("tools.vector.boxed", <VectorPick>[],
                  [const VectorPick(0, 0, 2)])),
              bare: pick("tools.vector.bare", false, true),
              mirror: pick(
                  "tools.vector.mirror", null, (across: true, down: false)),
              shapeBox: pick("tools.vector.shapeBox", null,
                  const Rect.fromLTWH(0, 0, 1, 1)),
              turnable: pick("tools.vector.turnable", false, true),
              combining: pick("tools.vector.combining", null, EqualSet([1])),
            ),
            null),
        layers: pick("tools.layers", layers, otherLayers),
        framing: pick(
            "tools.framing",
            (
              image: pick("tools.framing.image", picture, otherPicture),
              src: pick("tools.framing.src", const Rect.fromLTWH(0, 0, 2, 2),
                  const Rect.fromLTWH(0, 0, 1, 2)),
              dst: pick("tools.framing.dst", const Rect.fromLTWH(0, 0, 4, 4),
                  const Rect.fromLTWH(0, 0, 5, 4)),
              frame: pick(
                  "tools.framing.frame",
                  const Rect.fromLTWH(1, 1, 2, 2),
                  const Rect.fromLTWH(1, 1, 3, 2)),
              rotation: pick("tools.framing.rotation", 0.0, 1.0),
              pivot: pick("tools.framing.pivot", null, Offset.zero),
              flipX: pick("tools.framing.flipX", false, true),
              flipY: pick("tools.framing.flipY", false, true),
            ),
            null),
        knife: EqualList(pick("tools.knife", <Offset>[], [Offset.zero])),
        caret: pick("tools.caret", null, (Offset.zero, const Offset(0, 1))),
        marquee: pick("tools.marquee", null, const Rect.fromLTWH(0, 0, 1, 1)),
      ),
      retouch: (
        preview: pick(
            "retouch.preview",
            (
              image: pick("retouch.preview.image", picture, otherPicture),
              src: pick("retouch.preview.src", const Rect.fromLTWH(0, 0, 2, 2),
                  const Rect.fromLTWH(0, 0, 1, 2)),
              dst: pick("retouch.preview.dst", const Rect.fromLTWH(0, 0, 4, 4),
                  const Rect.fromLTWH(0, 0, 5, 4)),
            ),
            null),
        // Grown in place, so never compared: its length stands in.
        stroke: NotCompared([Offset.zero]),
        strokeLength: pick("retouch.strokeLength", 1, 2),
        radius: pick("retouch.radius", 4.0, 5.0),
        keeps: pick("retouch.keeps", false, true),
      ),
      guides: (
        canvas: pick("guides.canvas", guides, otherGuides),
        inView: pick("guides.inView", true, false),
        snapped: pick("guides.snapped", null, const SnapLines(vertical: 4)),
        rulers: pick("guides.rulers", const CanvasRulers(),
            const CanvasRulers(left: true)),
      ),
      text: pick(
          "text",
          (
            element: pick("text.element", "t", "u"),
            item: pick("text.item", null, "piece"),
          ),
          null),
    );
  }

  test("made twice from the same inputs, it does not draw again", () {
    expect(StagePainter(make()).shouldRepaint(StagePainter(make())), isFalse);
  });

  test("every input changed alone makes it draw again", () {
    names.clear();
    make();
    var every = [...names];
    expect(every.toSet(), hasLength(every.length), reason: "names repeated");
    // Everything the painter took one by one before it took these values,
    // and more: each leaf of a value counts.
    expect(every.length, greaterThan(100));
    var same = StagePainter(make());
    for (var name in every) {
      expect(StagePainter(make(name)).shouldRepaint(same), isTrue,
          reason: name);
    }
  });

  test("what cannot be compared does not, and what stands in for it does", () {
    var once = make(), again = make();
    expect(
        identical(once.live.counterValue.value, again.live.counterValue.value),
        isFalse);
    expect(once.live, again.live);
    expect(once.retouch, again.retouch);
    expect(make("live.counterTick").live, isNot(once.live));
    expect(make("retouch.strokeLength").retouch, isNot(once.retouch));
  });
}
