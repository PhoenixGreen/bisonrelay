import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';

import 'support/canvas_app.dart';
import 'support/canvas_panel_helpers.dart';
import 'support/canvas_sidebar_host.dart';
import 'support/element_samples.dart';
import 'support/kept_lists.dart';

// canvas_panel_keys_test.dart is what every kind's settings show, in the real
// sidebar at the width it opens at, with every section, card and "more"
// group open: every key in order and every piece of text in order, for each
// kind as first added and as filled (element_samples.dart), and for the few
// places that the place-and-size group shows something of its own (a page
// number, a Camera's depth, several page shapes, words on a line), for a
// panel with two boxes, and for what a shape's, a line's and a path's
// panels show beyond the samples (_strokeStates).
//
// It is how a change to how panels are built is shown to change nothing a
// person sees. Set PANEL_KEYS to a folder and run this file on the code as
// it is: each state's lists are written there. Make the change and run it
// again: a state whose lists differ fails, showing both where they part.
// Without PANEL_KEYS each state is still mounted and nothing is kept.
// A text's own states are canvas_text_panel_keys_test.dart's.

const _screen = Size(300, 9000);

/// _State is one element on the canvas it is on, selected.
typedef _State = ({String name, CanvasDocument document, String id});

const _doc = CanvasDocument(frames: 96, frameRate: 24);

List<_State> _states() {
  _State alone(String name, CanvasElement e) =>
      (name: name, document: _doc.addElement(e), id: e.id);
  var counter = newElement(ElementKind.counter, _doc) as CounterElement;
  var text = newElement(ElementKind.text, _doc) as TextElement;
  const line = LineElement(
      ElementBase(id: "line", x: 100, y: 400, width: 600, height: 10));
  const camera = CameraElement(ElementBase(id: "camera"));
  return [
    for (var (name, e) in [...elementSamples(), ...filledSamples()])
      // A 3D character's panel waits on its 3D scene, which a test cannot
      // build.
      if (e.kind != ElementKind.character3d) alone(name, e),
    (
      name: "Counter, in a document of pages",
      document:
          const CanvasDocument(kind: CanvasKind.pages).addElement(counter),
      id: counter.id,
    ),
    (
      name: "Counter, the page number",
      document: const CanvasDocument(kind: CanvasKind.pages)
          .addElement(counter.copyWith(source: CounterSource.page)),
      id: counter.id,
    ),
    // Two boxes in one panel: its own and its buttons'.
    alone("Counter, with buttons",
        counter.copyWith(buttons: CounterButton.values)),
    (
      name: "Text, with a Camera, on two page shapes",
      document: const CanvasDocument(targets: ["feedAd", "wide"])
          .addElement(camera)
          .addElement(text),
      id: text.id,
    ),
    (
      name: "Text, its own on this page shape",
      document: const CanvasDocument(targets: ["feedAd", "wide"])
          .addElement(text.withBase(ownDesign: true)),
      id: text.id,
    ),
    (
      name: "Text, on a line",
      document: _doc.addElement(line).addElement(
          text.copyWith(curve: const TextOnCurve(elementId: "line"))),
      id: text.id,
    ),
    ..._strokeStates(),
  ];
}

/// _strokeStates are what a shape's, a line's and a path's panels can show
/// beyond the samples: a bubble of each body, a picture and a pattern
/// inside a shape, words on a plain one, a turned line and a line whose bow
/// is keyed, a path with its follower on the canvas, a guide and a closed
/// one with no ends, and each of the three in a canvas laid out for two
/// page shapes.
List<_State> _strokeStates() {
  var shape = newElement(ElementKind.shape, _doc) as ShapeElement;
  var line = newElement(ElementKind.line, _doc) as LineElement;
  var path = newElement(ElementKind.path, _doc) as PathElement;
  var follower = newElement(ElementKind.text, _doc) as TextElement;
  _State alone(String name, CanvasElement e) =>
      (name: name, document: _doc.addElement(e), id: e.id);
  return [
    for (var (body, tail) in const [
      (BubbleBody.rounded, BubbleTail.pointer),
      (BubbleBody.oval, BubbleTail.thought),
      (BubbleBody.burst, BubbleTail.none),
    ])
      alone(
          "Shape, a ${body.name} bubble with a ${tail.name} tail",
          shape.copyWith(
              shape: ShapeKind.speechBubble,
              bubble: SpeechBubbleSpec(body: body, tail: tail))),
    alone("Shape, with words", shape.copyWith(text: "Words on it")),
    alone(
        "Shape, painted with a picture",
        shape.copyWith(
            painted: const TextFill(
                kind: TextFillKind.image, assetId: "a-picture", tile: true))),
    alone(
        "Shape, painted with a pattern",
        shape.copyWith(
            painted: const TextFill(
                kind: TextFillKind.pattern,
                pattern: ProceduralSpec(style: ProceduralStyle.lineGrid)))),
    alone("Line, turned", line.withBase(rotation: 30) as LineElement),
    alone(
        "Line, with ends, a dash and a fade",
        line.copyWith(
            startEnd: LineEnd.circle,
            endEnd: LineEnd.arrow,
            endSize: 2,
            dash: 12,
            fade: const GradientSpec(to: Color(0xFF3D7EFF)))),
    alone(
        "Line, bowed with its bow keyed",
        line.copyWith(curvature: 0.2).withBase(
                track: ElementTrack(const [
              Keyframe(frame: 0, values: {KeyframeChannel.bow: 0.4}),
              Keyframe(frame: 40, values: {KeyframeChannel.bow: -0.3}),
            ])) as LineElement),
    (
      name: "Path, with its follower on the canvas",
      document: _doc.addElement(follower.withBase(name: "Runner")).addElement(
          path.copyWith(follow: PathFollow(elementId: follower.id))),
      id: path.id,
    ),
    alone("Path, a guide", path.copyWith(guide: true)),
    alone("Path, closed", path.copyWith(closed: true)),
    // What each does on the page shape shown, in a canvas laid out for two.
    for (var e in <CanvasElement>[shape, line, path])
      (
        name: "${e.kind.label}, on two page shapes",
        document:
            const CanvasDocument(targets: ["feedAd", "wide"]).addElement(e),
        id: e.id,
      ),
  ];
}

/// _steadyIds is [keys] with the ids made fresh each run (newElementId's:
/// the element's own, a Layout's cells) said the same way every run: the
/// element's as `<id>`, the others numbered in the order they are met.
List<String> _steadyIds(List<String> keys, String id) {
  var fresh =
      RegExp(r"(?<![A-Za-z0-9])e[0-9a-z]{1,4}_[0-9a-z]{1,4}(?![0-9a-z])");
  var named = <String, String>{id: "<id>"};
  return [
    for (var k in keys)
      k.replaceAllMapped(fresh, (m) {
        var seen = m[0]!;
        return named.putIfAbsent(seen, () => "<id${named.length}>");
      }),
  ];
}

/// _settle lets what was opened lay out, its chevrons turn and anything read
/// from disk arrive, without waiting on a panel that never stops moving.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Each state from a panel as a new run has it, so that what the one
  // before opened does not show in the next, whichever runs alone.
  setUp(() {
    forgetPanelsForTest();
    forgetSectionsForTest();
    CanvasSection.openAll = true;
  });
  tearDownAll(() => CanvasSection.openAll = false);

  for (var state in _states()) {
    testWidgets("${state.name}: what its settings show", (tester) async {
      SharedPreferences.setMockInitialValues({});
      setTestScreen(tester, _screen);
      var c = CanvasController(state.document);
      addTearDown(c.dispose);
      c.selectOnly(state.id);
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await _settle(tester);
      await openEverything(tester, find.byType(CanvasSidebarHost));

      var (shown, words) = shownUnder(tester, find.byType(CanvasSidebarHost));
      expect(shown, isNotEmpty, reason: state.name);
      var keys = _steadyIds(shown, state.id);
      keepOrCompareLines("PANEL_KEYS", state.name, "keys", keys);
      keepOrCompareLines("PANEL_KEYS", state.name, "words", words);
    });
  }
}
