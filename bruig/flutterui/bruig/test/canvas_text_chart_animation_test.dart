import 'dart:convert';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_chart_animation_test.dart is the words' and a chart's
// animations brought up to what every other element's has: a loop, a
// direction and a strength each way, and the one Timing / Keyframe group.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);
  group("the words", () {
    test("a direction and a strength each way, kept", () {
      const a = TextAnimation(
          preset: TextAnimationPreset.slideLeft,
          exit: TextAnimationPreset.slideLeft,
          direction: AnimationDirection.above,
          strength: 2,
          exitDirection: AnimationDirection.right);
      expect(a.spec.dx, closeTo(0, 1e-9));
      expect(a.spec.dy, closeTo(-1.2, 1e-9),
          reason: "from above, twice as far");
      expect(a.leaving.spec.dx, closeTo(0.6, 1e-9),
          reason: "out to the right, its own way");
      // Nothing set: exactly the preset's own.
      const plain = TextAnimation(preset: TextAnimationPreset.slideUp);
      expect(plain.spec.dy, TextAnimationPreset.slideUp.spec.dy);
      var back = TextAnimation.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(back.direction, a.direction);
      expect(back.exitDirection, a.exitDirection);
      expect(back.strength, 2);
    });

    test("a loop of their own, kept with nothing else, and drawn", () async {
      var doc = const CanvasDocument().copyWith(frames: 120);
      var t = newElement(ElementKind.text, doc) as TextElement;
      t = t.copyWith(
          animation: const TextAnimation(
              loop: ElementLoop(preset: LoopPreset.float, cycle: 40)));
      var back = elementFromJson(
          jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
      expect((back as TextElement).animation.loop.preset, LoopPreset.float,
          reason: "a loop alone is still kept");

      Future<List<int>> draw(int frame) async {
        var rec = PictureRecorder();
        paintElement(Canvas(rec), t, frame);
        var img = await rec.endRecording().toImage(1400, 900);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var at0 = await draw(0), at10 = await draw(10);
      var moved = false;
      for (var i = 0; i < at0.length && !moved; i += 4) {
        if (at0[i + 3] != at10[i + 3]) moved = true;
      }
      expect(moved, isTrue, reason: "floating, a quarter of the way round");
    });
  });

  test("a chart's loop is kept with nothing else", () {
    var doc = const CanvasDocument();
    var c = newElement(ElementKind.chart, doc);
    var json = c.toJson();
    expect(json.containsKey("anim"), isFalse);
    var looped = elementFromJson({
      ...json,
      "anim": const ChartAnimation(loop: ElementLoop(preset: LoopPreset.pulse))
          .toJson(),
    });
    var again = elementFromJson(
        jsonDecode(jsonEncode(looped.toJson())) as Map<String, dynamic>);
    expect(CanvasController.elementLoopOf(again).preset, LoopPreset.pulse);
  });
}
