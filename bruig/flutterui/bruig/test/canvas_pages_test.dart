import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui;

// canvas_pages_test.dart is a document of pages: what choosing it settles,
// what a cover takes a page out of, and what number each leaf carries.

/// pages is a document of [count] canvases, of pages.
CanvasDocument pages(int count, {List<PageCover> covers = const []}) =>
    CanvasDocument(
      kind: CanvasKind.pages,
      size: const CanvasSize(ratio: CanvasRatio.a4, width: a4PageWidth),
      scenes: [
        for (var i = 0; i < count; i++)
          CanvasScene(
            id: "p$i",
            cover: i < covers.length ? covers[i] : PageCover.none,
          ),
      ],
    );

void main() {
  group("what a document is", () {
    test("scenes until somebody says otherwise", () {
      expect(const CanvasDocument().kind, CanvasKind.scenes);
      expect(const CanvasDocument().isPages, isFalse,
          reason: "a document that has to be told what it is, is not started");
    });

    test("choosing pages puts a new canvas on paper", () {
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.wide, width: 1920)));
      addTearDown(controller.dispose);

      controller.setKind(CanvasKind.pages);
      expect(controller.document.kind, CanvasKind.pages);
      expect(controller.document.size.ratio, CanvasRatio.a4);
      expect(controller.document.size.width, a4PageWidth);
      expect(controller.document.frameRate, 24,
          reason: "pages turn, and a turn at one frame a second takes "
              "eighteen seconds");
    });

    test("and leaves a canvas already on paper alone", () {
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.a4Wide, width: 3508)));
      addTearDown(controller.dispose);

      controller.setKind(CanvasKind.pages);
      expect(controller.document.size.ratio, CanvasRatio.a4Wide,
          reason: "a shape chosen on purpose is not an oversight");
      expect(controller.document.size.width, 3508);
    });

    test("the whole of choosing it is one undo step", () {
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.wide, width: 1920)));
      addTearDown(controller.dispose);

      controller.setKind(CanvasKind.pages);
      controller.undo();
      expect(controller.document.kind, CanvasKind.scenes);
      expect(controller.document.size.ratio, CanvasRatio.wide,
          reason: "the paper went back with the word that brought it");
    });

    test("and going back keeps what was built", () {
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.wide, width: 1920)));
      addTearDown(controller.dispose);

      controller.setKind(CanvasKind.pages);
      controller.setKind(CanvasKind.scenes);
      expect(controller.document.size.ratio, CanvasRatio.a4,
          reason: "a switch that threw a layout away is one nobody presses");
    });

    // At one frame a second a turn of eighteen frames takes eighteen
    // seconds, and playing a document through looked like playback that
    // never ended.
    test("and putting a document of pages on paper keeps its rate", () {
      var controller = CanvasController(pages(2));
      addTearDown(controller.dispose);
      expect(defaultRateFor(CanvasRatio.a4, CanvasKind.pages), 24);
      expect(defaultRateFor(CanvasRatio.a4, CanvasKind.scenes), 1,
          reason: "a printed scene really is a still");
      expect(controller.document.frameRate, 24);
    });

    test("but a rate somebody typed is theirs", () {
      var controller = CanvasController(const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.wide, width: 1920),
        frameRate: 30,
      ));
      addTearDown(controller.dispose);
      controller.setKind(CanvasKind.pages);
      expect(controller.document.frameRate, 30);
    });

    // A cut is still the default for both: a page turn is chosen, not
    // imposed on every document somebody makes of pages.
    test("both kinds cut until told otherwise, and a turn reads back", () {
      expect(const CanvasDocument().defaultTransition.kind,
          SceneTransitionKind.cut);
      expect(pages(2).defaultTransition.kind, SceneTransitionKind.cut);
      expect(SceneTransitionKind.fromName("pageTurn"),
          SceneTransitionKind.pageTurn,
          reason: "a document saved with one opens with it");
      expect(
          SceneTransitionKind.pageTurn.familyOf, SceneTransitionFamily.paper);
    });
  });

  group("covers and numbering", () {
    test("a cover is not numbered and the page after it is page one", () {
      var doc = pages(4, covers: [PageCover.front]);
      expect(doc.pageNumberAt(0), isNull);
      expect(doc.pageNumberAt(1), 1);
      expect(doc.pageNumberAt(2), 2);
    });

    test("unless the covers are counted", () {
      var doc = pages(3, covers: [PageCover.front]).copyWith(
          pages: const PagesSpec(countCovers: true, numbersOnCovers: true));
      expect(doc.pageNumberAt(0), 1);
      expect(doc.pageNumberAt(1), 2);
    });

    // Two answers to what reads like one question: a magazine counts its
    // cover as page one and does not print a 1 on it.
    test("counted and printed are different questions", () {
      var doc = pages(3, covers: [PageCover.front])
          .copyWith(pages: const PagesSpec(countCovers: true));
      expect(doc.pageNumberAt(0), isNull, reason: "nothing printed on it");
      expect(doc.pageNumberAt(1), 2, reason: "but it was counted");
    });

    test("numbering can start anywhere", () {
      var doc = pages(3).copyWith(pages: const PagesSpec(startAt: 90));
      expect(doc.pageNumberAt(0), 90);
      expect(doc.pageNumberAt(2), 92);
    });

    test("nothing is numbered in a document of scenes", () {
      var doc = pages(3).copyWith(kind: CanvasKind.scenes);
      expect(doc.pageNumberAt(0), isNull);
    });

    test("only one page holds each mark", () {
      var controller = CanvasController(pages(3));
      addTearDown(controller.dispose);

      controller.setSceneCover(0, PageCover.front);
      controller.setSceneCover(2, PageCover.back);
      expect(controller.document.pageCovers,
          [PageCover.front, PageCover.none, PageCover.back]);

      // Marking another front cover takes the mark off the first: two of them
      // would be two answers to what number a page carries.
      controller.setSceneCover(1, PageCover.front);
      expect(controller.document.pageCovers,
          [PageCover.none, PageCover.front, PageCover.back]);
    });

    // A counter is a counter wherever it is added: a page that carries a
    // countdown or a total is a page like any other. The switch that turns
    // one into a page number is in its settings.
    test("a counter added to a document of pages is still a counter", () {
      var made = newElement(ElementKind.counter, pages(2));
      expect((made as CounterElement).source, CounterSource.run);
    });

    // A left-hand leaf carries its number on the other edge, so that the
    // number is on the outside of the page on both sides of a spread.
    test("a mirrored page number swaps sides on a left-hand page", () {
      expect(pageIsLeft(0), isFalse, reason: "the first leaf is a right page");
      expect(pageIsLeft(1), isTrue);
      expect(pageIsLeft(2), isFalse);
      expect(pages(4).copyWith(sceneAt: 1).pageIsLeftHand, isTrue);
      expect(pages(4).copyWith(sceneAt: 2).pageIsLeftHand, isFalse);
      expect(const CanvasDocument().pageIsLeftHand, isFalse,
          reason: "a set of scenes has no left-hand leaf");
    });

    test("and the mirror is written down and read back", () {
      var number = CounterElement(const ElementBase(id: "n"),
          source: CounterSource.page, mirrored: true);
      var back = elementFromJson(number.toJson()) as CounterElement;
      expect(back.mirrored, isTrue);
      expect(back.source, CounterSource.page);
    });

    // Every move and every resize goes through rebase, so a field left out
    // of it is a setting that switches itself off the first time the element
    // is dragged.
    test("the mirror survives the number being moved", () {
      var number = CounterElement(const ElementBase(id: "n"),
          source: CounterSource.page, mirrored: true);
      var moved = number.withBase(x: 40, y: 90) as CounterElement;
      expect(moved.mirrored, isTrue);
      expect(moved.source, CounterSource.page);
      expect(moved.x, 40);
    });

    // A cover carries no number, so the master opened from one had nothing
    // to draw -- an element that cannot be seen cannot be placed.
    test("the master always has a number to show", () {
      var doc = pages(3, covers: [PageCover.front]);
      expect(doc.pageNumberAt(0), isNull);
      var master = doc.copyWith(
          master: const CanvasScene(id: "m"), masterOn: true, onMaster: true);
      expect(master.editingMaster, isTrue);
      expect(master.pageNumber, 1,
          reason: "the first number the document actually prints");
    });

    test("a page number is read off the page, not run or keyed", () {
      var number = CounterElement(const ElementBase(id: "n"),
          source: CounterSource.page);
      expect(number.isPageNumber, isTrue);
      expect(number.live, isFalse,
          reason: "it does not run, and it has no buttons");
    });
  });

  group("facing pages", () {
    test("are off until asked for", () {
      expect(pages(4).facingAt(1), isNull);
    });

    // The first leaf stands alone and everything after it pairs. A cover
    // *is* the first leaf, so marking one must not put two single pages at
    // the front of the document -- which is what it did.
    test("the first leaf stands alone and the rest pair from there", () {
      var doc = pages(6, covers: [PageCover.front])
          .copyWith(pages: const PagesSpec(facing: true));
      expect(doc.facingAt(0), isNull, reason: "the cover is the first leaf");
      expect(doc.facingAt(1), 2, reason: "and pairing starts straight after");
      expect(doc.facingAt(2), 1);
      expect(doc.facingAt(3), 4);
      expect(doc.facingIsLeft(1), isTrue);
      expect(doc.facingIsLeft(2), isFalse);
    });

    test("and the same rule with no cover at all", () {
      var doc = pages(5).copyWith(pages: const PagesSpec(facing: true));
      expect(doc.facingAt(0), isNull, reason: "page one opens alone");
      expect(doc.facingAt(1), 2);
      expect(doc.facingAt(3), 4);
    });

    // A cover breaks the pair it lands in: the leaf that would have faced it
    // stands alone rather than facing the outside of the document.
    test("a cover breaks the pair it lands in", () {
      var doc = pages(5, covers: [
        PageCover.none,
        PageCover.none,
        PageCover.none,
        PageCover.none,
        PageCover.back
      ]).copyWith(pages: const PagesSpec(facing: true));
      expect(doc.facingAt(1), 2);
      expect(doc.facingAt(3), isNull, reason: "4 is the back cover");
      expect(doc.facingAt(4), isNull);
    });

    test("and never pair with a cover", () {
      var doc = pages(4, covers: [
        PageCover.none,
        PageCover.none,
        PageCover.none,
        PageCover.back
      ]).copyWith(pages: const PagesSpec(facing: true));
      expect(doc.facingAt(1), 2, reason: "the pair before it is untouched");
      expect(doc.facingAt(3), isNull, reason: "the back has nothing beside it");
    });
  });

  group("written down and read back", () {
    test("the kind, the settings and the covers all survive", () {
      var doc = pages(3, covers: [
        PageCover.front,
        PageCover.none,
        PageCover.back
      ]).copyWith(
          pages: const PagesSpec(facing: true, startAt: 7, countCovers: true));
      var back = CanvasDocument.fromJson(doc.toJson());

      expect(back.kind, CanvasKind.pages);
      expect(back.pages.facing, isTrue);
      expect(back.pages.startAt, 7);
      expect(back.pages.countCovers, isTrue);
      expect(
          back.pageCovers, [PageCover.front, PageCover.none, PageCover.back]);
    });

    test("and a document of scenes writes none of it down", () {
      var json = const CanvasDocument().toJson();
      expect(json.containsKey("kind"), isFalse);
      expect(json.containsKey("pages"), isFalse);
    });
  });

  group("on the settings bar and in the panel", () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> show(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets("the type is the first thing the canvas settings ask",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.wide, width: 1920)));
      addTearDown(controller.dispose);
      await show(tester, CanvasSettingsPanel(controller: controller));

      var kind = find.byKey(const ValueKey("canvasKind"));
      expect(kind, findsOneWidget);
      expect(
          tester.getRect(kind).left,
          lessThan(
              tester.getRect(find.byKey(const ValueKey("canvasRatio"))).left),
          reason: "everything after it follows from the answer");

      // Nothing about pages on a document of scenes: every one of those
      // settings would be a question with no answer.
      expect(find.byKey(const ValueKey("pagesFacing")), findsNothing);

      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pages").last);
      await tester.pumpAndSettle();

      expect(controller.document.kind, CanvasKind.pages);
      expect(controller.document.size.ratio, CanvasRatio.a4);
      expect(find.byKey(const ValueKey("pagesFacing")), findsOneWidget);
      expect(find.byKey(const ValueKey("pagesStartAt")), findsOneWidget);
    });

    testWidgets("the panel is named for what the canvases are", (tester) async {
      var controller = CanvasController(pages(2));
      addTearDown(controller.dispose);
      await show(tester, CanvasDesignPanel(controller: controller));

      expect(find.text("PAGES"), findsWidgets);
      expect(find.text("SCENES"), findsNothing);

      await show(tester, CanvasScenesPanel(controller: controller));
      expect(find.text("Master page"), findsOneWidget,
          reason: "the master of a document of pages is a page");
      expect(find.text("Master scene"), findsNothing);
    });
  });

  // The view while two leaves are showing. What it is easy to get wrong is
  // that a spread is twice as wide and exactly as tall.
  group("the spread on the stage", () {
    const viewport = Size(1200, 800);

    Future<CanvasStageState> stage(
        WidgetTester tester, CanvasController controller) async {
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = viewport;
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
            body: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: CanvasStage(key: key, controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return key.currentState!;
    }

    CanvasController facing(int at) {
      var controller = CanvasController(
          pages(6).copyWith(pages: const PagesSpec(facing: true), sceneAt: at));
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets("is twice as wide and exactly as tall as one page",
        (tester) async {
      // Halving the fitted scale halves the height too, and on a canvas
      // fitted whole -- where the height is what decides -- that is a spread
      // drawn at half the size it should be.
      var alone = await stage(tester, CanvasController(pages(6)));
      var oneHigh = alone.pageRect.height;

      var pair = await stage(tester, facing(1));
      expect(pair.spreadRect.width, closeTo(pair.pageRect.width * 2, 0.5));
      expect(pair.spreadRect.height, closeTo(pair.pageRect.height, 0.5));
      expect(pair.pageRect.height, lessThanOrEqualTo(oneHigh));
      // The number that matters. Halving the fitted scale gave exactly half,
      // and in a window this shape two A4 leaves side by side still fit
      // across, so the height should not have come down at all.
      expect(pair.pageRect.height, greaterThan(oneHigh / 2 + 1),
          reason: "it is the width that has to make room, not the height");
    });

    testWidgets("sits in the middle of the window, whichever page is open",
        (tester) async {
      var left = await stage(tester, facing(1));
      var middleOfLeft = left.spreadRect.center.dx;
      expect(middleOfLeft, closeTo(viewport.width / 2, 1),
          reason: "the spread is centred, not the page being edited");
      expect(left.pageRect.right, closeTo(middleOfLeft, 1),
          reason: "an odd page is the left leaf, against the spine");

      var right = await stage(tester, facing(2));
      expect(right.spreadRect.center.dx, closeTo(middleOfLeft, 1),
          reason: "and it does not move when the other leaf is opened");
      expect(right.pageRect.left, closeTo(middleOfLeft, 1));
    });

    // Fitting to the width exists to fill the window with the page being
    // worked on -- it ignores the height entirely for that reason -- and a
    // spread in it is that page at half the width.
    testWidgets("is not shown at all when the canvas is fitted to the width",
        (tester) async {
      var controller = facing(1);
      controller.fit = CanvasFit.width;
      var view = await stage(tester, controller);
      expect(view.spreadRect.width, closeTo(view.pageRect.width, 0.5));
      expect(view.pageRect.center.dx, closeTo(viewport.width / 2, 1));
    });

    // The master is one page. Drawn in the spread of whichever page was open
    // before it, it looked different depending on where it was opened from.
    testWidgets("is not shown on the master, whichever page was open",
        (tester) async {
      for (var from in [1, 2]) {
        var controller = facing(from);
        controller.showMaster();
        var view = await stage(tester, controller);

        expect(controller.onMaster, isTrue);
        expect(view.spreadRect.width, closeTo(view.pageRect.width, 0.5),
            reason: "the master is a page alone, opened from page $from");
        expect(view.pageRect.center.dx, closeTo(viewport.width / 2, 1));
        // Placed as a right-hand page. A mirrored element is drawn on the
        // opposite side of the page from the box that moves it.
        expect(controller.document.pageIsLeftHand, isFalse);
        expect(controller.document.pageNumber, isNotNull,
            reason:
                "and it has a number to show, or there is nothing to place");
      }
    });

    // Played as a book, every leaf is in its own place, so the frame does not
    // change size between a cover and the spread after it.
    testWidgets("is given room while the book plays, even on a cover",
        (tester) async {
      var controller = CanvasController(pages(6, covers: [PageCover.front])
          .copyWith(pages: const PagesSpec(facing: true)));
      addTearDown(controller.dispose);
      var alone = await stage(tester, controller);
      expect(alone.spreadRect.width, closeTo(alone.pageRect.width, 0.5),
          reason: "editing, a cover stands on its own");

      controller.previewTransitionAfter(0);
      await tester.pump();
      expect(alone.spreadRect.width, closeTo(alone.pageRect.width * 2, 0.5));
      expect(alone.pageRect.left, closeTo(alone.spreadRect.center.dx, 1),
          reason: "the first leaf is a right-hand page");
      controller.stopPreview();
      await tester.pump();
    });

    // A leaf turns when the spread changes. Two pages of one spread are both
    // already on screen, so going from one to the other is the cursor moving
    // across an open book, not a page turning -- and animated anyway it slid
    // away from the spine, which is a turn that starts in the middle.
    test("a turn happens where the spread changes, not inside one", () {
      var doc = pages(6, covers: [PageCover.front])
          .copyWith(pages: const PagesSpec(facing: true));

      // The cover is alone, so leaving it opens a spread: that is a turn.
      expect(doc.facingAt(0), isNull);
      // Pages one and two face each other, so the join between them is not.
      expect(doc.facingAt(1), 2, reason: "both leaves are already showing");
      // And the join out of the right-hand leaf is a turn again.
      expect(doc.facingAt(2), 1);
      expect(doc.facingAt(2) == 3, isFalse,
          reason: "three is the next spread, not the facing leaf");
    });

    testWidgets("and pressing the other leaf opens it", (tester) async {
      var controller = facing(1);
      var view = await stage(tester, controller);
      expect(controller.document.at, 1);

      // A press on the right-hand half, which is page two.
      await tester.tapAt(Offset(view.pageRect.right + view.pageRect.width / 2,
          view.pageRect.center.dy));
      await tester.pumpAndSettle();
      expect(controller.document.at, 2);
      expect(controller.selection, isEmpty,
          reason: "opening a page is not selecting something on it");
    });
  });

  // A book played through: every leaf in its own place, a spread moving as
  // one picture, and a leaf that turns. Checked by reading pixels back,
  // since the three things reported were all things that looked wrong.
  group("playing a book", () {
    const paper = [
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
      Color(0xFFFFFF00),
      Color(0xFF00FFFF),
      Color(0xFFFF00FF),
      Color(0xFF800000),
      Color(0xFF008000),
    ];
    const ink = Color(0xFF000000);

    /// book is eight pages facing, each on its own paper, with a bar placed on
    /// page one and pulled across the gutter onto page two.
    CanvasDocument book(SceneTransitionKind kind) {
      var size = const CanvasSize(ratio: CanvasRatio.a4, width: a4PageWidth);
      var w = size.size.width, h = size.size.height;
      return CanvasDocument(
        kind: CanvasKind.pages,
        size: size,
        pages: const PagesSpec(facing: true),
        master: CanvasScene(id: "m", transition: SceneTransition.bestFor(kind)),
        scenes: [
          for (var i = 0; i < paper.length; i++)
            CanvasScene(
              id: "p$i",
              frames: 30,
              background: CanvasBackground(
                  spec: ProceduralSpec(
                      style: ProceduralStyle.plain, background: paper[i])),
              elements: [
                if (i == 1)
                  ShapeElement(
                      ElementBase(
                          id: "across",
                          x: w * 0.5,
                          y: h * 0.45,
                          width: w,
                          height: h * 0.1),
                      fill: ink),
              ],
            ),
        ],
      );
    }

    /// through is the moment [part] of the way through the join after
    /// [scene].
    int through(CanvasDocument doc, int scene, double part) {
      var frames = [
        for (var at = 0; at < doc.sequenceFrames; at++)
          if (placeInSequence(doc, at) case var p
              when p.scene == scene && p.changing)
            at
      ];
      return frames[((frames.length - 1) * part).round()];
    }

    /// seen is which paper (or the ink) is at [where], given as fractions
    /// of the whole spread.
    Future<Color> seen(CanvasDocument doc, int at, Offset where,
        {ProceduralCache? backgrounds}) async {
      var size = doc.size.size;
      const s = 0.1;
      var w = (size.width * 2 * s).round(), h = (size.height * s).round();
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.scale(s);
      paintBookFrame(canvas, doc, at, left: 0, backgrounds: backgrounds);
      var image = await recorder.endRecording().toImage(w, h);
      var bytes = await image.toByteData();
      var x = (where.dx * w).round().clamp(0, w - 1);
      var y = (where.dy * h).round().clamp(0, h - 1);
      var o = (y * w + x) * 4;
      var got = Color.fromARGB(255, bytes!.getUint8(o), bytes.getUint8(o + 1),
          bytes.getUint8(o + 2));
      double apart(Color a) =>
          (a.r - got.r).abs() + (a.g - got.g).abs() + (a.b - got.b).abs();
      return [...paper, ink].reduce((a, b) => apart(a) <= apart(b) ? a : b);
    }

    testWidgets("a picture across the gutter stays while the right leaf plays",
        (tester) async {
      await tester.runAsync(() async {
        var doc = book(SceneTransitionKind.cut);
        var playingTwo = doc.startOfScene(2) + 10;
        expect(placeInSequence(doc, playingTwo).scene, 2);
        expect(await seen(doc, playingTwo, const Offset(0.6, 0.5)), ink,
            reason: "the bar placed on page one reaches onto page two");
        expect(await seen(doc, playingTwo, const Offset(0.9, 0.2)), paper[2]);
      });
    });

    testWidgets("a slide between spreads moves the left leaf too",
        (tester) async {
      await tester.runAsync(() async {
        var doc = book(SceneTransitionKind.slideLeft);
        // Three quarters of the way, the arriving spread's left leaf is well
        // into the old left leaf's half. Moving one page, the left half kept
        // page one throughout.
        var at = through(doc, 2, 0.8);
        expect(await seen(doc, at, const Offset(0.45, 0.2)), paper[3]);
      });
    });

    testWidgets(
        "a page turn uncovers the next right leaf and lays its back "
        "on the left", (tester) async {
      await tester.runAsync(() async {
        var doc = book(SceneTransitionKind.pageTurn);
        var early = through(doc, 2, 0.3);
        expect(await seen(doc, early, const Offset(0.2, 0.2)), paper[1],
            reason: "the left leaf lies still until the turn reaches it");
        expect(await seen(doc, early, const Offset(0.98, 0.97)), paper[4],
            reason: "the corner goes first, uncovering page four");
        expect(await seen(doc, early, const Offset(0.55, 0.1)), paper[2],
            reason: "and the head of the leaf is still down");

        var late = through(doc, 2, 0.9);
        expect(await seen(doc, late, const Offset(0.25, 0.5)), paper[3],
            reason: "the back of the leaf is page three");
        expect(await seen(doc, late, const Offset(0.8, 0.5)), paper[4]);
      });
    });

    // A turn puts four leaves on screen. Through a cache of three, one of them
    // was thrown out every frame, and while it was made again the stand-in
    // was another page's paper -- a flicker between two colours.
    testWidgets("the paper holds its colour through a turn", (tester) async {
      await tester.runAsync(() async {
        var doc = book(SceneTransitionKind.pageTurn);
        var cache = ProceduralCache();
        addTearDown(cache.dispose);
        var begins = through(doc, 4, 0);
        var halfway = through(doc, 4, 0.5);
        // Played from the start of the spread, as it would be, so the cache
        // has been asked for what it is asked for in the editor.
        var settled = through(doc, 2, 1) + 1;
        for (var at = settled; at <= halfway; at++) {
          var left =
              await seen(doc, at, const Offset(0.05, 0.05), backgrounds: cache);
          var right =
              await seen(doc, at, const Offset(0.55, 0.05), backgrounds: cache);
          var corner = await seen(doc, at, const Offset(0.985, 0.98),
              backgrounds: cache);
          await Future.delayed(const Duration(milliseconds: 5));
          if (at < settled + 3) continue;
          expect(left, paper[3], reason: "page three's paper at $at");
          if (at < begins) expect(right, paper[4], reason: "page four at $at");
          if (at > begins + 3) {
            expect(corner, paper[6], reason: "page six, uncovered, at $at");
          }
        }
      });
    });
  });
}
