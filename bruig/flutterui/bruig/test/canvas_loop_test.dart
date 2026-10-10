import 'dart:convert';
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_loop_test.dart is an element's loop: when it plays, what it does to
// the element as it goes round, how it is kept, and its controls -- the
// Animation section's Looping group and its bar on the timeline.

/// box is a drawing of one blue square, 40 across, at (100, 100).
VectorElement box(
        {ElementLoop loop = const ElementLoop(), ElementTrack? track}) =>
    VectorElement(
        ElementBase(
            id: "v", x: 100, y: 100, width: 40, height: 40, track: track),
        viewBox: const Rect.fromLTWH(0, 0, 40, 40),
        shapes: [
          shapeOf(VectorShapeKind.box, const Rect.fromLTWH(0, 0, 40, 40),
              fill: const Color(0xFF0000FF)),
        ],
        animation: ElementAnimation(loop: loop));

void main() {
  group("when a loop plays", () {
    test("from the arrival's end, or the start, to the scene's end", () {
      const loop = ElementLoop(preset: LoopPreset.float, cycle: 10);
      expect(loop.span(last: 99), (0, 99));
      expect(loop.span(arrived: 20, last: 99), (20, 99));
      expect(
          loop.copyWith(from: 5, to: 50).span(arrived: 20, last: 99), (5, 50));
      // Three goes round of ten, four frames' rest between: done at 37.
      expect(loop.copyWith(repeats: 3, gap: 4).span(last: 99), (0, 37));
    });

    test("it rests between goes round, and not before it starts", () {
      const loop =
          ElementLoop(preset: LoopPreset.float, cycle: 10, gap: 5, from: 10);
      expect(loop.poseAt(5, last: 99), isNull, reason: "not started");
      expect(loop.poseAt(12, last: 99), isNotNull);
      expect(loop.poseAt(22, last: 99), isNull, reason: "resting");
      expect(loop.poseAt(25, last: 99), isNotNull, reason: "round again");
      // A quarter of the way round, Float is at its highest.
      var top = loop.poseAt(10 + 25 ~/ 10, last: 99)!;
      expect(top.dy, lessThan(0));
    });

    test("each motion moves, turns or sizes the element", () {
      for (var preset in LoopPreset.inFamily(LoopFamily.motion)) {
        var loop = ElementLoop(preset: preset, cycle: 40);
        var moved = false;
        for (var f = 0; f < 40; f++) {
          var p = loop.poseAt(f, last: 99)!;
          if (p.dx != 0 ||
              p.dy != 0 ||
              p.turn != 0 ||
              p.sx != 1 ||
              p.sy != 1 ||
              p.opacity != 1) {
            moved = true;
          }
        }
        expect(moved, isTrue, reason: "$preset");
      }
      // Stronger is further.
      var weak = const ElementLoop(preset: LoopPreset.sway, cycle: 40)
          .poseAt(10, last: 99)!;
      var strong =
          const ElementLoop(preset: LoopPreset.sway, cycle: 40, strength: 2)
              .poseAt(10, last: 99)!;
      expect(strong.turn, closeTo(weak.turn * 2, 1e-9));
    });

    test("kept with the element, on its own as well as with an arrival", () {
      var e = box(
          loop: const ElementLoop(
              preset: LoopPreset.heartbeat,
              cycle: 30,
              gap: 6,
              repeats: 4,
              strength: 1.5,
              ease: ChartEase.easeOut,
              from: 3,
              to: 90));
      expect(e.animation.on, isFalse, reason: "no arrival");
      expect(e.animation.any, isTrue);
      var back = elementFromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)
          as VectorElement;
      expect(back.animation.loop, e.animation.loop);
    });

    test("drawn: the element moved as the loop says", () async {
      Future<int> topmost(VectorElement e, int frame) async {
        var rec = PictureRecorder();
        paintElement(Canvas(rec), e, frame);
        var img = await rec.endRecording().toImage(240, 240);
        var px = (await img.toByteData())!.buffer.asUint8List();
        for (var y = 0; y < 240; y++) {
          if (px[(y * 240 + 120) * 4 + 3] > 128) return y;
        }
        return -1;
      }

      var still = box();
      var floating =
          box(loop: const ElementLoop(preset: LoopPreset.float, cycle: 40));
      expect(await topmost(still, 10), 100);
      expect(await topmost(floating, 0), 100, reason: "where it starts");
      // A quarter of the way round, it is up by 6% of its 40.
      expect(await topmost(floating, 10), closeTo(100 - 2.4, 1));
    });
  });

  group("loops that draw", () {
    Future<List<int>> draw(VectorElement e, int frame) async {
      var rec = PictureRecorder();
      paintElement(Canvas(rec), e, frame);
      var img = await rec.endRecording().toImage(240, 240);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    test("every one of them changes what is drawn, part way round", () async {
      var plain = await draw(box(), 6);
      for (var family in [
        LoopFamily.light,
        LoopFamily.line,
        LoopFamily.effect
      ]) {
        for (var preset in LoopPreset.inFamily(family)) {
          var looped = box(
              loop: ElementLoop(
                  preset: preset,
                  cycle: 40,
                  colour: const PaintSpec(Color(0xFFFFFF00))));
          var differs = false;
          // Somewhere in the first part of the cycle -- the glitch only
          // breaks up in its first fifth.
          for (var f in [1, 3, 6, 10, 16]) {
            var px = await draw(looped, f);
            for (var i = 0; i < px.length && !differs; i += 4) {
              if ((px[i] - plain[i]).abs() > 8 ||
                  (px[i + 1] - plain[i + 1]).abs() > 8 ||
                  (px[i + 2] - plain[i + 2]).abs() > 8 ||
                  (px[i + 3] - plain[i + 3]).abs() > 8) {
                differs = true;
              }
            }
            if (differs) break;
          }
          expect(differs, isTrue, reason: "$preset");
          expect(looped.animation.loop.poseAt(6, last: 99),
              preset.moves ? isNotNull : isNull,
              reason: "$preset: a move only where it moves");
        }
      }
    });

    test("a shimmer brightens the element, and nothing outside it", () async {
      var plain = await draw(box(), 20);
      var shimmer = await draw(
          box(
              loop: const ElementLoop(
                  preset: LoopPreset.shimmer, cycle: 40, angle: 0)),
          20);
      int at(List<int> px, int x, int y, int c) => px[(y * 240 + x) * 4 + c];
      // Half way round, the band is across the middle: brighter there.
      expect(
          at(shimmer, 120, 120, 0), greaterThan(at(plain, 120, 120, 0) + 60));
      // Off the element: still nothing.
      expect(at(shimmer, 90, 120, 3), 0);
    });

    test("its colour, band and angle are kept", () {
      var e = box(
          loop: const ElementLoop(
              preset: LoopPreset.colourWave,
              colour: PaintSpec(Color(0xFFFF9800),
                  gradient: GradientSpec(to: Color(0xFFE91E63))),
              band: 0.5,
              angle: -30));
      var back = elementFromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)
          as VectorElement;
      expect(back.animation.loop, e.animation.loop);
    });
  });

  group("a drawing's own shapes", () {
    /// pair is a drawing of two squares side by side, red then blue, each
    /// 40 across, at (100, 100) and (160, 100) -- the second with [own]
    /// animation in place of the drawing's; the drawing with [animation],
    /// coming in over frames 0 to 20 where it has one, and leaving over 30
    /// to 40 where it leaves.
    VectorElement pair(
        {ElementAnimation? own,
        ElementAnimation animation = const ElementAnimation()}) {
      var second = shapeOf(
              VectorShapeKind.box, const Rect.fromLTWH(60, 0, 40, 40),
              fill: const Color(0xFF0000FF))
          .copyWith(
              animation: own,
              owns: own == null ? null : ShapeAnimationPart.values.toSet());
      return VectorElement(
          ElementBase(
              id: "v",
              x: 100,
              y: 100,
              width: 100,
              height: 40,
              track: ElementTrack([
                if (animation.on) ...const [
                  Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
                  Keyframe(frame: 20, values: {KeyframeChannel.reveal: 1}),
                ],
                if (animation.closes) ...const [
                  Keyframe(frame: 30, values: {KeyframeChannel.close: 0}),
                  Keyframe(frame: 40, values: {KeyframeChannel.close: 1}),
                ],
              ])),
          viewBox: const Rect.fromLTWH(0, 0, 100, 40),
          shapes: [
            shapeOf(VectorShapeKind.box, const Rect.fromLTWH(0, 0, 40, 40),
                fill: const Color(0xFFFF0000)),
            second,
          ],
          animation: animation);
    }

    Future<List<int>> draw(VectorElement e, int frame) async {
      var rec = PictureRecorder();
      paintElement(Canvas(rec), e, frame,
          document: const CanvasDocument().copyWith(frames: 120));
      var img = await rec.endRecording().toImage(240, 240);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    int topmost(List<int> px, int x) {
      for (var y = 0; y < 240; y++) {
        if (px[(y * 240 + x) * 4 + 3] > 128) return y;
      }
      return -1;
    }

    int alphaAt(List<int> px, int x) => px[(120 * 240 + x) * 4 + 3];
    const floating = ElementLoop(preset: LoopPreset.float, cycle: 40);
    const fading = ElementAnimation(preset: ElementAnimationPreset.fadeIn);

    test("kept with the shape -- and read from the two it was kept as", () {
      var e = pair(
          own: const ElementAnimation(
              preset: ElementAnimationPreset.fadeUp,
              exit: ElementAnimationPreset.blurIn,
              loop: ElementLoop(preset: LoopPreset.sparkle, cycle: 30)));
      var back = elementFromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)
          as VectorElement;
      expect(back.shapes![1].animation, e.shapes![1].animation);
      expect(back.shapes![0].animation, isNull, reason: "as the drawing");

      var before = VectorShape.fromJson({
        "p": [],
        "arrive": {"preset": "fadeUp", "ease": "linear"},
        "loop": {"preset": "pulse"},
      })!;
      expect(before.animation?.preset, ElementAnimationPreset.fadeUp);
      expect(before.animation?.loop.preset, LoopPreset.pulse);
    });

    test("a shape loops on its own, about its own box", () async {
      var e = pair(own: const ElementAnimation(loop: floating));
      var start = await draw(e, 0), quarter = await draw(e, 10);
      expect(topmost(start, 180), 100);
      // A quarter of the way round: up by 6% of its own 40.
      expect(topmost(quarter, 180), closeTo(100 - 2.4, 1));
      expect(topmost(quarter, 120), 100, reason: "the other stays still");
    });

    test("a shape loops once it has come in", () async {
      var e = pair(animation: fading, own: fading.copyWith(loop: floating));
      // Coming in over 0-20, together: its loop starts at 20.
      expect(topmost(await draw(e, 20), 180), 100);
      expect(topmost(await draw(e, 30), 180), closeTo(100 - 2.4, 1));
    });

    test("its own loop is in place of the drawing's", () async {
      // The drawing floats; the second shape has an animation of its own
      // with no loop, so it alone stays still.
      var e = pair(
          animation: const ElementAnimation(loop: floating),
          own: const ElementAnimation());
      var quarter = await draw(e, 10);
      expect(topmost(quarter, 120), closeTo(100 - 2.4, 1),
          reason: "as the drawing");
      expect(topmost(quarter, 180), 100, reason: "its own: none");
    });

    test("a shape comes in its own way, or as the drawing does", () async {
      var asDrawing = await draw(pair(animation: fading), 10);
      var none = await draw(
          pair(animation: fading, own: const ElementAnimation()), 10);
      expect(alphaAt(asDrawing, 180), lessThan(230), reason: "half faded");
      expect(alphaAt(none, 180), 255, reason: "no way in of its own");
      expect(alphaAt(none, 120), lessThan(230),
          reason: "the other still fades, as the drawing");
    });

    test("what a shape has not made its own follows the drawing", () async {
      // Its own loop, and nothing else: the drawing's way in still brings it
      // in, and changing that changes it.
      var second = shapeOf(
              VectorShapeKind.box, const Rect.fromLTWH(60, 0, 40, 40),
              fill: const Color(0xFF0000FF))
          .copyWith(
              animation: const ElementAnimation(loop: floating),
              owns: {ShapeAnimationPart.looping});
      VectorElement with_(ElementAnimation drawing) => pair(animation: drawing)
          .copyWith(shapes: [pair().shapes!.first, second]);
      var fades = await draw(with_(fading), 10);
      expect(alphaAt(fades, 180), lessThan(230),
          reason: "the drawing's fade, half way in");
      var none = await draw(with_(const ElementAnimation()), 10);
      expect(alphaAt(none, 180), 255, reason: "no arrival on the drawing");
      // And it is kept knowing which parts are its own.
      var back = elementFromJson(jsonDecode(jsonEncode(with_(fading).toJson()))
          as Map<String, dynamic>) as VectorElement;
      expect(back.shapes![1].owns, {ShapeAnimationPart.looping});
    });

    test("the drawing's keyframe easing paces shapes coming in in turn",
        () async {
      VectorElement turned(KeyframeEasing easing) {
        var e = pair(animation: fading);
        return e.copyWith(shapes: [
          e.shapes!.first,
          e.shapes![1].copyWith(cue: VectorCue.after),
        ]).withBase(
            track: ElementTrack([
          Keyframe(
              frame: 0,
              values: const {KeyframeChannel.reveal: 0},
              easing: easing),
          const Keyframe(frame: 20, values: {KeyframeChannel.reveal: 1}),
        ])) as VectorElement;
      }

      // Eased in, the first shape is less far in a quarter of the way.
      var linear = await draw(turned(KeyframeEasing.linear), 5);
      var eased = await draw(turned(KeyframeEasing.easeIn), 5);
      expect(alphaAt(eased, 120), lessThan(alphaAt(linear, 120)));
    });

    test("a shape leaves its own way, or as the drawing does", () async {
      var leaving = fading.copyWith(exit: ElementAnimationPreset.fadeIn);
      var px = await draw(pair(animation: leaving, own: fading), 35);
      expect(alphaAt(px, 120), lessThan(230), reason: "the drawing's way out");
      expect(alphaAt(px, 180), 255, reason: "its own: staying");
    });
  });

  group("the controls", () {
    testWidgets("the Looping group sets a loop, and the timeline shows it",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(
          const CanvasDocument().copyWith(frames: 120).addElement(box()));
      addTearDown(c.dispose);
      c.selectOnly("v");
      tester.view.physicalSize = const Size(1400, 1800);
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
                body: Row(children: [
          SizedBox(width: 420, child: CanvasDesignPanel(controller: c)),
          Expanded(
              child: Align(
                  alignment: Alignment.bottomCenter,
                  child: CanvasTimeline(
                      controller: c, height: timelineHeight + 40))),
        ]))),
      ));
      await tester.pumpAndSettle();
      VectorElement now() => c.document.elementById("v") as VectorElement;

      // Open the Animation section, if it is shut.
      var family = find.byKey(const ValueKey("elementLoopFamily"));
      if (family.evaluate().isEmpty) {
        var heading = find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? "").toLowerCase() == "animation");
        await tester.ensureVisible(heading.first);
        await tester.tap(heading.first);
        await tester.pumpAndSettle();
      }
      tester
          .widget<CanvasDropdown<LoopFamily?>>(family)
          .onChanged(LoopFamily.motion);
      await tester.pumpAndSettle();
      expect(now().animation.loop.preset, LoopPreset.float);
      expect(find.byKey(const ValueKey("elementLoopCycle")), findsOneWidget);

      // Its bar, under the keyframes, runs to the scene's end; its end
      // dragged back to frame 60 stops it there.
      var strip = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      double xOf(int frame) => strip.left + strip.width * frame / 120;
      var y = strip.top + 44 + 8;
      await tester.dragFrom(
          Offset(xOf(120) - 1, y), Offset(xOf(61) - xOf(120), 0));
      await tester.pumpAndSettle();
      expect(now().animation.loop.to, closeTo(60, 1));
      c.undo();
      expect(now().animation.loop.to, isNull, reason: "one undo step");
      expect(tester.takeException(), isNull);
    });

    testWidgets("with a shape picked, the Animation section is the shape's",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var two = box();
      two = two.copyWith(shapes: [
        ...two.shapes!,
        shapeOf(VectorShapeKind.box, const Rect.fromLTWH(10, 10, 20, 20),
            fill: const Color(0xFFFF0000)),
      ]);
      var c = CanvasController(
          const CanvasDocument().copyWith(frames: 120).addElement(two));
      addTearDown(c.dispose);
      c.selectOnly("v");
      c.editVector("v");
      c.pickVectorShape(1);
      tester.view.physicalSize = const Size(900, 4000);
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
      VectorElement now() => c.document.elementById("v") as VectorElement;
      Text scope() => tester.widget<Text>(
          find.byKey(const ValueKey("vectorShapeAnimationScope")));

      var family = find.byKey(const ValueKey("elementLoopFamily"));
      if (family.evaluate().isEmpty) {
        var heading = find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? "").toLowerCase() == "animation");
        await tester.ensureVisible(heading.first);
        await tester.tap(heading.first);
        await tester.pumpAndSettle();
      }
      expect(find.text("Shape arriving"), findsNothing);
      expect(find.text("Shape looping"), findsNothing);
      expect(scope().data, contains("as the drawing"));

      tester
          .widget<CanvasDropdown<LoopFamily?>>(family)
          .onChanged(LoopFamily.light);
      await tester.pumpAndSettle();
      expect(now().shapes![1].animation?.loop.preset, LoopPreset.shimmer);
      expect(now().shapes![0].animation, isNull);
      expect(now().animation.loop.on, isFalse, reason: "not the drawing's");
      expect(scope().data, contains("own looping"));

      // A way in, with nothing on the timeline to time it by: the drawing
      // is given one too, in the same step.
      tester
          .widget<CanvasDropdown<ElementAnimationFamily?>>(
              find.byKey(const ValueKey("elementAnimationFamily")))
          .onChanged(ElementAnimationFamily.fade);
      await tester.pumpAndSettle();
      expect(now().shapes![1].animation?.on, isTrue);
      expect(now().animation.on, isTrue);
      c.undo();
      await tester.pumpAndSettle();
      expect(now().shapes![1].animation?.on, isFalse, reason: "one undo step");
      expect(now().animation.on, isFalse);

      // Back to the drawing's.
      var reset = find.byKey(const ValueKey("vectorShapeAnimationReset"));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(now().shapes![1].animation, isNull);

      // And the drawing's own, with no shape picked.
      var drawing = find.byKey(const ValueKey("vectorPlaylistMaster"));
      if (drawing.evaluate().isEmpty) {
        var heading = find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? "").toLowerCase() == "playlist");
        await tester.ensureVisible(heading.first);
        await tester.tap(heading.first);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(drawing);
      await tester.tap(drawing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("vectorShapeAnimationScope")),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
