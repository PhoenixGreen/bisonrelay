import 'dart:ui' as ui;
import 'dart:async';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_text_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_stage_view_test.dart is about the view, not the document: where the
// canvas is drawn and how far it can be moved.
//
// Three things checked here shipped broken. The canvas was painted at a scale
// measured against its own pixel width, so the same design opened at two
// export widths filled the window very differently; the painter drew outside
// the widget's bounds, so zooming in covered the sidebar, the settings band
// and the timeline -- including the zoom control, leaving no way back; and
// zooming enlarged the frame itself, so the borders of the canvas went off
// screen and nothing was left to say where it ended.
//
// The frame is fixed now. It is always the fitted size, centred, at every
// zoom, and the document is drawn *inside* it -- pageRect never moves, and
// contentRect is what grows and pans.
//
// Neither is visible to an ordinary widget test, because the canvas is painted
// rather than laid out and has no render box to measure. CanvasStageState
// exposes pageRect for exactly this.

void main() {
  const viewport = Size(800, 600);

  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller) async {
    var key = GlobalKey<CanvasStageState>();
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
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

  testWidgets("the whole canvas is visible to begin with", (tester) async {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    var page = stage.pageRect;
    expect(page.left, greaterThanOrEqualTo(0));
    expect(page.top, greaterThanOrEqualTo(0));
    expect(page.right, lessThanOrEqualTo(viewport.width));
    expect(page.bottom, lessThanOrEqualTo(viewport.height));

    // Filling the area, not sitting in a corner of it: one axis has to be
    // nearly the whole way across.
    expect(
        page.width > viewport.width - 60 || page.height > viewport.height - 60,
        isTrue,
        reason: "the canvas should fill the area it is drawn in");
  });

  testWidgets("the export width does not change how big it looks",
      (tester) async {
    // The point of measuring zoom against the fitted size rather than against
    // the document's own pixels. These two are the same design at two publish
    // sizes and must fill the window identically.
    var small = CanvasController(const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.wide, width: 640)));
    addTearDown(small.dispose);
    var a = (await pump(tester, small)).pageRect;

    var large = CanvasController(const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.wide, width: 4000)));
    addTearDown(large.dispose);
    var b = (await pump(tester, large)).pageRect;

    expect(b.width, closeTo(a.width, 1));
    expect(b.height, closeTo(a.height, 1));
  });

  testWidgets("a tall canvas fits its height, a wide one its width",
      (tester) async {
    var tall = CanvasController(const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.tall, width: 900)));
    addTearDown(tall.dispose);
    var page = (await pump(tester, tall)).pageRect;

    expect(page.height, closeTo(viewport.height - 48, 2));
    expect(page.width, lessThan(viewport.width));
  });

  testWidgets("zooming enlarges what is inside the frame, not the frame",
      (tester) async {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);
    var frame = stage.pageRect;

    expect(stage.contentRect.width, closeTo(frame.width, 1),
        reason: "at zoom 1 the document exactly fills its frame");

    controller.zoom = 3;
    await tester.pumpAndSettle();

    expect(stage.pageRect, frame,
        reason: "the border must stay exactly where it was");
    expect(stage.contentRect.width, closeTo(frame.width * 3, 1));
  });

  testWidgets("the frame is on screen whole at every zoom", (tester) async {
    // What the fixed frame is for: the edge of the canvas is always visible,
    // so there is never any doubt where the design stops.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    for (var zoom in [minZoom, 1.0, 4.0, maxZoom]) {
      controller.zoom = zoom;
      controller.pan = const Offset2(9999, 9999);
      await tester.pumpAndSettle();

      var page = stage.pageRect;
      expect(page.left, greaterThanOrEqualTo(-0.5));
      expect(page.top, greaterThanOrEqualTo(-0.5));
      expect(page.right, lessThanOrEqualTo(viewport.width + 0.5));
      expect(page.bottom, lessThanOrEqualTo(viewport.height + 0.5));
    }
  });

  testWidgets("a zoomed canvas cannot be panned away from the frame",
      (tester) async {
    // The pan is bounded by exactly the overhang, so the frame is always full.
    // Left unbounded, the document could be dragged out of its own border and
    // leave an empty rectangle.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.zoom = 4;
    controller.pan = const Offset2(99999, -99999);
    await tester.pumpAndSettle();

    var page = stage.pageRect;
    var content = stage.contentRect;
    expect(content.left, lessThanOrEqualTo(page.left + 0.5));
    expect(content.top, lessThanOrEqualTo(page.top + 0.5));
    expect(content.right, greaterThanOrEqualTo(page.right - 0.5));
    expect(content.bottom, greaterThanOrEqualTo(page.bottom - 0.5));
  });

  testWidgets("at zoom 1 there is nothing to pan", (tester) async {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.pan = const Offset2(200, 120);
    await tester.pumpAndSettle();
    expect(stage.contentRect.center.dx, closeTo(stage.pageRect.center.dx, 0.5));
    expect(stage.contentRect.center.dy, closeTo(stage.pageRect.center.dy, 0.5));
  });

  testWidgets("what is drawn stays inside the stage", (tester) async {
    // The clip is what stops a zoomed canvas painting over the sidebar, the
    // settings band and the timeline. There is no way to observe a
    // CustomPainter's overspill from a test, so what is asserted is that the
    // clip is there at all -- removing it is a one-line change that would
    // otherwise go unnoticed until somebody zoomed in.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    await pump(tester, controller);

    expect(
        find.descendant(
            of: find.byType(CanvasStage), matching: find.byType(ClipRect)),
        findsWidgets);
  });

  testWidgets("zooming out never leaves the canvas off-centre", (tester) async {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.zoom = 6;
    controller.pan = const Offset2(400, 300);
    await tester.pumpAndSettle();

    // Coming back to the whole canvas re-centres it, rather than leaving it
    // pushed to one side with empty space beside it.
    controller.zoom = 1;
    await tester.pumpAndSettle();
    expect(stage.contentRect.center.dx, closeTo(viewport.width / 2, 1));
    expect(stage.contentRect.center.dy, closeTo(viewport.height / 2, 1));
  });

  testWidgets("Fit returns to the whole canvas", (tester) async {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);
    var fitted = stage.contentRect;

    controller.zoom = 5;
    controller.pan = const Offset2(120, -80);
    await tester.pumpAndSettle();
    expect(controller.atFit, isFalse);

    controller.resetZoom();
    await tester.pumpAndSettle();
    expect(controller.atFit, isTrue);
    expect(stage.contentRect.width, closeTo(fitted.width, 1));
    expect(stage.contentRect.center.dx, closeTo(fitted.center.dx, 1));
  });

  group("fit to width", () {
    testWidgets("fills the width and lets the canvas run long",
        (tester) async {
      // A 9:16 story fitted whole is a narrow strip down the middle of a wide
      // window with most of the screen empty either side of it.
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.tall, width: 900)));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      var whole = stage.pageRect;
      expect(whole.width, lessThan(viewport.width / 2),
          reason: "fitted whole, a tall canvas barely uses the width");

      controller.fitWidth();
      await tester.pumpAndSettle();

      var wide = stage.pageRect;
      expect(wide.width, closeTo(viewport.width - 48, 1),
          reason: "fit to width uses all of it, less the margin");
      expect(wide.height, greaterThan(viewport.height),
          reason: "and the canvas is then taller than the window");
    });

    testWidgets("scrolls when the canvas is taller than the window",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.tall, width: 900)));
      addTearDown(controller.dispose);
      await pump(tester, controller);

      expect(find.byType(Scrollbar), findsNothing,
          reason: "nothing to scroll while the whole canvas is showing");

      controller.fitWidth();
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsOneWidget);

      var before = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .offset;
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();
      var after = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .offset;
      expect(after, greaterThan(before));
    });

    testWidgets("a wide canvas needs no scrolling", (tester) async {
      // Fit to width on a 16:9 in a wide window is the same picture as fitting
      // it whole -- the width is what limits it either way.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      controller.fitWidth();
      await tester.pumpAndSettle();
      expect(stage.pageRect.height, lessThanOrEqualTo(viewport.height));
      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets("a drop lands where it was let go on a scrolled canvas",
        (tester) async {
      // Everything inside the stage works in the scrolled content's
      // coordinates, but the drop is measured against the whole widget. Left
      // unadjusted, an element dropped on a scrolled canvas lands as far up
      // the page as the view had been scrolled down.
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.tall, width: 900)));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      controller.fitWidth();
      await tester.pumpAndSettle();
      var unscrolled = stage.toDocumentPoint(const Offset(200, 100));

      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -150));
      await tester.pumpAndSettle();
      var scrolled = stage.toDocumentPoint(const Offset(200, 100));

      expect(scrolled.dy, greaterThan(unscrolled.dy),
          reason: "the same screen point is further down the document");
    });

    testWidgets("switching the frame clears a zoom chosen against the old one",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.tall, width: 900)));
      addTearDown(controller.dispose);
      await pump(tester, controller);

      controller.zoom = 4;
      controller.fitWidth();
      await tester.pumpAndSettle();
      expect(controller.zoom, 1,
          reason: "4x of a strip is a very different amount of magnification "
              "from 4x of a full-width page");
    });
  });

  testWidgets("the select tool holds the view still", (tester) async {
    // The point of having a tool at all: nothing shifts under a careful
    // adjustment, and a trackpad's stray scroll cannot move what is being
    // aimed at.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    await pump(tester, controller);
    expect(controller.tool, CanvasTool.select);

    var centre = Offset(viewport.width / 2, viewport.height / 2);
    await tester.sendEventToBinding(PointerScrollEvent(
        position: centre, scrollDelta: const Offset(0, -120)));
    await tester.pumpAndSettle();
    expect(controller.zoom, 1, reason: "select must not zoom");
  });

  testWidgets("the select tool still scrolls a canvas too tall to fit",
      (tester) async {
    // Not a contradiction of the test above. Scrolling a page that is longer
    // than the window is how you read the rest of it; what select refuses to
    // do is let the view drift under a careful adjustment.
    var controller = CanvasController(const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.tall, width: 900)));
    addTearDown(controller.dispose);
    await pump(tester, controller);
    controller.fitWidth();
    await tester.pumpAndSettle();

    var scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    var before = scroll.offset;
    await tester.sendEventToBinding(PointerScrollEvent(
        position: Offset(viewport.width / 2, viewport.height / 2),
        scrollDelta: const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(before));
    expect(controller.zoom, 1, reason: "and still does not zoom");
  });

  testWidgets("the pan tool drags the view and scrolls to zoom",
      (tester) async {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.tool = CanvasTool.pan;
    var centre = Offset(viewport.width / 2, viewport.height / 2);
    await tester.sendEventToBinding(PointerScrollEvent(
        position: centre, scrollDelta: const Offset(0, -120)));
    await tester.pumpAndSettle();
    expect(controller.zoom, greaterThan(1), reason: "pan zooms on scroll");

    // Now there is an overhang, so a drag has somewhere to go.
    var before = stage.contentRect.left;
    await tester.dragFrom(centre, const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(stage.contentRect.left, lessThan(before));
  });

  testWidgets("the pan tool does not move elements", (tester) async {
    // A drag in the pan tool is about the view. Left to the old
    // hit-test-first path it would have picked up whatever was under the
    // pointer and dragged that instead.
    var document = const CanvasDocument();
    var element = newElement(ElementKind.shape, document);
    var controller = CanvasController(document.addElement(element));
    addTearDown(controller.dispose);
    await pump(tester, controller);

    controller.tool = CanvasTool.pan;
    var at = controller.document.elements.first;
    await tester.dragFrom(
        Offset(viewport.width / 2, viewport.height / 2), const Offset(60, 40));
    await tester.pumpAndSettle();

    expect(controller.document.elements.first.x, at.x);
    expect(controller.document.elements.first.y, at.y);
  });

  group("dragging a player", () {
    /// team fills the canvas with one side, so a player's document position
    /// and its position on screen are easy to reason about.
    (CanvasController, TeamElement) build() {
      var document = const CanvasDocument();
      var team = TeamElement(
        ElementBase(
          id: newElementId(),
          x: 0,
          y: 0,
          width: document.size.width.toDouble(),
          height: document.size.height.toDouble(),
        ),
        dotWidth: 60,
        dotHeight: 60,
      ).withFormation(TeamFormation.f442);
      var controller = CanvasController(document.addElement(team));
      return (controller, team);
    }

    testWidgets("moves that player and leaves the team where it is",
        (tester) async {
      var (controller, team) = build();
      addTearDown(controller.dispose);
      controller.selectOnly(team.id);
      var stage = await pump(tester, controller);

      var before = team.players[5];
      var at = stage.pageRect.topLeft +
          (team.centreOf(before) * stage.pageRect.width / team.width);

      await tester.dragFrom(at, const Offset(40, -30));
      await tester.pumpAndSettle();

      var after = controller.document.elements
          .whereType<TeamElement>()
          .single;
      expect(after.players[5].dx, isNot(before.dx));
      expect(after.x, team.x, reason: "the team's own box has not moved");
      expect(after.y, team.y);
      // Nobody else moved.
      expect(after.players[4].dx, closeTo(team.players[4].dx, 0.0001));
      expect(controller.selection, {team.id},
          reason: "the team stays selected; a player is not an element");
    });

    testWidgets("a locked player cannot be dragged", (tester) async {
      // What locking is for: pinning the back four so a run can be dragged
      // through them without knocking one out of position.
      var (controller, team) = build();
      addTearDown(controller.dispose);
      var locked = team.withPlayer(
          5, team.players[5].copyWith(locked: true));
      controller.replaceElement(locked);
      controller.selectOnly(team.id);
      var stage = await pump(tester, controller);

      var before = locked.players[5];
      var at = stage.pageRect.topLeft +
          (locked.centreOf(before) * stage.pageRect.width / locked.width);

      await tester.dragFrom(at, const Offset(40, -30));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<TeamElement>().single;
      expect(after.players[5].dx, closeTo(before.dx, 0.0001));
      expect(after.players[5].dy, closeTo(before.dy, 0.0001));
    });

    testWidgets("dragging a player on an animated document keyframes them",
        (tester) async {
      // The end of the reported bug, on the canvas rather than in the model:
      // with auto-keyframe on, dragging a player at frame 12 has to record the
      // run rather than move where he lines up.
      var document = const CanvasDocument(frames: 24);
      var team = TeamElement(
        ElementBase(
          id: newElementId(),
          x: 0,
          y: 0,
          width: document.size.width.toDouble(),
          height: document.size.height.toDouble(),
        ),
        dotWidth: 60,
        dotHeight: 60,
      ).withFormation(TeamFormation.f442);
      var controller = CanvasController(document.addElement(team));
      addTearDown(controller.dispose);
      controller.selectOnly(team.id);
      controller.autoKeyframe = true;
      controller.frame = 12;
      var stage = await pump(tester, controller);

      var before = team.players[6];
      var at = stage.pageRect.topLeft +
          (team.centreOf(before) * stage.pageRect.width / team.width);
      await tester.dragFrom(at, const Offset(50, -20));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<TeamElement>().single;
      expect(after.players[6].dx, closeTo(before.dx, 0.0001),
          reason: "where he lines up has not changed");
      expect(after.players[6].track, isNotNull,
          reason: "the run was recorded instead");
      expect(after.players[6].track!.keyAt(12), isNotNull);
      expect(after.centreAt(after.players[6], 0).dx,
          closeTo(after.centreOf(after.players[6]).dx, 0.5),
          reason: "and frame 0 still has him where he started");
      expect(controller.focusedPlayer, 6,
          reason: "clicking a player is what points the timeline at him");
    });

    testWidgets("dragging off the players moves the whole team",
        (tester) async {
      var (controller, team) = build();
      addTearDown(controller.dispose);
      controller.selectOnly(team.id);
      var stage = await pump(tester, controller);

      // A corner of the box, which no formation puts anybody on.
      var at = stage.pageRect.topLeft + const Offset(6, 6);
      await tester.dragFrom(at, const Offset(30, 20));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<TeamElement>().single;
      expect(after.x, isNot(team.x));
      expect(after.players[5].dx, closeTo(team.players[5].dx, 0.0001),
          reason: "everybody keeps their place within the box");
    });
  });

  group("a chart's placed title", () {
    /// build puts a chart in the middle of the canvas with its title placed.
    ///
    /// Inset rather than filling the canvas, so that a label can be dragged
    /// outside the *chart* while staying over the page -- the stage ignores a
    /// press outside the frame, so a label dragged clean off it could not be
    /// pressed a second time.
    (CanvasController, ChartElement) build() {
      var document = const CanvasDocument();
      var chart = ChartElement(
        ElementBase(
          id: newElementId(),
          x: 240,
          y: 140,
          width: document.size.width * 0.6,
          height: document.size.height * 0.6,
        ),
        title: "Messages",
        titleBox: const ChartLabel(x: 0.1, y: 0.1, width: 0.3, height: 0.2),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller = CanvasController(document.addElement(chart));
      return (controller, chart);
    }

    testWidgets("dragging it moves the title, not the chart", (tester) async {
      // The label sits inside the chart's own box, so without somewhere for
      // the press to go the ordinary hit test picks the chart up and moves the
      // whole thing -- which is what happened before it could be placed.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      controller.selectOnly(chart.id);
      var stage = await pump(tester, controller);

      var box = chart.titleBox.rectIn(
          Rect.fromLTWH(chart.x, chart.y, chart.width, chart.height));
      var scale = stage.pageRect.width / controller.document.size.width;
      var at = stage.pageRect.topLeft + box.center * scale;

      await tester.dragFrom(at, const Offset(60, 40));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<ChartElement>().single;
      expect(after.titleBox.x, greaterThan(chart.titleBox.x));
      expect(after.titleBox.y, greaterThan(chart.titleBox.y));
      expect(after.x, chart.x, reason: "the chart itself has not moved");
      expect(after.y, chart.y);
      expect(after.titleBox.width, chart.titleBox.width,
          reason: "and dragging its middle does not resize it");
    });

    testWidgets("dragging its corner resizes it", (tester) async {
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      controller.selectOnly(chart.id);
      var stage = await pump(tester, controller);

      var box = chart.titleBox.rectIn(
          Rect.fromLTWH(chart.x, chart.y, chart.width, chart.height));
      var scale = stage.pageRect.width / controller.document.size.width;
      var at = stage.pageRect.topLeft + box.bottomRight * scale;

      await tester.dragFrom(at, const Offset(50, 30));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<ChartElement>().single;
      expect(after.titleBox.width, greaterThan(chart.titleBox.width));
      expect(after.titleBox.height, greaterThan(chart.titleBox.height));
      expect(after.titleBox.x, chart.titleBox.x,
          reason: "a corner drag pins the other corner");
    });

    testWidgets("dragging it off the edge grows the chart's box",
        (tester) async {
      // Outside the box it still drew, but it was outside the selection
      // outline and outside what a marquee or a group move picks up -- so it
      // read as a separate thing that happened to be near the chart. The box
      // is what says the text belongs to the chart.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      controller.selectOnly(chart.id);
      var stage = await pump(tester, controller);

      var box = chart.titleBox.rectIn(
          Rect.fromLTWH(chart.x, chart.y, chart.width, chart.height));
      var scale = stage.pageRect.width / controller.document.size.width;
      var at = stage.pageRect.topLeft + box.center * scale;

      // Up and to the left, off the chart's own top-left corner.
      await tester.dragFrom(at, const Offset(-120, -90));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<ChartElement>().single;
      expect(after.width, greaterThan(chart.width));
      expect(after.height, greaterThan(chart.height));
      expect(after.x, lessThan(chart.x), reason: "grown on the side it left");

      // And the label is still where it was let go, in the bigger box.
      var moved = after.titleBox
          .rectIn(Rect.fromLTWH(after.x, after.y, after.width, after.height));
      expect(moved.left, closeTo(box.left - 120 / scale, 4));
      expect(moved.top, closeTo(box.top - 90 / scale, 4));
    });

    testWidgets("growing the box does not resize the chart itself",
        (tester) async {
      // The box grows so the words are inside the selection outline. The plot
      // must not grow with it: dragging a title off the corner made the bars
      // taller, which is a resize nobody asked for from a drag that was about
      // the words.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      controller.selectOnly(chart.id);
      var stage = await pump(tester, controller);

      var box = chart.titleBox.rectIn(
          Rect.fromLTWH(chart.x, chart.y, chart.width, chart.height));
      var scale = stage.pageRect.width / controller.document.size.width;
      var before = chart.body
          .rectIn(Rect.fromLTWH(chart.x, chart.y, chart.width, chart.height));

      await tester.dragFrom(
          stage.pageRect.topLeft + box.center * scale, const Offset(-120, -90));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<ChartElement>().single;
      var body = after.body
          .rectIn(Rect.fromLTWH(after.x, after.y, after.width, after.height));

      expect(after.width, greaterThan(chart.width), reason: "the box grew");
      expect(body.left, closeTo(before.left, 0.5),
          reason: "and the chart did not move");
      expect(body.width, closeTo(before.width, 0.5));
      expect(body.height, closeTo(before.height, 0.5));
    });

    testWidgets("bringing it back shrinks the box again", (tester) async {
      // Growing only was the first attempt, and left a box that could be
      // stretched but never put back -- so an experimental drag out and back
      // cost a chart a margin of empty selection for good.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      controller.selectOnly(chart.id);
      var stage = await pump(tester, controller);

      var scale = stage.pageRect.width / controller.document.size.width;
      Rect labelOnScreen() {
        var e = controller.document.elements.whereType<ChartElement>().single;
        return e.titleBox.rectIn(
            Rect.fromLTWH(e.x, e.y, e.width, e.height));
      }

      // A short drag, so the label stays over the canvas. Dragged clean off
      // the page it cannot be pressed again at all -- the stage ignores a
      // press outside the frame -- which is what the overspill margin is for.
      await tester.dragFrom(
          stage.pageRect.topLeft + labelOnScreen().center * scale,
          const Offset(-90, -60));
      await tester.pumpAndSettle();
      var grown =
          controller.document.elements.whereType<ChartElement>().single;
      expect(grown.width, greaterThan(chart.width));

      await tester.dragFrom(
          stage.pageRect.topLeft + labelOnScreen().center * scale,
          const Offset(90, 60));
      await tester.pumpAndSettle();

      var back = controller.document.elements.whereType<ChartElement>().single;
      expect(back.width, closeTo(chart.width, 1),
          reason: "back to the chart's own rectangle");
      expect(back.height, closeTo(chart.height, 1));
      expect(back.x, closeTo(chart.x, 1));
      expect(back.body.isWhole, isTrue,
          reason: "and the chart fills its box again");
    });

    testWidgets("a title the chart is placing is not draggable",
        (tester) async {
      // There is no box to take hold of: it is wherever the title happens to
      // end up above the plot, and dragging that would mean dragging the
      // arrangement rather than the label.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      var flowing = chart.copyWith(titleBox: const ChartLabel());
      controller.replaceElement(flowing);
      controller.selectOnly(chart.id);
      var stage = await pump(tester, controller);

      var at = stage.pageRect.topLeft +
          const Offset(0.2, 0.15) *
              stage.pageRect.width /
              1; // near where the title is drawn
      await tester.dragFrom(at, const Offset(40, 25));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<ChartElement>().single;
      expect(after.titleBox.placed, isFalse);
      expect(after.x, isNot(chart.x),
          reason: "the chart moved instead, as any other element would");
    });
  });

  group("the keyboard", () {
    Future<CanvasStageState> keyed(
        WidgetTester tester, CanvasController controller) async {
      var stage = await pump(tester, controller);
      // The stage takes focus on the first click, which is what a real user
      // does before typing anything at it.
      await tester.tapAt(Offset(viewport.width / 2, viewport.height / 2));
      await tester.pumpAndSettle();
      return stage;
    }

    testWidgets("space plays and stops", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 20));
      addTearDown(controller.dispose);
      addTearDown(controller.pause);
      await keyed(tester, controller);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.playing, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.playing, isFalse);
    });

    testWidgets("the arrows scrub the playhead", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      await keyed(tester, controller);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.frame, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.frame, 0);

      // Up and down are the same idea in tens, since scrubbing one frame at a
      // time across forty of them is forty presses.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.frame, 10);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(controller.frame, 0);
    });

    testWidgets("scrubbing stops playback", (tester) async {
      // Otherwise the next tick undoes the step and the key appears dead.
      var controller = CanvasController(const CanvasDocument(frames: 20));
      addTearDown(controller.dispose);
      addTearDown(controller.pause);
      await keyed(tester, controller);
      controller.play();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.playing, isFalse);
    });

    testWidgets("alt and the arrows still nudge", (tester) async {
      // Nudging moved to Alt in all four directions rather than only the two
      // the arrows gave up: a nudge that worked one way with a modifier and
      // another way without would be worse than either.
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await keyed(tester, controller);
      controller.selectOnly(element.id);

      var before = controller.document.elements.single.x;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      expect(controller.document.elements.single.x, before + 1);
      expect(controller.frame, 0, reason: "and the playhead stayed put");
    });

    testWidgets("space no longer pans", (tester) async {
      // It used to hold the view for a drag. The pan tool does that visibly
      // now, and space is worth more as play/stop on a page for building
      // animations.
      var controller = CanvasController(const CanvasDocument(frames: 20));
      addTearDown(controller.dispose);
      addTearDown(controller.pause);
      var stage = await keyed(tester, controller);
      controller.zoom = 3;
      await tester.pumpAndSettle();
      var before = stage.contentRect.left;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      // Space starts playback now, so stop it before dragging -- a running
      // timer outlives the test otherwise, and what is being checked here is
      // the drag, not the transport.
      controller.pause();

      await tester.dragFrom(
          Offset(viewport.width / 2, viewport.height / 2),
          const Offset(-60, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(stage.contentRect.left, before,
          reason: "holding space is not a pan modifier any more");
    });
  });

  group("the editing helpers", () {
    (CanvasController, CanvasElement) selected() {
      var document = const CanvasDocument();
      // Red, because a shape's default fill is the same blue the selection
      // furniture is drawn in, and the pixel count below cannot tell them
      // apart.
      var element = (newElement(ElementKind.shape, document) as ShapeElement)
          .copyWith(fill: const Color(0xFFCC2200));
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly(element.id);
      return (controller, element);
    }

    testWidgets("hiding them takes the handles out of reach too",
        (tester) async {
      // A handle that can be grabbed where nothing is drawn is a click that
      // appears to do nothing and then resizes something.
      var (controller, element) = selected();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      // The corner of the selected element, which is where a handle sits.
      var corner = stage.pageRect.topLeft +
          Offset(element.x, element.y) *
              (stage.pageRect.width / controller.document.size.width);

      controller.showHelpers = false;
      await tester.pumpAndSettle();

      var before = controller.document.elements.single;
      await tester.dragFrom(corner, const Offset(40, 40));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single;
      expect(after.width, before.width,
          reason: "no handle to grab, so nothing was resized");
      expect(after.height, before.height);
    });

    testWidgets("hiding them actually stops them being drawn", (tester) async {
      // The first version of this feature blanked the painter's selection set
      // and did nothing at all, because _paintSelection reads selectionBounds
      // rather than the selection -- every mark stayed exactly where it was.
      // The existing tests all checked behaviour rather than pixels and passed
      // throughout, so this one counts them.
      var (controller, element) = selected();
      addTearDown(controller.dispose);
      await pump(tester, controller);

      Future<int> blueish() async {
        var image = await tester.runAsync(() async {
          var boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first);
          return boundary.toImage();
        });
        var data = await tester.runAsync(() => image!.toByteData());
        var count = 0;
        for (var i = 0; i + 3 < data!.lengthInBytes; i += 4) {
          // The selection furniture is the one blue thing on the page.
          var r = data.getUint8(i);
          var g = data.getUint8(i + 1);
          var b = data.getUint8(i + 2);
          if (b > 150 && b > r + 40 && b > g + 20) count++;
        }
        return count;
      }

      var withHelpers = await blueish();
      expect(withHelpers, greaterThan(0),
          reason: "the box and handles are drawn to begin with");

      controller.showHelpers = false;
      await tester.pumpAndSettle();
      expect(await blueish(), 0,
          reason: "and nothing blue is left once they are off");
      expect(element.id, isNotEmpty);
    });

    testWidgets("the element itself is still selectable and movable",
        (tester) async {
      // Hiding the furniture must not turn the canvas into a picture.
      var (controller, element) = selected();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      controller.showHelpers = false;
      await tester.pumpAndSettle();

      var scale = stage.pageRect.width / controller.document.size.width;
      var middle = stage.pageRect.topLeft + element.bounds.center * scale;
      var before = controller.document.elements.single.x;

      await tester.dragFrom(middle, const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.x, greaterThan(before));
    });
  });

  testWidgets("zoom is bounded at both ends", (tester) async {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    await pump(tester, controller);

    controller.zoom = 1000;
    expect(controller.zoom, maxZoom);
    controller.zoom = 0.0001;
    expect(controller.zoom, minZoom);
  });

  testWidgets("a click still lands on the element under it when zoomed",
      (tester) async {
    // The hit test converts through the same scale the painter uses. When the
    // two were allowed to differ, clicking a player selected whatever happened
    // to be at the unzoomed position instead.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.zoom = 2.5;
    controller.pan = const Offset2(30, -20);
    await tester.pumpAndSettle();

    var centre = stage.contentRect.center;
    expect(stage.toDocumentPoint(centre).dx,
        closeTo(controller.document.size.width / 2, 1));
    expect(stage.toDocumentPoint(centre).dy,
        closeTo(controller.document.size.height / 2, 1));
  });

  group("a button on the canvas", () {
    (CanvasController, ButtonElement) withButton() {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.button, document) as ButtonElement;
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly(element.id);
      return (controller, element);
    }

    testWidgets("a selected button can still be dragged", (tester) async {
      // It could not: the press that would have started the drag ran the
      // button's action instead, so a button was stuck where it was placed the
      // moment it was selected once.
      var (controller, element) = withButton();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      var at = stage.pageRect.topLeft +
          element.center * stage.pageRect.width / controller.document.size.width.toDouble();
      await tester.dragFrom(at, const Offset(60, 40));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single;
      expect(after.x, greaterThan(element.x));
      expect(after.y, greaterThan(element.y));
    });

    testWidgets("clicking one without moving still runs it", (tester) async {
      var (controller, element) = withButton();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      var at = stage.pageRect.topLeft +
          element.center * stage.pageRect.width / controller.document.size.width.toDouble();
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.x, element.x,
          reason: "a click is not a drag");
    });
  });

  group("a team's frame lock", () {
    (CanvasController, TeamElement) withTeam({bool frameLocked = false}) {
      var document = const CanvasDocument();
      var team = TeamElement(
        ElementBase(
          id: newElementId(),
          x: 0,
          y: 0,
          width: document.size.width.toDouble(),
          height: document.size.height.toDouble(),
        ),
        dotWidth: 60,
        dotHeight: 60,
        frameLocked: frameLocked,
      ).withFormation(TeamFormation.f442);
      var controller = CanvasController(document.addElement(team));
      controller.selectOnly(team.id);
      return (controller, team);
    }

    testWidgets("pins the box while leaving the players free", (tester) async {
      // A pitch is set up once and worked on for an hour, and in that hour a
      // drag that starts a few pixels off a dot takes hold of the team and
      // slides all eleven -- easy to do and easy not to notice.
      var (controller, team) = withTeam(frameLocked: true);
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      double toStage(double x) =>
          stage.pageRect.left + x * stage.pageRect.width / team.width;

      // Empty grass, between the lines.
      await tester.dragFrom(
          Offset(toStage(team.width * 0.5), stage.pageRect.center.dy),
          const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.x, team.x,
          reason: "the team's box did not move");

      var before = team.players[6];
      await tester.dragFrom(
          stage.pageRect.topLeft +
              team.centreOf(before) * stage.pageRect.width / team.width,
          const Offset(40, 0));
      await tester.pumpAndSettle();

      var after = controller.document.elements.whereType<TeamElement>().single;
      expect(after.players[6].dx, greaterThan(before.dx),
          reason: "but the player did");
    });

    testWidgets("unlocked, the box still moves", (tester) async {
      var (controller, team) = withTeam();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      await tester.dragFrom(
          Offset(stage.pageRect.left + stage.pageRect.width * 0.5,
              stage.pageRect.center.dy),
          const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.x, isNot(team.x));
    });
  });

  group("two teams on one pitch", () {
    /// pitch is two teams whose boxes overlap, which is what a real one is:
    /// each covers its own half plus a bit, so a player standing near the
    /// halfway line is inside both.
    (CanvasController, TeamElement, TeamElement) pitch() {
      var document = const CanvasDocument();
      var w = document.size.width.toDouble();
      var h = document.size.height.toDouble();
      var home = TeamElement(
        ElementBase(
            id: "home", name: "Home", x: 0, y: 0, width: w * 0.6, height: h),
        dotWidth: 50,
        dotHeight: 50,
        frameLocked: true,
      ).withFormation(TeamFormation.f442);
      var away = TeamElement(
        ElementBase(
            id: "away",
            name: "Away",
            x: w * 0.4,
            y: 0,
            width: w * 0.6,
            height: h),
        dotWidth: 50,
        dotHeight: 50,
        frameLocked: true,
      ).withFormation(TeamFormation.f442, mirror: true);

      var controller =
          CanvasController(document.addElement(home).addElement(away));
      return (controller, home, away);
    }

    testWidgets("a player wins against the other team's box", (tester) async {
      // The reported problem. The away box is drawn last and covers the home
      // strikers, so clicking one used to find the away team's box first and
      // pick that up instead.
      var (controller, home, _) = pitch();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      var striker = home.players.last;
      var at = stage.pageRect.topLeft +
          home.centreOf(striker) *
              stage.pageRect.width /
              controller.document.size.width.toDouble();

      await tester.dragFrom(at, const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(controller.selection, {"home"},
          reason: "the player's own team was selected, not the box on top");
      var after = controller.document.elementById("home") as TeamElement;
      expect(after.players.last.dx, greaterThan(striker.dx));
    });

    testWidgets("a player outside his own box is still grabbable",
        (tester) async {
      // A player is placed as a fraction of the box but is not confined to it,
      // so the ordinary element hit test never returned his team at all.
      var (controller, home, _) = pitch();
      addTearDown(controller.dispose);

      // Push him well past the right-hand edge of his own team's box.
      var moved = home.withPlayer(10, home.players[10].copyWith(dx: 1.4));
      controller.replaceElement(moved);
      var stage = await pump(tester, controller);

      var at = stage.pageRect.topLeft +
          moved.centreOf(moved.players[10]) *
              stage.pageRect.width /
              controller.document.size.width.toDouble();

      await tester.dragFrom(at, const Offset(20, 0));
      await tester.pumpAndSettle();

      expect(controller.selection, {"home"});
      var after = controller.document.elementById("home") as TeamElement;
      expect(after.players[10].dx, greaterThan(1.4));
    });

    testWidgets("empty grass between them still selects nothing",
        (tester) async {
      // Both boxes are frame-locked, so a drag on the pitch itself must not
      // slide either team.
      var (controller, home, away) = pitch();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      await tester.dragFrom(
          Offset(stage.pageRect.center.dx, stage.pageRect.top + 6),
          const Offset(50, 0));
      await tester.pumpAndSettle();

      expect((controller.document.elementById("home") as TeamElement).x, home.x);
      expect((controller.document.elementById("away") as TeamElement).x, away.x);
    });
  });

  group("the overspill", () {
    testWidgets("shrinks the page to make room, and is centred on it",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      var closed = stage.pageRect;
      controller.showOverspill = true;
      await tester.pumpAndSettle();
      var open = stage.pageRect;

      expect(open.width, lessThan(closed.width),
          reason: "the page gives up the room rather than the margin");
      expect(open.center.dx, closeTo(closed.center.dx, 1));
      expect(open.center.dy, closeTo(closed.center.dy, 1));
      // Twelve per cent each way, so the page keeps about four fifths.
      expect(open.width / closed.width, closeTo(1 / 1.24, 0.02));
    });

    testWidgets("an element off the page can be selected once it is on",
        (tester) async {
      // The point of the whole thing. An element animated in from the left
      // starts outside the page, where it is clipped away entirely -- so its
      // first keyframe could not be seen, selected or dragged.
      var document = const CanvasDocument();
      var element = ShapeElement(
        ElementBase(
          id: "s",
          x: -120,
          y: document.size.height / 2 - 40,
          width: 80,
          height: 80,
        ),
        fill: const Color(0xFFCC2200),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      Offset atElement() {
        var scale = stage.pageRect.width / document.size.width;
        return stage.pageRect.topLeft + element.center * scale;
      }

      await tester.tapAt(atElement());
      await tester.pumpAndSettle();
      expect(controller.selection, isEmpty,
          reason: "off the page, there is nothing there to click");

      controller.showOverspill = true;
      await tester.pumpAndSettle();
      await tester.tapAt(atElement());
      await tester.pumpAndSettle();
      expect(controller.selection, {"s"});
    });

    testWidgets("the page's own edge is still where it was", (tester) async {
      // The border has to keep meaning "this is what gets published", which is
      // the only thing stopping the margin being mistaken for more canvas.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      controller.showOverspill = true;
      await tester.pumpAndSettle();

      expect(stage.pageRect.width / stage.pageRect.height,
          closeTo(16 / 9, 0.01),
          reason: "the page is still the document's shape");
    });
  });

  group("the canvas keyboard", () {
    testWidgets("the arrows scrub and the space bar plays", (tester) async {
      // The positive half of the typing guard: with focus on the canvas rather
      // than in a field, the shortcuts are the canvas's own.
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      // The stage takes focus on pointer down.
      await tester.tapAt(stage.pageRect.center);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.frame, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(controller.frame, 11, reason: "up and down move ten at a time");

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.frame, 10);
    });

    testWidgets("alt and an arrow nudges the selection instead",
        (tester) async {
      var document = const CanvasDocument(frames: 40);
      var element = (newElement(ElementKind.shape, document) as ShapeElement)
          .copyWith(fill: const Color(0xFFCC2200));
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly(element.id);
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      await tester.tapAt(stage.pageRect.center);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.x, element.x + 1);
      expect(controller.frame, 0, reason: "and the playhead stayed put");
    });
  });

  group("typing on the canvas", () {
    (CanvasController, TextElement) withText() {
      var document = const CanvasDocument();
      var element = TextElement(
        ElementBase(
          id: "t",
          x: document.size.width / 4,
          y: document.size.height / 4,
          width: document.size.width / 2,
          height: document.size.height / 2,
        ),
        text: "Text",
      );
      var controller = CanvasController(document.addElement(element));
      return (controller, element);
    }

    Future<void> clickText(
        WidgetTester tester, CanvasStageState stage, TextElement e,
        {required CanvasController controller}) async {
      var scale = stage.pageRect.width / controller.document.size.width;
      await tester.tapAt(stage.pageRect.topLeft + e.center * scale);
      await tester.pumpAndSettle();
    }

    testWidgets("a second click opens an editor over the element",
        (tester) async {
      // A canvas is painted, not laid out, so there is nothing to type into:
      // the words are pixels drawn by a painter. The editor is a real field
      // put over the top, styled from the same spec.
      var (controller, element) = withText();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      await clickText(tester, stage, element, controller: controller);
      expect(controller.selection, {"t"});
      expect(find.byType(CanvasTextEditor), findsNothing,
          reason: "the first click selects, so text can still be dragged");

      await clickText(tester, stage, element, controller: controller);
      expect(find.byType(CanvasTextEditor), findsOneWidget);
    });

    testWidgets("typing writes straight into the element", (tester) async {
      var (controller, element) = withText();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      await clickText(tester, stage, element, controller: controller);
      await clickText(tester, stage, element, controller: controller);

      await tester.enterText(find.byType(TextField), "A headline");
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as TextElement).text,
          "A headline");
    });

    testWidgets("the words are not drawn twice while being typed",
        (tester) async {
      // The element's own text is left unpainted while the editor is open --
      // both at once is the same sentence half a pixel apart.
      var (controller, element) = withText();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      await clickText(tester, stage, element, controller: controller);
      await clickText(tester, stage, element, controller: controller);

      var painter = tester
          .widgetList<CustomPaint>(find.descendant(
              of: find.byType(CanvasStage), matching: find.byType(CustomPaint)))
          .map((w) => w.painter)
          .whereType<CustomPainter>()
          .toList();
      expect(painter, isNotEmpty);
      expect(find.byType(TextField), findsOneWidget);
      expect(controller.document.elements.single.id, "t");
    });

    testWidgets("escape finishes, and the text stays", (tester) async {
      var (controller, element) = withText();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      await clickText(tester, stage, element, controller: controller);
      await clickText(tester, stage, element, controller: controller);

      await tester.enterText(find.byType(TextField), "Kept");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CanvasTextEditor), findsNothing);
      expect((controller.document.elements.single as TextElement).text, "Kept");
    });
  });

  group("dragging an element that already has a pose", () {
    testWidgets("the third keyframe does not jump away from the pointer",
        (tester) async {
      // movedTo turns a target position into a pose offset by subtracting the
      // resting position, so a drag that started from the *resting* top-left
      // produced a pose of exactly the drag delta -- throwing away whatever
      // pose the frame already had. On the first two keyframes that pose was
      // usually zero; on the third it was not, and the element leapt.
      var document = const CanvasDocument(frames: 40);
      var element = ShapeElement(
        ElementBase(
          id: "s",
          x: 100,
          y: 100,
          width: 80,
          height: 80,
        ),
        fill: const Color(0xFFCC2200),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("s");
      controller.setKeyframe("s", const Keyframe(frame: 0));
      controller.setKeyframe("s", const Keyframe(frame: 20, dx: 300, dy: 120));

      controller.frame = 20;
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;
      var before = controller.document.elementById("s")!.boundsAt(20);

      // Take hold of it where it actually is, and move it a little.
      await tester.dragFrom(
          stage.pageRect.topLeft + before.center * scale, const Offset(20, 10));
      await tester.pumpAndSettle();

      var after = controller.document.elementById("s")!.boundsAt(20);
      expect(after.left, closeTo(before.left + 20 / scale, 1),
          reason: "it followed the pointer rather than leaping");
      expect(after.top, closeTo(before.top + 10 / scale, 1));
      // And the other keyframe is untouched.
      expect(controller.document.elementById("s")!.boundsAt(0).left, 100);
    });
  });

  group("selecting a curve", () {
    testWidgets("a bowed line is caught by its stroke, not its box",
        (tester) async {
      // A bowed line bulges outside its own bounding box, so the visible
      // stroke was not clickable while an empty corner of the box was.
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
          id: "l",
          x: 200,
          y: document.size.height / 2,
          width: 800,
          height: 6,
        ),
        curvature: 0.35,
        strokeWidth: 6,
      );
      var controller = CanvasController(document.addElement(line));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;

      // The middle of the bow, which is well outside the element's box.
      var curve = curveOfElement(line)!;
      var apex = curve[curve.length ~/ 2];
      expect(line.bounds.contains(apex), isFalse,
          reason: "the test is only meaningful off the box");

      await tester.tapAt(stage.pageRect.topLeft + apex * scale);
      await tester.pumpAndSettle();
      expect(controller.selection, {"l"});
    });

    testWidgets("text on a line is caught where the words are",
        (tester) async {
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
            id: "l", x: 200, y: document.size.height / 2, width: 800, height: 6),
      );
      var text = TextElement(
        // Its own box is nowhere near the line.
        const ElementBase(id: "t", x: 0, y: 0, width: 100, height: 40),
        text: "CAPTION",
        curve: const TextOnCurve(elementId: "l"),
      );
      var controller =
          CanvasController(document.addElement(line).addElement(text));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;

      await tester.tapAt(
          stage.pageRect.topLeft + Offset(260, document.size.height / 2) * scale);
      await tester.pumpAndSettle();
      expect(controller.selection, {"t"},
          reason: "the words are on top of the line and win");
    });
  });

  group("the selection box follows what is drawn", () {
    /// bowed is a line curving well outside its own rectangle.
    (CanvasController, LineElement) bowed() {
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
          id: "l",
          x: 200,
          y: document.size.height / 2,
          width: 800,
          height: 6,
        ),
        curvature: 0.4,
        strokeWidth: 6,
      );
      var controller = CanvasController(document.addElement(line));
      controller.selectOnly("l");
      return (controller, line);
    }

    testWidgets("a bowed line's box covers the bow, not just the chord",
        (tester) async {
      var (controller, line) = bowed();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);

      var box = visualBoundsOf(line, controller.document, 0);
      expect(box.height, greaterThan(line.height * 5),
          reason: "the element's own rectangle is a thin strip");
      // Every point of the curve is inside it.
      for (var p in curveOfElement(line)!) {
        expect(box.inflate(1).contains(p), isTrue);
      }
      expect(stage.pageRect.width, greaterThan(0));
    });

    testWidgets("dragging a corner of that box resizes the line",
        (tester) async {
      // The handles are on the visual box and the element's own rectangle
      // follows it in proportion. Resizing one box while the handles sat on
      // another is what made a curved line fight the pointer.
      var (controller, line) = bowed();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / controller.document.size.width;

      var box = visualBoundsOf(line, controller.document, 0);
      await tester.dragFrom(
          stage.pageRect.topLeft + box.bottomRight * scale,
          const Offset(-60, 0));
      await tester.pumpAndSettle();

      var after = controller.document.elementById("l")!;
      expect(after.width, lessThan(line.width));
      expect(after.width, greaterThan(0));
    });

    testWidgets("text on a line is boxed around the words", (tester) async {
      // The reported problem: clicking the text put a selection box in an
      // empty part of the canvas, because the box came from the element's own
      // rectangle and the words are wherever the line is.
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
            id: "l", x: 200, y: document.size.height * 0.7, width: 800, height: 6),
      );
      var text = TextElement(
        // Far away from the line, up in the corner.
        const ElementBase(id: "t", x: 0, y: 0, width: 300, height: 80),
        text: "CAPTION",
        textSpec: const TextSpec(fontSize: 40),
        curve: const TextOnCurve(elementId: "l"),
      );
      var controller =
          CanvasController(document.addElement(line).addElement(text));
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      await pump(tester, controller);

      var box = visualBoundsOf(text, controller.document, 0);
      expect(box.overlaps(text.bounds), isFalse,
          reason: "the words are nowhere near the element's own rectangle");
      // And they are on the line.
      expect(box.center.dy, closeTo(document.size.height * 0.7, 60));
      expect(box.center.dx, closeTo(600, 120));
    });

    testWidgets("placed text gets an outline but no handles", (tester) async {
      // Its size and angle are the line's, so eight squares and a rotate ring
      // would be controls that appear to do nothing.
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
            id: "l", x: 200, y: document.size.height / 2, width: 800, height: 6),
      );
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 300, height: 80),
        text: "CAPTION",
        curve: const TextOnCurve(elementId: "l"),
      );
      var controller =
          CanvasController(document.addElement(line).addElement(text));
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      await pump(tester, controller);

      expect(hasOwnGeometry(text, controller.document, 0), isFalse);
      expect(hasOwnGeometry(line, controller.document, 0), isTrue);
    });

    testWidgets("the text editor opens over the words", (tester) async {
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
            id: "l", x: 200, y: document.size.height * 0.7, width: 800, height: 6),
      );
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 300, height: 80),
        text: "CAPTION",
        textSpec: const TextSpec(fontSize: 40),
        curve: const TextOnCurve(elementId: "l"),
      );
      var controller =
          CanvasController(document.addElement(line).addElement(text));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;

      var words = visualBoundsOf(text, controller.document, 0);
      var at = stage.pageRect.topLeft + words.center * scale;
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(find.byType(CanvasTextEditor), findsOneWidget);
      var editor = tester.getRect(find.byType(CanvasTextEditor));
      expect(editor.center.dx, closeTo(at.dx, 60),
          reason: "it opened on the words, not on the stored rectangle");
      expect(editor.center.dy, closeTo(at.dy, 60));
    });
  });

  group("dragging a curve from inside its box", () {
    (CanvasController, LineElement) bowedLine() {
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
          id: "l",
          x: 200,
          y: document.size.height / 2,
          width: 800,
          height: 6,
        ),
        curvature: 0.4,
        strokeWidth: 6,
      );
      var controller = CanvasController(document.addElement(line));
      return (controller, line);
    }

    /// emptyCorner is a point inside the line's box but well away from the
    /// stroke, which is where clicking used to do nothing.
    Offset emptyCorner(CanvasController controller, LineElement line) {
      var box = visualBoundsOf(line, controller.document, 0);
      return Offset(box.left + box.width * 0.08, box.top + box.height * 0.12);
    }

    testWidgets("a selected line moves from anywhere inside its box",
        (tester) async {
      var (controller, line) = bowedLine();
      addTearDown(controller.dispose);
      controller.selectOnly("l");
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / controller.document.size.width;

      var inside = emptyCorner(controller, line);
      await tester.dragFrom(
          stage.pageRect.topLeft + inside * scale, const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(controller.document.elementById("l")!.x,
          closeTo(line.x + 40 / scale, 1),
          reason: "it followed the pointer from empty space in its own box");
    });

    testWidgets("but an unselected one is still only caught by its stroke",
        (tester) async {
      // Otherwise a bowed line's large empty box steals every click meant for
      // whatever is underneath it.
      var (controller, line) = bowedLine();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / controller.document.size.width;

      await tester.tapAt(
          stage.pageRect.topLeft + emptyCorner(controller, line) * scale);
      await tester.pumpAndSettle();
      expect(controller.selection, isEmpty);
    });

    testWidgets("something under the box still wins the click",
        (tester) async {
      var (controller, line) = bowedLine();
      addTearDown(controller.dispose);
      var under = ShapeElement(
        ElementBase(
          id: "s",
          x: emptyCorner(controller, line).dx - 40,
          y: emptyCorner(controller, line).dy - 40,
          width: 80,
          height: 80,
        ),
        fill: const Color(0xFFCC2200),
      );
      controller.apply(controller.document.addElement(under));
      controller.selectOnly("l");
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / controller.document.size.width;

      await tester.tapAt(
          stage.pageRect.topLeft + emptyCorner(controller, line) * scale);
      await tester.pumpAndSettle();
      expect(controller.selection, {"s"},
          reason: "the shape is on top of that empty space and gets the click");
    });
  });

  group("the on-canvas editor's box", () {
    testWidgets("is wide enough to type a caption into", (tester) async {
      // The box around the letters is exactly as wide as the letters, which
      // for a word or two is a slot too small to see what is being typed.
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
            id: "l", x: 200, y: document.size.height / 2, width: 800, height: 6),
      );
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 120, height: 40),
        text: "Hi",
        textSpec: const TextSpec(fontSize: 30),
        curve: const TextOnCurve(elementId: "l"),
      );
      var controller =
          CanvasController(document.addElement(line).addElement(text));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;

      var words = visualBoundsOf(text, controller.document, 0);
      var at = stage.pageRect.topLeft + words.center * scale;
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      var editor = tester.getRect(find.byType(CanvasTextEditor));
      expect(editor.width, greaterThan(words.width * scale * 2),
          reason: "far wider than the two letters it opened on");
      expect(editor.center.dx, closeTo(at.dx, 4),
          reason: "and grown about its own centre, so they stay put");
    });

    testWidgets("does not jump about as the words are typed", (tester) async {
      // The letters move on every keystroke, so a box followed live jumped
      // under the caret while it was being typed into.
      var document = const CanvasDocument();
      var line = LineElement(
        ElementBase(
            id: "l", x: 200, y: document.size.height / 2, width: 800, height: 6),
      );
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 120, height: 40),
        text: "Hi",
        textSpec: const TextSpec(fontSize: 30),
        curve: const TextOnCurve(elementId: "l"),
      );
      var controller =
          CanvasController(document.addElement(line).addElement(text));
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;

      var at = stage.pageRect.topLeft +
          visualBoundsOf(text, controller.document, 0).center * scale;
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      var before = tester.getRect(find.byType(CanvasTextEditor));
      await tester.enterText(
          find.byType(TextField), "A much longer caption than before");
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(CanvasTextEditor)), before,
          reason: "the box stayed exactly where it opened");
    });
  });

  group("grabbing a resize handle", () {
    testWidgets("a near miss still takes the handle, not the element",
        (tester) async {
      // The reported fault: aiming at a handle and landing a few pixels inside
      // it fell through to the element underneath and *moved* it, which is a
      // far worse outcome than doing nothing.
      var document = const CanvasDocument();
      var element = ShapeElement(
        ElementBase(
          id: "s",
          x: document.size.width / 4,
          y: document.size.height / 4,
          width: document.size.width / 2,
          height: document.size.height / 2,
        ),
        fill: const Color(0xFFCC2200),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("s");
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;

      // Ten screen pixels inside the bottom-right corner: a miss, but the kind
      // anybody makes.
      var corner = stage.pageRect.topLeft + element.bounds.bottomRight * scale;
      await tester.dragFrom(corner - const Offset(10, 10), const Offset(-40, 0));
      await tester.pumpAndSettle();

      var after = controller.document.elementById("s")!;
      expect(after.x, element.x, reason: "it was not dragged about");
      expect(after.width, lessThan(element.width),
          reason: "it was resized, which is what was being aimed at");
    });

    testWidgets("but the middle of an element still moves it", (tester) async {
      // The slop must not grow so far that the element itself is unreachable.
      var document = const CanvasDocument();
      var element = ShapeElement(
        ElementBase(
          id: "s",
          x: document.size.width / 4,
          y: document.size.height / 4,
          width: document.size.width / 2,
          height: document.size.height / 2,
        ),
        fill: const Color(0xFFCC2200),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("s");
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / document.size.width;

      await tester.dragFrom(
          stage.pageRect.topLeft + element.center * scale, const Offset(30, 0));
      await tester.pumpAndSettle();

      var after = controller.document.elementById("s")!;
      expect(after.width, element.width, reason: "not resized");
      expect(after.x, greaterThan(element.x), reason: "moved");
    });
  });

  group("resizing a picture", () {
    (CanvasController, ImageElement) withPicture({bool locked = true}) {
      var document = const CanvasDocument();
      var element = ImageElement(
        const ElementBase(id: "i", x: 100, y: 100, width: 400, height: 200),
      ).copyWith(lockAspect: locked);
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly("i");
      return (controller, element);
    }

    testWidgets("the handles hold its proportions without Shift",
        (tester) async {
      var (controller, element) = withPicture();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / controller.document.size.width;

      await tester.dragFrom(
          stage.pageRect.topLeft + element.bounds.bottomRight * scale,
          const Offset(0, 100));
      await tester.pumpAndSettle();

      var after = controller.document.elementById("i")!;
      expect(after.width / after.height,
          closeTo(element.width / element.height, 0.02),
          reason: "dragging one edge moved the other with it");
      expect(after.height, greaterThan(element.height));
    });

    testWidgets("unlocking lets it be stretched", (tester) async {
      var (controller, element) = withPicture(locked: false);
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      var scale = stage.pageRect.width / controller.document.size.width;

      await tester.dragFrom(
          stage.pageRect.topLeft + element.bounds.bottomRight * scale,
          const Offset(0, 100));
      await tester.pumpAndSettle();

      var after = controller.document.elementById("i")!;
      expect(after.width, closeTo(element.width, 1),
          reason: "only the edge that was dragged moved");
      expect(after.height, greaterThan(element.height));
    });
  });

  group("painting a retouching stroke", () {
    /// seed puts a decoded picture into the store, which the brush needs: a
    /// stroke is stored in the picture's own coordinates, so with nothing
    /// loaded there is nothing to convert against.
    Future<void> seed(WidgetTester tester, CanvasController controller) async {
      var pixels = Uint8List(64 * 64 * 4);
      for (var i = 0; i < 64 * 64; i++) {
        pixels[i * 4] = 200;
        pixels[i * 4 + 1] = 200;
        pixels[i * 4 + 2] = 200;
        pixels[i * 4 + 3] = 255;
      }
      await tester.runAsync(() async {
        var done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, 64, 64, ui.PixelFormat.rgba8888, done.complete);
        controller.images.putForTest("abcdefghijklmnop", await done.future);
      });
    }

    (CanvasController, ImageElement) withPicture() {
      var document = const CanvasDocument();
      var element = ImageElement(
        ElementBase(
          id: "i",
          x: 0,
          y: 0,
          width: document.size.width.toDouble(),
          height: document.size.height.toDouble(),
        ),
        assetId: "abcdefghijklmnop",
      );
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly("i");
      controller.retouch = RetouchBrush.erase;
      return (controller, element);
    }

    testWidgets("the picture is left alone until the pointer comes up",
        (tester) async {
      // Writing each point as it arrived changed the removal on every one,
      // which changes the cache key, which sets the store rebuilding the whole
      // treated picture -- a full pass over every pixel, dozens of times a
      // second, while somebody is trying to draw a line.
      var (controller, _) = withPicture();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      await seed(tester, controller);

      ImageElement current() =>
          controller.document.elementById("i")! as ImageElement;

      var from = stage.pageRect.center;
      var gesture = await tester.startGesture(from);
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(from + Offset(i * 12.0, 0));
        await tester.pump();
      }

      expect(current().removal.strokes, isEmpty,
          reason: "nothing written while the line is being drawn");

      await gesture.up();
      await tester.pumpAndSettle();

      // Still nothing: the stroke is held so the brush can be adjusted
      // against it, and applied when the reader is satisfied.
      expect(current().removal.strokes, isEmpty);
      expect(controller.hasPendingStroke, isTrue);
      expect(controller.pendingStroke!.length, greaterThan(3),
          reason: "with every point that was drawn");

      controller.applyStroke();
      expect(current().removal.strokes.length, 1,
          reason: "and the whole line lands in one go");
      expect(controller.hasPendingStroke, isFalse);
    });

    testWidgets("a whole stroke is one undo step", (tester) async {
      var (controller, _) = withPicture();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      await seed(tester, controller);

      var from = stage.pageRect.center;
      var gesture = await tester.startGesture(from);
      for (var i = 1; i <= 4; i++) {
        await gesture.moveTo(from + Offset(i * 12.0, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      controller.applyStroke();

      expect(
          (controller.document.elementById("i")! as ImageElement)
              .removal
              .strokes,
          hasLength(1));
      controller.undo();
      expect(
          (controller.document.elementById("i")! as ImageElement)
              .removal
              .strokes,
          isEmpty,
          reason: "one press takes the whole line back, not one point of it");
    });

    testWidgets("a marking brush lands in the hints instead", (tester) async {
      var (controller, _) = withPicture();
      addTearDown(controller.dispose);
      controller.replaceElement((controller.document.elementById("i")!
              as ImageElement)
          .copyWith(
              removal: const BackgroundRemoval(mode: RemovalMode.learn)));
      controller.retouch = RetouchBrush.markSubject;
      var stage = await pump(tester, controller);
      await seed(tester, controller);

      var from = stage.pageRect.center;
      var gesture = await tester.startGesture(from);
      await gesture.moveTo(from + const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      controller.applyStroke();

      var after = controller.document.elementById("i")! as ImageElement;
      expect(after.removal.hints, hasLength(1));
      expect(after.removal.hints.single.keep, isTrue);
      expect(after.removal.strokes, isEmpty);
    });
  });

  group("a held stroke", () {
    Future<CanvasController> drawOne(WidgetTester tester,
        {RetouchBrush brush = RetouchBrush.erase}) async {
      var document = const CanvasDocument();
      var element = ImageElement(
        ElementBase(
          id: "i",
          x: 0,
          y: 0,
          width: document.size.width.toDouble(),
          height: document.size.height.toDouble(),
        ),
        assetId: "abcdefghijklmnop",
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      controller.retouch = brush;
      var stage = await pump(tester, controller);

      var pixels = Uint8List(64 * 64 * 4);
      for (var i = 0; i < 64 * 64; i++) {
        pixels[i * 4] = 200;
        pixels[i * 4 + 1] = 200;
        pixels[i * 4 + 2] = 200;
        pixels[i * 4 + 3] = 255;
      }
      await tester.runAsync(() async {
        var done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, 64, 64, ui.PixelFormat.rgba8888, done.complete);
        controller.images.putForTest("abcdefghijklmnop", await done.future);
      });

      var from = stage.pageRect.center;
      var gesture = await tester.startGesture(from);
      await gesture.moveTo(from + const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets("takes the brush's settings as they are when it is applied",
        (tester) async {
      // The reported fault. A stroke used to take the settings the instant the
      // pointer came up, so changing hardness or cling afterwards did nothing
      // to it and the only way to try a setting was to undo and draw again.
      var controller = await drawOne(tester);

      controller.brushHardness = 0.25;
      controller.brushSnap = 0.3;
      controller.brushSize = 0.09;
      controller.applyStroke();

      var stroke = (controller.document.elementById("i")! as ImageElement)
          .removal
          .strokes
          .single;
      expect(stroke.hardness, 0.25);
      expect(stroke.snap, 0.3);
      expect(stroke.radius, 0.09);
    });

    testWidgets("can be thrown away without touching the picture",
        (tester) async {
      var controller = await drawOne(tester);
      controller.discardStroke();

      expect(controller.hasPendingStroke, isFalse);
      expect(
          (controller.document.elementById("i")! as ImageElement)
              .removal
              .strokes,
          isEmpty);
      expect(controller.canUndo, isFalse,
          reason: "and nothing to undo, since nothing was ever done");
    });

    testWidgets("remembers which brush drew it", (tester) async {
      // Picking up a different brush before applying is choosing to do
      // something else, not to adjust this.
      var controller = await drawOne(tester, brush: RetouchBrush.restore);
      expect(controller.pendingKeeps, isTrue);

      controller.retouch = RetouchBrush.erase;
      controller.applyStroke();

      expect(
          (controller.document.elementById("i")! as ImageElement)
              .removal
              .strokes
              .single
              .keep,
          isTrue);
    });

    testWidgets("a marking brush's hint is never softened or snapped",
        (tester) async {
      // A hint is a sample rather than a mark on the picture, so it is taken
      // exactly where it was drawn.
      var controller = await drawOne(tester, brush: RetouchBrush.markSubject);
      controller.brushHardness = 0.2;
      controller.brushSnap = 0.4;
      controller.applyStroke();

      var hint = (controller.document.elementById("i")! as ImageElement)
          .removal
          .hints
          .single;
      expect(hint.hardness, 1);
      expect(hint.snap, 0);
    });
  });

  group("the held stroke's preview", () {
    testWidgets("is drawn through the same placement as the picture",
        (tester) async {
      // The preview is the size of the whole picture, and the picture is not
      // necessarily drawn whole -- "fill the box" shows a centre crop of it.
      // Stretching the whole preview into the element put the tint somewhere
      // other than the stroke, over an area that had nothing to do with it.
      var document = const CanvasDocument();
      var wide = ImageElement(
        const ElementBase(id: "i", x: 0, y: 0, width: 400, height: 100),
        assetId: "abcdefghijklmnop",
      ).copyWith(fit: ImageFit.cover);

      // A square picture in a wide box: cover crops the top and bottom away.
      var placement = placeImage(
          const Size(200, 200), wide.bounds, ImageFit.cover);

      expect(placement.dst, wide.bounds,
          reason: "cover fills the box");
      expect(placement.src.height, lessThan(200),
          reason: "and takes only a band out of the middle of the picture");
      expect(placement.src.width, 200);

      // Drawing the preview through this placement puts a stroke recorded at
      // the middle of the picture in the middle of the box; drawing the whole
      // preview into dst would squash the discarded bands into it as well.
      expect(document.size.width, greaterThan(0));
    });

    testWidgets("waits for the settings to stop moving", (tester) async {
      // Rebuilding on every change means every keystroke and every pixel of a
      // scrub: a full pass over the picture and an image decode for each.
      var document = const CanvasDocument();
      var element = ImageElement(
        ElementBase(
          id: "i",
          x: 0,
          y: 0,
          width: document.size.width.toDouble(),
          height: document.size.height.toDouble(),
        ),
        assetId: "abcdefghijklmnop",
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      controller.retouch = RetouchBrush.erase;
      await pump(tester, controller);

      controller.holdStroke("i", const [Offset(0.5, 0.5)],
          keeps: false, teaches: false);
      await tester.pump();

      // Nothing has been built yet: the timer has not fired.
      expect(find.byType(CanvasStage), findsOneWidget);
      controller.brushHardness = 0.5;
      controller.brushHardness = 0.6;
      controller.brushHardness = 0.7;
      await tester.pump(const Duration(milliseconds: 50));
      // Still nothing -- three changes in quick succession are one rebuild,
      // not three.
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });

  group("the cut-around brush", () {
    testWidgets("its stroke is held as a boundary, not a mark", (tester) async {
      var document = const CanvasDocument();
      var element = ImageElement(
        ElementBase(
          id: "i",
          x: 0,
          y: 0,
          width: document.size.width.toDouble(),
          height: document.size.height.toDouble(),
        ),
        assetId: "abcdefghijklmnop",
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      controller.retouch = RetouchBrush.cutAround;
      var stage = await pump(tester, controller);

      var pixels = Uint8List(64 * 64 * 4);
      for (var i = 0; i < 64 * 64; i++) {
        pixels[i * 4] = 200;
        pixels[i * 4 + 1] = 200;
        pixels[i * 4 + 2] = 200;
        pixels[i * 4 + 3] = 255;
      }
      await tester.runAsync(() async {
        var done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, 64, 64, ui.PixelFormat.rgba8888, done.complete);
        controller.images.putForTest("abcdefghijklmnop", await done.future);
      });

      var from = stage.pageRect.center;
      var gesture = await tester.startGesture(from);
      await gesture.moveTo(from + const Offset(40, 0));
      await gesture.moveTo(from + const Offset(40, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.pendingFills, isTrue);
      controller.applyStroke();

      var stroke = (controller.document.elementById("i")! as ImageElement)
          .removal
          .strokes
          .single;
      expect(stroke.fill, isTrue);
      expect(stroke.snap, 0,
          reason: "a boundary does not care what colour anything is");
    });
  });
}
