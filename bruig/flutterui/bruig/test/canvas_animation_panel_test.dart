import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_clip_display.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show boxOf, motionSceneOf;
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show KeyframeEasing;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The Animation panel: the picked clip as a row of devices. A ready-made
// motion picked writes its keys; a click on a Keys row adds one, a drag
// retimes it; the Keys device is dragged wider; each change one undo step.

Future<(CanvasController, String)> pump(WidgetTester tester,
    {double scale = 1, double height = 360}) async {
  tester.view.physicalSize = const Size(2400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  var c =
      CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
    ShapeElement(const ElementBase(
        id: "a", name: "Logo", x: 100, y: 100, width: 50, height: 50)),
    ShapeElement(const ElementBase(
        id: "b", name: "Box", x: 400, y: 100, width: 50, height: 50)),
  ]));
  addTearDown(c.dispose);
  var clip = c.newClip("a", preset: presetNamed("Pop"), slot: 0);
  c.pickMotion("a", clip);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(
          size: const Size(1600, 900), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
          body: Align(
              alignment: Alignment.bottomCenter,
              child: AnimationPanel(controller: c, height: height))),
    )),
  ));
  await tester.pumpAndSettle();
  return (c, clip);
}

void main() {
  testWidgets(
      "its text is one size however tall the panel, its hints behind a ?",
      (tester) async {
    Size sizeAt(double height) => tester.getSize(find.text("Length").first);
    await pump(tester, height: 280);
    var short = sizeAt(280);
    await pump(tester, height: 520);
    expect(sizeAt(520), short, reason: "not shrunk to the panel");
    expect(find.textContaining("How long it is"), findsNothing);
    // Behind its "?", read when clicked.
    var help = find.byKey(const ValueKey("deviceHelp-motionTiming"));
    expect(help, findsOneWidget);
    await tester.tap(help);
    await tester.pump();
    expect(find.textContaining("How long it is"), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    // The ones in view: the rest are along the row, built as it scrolls.
    for (var id in ["motionClips", "motionLaunch"]) {
      expect(find.byKey(ValueKey("deviceHelp-$id")), findsOneWidget,
          reason: id);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "a game's count is offered as a trigger, at any change or a number",
      (tester) async {
    var (c, clip) = await pump(tester);
    c.apply(c.document
        .copyWith(game: true, counts: const [GameCount("coins", "Coins")]));
    // Wide enough for the Launch section to be built.
    tester.view.physicalSize = const Size(4000, 900);
    await tester.pumpAndSettle();
    tester
        .widget<StudioDrop<String>>(
            find.byKey(const ValueKey("animTriggerAdd")))
        .onChanged("count:coins");
    await tester.pumpAndSettle();
    var t = c.motionOf("a").clip(clip)!.triggers.single;
    expect((t.kind, t.target, t.amount), (ClipTriggerKind.count, "coins", 0));
    expect(find.text("Coins changes"), findsOneWidget);
    tester
        .widget<StudioDrop<double>>(
            find.byKey(const ValueKey("animTriggerAmount-0")))
        .onChanged(3);
    await tester.pumpAndSettle();
    expect(c.motionOf("a").clip(clip)!.triggers.single.amount, 3);
    expect(find.text("Coins reaches 3"), findsOneWidget);
  });

  testWidgets("nothing picked, it says how to pick something", (tester) async {
    var (c, _) = await pump(tester);
    c.pickMotion(null, null);
    c.clearSelection();
    await tester.pump();
    expect(find.textContaining("Pick a slot"), findsOneWidget);
  });

  // Ken, 2026-11-08: the motion devices as the audio ones -- displays wide
  // as the prototype's, settings that do not scroll, choices as dropdowns.
  for (var scale in [1.0, 1.5]) {
    testWidgets(
        "short, a device's screen is kept small over its settings "
        "(text x$scale)", (tester) async {
      // The panel at the Chain's M: its cards on the short layout.
      var (c, clip) = await pump(tester, scale: scale, height: 242);
      c.setMotionDevices(
          "a", withMotionDeviceIds([MotionDevice(MotionDeviceKind.oscillate)]));
      tester.view.physicalSize = const Size(4000, 900);
      await tester.pumpAndSettle();
      var id = c.motionDevicesOf("a").single.id;
      // In the settings panel's style (Ken, 2026-11-12): a small screen,
      // the card's width, over its settings.
      var screen = tester.getSize(find.byKey(ValueKey("mdevScreen-$id")));
      expect(screen.width, greaterThanOrEqualTo(200));
      expect(screen.height, lessThanOrEqualTo(96));
      // Moves is a dropdown, not a knob turned through its words.
      expect(find.byKey(ValueKey("mdev-$id-moves")), findsOneWidget);
      expect(tester.widget(find.byKey(ValueKey("mdev-$id-moves"))),
          isA<StudioDrop<int>>());
      // Nothing in the cards scrolls along, and nothing is cut.
      for (var card in [
        "motionClipsCard",
        "motionTimingCard",
        "mdevCard-$id"
      ]) {
        expect(
            find.descendant(
                of: find.byKey(ValueKey(card)),
                matching: find.byWidgetPredicate((w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.horizontal)),
            findsNothing,
            reason: card);
      }
      // The clip's name lines up with the dropdowns beside it.
      var name = tester.getRect(find.byKey(const ValueKey("animClipNameBox")));
      var layer =
          tester.getRect(find.byKey(const ValueKey("motionClipsOn-open")));
      // As tall as they are, on their grid: beside them, or under the
      // first of them where the row is full.
      expect(name.height, closeTo(layer.height, 1));
      expect(tester.takeException(), isNull);
    });
  }

  // Ken, 2026-11-08: the clip's screen shows what it does as set, and is
  // edited there -- its points moved, a stretch's curve, a point added and
  // taken out -- with a Reset back to its preset.
  group("the clip's screen", () {
    Future<(CanvasController, String, Rect)> path(WidgetTester tester) async {
      var (c, clip) = await pump(tester);
      var m = c.motionOf("a").clip(clip)!;
      c.setMotion(
          "a", c.motionOf("a").withClip(presetNamed("Slide in")!.onto(m)));
      await tester.pumpAndSettle();
      var rect =
          tester.getRect(find.byKey(ValueKey("motionClipDisplay-$clip")));
      return (c, clip, rect);
    }

    ClipLayout layoutOf(CanvasController c, String clip, Rect rect,
            [ClipView view = ClipView.path]) =>
        ClipLayout(c.motionOf("a").clip(clip)!, view, rect.size,
            boxOf(c.document.elementById("a")!), motionSceneOf(c.document, 0));

    testWidgets("its end point dragged moves it, as one step; Reset",
        (tester) async {
      var (c, clip, rect) = await path(tester);
      expect(find.byKey(const ValueKey("motionClipsReset")), findsNothing,
          reason: "as its preset made it");
      var l = layoutOf(c, clip, rect);
      var end = l.handles.where((h) => !h.ease).last;
      await tester.timedDragFrom(rect.topLeft + end.at, const Offset(0, -30),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var m = c.motionOf("a").clip(clip)!;
      expect(m.edited, isTrue);
      expect(l.value(MotionProp.y, m.length), 0, reason: "it was level");
      var after = layoutOf(c, clip, rect);
      expect(after.value(MotionProp.y, m.length), closeTo(-30 / l.scale, 2),
          reason: "moved up as far as it was dragged");
      expect(find.byKey(const ValueKey("motionClipsReset")), findsOneWidget);
      // Back to its preset, in one step.
      await tester.tap(find.byKey(const ValueKey("motionClipsReset")));
      await tester.pumpAndSettle();
      m = c.motionOf("a").clip(clip)!;
      expect(m.edited, isFalse);
      expect(m.keys[MotionProp.y], isNull);
      expect(find.byKey(const ValueKey("motionClipsReset")), findsNothing);
      c.undo();
      expect(c.motionOf("a").clip(clip)!.edited, isTrue, reason: "one undo");
    });

    testWidgets("a stretch's diamond picks its curve", (tester) async {
      var (c, clip, rect) = await path(tester);
      var l = layoutOf(c, clip, rect);
      var diamond = l.handles.firstWhere((h) => h.ease);
      await tester.tapAt(rect.topLeft + diamond.at);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("motionClipsEase-bounce")));
      await tester.pumpAndSettle();
      var keys = c.motionOf("a").clip(clip)!.keys[MotionProp.x]!;
      expect(
          keys.firstWhere((k) => k.t == diamond.t).ease, KeyframeEasing.bounce);
    });

    testWidgets(
        "a double-click on the path adds a point; a right-click "
        "takes it out", (tester) async {
      var (c, clip, rect) = await path(tester);
      int count() => c.motionOf("a").clip(clip)!.keys[MotionProp.x]!.length;
      var before = count();
      var l = layoutOf(c, clip, rect);
      var len = c.motionOf("a").clip(clip)!.length;
      var spot = rect.topLeft + l.toScreen(l.pose(len * 0.2).move);
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
      expect(count(), before + 1);
      var made =
          layoutOf(c, clip, rect).handles.where((h) => !h.ease).toList()[1];
      // A mouse's right button, then the mouse taken away: hovered, the
      // screen plays.
      var mouse = await tester.startGesture(rect.topLeft + made.at,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(count(), before);
    });

    testWidgets("a size-only clip shows its values; a point dragged up",
        (tester) async {
      var (c, clip) = await pump(tester);
      expect(find.byKey(const ValueKey("motionClipsView-path")), findsNothing,
          reason: "Pop has no path");
      var rect =
          tester.getRect(find.byKey(ValueKey("motionClipDisplay-$clip")));
      var l = layoutOf(c, clip, rect, ClipView.graph);
      var key = l.handles
          .where((h) => !h.ease && h.props.single == MotionProp.scale)
          .last;
      var was = l.value(MotionProp.scale, key.t);
      await tester.timedDragFrom(rect.topLeft + key.at, const Offset(0, -20),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var now = c.motionOf("a").clip(clip)!;
      expect(now.edited, isTrue);
      expect(
          layoutOf(c, clip, rect, ClipView.graph)
              .value(MotionProp.scale, key.t),
          greaterThan(was));
    });

    testWidgets("its own style: frames shown; Reset its direction and reach",
        (tester) async {
      var (c, clip) = await pump(tester);
      tester
          .widget<StudioDrop<String>>(
              find.byKey(const ValueKey("motionClipsPreset")))
          .onChanged("own:wipe");
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("motionClipsReset")), findsNothing);
      var a = CanvasController.elementAnimationOf(c.document.elementById("a")!);
      c.setElementAnimation("a", a.copyWith(strength: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("motionClipsReset")));
      await tester.pumpAndSettle();
      expect(
          CanvasController.elementAnimationOf(c.document.elementById("a")!)
              .strength,
          1);
      expect(tester.takeException(), isNull);
    });
  });

  // Ken, 2026-11-08: once renamed, the name could not be left.
  testWidgets("the clip's name: Return keeps it and leaves; Escape undoes",
      (tester) async {
    var (c, clip) = await pump(tester);
    var field = find.byKey(const ValueKey("animClipName"));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    bool typing() =>
        FocusManager.instance.primaryFocus?.debugLabel == "clipName";
    await tester.tap(field);
    await tester.pump();
    expect(typing(), isTrue);
    await tester.enterText(field, "Bounce");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.motionOf("a").clip(clip)!.name, "Bounce");
    expect(typing(), isFalse, reason: "left");
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, "Nope");
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(typing(), isFalse);
    expect(c.motionOf("a").clip(clip)!.name, "Bounce");
    expect(tester.widget<TextField>(field).controller!.text, "Bounce",
        reason: "as it was");
  });

  testWidgets("an element picked, with no clip, shows its first",
      (tester) async {
    var (c, clip) = await pump(tester);
    c.pickMotion(null, null);
    c.selectOnly("a");
    await tester.pump();
    expect(find.textContaining("Pick a slot"), findsNothing);
    // The clip it shows, by its name in its Clip card (the Chain's header
    // names the element).
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey("animClipName")))
            .controller!
            .text,
        "Pop");
  });

  testWidgets("a ready-made motion picked writes the clip's keys",
      (tester) async {
    var (c, clip) = await pump(tester);
    // The clip it shows, by its name in its Clip card (the Chain's header
    // names the element).
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey("animClipName")))
            .controller!
            .text,
        "Pop");
    // Its Preset dropdown: the ready-made motions of its kind.
    tester
        .widget<StudioDrop<String>>(
            find.byKey(const ValueKey("motionClipsPreset")))
        .onChanged("p:Slide in");
    await tester.pumpAndSettle();
    var m = c.motionOf("a").clip(clip)!;
    expect(m.preset, "Slide in");
    expect(m.keys[MotionProp.x]!.first.value, isA<MotionPlace>(),
        reason: "it slides in from off an edge");
    c.undo();
    expect(c.motionOf("a").clip(clip)!.preset, "Pop", reason: "one step");
  });

  // Ken, 2026-11-08: the Keys are the Curves tab's, as the prototype's.
  testWidgets("in Curves, a value given a key, picked and taken away",
      (tester) async {
    var (c, clip) = await pump(tester);
    c.showMotionCurves("a", clip);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("curvesAdd-turn")));
    await tester.pumpAndSettle();
    var m = c.motionOf("a").clip(clip)!;
    expect(m.keys[MotionProp.turn], hasLength(1));
    expect(m.edited, isTrue, reason: "keys by hand");
    // Only Turn shown: its key, at the start, half way up.
    for (var p in MotionProp.values) {
      if (p != MotionProp.turn && (m.keys[p]?.isNotEmpty ?? false)) {
        await tester.tap(find.byKey(ValueKey("curvesValue-${p.name}")));
        await tester.pump();
      }
    }
    var g = tester.getRect(find.byKey(const ValueKey("curvesGraph")));
    await tester.tapAt(Offset(g.left + 12, g.top + 34 + (g.height - 54) / 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("curvesKeyName")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("curvesRemove")));
    await tester.pumpAndSettle();
    expect(c.motionOf("a").clip(clip)!.keys[MotionProp.turn], isNull);
  });

  testWidgets("a key dragged along in Curves is retimed, as one step",
      (tester) async {
    var (c, clip) = await pump(tester);
    // Across alone, from nought to a hundred over its length.
    var was = c.motionOf("a").clip(clip)!;
    c.setMotion(
        "a",
        c.motionOf("a").withClip(was.copyWith(keys: {
              MotionProp.x: [
                MotionKey(0, MotionNumber(0)),
                MotionKey(was.length, MotionNumber(100)),
              ],
            })));
    var before = c.motionOf("a").clip(clip)!;
    c.showMotionCurves("a", clip);
    await tester.pumpAndSettle();
    var g = tester.getRect(find.byKey(const ValueKey("curvesGraph")));
    // The first key: at the start, at the foot.
    var at = Offset(g.left + 12, g.top + 34 + (g.height - 54));
    await tester.timedDragFrom(
        at, Offset(g.width / 4, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    var moved = c.motionOf("a").clip(clip)!.keys[MotionProp.x]!;
    expect(moved.first.t, greaterThan(0));
    c.undo();
    expect(c.motionOf("a").clip(clip)!.keys[MotionProp.x]!.map((m) => m.t),
        before.keys[MotionProp.x]!.map((m) => m.t));
  });

  testWidgets("Curves fills the panel; Chain brings the cards back",
      (tester) async {
    var (c, clip) = await pump(tester);
    c.showMotionCurves("a", clip);
    await tester.pumpAndSettle();
    var panel = tester.getRect(find.byKey(const ValueKey("motionCurves")));
    expect(tester.getSize(find.byKey(const ValueKey("curvesGraph"))).width,
        greaterThan(panel.width / 2));
    expect(find.byKey(const ValueKey("motionClipsCard")), findsNothing);
    c.closeMotionCurves();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("motionClipsCard")), findsOneWidget);
  });

  testWidgets("placed, its start is pinned to a marker", (tester) async {
    var (c, clip) = await pump(tester);
    var m = c.addMarker(48);
    var p = c.placeClip("a", clip, seconds: 0);
    c.pickMotion("a", clip, placement: p);
    await tester.pumpAndSettle();
    c.pinPlacement("a", p, ClipPin(PinKind.marker, target: m));
    await tester.pumpAndSettle();
    expect(c.spanOf(p)!.start, 2);
    expect(find.byKey(const ValueKey("animStartPin")), findsOneWidget);
    expect(find.textContaining("2.00–"), findsOneWidget);
  });

  for (var scale in [0.65, 1.5]) {
    testWidgets("at text size $scale, nothing overflows", (tester) async {
      await pump(tester, scale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("Inside it: an arrival plays the element's own", (tester) async {
    var (c, _) = await pump(tester);
    var id = c.newClip("a", kind: MotionKind.arrive);
    c.pickMotion("a", id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("animDevice-inside")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("animInside-own")));
    await tester.pumpAndSettle();
    expect(c.motionOf("a").clip(id)!.inside["own"], isTrue);
    await tester.tap(find.byKey(const ValueKey("animInside-own")));
    await tester.pumpAndSettle();
    expect(c.motionOf("a").clip(id)!.inside, isEmpty,
        reason: "turned off, nothing left behind");
  });

  testWidgets("a move has nothing inside it for a shape", (tester) async {
    var (c, _) = await pump(tester);
    var id = c.newClip("a", preset: presetNamed("Shake"));
    c.pickMotion("a", id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("animDevice-inside")), findsNothing,
        reason: "a shake is a move: a shape has nothing more to do in it");
  });
}
