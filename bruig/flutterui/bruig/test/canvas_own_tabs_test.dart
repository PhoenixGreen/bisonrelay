import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show ChainGroupColour;
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'package:bruig/plugin_system/canvas/ui/own_style.dart';
import 'package:bruig/plugin_system/canvas/ui/preset_pair.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_own_tabs_test.dart is the Motion clips card's Arrive, Loop and
// Leave (Ken, 2026-11-12: "you should probably be able to toggle between
// the 3 presets"), and the cards after it marked as the picked one's.

CanvasController make() {
  var c =
      CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
    TextElement(const ElementBase(id: "t", width: 400, height: 120),
        text: "Who sees your records?"),
  ]));
  c.selectOnly("t");
  return c;
}

TextElement text(CanvasController c) =>
    c.document.elementById("t") as TextElement;

Future<CanvasController> show(WidgetTester tester, CanvasController c) async {
  addTearDown(c.dispose);
  tester.view.physicalSize = const Size(3200, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
                listenable: c,
                builder: (context, _) =>
                    AnimationPanel(controller: c, height: 520)))),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  test("the settings panel's new leaving is the one the Chain shows", () {
    var c = make();
    addTearDown(c.dispose);
    c.applyTextAnimation(text(c), TextAnimationPreset.fadeIn);
    expect(c.ownTabOf(text(c)), MotionKind.arrive);
    c.applyTextExit(text(c), TextAnimationPreset.fadeIn);
    var (leave, _) = ownClipOf(text(c), MotionKind.leave)!;
    expect(c.pickedMotion, leave.id);
    expect(c.ownTabOf(text(c)), MotionKind.leave);
  });

  testWidgets("set up from the tabs: an arrival, then a leaving",
      (tester) async {
    var c = await show(tester, make());
    expect(find.byKey(const ValueKey("ownTabs")), findsOneWidget);
    expect(c.ownTabOf(text(c)), MotionKind.arrive,
        reason: "nothing yet: its arrival, to set up");
    expect(find.byKey(const ValueKey("ownTabPresetFamily")), findsOneWidget);
    tester
        .widget<StudioDrop<String>>(
            find.byKey(const ValueKey("ownTabPresetFamily")))
        .onChanged("Slide");
    await tester.pumpAndSettle();
    expect(text(c).animation.preset.family, TextAnimationFamily.slide);
    tester
        .widget<StudioDrop<TextAnimationPreset>>(
            find.byKey(const ValueKey("ownTabPreset")))
        .onChanged(TextAnimationPreset.slideUp);
    await tester.pumpAndSettle();
    expect(ownClipOf(text(c), MotionKind.arrive), isNotNull);
    expect(find.byKey(const ValueKey("motionZone-Arrive · Slide up")),
        findsOneWidget);
    // The leaving, from its tab: None, so its Preset to set it up.
    await tester.tap(find.byKey(const ValueKey("ownTab-leave")));
    await tester.pumpAndSettle();
    expect(c.ownTabOf(text(c)), MotionKind.leave);
    expect(find.byKey(const ValueKey("motionTimingCard")), findsNothing,
        reason: "no clip yet: not the arrival's cards");
    tester
        .widget<StudioDrop<String>>(
            find.byKey(const ValueKey("ownTabPresetFamily")))
        .onChanged("Fade");
    await tester.pumpAndSettle();
    var (leave, _) = ownClipOf(text(c), MotionKind.leave)!;
    expect(c.pickedMotion, leave.id);
    expect(
        find.byKey(ValueKey("motionZone-Leave · "
            "${c.ownPresetLabel(text(c), MotionKind.leave)}")),
        findsOneWidget);
    // Back to the arrival: its cards again.
    await tester.tap(find.byKey(const ValueKey("ownTab-arrive")));
    await tester.pumpAndSettle();
    var (arrive, _) = ownClipOf(text(c), MotionKind.arrive)!;
    expect(c.pickedMotion, arrive.id);
    expect(find.byKey(const ValueKey("motionTimingCard")), findsOneWidget);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey("motionTimingCard")),
            matching: find.byType(ChainGroupColour)),
        findsOneWidget,
        reason: "the arrival's, in its colour");
    expect(tester.takeException(), isNull);
  });

  testWidgets("the loop: its preset and its style, with no clip",
      (tester) async {
    var c = await show(tester, make());
    await tester.tap(find.byKey(const ValueKey("ownTab-loop")));
    await tester.pumpAndSettle();
    tester
        .widget<StudioDrop<String>>(
            find.byKey(const ValueKey("ownTabPresetFamily")))
        .onChanged("Motion");
    await tester.pumpAndSettle();
    tester
        .widget<StudioDrop<LoopPreset>>(
            find.byKey(const ValueKey("ownTabPreset")))
        .onChanged(LoopPreset.float);
    await tester.pumpAndSettle();
    expect(text(c).animation.loop.preset, LoopPreset.float);
    expect(
        find.byKey(const ValueKey("motionZone-Loop · Float")), findsOneWidget);
    expect(find.byKey(const ValueKey("ownStyleCard")), findsOneWidget);
    // Taken away: its tab says None.
    tester
        .widget<StudioDrop<String>>(
            find.byKey(const ValueKey("ownTabPresetFamily")))
        .onChanged("");
    await tester.pumpAndSettle();
    expect(c.ownPresetLabel(text(c), MotionKind.loop), "None");
    expect(find.byKey(const ValueKey("ownStyleCard")), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test("a family picked: the first of it, or as it is where it is one", () {
    var pair = PresetPair(textPresetOptions(), TextAnimationPreset.slideUp,
        TextAnimationPreset.none);
    expect(pair.family, "Slide");
    expect(pair.kinds.every((o) => o.family == "Slide"), isTrue);
    expect(pair.inFamily("Slide"), TextAnimationPreset.slideUp);
    expect(pair.inFamily("Fade").family, TextAnimationFamily.fade);
    expect(pair.inFamily(""), TextAnimationPreset.none);
    expect(pair.families.length, lessThan(pair.options.length),
        reason: "a shorter list");
  });
}
