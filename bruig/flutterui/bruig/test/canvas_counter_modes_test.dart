import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart' show GameCount;
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show visualBoundsOf;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';

import 'support/canvas_app.dart';
import 'support/canvas_panel_helpers.dart';
import 'support/canvas_sidebar_host.dart';

// canvas_counter_modes_test.dart is a counter as each of its five things
// (CounterMode) where a person meets it: on the stage and in its panel.

const _viewport = Size(1200, 800);

/// _face is a real face registered under a name of its own, so nothing
/// else drawn in the same run is drawn in it.
const _face = "CounterCaseInter";

/// _hint finds a panel's "?" that says [message], or with [whole] false,
/// one that starts with it.
Finder _hint(String message, {bool whole = true}) =>
    find.byWidgetPredicate((w) =>
        w is CanvasHint &&
        (whole ? w.message == message : w.message.startsWith(message)));
const _base = ElementBase(id: "n", x: 300, y: 200, width: 300, height: 160);

/// _onScreen is document point [doc] on the screen, where the stage sits
/// beside what is built before it.
Offset _onScreen(WidgetTester tester, CanvasStageState s, Offset doc) =>
    tester.getTopLeft(find.byType(CanvasStage)) + s.toStagePoint(doc);

void main() {
  /// stage shows [controller] on a stage after something else that
  /// watches it, as the editor's sidebar does, and hands back its state.
  Future<CanvasStageState> stage(
      WidgetTester tester, CanvasController controller) async {
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(Row(children: [
      // Built first, as the sidebar is, so it is already listening when
      // the stage starts.
      SizedBox(
          width: 200,
          child: ListenableBuilder(
              listenable: controller,
              builder: (_, __) => Text("${controller.revision}"))),
      Expanded(child: CanvasStage(key: key, controller: controller)),
    ])));
    await tester.pump();
    return key.currentState!;
  }

  group("opening the editor", () {
    testWidgets(
        "on a counter set to start running starts it, and says so "
        "after the page is built", (tester) async {
      const e = CounterElement(_base, keyed: false, running: true, to: 1000);
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      await stage(tester, c);
      expect(tester.takeException(), isNull);
      expect(c.counterRunning(e), isTrue);
      c.leavePage();
    });
  });

  group("From and To on a counter counted by keyframes", () {
    /// made is a new counter added as the Add menu adds one (its count laid
    /// out from the playhead), on a canvas of 96 frames at 24 a second,
    /// with its panel open.
    Future<CanvasController> made(WidgetTester tester) async {
      const doc = CanvasDocument(frames: 96, frameRate: 24);
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.addElement(newElement(ElementKind.counter, doc));
      await pumpCanvasApp(tester, designSidebar(c),
          size: const Size(1400, 900));
      await openSection(tester, "counter.content");
      return c;
    }

    CounterElement counterIn(CanvasController c) =>
        c.document.elements.single as CounterElement;

    /// shownAt is what the canvas draws of the counter on [frame].
    double shownAt(CanvasController c, int frame) {
      var e = counterIn(c);
      return e.shownValue(page: null, pose: e.poseAt(frame));
    }

    testWidgets("a fresh counter set to count to 500 counts to 500",
        (tester) async {
      var c = await made(tester);
      var keys = counterIn(c).track!.keys;
      expect(shownAt(c, keys.last.frame), 100, reason: "as made");

      await enterValue(tester, find.byKey(const ValueKey("counterTo")), "500");
      await tester.pumpAndSettle();
      expect(counterIn(c).to, 500);
      expect(shownAt(c, keys.last.frame), 500,
          reason: "its last key held the old To, so it moves with it");
      expect(shownAt(c, keys.first.frame), 0, reason: "and From is as it was");

      await enterValue(tester, find.byKey(const ValueKey("counterFrom")), "20");
      await tester.pumpAndSettle();
      expect(shownAt(c, keys.first.frame), 20);
      expect(shownAt(c, keys.last.frame), 500);
      expect(_hint("Counts 20 to 500."), findsOneWidget);
    });

    testWidgets("and the quick strip's ends do the same", (tester) async {
      var c = await made(tester);
      var last = counterIn(c).track!.keys.last.frame;
      await enterValue(
          tester, find.byKey(const ValueKey("quickCounterTo")), "250");
      await tester.pumpAndSettle();
      expect(shownAt(c, last), 250);
    });

    testWidgets(
        "but a key somebody has set to something else stays theirs, "
        "and the panel says what the keys count", (tester) async {
      var c = await made(tester);
      var keys = counterIn(c).track!.keys;
      c.frame = keys.last.frame;
      c.setValueKey(counterIn(c), KeyframeChannel.count, 80, seed: false);
      await tester.pumpAndSettle();

      await enterValue(tester, find.byKey(const ValueKey("counterTo")), "500");
      await tester.pumpAndSettle();
      expect(counterIn(c).to, 500);
      expect(shownAt(c, keys.last.frame), 80,
          reason: "the key was changed by hand, so To leaves it");
      expect(_hint("Counts 0 to 500."), findsNothing,
          reason: "it does not: its keys count 0 to 80");
      expect(
          _hint("Its keyframes count 0 to 80", whole: false), findsOneWidget);
    });
  });

  group("a counter's words in a case", () {
    /// drawn is [e] painted alone in a box 100 by 60, narrow enough that
    /// its type is shrunk to fit, as pixels.
    Future<List<int>> drawn(WidgetTester tester, CounterElement e) async {
      late List<int> out;
      await tester.runAsync(() async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        paintCounter(canvas, const Rect.fromLTWH(0, 0, 100, 60), e, 42);
        var picture = recorder.endRecording();
        var image = await picture.toImage(100, 60);
        var bytes = (await image.toByteData())!;
        image.dispose();
        picture.dispose();
        out = [
          for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i)
        ];
      });
      return out;
    }

    testWidgets("are fitted as they are drawn: upper-cased, as if typed so",
        (tester) async {
      // A real face: the test's own draws every letter the same width, so
      // a case would change nothing it measures.
      await tester.runAsync(() async {
        var loader = FontLoader(_face);
        loader.addFont(File("assets/fonts/Inter-Regular.otf")
            .readAsBytes()
            .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
        await loader.load();
      });
      const words = TextSpec(
          fontFamily: _face,
          fontSize: 18,
          color: Color(0xFFFFFFFF),
          textCase: TextCase.upper,
          align: TextAlignSpec.center);
      const cased = CounterElement(_base,
          from: 42,
          to: 42,
          after: " kilograms",
          affixSpec: words,
          numberSpec: TextSpec(
              fontFamily: _face,
              fontSize: 40,
              color: Color(0xFFFFFFFF),
              align: TextAlignSpec.center),
          box: BoxSpec(padding: 0));
      var typed = cased.copyWith(
          after: " KILOGRAMS",
          affixSpec: words.copyWith(textCase: TextCase.none));
      expect(await drawn(tester, cased), await drawn(tester, typed));
    });
  });

  group("a loose word", () {
    testWidgets("is taken wherever its letters are drawn", (tester) async {
      // "kilograms" at 20: the test face draws each letter a square, so it
      // is drawn 180 wide, centred on the box's middle, 360 to 540.
      const e = CounterElement(_base,
          keyed: false,
          after: "kilograms",
          loose: true,
          afterAt: Offset(0, 0.3),
          affixSpec: TextSpec(fontSize: 20, align: TextAlignSpec.center),
          box: BoxSpec(padding: 0));
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("n");
      var s = await stage(tester, c);
      await tester.pumpAndSettle();
      var letter = const Offset(530, 200 + 80 + 0.3 * 160);
      var g = await tester.startGesture(_onScreen(tester, s, letter));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(-10, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      var now = c.document.elementById("n")! as CounterElement;
      expect(now.x, e.x, reason: "the counter stays where it is");
      expect(now.afterAt, isNot(e.afterAt), reason: "the word is moved");
      c.leavePage();
    });
  });

  group("a mirrored page number on a left-hand page", () {
    /// left is a book of three pages showing page 2, a left-hand leaf, each
    /// page carrying a mirrored page number placed off to the left.
    CanvasDocument left() {
      var number = CounterElement(
          const ElementBase(id: "n", x: 20, y: 300, width: 120, height: 60),
          source: CounterSource.page,
          mirrored: true,
          box: const BoxSpec(fill: Color(0xFF223344)));
      return CanvasDocument(
        kind: CanvasKind.pages,
        size: const CanvasSize(width: 800, ratio: CanvasRatio.square),
        scenes: [
          for (var i = 0; i < 3; i++)
            CanvasScene(id: "p$i", elements: [number], frames: 48),
        ],
        sceneAt: 1,
      );
    }

    testWidgets("is pressed where it is drawn, across the page",
        (tester) async {
      var doc = left();
      expect(doc.pageIsLeftHand, isTrue);
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      var s = await stage(tester, c);
      await tester.pumpAndSettle();

      // Placed at 20 to 140; drawn mirrored at 660 to 780.
      await tester.tapAt(_onScreen(tester, s, const Offset(80, 330)));
      await tester.pumpAndSettle();
      expect(c.selection, isNot(contains("n")),
          reason: "nothing of it is drawn where it is placed");
      await tester.tapAt(_onScreen(tester, s, const Offset(720, 330)));
      await tester.pumpAndSettle();
      expect(c.selection, contains("n"));
      CounterElement now() => c.document.elementById("n")! as CounterElement;
      expect(visualBoundsOf(now(), c.document, c.frame).left, 660,
          reason: "its selection box is where it is drawn");

      // And moved by a drag, it goes the way the pointer goes.
      var g = await tester
          .startGesture(_onScreen(tester, s, const Offset(720, 330)));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      var scale = s.toStagePoint(const Offset(1, 0)).dx -
          s.toStagePoint(Offset.zero).dx;
      expect(visualBoundsOf(now(), c.document, c.frame).left,
          closeTo(660 + 40 / scale, 0.5));
      c.leavePage();
    });
  });

  group("Start, Reset and Set", () {
    const buttons = [CounterButton.startStop, CounterButton.reset];

    /// shot is [e] painted in a 300 by 160 box, as pixels.
    Future<List<int>> shot(WidgetTester tester, CounterElement e) async {
      late List<int> out;
      await tester.runAsync(() async {
        var recorder = ui.PictureRecorder();
        paintCounter(
            ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 300, 160), e, 30);
        var picture = recorder.endRecording();
        var image = await picture.toImage(300, 160);
        var bytes = (await image.toByteData())!;
        image.dispose();
        picture.dispose();
        out = [
          for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i)
        ];
      });
      return out;
    }

    for (var (what, e) in [
      (
        "a clock",
        const CounterElement(_base,
            keyed: false, source: CounterSource.clock, buttons: buttons)
      ),
      (
        "a game's count",
        const CounterElement(_base,
            source: CounterSource.game, gameCount: "coins", buttons: buttons)
      ),
      ("a keyed count", const CounterElement(_base, buttons: buttons)),
      (
        "a page number",
        const CounterElement(_base,
            source: CounterSource.page, buttons: buttons)
      ),
    ]) {
      testWidgets("are not drawn, pressed or offered on $what, and are kept",
          (tester) async {
        expect(counterButtonRects(e, e.bounds), isEmpty,
            reason: "nothing to press");
        expect(await shot(tester, e),
            await shot(tester, e.copyWith(buttons: const [])),
            reason: "nothing drawn");

        var c = CanvasController(
            const CanvasDocument(frames: 48, game: true, counts: [
          GameCount("coins", "Coins"),
        ]).addElement(e));
        addTearDown(c.dispose);
        c.selectOnly("n");
        await pumpCanvasApp(tester, designSidebar(c),
            size: const Size(1400, 900));
        expect(find.byKey(const ValueKey("counterButton-reset")), findsNothing,
            reason: "not offered");
        expect(e.props()["buttons"], ["startStop", "reset"],
            reason: "still in the file, for when it is a run again");
      });
    }

    testWidgets("are drawn, pressed and offered on a run", (tester) async {
      const e = CounterElement(_base, keyed: false, buttons: buttons);
      expect(counterButtonRects(e, e.bounds), hasLength(2));
      expect(await shot(tester, e),
          isNot(await shot(tester, e.copyWith(buttons: const []))));
      var c = CanvasController(const CanvasDocument(frames: 48).addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("n");
      await pumpCanvasApp(tester, designSidebar(c),
          size: const Size(1400, 900));
      await openSection(tester, "counter.more");
      expect(find.byKey(const ValueKey("counterButton-reset")), findsOneWidget);
    });
  });

  group("a clock", () {
    testWidgets(
        "keeps the time on the canvas for as long as it is open, "
        "whether or not it was set to start running", (tester) async {
      for (var running in [false, true]) {
        const clock = CounterElement(_base,
            keyed: false,
            source: CounterSource.clock,
            separator: CounterSeparator.hours);
        var c = CanvasController(const CanvasDocument()
            .addElement(clock.copyWith(running: running)));
        addTearDown(c.dispose);
        c.startCounters();
        var later = DateTime.now();
        // Long past the hundred seconds From and To would count it for.
        for (var minutes in [5, 10, 60]) {
          var ticks = c.counterTicks;
          c.tickCounters(now: later.add(Duration(minutes: minutes)));
          expect(c.counterTicks, greaterThan(ticks),
              reason: "running $running, $minutes minutes on: the canvas is "
                  "told the time has moved, to draw it again");
        }
        c.leavePage();
      }
    });

    testWidgets("and one made from a run keeps it from then on",
        (tester) async {
      const run = CounterElement(_base, keyed: false);
      var c = CanvasController(const CanvasDocument().addElement(run));
      addTearDown(c.dispose);
      c.startCounters();
      c.replaceElement(run.copyWith(
          source: CounterSource.clock, separator: CounterSeparator.hours));
      var ticks = c.counterTicks;
      c.tickCounters(now: DateTime.now().add(const Duration(seconds: 2)));
      expect(c.counterTicks, greaterThan(ticks));
      c.leavePage();
    });
  });

  group("the panel at every text size", () {
    // Each mode in a book of pages, where the page number's switches sit
    // in the Count section, in the narrow sidebar the panel opens in.
    for (var (what, e) in [
      ("keyed", const CounterElement(_base)),
      (
        "a run with buttons",
        const CounterElement(_base,
            keyed: false, buttons: CounterButton.values, looseButtons: true)
      ),
      (
        "a clock",
        const CounterElement(_base,
            keyed: false,
            source: CounterSource.clock,
            separator: CounterSeparator.hours)
      ),
      (
        "a game's count",
        const CounterElement(_base,
            source: CounterSource.game, gameCount: "coins")
      ),
      (
        "a page number",
        const CounterElement(_base, source: CounterSource.page, mirrored: true)
      ),
    ]) {
      for (var scale in const [0.65, 1.0, 1.25, 1.5]) {
        testWidgets("fits for $what at $scale", (tester) async {
          setTestTextScale(tester, scale);
          SharedPreferences.setMockInitialValues({});
          var c = CanvasController(const CanvasDocument(
              kind: CanvasKind.pages,
              game: true,
              counts: [GameCount("coins", "Coins")]).addElement(e));
          addTearDown(c.dispose);
          c.selectOnly("n");
          await pumpCanvasApp(tester, designSidebar(c),
              size: const Size(300, 9000));
          await openEverything(tester, find.byType(CanvasSidebarHost));
          expect(find.byKey(const ValueKey("counterIsPageNumber")),
              findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
