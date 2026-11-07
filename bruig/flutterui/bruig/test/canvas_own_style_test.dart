import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceKnob;
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/own_style.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart'
    show shapeOf, VectorShapeKind;
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart'
    show groupStarts;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_own_style_test.dart is an element's own ways to arrive, leave and
// loop in its motion chain (Ken, 2026-11-08): the sidebar's Animation
// sections, every kind of element, in the chain -- the Preset of an own
// clip, and the "Its own style" card beside it.

Future<CanvasController> pump(WidgetTester tester, CanvasElement e,
    {MotionKind kind = MotionKind.arrive, double scale = 1}) async {
  tester.view.physicalSize = const Size(3000, 420);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var c = CanvasController(
      CanvasDocument(frames: 96, frameRate: 24, elements: [e]));
  addTearDown(c.dispose);
  var id = c.newClip(e.id, kind: kind, slot: 0);
  // Its own: what the element itself does, played across the clip.
  c.setMotion(
      e.id,
      c.motionOf(e.id).withClip(
          c.motionOf(e.id).clip(id)!.copyWith(inside: {"own": true})));
  c.pickMotion(e.id, id);
  c.selectOnly(e.id);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: c,
                builder: (context, _) =>
                    AnimationPanel(controller: c, height: 400)))),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  for (var scale in [1.0, 1.5]) {
    testWidgets("a text's own arrival, picked and set in the chain, at $scale",
        (tester) async {
      var c = await pump(
          tester,
          TextElement(const ElementBase(id: "t", width: 300, height: 60),
              text: "The security budget"),
          scale: scale);
      TextElement text() => c.document.elementById("t") as TextElement;
      var preset = tester.widget<StudioDrop<String>>(
          find.byKey(const ValueKey("motionClipsPreset")));
      expect(preset.options.map((o) => o.$1),
          contains("own:${TextAnimationPreset.pop.name}"),
          reason: "the words' own presets, offered");
      preset.onChanged("own:${TextAnimationPreset.pop.name}");
      await tester.pumpAndSettle();
      expect(text().animation.preset, TextAnimationPreset.pop);
      // The rest beside it: the gap between the words, their order.
      expect(find.byKey(const ValueKey("ownStyleCard")), findsOneWidget);
      tester
          .widget<DeviceKnob>(find.byKey(const ValueKey("ownGap")))
          .onChanged(1.5);
      await tester.pump();
      expect(text().animation.gap, 1.5);
      tester
          .widget<StudioDrop<bool>>(find.byKey(const ValueKey("ownOrder")))
          .onChanged(true);
      await tester.pump();
      expect(text().animation.flipOrder, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("a chart's own arrival: the presets its kind suits",
      (tester) async {
    var c = await pump(
        tester,
        ChartElement(const ElementBase(id: "c", width: 300, height: 200),
            data: ChartData.parse("Cat\tA\nx\t10\ny\t6")));
    var style = OwnStyle(c.document.elementById("c")!);
    var preset = tester.widget<StudioDrop<String>>(
        find.byKey(const ValueKey("motionClipsPreset")));
    for (var (name, _) in style.presets()) {
      expect(preset.options.map((o) => o.$1), contains("own:$name"));
    }
    preset.onChanged("own:grow");
    await tester.pumpAndSettle();
    expect((c.document.elementById("c") as ChartElement).animation.preset.name,
        "grow");
    expect(find.byKey(const ValueKey("ownGap")), findsOneWidget);
  });

  testWidgets("a box's cutting arrival: its pieces, as the sidebar had them",
      (tester) async {
    var c = await pump(tester,
        ShapeElement(const ElementBase(id: "s", width: 80, height: 80)));
    tester
        .widget<StudioDrop<String>>(
            find.byKey(const ValueKey("motionClipsPreset")))
        .onChanged("own:shatter");
    await tester.pumpAndSettle();
    ElementAnimation a() =>
        CanvasController.elementAnimationOf(c.document.elementById("s")!);
    expect(a().preset, ElementAnimationPreset.shatter);
    tester
        .widget<DeviceKnob>(find.byKey(const ValueKey("ownPieces")))
        .onChanged(20);
    await tester.pump();
    expect(a().effect.pieces, 20);
    tester
        .widget<StudioDrop<ChartEase>>(find.byKey(const ValueKey("ownEase")))
        .onChanged(ChartEase.bounce);
    await tester.pump();
    expect(a().ease, ChartEase.bounce);
    c.undo();
    expect(a().ease, isNot(ChartEase.bounce), reason: "one step each");
  });

  testWidgets("a loop's every setting, for a text too", (tester) async {
    var c = await pump(
        tester,
        TextElement(const ElementBase(id: "t", width: 300, height: 60),
            text: "Loops"),
        kind: MotionKind.loop);
    tester
        .widget<StudioDrop<LoopPreset>>(find.byKey(const ValueKey("ownLoop")))
        .onChanged(LoopPreset.float);
    await tester.pumpAndSettle();
    ElementLoop loop() =>
        CanvasController.elementLoopOf(c.document.elementById("t")!);
    expect(loop().preset, LoopPreset.float);
    expect(find.byKey(const ValueKey("ownStyleCard")), findsOneWidget);
    tester
        .widget<DeviceKnob>(find.byKey(const ValueKey("ownLoopRepeats")))
        .onChanged(3);
    await tester.pump();
    expect(loop().repeats, 3);
    tester
        .widget<DeviceKnob>(find.byKey(const ValueKey("ownLoopCycle")))
        .onChanged(2);
    await tester.pump();
    expect(loop().cycle, 48);
    expect(tester.takeException(), isNull);
  });

  // The sidebar's "This shape" and "Every shape", in the chain: a Shapes
  // card listing them, the picked one's cue and own arrival.
  testWidgets("a drawing's shapes: each comes in its own time", (tester) async {
    var c = await pump(
        tester,
        VectorElement(const ElementBase(id: "v", width: 120, height: 40),
            viewBox: const Rect.fromLTWH(0, 0, 120, 40),
            shapes: [
              for (var i = 0; i < 3; i++)
                shapeOf(VectorShapeKind.box, Rect.fromLTWH(40.0 * i, 0, 40, 40),
                    fill: const Color(0xFF0000FF)),
            ]));
    VectorElement v() => c.document.elementById("v") as VectorElement;
    expect(find.byKey(const ValueKey("partsCard")), findsOneWidget);
    expect(find.byKey(const ValueKey("partRow-2")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("partRow-2")));
    await tester.pump();
    tester
        .widget<StudioDrop<VectorCue>>(find.byKey(const ValueKey("partCue")))
        .onChanged(VectorCue.gap);
    await tester.pump();
    var third = v().shapes![groupStarts(v())[2]];
    expect(third.cue, VectorCue.gap);
    tester
        .widget<StudioDrop<ElementAnimationPreset?>>(
            find.byKey(const ValueKey("partArrival")))
        .onChanged(ElementAnimationPreset.shatter);
    await tester.pump();
    third = v().shapes![groupStarts(v())[2]];
    expect(third.animation?.preset, ElementAnimationPreset.shatter);
    expect(find.byKey(const ValueKey("partOwn-2")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("partsResetAll")));
    await tester.pump();
    expect(v().shapes!.every((s) => s.animation == null), isTrue,
        reason: "every shape back to the drawing's");
    c.undo();
    await tester.pump();
    // Let go: the drawing's own arrival again.
    tester
        .widget<StudioDrop<ElementAnimationPreset?>>(
            find.byKey(const ValueKey("partArrival")))
        .onChanged(null);
    await tester.pump();
    expect(v().shapes![groupStarts(v())[2]].animation, isNull);
    expect(find.byKey(const ValueKey("partOwn-2")), findsNothing);
    // One after another, then every one at once.
    await tester.tap(find.byKey(const ValueKey("partsStagger")));
    await tester.pump();
    expect(
        groupStarts(v())
            .skip(1)
            .every((g) => v().shapes![g].cue != VectorCue.together),
        isTrue);
    await tester.tap(find.byKey(const ValueKey("partsTogether")));
    await tester.pump();
    for (var g in groupStarts(v()).skip(1)) {
      expect(v().shapes![g].cue, VectorCue.together);
    }
    expect(tester.takeException(), isNull);
  });

  // The sidebar's picture layers, in the chain: staggered in, each one's
  // cue, and a layer looping on its own.
  testWidgets("a picture's layers: staggered, cued, one looping",
      (tester) async {
    var c = await pump(
        tester,
        ImageElement(const ElementBase(id: "i", width: 100, height: 100),
            assetId: "red",
            layers: [
              ImageLayer.base,
              ImageLayer.picture("blue", const Rect.fromLTWH(0, 0, 1000, 1000)),
            ]));
    ImageElement i() => c.document.elementById("i") as ImageElement;
    expect(find.byKey(const ValueKey("partsCard")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("partsStagger")));
    await tester.pump();
    expect(layersSequenced(i().stack), isTrue);
    c.undo();
    expect(layersSequenced(i().stack), isFalse, reason: "one step");

    await tester.tap(find.byKey(const ValueKey("partRow-1")));
    await tester.pump();
    var top = i().stack.last;
    tester
        .widget<StudioDrop<VectorCue>>(find.byKey(const ValueKey("partCue")))
        .onChanged(top.cue.next);
    await tester.pump();
    expect(i().stack.last.cue, top.cue.next);

    tester
        .widget<StudioDrop<LoopPreset>>(find.byKey(const ValueKey("partLoop")))
        .onChanged(LoopPreset.values.firstWhere((p) => p != LoopPreset.none));
    await tester.pump();
    expect(i().stack.last.loop.on, isTrue);
    expect(find.byKey(const ValueKey("partOwn-1")), findsOneWidget);
    tester
        .widget<DeviceKnob>(find.byKey(const ValueKey("partLoopCycle")))
        .onChanged(2.0);
    await tester.pump();
    expect(i().stack.last.loop.cycle, 48);
    expect(i().stack.first.loop.on, isFalse, reason: "the other, its own");
    await tester.tap(find.byKey(const ValueKey("partsResetAll")));
    await tester.pump();
    expect(i().stack.any((l) => l.loop.on), isFalse);
    expect(find.byKey(const ValueKey("partsResetAll")), findsNothing,
        reason: "nothing left to reset");
    c.undo();
    expect(i().stack.last.loop.on, isTrue, reason: "one undo step");
    expect(tester.takeException(), isNull);
  });

  // The sidebar's tests of what is offered, in the chain's terms.
  test("a chart is offered the presets its kind suits; a box has no gap", () {
    var bars = ChartElement(const ElementBase(id: "c"),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"));
    var names = OwnStyle(bars).presets().map((p) => p.$1);
    expect(names, isNot(contains("sweep")),
        reason: "a sweep round a bar chart is a sweep round a rectangle");
    expect(names, contains("grow"));
    expect(OwnStyle(bars).gap, isNotNull);
    var box = ShapeElement(const ElementBase(id: "s"));
    expect(OwnStyle(box).gap, isNull, reason: "nothing to space");
    // A text's arrival brings the curve its preset was made for.
    var text = TextElement(const ElementBase(id: "t"), text: "Hello");
    var popped =
        OwnStyle(text).withPreset(TextAnimationPreset.pop.name) as TextElement;
    expect(popped.animation.preset, TextAnimationPreset.pop);
    if (TextAnimationPreset.pop.wants case var wants?) {
      expect(popped.animation.ease, wants);
    }
  });
}
