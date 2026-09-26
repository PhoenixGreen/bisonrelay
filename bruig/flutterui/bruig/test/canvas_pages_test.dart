import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
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
      expect(controller.document.frameRate, 1,
          reason: "a printed sheet has no frames to have a rate between");
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

    test("pages turn, scenes cut", () {
      expect(const CanvasDocument().defaultTransition.kind,
          SceneTransitionKind.cut);
      expect(pages(2).defaultTransition.kind, SceneTransitionKind.pageTurn);
      expect(pages(2).defaultTransition.way, SceneTransitionWay.left,
          reason: "the spine of a document that reads left to right");
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

    // The first body page is on the right on its own, as a bound document
    // opens, and then two at a time.
    test("pair as a bound document does", () {
      var doc = pages(6, covers: [PageCover.front])
          .copyWith(pages: const PagesSpec(facing: true));
      expect(doc.facingAt(0), isNull, reason: "a cover has nothing beside it");
      expect(doc.facingAt(1), isNull, reason: "page one opens alone");
      expect(doc.facingAt(2), 3);
      expect(doc.facingAt(3), 2);
      expect(doc.facingIsLeft(2), isTrue);
      expect(doc.facingIsLeft(3), isFalse);
    });

    test("and never pair with a cover", () {
      var doc = pages(4, covers: [
        PageCover.none,
        PageCover.none,
        PageCover.none,
        PageCover.back
      ]).copyWith(pages: const PagesSpec(facing: true));
      expect(doc.facingAt(1), 2);
      expect(doc.facingAt(3), isNull);
    });
  });

  // The leaf itself. Drawn rather than described: a page turn that is a
  // horizontal squash reads as a wipe, and the only way to know which one
  // this is, is to look at where the pixels end up.
  group("the page turn", () {
    /// turned is the transition drawn at [t] over a red page giving way to a
    /// blue one, as pixels.
    Future<ui.Image> turned(double t) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      var page = const Rect.fromLTWH(0, 0, 100, 100);
      paintTransition(
        canvas,
        page,
        SceneTransition.bestFor(SceneTransitionKind.pageTurn),
        t,
        from: () =>
            canvas.drawRect(page, Paint()..color = const Color(0xFFFF0000)),
        to: () =>
            canvas.drawRect(page, Paint()..color = const Color(0xFF0000FF)),
      );
      return recorder.endRecording().toImage(100, 100);
    }

    Future<bool> redderAt(ui.Image image, int x) async {
      var data = await image.toByteData();
      var at = (50 * 100 + x) * 4;
      return data!.getUint8(at) > data.getUint8(at + 2);
    }

    test("hinges on the left, so the far side goes first", () async {
      // Halfway through, the leaf covers the spine end of the page and the
      // page arriving is showing at the free end. A wipe would do the
      // opposite of nothing in particular; a squash would show this too, so
      // the third case below is the one that tells them apart.
      var half = await turned(0.5);
      expect(await redderAt(half, 5), isTrue, reason: "the leaf, by the spine");
      expect(await redderAt(half, 95), isFalse, reason: "the page beneath");
    });

    test("and is gone by the end", () async {
      var done = await turned(1);
      expect(await redderAt(done, 5), isFalse);
      expect(await redderAt(done, 95), isFalse);
    });

    test("with the whole leaf still there at the start", () async {
      var start = await turned(0);
      expect(await redderAt(start, 5), isTrue);
      expect(await redderAt(start, 95), isTrue);
    });

    test("it takes longer than a cut and points at the spine", () {
      var best = SceneTransition.bestFor(SceneTransitionKind.pageTurn);
      expect(best.frames, greaterThan(0));
      expect(best.way, SceneTransitionWay.left);
      expect(SceneTransitionWay.waysFor(SceneTransitionKind.pageTurn),
          [SceneTransitionWay.left, SceneTransitionWay.right],
          reason: "up and down are not things a page does");
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
    });
  });
}
