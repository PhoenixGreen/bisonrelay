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
import 'package:bruig/plugin_system/canvas/render/element_effects.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  return VectorElement(
      ElementBase(
          id: "v",
          x: 100,
          y: 100,
          width: 40.0 * count,
          height: 40,
          track: animation.on
              ? ElementTrack([
                  Keyframe(frame: from, values: {KeyframeChannel.reveal: 0}),
                  Keyframe(frame: to, values: {KeyframeChannel.reveal: 1}),
                ])
              : null),
      viewBox: Rect.fromLTWH(0, 0, 40.0 * count, 40),
      shapes: [
        for (var i = 0; i < count; i++)
          shapeOf(VectorShapeKind.box, Rect.fromLTWH(40.0 * i, 0, 40, 40),
              fill: const Color(0xFF0000FF)),
      ],
      animation: animation);
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
      // Kept before they were told apart: the way out as it was, the
      // arrival's.
      var old = ElementAnimation.fromJson(const {
        "preset": "slideLeft",
        "exit": "slideLeft",
        "direction": "below",
        "strength": 1.5,
      });
      expect(old.exitDirection, AnimationDirection.below);
      expect(old.exitStrength, 1.5);
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
    test("Delay and Length move the arrival's keyframes", () {
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

  group("the controls", () {
    testWidgets(
        "slide is one choice with a Direction; Delay typed; Preview plays",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(
          const CanvasDocument().copyWith(frames: 120).addElement(drawing()));
      addTearDown(c.dispose);
      c.selectOnly("v");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(panel(c));
      await tester.pumpAndSettle();
      VectorElement now() => c.document.elementById("v") as VectorElement;

      var family = find.byKey(const ValueKey("elementAnimationFamily"));
      if (family.evaluate().isEmpty) {
        var heading = find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? "").toLowerCase() == "animation");
        await tester.ensureVisible(heading.first);
        await tester.tap(heading.first);
        await tester.pumpAndSettle();
      }
      tester
          .widget<CanvasDropdown<ElementAnimationFamily?>>(family)
          .onChanged(ElementAnimationFamily.slide);
      await tester.pumpAndSettle();
      expect(now().animation.preset.family, ElementAnimationFamily.slide);
      expect(find.byKey(const ValueKey("elementAnimationPreset")), findsNothing,
          reason: "one slide, not four");
      tester
          .widget<CanvasDropdown<AnimationDirection>>(
              find.byKey(const ValueKey("elementAnimationDirection")))
          .onChanged(AnimationDirection.below);
      await tester.pumpAndSettle();
      expect(now().animation.direction, AnimationDirection.below);
      // The way out, with its own.
      tester
          .widget<CanvasDropdown<ElementAnimationFamily?>>(
              find.byKey(const ValueKey("elementAnimationExitFamily")))
          .onChanged(ElementAnimationFamily.slide);
      await tester.pumpAndSettle();
      tester
          .widget<CanvasDropdown<AnimationDirection>>(
              find.byKey(const ValueKey("elementAnimationExitDirection")))
          .onChanged(AnimationDirection.right);
      await tester.pumpAndSettle();
      expect(now().animation.exitDirection, AnimationDirection.right);
      expect(now().animation.direction, AnimationDirection.below,
          reason: "the way in left as it was");
      expect(find.byKey(const ValueKey("elementAnimationExitStrength")),
          findsOneWidget);
      expect(find.byKey(const ValueKey("elementAnimationStrength")),
          findsOneWidget);

      // The curve picker draws each curve.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementAnimationEase")),
              matching: find.byType(EaseCurve)),
          findsWidgets);

      var delay = tester.widget<CanvasNumberField>(
          find.byKey(const ValueKey("elementAnimationDelay")));
      delay.onChanged(12);
      delay.onCommit!();
      await tester.pumpAndSettle();
      var (at, span) = c.elementAnimationSpan(now());
      expect(at, 12);
      expect(span, isNotNull);

      var preview = find.byKey(const ValueKey("elementAnimationPreview"));
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pump();
      expect(c.previewing?.id, "v");
      c.pause();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets("Stagger gives a drawing with no arrival one, in one step",
        (tester) async {
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

      var stagger = find.byKey(const ValueKey("vectorStagger"));
      if (stagger.evaluate().isEmpty) {
        var heading = find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? "").toLowerCase() == "playlist");
        await tester.ensureVisible(heading.first);
        await tester.tap(heading.first);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(stagger);
      await tester.tap(stagger);
      await tester.pumpAndSettle();
      expect(now().animation.on, isTrue);
      expect(sequenced(now().shapes!), isTrue);
      expect(vectorArrivalSpan(now()), isNotNull);
      c.undo();
      expect(now().animation.on, isFalse, reason: "one undo step");
      expect(sequenced(now().shapes!), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets("a playlist row picked is taken out with Backspace",
      (tester) async {
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
    var row = find.byKey(const ValueKey("vectorPlaylist-1"));
    if (row.evaluate().isEmpty) {
      var heading = find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? "").toLowerCase() == "playlist");
      await tester.ensureVisible(heading.first);
      await tester.tap(heading.first);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(row);
    await tester.tap(find.descendant(of: row, matching: find.text("2")));
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

  testWidgets("the playlist: Preview level with its words; Master, Reset",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument()
        .copyWith(frames: 120)
        .addElement(drawing(
            count: 2,
            animation: const ElementAnimation(
                preset: ElementAnimationPreset.fadeIn))));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(panel(c));
    await tester.pumpAndSettle();
    VectorElement now() => c.document.elementById("v") as VectorElement;

    var words = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? "").toLowerCase() == "playlist");
    var preview = find.byKey(const ValueKey("elementAnimationPreview"));
    expect(
        (tester.getCenter(preview).dy - tester.getCenter(words.first).dy).abs(),
        lessThan(2),
        reason: "the button in line with the heading");

    var master = find.byKey(const ValueKey("vectorPlaylistMaster"));
    if (master.evaluate().isEmpty) {
      await tester.tap(words.first);
      await tester.pumpAndSettle();
    }
    // A shape picked, and given its own loop.
    c.editVector("v");
    c.pickVectorShape(1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("vectorShapeAnimationScope")),
        findsOneWidget);
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
    expect(now().shapes![1].owns, isNotEmpty);
    var reset = find.byKey(const ValueKey("vectorShapeAnimationReset"));
    expect(
        (tester.getCenter(reset).dy -
                tester
                    .getCenter(
                        find.byKey(const ValueKey("vectorShapeAnimationScope")))
                    .dy)
            .abs(),
        lessThan(2),
        reason: "Reset level with the words beside it");
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(now().shapes![1].animation, isNull, reason: "back to the drawing's");

    // Master: the drawing's own animation, no shape picked.
    await tester.ensureVisible(master);
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(c.vectorShape, -1);
    expect(
        find.byKey(const ValueKey("vectorShapeAnimationScope")), findsNothing);
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
        .widget<CanvasIconButton>(find.byKey(ValueKey("vectorTool-$tool")))
        .active;
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

  testWidgets("Reset all puts every shape back to the Master, in one step",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var e = drawing(count: 3);
    e = e.copyWith(shapes: [
      for (var s in e.shapes!)
        s.copyWith(
            animation: const ElementAnimation(
                loop: ElementLoop(preset: LoopPreset.pulse)),
            owns: {ShapeAnimationPart.looping}),
    ]);
    var c = CanvasController(
        const CanvasDocument().copyWith(frames: 120).addElement(e));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(panel(c));
    await tester.pumpAndSettle();
    VectorElement now() => c.document.elementById("v") as VectorElement;
    var all = find.byKey(const ValueKey("vectorResetAllAnimation"));
    if (all.evaluate().isEmpty) {
      var heading = find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? "").toLowerCase() == "playlist");
      await tester.ensureVisible(heading.first);
      await tester.tap(heading.first);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(now().shapes!.every((s) => s.animation == null), isTrue);
    expect(tester.widget<CanvasIconButton>(all).onPressed, isNull,
        reason: "nothing left to reset");
    c.undo();
    expect(now().shapes!.every((s) => s.animation != null), isTrue,
        reason: "one undo step");
    expect(tester.takeException(), isNull);
  });

  testWidgets("Kind and Which share a line; numbers, not sliders",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument()
        .copyWith(frames: 120)
        .addElement(drawing(
            animation: const ElementAnimation(
                preset: ElementAnimationPreset.scaleIn,
                exit: ElementAnimationPreset.fadeUp,
                loop: ElementLoop(preset: LoopPreset.shimmer)))));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(panel(c));
    await tester.pumpAndSettle();
    var kind = find.byKey(const ValueKey("elementAnimationFamily"));
    if (kind.evaluate().isEmpty) {
      var heading = find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? "").toLowerCase() == "animation");
      await tester.ensureVisible(heading.first);
      await tester.tap(heading.first);
      await tester.pumpAndSettle();
    }
    for (var (k, w) in const [
      ("elementAnimationFamily", "elementAnimationPreset"),
      ("elementAnimationExitFamily", "elementAnimationExit"),
    ]) {
      var a = tester.getRect(find.byKey(ValueKey(k)));
      var b = tester.getRect(find.byKey(ValueKey(w)));
      expect(a.top, closeTo(b.top, 1), reason: "$k beside $w");
      expect(a.width, closeTo(b.width, 1), reason: "half each");
    }
    var strength = find.byKey(const ValueKey("elementAnimationStrength"));
    expect(
        tester.getRect(strength).top, greaterThan(tester.getRect(kind).bottom),
        reason: "the motion on the line below");
    expect(find.byType(Slider), findsNothing, reason: "numbers to scrub");
    expect(find.text("TIMING / KEYFRAME"), findsOneWidget);
    expect(find.byKey(const ValueKey("elementKeyframeEasing")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
