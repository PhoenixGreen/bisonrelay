import 'dart:convert';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dock.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
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
      expect(dock.placeOf(DockPanel.chain), DockPlace.main);
    });

    test("the Effects and Animation panels of before are the Chain", () {
      expect(DockPanel.fromName("effects"), DockPanel.chain);
      expect(DockPanel.fromName("animation"), DockPanel.chain);
      expect(DockPanel.fromName("chain"), DockPanel.chain);
      var saved = DockLayout.fromJson(jsonDecode(jsonEncode(const DockLayout()
              .withHome(DockPanel.chain, DockPlace.left)
              .toJson())
          .replaceAll('"chain"', '"animation"')));
      expect(saved.homeOf(DockPanel.chain), DockPlace.left,
          reason: "a layout saved with the old name keeps its place");
    });

    test("one place puts everything in main; above needs three", () {
      var dock = const DockLayout().withHome(DockPanel.chain, DockPlace.above);
      expect(dock.placeOf(DockPanel.chain), DockPlace.main,
          reason: "no above with two places");
      expect(dock.copyWith(places: DockPlaces.three).placeOf(DockPanel.chain),
          DockPlace.above);
      expect(dock.copyWith(places: DockPlaces.one).placeOf(DockPanel.slots),
          DockPlace.main);
      expect(dock.homeOf(DockPanel.chain), DockPlace.above,
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
      expect(c.rowsShown, isFalse, reason: "the Chain took main");
      expect(c.mixerOpen, isTrue);
      c.animationOpen = true;
      expect(c.mixerOpen, isTrue,
          reason: "the Chain keeps main, on its motion");
      expect(c.effectsOpen, isFalse, reason: "one view at a time");
      expect(c.chainShowsMotion, isTrue);
    });

    test("the Chain's button opens it on what is picked", () {
      var c = CanvasController(
          CanvasDocument(frames: 48, elements: [
            ShapeElement(const ElementBase(id: "s", width: 100, height: 40)),
            AudioElement(const ElementBase(id: "a", name: "Music"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 2)],
                    timed: true)),
          ]),
          audioEngine: FakeEngine(const {"t": 2}));
      addTearDown(c.dispose);
      c.selectOnly("s");
      c.toggleDock(DockPanel.chain);
      expect(c.chainShowsMotion, isTrue, reason: "a shape: its motion");
      c.showChain(motion: false);
      expect(c.chainShowsMotion, isFalse,
          reason: "switched by hand, and not switched back");
      // Last on its motion; then a channel picked opens it on its sound.
      c.showChain(motion: true);
      c.toggleDock(DockPanel.chain);
      c.selectBackground();
      c.selectedChannel = "a";
      c.toggleDock(DockPanel.chain);
      expect(c.chainShowsMotion, isFalse,
          reason: "a channel picked: its sound");
    });

    test("the Chain's button opens it on the view it was last on", () {
      var c = make();
      c.animationOpen = true;
      c.toggleDock(DockPanel.chain);
      expect(c.dockOpen(DockPanel.chain), isFalse);
      expect(c.animationOpen || c.effectsOpen, isFalse);
      c.toggleDock(DockPanel.chain);
      expect(c.chainShowsMotion, isTrue, reason: "back on its motion");
      c.showChain(motion: false);
      expect(c.effectsOpen, isTrue);
      expect(c.animationOpen, isFalse);
      c.toggleDock(DockPanel.chain);
      c.toggleDock(DockPanel.chain);
      expect(c.effectsOpen, isTrue, reason: "back on its sound");
    });

    test("moved to another place, it opens there and keeps to it", () {
      var c = make();
      c.dock = c.dock.copyWith(places: DockPlaces.three);
      c.moveDockPanel(DockPanel.chain, DockPlace.above);
      expect(c.dockOpen(DockPanel.chain), isTrue);
      expect(c.rowsShown, isTrue, reason: "the timeline keeps main");
      expect(c.dockShownIn(DockPlace.above), DockPanel.chain);
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
      c.toggleDock(DockPanel.chain, beside: true);
      expect(c.dock.placeOf(DockPanel.chain), DockPlace.left);
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
        DockPanel.chain
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
        {double width = 1600,
        void Function(CanvasController)? set,
        CanvasDocument document = const CanvasDocument(frames: 48)}) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(document, audioEngine: FakeEngine(const {}));
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

    for (var (width, scale, named) in [
      (1300.0, 1.2, true),
      (2000.0, 1.5, true),
      (560.0, 1.0, false),
    ]) {
      testWidgets(
          "the panels' buttons have their names where they fit: "
          "$width wide at $scale", (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var c = CanvasController(const CanvasDocument(frames: 48),
            audioEngine: FakeEngine(const {}));
        addTearDown(c.dispose);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: CanvasDock(controller: c, room: 700),
              ),
            ),
          ),
        ));
        // Measured after a frame, and settled the frame after.
        await tester.pump();
        await tester.pump();
        for (var p in DockPanel.values) {
          expect(
              find.descendant(
                  of: find.byKey(ValueKey(p.key)),
                  matching: find.text(p.label)),
              named ? findsOneWidget : findsNothing,
              reason: p.label);
        }
        expect(tester.takeException(), isNull);
      });
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

    testWidgets("the Chain's tabs open a channel's notes and its clip",
        (tester) async {
      var c = await show(tester,
          set: (c) => c.openEffects("p"),
          document: CanvasDocument(
            frames: 100,
            elements: [
              AudioElement(const ElementBase(id: "p", name: "Keys"),
                  clip: const MediaClip(timed: true),
                  instrument: const InstrumentPart()),
            ],
            session: const SessionGrid().put(
                "p",
                0,
                const SessionClip(
                    id: "clip",
                    name: "Chords",
                    midi: true,
                    bars: 1,
                    notes: [MidiNote(60, 0.1, 1)])),
          ));
      await tester.pump();
      expect(find.byKey(const ValueKey("chainTabDevices")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("chainTabNotes")));
      await tester.pump();
      expect(c.pianoRollShown, isTrue, reason: "the part's notes");
      await tester.tap(find.byKey(const ValueKey("chainTabClip")));
      await tester.pump();
      expect(c.clipEditorShown, isTrue, reason: "its first clip");
      await tester.tap(find.byKey(const ValueKey("chainTabDevices")));
      await tester.pump();
      expect((c.pianoRollShown, c.clipEditorShown), (false, false));
      expect(tester.takeException(), isNull);
    });

    testWidgets("Speech is the Chain's Speech view, not a device",
        (tester) async {
      var c = await show(tester,
          set: (c) => c.openEffects("v"),
          document: const CanvasDocument(frames: 100, elements: [
            AudioElement(ElementBase(id: "v", name: "Narrator"),
                clip: MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 2)],
                    timed: true)),
          ]));
      await tester.pump();
      expect(find.byKey(const ValueKey("speechStart")), findsNothing,
          reason: "the chain holds only what the sound passes through");
      await tester.tap(find.byKey(const ValueKey("chainTabSpeech")));
      await tester.pump();
      expect(c.speechShown, isTrue);
      await tester.tap(find.byKey(const ValueKey("speechStartButton")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.speechOf("v"), isNotNull);
      expect(find.byKey(const ValueKey("device-speech")), findsOneWidget);
      expect(find.byKey(const ValueKey("speechSing")), findsOneWidget,
          reason: "Sing it, after the speech");
      await tester.tap(find.byKey(const ValueKey("chainTabDevices")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey("device-speech")), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a timeline squeezed below its rows is cut off, not spilled",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Half a pixel short of its rows, it is still drawn rather than
      // folded to its bar: the height that spilled. And with two scenes
      // run together, the scenes' strip over the rows too.
      var one = CanvasController(const CanvasDocument(frames: 48),
          audioEngine: FakeEngine(const {}));
      addTearDown(one.dispose);
      var two = CanvasController(
          const CanvasDocument(frames: 48, scenes: [
            CanvasScene(id: "one"),
            CanvasScene(id: "two"),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(two.dispose);
      two.playAll = true;
      for (var (c, h, bar) in [
        (one, 85.5, false),
        (two, 85.5, false),
        (two, 90.0, false),
        (one, 60.0, false),
        (one, 90.0, true)
      ]) {
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: CanvasTimeline(
                    controller: c, height: h, onResize: (_) {}, showBar: bar),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: "at $h");
      }
    });

    testWidgets("the Chain switches between its sound and its motion",
        (tester) async {
      var c = await show(tester, set: (c) => c.toggleDock(DockPanel.chain));
      expect(find.byKey(const ValueKey("chainPanel")), findsOneWidget);
      expect(find.byKey(const ValueKey("chainSound")), findsOneWidget,
          reason: "it opens on its sound");
      await tester.tap(find.byKey(const ValueKey("chainShowMotion")));
      await tester.pump();
      expect(c.chainShowsMotion, isTrue);
      expect(find.byKey(const ValueKey("chainMotion")), findsOneWidget);
      expect(find.byKey(const ValueKey("chainSound")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("chainShowSound")));
      await tester.pump();
      expect(c.effectsOpen, isTrue);
      expect(find.byKey(const ValueKey("chainSound")), findsOneWidget);
      // Its header resizes it, as a panel's top edge does.
      var before =
          tester.getSize(find.byKey(const ValueKey("chainPanel"))).height;
      await tester.drag(
          find.byKey(const ValueKey("chainTier")), const Offset(0, -60));
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey("chainPanel"))).height,
          greaterThan(before));
      // Closed from its ⋯.
      await tester.tap(find.byKey(const ValueKey("chainMore")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("chainClose")));
      await tester.pump();
      await tester.pump();
      expect(c.dockOpen(DockPanel.chain), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a panel above, over the bottom places", (tester) async {
      var c = await show(tester, set: (c) {
        c.dock = c.dock.copyWith(places: DockPlaces.three);
        c.moveDockPanel(DockPanel.chain, DockPlace.above);
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
