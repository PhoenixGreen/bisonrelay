import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// What the timeline, the slots and the Animation panel do to an element's
// clips, through the controller: made, placed, moved, stretched, cut, pinned
// and taken away -- each undone as any change is.

CanvasController make() => CanvasController(CanvasDocument(
      frames: 240,
      frameRate: 24,
      elements: [
        ShapeElement(
            const ElementBase(id: "a", x: 100, y: 100, width: 50, height: 50)),
        ShapeElement(
            const ElementBase(id: "b", x: 400, y: 100, width: 50, height: 50)),
      ],
    ));

void main() {
  test("a clip made in a slot, then placed", () {
    var c = make();
    addTearDown(c.dispose);
    var id = c.newClip("a", preset: presetNamed("Pop"), slot: 1);
    expect(c.motionOf("a").slot(1)?.name, "Pop");
    var p = c.placeClip("a", id, seconds: 2);
    expect(c.spanOf(p)!.start, 2);
    expect(c.spanOf(p)!.end, closeTo(2.5, 1e-9));
    c.undo();
    expect(c.motionOf("a").placed, isEmpty, reason: "placing is a step");
  });

  test("moved by hand, a placed clip lets go of its pins", () {
    var c = make();
    addTearDown(c.dispose);
    var m = c.addMarker(48);
    var id = c.newClip("a", preset: presetNamed("Jump"));
    var p = c.placeClip("a", id, seconds: 0);
    c.pinPlacement("a", p, ClipPin(PinKind.marker, target: m));
    expect(c.spanOf(p)!.start, 2, reason: "pinned to the marker at 2 s");
    expect(c.movePlacement("a", p, 3, layer: 1), isTrue);
    var placed = c.motionOf("a").placement(p)!;
    expect((placed.start, placed.layer, placed.startPin), (3, 1, null));
  });

  test("stretched, a one-shot is retimed; its other end stays", () {
    var c = make();
    addTearDown(c.dispose);
    var id = c.newClip("a", preset: presetNamed("Jump")); // 0.7 s
    var p = c.placeClip("a", id, seconds: 1);
    c.stretchPlacement("a", p, end: 2.4);
    var s = c.spanOf(p)!;
    expect((s.start, s.end), (1, 2.4));
    expect(s.speed, closeTo(0.5, 1e-9));
    c.stretchPlacement("a", p, start: 2);
    expect((c.spanOf(p)!.start, c.spanOf(p)!.end), (2, 2.4));
  });

  test("cut in two, it looks the same, and what followed it follows on", () {
    var c = make();
    addTearDown(c.dispose);
    var walk = c.newClip("a", preset: presetNamed("Shake"));
    var jump = c.newClip("a", preset: presetNamed("Jump"));
    var p = c.placeClip("a", walk, seconds: 0);
    var q = c.placeClip("a", jump, seconds: 0);
    c.pinPlacement("a", q, ClipPin(PinKind.after, target: p));
    double dx(int frame) =>
        poseWithMotion(c.document.elementById("a")!, frame, c.document).dx;
    var before = [for (var f = 0; f < 12; f++) dx(f)];
    var second = c.cutPlacement("a", p, 0.25)!;
    expect([for (var f = 0; f < 12; f++) dx(f)], before);
    expect(c.motionOf("a").placement(q)!.startPin,
        ClipPin(PinKind.after, target: second));
    expect(c.spanOf(q)!.start, closeTo(0.5, 1e-9));
  });

  test("taken away, what was pinned to it keeps its time", () {
    var c = make();
    addTearDown(c.dispose);
    var x = c.newClip("a", preset: presetNamed("Jump"));
    var y = c.newClip("b", preset: presetNamed("Bump"));
    var p = c.placeClip("a", x, seconds: 1);
    var q = c.placeClip("b", y, seconds: 0);
    c.pinPlacement("b", q, ClipPin(PinKind.after, target: p));
    var was = c.spanOf(q)!.start;
    c.removePlacement("a", p);
    expect(c.motionOf("a").placed, isEmpty);
    var left = c.motionOf("b").placement(q)!;
    expect((left.startPin, c.spanOf(q)!.start), (null, was));
  });

  test("copied to another element, as its own clip in a free slot", () {
    var c = make();
    addTearDown(c.dispose);
    var x = c.newClip("a", preset: presetNamed("Float"), slot: 0);
    var y = c.copyClipTo("a", x, "b")!;
    expect(y, isNot(x));
    expect(c.motionOf("b").slot(0)?.name, "Float");
    var model = c.newClip("a", kind: MotionKind.model);
    expect(c.copyClipTo("a", model, "b"), isNull,
        reason: "a model's own animation stays with it");
  });

  test("the animation and the effects are the Chain's two views, by turns", () {
    var c = make();
    addTearDown(c.dispose);
    c.animationOpen = true;
    c.effectsOpen = true;
    expect((c.animationOpen, c.effectsOpen), (false, true),
        reason: "one view of the Chain at a time");
    c.animationOpen = true;
    expect((c.animationOpen, c.effectsOpen), (true, false));
    expect(c.dockOpen(DockPanel.chain), isTrue);
    expect(c.chainShowsMotion, isTrue);
  });

  test("moved by a clip, its box is where it is drawn", () {
    var c = make();
    addTearDown(c.dispose);
    var id = c.newClip("a", preset: presetNamed("Slide out"));
    c.placeClip("a", id, seconds: 0);
    var e = c.document.elementById("a")!;
    var end = c.frameAt(c.motionOf("a").clip(id)!.length);
    var moved = e.movedBoundsAt(end, c.document);
    expect(moved, isNot(e.boundsAt(end)), reason: "the clip has moved it");
    expect(moved.center.dx - e.bounds.center.dx,
        poseWithMotion(e, end, c.document).dx);
  });
}
