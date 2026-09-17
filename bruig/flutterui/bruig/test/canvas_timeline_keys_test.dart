import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_timeline_keys_test.dart is taking hold of keyframes on the strip.
//
// The marks are painted rather than built, so everything here is a position
// on a picture: which pixels select a mark, which select the bar joining a
// pair, and what the keyboard does once one is picked. That is also where the
// bugs were -- the strip was shorter than its own drawing, so the lower half
// of every mark was painted outside the widget and the pointer never reached
// it.

void main() {
  /// _strip builds a timeline over an element with keyframes on [at].
  Future<(CanvasController, Rect)> strip(
    WidgetTester tester,
    List<int> at, {
    int frames = 40,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var document = CanvasDocument(frames: frames);
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
    return (controller, tester.getRect(find.byType(CustomPaint).last));
  }

  /// markAt is where a frame's mark is drawn on the strip, at [dy] down the
  /// painted area.
  ///
  /// The strip's own formula: a frame's mark sits in the middle of the frame's
  /// share of the width, not at the fraction of the way along it. Measured the
  /// other way, a tap lands a few pixels off the mark and misses it -- which
  /// is a thing about this test, not about the strip, and cost an hour.
  Offset markAt(Rect paint, int frame, int frames, double dy) => Offset(
        paint.left + paint.width * (frame + 0.5) / frames,
        paint.top + dy,
      );

  group("a keyframe", () {
    testWidgets("can be clicked anywhere on the mark, not only its top edge",
        (tester) async {
      // The strip was thirty-nine pixels tall and the drawing needed
      // sixty-two, so the bottom half of the diamond was painted outside the
      // widget: taps there went nowhere.
      var (controller, paint) = await strip(tester, [10]);
      for (var dy in [26.0, 31.0, 36.0, 41.0, 46.0]) {
        controller.frame = 0;
        await tester.tapAt(markAt(paint, 10, 40, dy));
        await tester.pumpAndSettle();
        expect(controller.frame, 10, reason: "at $dy down the strip");
      }
    });

    testWidgets("and the whole mark row is inside the strip", (tester) async {
      var (_, paint) = await strip(tester, [10]);
      expect(paint.height, greaterThan(60),
          reason: "the two rows of marks and the air around them");
    });
  });

  group("dragging a keyframe", () {
    testWidgets("leaves the playhead where it was", (tester) async {
      // The playhead is what somebody lines a keyframe up *with*, so moving
      // it the instant the mark is touched takes the guide away.
      var (controller, paint) = await strip(tester, [10]);
      controller.frame = 25;
      await tester.pumpAndSettle();

      await tester.dragFrom(
          markAt(paint, 10, 40, 36), Offset(paint.width * 8 / 39, 0));
      await tester.pumpAndSettle();

      expect(controller.frame, 25, reason: "the guide stayed put");
      var track = controller.document.elements.single.track!;
      expect(track.keyAt(10), isNull, reason: "and the mark moved");
      expect(track.keys.single.frame, greaterThan(10));
    });

    testWidgets("while clicking one still goes to it", (tester) async {
      var (controller, paint) = await strip(tester, [10]);
      controller.frame = 25;
      await tester.pumpAndSettle();

      await tester.tapAt(markAt(paint, 10, 40, 36));
      await tester.pumpAndSettle();
      expect(controller.frame, 10);
    });
  });

  group("the bar between a pair", () {
    testWidgets("selects both ends when it is clicked", (tester) async {
      // It is what says the two belong together, so picking it up picks up
      // the pair -- shown by Delete, which then takes both.
      var (controller, paint) = await strip(tester, []);
      var element = controller.document.elements.single;
      controller.frame = 6;
      controller.setValueKey(element, KeyframeChannel.reveal, 0);
      controller.frame = 18;
      controller.setValueKey(
          controller.document.elements.single, KeyframeChannel.reveal, 1);
      await tester.pumpAndSettle();

      // The middle of the bar, on the mark row and clear of both ends.
      await tester.tapAt(markAt(paint, 12, 40, 36));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      var track = controller.document.elements.single.track;
      expect(track?.keyAt(6), isNull, reason: "both ends went");
      expect(track?.keyAt(18), isNull);
    });

    testWidgets("and can be clicked anywhere down the bar", (tester) async {
      var (controller, paint) = await strip(tester, []);
      var element = controller.document.elements.single;
      controller.frame = 6;
      controller.setValueKey(element, KeyframeChannel.reveal, 0);
      controller.frame = 18;
      controller.setValueKey(
          controller.document.elements.single, KeyframeChannel.reveal, 1);
      controller.frame = 30;
      await tester.pumpAndSettle();

      // Low on the row, which used to be outside the widget.
      await tester.tapAt(markAt(paint, 12, 40, 44));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.track?.keyAt(6), isNull);
    });
  });

  group("copy and paste", () {
    testWidgets("lays the run down again with its first mark on the playhead",
        (tester) async {
      var (controller, paint) = await strip(tester, [4, 9]);

      await tester.tapAt(markAt(paint, 4, 40, 36));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tapAt(markAt(paint, 9, 40, 36));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);

      controller.frame = 20;
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      var track = controller.document.elements.single.track!;
      expect(track.keyAt(20), isNotNull, reason: "the first, on the playhead");
      expect(track.keyAt(25), isNotNull, reason: "and the spacing kept");
      expect(track.keyAt(4), isNotNull, reason: "the originals stay");
      expect(track.keyAt(9), isNotNull);
      expect(track.keyAt(20)!.dx, track.keyAt(4)!.dx,
          reason: "and the poses come with them");
    });

    testWidgets("and refuses to land on a keyframe that is already there",
        (tester) async {
      // Two keyframes on one frame is one keyframe, so a paste that
      // overlapped would quietly eat what it landed on.
      var (controller, paint) = await strip(tester, [4, 20]);

      await tester.tapAt(markAt(paint, 4, 40, 36));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);

      controller.frame = 20;
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      var track = controller.document.elements.single.track!;
      expect(track.keys.length, 2, reason: "nothing was added");
      expect(track.keyAt(20)!.dx, 25, reason: "and nothing was eaten");
    });
  });

  group("stepping between keyframes", () {
    testWidgets("goes to the next one and the one before", (tester) async {
      var (controller, _) = await strip(tester, [5, 18, 30]);
      controller.frame = 0;
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey("nextKeyframe")));
      await tester.pumpAndSettle();
      expect(controller.frame, 5);

      await tester.tap(find.byKey(const ValueKey("nextKeyframe")));
      await tester.pumpAndSettle();
      expect(controller.frame, 18);

      await tester.tap(find.byKey(const ValueKey("prevKeyframe")));
      await tester.pumpAndSettle();
      expect(controller.frame, 5);
    });

    testWidgets("and stays put at either end", (tester) async {
      var (controller, _) = await strip(tester, [5]);
      controller.frame = 5;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("nextKeyframe")));
      await tester.pumpAndSettle();
      expect(controller.frame, 5, reason: "there is no next one");
    });
  });

  group("a counter's bars on the strip", () {
    testWidgets("are there, and clicking one takes both of its marks",
        (tester) async {
      var (controller, paint) = await strip(tester, []);
      var element = controller.document.elements.single;
      // A count with three points: two stretches, two bars.
      for (var (frame, value) in [(0, 0.0), (10, 50.0), (20, 100.0)]) {
        controller.frame = frame;
        controller.setValueKey(
            controller.document.elements.single, KeyframeChannel.count, value,
            seed: false);
      }
      expect(element.id, isNotNull);
      await tester.pumpAndSettle();

      // The middle of the second stretch, clear of both its ends.
      await tester.tapAt(markAt(paint, 15, 40, 36));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      var track = controller.document.elements.single.track;
      expect(track?.keyAt(10), isNull, reason: "both ends of that bar went");
      expect(track?.keyAt(20), isNull);
      expect(track?.keyAt(0), isNotNull, reason: "and the first stayed");
    });
  });

  group("the bar between two marks", () {
    // What a reader takes it to mean is "something changes over this
    // stretch", so that is what it says: one bar for each stretch a counted
    // number moves over.
    ElementTrack counting(List<(int, double)> points) => ElementTrack([
          for (var (frame, value) in points)
            Keyframe(frame: frame, values: {KeyframeChannel.count: value}),
        ]);

    test("is drawn for every stretch the number changes over", () {
      var bands = bandsIn(counting([(0, 0), (10, 50), (20, 100)]));
      expect(bands, hasLength(2));
      expect([bands[0].from, bands[0].to], [0, 10]);
      expect([bands[1].from, bands[1].to], [10, 20]);
    });

    test("and not over a stretch that holds", () {
      // The bar says the number is *travelling* here, and a held one does
      // not travel: it stays as it is and steps at the far end.
      var track = ElementTrack([
        const Keyframe(
            frame: 0,
            easing: KeyframeEasing.hold,
            values: {KeyframeChannel.count: 0}),
        const Keyframe(frame: 12, values: {KeyframeChannel.count: 100}),
      ]);
      expect(bandsIn(track), isEmpty);
    });

    test("and it is the keyframe the stretch leaves that decides", () {
      // Ease, hold, ease, hold: a bar over the first stretch, none over the
      // second, a bar over the third.
      var track = ElementTrack([
        const Keyframe(
            frame: 0,
            easing: KeyframeEasing.easeIn,
            values: {KeyframeChannel.count: 0}),
        const Keyframe(
            frame: 10,
            easing: KeyframeEasing.hold,
            values: {KeyframeChannel.count: 25}),
        const Keyframe(
            frame: 20,
            easing: KeyframeEasing.easeIn,
            values: {KeyframeChannel.count: 50}),
        const Keyframe(
            frame: 30,
            easing: KeyframeEasing.hold,
            values: {KeyframeChannel.count: 75}),
      ]);
      var bands = bandsIn(track);
      expect([
        for (var b in bands) [b.from, b.to]
      ], [
        [0, 10],
        [20, 30],
      ]);
    });

    test("and not where the two ends read the same", () {
      // Nothing happens there, and a bar over it would be saying something
      // untrue.
      var bands = bandsIn(counting([(0, 40), (10, 40), (20, 90)]));
      expect(bands, hasLength(1));
      expect([bands.single.from, bands.single.to], [10, 20]);
    });

    test("is drawn between keyframes laid by hand, on any element", () {
      // It used to be drawn only for the two channels a preset lays down, so
      // a chart moved across the canvas by hand had four marks and nothing
      // between them.
      var track = ElementTrack(const [
        Keyframe(frame: 0, dx: 0),
        Keyframe(frame: 10, dx: 80),
        Keyframe(frame: 20, dx: 80, easing: KeyframeEasing.hold),
        Keyframe(frame: 30, dx: 200),
      ]);
      var bands = bandsIn(track);
      expect([
        for (var b in bands) [b.from, b.to]
      ], [
        [0, 10],
      ], reason: "10 to 20 says the same thing twice, and 20 holds");
    });

    test("and every kind of change counts as one", () {
      for (var (still, moved) in [
        (const Keyframe(frame: 0), const Keyframe(frame: 10, dy: 40)),
        (const Keyframe(frame: 0), const Keyframe(frame: 10, scale: 1.4)),
        (const Keyframe(frame: 0), const Keyframe(frame: 10, rotate: 90)),
        (const Keyframe(frame: 0), const Keyframe(frame: 10, opacity: 0.2)),
        (
          const Keyframe(frame: 0, values: {KeyframeChannel.slide: 0}),
          const Keyframe(frame: 10, values: {KeyframeChannel.slide: 0.5}),
        ),
      ]) {
        expect(bandsIn(ElementTrack([still, moved])), hasLength(1),
            reason: "$moved");
      }
    });

    test("but a channel only one of them pins is not a change", () {
      // A channel the other does not carry holds whatever was set before it,
      // so the end of an arrival and the start of an exit have nothing
      // happening between them -- which is what they look like.
      var track = ElementTrack(const [
        Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
        Keyframe(frame: 10, values: {KeyframeChannel.reveal: 1}),
        Keyframe(frame: 30, values: {KeyframeChannel.close: 0}),
        Keyframe(frame: 47, values: {KeyframeChannel.close: 1}),
      ]);
      var bands = bandsIn(track);
      expect([
        for (var b in bands) [b.from, b.to]
      ], [
        [0, 10],
        [30, 47],
      ], reason: "the arrival and the exit, and nothing in the gap");
    });

    test("and an arrival held at the start has no bar either", () {
      // It does not arrive over the stretch, it snaps at the end of it.
      var track = ElementTrack([
        const Keyframe(
            frame: 0,
            easing: KeyframeEasing.hold,
            values: {KeyframeChannel.reveal: 0}),
        const Keyframe(frame: 24, values: {KeyframeChannel.reveal: 1}),
      ]);
      expect(bandsIn(track), isEmpty);
    });

    test("and an arrival is still one bar however many keyframes follow it",
        () {
      // A pair means nothing apart, so it stays one bar from the first to the
      // last -- which is not the same rule, and deliberately.
      var track = ElementTrack([
        const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
        const Keyframe(frame: 24, values: {KeyframeChannel.reveal: 1}),
      ]);
      expect(bandsIn(track), hasLength(1));
      expect(bandsIn(track).single.channel, KeyframeChannel.reveal);
    });
  });
}
