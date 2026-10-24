import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_exit_fallback_test.dart is a way out with no exit chosen.
//
// The editor keeps the two together -- choosing None for an exit takes its
// keyframes away -- but a document written any other way can have a closing
// band and no exit, and the element used to stay on screen straight through
// it. Now it fades over the band.

/// _square is a black square that leaves between frames 10 and 20.
ShapeElement _square(
        {ElementAnimationPreset exit = ElementAnimationPreset.none}) =>
    ShapeElement(
      ElementBase(
          id: "s",
          x: 10,
          y: 10,
          width: 40,
          height: 40,
          track: ElementTrack([
            const Keyframe(frame: 10, values: {KeyframeChannel.close: 0}),
            const Keyframe(frame: 20, values: {KeyframeChannel.close: 1}),
          ])),
      fill: const Color(0xFF000000),
      animation: ElementAnimation(exit: exit),
    );

/// _alpha is how opaque the middle of the square is drawn at [frame].
Future<int> _alpha(ShapeElement e, int frame) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, frame);
  var img = await rec.endRecording().toImage(60, 60);
  var px = (await img.toByteData())!.buffer.asUint8List();
  return px[(30 * 60 + 30) * 4 + 3];
}

void main() {
  test("with no exit chosen it fades over its closing band", () async {
    var e = _square();
    expect(leavesByItself(e), isFalse);
    expect(await _alpha(e, 5), 255, reason: "there before it starts leaving");
    expect(await _alpha(e, 15), inInclusiveRange(110, 145),
        reason: "half gone half way through");
    expect(await _alpha(e, 20), 0, reason: "gone at the end");
  });

  test("an exit that is chosen is left to play itself", () async {
    // Fade in, played backwards, is the exit -- so the fallback must not
    // fade it a second time on top.
    var e = _square(exit: ElementAnimationPreset.fadeIn);
    expect(leavesByItself(e), isTrue);
    var half = await _alpha(e, 15);
    expect(half, greaterThan(20), reason: "not faded twice: $half");
    expect(await _alpha(e, 20), 0);
  });
}
