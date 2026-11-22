import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/transport_controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_rebuild_budget_test.dart is how much of the editor is built again
// for the three things done many times a second: a keystroke typed on the
// canvas, a step of a drag, and a frame of play with the mixer open.
//
// The whole editor is pumped, as the app has it, and every widget built is
// counted and put down to the editor's own widget it belongs to. Each
// workload has a budget well above what it costs now. Over budget means
// something has gone back to listening to the whole controller where it
// should listen to CanvasController.chrome or playheadMoved; the failure
// names what was built.

/// canvasWidgets are the names of the editor's own widget classes, read from
/// its source, to put each widget built down to.
final Set<String> canvasWidgets = () {
  var names = <String>{};
  var declared = RegExp(
      r"class (\w+)(?:<[^>]*>)? extends (StatelessWidget|StatefulWidget)");
  for (var f
      in Directory("lib/plugin_system/canvas").listSync(recursive: true)) {
    if (f is File && f.path.endsWith(".dart")) {
      for (var m in declared.allMatches(f.readAsStringSync())) {
        names.add(m.group(1)!);
      }
    }
  }
  return names;
}();

/// ownerOf is the nearest of the editor's widgets at or above [element].
String ownerOf(Element element) {
  String? found;
  void check(Element e) {
    var name = e.widget.runtimeType.toString().split("<").first;
    if (canvasWidgets.contains(name)) found = name;
  }

  check(element);
  if (found == null) {
    element.visitAncestorElements((e) {
      check(e);
      return found == null;
    });
  }
  return found ?? "(the app round it)";
}

/// Builds counts what is built, from [start] on.
class Builds {
  int total = 0;
  int steps = 0;
  final Map<String, int> byOwner = {};

  void start() {
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      total++;
      var owner = ownerOf(element);
      byOwner[owner] = (byOwner[owner] ?? 0) + 1;
    };
  }

  int get perStep => steps == 0 ? 0 : total ~/ steps;

  int of(String owner) => steps == 0 ? 0 : (byOwner[owner] ?? 0) ~/ steps;

  /// most are the owners that built most, for a failure to name.
  String get most {
    var sorted = byOwner.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(8).map((e) => "${e.key} ${e.value ~/ steps}").join(", ");
  }
}

void main() {
  late Builds builds;

  setUp(() => builds = Builds());
  tearDown(() => debugOnRebuildDirtyWidget = null);

  /// step does [act] and pumps one frame, as one step of the workload.
  Future<void> step(WidgetTester tester, Future<void> Function() act) async {
    await act();
    await tester.pump(const Duration(milliseconds: 16));
    builds.steps++;
  }

  /// show pumps the whole editor on a canvas of six shapes and some words.
  /// The sidebar is put away, or with [sidebar] sits above the panels on
  /// its Design sidebar: beside everything it would be in the app's side
  /// menu, which needs the chat client.
  Future<CanvasController> show(WidgetTester tester,
      {bool timeline = false, bool sidebar = false}) async {
    SharedPreferences.setMockInitialValues({});
    CanvasScreen.framedForTest = (page) => page;
    addTearDown(() => CanvasScreen.framedForTest = null);
    setTestScreen(tester, const Size(1600, 1000));
    var document = CanvasDocument(frames: 240, frameRate: 24, elements: [
      for (var i = 0; i < 6; i++)
        ShapeElement(ElementBase(
            id: "s$i",
            name: "Shape $i",
            x: 100.0 + i * 200,
            y: 600,
            width: 150,
            height: 150)),
      TextElement(
          const ElementBase(
              id: "t", name: "Words", x: 400, y: 200, width: 800, height: 200),
          text: "Hello"),
    ]);
    var controller = CanvasController(document, audioEngine: FakeEngine({}));
    addTearDown(controller.dispose);
    var prefs = CanvasPreferences()
      ..timeline = timeline
      ..sidebars = sidebar
          ? const SidebarLayout(mode: SidebarMode.above, current: "design")
          : const SidebarLayout(mode: SidebarMode.hidden);
    await tester
        .pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    return controller;
  }

  /// onStage is where [id]'s centre is on screen.
  Offset onStage(WidgetTester tester, CanvasController controller, String id) {
    var stage = tester.state<CanvasStageState>(find.byType(CanvasStage));
    var scale = stage.pageRect.width / controller.document.size.width;
    // The page's place is the stage's own: on screen, from the stage's corner.
    return tester.getTopLeft(find.byType(CanvasStage)) +
        stage.pageRect.topLeft +
        controller.document.elementById(id)!.center * scale;
  }

  group("chrome", () {
    CanvasController controller() {
      var c = CanvasController(
          CanvasDocument(elements: [
            ShapeElement(const ElementBase(id: "a", width: 10, height: 10)),
          ]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      return c;
    }

    test("passes over a gesture's steps, and catches up at its end", () {
      var c = controller();
      var told = 0;
      c.chrome.addListener(() => told++);
      c.beginInteraction();
      for (var x = 1; x <= 5; x++) {
        c.replaceElement(
            ShapeElement(
                ElementBase(id: "a", x: x * 10, width: 10, height: 10)),
            transient: true);
      }
      expect(told, 0, reason: "a drag's steps are the canvas's business");
      c.endInteraction();
      expect(told, 1, reason: "and once it is done, everything hears");
    });

    test("hears an edit that is not part of a gesture", () {
      var c = controller();
      var told = 0;
      c.chrome.addListener(() => told++);
      // transient without beginInteraction: nothing would catch up later.
      c.replaceElement(
          ShapeElement(const ElementBase(id: "a", x: 5, width: 10, height: 10)),
          transient: true);
      c.replaceElement(ShapeElement(
          const ElementBase(id: "a", x: 9, width: 10, height: 10)));
      expect(told, 2);
    });

    testWidgets("passes over frames of play, and hears play stop",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [
            ShapeElement(const ElementBase(id: "a", width: 10, height: 10)),
          ]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var told = 0;
      c.play();
      await tester.pump(const Duration(milliseconds: 10));
      c.chrome.addListener(() => told++);
      var from = c.frame;
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.frame - from, greaterThan(5), reason: "it is playing");
      expect(told, 0);
      c.pause();
      expect(told, 1);
    });

    test("passes over a game's steps and a live counter's ticks", () {
      var counter = CounterElement(const ElementBase(id: "count"),
          keyed: false, to: 1000, rate: 1);
      var c = CanvasController(
          CanvasDocument(frames: 240, game: true, elements: [counter]),
          audioEngine: FakeEngine({}));
      addTearDown(() {
        c.gaming = false;
        c.dispose();
      });
      c.gaming = true;
      c.pressCounterButton(counter, CounterButton.startStop);
      var told = 0;
      c.chrome.addListener(() => told++);
      for (var i = 0; i < 5; i++) {
        c.stepGame(1 / 60);
      }
      expect(told, 0, reason: "a step of the game is not a change");
      c.tickCounters(now: DateTime.now().add(const Duration(seconds: 1)));
      expect(c.counterValue(counter), greaterThan(0), reason: "it counted");
      expect(told, 0, reason: "nor a count moving on");
    });
  });

  group("the whole editor", () {
    testWidgets("typing a word on the canvas", (tester) async {
      var controller = await show(tester);
      var at = onStage(tester, controller, "t");
      // A click selects, a second opens the words for typing.
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      var field = find.descendant(
          of: find.byType(CanvasTextEditor),
          matching: find.byType(EditableText));
      expect(field, findsOneWidget);

      builds.start();
      var text = "Hello";
      for (var i = 0; i < 20; i++) {
        text += "x";
        await step(tester, () => tester.enterText(field, text));
      }
      expect((controller.document.elementById("t") as TextElement).text, text,
          reason: "the typing reached the document");
      // About 57 a keystroke, nearly all the field itself; it was 400 when
      // the settings band was built again for each.
      expect(builds.perStep, lessThan(120), reason: builds.most);
      expect(builds.of("CanvasSettingsBar"), 0, reason: builds.most);
    });

    testWidgets("dragging a shape", (tester) async {
      var controller = await show(tester);
      var gesture =
          await tester.startGesture(onStage(tester, controller, "s2"));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      var x = controller.document.elementById("s2")!.x;

      builds.start();
      for (var i = 0; i < 20; i++) {
        await step(tester, () => gesture.moveBy(const Offset(3, 1)));
      }
      expect(controller.document.elementById("s2")!.x, greaterThan(x),
          reason: "the shape moved");
      // About 8 a step, the stage; it was 351.
      expect(builds.perStep, lessThan(30), reason: builds.most);
      expect(builds.of("CanvasSettingsBar"), 0, reason: builds.most);
      await gesture.up();
      await tester.pump();
    });

    testWidgets("dragging a shape, with the sidebar showing its settings",
        (tester) async {
      var controller = await show(tester, sidebar: true);
      expect(find.byType(CanvasSidebar), findsOneWidget);
      var gesture =
          await tester.startGesture(onStage(tester, controller, "s2"));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.selection, {"s2"});

      builds.start();
      for (var i = 0; i < 20; i++) {
        await step(tester, () => gesture.moveBy(const Offset(3, 1)));
      }
      // The settings follow the shape (its place), and nothing else in the
      // sidebar is built: not its headings, its stack or its other panels.
      // About 82 a step, nearly all the settings' Layout section. The
      // sidebar itself was 511 more at every step, every heading built
      // again, while it listened to the whole controller.
      for (var still in [
        "CanvasSidebar",
        "CanvasLayersPanel",
        "CanvasElementsPanel",
        "ColourPanel"
      ]) {
        expect(builds.of(still), 0, reason: "$still: ${builds.most}");
      }
      expect(builds.perStep, lessThan(200), reason: builds.most);
      await gesture.up();
      await tester.pump();
    });

    testWidgets("playing, with the sidebar showing", (tester) async {
      var controller = await show(tester, timeline: true, sidebar: true);
      controller.play();
      await tester.pump(const Duration(milliseconds: 100));
      var from = controller.frame;

      builds.start();
      for (var i = 0; i < 40; i++) {
        await step(tester, () async {});
      }
      expect(controller.frame - from, greaterThan(10), reason: "it played");
      // About 16 a frame, the play bar's readout; the sidebar was 204 more.
      expect(builds.of("CanvasSidebar"), 0, reason: builds.most);
      expect(builds.perStep, lessThan(80), reason: builds.most);
      controller.pause();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets("playing with the mixer open", (tester) async {
      var controller = await show(tester, timeline: true);
      controller.setDockOpen(DockPanel.mixer, true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey("mixerToggle")), findsOneWidget);
      controller.play();
      await tester.pump(const Duration(milliseconds: 100));
      var from = controller.frame;
      double line() =>
          tester.getTopLeft(find.byKey(const ValueKey("timelinePlayhead"))).dx;
      var lineFrom = line();

      builds.start();
      for (var i = 0; i < 40; i++) {
        await step(tester, () async {});
      }
      expect(controller.frame - from, greaterThan(10), reason: "it played");
      // What follows the playhead still does, without the rest being built.
      expect(
          tester
              .widget<TransportPosition>(find.byType(TransportPosition))
              .frame,
          controller.frame,
          reason: "the play bar's readout keeps up");
      expect(line(), greaterThan(lineFrom),
          reason: "the timeline's playhead line moves");
      // About 37 a frame; it was 370, the play bar, band and timeline each
      // built again.
      expect(builds.perStep, lessThan(80), reason: builds.most);
      for (var still in ["CanvasSettingsBar", "CanvasPlayBar", "CanvasDock"]) {
        expect(builds.of(still), 0, reason: "$still: ${builds.most}");
      }
      controller.pause();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets("a game running", (tester) async {
      var controller = await show(tester, timeline: true);
      controller.apply(controller.document.copyWith(game: true));
      controller.gaming = true;
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.playing, isTrue, reason: "its timeline plays too");

      builds.start();
      for (var i = 0; i < 40; i++) {
        await step(tester, () async {});
      }
      expect(controller.gaming, isTrue);
      // It was over 700 a step, the settings band, the play bar and the
      // dock each built again; the timeline still is, 80 of what is left.
      for (var still in ["CanvasSettingsBar", "CanvasPlayBar", "CanvasDock"]) {
        expect(builds.of(still), 0, reason: "$still: ${builds.most}");
      }
      controller.gaming = false;
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
