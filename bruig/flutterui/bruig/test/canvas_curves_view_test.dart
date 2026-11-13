import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/curve_view.dart';
import 'package:bruig/plugin_system/canvas/ui/track_curves.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_curves_view_test.dart is the Curves made easier to work in (Ken,
// 2026-11-14): pinch and scroll to move about, a playhead to drag, Delete
// for a key, handles to shape an ease by hand; Curves offered for a
// camera's own keyframes; and Keys always beside Curves.

ShapeElement logo() => ShapeElement(ElementBase(
    id: "logo",
    name: "Logo",
    width: 20,
    height: 20,
    track: ElementTrack(const [
      Keyframe(frame: 0),
      Keyframe(frame: 24, dx: 100),
      Keyframe(frame: 48, dx: 100, rotate: 90),
    ])));

Widget host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Align(alignment: Alignment.topLeft, child: child))),
    );

void main() {
  group("an ease drawn with handles", () {
    test("is the curve CSS would draw", () {
      for (var t in [0.1, 0.3, 0.5, 0.8]) {
        expect(EaseCurve.linear.apply(t), closeTo(t, 1e-6));
        // Ease in and out, as handles, are the very curves they were.
        expect(KeyframeEasing.easeIn.asCurve.apply(t),
            closeTo(KeyframeEasing.easeIn.apply(t), 1e-4));
        expect(KeyframeEasing.easeOut.asCurve.apply(t),
            closeTo(KeyframeEasing.easeOut.apply(t), 1e-4));
      }
      expect(EaseCurve.inOut.apply(0.5), closeTo(0.5, 1e-6));
      expect(EaseCurve.inOut.apply(0), 0);
      expect(EaseCurve.inOut.apply(1), 1);
    });

    test("moves a keyframe's values, overshooting where it is drawn to", () {
      var track = ElementTrack(const [
        Keyframe(
            frame: 0,
            easing: KeyframeEasing.custom,
            curve: EaseCurve(0.2, 1.6, 0.6, 1.2)),
        Keyframe(frame: 10, dx: 100),
      ]);
      var most = 0.0;
      for (var f = 0.0; f <= 10; f += 0.25) {
        if (track.between(f).dx > most) most = track.between(f).dx;
      }
      expect(most, greaterThan(100), reason: "past where it is going");
      expect(track.between(10).dx, 100, reason: "and there in the end");
    });

    test("is kept with the keyframe and the clip key", () {
      const k = Keyframe(
          frame: 3,
          easing: KeyframeEasing.custom,
          curve: EaseCurve(0.1, 0.2, 0.3, 0.4));
      expect(Keyframe.fromJson(k.toJson()).curve, k.curve);
      var m = MotionKey(0.5, const MotionNumber(2),
          ease: KeyframeEasing.custom, curve: const EaseCurve(0.1, 0, 0.9, 1));
      expect(MotionKey.fromJson(m.toJson(), 0), m);
      // Another easing does not carry a curve into the file.
      expect(const Keyframe(frame: 0, curve: EaseCurve.inOut).toJson(),
          isNot(contains("c")));
    });
  });

  group("the element's Curves", () {
    Future<CanvasController> show(WidgetTester tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 100, frameRate: 24, elements: [logo()]));
      c.selectOnly("logo");
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      c.showTrackCurves();
      await tester.pumpWidget(host(ListenableBuilder(
          listenable: c,
          builder: (context, _) => TrackCurves(controller: c, height: 300))));
      await tester.pump();
      return c;
    }

    Rect graph(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey("trackCurvesGraph")));

    /// xOf is where frame [f] is across the graph, fitted.
    double xOf(WidgetTester tester, int f) {
      var r = graph(tester);
      return r.left + 12 + f / 99 * (r.width - 24);
    }

    /// keyOf is where the Across key at frame [f], holding [v], is drawn:
    /// across from 0 to 100, scaled with a tenth each side.
    Offset keyOf(WidgetTester tester, int f, double v) {
      var r = graph(tester);
      var lo = -10.0, hi = 110.0;
      return Offset(xOf(tester, f),
          r.top + 34 + (1 - (v - lo) / (hi - lo)) * (r.height - 54));
    }

    testWidgets("Delete takes the picked keyframe away", (tester) async {
      var c = await show(tester);
      await tester.tapAt(keyOf(tester, 24, 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect([for (var k in c.keyframeTarget!.track.keys) k.frame], [0, 48]);
    });

    testWidgets("the playhead is dragged by its cap, and by its line",
        (tester) async {
      var c = await show(tester);
      c.frame = 10;
      await tester.pump();
      var top = graph(tester).top;
      await tester.dragFrom(Offset(xOf(tester, 10), top + 10),
          Offset(xOf(tester, 60) - xOf(tester, 10), 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.frame, closeTo(60, 1));
      // Its line, down among the values, where no key is.
      await tester.dragFrom(Offset(xOf(tester, 60), top + 200),
          Offset(xOf(tester, 80) - xOf(tester, 60), 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.frame, closeTo(80, 1));
    });

    testWidgets("⌘-scroll zooms in on time; the ruler shows it all again",
        (tester) async {
      await show(tester);
      var before = keyOf(tester, 24, 100);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      var at = Offset(xOf(tester, 0), graph(tester).center.dy);
      tester.binding.handlePointerEvent(
          PointerScrollEvent(position: at, scrollDelta: const Offset(0, -240)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(find.byKey(const ValueKey("trackCurvesFit")), findsOneWidget);
      // About the left edge, the key a second in is now further along.
      var c = (tester.state(find.byType(TrackCurves)) as CurveViewing).view;
      expect(c.zoom, greaterThan(2));
      expect(c.from, closeTo(0, 1e-9));
      // Double-clicking the ruler: as it was.
      var ruler = Offset(graph(tester).center.dx, graph(tester).top + 10);
      await tester.tapAt(ruler);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(ruler);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.fitted, isTrue);
      expect(keyOf(tester, 24, 100), before);
    });

    testWidgets("a two-finger swipe, or a drag on the background, moves it",
        (tester) async {
      await show(tester);
      var view = (tester.state(find.byType(TrackCurves)) as CurveViewing).view;
      view.zoom = 4;
      // A drag on empty ground: the values move with the hand.
      var r = graph(tester);
      await tester.dragFrom(
          Offset(r.left + r.width * 0.85, r.top + 60), const Offset(0, 80),
          kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(view.vMid, greaterThan(0.5));
      // A trackpad swipe sideways: along time.
      var pointer = TestPointer(1, PointerDeviceKind.trackpad);
      var at = r.center;
      await tester.sendEventToBinding(pointer.panZoomStart(at));
      await tester.sendEventToBinding(
          pointer.panZoomUpdate(at, pan: const Offset(-200, 0)));
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pump();
      expect(view.from, greaterThan(0));
    });

    testWidgets("its handles shape the ease out of a keyframe", (tester) async {
      var c = await show(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey("trackCurvesHandles")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("trackCurvesHandles")));
      await tester.pump();
      expect(curvesShowHandles, isTrue);
      addTearDown(() => curvesShowHandles = false);
      // The first ease's first handle: a third of the way to the next key,
      // as linear starts it, on Across.
      var p0 = keyOf(tester, 0, 0), p1 = keyOf(tester, 24, 100);
      var h1 = p0 + (p1 - p0) / 3;
      await tester.dragFrom(h1, Offset(0, (p1.dy - p0.dy) * 0.5));
      await tester.pump(const Duration(milliseconds: 400));
      var k = c.keyframeTarget!.track.keyAt(0)!;
      expect(k.easing, KeyframeEasing.custom);
      expect(k.curve!.x1, closeTo(1 / 3, 0.02));
      expect(k.curve!.y1, closeTo(1 / 3 + 0.5, 0.03));
    });
  });

  group("the Chain's header", () {
    CanvasController camera() {
      var c = CanvasController(
          CanvasDocument(frames: 100, frameRate: 24, elements: [
            CameraElement(ElementBase(
                id: "cam",
                name: "Camera",
                width: 1920,
                height: 1080,
                track: ElementTrack(const [
                  Keyframe(frame: 0),
                  Keyframe(frame: 48, scale: 2),
                ]))),
          ]),
          audioEngine: FakeEngine({}));
      c.selectOnly("cam");
      c.showChain(motion: true);
      return c;
    }

    Future<void> show(WidgetTester tester, CanvasController c) async {
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(SizedBox(
          width: 1400,
          height: 420,
          child: ListenableBuilder(
              listenable: c,
              builder: (context, _) =>
                  ChainPanel(controller: c, height: 400, onResize: (_) {})))));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets("offers Curves for a camera's own keyframes", (tester) async {
      var c = camera();
      await show(tester, c);
      await tester.tap(find.byKey(const ValueKey("chainTabCurves")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.trackCurvesShown, isTrue);
      expect(find.byKey(const ValueKey("trackCurves")), findsOneWidget);
    });

    testWidgets("Keys, from the Curves, goes back with the keys showing",
        (tester) async {
      var c = camera();
      c.keysShown = false;
      addTearDown(() => c.keysShown = false);
      await show(tester, c);
      await tester.tap(find.byKey(const ValueKey("chainTabCurves")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey("chainKeys")), findsOneWidget,
          reason: "beside Curves while the Curves show");
      await tester.tap(find.byKey(const ValueKey("chainKeys")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.trackCurvesShown, isFalse);
      expect(c.keysShown, isTrue);
      // On the chain, it shows and hides them.
      await tester.tap(find.byKey(const ValueKey("chainKeys")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.trackCurvesShown, isFalse);
      expect(c.keysShown, isFalse);
    });
  });
}
