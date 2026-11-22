import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/canvas_panel_helpers.dart';
import 'support/canvas_timeline_menus.dart';

// canvas_editor_elements_test.dart is an element's settings: shapes,
// pictures, teams, counters, outlines, scrubbing numbers, cropping, locking
// proportions and how the settings are laid out.
//
// Built as widgets and used, rather than tested through the controller: a
// control drawn but wired to nothing passes every model test there is. So
// these tap the thing and look at the document.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  Future<void> pump(WidgetTester tester, Widget child,
          {CanvasPreferences? prefs}) =>
      pumpCanvasApp(tester, child, size: const Size(1400, 900), prefs: prefs);

  group("a team's settings", () {
    /// panel pumps the Layers sidebar with a team selected, which is where an
    /// element's settings live.
    Future<CanvasController> panel(WidgetTester tester,
        {TeamElement? team}) async {
      var document = const CanvasDocument(size: CanvasSize(width: 1000));
      var element = (team ??
          TeamElement(
            ElementBase(id: newElementId(), width: 400, height: 300),
          ).withFormation(TeamFormation.f442)) as CanvasElement;
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));
      return controller;
    }

    TeamElement teamIn(CanvasController c) =>
        c.document.elements.whereType<TeamElement>().single;

    testWidgets("one element is the whole team", (tester) async {
      var controller = await panel(tester);
      expect(teamIn(controller).players.length, 11,
          reason: "ten outfield players and a goalkeeper");
      // The panel header names the element now, so the first group no longer
      // captions itself with the same word.
      expect(find.text("TEAM SETTINGS"), findsOneWidget);
      expect(
          find.byKey(const ValueKey("elementSection-players")), findsOneWidget);
    });

    testWidgets("choosing a formation moves everybody", (tester) async {
      var controller = await panel(tester);
      var before = [for (var p in teamIn(controller).players) (p.dx, p.dy)];

      // Scrolled to first: every element carries a Presets line at the top
      // of its settings now, so what is below it starts lower down.
      await tester.ensureVisible(find.text("4-4-2").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("4-4-2").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("4-3-3").last);
      await tester.pumpAndSettle();

      var after = teamIn(controller);
      expect(after.formation, TeamFormation.f433);
      expect([for (var p in after.players) (p.dx, p.dy)], isNot(before));
      expect(after.players.length, 11);
    });

    testWidgets("the squad list opens and edits one player", (tester) async {
      // Behind an expander because eleven rows of four fields is more than
      // every other element's settings put together.
      var controller = await panel(tester);
      var id = teamIn(controller).id;

      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      await _openPlayers(tester);

      // The goalkeeper is the first row, and is labelled as such.
      expect(find.text("GK"), findsOneWidget);

      await enterValue(tester, find.byKey(ValueKey("name-0-$id")), "Banks");
      await tester.pump();
      expect(teamIn(controller).players.first.name, "Banks");

      await enterValue(tester, find.byKey(ValueKey("num-0-$id")), "01");
      await tester.pump();
      expect(teamIn(controller).players.first.number, "01",
          reason: "a squad number is written, not counted");
    });

    testWidgets("a player's coordinates are the canvas's, not the box's",
        (tester) async {
      var team = TeamElement(
        ElementBase(id: newElementId(), x: 100, y: 50, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller = await panel(tester, team: team);
      var id = teamIn(controller).id;

      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      // Opened only if shut: an expander opened earlier in this file is
      // remembered open.
      if (find.byKey(ValueKey("x-0-$id")).evaluate().isEmpty) {
        await tester.ensureVisible(find.text("PLAYERS"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("PLAYERS"));
        await tester.pumpAndSettle();
      }

      await enterValue(tester, find.byKey(ValueKey("x-0-$id")), "260");
      await tester.pump();
      var keeper = teamIn(controller).players.first;
      expect(teamIn(controller).centreOf(keeper).dx, closeTo(260, 0.5),
          reason: "typed as a canvas coordinate, stored as a fraction");
      expect(keeper.dx, closeTo((260 - 100) / 400, 0.001));
    });

    testWidgets("lock, hide and reorder work per player", (tester) async {
      var controller = await panel(tester);
      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      await _openPlayers(tester);

      /// press chooses [item] from one player's ⋯ menu: scrolled into view
      /// first, as eleven rows are taller than the settings column.
      Future<void> press(int index, String item) async {
        var id = teamIn(controller).id;
        var more = find.byKey(ValueKey("more-$index-$id"));
        await tester.ensureVisible(more);
        await tester.pumpAndSettle();
        await tester.tap(more);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey("$item-$index-$id")));
        await tester.pumpAndSettle();
      }

      await press(0, "lock");
      expect(teamIn(controller).players.first.locked, isTrue);
      expect(teamIn(controller).locked, isFalse,
          reason: "locking a player must not lock the whole team");

      await press(0, "hide");
      expect(teamIn(controller).players.first.hidden, isTrue);

      var second = teamIn(controller).players[1].number;
      await press(0, "forward");
      expect(teamIn(controller).players[0].number, second,
          reason: "the keeper moved up one, so the next player is now first");
    });

    testWidgets("the dot's width and height are locked together",
        (tester) async {
      // A player marker is a circle, and an oval is almost always somebody
      // having dragged one field without meaning to.
      var controller = await panel(tester);
      expect(teamIn(controller).lockDotAspect, isTrue);

      await enterValue(
          tester, find.byKey(const ValueKey("teamDotWidth")), "60");
      await tester.pump();
      expect(teamIn(controller).dotWidth, 60);
      expect(teamIn(controller).dotHeight, 60);

      // Scrolled to first: a team has more settings than fit in the panel,
      // and a tap on something below the fold lands on whatever is there.
      var lock = byTip("Width and height move together");
      await tester.ensureVisible(lock);
      await tester.pumpAndSettle();
      await tester.tap(lock);
      await tester.pumpAndSettle();
      await enterValue(
          tester, find.byKey(const ValueKey("teamDotHeight")), "20");
      await tester.pump();
      expect(teamIn(controller).dotWidth, 60, reason: "now independent");
      expect(teamIn(controller).dotHeight, 20);
    });

    testWidgets("numbers and names share one set of type controls",
        (tester) async {
      // They were two identical panels, and the two drifted -- a team's names
      // ended up in a different face from its numbers.
      var controller = await panel(tester);
      expect(
          find.byKey(const ValueKey("elementSection-labels")), findsOneWidget);
      expect(teamIn(controller).labelSpec.fontSize, isNotNull);
    });
  });

  group("the element settings", () {
    testWidgets("carry no lock, hide or reorder controls", (tester) async {
      // All four are properties of the *layer* rather than of the thing on it,
      // and the layer list already shows them on the row that names the
      // element -- where hiding something does not make the panel you are
      // hiding it from disappear.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await pump(tester, designSidebar(controller));

      // The layer row has them.
      expect(byTip("Lock"), findsOneWidget);
      expect(byTip("Hide"), findsOneWidget);
      expect(byTip("Move forward"), findsOneWidget);
      // The settings below it do not.
      expect(byTip("Lock in place"), findsNothing);
      expect(byTip("Bring to front"), findsNothing);
      expect(byTip("Send to back"), findsNothing);
    });

    testWidgets("a player row keeps its own, since the layer list has none",
        (tester) async {
      var team = TeamElement(
        const ElementBase(id: "t", name: "Home", width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller =
          CanvasController(const CanvasDocument().addElement(team));
      addTearDown(controller.dispose);
      controller.selectOnly("t");

      await pump(tester, designSidebar(controller));
      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      var more = find.byKey(const ValueKey("more-0-t"));
      if (more.evaluate().isEmpty) {
        await tester.ensureVisible(find.text("PLAYERS"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("PLAYERS"));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text("Lock in place"), findsOneWidget,
          reason: "a player is not a layer and has nowhere else to be locked");
    });
  });

  group("animated settings", () {
    (CanvasController, CanvasElement) moving() {
      var document = const CanvasDocument(frames: 30);
      // An instrument: the one kind still on the older panel, whose
      // Position has the pose diamond and easing (the rebuilt panels key in
      // the Chain).
      var element = const AudioElement(
          ElementBase(id: "s", x: 100, y: 50, width: 40, height: 40),
          instrument: InstrumentPart());
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly("s");
      controller.setKeyframe("s", const Keyframe(frame: 0));
      controller.setKeyframe("s", const Keyframe(frame: 20, dx: 200, dy: 60));
      return (controller, element);
    }

    testWidgets("X and Y show where the element is on this frame",
        (tester) async {
      // They showed where it *rests*, so scrubbing into the middle of a move
      // left two numbers describing somewhere the element visibly was not.
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, designSidebar(controller));

      var x = find.byKey(const ValueKey("elementX"));
      expect(find.descendant(of: x, matching: find.text("200")), findsOneWidget,
          reason: "half way along a 100 to 300 move");
    });

    testWidgets("typing a position while animating writes a keyframe",
        (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, designSidebar(controller));

      await typeNumber(tester, "elementX", "500");

      var element = controller.document.elementById("s")!;
      expect(element.x, 100, reason: "the resting position is untouched");
      expect(element.track!.keyAt(10)!.dx, 400);
      expect(element.boundsAt(10).left, 500);
      expect(element.boundsAt(0).left, 100, reason: "and frame 0 is unchanged");
    });

    testWidgets("angle and opacity follow the pose too", (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.setKeyframe(
          "s", const Keyframe(frame: 20, rotate: 90, opacity: 0.5));
      controller.frame = 20;
      await pump(tester, designSidebar(controller));

      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementAngle")),
              matching: find.text("90°")),
          findsOneWidget);
    });
  });

  group("the shape settings", () {
    /// panel builds an element's settings the way the Layers sidebar does.
    Future<CanvasController> panel(WidgetTester tester, ShapeElement shape,
        {String? text}) async {
      var element = text == null ? shape : shape.copyWith(text: text);
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));
      return controller;
    }

    ShapeElement shapeOf(ShapeKind kind) => ShapeElement(
          const ElementBase(id: "s", width: 200, height: 120),
          shape: kind,
        );

    /// tail opens the button on the end of the Bubble line, which holds the
    /// tail's own measurements. Only if it is shut: an opened area stays open
    /// for the rest of the file.
    Future<void> tail(WidgetTester tester) async {
      var button = find.byKey(const ValueKey("more-shapeBubbleMore"));
      if (find.text("Length").evaluate().isNotEmpty) return;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets("a bubble shows its own settings, label or no label",
        (tester) async {
      // They were nested inside "if there is a label" by accident, so a bubble
      // with nothing written in it offered none of them -- which is exactly
      // the state a bubble is in when it has just been added.
      await panel(tester, shapeOf(ShapeKind.speechBubble));
      // In its Content, with what shape it is (batch 2 of the rebuild).
      expect(find.text("Tail"), findsWidgets);
      expect(find.text("Body"), findsOneWidget);
      expect(find.text("Tail"), findsOneWidget);
      // Where the tail points is a measurement, so it is behind the button
      // on the end of that line.
      await tail(tester);
      expect(find.text("Points"), findsOneWidget);
    });

    testWidgets("and still shows them once it has one", (tester) async {
      await panel(tester, shapeOf(ShapeKind.speechBubble), text: "Hello");
      // In its Content, with what shape it is (batch 2 of the rebuild).
      expect(find.text("Tail"), findsWidgets);
      expect(find.byKey(const ValueKey("shapeLabelType")), findsOneWidget);
    });

    testWidgets("another shape shows none of them", (tester) async {
      await panel(tester, shapeOf(ShapeKind.star), text: "Hi");
      expect(find.byKey(const ValueKey("elementSection-bubble")), findsNothing);
      expect(find.text("Tail"), findsNothing);
    });

    testWidgets("the label's type appears only when there is a label",
        (tester) async {
      await panel(tester, shapeOf(ShapeKind.star));
      expect(find.byKey(const ValueKey("shapeLabelType")), findsNothing);
    });

    testWidgets("changing the tail writes it to the element", (tester) async {
      var controller = await panel(tester, shapeOf(ShapeKind.speechBubble));

      // Scrolled to first: the settings share their column with the add grid
      // and the layer list now, so a control this far down the panel is below
      // the fold until it is brought up.
      await tester.ensureVisible(find.text(BubbleTail.pointer.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(BubbleTail.pointer.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(BubbleTail.thought.label).last);
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ShapeElement;
      expect(after.bubble.tail, BubbleTail.thought);
    });

    testWidgets("the tail angle can be typed", (tester) async {
      var controller = await panel(tester, shapeOf(ShapeKind.speechBubble));
      await tail(tester);
      await enterValue(
          tester, find.byKey(const ValueKey("bubbleTailAngle")), "270");
      await tester.pump();
      expect(
          (controller.document.elements.single as ShapeElement)
              .bubble
              .tailAngle,
          270);
    });

    testWidgets("the fill swatch goes away while a picture is over it",
        (tester) async {
      // The same as the box next door: a picture or a pattern fills the whole
      // outline, so the swatch changed nothing you could see. The stroke's
      // colour stays either way -- the outline is drawn over the picture.
      var controller = await panel(tester, shapeOf(ShapeKind.star));
      // Its Look's: the quick strip has one too, gone the same way.
      var fill = find.descendant(
          of: find.byKey(const ValueKey("elementSection-look")),
          matching: find.byWidgetPredicate(
              (w) => w is CanvasColorButton && w.label == "Fill"));
      var stroke = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Colour");
      expect(fill, findsOneWidget);

      var kind = find.byKey(const ValueKey("shapeFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-shapeMore"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      expect((controller.document.elements.single as ShapeElement).painted.kind,
          TextFillKind.pattern);
      expect(fill, findsNothing, reason: "the pattern decides now");
      expect(stroke, findsOneWidget, reason: "but the outline is still drawn");
    });

    testWidgets("choosing a stroke colour gives the shape a stroke",
        (tester) async {
      // A shape arrives with a stroke 0 wide, and a stroke 0 wide is not
      // drawn however it is coloured -- so the swatch called Colour was a
      // setting that did nothing at all until a number was typed into the
      // box beside it. Asking for a colour is asking for a line.
      var controller = await panel(tester, shapeOf(ShapeKind.star));
      expect(
          (controller.document.elements.single as ShapeElement).strokeWidth, 0,
          reason: "otherwise this test is not asking anything");

      var colour = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Colour");
      expect(colour, findsOneWidget);
      tester
          .widget<CanvasColorButton>(colour)
          .onChanged(const Color(0xFF00FF00));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ShapeElement;
      expect(after.strokeColor, const Color(0xFF00FF00));
      expect(after.strokeWidth, greaterThan(0),
          reason: "and a line to see it on");
    });

    testWidgets("but leaves a stroke it already has alone", (tester) async {
      var controller = await panel(
          tester,
          ShapeElement(const ElementBase(id: "s", width: 200, height: 120),
              shape: ShapeKind.star, strokeWidth: 12));
      var colour = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Colour");
      tester
          .widget<CanvasColorButton>(colour)
          .onChanged(const Color(0xFF00FF00));
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ShapeElement).strokeWidth,
          12);
    });

    testWidgets("a colour and a fade set in one visit both land",
        (tester) async {
      // Two writes to the same element, and the panel's controls are built
      // from the element as it was when it was last laid out -- so written in
      // one frame the second was built on the same stale copy and undid the
      // first. Reported as a gradient point's opacity not sticking.
      var controller = await panel(tester, shapeOf(ShapeKind.star));
      // Its Look's, not the quick strip's.
      var fill = find
          .byWidgetPredicate((w) => w is CanvasColorButton && w.label == "Fill")
          .last;
      await tester.ensureVisible(fill);
      await tester.pumpAndSettle();
      await tester.tap(fill);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey("colorModegradient")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("gradientAdd")));
      await tester.pumpAndSettle();

      // Back to the first point, and its opacity turned down.
      var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
      await tester.tapAt(Offset(bar.left + 4, bar.center.dy));
      await tester.pumpAndSettle();
      var slider =
          tester.getRect(find.byKey(const ValueKey("gradientOpacity")));
      await tester.dragFrom(Offset(slider.right - 20, slider.center.dy),
          Offset(-slider.width / 2, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Select"));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ShapeElement;
      expect(after.fillFade, isNotNull, reason: "the fade was set");
      expect(after.fill.a, lessThan(0.9),
          reason: "and so was the first colour's opacity");
    });

    testWidgets("the curl appears only for a curved tail", (tester) async {
      await panel(tester, shapeOf(ShapeKind.speechBubble));
      await tail(tester);
      expect(find.text("Curl"), findsNothing);

      var curved = ShapeElement(
        const ElementBase(id: "s", width: 200, height: 120),
        shape: ShapeKind.speechBubble,
        bubble: const SpeechBubbleSpec(tail: BubbleTail.curved),
      );
      await panel(tester, curved);
      await tail(tester);
      expect(find.text("Curl"), findsOneWidget);
    });
  });

  group("scrubbing a number", () {
    // The timeline's Length and Per second, as they are in a column with
    // their captions over them. The play bar keeps its captions in hover
    // text now, so what is dragged here is the same field where the caption
    // is on the screen to take hold of.
    Widget fields(CanvasController controller) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            var document = controller.document;
            return Row(children: [
              CanvasNumberField(
                key: const ValueKey("canvasFrames"),
                label: "Length",
                value: document.frames.toDouble(),
                min: 1,
                max: maxFrameCount.toDouble(),
                width: 68,
                onChanged: (v) {
                  controller.beginInteraction();
                  controller.apply(document.copyWith(frames: v.round()),
                      transient: true);
                },
                onCommit: controller.endInteraction,
              ),
              CanvasNumberField(
                key: const ValueKey("canvasFrameRate"),
                label: "Per second",
                value: document.frameRate.toDouble(),
                min: 1,
                max: 60,
                width: 60,
                onChanged: (v) {
                  controller.beginInteraction();
                  controller.apply(document.copyWith(frameRate: v.round()),
                      transient: true);
                },
                onCommit: controller.endInteraction,
              ),
            ]);
          },
        );

    testWidgets("one pixel is one of the field's own last digits",
        (tester) async {
      // Not a fraction of the field's range, which was the first attempt and
      // was hundreds per pixel: most of these ranges are guard rails rather
      // than scales.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, fields(controller));

      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.text("Length"));
      await tester.drag(caption, const Offset(40, 0));
      await tester.pumpAndSettle();

      // A whole-number field, so forty pixels is forty frames.
      expect(controller.document.frames, 240);
    });

    testWidgets("dragging the caption runs the value up and down",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, fields(controller));

      var before = controller.document.frames;
      // The caption above the field is the handle -- a TextField owns its own
      // drag, which is how text is selected, so the field itself cannot be it.
      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.text("Length"));
      expect(caption, findsOneWidget);

      await tester.drag(caption, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, greaterThan(before));

      var up = controller.document.frames;
      await tester.drag(caption, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, lessThan(up),
          reason: "and back down again");
    });

    testWidgets("it stays inside the field's own limits", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      await pump(tester, fields(controller));

      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrameRate")),
          matching: find.text("Per second"));
      // Far past the bottom of a 1..60 field.
      await tester.drag(caption, const Offset(-4000, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 1);

      await tester.drag(caption, const Offset(8000, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 60);
    });

    testWidgets("where in the caption it is grabbed makes no difference",
        (tester) async {
      // The gesture reports the pointer's position within the widget rather
      // than how far it has travelled, so an unadjusted read moved the value
      // by wherever in the label it was taken hold of.
      Future<int> dragFromFraction(double at) async {
        var controller = CanvasController(const CanvasDocument(frames: 200));
        addTearDown(controller.dispose);
        await pump(tester, fields(controller));

        var caption = find.descendant(
            of: find.byKey(const ValueKey("canvasFrames")),
            matching: find.text("Length"));
        var box = tester.getRect(caption);
        await tester.dragFrom(Offset(box.left + box.width * at, box.center.dy),
            const Offset(30, 0));
        await tester.pumpAndSettle();
        return controller.document.frames;
      }

      expect(await dragFromFraction(0.1), await dragFromFraction(0.9));
      expect(await dragFromFraction(0.5), 230);
    });

    testWidgets("holding the number itself scrubs it as well", (tester) async {
      // A caption is written once per column, so a chart's fourth series has
      // an Offset field with nothing above it to drag -- a number that could
      // only be typed. Holding the field is the other handle: a press on a
      // number means nothing else, where a *drag* on one is how text is
      // selected.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));
      await openTiming(tester);

      var field = find.byKey(const ValueKey("canvasFrames"));
      String shown() => tester
          .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)))
          .controller!
          .text;

      var press = await tester.startGesture(tester.getCenter(field));
      await tester.pump(const Duration(milliseconds: 500));
      await press.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(controller.document.frames, 240,
          reason: "forty pixels, forty frames, the same as the caption");
      // While it is still being dragged: pressing the field is what gives it
      // the focus, and a field with the focus is not rewritten from outside
      // -- so the number ran up and down on the canvas with the old figure
      // still sitting in the box.
      expect(shown(), "240", reason: "and the box says what the value is");

      await press.up();
      await tester.pumpAndSettle();
      expect(shown(), "240");
    });

    testWidgets("but a drag that was not held leaves the number alone",
        (tester) async {
      // That is the field's own drag, which selects the digits to retype
      // them. Taking it would make an exact number impossible to type over.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));
      await openTiming(tester);

      await tester.drag(
          find.byKey(const ValueKey("canvasFrames")), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, 200);
    });

    testWidgets("and the hold itself reaches nothing but the field",
        (tester) async {
      // What made it temperamental: the hold used to drop the focus, to keep
      // the caret out of the way. Losing the focus calls onCommit, which
      // closes the undo step, which rebuilds the settings panel -- which can
      // take the field's own state away in the middle of its gesture. So the
      // scrub worked or did not depending on what the panel did next.
      var commits = 0;
      var value = 10.0;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => CanvasNumberField(
            key: const ValueKey("held"),
            label: "Size",
            value: value,
            onChanged: (v) => setState(() => value = v),
            onCommit: () => commits++,
          ),
        ),
      );

      var field = find.byKey(const ValueKey("held"));
      // Focused first, which is the ordinary way round: a number is clicked,
      // looked at, and then dragged. That is also the case the old hold broke,
      // since a field with nothing to lose loses no focus.
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(commits, 0, reason: "clicking into a field finishes nothing");

      var press = await tester.startGesture(tester.getCenter(field));
      await tester.pump(const Duration(milliseconds: 500));
      await press.moveBy(const Offset(20, 0));
      await tester.pump();

      expect(value, 30, reason: "twenty pixels on a whole-number field");
      expect(commits, 0, reason: "nothing is finished until it is let go");

      await press.up();
      await tester.pumpAndSettle();
      expect(commits, 1);
    });

    testWidgets("and the pointer says so over the box", (tester) async {
      // The same left-and-right cursor the caption shows, which is the only
      // thing that says a number can be dragged at all. On the field itself
      // rather than in a region around it: a text field carries a cursor of
      // its own and the innermost one wins, so an I-beam would have said
      // "type here" over the one control that also does something else.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));
      await openTiming(tester);

      var box = tester.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.byType(TextField)));
      expect(box.mouseCursor, SystemMouseCursors.resizeLeftRight);
    });

    testWidgets("typing into the field still works", (tester) async {
      // The scrub must not have taken the field over.
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));
      await openTiming(tester);

      await enterValue(
          tester, find.byKey(const ValueKey("canvasFrames")), "125");
      await tester.pump();
      expect(controller.document.frames, 125);
    });
  });

  group("cropping a picture", () {
    test("trims the frame, so what is left stays where it was", () {
      // Reported as "some kind of strange zoom which is very hard to
      // control": the crop showed less of the picture in the same box, so
      // the rest was re-fitted to fill the frame. What a crop means to
      // anybody using one is that the edge moves in and takes that strip
      // with it.
      var picture = ImageElement(
        const ElementBase(id: "p", x: 100, y: 50, width: 400, height: 200),
        assetId: "a",
      );

      // A quarter off the left: the left edge moves in by a quarter of the
      // frame, and the right edge does not move at all.
      var cropped = picture.croppedTo(const ImageCrop(left: 0.25));
      expect(cropped.x, closeTo(200, 0.01));
      expect(cropped.width, closeTo(300, 0.01));
      expect(cropped.x + cropped.width, closeTo(500, 0.01),
          reason: "the right-hand edge is where it was");
      expect(cropped.y, 50, reason: "and nothing happened to the height");
      expect(cropped.height, 200);

      // And a second crop is measured against what is showing now, not
      // against the whole picture: another quarter off the left of what is
      // left takes a quarter of *this* frame.
      var again = cropped.croppedTo(const ImageCrop(left: 0.5));
      expect(again.x, closeTo(300, 0.01));
      expect(again.width, closeTo(200, 0.01));
    });

    test("and giving it all back puts the frame back", () {
      var picture = ImageElement(
        const ElementBase(id: "p", x: 100, y: 50, width: 400, height: 200),
        assetId: "a",
      );
      var cropped = picture
          .croppedTo(const ImageCrop(left: 0.25, bottom: 0.5))
          .croppedTo(const ImageCrop());
      expect(cropped.x, closeTo(100, 0.01));
      expect(cropped.width, closeTo(400, 0.01));
      expect(cropped.height, closeTo(200, 0.01));
    });

    test("but not to nothing", () {
      var picture = ImageElement(
        const ElementBase(id: "p", width: 40, height: 40),
        assetId: "a",
      );
      var flat = picture.croppedTo(const ImageCrop(left: 0.99));
      expect(flat.width, 40, reason: "the frame is left alone");
      expect(flat.crop.left, 0.99, reason: "and the crop is still written");
    });
  });

  group("the image settings", () {
    Future<CanvasController> panel(
        WidgetTester tester, ImageElement image) async {
      var controller =
          CanvasController(const CanvasDocument().addElement(image));
      addTearDown(controller.dispose);
      controller.selectOnly(image.id);
      await pump(tester, designSidebar(controller));
      await openSection(tester, "image.picture.colour");
      return controller;
    }

    // The card a group is drawn as, found by its name.
    Finder group(String label) => find
        .byWidgetPredicate((w) => w is CanvasControlGroup && w.label == label);

    ImageElement empty() =>
        const ImageElement(ElementBase(id: "i", width: 200, height: 200));
    ImageElement filled() =>
        const ImageElement(ElementBase(id: "i", width: 200, height: 200),
            assetId: "abcdefghij123456");

    testWidgets("an empty one offers somewhere to put a picture",
        (tester) async {
      // The control the element did not have, and without which it does
      // nothing at all.
      await panel(tester, empty());
      expect(byTip("Add a picture"), findsOneWidget);
    });

    testWidgets("a filled one offers to replace or remove it", (tester) async {
      var controller = await panel(tester, filled());
      expect(byTip("Replace this picture"), findsOneWidget);

      await tester.ensureVisible(byTip("Take the picture out"));
      await tester.pumpAndSettle();
      await tester.tap(byTip("Take the picture out"));
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ImageElement).hasImage,
          isFalse);
    });

    testWidgets("the zoom field reaches the picture", (tester) async {
      // Reported as the numbers moving while the picture did not. The field
      // writes the element, and the element is what the painter places --
      // see placeImage, which is tested against the pixels next door.
      var controller = await panel(tester, filled());
      // Framing is in the Fit tool on the Position shelf.
      var tool = find.byKey(const ValueKey("positionTool-fit"));
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();
      var zoom = find.ancestor(
          of: find.text("Zoom"), matching: find.byType(CanvasNumberField));
      expect(zoom, findsOneWidget, reason: "offered for a picture that fills");
      await typeInto(tester, zoom, "2");
      expect((controller.document.elements.single as ImageElement).framing.zoom,
          2);
    });

    testWidgets("and framing is not offered where it can do nothing",
        (tester) async {
      // Contained or stretched there is no slack to spend and no window to
      // shrink, so the three numbers would be three dead controls.
      await panel(tester, filled().copyWith(fit: ImageFit.contain));
      var tool = find.byKey(const ValueKey("positionTool-fit"));
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();
      expect(group("Framing"), findsNothing);
      // What framing needs is said in the Fit tool -- its hint.
      expect(
          find.byWidgetPredicate(
              (w) => w is CanvasHint && w.message.contains("With Cover")),
          findsOneWidget,
          reason: "and it says where they went");
    });

    testWidgets("crop and overlay appear only once there is a picture",
        (tester) async {
      await panel(tester, empty());
      expect(group("Crop"), findsNothing);
      expect(group("Overlay"), findsNothing);

      await panel(tester, filled());
      // The crop is a tool in Mask's shelf now, its numbers with it
      // in hand -- see canvas_panel_kit_test.
      expect(group("Crop"), findsNothing);
      expect(group("Overlay"), findsOneWidget);
      // The base picture's shape cuts the whole of it, so it is the frame's:
      // a tool on Frame's shelf, picture or not, and not a second time with
      // the picture.
      expect(find.byKey(const ValueKey("frameTool-shape")), findsOneWidget);
      expect(group("Shape"), findsNothing);
    });

    testWidgets("the overlay colour appears only once a blend is chosen",
        (tester) async {
      // By key: several groups have a colour in them, and the border's is
      // always there.
      await panel(tester, filled());
      expect(find.byKey(const ValueKey("imageOverlayColour")), findsNothing);

      await panel(tester, filled().copyWith(blend: OverlayBlend.multiply));
      expect(find.byKey(const ValueKey("imageOverlayColour")), findsOneWidget);
    });

    testWidgets("a frame can be chosen and cleared", (tester) async {
      var controller = await panel(tester, filled());

      await tester.ensureVisible(find.text("Rectangle").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Rectangle").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ShapeKind.circle.label).last);
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ImageElement).frame,
          ShapeKind.circle);
    });
  });

  group("element settings use numbers, not sliders", () {
    testWidgets("a fraction is typed and dragged like every other number",
        (tester) async {
      // A slider inside a settings row is a few dozen pixels wide, so the
      // whole of an opacity is about forty pixels of travel and nothing can be
      // set precisely. They are number fields now, which type and scrub.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      expect(find.byType(Slider), findsNothing,
          reason: "no sliders left in an element's settings");

      // A percentage on the panel, a fraction in the document.
      await typeNumber(tester, "elementOpacity", "40");
      expect(controller.document.elements.single.opacity, closeTo(0.4, 0.001));
    });

    testWidgets("dragging the number scrubs a percent a pixel", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      var number = find.byKey(const ValueKey("elementOpacity-number"));
      await tester.ensureVisible(number);
      await tester.pumpAndSettle();
      await tester.drag(number, const Offset(-25, 0));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // A percent a pixel, so twenty-five pixels is a quarter.
      expect(controller.document.elements.single.opacity, closeTo(0.75, 0.02));
    });
  });

  group("the counter settings", () {
    // Two elements in one, and the switch between them is the thing to pin:
    // keyframes on, the number is read off the timeline; off, it runs in real
    // time and the buttons under it mean something.
    Future<CanvasController> panel(WidgetTester tester,
        {CounterElement Function(CounterElement)? shape,
        int frames = 60}) async {
      var element = const CounterElement(
        ElementBase(id: "n", width: 320, height: 160),
        from: 0,
        to: 100,
      );
      var controller = CanvasController(CanvasDocument(frames: frames)
          .addElement(shape == null ? element : shape(element)));
      addTearDown(controller.dispose);
      controller.selectOnly("n");
      await pump(tester, designSidebar(controller));
      return controller;
    }

    CounterElement counterIn(CanvasController controller) =>
        controller.document.elements.single as CounterElement;

    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// showCount opens the Count section if it is shut, and hands back what
    /// shuts it again -- an expander remembers, and the memory outlives the
    /// test.
    Future<Future<void> Function()> showCount(WidgetTester tester) async {
      var open =
          find.byKey(const ValueKey("counterKeyed")).evaluate().isNotEmpty;
      if (!open) await press(tester, find.text("COUNT"));
      return () async {
        if (!open) await press(tester, find.text("COUNT"));
      };
    }

    testWidgets("count from, to and how the number is written", (tester) async {
      var controller = await panel(tester);
      await enterValue(tester, find.byKey(const ValueKey("counterTo")), "250");
      await tester.pumpAndSettle();
      expect(counterIn(controller).to, 250);

      await enterValue(
          tester, find.byKey(const ValueKey("counterDecimals")), "2");
      await tester.pumpAndSettle();
      expect(counterIn(controller).decimals, 2);
      expect(counterIn(controller).format(1234.5), "1234.50");
    });

    testWidgets("the words either side are the counter's, not the number's",
        (tester) async {
      var controller = await panel(tester);
      await enterValue(
          tester, find.byKey(const ValueKey("counterBefore")), "£");
      await tester.pumpAndSettle();
      expect(counterIn(controller).before, "£");
      expect(counterIn(controller).textFor(12), "£12");
    });

    testWidgets("the two ends can be pinned where the playhead is",
        (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      controller.frame = 0;
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const ValueKey("counterPinFrom")));
      controller.frame = 24;
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const ValueKey("counterPinTo")));

      controller.frame = 12;
      expect(
          controller.valueAt(counterIn(controller), KeyframeChannel.count, -1),
          closeTo(50, 0.001),
          reason: "half way along, half way through the count");

      // And pinning a number says nothing about where the element is. It used
      // to: the seed keyframe is a resting pose, which is how a track says it
      // has been animated in space -- so the position, size, angle and fade
      // diamond lit up and every later drag wrote a pose.
      expect(counterIn(controller).track?.posesAnything, isFalse);
      await shut();
    });

    testWidgets("and a point in between is another keyframe", (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      controller.frame = 10;
      await tester.pumpAndSettle();
      await enterValue(
          tester, find.byKey(const ValueKey("counterPointValue")), "140");
      await tester.pumpAndSettle();

      expect(counterIn(controller).track?.keyAt(10), isNotNull);
      expect(
          controller.valueAt(counterIn(controller), KeyframeChannel.count, -1),
          140,
          reason: "a point can be higher than either end");
      await shut();
    });

    testWidgets("and one easing can be given to every point", (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      for (var frame in [0, 6, 12]) {
        controller.frame = frame;
        await tester.pumpAndSettle();
        await press(tester, find.byKey(const ValueKey("counterAddPoint")));
      }

      controller.frame = 6;
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const ValueKey("counterEasing")));
      await press(tester, find.text("Hold (stays the same)").last);
      await press(tester, find.byKey(const ValueKey("counterEasingAll")));

      var track = counterIn(controller).track!;
      for (var frame in [0, 6, 12]) {
        expect(track.keyAt(frame)?.easing, KeyframeEasing.hold,
            reason: "frame $frame");
      }
      await shut();
    });

    testWidgets("and each point says how the number leaves it", (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      controller.frame = 6;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("counterEasing")), findsNothing,
          reason: "no keyframe here, so nothing to ease out of");

      await press(tester, find.byKey(const ValueKey("counterPinFrom")));
      var easing = find.byKey(const ValueKey("counterEasing"));
      expect(easing, findsOneWidget);

      await press(tester, easing);
      await press(tester, find.text("Hold (stays the same)").last);
      expect(
          counterIn(controller).track?.keyAt(6)?.easing, KeyframeEasing.hold);
      expect(
          counterIn(controller).track?.keyAt(6)?.values[KeyframeChannel.count],
          0,
          reason: "and the number it pins is still there");
      await shut();
    });

    testWidgets("switching the keyframes off offers the live settings instead",
        (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);
      expect(find.byKey(const ValueKey("counterPinFrom")), findsOneWidget);
      expect(find.byKey(const ValueKey("counterRate")), findsNothing);

      await press(tester, find.byKey(const ValueKey("counterKeyed")));
      expect(counterIn(controller).live, isTrue);
      expect(find.byKey(const ValueKey("counterPinFrom")), findsNothing);
      expect(find.byKey(const ValueKey("counterRate")), findsOneWidget);
      expect(find.byKey(const ValueKey("counterLoop")), findsOneWidget);
      await shut();
    });

    testWidgets("and asking for the time writes it the way a clock is written",
        (tester) async {
      // A clock written plainly is a number of seconds since midnight, which
      // is not a thing anybody wants to read.
      var controller =
          await panel(tester, shape: (e) => e.copyWith(keyed: false));
      var shut = await showCount(tester);

      await press(tester, find.byKey(const ValueKey("counterSource")));
      await press(tester, find.text("The time").last);
      expect(counterIn(controller).source, CounterSource.clock);
      expect(counterIn(controller).separator.isTime, isTrue);
      await shut();
    });

    testWidgets("the number's spacing and the words' placing are offered",
        (tester) async {
      // Both of these went missing once: they live inside the two type
      // sections rather than in a group of their own, and a section nobody
      // opens is a setting nobody has.
      var controller = await panel(tester);
      await openFold(tester, "counterNumberType",
          shows: find.byKey(const ValueKey("counterGap")));
      expect(find.byKey(const ValueKey("counterGap")), findsOneWidget);
      await enterValue(tester, find.byKey(const ValueKey("counterGap")), "1.5");
      await tester.pumpAndSettle();
      expect(counterIn(controller).gap, 1.5);

      await openFold(tester, "counterAffixType",
          shows: find.byKey(const ValueKey("counterLoose")));
      expect(find.byKey(const ValueKey("counterLoose")), findsOneWidget);
      expect(find.byKey(const ValueKey("counterBeforeAtX")), findsNothing);

      await press(tester, find.byKey(const ValueKey("counterLoose")));
      expect(counterIn(controller).loose, isTrue);
      for (var key in [
        "counterBeforeAtX",
        "counterBeforeAtY",
        "counterAfterAtX",
        "counterAfterAtY",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }

      await enterValue(
          tester, find.byKey(const ValueKey("counterAfterAtY")), "0.3");
      await tester.pumpAndSettle();
      expect(counterIn(controller).afterAt.dy, 0.3);
      expect(counterIn(controller).beforeAt.dy, 0,
          reason: "one word, not both");
    });

    testWidgets("the buttons are switched on one at a time", (tester) async {
      var controller =
          await panel(tester, shape: (e) => e.copyWith(keyed: false));
      expect(counterIn(controller).buttons, isEmpty);

      await press(
          tester, find.byKey(const ValueKey("counterButton-startStop")));
      await press(tester, find.byKey(const ValueKey("counterButton-input")));
      expect(counterIn(controller).buttons,
          [CounterButton.startStop, CounterButton.input],
          reason: "kept in the order they are declared in, not switched on");

      await press(
          tester, find.byKey(const ValueKey("counterButton-startStop")));
      expect(counterIn(controller).buttons, [CounterButton.input]);
    });
  });

  group("the settings' layout", () {
    // Six clusters of small controls down one narrow column, separated by nine
    // pixels of nothing, ran together into one field of boxes: the caption
    // over each was the only thing saying where one ended, and a caption is
    // nine pixels tall and grey.

    testWidgets("a group is a card of its own, in a section", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      expect(find.byType(CanvasControlGroup), findsWidgets);
      // A card says where one group ends and the next begins; a rule under
      // each as well would be the same thing said twice.
      expect(
          find.descendant(
              of: find.byType(CanvasSection),
              matching: find.byType(CanvasGroupRule)),
          findsNothing);
    });

    testWidgets("the background's settings are not captioned Background",
        (tester) async {
      // The header says it. A caption underneath repeating it was the word
      // twice, and the background is what the panel shows whenever nothing is
      // selected -- so it was the commonest thing on the panel.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));

      expect(find.text("BACKGROUND SETTINGS"), findsOneWidget);
      expect(find.text("BACKGROUND"), findsNothing);
      expect(find.text("Style"), findsOneWidget,
          reason: "and its controls are still there");
    });

    testWidgets("a path's points are not folded away", (tester) async {
      // They are the thing anybody opens a path's settings for, and a section
      // that has to be opened first is a press paid every time.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.path, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      // Its group's name is in small capitals in the rebuilt panel.
      expect(find.textContaining(RegExp(r"points \(", caseSensitive: false)),
          findsOneWidget,
          reason: "a card with its count in the name, not a fold");
      expect(find.byKey(ValueKey("node-frame-0-${element.id}")), findsOneWidget,
          reason: "and the first point's row is already showing");
    });

    testWidgets("the panel's header names what is being edited",
        (tester) async {
      // The settings used to head themselves with the element's name, three
      // lines above a group with the same name again. The header says it now,
      // and says it usefully: "Shape settings" rather than a phrase that is
      // true of everything.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));

      expect(find.text("BACKGROUND SETTINGS"), findsOneWidget,
          reason: "with nothing selected, that is what these are");

      controller.selectOnly(element.id);
      await tester.pumpAndSettle();
      expect(find.text("SHAPE SETTINGS"), findsOneWidget);
      expect(find.text("ELEMENT SETTINGS"), findsNothing);
    });

    testWidgets("and a group does not say it again", (tester) async {
      // A panel headed "Shape settings" over a group captioned "Shape" over a
      // control labelled "Shape" is the same word three times in four lines.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      expect(find.text("SHAPE"), findsNothing,
          reason: "the group caption is gone; the header carries the name");
      // The control that chooses which shape keeps its own label. The other
      // two "Shape"s in the column are the chip that adds one and the layer
      // row that names it, neither of which is this panel repeating itself.
      expect(find.byKey(const ValueKey("shapeKind-rectangle")), findsOneWidget,
          reason: "chosen from tiles, each the shape itself");
    });

    testWidgets("a field that explains itself has no caption", (tester) async {
      // "Label" over a field captioned "Text inside" was the same instruction
      // twice. The empty field says what it is for.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      expect(find.text("Text inside"), findsNothing);
      expect(find.text("Type text on the shape"), findsOneWidget);
    });

    testWidgets("the element's own name is not said twice", (tester) async {
      // The settings are headed with it already, so the group caption under
      // that heading said "Chart" directly under "Chart".
      var document = const CanvasDocument();
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10"),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, designSidebar(controller));

      // Not at all in the settings themselves: the panel's header says it.
      expect(find.text("CHART"), findsNothing);
      expect(find.text("CHART SETTINGS"), findsOneWidget);
      // Wherever else the word appears in the column -- the layer row that
      // names the element, the Add chip that makes one -- it is not the
      // caption this test is about. How many of those are on screen depends
      // on what fits under the settings, so what is pinned is that the one
      // inside the layer row is there and the caption is not.
      expect(find.text("Chart"), findsAtLeastNWidgets(1));
      expect(
          find.descendant(
              of: find.byType(CanvasLayerRow), matching: find.text("Chart")),
          findsOneWidget);
    });
  });

  group("the outline settings", () {
    // The outline's own Feather: the mask's edge has one too.
    Finder outlineFeather() => find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is CanvasControlGroup && w.label == "Outline"),
        matching: find.text("Feather"));

    Future<CanvasController> panel(WidgetTester tester,
        {ImageOutline outline = const ImageOutline(),
        String assetId = "abcdefghijklmnop"}) async {
      var element = ImageElement(
        const ElementBase(id: "i", width: 200, height: 200),
        assetId: assetId,
        outline: outline,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      await pump(tester, designSidebar(controller));
      if (assetId.isNotEmpty) {
        await openSection(tester, "image.picture.effects");
      }
      return controller;
    }

    testWidgets("the width is the only control until there is a width",
        (tester) async {
      // The width is also the off switch, so everything else is noise while
      // it is zero -- and a colour and a style sitting there doing nothing is
      // how a reader concludes the feature is broken.
      await panel(tester);

      expect(find.text("Width"), findsOneWidget);
      expect(find.byKey(const ValueKey("imageOutlineColour")), findsNothing);
      expect(outlineFeather(), findsNothing);
    });

    testWidgets("with a width, it offers a colour, a style and a feather",
        (tester) async {
      await panel(tester, outline: const ImageOutline(width: 4));

      expect(find.byKey(const ValueKey("imageOutlineColour")), findsOneWidget);
      expect(outlineFeather(), findsOneWidget);
      expect(find.byType(CanvasDropdown<OutlineStyle>), findsOneWidget);
    });

    testWidgets("typing a width turns it on", (tester) async {
      var controller = await panel(tester);
      var width = find.ancestor(
          of: find.text("Width"), matching: find.byType(CanvasNumberField));

      await typeInto(tester, width, "6");

      var element = controller.document.elements.single as ImageElement;
      expect(element.outline.width, 6);
      expect(element.outline.on, isTrue);
    });

    testWidgets("a picture's size can be changed after it is already in",
        (tester) async {
      // The width, quality and format controls are offered on the way in, and
      // only above half a megabyte, so a reader who wanted them for a smaller
      // picture -- or who took a size on the way in and thought better of it
      // -- had nowhere to go.
      const tooltip = "Change this picture's size and quality";
      await panel(tester);
      expect(byTip(tooltip), findsOneWidget);

      await panel(tester, assetId: "");
      expect(byTip(tooltip), findsNothing,
          reason: "nothing to resize until there is a picture");
    });

    testWidgets("there is nothing to outline without a picture",
        (tester) async {
      await panel(tester, assetId: "");
      expect(find.text("Width"), findsNothing);
    });
  });

  group("the remove-background settings", () {
    // Within the logos-and-scans group: the mask tools beside it have a
    // Brush and an Invert of their own.
    Finder text(String words) => find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is CanvasControlGroup && w.label == "Logos and scans"),
        matching: find.text(words));

    Future<CanvasController> panel(WidgetTester tester,
        {BackgroundRemoval removal = const BackgroundRemoval()}) async {
      var element = ImageElement(
        const ElementBase(id: "i", width: 200, height: 200),
        assetId: "abcdefghijklmnop",
        removal: removal,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      await pump(tester, designSidebar(controller));
      await openSection(tester, "image.picture.mask");
      return controller;
    }

    testWidgets("the removal brushes are the mask tools now, on any picture",
        (tester) async {
      // The rub-out, cut-around and put-back brushes worked on the base
      // picture alone and asked for numbers nobody could read off a
      // photograph. The mask tools replace them, on every layer, a pick of a
      // layer away.
      var controller = await panel(tester);
      expect(byTip("Rub the background out by hand"), findsNothing);
      expect(byTip("Put back what was taken by mistake"), findsNothing);

      controller.editImage("i");
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("imageTool-brush")), findsOneWidget);
      expect(find.byKey(const ValueKey("imageTool-subject")), findsOneWidget);
      expect(find.byKey(const ValueKey("imageTool-lasso")), findsOneWidget);
    });

    testWidgets("turning a brush on offers its size, hardness and cling",
        (tester) async {
      var controller = await panel(tester);
      expect(text("Brush"), findsNothing,
          reason: "not until there is a brush in hand");

      controller.retouch = RetouchBrush.erase;
      await tester.pumpAndSettle();

      expect(text("Brush"), findsOneWidget);
      expect(text("Hardness"), findsOneWidget);
      expect(text("Cling"), findsOneWidget);
    });

    testWidgets("the cut offers to take the other side of the line",
        (tester) async {
      var controller = await panel(tester);
      const outward = "Taking what is outside the line — press to take what "
          "is inside";
      const inward = "Taking what is inside the line — press to take what "
          "is outside";

      expect(byTip(outward), findsNothing,
          reason: "only the cut has two sides to choose between");

      controller.retouch = RetouchBrush.cutAround;
      await tester.pumpAndSettle();

      expect(byTip(outward), findsOneWidget);
      expect(byTip("Cling"), findsNothing);

      await tester.ensureVisible(byTip(outward));
      await tester.pumpAndSettle();
      await tester.tap(byTip(outward));
      await tester.pumpAndSettle();

      expect(controller.cutInside, isTrue);
      expect(byTip(inward), findsOneWidget);
    });

    testWidgets("a marking brush offers neither hardness nor cling",
        (tester) async {
      // A hint is a sample rather than a mark on the picture, so it is taken
      // exactly where it was drawn.
      var controller = await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.learn));
      controller.retouch = RetouchBrush.markBackground;
      await tester.pumpAndSettle();

      expect(text("Brush"), findsOneWidget);
      expect(text("Hardness"), findsNothing);
      expect(text("Cling"), findsNothing);
    });

    testWidgets("the marking brushes appear with the method that uses them",
        (tester) async {
      await panel(tester);
      expect(
          byTip("Mark some background — draw over a few parts "
              "that should go"),
          findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.learn));
      expect(
          byTip("Mark some background — draw over a few parts "
              "that should go"),
          findsOneWidget);
      expect(
          byTip("Mark the subject — draw over a few parts that "
              "should stay"),
          findsOneWidget);
    });

    testWidgets("undo and clear appear once something has been painted",
        (tester) async {
      await panel(tester);
      expect(byTip("Undo the last brush stroke"), findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(strokes: [
            RemovalStroke(points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
          ]));
      expect(byTip("Undo the last brush stroke"), findsOneWidget);
      expect(byTip("Clear every brush stroke"), findsOneWidget);
    });

    testWidgets("a picture worked on by hand is offered no method settings",
        (tester) async {
      // They were shown whenever anything was being removed, which includes a
      // picture the brush alone has been used on -- so somebody working by
      // hand was offered a tolerance and a softness that nothing reads.
      await panel(tester,
          removal: const BackgroundRemoval(strokes: [
            RemovalStroke(points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
          ]));

      expect(text("Softness"), findsNothing);
      expect(text("Tolerance"), findsNothing);
      expect(text("Spread"), findsNothing);
      expect(text("Invert"), findsNothing);
      // The brush's own are still there.
      expect(byTip("Undo the last brush stroke"), findsOneWidget);
    });

    testWidgets("the brightness method is offered no tolerance",
        (tester) async {
      // It cuts at a threshold and never reads one.
      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.luminance));
      expect(text("Threshold"), findsOneWidget);
      expect(text("Tolerance"), findsNothing);
      expect(text("Softness"), findsOneWidget);
    });

    testWidgets("a method's own settings stay behind the method",
        (tester) async {
      await panel(tester);
      expect(text("Edge"), findsNothing);
      expect(text("Spread"), findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.cornerFlood));
      expect(text("Edge"), findsOneWidget);
      expect(text("Spread"), findsOneWidget);
    });
  });

  group("locking an element's proportions", () {
    // The lock is about the shape, not about the size: it must not stop a
    // resize, only stop one from changing the proportions.
    Future<CanvasController> panel(WidgetTester tester,
        {bool locked = false}) async {
      var document = const CanvasDocument();
      var element = ShapeElement(
        ElementBase(
            id: "s", x: 0, y: 0, width: 200, height: 100, lockAspect: locked),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("s");
      await pump(tester, designSidebar(controller));
      return controller;
    }

    ElementBase baseIn(CanvasController c) => c.document.elements.single.base;

    testWidgets("unlocked, the two numbers are free of each other",
        (tester) async {
      var controller = await panel(tester);
      await typeNumber(tester, "elementW", "400");

      expect(baseIn(controller).width, 400);
      expect(baseIn(controller).height, 100, reason: "the height stayed");
    });

    testWidgets("locked, the height follows the width", (tester) async {
      var controller = await panel(tester, locked: true);
      await typeNumber(tester, "elementW", "400");

      expect(baseIn(controller).width, 400);
      expect(baseIn(controller).height, 200,
          reason: "twice as wide, so twice as tall -- 2:1 either way");
    });

    testWidgets("and the width follows the height", (tester) async {
      var controller = await panel(tester, locked: true);
      await typeNumber(tester, "elementH", "50");

      expect(baseIn(controller).height, 50);
      expect(baseIn(controller).width, 100);
    });

    testWidgets("the lock is a button beside the two numbers it holds",
        (tester) async {
      var controller = await panel(tester);
      expect(find.byIcon(Icons.link_off), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.link_off));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.link_off));
      await tester.pumpAndSettle();
      expect(baseIn(controller).lockAspect, isTrue);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets("it does not stop a resize, it only holds the shape",
        (tester) async {
      // The whole of what it is for. Refusing the edit would be a lock that
      // stopped the element being resized at all.
      var controller = await panel(tester, locked: true);
      var before = baseIn(controller).width;
      await typeNumber(tester, "elementW", "500");
      expect(baseIn(controller).width, isNot(before));
    });
  });

  group("a dropdown's ink", () {
    testWidgets("is painted by a Material of its own", (tester) async {
      // Ink -- the splash, and the highlight a focused control keeps -- is
      // painted by the nearest Material *ancestor*, in that ancestor's
      // coordinates and clipped to it. With the sidebar's Material as the
      // nearest, the highlight left behind by choosing a chart type was drawn
      // at the dropdown's place in the sidebar and stayed there: a grey box
      // floating over the Add panel while the settings scrolled underneath.
      await pump(
        tester,
        CanvasDropdown<int>(
          label: "Type",
          value: 1,
          options: const [(1, "Bars"), (2, "Lines")],
          onChanged: (_) {},
        ),
      );

      var inside = find.descendant(
          of: find.byType(CanvasDropdown<int>),
          matching: find.byType(Material));
      expect(inside, findsWidgets,
          reason: "without one, the ink is the sidebar's to paint");
      expect(
          find.descendant(
              of: inside.last, matching: find.byType(DropdownButton<int>)),
          findsOneWidget);
    });
  });
}

/// _openPlayers opens a team's squad list, if it is shut: an expander opened
/// earlier in the file is remembered open, and tapping it again shuts it.
Future<void> _openPlayers(WidgetTester tester) async {
  var rows = find.byWidgetPredicate((w) =>
      w.key is ValueKey &&
      "${(w.key as ValueKey).value}".startsWith("player-0-"));
  if (rows.evaluate().isNotEmpty) return;
  await tester.ensureVisible(find.text("PLAYERS"));
  await tester.pumpAndSettle();
  await tester.tap(find.text("PLAYERS"));
  await tester.pumpAndSettle();
}
