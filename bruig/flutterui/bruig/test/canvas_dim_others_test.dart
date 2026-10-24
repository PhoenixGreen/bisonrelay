import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_dim_others_test.dart is one point of an argument taking the light
// as it arrives, and the points before it stepping back to let it.

/// _arriving is a shape that fades in from [from] over ten frames.
ShapeElement _arriving(String id, int from, {int? leaves}) => ShapeElement(
      ElementBase(
          id: id,
          track: ElementTrack([
            Keyframe(frame: from, values: const {KeyframeChannel.reveal: 0}),
            Keyframe(
                frame: from + 10, values: const {KeyframeChannel.reveal: 1}),
            if (leaves != null) ...[
              Keyframe(frame: leaves, values: const {KeyframeChannel.close: 0}),
              Keyframe(
                  frame: leaves + 10, values: const {KeyframeChannel.close: 1}),
            ],
          ])),
      animation: const ElementAnimation(
          preset: ElementAnimationPreset.fadeIn,
          exit: ElementAnimationPreset.fadeIn),
    );

CanvasController _beats() => CanvasController(CanvasDocument(frames: 200)
    .addElement(_arriving("first", 0))
    .addElement(_arriving("gone", 0, leaves: 15))
    .addElement(_arriving("second", 40))
    .addElement(_arriving("third", 80))
    .addElement(_arriving("later", 120)));

ElementTrack _track(CanvasController c, String id) =>
    c.document.elements.firstWhere((e) => e.id == id).base.track!;

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  test("what is on the canvas steps back as the next point arrives", () {
    var c = _beats();
    addTearDown(c.dispose);
    expect(c.dimOthers("second"), 1, reason: "only the first is on screen");

    var first = _track(c, "first");
    expect(first.at(40).opacity, 1, reason: "full until the second arrives");
    expect(first.at(52).opacity, closeTo(0.3, 0.001));
    expect(first.at(199).opacity, closeTo(0.3, 0.001), reason: "and stays");
    expect(_track(c, "gone").at(60).opacity, 1, reason: "long gone, untouched");
    expect(_track(c, "later").at(150).opacity, 1, reason: "not here yet");
    expect(_track(c, "second").at(60).opacity, 1, reason: "never itself");
  });

  test("and the next beat does not sink it further", () {
    var c = _beats();
    addTearDown(c.dispose);
    c.dimOthers("second");
    expect(c.dimOthers("third"), 1, reason: "the second; the first is dim");
    expect(_track(c, "first").at(150).opacity, closeTo(0.3, 0.001));
    expect(_track(c, "second").at(150).opacity, closeTo(0.3, 0.001));
  });

  test("its own arrival and exit go on working", () {
    // The keyframes the dimming lays sit among the arrival's; the arrival
    // still runs from nothing to all of it before the dimming begins.
    var c = _beats();
    addTearDown(c.dispose);
    c.dimOthers("third");
    var second = _track(c, "second");
    expect(second.at(45).values[KeyframeChannel.reveal], closeTo(0.5, 0.01));
    expect(second.at(50).opacity, 1);
  });

  testWidgets("the button in the Animation section dims the others",
      (tester) async {
    var c = _beats();
    addTearDown(c.dispose);
    c.selectOnly("second");
    tester.view.physicalSize = const Size(1400, 1800);
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
      child:
          MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
    var button = find.byKey(const ValueKey("elementDimOthers"));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(_track(c, "first").at(60).opacity, closeTo(0.3, 0.001));
    c.undo();
    expect(_track(c, "first").at(60).opacity, 1, reason: "one undo step");
  });
}
