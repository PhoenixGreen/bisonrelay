import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
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
}
