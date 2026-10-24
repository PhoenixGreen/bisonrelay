import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_drag_presets_test.dart is an animated element being dragged: moved,
// with its animations coming along, unless what it has is movement.
//
// An arrival, an exit, a loop, a fade and a dim all play wherever the
// element is put; that is what makes them worth having. Movement on the
// timeline is the one kind of animation a drag records into. A fade counted
// as movement, so an element dimmed by "Dim the others" took a keyframe on
// every drag and crept off where it had been put.

ShapeElement _shape({ElementTrack? track}) => ShapeElement(
    ElementBase(id: "s", x: 100, y: 100, width: 50, height: 50, track: track));

CanvasController _with(ShapeElement e) =>
    CanvasController(const CanvasDocument(frames: 120).addElement(e));

ShapeElement _in(CanvasController c) =>
    c.document.elements.single as ShapeElement;

/// _drag drags the element 40 to the right at frame [at], from where it is
/// drawn there.
void _drag(CanvasController c, int at) {
  c.frame = at;
  var e = _in(c);
  var pose = e.track?.at(at) ?? Keyframe.rest;
  c.replaceElement(c.movedTo(e, Offset(e.x + pose.dx + 40, e.y + pose.dy)));
}

void main() {
  test("with an arrival and an exit, a drag moves it", () {
    var c = _with(_shape());
    addTearDown(c.dispose);
    c.applyElementAnimation(_in(c), ElementAnimationPreset.fadeIn);
    c.applyElementExit(_in(c), ElementAnimationPreset.slideUp);
    var keys = _in(c).track!.keys.length;
    _drag(c, 60);
    expect(_in(c).x, 140, reason: "put somewhere else");
    expect(_in(c).track!.keys.length, keys, reason: "no keyframe added");
    expect(_in(c).track!.keys.every((k) => !k.movesElement), isTrue);
  });

  test("and dimmed or faded, it is still moved", () {
    var c = _with(_shape(
        track: ElementTrack([
      const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
      const Keyframe(frame: 10, values: {KeyframeChannel.reveal: 1}),
      const Keyframe(frame: 40),
      const Keyframe(frame: 52, opacity: 0.3),
    ])));
    addTearDown(c.dispose);
    _drag(c, 80);
    expect(_in(c).x, 140);
    expect(_in(c).track!.keys.any((k) => k.movesElement), isFalse);
  });

  test("but one that already moves is posed, at the playhead", () {
    var c = _with(_shape(
        track: ElementTrack([
      const Keyframe(frame: 0),
      const Keyframe(frame: 30, dx: 60),
    ])));
    addTearDown(c.dispose);
    _drag(c, 30);
    expect(_in(c).x, 100, reason: "its resting place stays put");
    expect(_in(c).track!.keyAt(30)!.dx, 100);
  });

  test("and so is one pinned by hand before anything has moved", () {
    // Add Keyframe at the start, then a drag later on: the ordinary way to
    // begin a movement.
    var c = _with(_shape(track: ElementTrack([const Keyframe(frame: 0)])));
    addTearDown(c.dispose);
    _drag(c, 30);
    expect(_in(c).x, 100);
    expect(_in(c).track!.keyAt(30)!.dx, 40);
  });

  test("and anything at all, with auto-keyframe on", () {
    var c = _with(_shape());
    addTearDown(c.dispose);
    c.applyElementAnimation(_in(c), ElementAnimationPreset.fadeIn);
    c.autoKeyframe = true;
    _drag(c, 60);
    expect(_in(c).x, 100);
    expect(_in(c).track!.keyAt(60)!.dx, 40);
  });
}
