import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceKnob;
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'canvas_chain_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_transitions_ui_test.dart is how a scene gives way to the next one,
// in the Animation panel: a scene double-clicked on the timeline opens its
// transition there, part by part.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<CanvasController> bar(WidgetTester tester,
      {CanvasDocument? document, double? width}) async {
    var controller = CanvasController(document ??
        const CanvasDocument().withScenes([
          const CanvasScene(id: "a", frames: 12),
          const CanvasScene(id: "b", frames: 12),
        ]));
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    controller.pickScene(controller.document.at);
    controller.showChain(motion: true);
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
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              // In the Chain, whose header names the scene and what it
              // gives way to.
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => ChainPanel(
                    controller: controller, height: 390, onResize: (_) {}),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets("a scene cuts to the next one until it is told otherwise",
      (tester) async {
    var controller = await bar(tester);
    expect(
        controller.document.transitionAfter(0).kind, SceneTransitionKind.cut);
    expect(find.text("Scene 1"), findsOneWidget);
    expect(find.text("gives way to Scene 2"), findsOneWidget);

    // The family first, then the one: two dozen names in a single list is a
    // wall nobody reads to the end of. Choosing a family applies the first of
    // its kinds, so the canvas shows something at once.
    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Fade").last);
    await tester.pumpAndSettle();

    expect(
        controller.document.transitionAfter(0).kind, SceneTransitionKind.fade,
        reason: "the first of the family it was given");

    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Cross fade").last);
    await tester.pumpAndSettle();

    expect(
        controller.document.transitionAfter(0).kind, SceneTransitionKind.fade);
    expect(controller.document.allScenes.first.custom, isTrue);
  });

  // Ken, 2026-11-08: the prototype's one Transition card, its length and
  // overlap knobs in seconds.
  testWidgets("its length and overlap are knobs in seconds", (tester) async {
    var controller = await bar(tester);
    controller.setSceneTransition(
        0, const SceneTransition(kind: SceneTransitionKind.fade));
    await tester.pumpAndSettle();
    var rate = controller.document.frameRate;
    tester
        .widget<DeviceKnob>(find.byKey(const ValueKey("transitionLength")))
        .onChanged(8 / rate);
    await tester.pumpAndSettle();
    expect(controller.document.transitionAfter(0).frames, 8);
    tester
        .widget<DeviceKnob>(find.byKey(const ValueKey("transitionOverlap")))
        .onChanged(3 / rate);
    await tester.pumpAndSettle();
    expect(controller.document.transitionAfter(0).overlap, 3);
    controller.undo();
    expect(controller.document.transitionAfter(0).overlap, 12,
        reason: "one step");
  });

  testWidgets("a scene can be put back on the master's transition",
      (tester) async {
    // Which is what Comes from is for: the master's, changing the default
    // changes this scene with it.
    var controller = await bar(tester);
    controller.setSceneTransition(
        0, const SceneTransition(kind: SceneTransitionKind.wipeLeft));
    await tester.pumpAndSettle();
    expect(controller.document.allScenes.first.custom, isTrue);
    tester
        .widget<StudioDrop<bool>>(
            find.byKey(const ValueKey("transitionCustom")))
        .onChanged(false);
    await tester.pumpAndSettle();
    expect(controller.document.allScenes.first.custom, isFalse);
    expect(controller.document.transitionAfter(0).kind, SceneTransitionKind.cut,
        reason: "back to the document's own, which is a cut");
  });

  testWidgets("on the master canvas it sets what every scene does",
      (tester) async {
    var controller = await bar(tester);
    controller.showMaster();
    await tester.pumpAndSettle();
    expect(find.text("Every scene"), findsOneWidget);
    expect(find.byKey(const ValueKey("transitionCustom")), findsNothing,
        reason: "it is where every other one comes from");

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Fade").last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Fade through a colour").last);
    await tester.pumpAndSettle();

    expect(controller.document.defaultTransition.kind,
        SceneTransitionKind.through);
    expect(controller.document.transitionAfter(0).kind,
        SceneTransitionKind.through,
        reason: "a scene with none of its own follows it");
    expect(controller.document.allScenes.first.custom, isFalse,
        reason: "and is not marked as having one");
  });

  testWidgets("the preview plays the join on the canvas", (tester) async {
    // The stage draws the whole run while it is playing, which is the same
    // function the export uses -- so what is watched is what will be
    // published.
    var controller = await bar(tester);
    controller.setSceneTransition(
        0,
        const SceneTransition(
            kind: SceneTransitionKind.fade, frames: 6, overlap: 6));
    await tester.pumpAndSettle();
    expect(controller.previewAt, isNull);

    await tester.tap(find.byKey(const ValueKey("previewTransition")));
    await tester.pump();
    expect(controller.previewAt, isNotNull,
        reason: "the canvas is showing the run rather than the scene");
    expect(controller.playing, isTrue);

    // It stops rather than running on through the document.
    await tester.pump(const Duration(seconds: 3));
    expect(controller.previewAt, isNull);
    expect(controller.playing, isFalse);
  });

  testWidgets("the overlay kinds bring their own settings", (tester) async {
    // A direction, a shape, how many bars, how soft the edge is -- each shown
    // only for the kinds it means anything for.
    var controller = await bar(tester);

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Overlay").last);
    await tester.pumpAndSettle();

    // The first of the overlay family is the band: a direction and a colour,
    // and no shape or bars.
    expect(
        controller.document.transitionAfter(0).kind, SceneTransitionKind.band);
    expect(find.byKey(const ValueKey("transitionWay")), findsOneWidget);
    expect(find.byKey(const ValueKey("transitionShape")), findsNothing);
    expect(find.byKey(const ValueKey("transitionCount")), findsNothing);

    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Blinds").last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("transitionCount")), findsOneWidget,
        reason: "blinds are made of a number of bars");

    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Shapes").last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("transitionShape")), findsOneWidget);
    expect(find.byKey(const ValueKey("transitionCount")), findsOneWidget,
        reason: "how many of them, and how far apart");
    expect(find.byKey(const ValueKey("transitionSpacing")), findsOneWidget);
    expect(find.byKey(const ValueKey("transitionRadius")), findsOneWidget,
        reason: "and how big each one is");
  });

  test("the preview works from the shared canvas, whichever scene was last",
      () {
    // Asked for the join after whatever scene was last open, the button did
    // nothing at all whenever that was the last scene -- which is what made
    // it seem temperamental.
    var controller = CanvasController(const CanvasDocument().withScenes([
      const CanvasScene(id: "a", frames: 12),
      const CanvasScene(id: "b", frames: 12),
    ]));
    addTearDown(controller.dispose);

    controller.goToScene(1);
    controller.showMaster();
    expect(controller.document.editingMaster, isTrue);

    controller.previewTransitionAfter(controller.document.at);
    expect(controller.previewAt, isNotNull,
        reason: "the first join stands for the default");

    controller.stopPreview();
    expect(controller.document.editingMaster, isTrue,
        reason: "and it puts the shared canvas back when it is done");
  });

  testWidgets("choosing a kind starts it where that kind looks best",
      (tester) async {
    // One set of settings cannot suit two dozen transitions: six is a
    // sensible number of blinds and a poor number of halftone dots, and
    // eighteen frames is slow for a cut and quick for paint being thrown at
    // a page and washed off again.
    var controller = await bar(tester);

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Drawn").last);
    await tester.pumpAndSettle();
    // The first of the family, which is what choosing a family gives you.
    var chevrons = controller.document.transitionAfter(0);
    expect(chevrons.kind, SceneTransitionKind.arrow);
    expect(chevrons.count,
        SceneTransition.bestFor(SceneTransitionKind.arrow).count);

    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Paint splatter").last);
    await tester.pumpAndSettle();

    var splats = controller.document.transitionAfter(0);
    expect(splats.count,
        SceneTransition.bestFor(SceneTransitionKind.splatter).count);
    expect(splats.count, isNot(chevrons.count),
        reason: "splats are not counted in chevrons");
  });

  testWidgets("and reset puts it back to that", (tester) async {
    // The two ways out of a transition that has been fiddled with past the
    // point of remembering what it was: the preview says what the fiddling
    // did, and this undoes all of it.
    var controller = await bar(tester);

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Drawn").last);
    await tester.pumpAndSettle();

    var kind = controller.document.transitionAfter(0).kind;
    controller.setSceneTransition(
        0,
        controller.document
            .transitionAfter(0)
            .copyWith(count: 37, spacing: 1.4, frames: 3));
    await tester.pumpAndSettle();

    // Reset every setting, in its card's menu.
    await revealInMenu(tester, "deviceReset-sceneTransition");
    await tester.tap(find.byKey(const ValueKey("deviceReset-sceneTransition")));
    await tester.pumpAndSettle();

    var back = controller.document.transitionAfter(0);
    expect(back.kind, kind, reason: "the same transition, not a different one");
    expect(back.count, SceneTransition.bestFor(kind).count);
    expect(back.spacing, SceneTransition.bestFor(kind).spacing);
    expect(back.frames, SceneTransition.bestFor(kind).frames);
  });

  testWidgets("barn doors come up with a direction already chosen",
      (tester) async {
    // They open on an axis rather than in four directions, and "to the
    // right" -- the way every transition started out pointing -- is not one
    // of the two, so the setting came up with nothing in it.
    var controller = await bar(tester);

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Overlay").last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Barn doors").last);
    await tester.pumpAndSettle();

    var doors = controller.document.transitionAfter(0);
    expect(SceneTransitionWay.waysFor(SceneTransitionKind.barn),
        contains(doors.way),
        reason: "pointed ${doors.way.name}, which barn doors cannot be");
    // And the dropdown says so rather than showing an empty box.
    expect(
        find.text(doors.way.saysFor(SceneTransitionKind.barn)), findsOneWidget);
  });

  // Ken, 2026-11-08: one card, as the prototype's, its settings those the
  // kind has.
  testWidgets("its settings are one card's, those the kind has",
      (tester) async {
    var controller = await bar(tester);
    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Overlay").last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("sceneTransitionCard")), findsOneWidget);
    expect(find.byKey(const ValueKey("transitionLength")), findsOneWidget);
    expect(find.byKey(const ValueKey("sceneTransitionScreen")), findsOneWidget,
        reason: "its screen plays it");
    expect(find.byKey(const ValueKey("animDevice-sceneTiming")), findsNothing,
        reason: "no separate sections any more");
    // A cut: no length, no look.
    controller.setSceneTransition(0, const SceneTransition());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("transitionLength")), findsNothing);
    expect(find.byKey(const ValueKey("transitionWay")), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the ways offered are the ones the kind has", (tester) async {
    // Four directions on everything was two settings that did nothing and
    // one that was missing: barn doors opened the same whether they were
    // told left or right, and shapes had no way of being told to stay where
    // they were.
    var controller = await bar(tester);

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Overlay").last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Barn doors").last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("transitionWay")));
    await tester.pumpAndSettle();
    expect(find.text("Up and down"), findsWidgets);
    expect(find.text("To the left"), findsNothing,
        reason: "a door opening left and one opening right are one setting");
    await tester.tap(find.text("Up and down").last);
    await tester.pumpAndSettle();
    expect(controller.document.transitionAfter(0).way, SceneTransitionWay.up);

    await tester.tap(find.byKey(const ValueKey("transitionKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Shapes").last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("transitionWay")));
    await tester.pumpAndSettle();
    expect(find.text("In place"), findsWidgets,
        reason: "shapes can grow where they stand rather than travelling");
    await tester.tap(find.text("In place").last);
    await tester.pumpAndSettle();
    expect(
        controller.document.transitionAfter(0).way, SceneTransitionWay.inPlace);
  });

  testWidgets("the sidebar has the vocal cues, with one scene or many",
      (tester) async {
    // The transition left for the Animation panel; what stayed is the cues,
    // which a single scene has as much as many.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
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
                width: 320, child: CanvasDesignPanel(controller: controller))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("VOCAL CUES"), findsOneWidget);
    expect(find.text("TRANSITION"), findsNothing);

    controller.addScene();
    await tester.pumpAndSettle();
    expect(find.text("VOCAL CUES"), findsOneWidget);
    expect(find.text("TRANSITION"), findsNothing);
    expect(find.byKey(const ValueKey("transitionFamily")), findsNothing);
  });

  testWidgets("and the last scene has nothing to give way to", (tester) async {
    var controller = await bar(tester);
    controller.goToScene(1);
    controller.pickScene(1);
    await tester.pumpAndSettle();
    expect(find.text("the last: gives way to nothing"), findsOneWidget);

    var button = tester.widget<InkWell>(find.descendant(
        of: find.byKey(const ValueKey("previewTransition")),
        matching: find.byType(InkWell)));
    expect(button.onTap, isNull);
  });
}
