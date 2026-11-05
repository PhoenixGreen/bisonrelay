import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_settled_frame_test.dart is which frame a canvas opens on.
//
// Reported: opening a canvas whose elements arrive showed none of them, which
// reads as a document that has failed to load rather than one that is about
// to play. It opens on the frame everything has arrived by.

/// _rate is the documents' frame rate, which the arrivals are timed in.
const _rate = 24;

CanvasElement _arriving(String id, {required int from, required int to}) =>
    withOwnSpan(ShapeElement(ElementBase(id: id, width: 50, height: 50)),
        MotionKind.arrive, from, to, _rate);

void main() {
  test("a canvas with nothing arriving opens at the start", () {
    var document = const CanvasDocument(
        frames: 60, elements: [ShapeElement(ElementBase(id: "a"))]);
    expect(settledFrameOf(document), 0);
  });

  test("and one with an arrival opens where it finishes", () {
    var document = CanvasDocument(
        frames: 60,
        frameRate: _rate,
        elements: [_arriving("a", from: 0, to: 24)]);
    expect(settledFrameOf(document), 24);
  });

  test("the last of them, where several arrive", () {
    var document = CanvasDocument(frames: 60, frameRate: _rate, elements: [
      _arriving("a", from: 0, to: 24),
      _arriving("b", from: 12, to: 40),
    ]);
    expect(settledFrameOf(document), 40);
  });

  test("never past the end of the document", () {
    // A band left behind by a document that has since been shortened.
    var document = CanvasDocument(
        frames: 10,
        frameRate: _rate,
        elements: [_arriving("a", from: 0, to: 40)]);
    expect(settledFrameOf(document), 9);
  });

  test("and a canvas opens on it", () {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    controller.load(CanvasDocument(
        frames: 60,
        frameRate: _rate,
        elements: [_arriving("a", from: 0, to: 24)]));
    expect(controller.frame, 24);
  });

  test("a canvas with no arrivals still opens at the start", () {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    controller.load(const CanvasDocument(
        frames: 60, elements: [ShapeElement(ElementBase(id: "a"))]));
    expect(controller.frame, 0);
  });
}
