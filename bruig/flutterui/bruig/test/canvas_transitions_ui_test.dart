import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/transitions_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_transitions_ui_test.dart is the line that says how a scene gives way
// to the next one.

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
            width: width,
            child: CanvasTransitionsPanel(
              controller: controller,
              onPreview: () =>
                  controller.previewTransitionAfter(controller.document.at),
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
    expect(find.text("AFTER SCENE 1"), findsOneWidget);

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

  testWidgets("its length and overlap are frames", (tester) async {
    var controller = await bar(tester);
    controller.setSceneTransition(
        0, const SceneTransition(kind: SceneTransitionKind.fade));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey("transitionFrames")), "8");
    await tester.pumpAndSettle();
    expect(controller.document.transitionAfter(0).frames, 8);

    await tester.enterText(
        find.byKey(const ValueKey("transitionOverlap")), "3");
    await tester.pumpAndSettle();
    expect(controller.document.transitionAfter(0).overlap, 3);
  });

  testWidgets("a scene can be put back on the master's transition",
      (tester) async {
    // Which is what the switch is for: off, changing the default changes this
    // scene with it.
    var controller = await bar(tester);
    controller.setSceneTransition(
        0, const SceneTransition(kind: SceneTransitionKind.wipeLeft));
    await tester.pumpAndSettle();
    expect(controller.document.allScenes.first.custom, isTrue);

    await tester.tap(find.text("Set on this scene"));
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
    expect(find.text("EVERY SCENE, UNLESS IT SAYS OTHERWISE"), findsOneWidget);

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

  testWidgets("is laid out like the panel beside it", (tester) async {
    // Lifted from the line over the timeline, these controls kept that line's
    // arrangement: captions beside their controls and packed in tight, which
    // is right for a strip and wrong for a column.
    await bar(tester);

    // Something with settings to lay out: a cut has none.
    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Overlay").last);
    await tester.pumpAndSettle();

    // A control's own caption sits above it, as it does in the settings
    // panel. In the strip it sat beside it, which is what packed a dozen
    // controls into four hundred pixels.
    var caption = tester.getRect(find.text("Frames"));
    // The box itself rather than the control around it: the control is the
    // caption and the box together, so its own top says nothing about which
    // of the two is on top.
    var field = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey("transitionFrames")),
        matching: find.byType(EditableText)));
    expect(caption.bottom, lessThanOrEqualTo(field.top + 1),
        reason: "caption at ${caption.bottom}, its field at ${field.top}");
    expect((caption.left - field.left).abs(), lessThan(14),
        reason: "and starts at the same edge, give or take the box's own "
            "padding");

    // Plain groups, with the rule and the room the panel's own groups have --
    // no box round each section. A boxed section indents everything inside it
    // by the box's own padding, so what says there is no box is where the
    // controls start: hard against the panel's edge.
    var panel = tester.getRect(find.byType(CanvasTransitionsPanel));
    var firstControl = tester.getRect(find.text("Gives way with"));
    expect(firstControl.left - panel.left, lessThan(12),
        reason: "controls start at the panel's own edge: "
            "${firstControl.left - panel.left}");

    // A button with no caption of its own sits level with the controls that
    // have one, rather than three pixels high of them: the nudge that lines
    // it up allowed for the caption and not for the gap under it, which is
    // nothing at all until the button is in a row with two dropdowns.
    var play = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey("previewTransition")),
        matching: find.byType(Icon)));
    var box = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey("transitionKind")),
        matching: find.byType(Container)));
    expect((play.center.dy - box.center.dy).abs(), lessThan(1.5),
        reason: "the button's middle at ${play.center.dy}, the dropdown "
            "beside it at ${box.center.dy}");

    // And the panel's own heading is a sentence, so it is given the room one
    // needs: close under it, it and the caption below read as one paragraph.
    var heading = tester.getRect(find.textContaining("AFTER "));
    var under = tester.getRect(find.text("Gives way with"));
    expect(under.top - heading.bottom, greaterThan(10),
        reason: "${under.top - heading.bottom} between them");

    // And it scrolls the way a column does. The line it came from scrolled
    // sideways, which is how a dozen controls ended up somewhere off the end
    // of a four-hundred-pixel strip.
    var scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first);
    expect(scroll.scrollDirection, Axis.vertical);
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

    await tester.tap(find.byKey(const ValueKey("resetTransition")));
    await tester.pumpAndSettle();

    var back = controller.document.transitionAfter(0);
    expect(back.kind, kind, reason: "the same transition, not a different one");
    expect(back.count, SceneTransition.bestFor(kind).count);
    expect(back.spacing, SceneTransition.bestFor(kind).spacing);
    expect(back.frames, SceneTransition.bestFor(kind).frames);
  });

  testWidgets("the top row holds together in a narrow sidebar", (tester) async {
    // What this transition is, which one it is, play it, put it back: one
    // question and the two answers to it. The names were a fixed width, so
    // in a narrow sidebar the buttons were pushed onto a line of their own
    // with the whole width of the panel to the right of them.
    var controller = await bar(tester, width: 250);

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Overlay").last);
    await tester.pumpAndSettle();
    expect(controller.document.transitionAfter(0).on, isTrue);

    // Against the first of the two names, not the second: the two names
    // wrapping apart from each other is the same fault one step earlier.
    var names = tester.getRect(find.byKey(const ValueKey("transitionFamily")));
    for (var button in [
      "transitionKind",
      "resetTransition",
      "previewTransition"
    ]) {
      var box = tester.getRect(find.byKey(ValueKey(button)));
      expect(box.center.dy, closeTo(names.center.dy, 6),
          reason: "$button is on its own line: ${box.center.dy} against "
              "${names.center.dy}");
      expect(box.right, lessThanOrEqualTo(250),
          reason: "$button runs off the edge of the panel");
    }
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

  testWidgets("its settings are laid out in sections", (tester) async {
    // One group of a dozen controls is what this panel was, and a dozen
    // small boxes wrapped into a block reads as a field of boxes. The
    // settings panel beside it splits the same number into Colours, Amount
    // and Movement, and that is the whole of the difference between the two.
    await bar(tester);

    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Overlay").last);
    await tester.pumpAndSettle();

    expect(find.text("HOW LONG"), findsOneWidget);
    expect(find.text("WHAT IT LOOKS LIKE"), findsOneWidget);

    // And no empty heading with a rule under it where a transition has
    // nothing to say about how it looks.
    await tester.tap(find.byKey(const ValueKey("transitionFamily")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("A cut").last);
    await tester.pumpAndSettle();
    expect(find.text("HOW LONG"), findsNothing);
    expect(find.text("WHAT IT LOOKS LIKE"), findsNothing);
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

  testWidgets("with one scene the panel is not offered at all", (tester) async {
    // A whole panel of settings about an event that cannot happen. The
    // transition settings live in the sidebar now, beside the other panels --
    // a dozen controls laid out sideways over the timeline meant scrolling to
    // reach half of them and scrolling back to see what the first ones said.
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
    expect(find.text("TRANSITION"), findsNothing);

    controller.addScene();
    await tester.pumpAndSettle();
    expect(find.text("TRANSITION"), findsOneWidget,
        reason: "and it is there as soon as there is a scene after this one");
  });

  testWidgets("and the last scene has nothing to give way to", (tester) async {
    var controller = await bar(tester);
    controller.goToScene(1);
    await tester.pumpAndSettle();

    var button = tester.widget<InkWell>(find.descendant(
        of: find.byKey(const ValueKey("previewTransition")),
        matching: find.byType(InkWell)));
    expect(button.onTap, isNull);
  });
}
