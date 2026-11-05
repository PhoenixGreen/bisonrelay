import 'dart:convert';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dock.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_audio_fake.dart';
import 'canvas_timeline_menus.dart';

// canvas_dock_test.dart is the panels under the canvas: where each opens
// (main, left beside it, above), one at a time in a place, the layouts, and
// the dock that draws them under the play bar.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("where a panel opens", () {
    test("two places to begin with: the slots and the mixer on the left", () {
      const dock = DockLayout();
      expect(dock.places, DockPlaces.two);
      expect(dock.placeOf(DockPanel.timeline), DockPlace.main);
      expect(dock.placeOf(DockPanel.slots), DockPlace.left);
      expect(dock.placeOf(DockPanel.mixer), DockPlace.left);
      expect(dock.placeOf(DockPanel.effects), DockPlace.main);
      expect(dock.placeOf(DockPanel.animation), DockPlace.left,
          reason: "beside the timeline its clips are clicked on");
    });

    test("one place puts everything in main; above needs three", () {
      var dock =
          const DockLayout().withHome(DockPanel.animation, DockPlace.above);
      expect(dock.placeOf(DockPanel.animation), DockPlace.main,
          reason: "no above with two places");
      expect(
          dock.copyWith(places: DockPlaces.three).placeOf(DockPanel.animation),
          DockPlace.above);
      expect(dock.copyWith(places: DockPlaces.one).placeOf(DockPanel.slots),
          DockPlace.main);
      expect(dock.homeOf(DockPanel.animation), DockPlace.above,
          reason: "kept for when there is an above again");
    });

    test("kept as it is written, and junk read as the start", () {
      var dock = const DockLayout(
              places: DockPlaces.three,
              switcher: DockSwitcher.tabs,
              showLayouts: false)
          .withHome(DockPanel.mixer, DockPlace.above)
          .copyWith(saved: [
        const DockArrangement("Mine",
            shown: {DockPlace.main: DockPanel.mixer}, one: DockPanel.mixer),
      ]);
      var back = DockLayout.fromJson(jsonDecode(jsonEncode(dock.toJson())));
      expect(back, dock);
      expect(back.saved.single.shown[DockPlace.main], DockPanel.mixer);
      expect(
          DockLayout.fromJson({
            "places": "nine",
            "homes": {"x": "y"}
          }),
          const DockLayout());
      expect(DockLayout.fromJson("nonsense"), const DockLayout());
    });
  });

  group("one panel in a place", () {
    CanvasController make() {
      var c = CanvasController(const CanvasDocument(frames: 48),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      return c;
    }

    test("opening one closes whatever shared its place", () {
      var c = make();
      c.slotsBeside = true;
      c.mixerOpen = true;
      expect(c.slotsBeside, isFalse, reason: "the mixer took the left");
      expect(c.rowsShown, isTrue, reason: "main is the timeline's still");
      c.effectsOpen = true;
      expect(c.rowsShown, isFalse, reason: "the effects took main");
      expect(c.mixerOpen, isTrue);
      c.animationOpen = true;
      expect(c.mixerOpen, isFalse, reason: "the Animation panel took the left");
      expect(c.effectsOpen, isTrue);
    });

    test("moved to another place, it opens there and keeps to it", () {
      var c = make();
      c.dock = c.dock.copyWith(places: DockPlaces.three);
      c.moveDockPanel(DockPanel.effects, DockPlace.above);
      expect(c.effectsOpen, isTrue);
      expect(c.rowsShown, isTrue, reason: "the timeline keeps main");
      expect(c.dockShownIn(DockPlace.above), DockPanel.effects);
    });

    test("with one place, only one is open", () {
      var c = make();
      c.slotsBeside = true;
      expect(c.rowsShown, isTrue);
      c.dock = c.dock.copyWith(places: DockPlaces.one);
      expect([
        for (var p in DockPanel.values)
          if (c.dockOpen(p)) p
      ], hasLength(1));
      c.mixerOpen = true;
      expect(c.rowsShown, isFalse);
      expect(c.slotsBeside, isFalse);
    });

    test("Shift opens it on the left, beside main", () {
      var c = make();
      c.toggleDock(DockPanel.effects, beside: true);
      expect(c.dock.placeOf(DockPanel.effects), DockPlace.left);
      expect(c.effectsOpen, isTrue);
      expect(c.rowsShown, isTrue);
    });

    test("the slots beside the rows only with the timeline in main", () {
      var c = make();
      c.slotsBeside = true;
      expect(c.slotsWithRows, isTrue);
      expect(c.slotsWidth, greaterThan(0));
      c.moveDockPanel(DockPanel.slots, DockPlace.main);
      expect(c.slotsWithRows, isFalse);
      expect(c.slotsWidth, 0);
    });
  });

  group("layouts", () {
    test("each sets every place, and remembers it was chosen", () {
      var c = CanvasController(const CanvasDocument(frames: 48),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.arrange(builtInArrangements.firstWhere((a) => a.name == "Mix"));
      expect(c.mixerOpen, isTrue);
      expect(c.effectsOpen, isTrue);
      expect(c.rowsShown, isFalse);
      expect(c.dockArrangement, "Mix");
      c.slotsBeside = true;
      expect(c.dockArrangement, isNull, reason: "changed since");
    });

    test("with one place, a layout shows its one panel", () {
      var c = CanvasController(const CanvasDocument(frames: 48),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.dock = c.dock.copyWith(places: DockPlaces.one);
      c.arrange(builtInArrangements.firstWhere((a) => a.name == "Animate"));
      expect(c.animationOpen, isTrue);
      expect([
        for (var p in DockPanel.values)
          if (c.dockOpen(p)) p
      ], [
        DockPanel.animation
      ]);
    });

    test("one of the reader's own is kept, and forgotten", () {
      var c = CanvasController(const CanvasDocument(frames: 48),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.mixerOpen = true;
      c.saveArrangement("Mixing");
      expect(c.dock.arrangements.last.name, "Mixing");
      c.arrange(builtInArrangements.firstWhere((a) => a.name == "Clear"));
      expect(c.mixerOpen, isFalse);
      c.arrange(c.dock.saved.single);
      expect(c.mixerOpen, isTrue);
      c.removeArrangement("Mixing");
      expect(c.dock.saved, isEmpty);
    });
  });

  group("the dock", () {
    Future<CanvasController> show(WidgetTester tester,
        {double width = 1600, void Function(CanvasController)? set}) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(const CanvasDocument(frames: 48),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      set?.call(c);
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
              alignment: Alignment.bottomCenter,
              child: CanvasDock(controller: c, room: 700),
            ),
          ),
        ),
      ));
      await tester.pump();
      return c;
    }

    testWidgets("the play bar over the timeline, with a button a panel",
        (tester) async {
      var c = await show(tester);
      var bar = tester.getRect(find.byKey(const ValueKey("play")));
      var rows = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      expect(bar.bottom, lessThan(rows.top), reason: "the bar over them");
      for (var p in DockPanel.values) {
        expect(find.byKey(ValueKey(p.key)), findsOneWidget, reason: p.label);
      }
      await tester.tap(find.byKey(const ValueKey("rowsToggle")));
      await tester.pump();
      expect(c.rowsShown, isFalse);
      expect(find.byKey(const ValueKey("keyframeStrip")), findsNothing);
      expect(find.byKey(const ValueKey("play")), findsOneWidget,
          reason: "the bar stays");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the mixer on the left, beside the timeline, as wide as set",
        (tester) async {
      var c = await show(tester);
      await tester.tap(find.byKey(const ValueKey("mixerToggle")));
      await tester.pump();
      expect(c.mixerOpen, isTrue);
      var mixer = tester.getRect(find.byKey(const ValueKey("dockPlace-left")));
      var main = tester.getRect(find.byKey(const ValueKey("dockPlace-main")));
      expect(mixer.right, lessThanOrEqualTo(main.left));
      expect(mixer.top, closeTo(main.top, 1));
      await tester.drag(
          find.byKey(const ValueKey("dockLeftGrip")), const Offset(90, 0));
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey("dockPlace-left"))).width,
          closeTo(mixer.width + 90, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets("the slots beside the timeline are drawn with it, row by row",
        (tester) async {
      var c = await show(tester, set: (c) => c.slotsBeside = true);
      expect(c.slotsWithRows, isTrue);
      expect(find.byKey(const ValueKey("dockPanel-slots")), findsNothing,
          reason: "one timeline, its slots beside its rows");
      expect(find.byKey(const ValueKey("dockPanel-timeline")), findsOneWidget);
    });

    testWidgets("one place: every panel full width, each in place of the last",
        (tester) async {
      var c = await show(tester,
          set: (c) => c.dock = c.dock.copyWith(places: DockPlaces.one));
      await tester.tap(find.byKey(const ValueKey("mixerToggle")));
      await tester.pump();
      expect(c.rowsShown, isFalse);
      expect(find.byKey(const ValueKey("dockPlace-left")), findsNothing);
      var main = tester.getRect(find.byKey(const ValueKey("dockPlace-main")));
      expect(main.width, closeTo(1600, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets("tabs over each place switch it, the bar keeps the menu",
        (tester) async {
      var c = await show(tester,
          set: (c) => c.dock = c.dock.copyWith(switcher: DockSwitcher.tabs));
      expect(find.byKey(const ValueKey("mixerToggle")), findsNothing);
      expect(find.byKey(const ValueKey("playBarSettings")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("dockTab-mixer")));
      await tester.pump();
      expect(c.mixerOpen, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets("layouts only: a button a layout", (tester) async {
      var c = await show(tester,
          set: (c) => c.dock = c.dock.copyWith(switcher: DockSwitcher.layouts));
      await tester.tap(find.byKey(const ValueKey("dockLayout-Mix")));
      await tester.pump();
      expect(c.mixerOpen && c.effectsOpen, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the layouts can come off the bar; the menu still has them",
        (tester) async {
      var c = await show(tester);
      expect(find.byKey(const ValueKey("dockLayouts")), findsOneWidget);
      c.dock = c.dock.copyWith(showLayouts: false);
      await tester.pump();
      expect(find.byKey(const ValueKey("dockLayouts")), findsNothing);
      await openMore(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dockLayoutMenu-Mix")));
      await tester.pumpAndSettle();
      expect(c.mixerOpen, isTrue);
    });

    testWidgets("the menu sets how many places, and how they are switched",
        (tester) async {
      var c = await show(tester);
      await openMore(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dockPlaces-three")));
      await tester.pumpAndSettle();
      expect(c.dock.places, DockPlaces.three);
      await openMore(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dockSwitcher-tabs")));
      await tester.pumpAndSettle();
      expect(c.dock.switcher, DockSwitcher.tabs);
    });

    testWidgets("one settings button: the panels, the layouts, the timeline",
        (tester) async {
      await show(tester);
      expect(find.byKey(const ValueKey("playBarSettings")), findsOneWidget);
      expect(find.byKey(const ValueKey("dockMenu")), findsNothing);
      expect(find.byKey(const ValueKey("timelineMore")), findsNothing);
      await openMore(tester);
      for (var heading in ["PANELS", "LAYOUTS", "TIMELINE"]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      // Pictures to choose from, one a choice.
      for (var key in [
        "dockPlaces-one",
        "dockPlaces-two",
        "dockPlaces-three",
        "dockSwitcher-buttons",
        "dockSwitcher-tabs",
        "dockSwitcher-layouts",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(tester.takeException(), isNull);
      await closeMore(tester);
    });

    testWidgets("a panel above, over the bottom places", (tester) async {
      var c = await show(tester, set: (c) {
        c.dock = c.dock.copyWith(places: DockPlaces.three);
        c.moveDockPanel(DockPanel.animation, DockPlace.above);
      });
      var above = tester.getRect(find.byKey(const ValueKey("dockRow-above")));
      var lower = tester.getRect(find.byKey(const ValueKey("dockRow-lower")));
      expect(above.bottom, lessThanOrEqualTo(lower.top + 0.5));
      expect(c.rowsShown, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets("narrow, the buttons are icons and nothing overflows",
        (tester) async {
      await show(tester, width: 900);
      expect(find.text("Mixer"), findsNothing);
      expect(find.byKey(const ValueKey("mixerToggle")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the bar under the panels, where it is asked to be",
        (tester) async {
      var c = await show(tester);
      // After the bar has read the reader's choice back: see CanvasPlayBar.
      c.barBelow = true;
      await tester.pump();
      var bar = tester.getRect(find.byKey(const ValueKey("play")));
      var rows = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      expect(bar.top, greaterThan(rows.bottom));
    });
  });
}
