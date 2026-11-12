import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/track_curves.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_track_curves_test.dart is the Curves of an element's own keyframes
// (Ken, 2026-11-09: the approved keyframes prototype, v2): opened from the
// Keyframes card on the keyframe picked there; a key dragged up or down
// changes that value, right-clicked puts it back to rest; a double-click
// adds a keyframe; the easing set from the toolbar; a value's line hidden
// from the list; closed back to the cards.

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

CanvasController make() {
  var c = CanvasController(
      CanvasDocument(frames: 100, frameRate: 24, elements: [logo()]));
  c.selectOnly("logo");
  return c;
}

List<int> framesOf(CanvasController c) =>
    [for (var k in c.keyframeTarget!.track.keys) k.frame];

Keyframe keyAt(CanvasController c, int f) => c.keyframeTarget!.track.keyAt(f)!;

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
  Future<CanvasController> show(WidgetTester tester, {int? frame}) async {
    var c = make();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1000, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    c.showTrackCurves(frame: frame);
    await tester.pumpWidget(host(ListenableBuilder(
        listenable: c,
        builder: (context, _) => TrackCurves(controller: c, height: 300))));
    await tester.pump();
    return c;
  }

  /// at is where [id]'s key at frame [f] holding [v] is drawn, the value
  /// scaled across [lo]..[hi] as the graph scales it (a tenth more each
  /// side).
  Offset at(WidgetTester tester, int f, double v, double lo, double hi) {
    var r = tester.getRect(find.byKey(const ValueKey("trackCurvesGraph")));
    var pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    var x = 12 + f / 99 * (r.width - 24);
    var y = 34 + (1 - (v - lo) / (hi - lo)) * (r.height - 54);
    return r.topLeft + Offset(x, y);
  }

  Offset across(WidgetTester tester, int f, double v) =>
      at(tester, f, v, 0, 100);

  testWidgets("opened on a keyframe: its first value picked", (tester) async {
    await show(tester, frame: 24);
    expect(find.text("Across at frame 24"), findsOneWidget);
    expect(find.byKey(const ValueKey("trackCurvesValue-dx")), findsOneWidget);
    expect(
        find.byKey(const ValueKey("trackCurvesValue-rotate")), findsOneWidget);
    expect(find.byKey(const ValueKey("trackCurvesValue-scale")), findsNothing,
        reason: "only what changes");
    expect(tester.takeException(), isNull);
  });

  testWidgets("opened on nothing: the hint, and a key clicked is picked",
      (tester) async {
    await show(tester);
    expect(find.byKey(const ValueKey("trackCurvesHint")), findsOneWidget);
    await tester.tapAt(across(tester, 48, 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Across at frame 48"), findsOneWidget);
  });

  testWidgets("a key dragged down lowers that value, at the same frame",
      (tester) async {
    var c = await show(tester);
    var from = across(tester, 24, 100);
    var g = await tester.startGesture(from);
    await tester.pump();
    await g.moveTo(from + const Offset(0, 30));
    await tester.pump();
    await g.moveTo(from + const Offset(0, 60));
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(framesOf(c), [0, 24, 48]);
    expect(keyAt(c, 24).dx, lessThan(90));
    expect(keyAt(c, 24).dx, greaterThan(40));
    expect(keyAt(c, 48).dx, 100, reason: "the other keyframes left alone");
    expect(c.canUndo, isTrue);
  });

  testWidgets("a key dragged sideways moves its whole keyframe",
      (tester) async {
    var c = await show(tester);
    var from = across(tester, 24, 100);
    var to = across(tester, 36, 100);
    var g = await tester.startGesture(from);
    await tester.pump();
    await g.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(framesOf(c), [0, 36, 48]);
    expect(keyAt(c, 36).dx, closeTo(100, 1));
  });

  testWidgets("right-clicked, a value goes back to rest", (tester) async {
    var c = await show(tester);
    await tester.tapAt(across(tester, 24, 100),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 400));
    expect(keyAt(c, 24).dx, 0);
    expect(framesOf(c), [0, 24, 48], reason: "the keyframe stays");
  });

  testWidgets("the inspector's rest button does the same", (tester) async {
    var c = await show(tester, frame: 48);
    await tester.tap(find.byKey(const ValueKey("trackCurvesRest")));
    await tester.pump();
    expect(keyAt(c, 48).dx, 0);
  });

  testWidgets("a double-click adds a keyframe holding the pose there",
      (tester) async {
    var c = await show(tester);
    var p = across(tester, 12, 20);
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 400));
    expect(framesOf(c), [0, 12, 24, 48]);
    expect(keyAt(c, 12).dx, greaterThan(0));
    expect(find.text("Across at frame 12"), findsOneWidget);
  });

  testWidgets("the toolbar eases the picked keyframe", (tester) async {
    var c = await show(tester, frame: 24);
    var ease = find.byKey(const ValueKey("trackCurvesEase-easeOut"));
    await tester.ensureVisible(ease);
    await tester.tap(ease);
    await tester.pump();
    expect(keyAt(c, 24).easing, KeyframeEasing.easeOut);
  });

  testWidgets("a value hidden from the list: its keys no longer picked",
      (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey("trackCurvesValue-dx")));
    await tester.pump();
    // Where Across's key at 24 was; Angle's there is at the bottom.
    await tester.tapAt(across(tester, 24, 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey("trackCurvesHint")), findsOneWidget);
  });

  testWidgets("Speed draws without trouble", (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey("trackCurvesSpeed")));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets("from the Keys strip, in the Motion view, and closed back",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.keysShown = true;
    addTearDown(() => c.keysShown = false);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(AnimationPanel(controller: c, height: 360)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("keysStrip")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("keysCurves")));
    await tester.pumpAndSettle();
    expect(c.trackCurvesShown, isTrue);
    expect(find.byKey(const ValueKey("trackCurvesPanel")), findsOneWidget);
    expect(find.byKey(const ValueKey("keysStrip")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("trackCurvesClose")));
    await tester.pumpAndSettle();
    expect(c.trackCurvesShown, isFalse);
    expect(find.byKey(const ValueKey("keysStrip")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
