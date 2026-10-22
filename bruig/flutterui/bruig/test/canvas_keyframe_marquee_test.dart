import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_keyframe_marquee_test.dart is several keyframes picked at once --
// a box dragged over them -- and moved together, keeping their spacing.

void main() {
  Future<(CanvasController, Rect, String)> strip(
      WidgetTester tester, List<int> at) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var document = const CanvasDocument(frames: 60);
    var element = newElement(ElementKind.shape, document);
    var controller = CanvasController(document.addElement(element));
    addTearDown(controller.dispose);
    controller.selectOnly(element.id);
    for (var frame in at) {
      controller.setKeyframe(
          element.id, Keyframe(frame: frame, dx: 5.0 + frame));
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(body: CanvasTimeline(controller: controller))),
    ));
    await tester.pumpAndSettle();
    return (
      controller,
      tester.getRect(find.byKey(const ValueKey("keyframeStrip"))),
      element.id,
    );
  }

  Offset at(Rect paint, int frame, double dy) =>
      Offset(paint.left + paint.width * frame / 60, paint.top + dy);

  List<int> keys(CanvasController c, String id) =>
      [for (var k in c.document.elementById(id)!.base.track!.keys) k.frame];

  Future<void> drag(WidgetTester tester, Offset from, Offset to,
      {bool hold = false}) async {
    var g = await tester.startGesture(from);
    await tester.pump();
    // Held a moment before moving, as a hand does: long enough for the press
    // to have been taken as the start of a tap before the drag wins.
    if (hold) await tester.pump(const Duration(milliseconds: 200));
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 6)!);
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
      "a box dragged over the keyframes picks them, and they move as one",
      (tester) async {
    var (c, paint, id) = await strip(tester, [10, 20, 30, 50]);
    // Under the ruler, from before the first to past the third.
    await drag(tester, at(paint, 6, 38), at(paint, 34, 38));
    // Now drag the middle one of the three along by five frames.
    await drag(tester, at(paint, 20, 36), at(paint, 25, 36));
    expect(keys(c, id), [15, 25, 35, 50],
        reason: "the three picked moved together; the fourth stayed");
  });

  testWidgets("a drag on the ruler still scrubs", (tester) async {
    var (c, paint, id) = await strip(tester, [10, 20]);
    await drag(tester, at(paint, 5, 10), at(paint, 40, 10));
    expect(c.frame, greaterThan(30));
    expect(keys(c, id), [10, 20]);
  });

  testWidgets(
      "pressed and held first, the picked keyframes still move as one, "
      "and undo takes the whole move back in one step", (tester) async {
    var (c, paint, id) = await strip(tester, [10, 20, 30, 50]);
    await drag(tester, at(paint, 6, 38), at(paint, 34, 38));
    await drag(tester, at(paint, 20, 36), at(paint, 28, 36), hold: true);
    expect(keys(c, id), [18, 28, 38, 50]);
    c.undo();
    expect(keys(c, id), [10, 20, 30, 50], reason: "one undo, not one a frame");
  });

  testWidgets("a click on one of several picked picks it alone",
      (tester) async {
    var (c, paint, id) = await strip(tester, [10, 20, 30]);
    await drag(tester, at(paint, 6, 38), at(paint, 34, 38));
    await tester.tapAt(at(paint, 20, 36));
    await tester.pumpAndSettle();
    // Now a drag of 30 moves 30 alone.
    await drag(tester, at(paint, 30, 36), at(paint, 35, 36), hold: true);
    expect(keys(c, id), [10, 20, 35]);
  });

  testWidgets("dragged by the bar between a pair, every picked keyframe moves",
      (tester) async {
    // An arrival and an exit, as an element given both has: two pairs, each
    // joined by a bar.
    var (c, paint, id) = await strip(tester, const []);
    var e = c.document.elementById(id)!;
    c.apply(c.document.withElement(e.withBase(
        track: ElementTrack(const [
      Keyframe(frame: 10, values: {KeyframeChannel.reveal: 0}),
      Keyframe(frame: 20, values: {KeyframeChannel.reveal: 1}),
      Keyframe(frame: 40, values: {KeyframeChannel.close: 0}),
      Keyframe(frame: 50, values: {KeyframeChannel.close: 1}),
    ]))));
    await tester.pumpAndSettle();
    await drag(tester, at(paint, 6, 38), at(paint, 54, 38));
    await drag(tester, at(paint, 15, 36), at(paint, 19, 36), hold: true);
    expect(keys(c, id), [14, 24, 44, 54], reason: "both pairs, together");
  });
}
