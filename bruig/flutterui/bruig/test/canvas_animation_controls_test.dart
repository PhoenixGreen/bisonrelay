import 'dart:convert';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/render/element_effects.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_animation_controls_test.dart is the Animation section's own tools:
// the curves and their pictures, one Direction and a Strength in place of a
// preset for every way round, the arrival's Delay and Length typed, a
// Preview that plays one element alone, and a drawing's Stagger.

/// drawing is a drawing of [count] squares in a row, 40 across, at
/// (100, 100) -- with an arrival over frames [from] to [to] where [arrival]
/// is set.
VectorElement drawing(
    {int count = 1,
    ElementAnimation animation = const ElementAnimation(),
    int from = 0,
    int to = 20}) {
  var e = VectorElement(
      ElementBase(id: "v", x: 100, y: 100, width: 40.0 * count, height: 40),
      viewBox: Rect.fromLTWH(0, 0, 40.0 * count, 40),
      shapes: [
        for (var i = 0; i < count; i++)
          shapeOf(VectorShapeKind.box, Rect.fromLTWH(40.0 * i, 0, 40, 40),
              fill: const Color(0xFF0000FF)),
      ],
      animation: animation);
  return animation.on
      ? withOwnSpan(e, MotionKind.arrive, from, to, defaultFrameRate)
          as VectorElement
      : e;
}

Widget panel(CanvasController c) => MultiProvider(
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
    );

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);
  group("the curves", () {
    test("ease in and ease in & out start and end where they should", () {
      for (var c in [ChartEase.easeIn, ChartEase.easeInOut]) {
        expect(c.apply(0), 0);
        expect(c.apply(1), 1);
      }
      expect(ChartEase.easeIn.apply(0.5), lessThan(0.5), reason: "slow first");
      expect(ChartEase.easeInOut.apply(0.5), closeTo(0.5, 1e-9));
      expect(ChartEase.easeInOut.apply(0.25), lessThan(0.25));
      expect(ChartEase.easeInOut.apply(0.75), greaterThan(0.75));
    });
  });

  group("direction and strength", () {
    test("a direction turns a slide, and keeps how far it goes", () {
      const a = ElementAnimation(preset: ElementAnimationPreset.slideLeft);
      expect(a.spec.dx, closeTo(-0.9, 1e-9));
      var above = a.copyWith(direction: AnimationDirection.above).spec;
      expect(above.dx, closeTo(0, 1e-9));
      expect(above.dy, closeTo(-0.9, 1e-9));
      var corner = a.copyWith(direction: AnimationDirection.belowRight).spec;
      expect(corner.dx, closeTo(0.9 / 1.41421356, 1e-6));
      expect(corner.dy, closeTo(0.9 / 1.41421356, 1e-6));
      expect(a.directionOf(a.preset), AnimationDirection.left);
      expect(
          const ElementAnimation(preset: ElementAnimationPreset.slideUp)
              .directionOf(ElementAnimationPreset.slideUp),
          AnimationDirection.below);
    });

    test("strength moves it further, grows it more and turns it more", () {
      const slide = ElementAnimation(
          preset: ElementAnimationPreset.slideRight, strength: 2);
      expect(slide.spec.dx, closeTo(1.8, 1e-9));
      const grow =
          ElementAnimation(preset: ElementAnimationPreset.scaleIn, strength: 2);
      expect(grow.spec.from, closeTo(1 - 0.4 * 2, 1e-9));
      const spin = ElementAnimation(
          preset: ElementAnimationPreset.spinIn, strength: 0.5);
      expect(spin.spec.turns, closeTo(0.5, 1e-9));
      expect(
          const ElementAnimation(preset: ElementAnimationPreset.fadeIn)
              .strengthens,
          isFalse);
      expect(
          const ElementAnimation(preset: ElementAnimationPreset.wipe).directed,
          isTrue);
    });

    test("the way in and the way out each have their own", () {
      const a = ElementAnimation(
          preset: ElementAnimationPreset.slideLeft,
          exit: ElementAnimationPreset.slideLeft,
          direction: AnimationDirection.left,
          exitDirection: AnimationDirection.right,
          strength: 1,
          exitStrength: 2);
      expect(a.spec.dx, lessThan(0), reason: "comes in from the left");
      expect(a.leaving.spec.dx, closeTo(1.8, 1e-9),
          reason: "goes out to the right, twice as far");
      var b = a.copyWith(direction: AnimationDirection.above);
      expect(b.leaving.spec.dx, closeTo(1.8, 1e-9),
          reason: "the arrival changed, not the way out");
      var back = ElementAnimation.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(back, a);
      // Set on the way in only: the way out stays the preset's own.
      var inOnly = const ElementAnimation(
          preset: ElementAnimationPreset.slideLeft,
          exit: ElementAnimationPreset.slideLeft,
          direction: AnimationDirection.above);
      var again = ElementAnimation.fromJson(
          jsonDecode(jsonEncode(inOnly.toJson())) as Map<String, dynamic>);
      expect(again.exitDirection, isNull);
    });

    test("kept with the element", () {
      var e = drawing(
          animation: const ElementAnimation(
              preset: ElementAnimationPreset.slideLeft,
              direction: AnimationDirection.aboveRight,
              strength: 1.5));
      var back = elementFromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)
          as VectorElement;
      expect(back.animation, e.animation);
    });

    test("a wipe starts from the edge its direction says", () async {
      Future<List<int>> wiped(AnimationDirection? way) async {
        var rec = PictureRecorder();
        var canvas = Canvas(rec);
        paintArriving(
            canvas,
            const Rect.fromLTWH(0, 0, 100, 100),
            ElementAnimation(
                preset: ElementAnimationPreset.wipe,
                ease: ChartEase.linear,
                direction: way),
            const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0.5}),
            () => canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100),
                Paint()..color = const Color(0xFF000000)));
        var img = await rec.endRecording().toImage(100, 100);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      int alpha(List<int> px, int x, int y) => px[(y * 100 + x) * 4 + 3];
      var left = await wiped(null);
      expect(alpha(left, 20, 50), 255);
      expect(alpha(left, 80, 50), 0);
      var right = await wiped(AnimationDirection.right);
      expect(alpha(right, 20, 50), 0);
      expect(alpha(right, 80, 50), 255);
      var below = await wiped(AnimationDirection.below);
      expect(alpha(below, 50, 20), 0);
      expect(alpha(below, 50, 80), 255);
    });
  });

  group("timing and preview", () {
    test("Delay and Length move the arrival", () {
      var c = CanvasController(const CanvasDocument()
          .copyWith(frames: 60)
          .addElement(drawing(
              animation: const ElementAnimation(
                  preset: ElementAnimationPreset.fadeIn))));
      addTearDown(c.dispose);
      CanvasElement now() => c.document.elementById("v")!;
      c.beginInteraction();
      c.setElementArrivalTiming(now(), delay: 10);
      c.setElementArrivalTiming(now(), length: 70);
      c.endInteraction();
      expect(c.elementAnimationSpan(now()), (10, 70));
      expect(c.document.frames, greaterThanOrEqualTo(81), reason: "grown");
      c.undo();
      expect(c.elementAnimationSpan(now()), (0, 20), reason: "one undo step");
    });

    test("a preview plays one element and leaves the playhead", () {
      var c = CanvasController(const CanvasDocument()
          .copyWith(frames: 120)
          .addElement(drawing(
              animation: const ElementAnimation(
                  preset: ElementAnimationPreset.fadeIn,
                  loop: ElementLoop(preset: LoopPreset.float, cycle: 10)),
              from: 30,
              to: 50)));
      addTearDown(c.dispose);
      c.frame = 5;
      var (from, to) = c.previewSpanOf(c.document.elementById("v")!);
      expect(from, 30);
      // Two goes round the loop after arriving, and a moment.
      expect(to, greaterThanOrEqualTo(70));
      expect(to, lessThan(90));
      c.previewElement("v");
      expect(c.previewing, (id: "v", frame: 30));
      expect(c.playing, isTrue);
      for (var i = 0; i < 10; i++) {
        c.tickForTest();
      }
      expect(c.previewing?.frame, 40);
      expect(c.frame, 5, reason: "the playhead stays");
      for (var i = 0; i < 200 && c.previewing != null; i++) {
        c.tickForTest();
      }
      expect(c.previewing, isNull, reason: "done");
      expect(c.playing, isFalse);
      c.previewElement("v");
      c.pause();
      expect(c.previewing, isNull, reason: "pausing stops it");
    });
  });

  group("stagger", () {
    test("each shape after the one before, a little overlapping", () {
      var e = withStagger(drawing(count: 4), 30);
      var times = cueTimes(e.shapes!, 30);
      for (var i = 1; i < times.length; i++) {
        var (start, _) = times[i];
        var (before, took) = times[i - 1];
        expect(start, greaterThan(before));
        expect(start, lessThan(before + took), reason: "overlapping");
      }
      var (lastStart, lastTook) = times.last;
      expect(lastStart + lastTook, closeTo(30, 1e-6),
          reason: "all of them over the arrival");
    });
  });

  group("the controls", () {});

  testWidgets("a layer picked is taken out with Backspace", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument()
        .copyWith(frames: 120)
        .addElement(drawing(count: 3)));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(panel(c));
    await tester.pumpAndSettle();
    VectorElement now() => c.document.elementById("v") as VectorElement;
    // The layer picked in the Layers strip, as a picture's is.
    var row = find.byKey(const ValueKey("vectorLayer-1"));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    var middle = now().shapes![1];
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(c.document.elementById("v"), isNotNull, reason: "not the drawing");
    expect(now().shapes!.length, 2);
    expect(now().shapes!.contains(middle), isFalse, reason: "the one picked");
    c.undo();
    expect(now().shapes!.length, 3, reason: "one undo step");
    expect(tester.takeException(), isNull);
  });

  testWidgets("the align tool lights the select tool it works with",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument()
        .copyWith(frames: 120)
        .addElement(drawing(count: 2)));
    addTearDown(c.dispose);
    c.selectOnly("v");
    c.editVector("v");
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(panel(c));
    await tester.pumpAndSettle();
    bool lit(String tool) => tester
        .widget<CanvasToolTiles<VectorTool>>(
            find.byKey(const ValueKey("vectorTools")))
        .lit(VectorTool.values.byName(tool));
    c.vectorTool = VectorTool.align;
    await tester.pumpAndSettle();
    expect(lit("align"), isTrue);
    expect(lit("select"), isTrue, reason: "points, with Select points");
    expect(lit("selectShapes"), isFalse);
    c.vectorTool = VectorTool.selectShapes;
    c.vectorTool = VectorTool.align;
    await tester.pumpAndSettle();
    expect(lit("selectShapes"), isTrue, reason: "shapes, with Select shapes");
    expect(lit("select"), isFalse);
    expect(tester.takeException(), isNull);
  });
}
