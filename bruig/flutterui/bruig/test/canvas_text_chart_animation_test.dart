import 'dart:convert';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Color, Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_text_chart_animation_test.dart is the words' and a chart's
// animations brought up to what every other element's has: a loop, a
// direction and a strength each way, and the one Timing / Keyframe group.

void main() {
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

  for (var kind in [ElementKind.text, ElementKind.chart]) {
    testWidgets("${kind.name}: Looping, Timing / Keyframe, no hints",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var doc = const CanvasDocument().copyWith(frames: 120);
      var e = newElement(kind, doc);
      var c = CanvasController(doc.addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      if (kind == ElementKind.text) {
        c.applyTextAnimation(
            c.selected as TextElement, TextAnimationPreset.slideLeft);
      }
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      var keys = kind == ElementKind.text ? "text" : "chart";
      var family = find.byKey(ValueKey("${keys}LoopFamily"));
      if (family.evaluate().isEmpty) {
        var heading = find.text("ANIMATION");
        await tester.ensureVisible(heading.first);
        await tester.tap(heading.first);
        await tester.pumpAndSettle();
      }
      expect(family, findsOneWidget, reason: "a Looping group");
      tester
          .widget<CanvasDropdown<LoopFamily?>>(family)
          .onChanged(LoopFamily.motion);
      await tester.pumpAndSettle();
      expect(CanvasController.elementLoopOf(c.selected!).on, isTrue);
      var animation = find.ancestor(
          of: find.text("ANIMATION"), matching: find.byType(CanvasExpander));
      expect(find.descendant(of: animation, matching: find.byType(CanvasHint)),
          findsNothing,
          reason: "no ? in the Animation section");
      if (kind == ElementKind.text) {
        expect(find.text("TIMING / KEYFRAME"), findsOneWidget);
        expect(
            find.byKey(const ValueKey("textAnimationDelay")), findsOneWidget);
        expect(find.byKey(const ValueKey("textAnimationDirection")),
            findsOneWidget,
            reason: "a slide is one choice with a Direction");
        expect(find.byKey(const ValueKey("textAnimationPreset")), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
