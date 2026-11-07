import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_dim_others_test.dart is one point of an argument taking the light
// as it arrives, and the points before it stepping back to let it.

/// _arriving is a shape that fades in from [from] over ten frames, by its
/// own arrival clip -- and out from [leaves], if it is given.
CanvasElement _arriving(String id, int from, {int? leaves}) {
  CanvasElement e = ShapeElement(
    ElementBase(id: id),
    animation: const ElementAnimation(
        preset: ElementAnimationPreset.fadeIn,
        exit: ElementAnimationPreset.fadeIn),
  );
  e = withOwnSpan(e, MotionKind.arrive, from, from + 10, _rate);
  if (leaves != null) {
    e = withOwnSpan(e, MotionKind.leave, leaves, leaves + 10, _rate);
  }
  return e;
}

/// _rate is the canvas's frame rate, which the arrivals are timed in.
const _rate = 24;

CanvasController _beats() =>
    CanvasController(CanvasDocument(frames: 200, frameRate: _rate)
        .addElement(_arriving("first", 0))
        .addElement(_arriving("gone", 0, leaves: 15))
        .addElement(_arriving("second", 40))
        .addElement(_arriving("third", 80))
        .addElement(_arriving("later", 120)));

ElementTrack _track(CanvasController c, String id) =>
    c.document.elements.firstWhere((e) => e.id == id).base.track ??
    ElementTrack.empty;

void main() {
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
    // The keyframes the dimming lays leave the arrival's clip as it was; the
    // element is fully there when its arrival ends, before the dimming.
    var c = _beats();
    addTearDown(c.dispose);
    c.dimOthers("third");
    var second = c.document.elementById("second")!;
    expect(ownSpan(second, MotionKind.arrive, _rate), (40, 10));
    expect(_track(c, "second").at(50).opacity, 1);
  });

  testWidgets("the button in its arrival's Timing dims the others",
      (tester) async {
    var c = _beats();
    addTearDown(c.dispose);
    var own = ownClipOf(c.document.elementById("second")!, MotionKind.arrive)!;
    c.selectOnly("second");
    c.pickMotion("second", own.$1.id, placement: own.$2.id);
    tester.view.physicalSize = const Size(3000, 420);
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
                      AnimationPanel(controller: c, height: 400)))),
    ));
    await tester.pumpAndSettle();
    var button = find.byKey(const ValueKey("animDimOthers"));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(_track(c, "first").at(60).opacity, closeTo(0.3, 0.001));
    c.undo();
    expect(_track(c, "first").at(60).opacity, 1, reason: "one undo step");
  });
}
