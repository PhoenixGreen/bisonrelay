import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/design_device.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';

import 'support/canvas_app.dart';
import 'support/canvas_panel_helpers.dart';
import 'support/canvas_sidebar_host.dart';
import 'support/panel_rows.dart';

// canvas_shape_line_path_panels_test.dart is a shape's, a line's and a
// path's settings, used in the real sidebar: a stroke's controls in the
// quick strip and in Look are one control twice, with the model's range; a
// line's Layout reads and sets the line as it is drawn, turned or slanted;
// a closed path offers no ends, and its run is told and timed round to its
// start; a follower gone from the canvas is shown as missing; a square or a
// circle keeps its box square by its kind, held; Scale inside says
// what it scales on each; what the Chain's Design table writes stays
// within the same ranges; and
// every control of the three, pressed or set, changes what it says in one
// undo step (_rows: a new control is one row there).

/// _drawn is where [line]'s two ends are drawn on the page as it rests.
(Offset, Offset) _drawn(LineElement line) =>
    (line.curveOnPage.first, line.curveOnPage.last);

double _degrees(Offset d) => math.atan2(d.dy, d.dx) * 180 / math.pi;

void main() {
  // Each test from a panel as a new run has it, every section open.
  setUp(() {
    forgetPanelsForTest();
    forgetSectionsForTest();
    CanvasSection.openAll = true;
  });
  tearDownAll(() => CanvasSection.openAll = false);

  LineElement lineIn(CanvasController c) =>
      c.document.elementById("l") as LineElement;

  group("a stroke's twin controls", () {
    final line = LineElement(
        const ElementBase(id: "l", x: 100, y: 300, width: 300, height: 100),
        strokeWidth: 6);
    final path = PathElement(
        const ElementBase(id: "p", x: 100, y: 300, width: 300, height: 200),
        nodes: PathElement.defaultNodes(frames: 96));

    for (var e in <StrokedElement>[line, path]) {
      var kind = e.kind.label;
      testWidgets("a $kind's two width controls offer the model's range",
          (tester) async {
        await showPanel(tester, e);
        const range = (StrokeRange.minWidth, StrokeRange.maxWidth);
        expect(rangeOf(tester, stepperIn(quickStrip, "Width")), range);
        expect(rangeOf(tester, numberIn(lookSection, "Width")), range);
      });

      testWidgets("a $kind's dash and end size offer the model's range",
          (tester) async {
        await showPanel(tester, e);
        expect(rangeOf(tester, numberIn(lookSection, "Dash")),
            (0.0, StrokeRange.maxDash));
        expect(rangeOf(tester, numberIn(lookSection, "End size")),
            (StrokeRange.minEndSize, StrokeRange.maxEndSize));
      });

      testWidgets("a $kind's quick colour offers the fade its Look's does",
          (tester) async {
        await showPanel(tester, e);
        var quick =
            tester.widget<CanvasColorButton>(colourIn(quickStrip, "Colour"));
        var look =
            tester.widget<CanvasColorButton>(colourIn(lookSection, "Colour"));
        expect(look.onGradientChanged, isNotNull);
        expect(quick.onGradientChanged, isNotNull);
      });
    }

    testWidgets("a line's quick dash offers the model's range too",
        (tester) async {
      await showPanel(tester, line);
      expect(rangeOf(tester, stepperIn(quickStrip, "Dash")),
          (0.0, StrokeRange.maxDash));
    });

    testWidgets("a shape's two outline widths go from none to the most",
        (tester) async {
      await showPanel(tester,
          const ShapeElement(ElementBase(id: "s", width: 200, height: 120)));
      const range = (0.0, StrokeRange.maxWidth);
      expect(rangeOf(tester, stepperIn(quickStrip, "Outline")), range);
      expect(rangeOf(tester, numberIn(lookSection, "Stroke")), range);
    });

    testWidgets(
        "a shape's quick outline colour offers the fade its Look's does",
        (tester) async {
      var c = await showPanel(tester,
          const ShapeElement(ElementBase(id: "s", width: 200, height: 120)));
      var quick = tester
          .widget<CanvasColorButton>(colourIn(quickStrip, "Outline colour"));
      expect(quick.onGradientChanged, isNotNull);
      // And a fade asked for on a shape with no outline gives it one, as
      // its colour does.
      quick.onGradientChanged!(
          const GradientSpec(to: Color(0xFF00FF00), angle: 0));
      await tester.pumpAndSettle();
      var s = c.document.elementById("s") as ShapeElement;
      expect(s.strokeFade, isNotNull);
      expect(s.strokeWidth, greaterThan(0));
    });
  });

  group("a closed path", () {
    PathElement path({required bool closed}) => PathElement(
        const ElementBase(id: "p", x: 100, y: 300, width: 300, height: 200),
        nodes: PathElement.defaultNodes(frames: 96),
        closed: closed,
        startEnd: LineEnd.circle);

    testWidgets("offers no ends, since it draws none", (tester) async {
      await showPanel(tester, path(closed: true));
      expect(dropdownIn(lookSection, "Start"), findsNothing);
      expect(dropdownIn(lookSection, "End"), findsNothing);
      expect(numberIn(lookSection, "End size"), findsNothing);
      expect(dropdownIn(lookSection, "Stroke end"), findsOneWidget,
          reason: "a dash still has a cap on each of its own ends");
    });

    testWidgets("and offers them again once it is opened", (tester) async {
      var c = await showPanel(tester, path(closed: true));
      await pressOn(
          tester,
          widgetIn<CanvasToggle>(
              quickStrip, (w) => w.key == const ValueKey("quickPathClosed")));
      expect((c.document.elementById("p") as PathElement).closed, isFalse);
      expect(dropdownIn(lookSection, "Start"), findsOneWidget);
      expect(dropdownIn(lookSection, "End"), findsOneWidget);
      expect(numberIn(lookSection, "End size"), findsOneWidget);
    });

    group("followed", () {
      // Ten frames a side; round to the start again by frame 30.
      final followed = PathElement(
          const ElementBase(id: "p", x: 100, y: 300, width: 300, height: 200),
          nodes: [
            for (var (i, n) in PathElement.defaultNodes(frames: 96).indexed)
              n.copyWith(frame: i * 10),
          ],
          closed: true,
          follow: const PathFollow(elementId: "f"));
      const runner = TextElement(ElementBase(id: "f", name: "Runner"));

      testWidgets("its run is said to end back at its start", (tester) async {
        await showPanel(tester, followed, beside: [runner]);
        expect(find.textContaining("frames 0–30"), findsOneWidget);
        expect(
            tester.widget<CanvasNumberField>(keyed("pathEndFrame")).value, 30);
      });

      testWidgets("a run longer than the scene is said to end with it",
          (tester) async {
        // Its last point on the scene's last frame: no frames to go round.
        var late = followed.copyWith(nodes: [
          for (var (i, n) in followed.nodes.indexed)
            n.copyWith(frame: const [0, 48, 95][i]),
        ]);
        await showPanel(tester, late, beside: [runner]);
        expect(find.textContaining("frames 0–95"), findsOneWidget);
        expect(
            tester.widget<CanvasNumberField>(keyed("pathEndFrame")).value, 95);
      });

      testWidgets("its last point is not called the end of the run",
          (tester) async {
        await showPanel(tester, followed, beside: [runner]);
        expect(tester.widget<CanvasNumberField>(keyed("node-frame-2-p")).label,
            "Frame");
      });

      testWidgets("its last point offers a point after it", (tester) async {
        await showPanel(tester, followed, beside: [runner]);
        expect(
            tester
                .widget<CanvasIconButton>(_nodeButton(2, Icons.add))
                .onPressed,
            isNotNull);
      });
    });
  });

  group("a follower no longer on the canvas", () {
    var path = PathElement(
        const ElementBase(id: "p", x: 100, y: 300, width: 300, height: 200),
        nodes: PathElement.defaultNodes(frames: 96),
        follow: const PathFollow(elementId: "gone"));
    const runner = TextElement(ElementBase(id: "f", name: "Runner"));
    Finder whoFollows() => dropdownIn("elementSection-more", "Who follows");
    List<PathFollow> offered(WidgetTester tester) => [
          for (var (v, _) in tester
              .widget<CanvasDropdown<PathFollow>>(whoFollows())
              .options)
            v
        ];

    testWidgets("is shown in Who follows as missing", (tester) async {
      await showPanel(tester, path, beside: [runner]);
      expect(find.descendant(of: whoFollows(), matching: find.text("Missing")),
          findsOneWidget);
    });

    testWidgets("and choosing it again changes nothing", (tester) async {
      var c = await showPanel(tester, path, beside: [runner]);
      var before = c.document;
      await chosen(whoFollows(), const PathFollow(elementId: "gone"))(tester);
      await tester.pumpAndSettle();
      expect(c.document, same(before));
    });

    testWidgets("and is not offered once another is chosen", (tester) async {
      var c = await showPanel(tester, path, beside: [runner]);
      await chosen(whoFollows(), const PathFollow(elementId: "f"))(tester);
      await tester.pumpAndSettle();
      expect((c.document.elementById("p") as PathElement).follow,
          const PathFollow(elementId: "f"));
      expect(offered(tester),
          isNot(contains(const PathFollow(elementId: "gone"))));
    });
  });

  group("a line's Layout", () {
    // Its box slopes one way and it is turned 30 degrees on top: what is
    // drawn points neither way.
    const turned = LineElement(ElementBase(
        id: "l", x: 100, y: 300, width: 300, height: 100, rotation: 30));
    final slanted = turned.withBase(rotation: 0, skewX: 25) as LineElement;

    testWidgets("Level lays a turned line level where it is drawn",
        (tester) async {
      var c = await showPanel(tester, turned);
      var (start, _) = _drawn(turned);
      await pressOn(tester, find.byKey(const ValueKey("lineLevel")));
      var (a, b) = _drawn(lineIn(c));
      expect(b.dy, closeTo(a.dy, 0.05));
      expect((b - a).distance, closeTo(turned.length, 0.05));
      expect(a.dx, closeTo(start.dx, 0.05), reason: "turned about its start");
      expect(a.dy, closeTo(start.dy, 0.05));
    });

    testWidgets("Upright stands a turned line upright where it is drawn",
        (tester) async {
      var c = await showPanel(tester, turned);
      await pressOn(tester, find.byKey(const ValueKey("linePlumb")));
      var (a, b) = _drawn(lineIn(c));
      expect(b.dx, closeTo(a.dx, 0.05));
    });

    testWidgets("Direction shows which way the line is drawn pointing",
        (tester) async {
      await showPanel(tester, turned);
      var (a, b) = _drawn(turned);
      var field = tester
          .widget<CanvasNumberField>(find.byKey(const ValueKey("lineAngle")));
      expect(field.value, closeTo(_degrees(b - a), 0.05));
    });

    testWidgets("and sets it, the start staying where it is drawn",
        (tester) async {
      var c = await showPanel(tester, turned);
      var (start, _) = _drawn(turned);
      await setNumber(tester, find.byKey(const ValueKey("lineAngle")), 90);
      var (a, b) = _drawn(lineIn(c));
      expect(_degrees(b - a), closeTo(90, 0.05));
      expect((a - start).distance, closeTo(0, 0.05));
    });

    testWidgets("Length shows how long a slanted line is drawn",
        (tester) async {
      await showPanel(tester, slanted);
      var (a, b) = _drawn(slanted);
      var field = tester
          .widget<CanvasNumberField>(find.byKey(const ValueKey("lineLength")));
      expect(field.value, closeTo((b - a).distance, 0.05));
    });

    testWidgets("and sets it, keeping where it starts and points",
        (tester) async {
      var c = await showPanel(tester, turned);
      var (start, end) = _drawn(turned);
      await setNumber(tester, find.byKey(const ValueKey("lineLength")), 500);
      var (a, b) = _drawn(lineIn(c));
      expect((b - a).distance, closeTo(500, 0.05));
      expect((a - start).distance, closeTo(0, 0.05));
      expect(_degrees(b - a), closeTo(_degrees(end - start), 0.05));
    });

    testWidgets("its own direction is not a second field called Angle",
        (tester) async {
      await showPanel(tester, turned);
      expect(
          tester
              .widget<CanvasNumberField>(
                  find.byKey(const ValueKey("lineAngle")))
              .label,
          "Direction");
      expect(
          widgetIn<Widget>(
              layoutSection,
              (w) =>
                  (w is CanvasNumberField && w.label == "Angle") ||
                  (w is CanvasStepper && w.label == "Angle")),
          findsOneWidget,
          reason: "the element's turn, the position group's");
    });
  });

  group("a line's ends", () {
    const line = LineElement(
        ElementBase(id: "l", x: 100, y: 300, width: 300, height: 100),
        startEnd: LineEnd.circle,
        endEnd: LineEnd.arrow);

    testWidgets("Swap ends puts each end's mark on the other", (tester) async {
      var c = await showPanel(tester, line);
      await pressOn(tester, find.byKey(const ValueKey("strokeSwapEnds")));
      var after = lineIn(c);
      expect((after.startEnd, after.endEnd), (LineEnd.arrow, LineEnd.circle));
      expect((after.start, after.end), (line.start, line.end),
          reason: "the line itself stays where it is");
    });

    testWidgets("the slope switch says what it does", (tester) async {
      var c = await showPanel(tester, line);
      var toggle = widgetIn<CanvasToggle>(
          lookSection, (w) => w.key == const ValueKey("lineFlipped"));
      expect(tester.widget<CanvasToggle>(toggle).label, "Slope the other way");
      var ends = tester.widget<CanvasControlGroup>(
          widgetIn<CanvasControlGroup>(lookSection, (w) => w.label == "Ends"));
      expect(ends.help, isNot(contains("swaps which end is the start")));
      await pressOn(tester, toggle);
      var after = lineIn(c);
      expect(after.flipped, isTrue);
      expect(after.startEnd, LineEnd.circle,
          reason: "the start keeps its mark, on the left");
      expect(after.start.dx, lessThan(after.end.dx));
    });
  });

  group("a bubble's tail", () {
    testWidgets("is said to point to, not to have points", (tester) async {
      await showPanel(
          tester,
          const ShapeElement(ElementBase(id: "s", width: 200, height: 120),
              shape: ShapeKind.speechBubble));
      expect(
          tester
              .widget<CanvasNumberField>(
                  find.byKey(const ValueKey("bubbleTailAngle")))
              .label,
          "Points to");
    });
  });

  group("a square or a circle", () {
    const oblong = ShapeElement(
        ElementBase(id: "s", x: 100, y: 100, width: 200, height: 120));

    void expectSquared(ShapeElement s) {
      expect(s.width, 120, reason: "its shorter side");
      expect(s.height, 120);
      expect(
          Offset(s.x + s.width / 2, s.y + s.height / 2), const Offset(200, 160),
          reason: "about its middle");
      expect(s.keepsAspect, isTrue, reason: "held square by its kind");
      expect(s.base.lockAspect, isFalse,
          reason: "with nothing saved: the person did not hold it");
    }

    for (var kind in ShapeKind.values.where((k) => k.isRegular)) {
      test("chosen as a ${kind.name}, a box is squared and held", () {
        expectSquared(oblong.withKind(kind));
      });
    }

    test("another kind after it leaves the box and lets it go", () {
      var other = oblong.withKind(ShapeKind.circle).withKind(ShapeKind.ellipse);
      expect((other.width, other.height), (120.0, 120.0));
      expect(other.keepsAspect, isFalse);
    });

    test("a hold the person set is kept through a circle and back", () {
      var held = oblong.withBase(lockAspect: true) as ShapeElement;
      var back = held.withKind(ShapeKind.circle).withKind(ShapeKind.ellipse);
      expect(back.base.lockAspect, isTrue);
      expect(back.keepsAspect, isTrue);
    });

    test("one saved held by its kind reads held, as the person's hold", () {
      var saved = oblong.withKind(ShapeKind.circle).withBase(lockAspect: true)
          as ShapeElement;
      var read = ShapeElement.fromJson(saved.toJson(), saved.base);
      expect(read.base.lockAspect, isTrue);
    });

    test("one regular kind after another keeps it held", () {
      var square = oblong.withKind(ShapeKind.circle).withKind(ShapeKind.square);
      expectSquared(square);
    });

    test("a held box that is not square or round is left held", () {
      var held = oblong.withBase(lockAspect: true) as ShapeElement;
      expect(held.withKind(ShapeKind.star).base.lockAspect, isTrue);
    });

    test("one saved oblong reads as it was saved", () {
      var saved = oblong.copyWith(shape: ShapeKind.circle);
      var read = ShapeElement.fromJson(saved.toJson(), saved.base);
      expect((read.width, read.height), (200.0, 120.0));
      expect(read.base.lockAspect, isFalse);
    });

    test("a new shape from the add menu starts square", () {
      var made = newElement(ElementKind.shape, panelDocument) as ShapeElement;
      expect(made.width, made.height);
      var round = made.withKind(ShapeKind.circle);
      expect((round.x, round.y, round.width, round.height),
          (made.x, made.y, made.width, made.height));
      expect(round.keepsAspect, isTrue);
    });

    testWidgets("picked from the tiles", (tester) async {
      var c = await showPanel(tester, oblong);
      await pressOn(tester, find.byKey(const ValueKey("shapeKind-circle")));
      expectSquared(c.document.elementById("s") as ShapeElement);
    });

    testWidgets("picked from the quick strip", (tester) async {
      var c = await showPanel(tester, oblong);
      tester
          .widget<CanvasDropdown<ShapeKind>>(
              find.byKey(const ValueKey("quickShape")))
          .onChanged(ShapeKind.square);
      await tester.pumpAndSettle();
      expectSquared(c.document.elementById("s") as ShapeElement);
    });

    /// lock is the button that holds the proportions, or lets them go.
    Finder lock() => widgetIn<CanvasIconButton>(
        layoutSection, (w) => w.icon == Icons.link || w.icon == Icons.link_off);

    testWidgets("a circle's proportions show held and cannot be let go",
        (tester) async {
      await showPanel(tester, oblong.withKind(ShapeKind.circle));
      var button = tester.widget<CanvasIconButton>(lock());
      expect(button.icon, Icons.link);
      expect(button.active, isTrue);
      expect(button.onPressed, isNull);
    });

    testWidgets("a rectangle's can still be held and let go", (tester) async {
      var c = await showPanel(tester, oblong);
      expect(tester.widget<CanvasIconButton>(lock()).onPressed, isNotNull);
      await pressOn(tester, lock());
      expect(c.document.elementById("s")!.base.lockAspect, isTrue);
    });

    testWidgets("a circle's width set sets its height, its outline kept",
        (tester) async {
      // A circle saved square by an earlier choice, nothing held.
      const round = ShapeElement(
          ElementBase(id: "s", x: 100, y: 100, width: 120, height: 120),
          shape: ShapeKind.circle,
          strokeWidth: 6);
      var c = await showPanel(tester, round);
      await setNumber(tester, stepperIn(layoutSection, "W"), 200);
      var s = c.document.elementById("s") as ShapeElement;
      expect((s.width, s.height), (200.0, 200.0));
      expect(s.strokeWidth, 6);
    });
  });

  group("Scale inside on another page shape", () {
    /// hint is what the "?" beside Scale inside says for [e], in a canvas
    /// laid out for two page shapes.
    Future<String> hint(WidgetTester tester, CanvasElement e) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(
          const CanvasDocument(targets: ["feedAd", "wide"]).addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      await pumpCanvasApp(tester, designSidebar(c),
          size: const Size(320, 9000));
      await openEverything(tester, find.byType(CanvasSidebarHost));
      expect(find.byKey(const ValueKey("elementTypeScale")), findsOneWidget);
      return tester
          .widgetList<CanvasHint>(find.byType(CanvasHint))
          .map((h) => h.message)
          .singleWhere((m) => m.contains("on the shape of page you are on"));
    }

    const box = ElementBase(id: "e", x: 100, y: 100, width: 200, height: 120);

    testWidgets("names what it scales on a shape", (tester) async {
      var said = await hint(tester, const ShapeElement(box));
      for (var part in ["words", "outline", "corners", "padding"]) {
        expect(said, contains(part));
      }
      expect(said, isNot(contains("rules")));
    });

    for (var e in <CanvasElement>[
      const LineElement(box),
      PathElement(box, nodes: PathElement.defaultNodes()),
    ]) {
      testWidgets("and on a ${e.kind.label.toLowerCase()}", (tester) async {
        var said = await hint(tester, e);
        expect(said, contains("width"));
        expect(said, contains("dashes"));
        expect(said, isNot(contains("type")));
      });
    }

    testWidgets("and on text, as it always has", (tester) async {
      var said = await hint(tester, const TextElement(box, text: "Words"));
      expect(said, contains("the type, the line spacing, the padding"));
    });
  });

  group("the Chain's Design table", () {
    const line = LineElement(ElementBase(id: "l", width: 300, height: 100));
    final path = PathElement(const ElementBase(id: "p", width: 300),
        nodes: PathElement.defaultNodes());
    const shape = ShapeElement(ElementBase(id: "s", width: 200));

    for (var e in <StrokedElement>[line, path]) {
      test("writes a ${e.kind.label}'s stroke within what can be set", () {
        StrokeSpec at(String id, double v) =>
            (designWritten(e, id, v) as StrokedElement).stroke;
        expect(at("stroke", 0).strokeWidth, StrokeRange.minWidth);
        expect(at("stroke", 1e6).strokeWidth, StrokeRange.maxWidth);
        expect(at("endSize", 0).endSize, StrokeRange.minEndSize);
        expect(at("endSize", 1e6).endSize, StrokeRange.maxEndSize);
        expect(at("dash", -5).dash, 0);
        expect(at("dash", 1e6).dash, StrokeRange.maxDash);
        expect(at("stroke", 7).strokeWidth, 7, reason: "and within, as asked");
      });
    }

    test("writes a shape's outline within what can be set", () {
      double at(double v) =>
          (designWritten(shape, "stroke", v) as ShapeElement).strokeWidth;
      expect(at(-5), 0);
      expect(at(1e6), StrokeRange.maxWidth);
      expect(at(7), 7);
    });
  });

  group("at every text size", () {
    // The Swap ends button beside the ends, and Scale inside on a canvas of
    // two page shapes, in the narrow sidebar the panel opens in.
    for (var e in <CanvasElement>[
      const ShapeElement(ElementBase(id: "s", width: 200, height: 120)),
      const LineElement(ElementBase(id: "l", width: 300, height: 100),
          startEnd: LineEnd.circle, endEnd: LineEnd.arrow),
      PathElement(const ElementBase(id: "p", width: 300, height: 200),
          nodes: PathElement.defaultNodes(frames: 96)),
    ]) {
      for (var scale in const [0.65, 1.0, 1.25, 1.5]) {
        testWidgets("a ${e.kind.label.toLowerCase()}'s panel fits at $scale",
            (tester) async {
          setTestTextScale(tester, scale);
          SharedPreferences.setMockInitialValues({});
          var c = CanvasController(
              const CanvasDocument(targets: ["feedAd", "wide"]).addElement(e));
          addTearDown(c.dispose);
          c.selectOnly(e.id);
          await pumpCanvasApp(tester, designSidebar(c),
              size: const Size(300, 9000));
          await openEverything(tester, find.byType(CanvasSidebarHost));
          expect(
              find.byKey(const ValueKey("elementTypeScale")), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group("every control", () => everyControl(_rows()));
}

/// _nodeButton is the button with [icon] on the path's point [i].
Finder _nodeButton(int i, IconData icon) => find.descendant(
    of: find.byKey(ValueKey("path-node-$i-p")),
    matching:
        find.byWidgetPredicate((w) => w is CanvasIconButton && w.icon == icon));

List<ControlRow> _rows() {
  const shape = ShapeElement(
      ElementBase(id: "s", x: 100, y: 100, width: 200, height: 120));
  final star = shape.copyWith(shape: ShapeKind.star);
  final bubble = shape.copyWith(
      shape: ShapeKind.speechBubble,
      bubble: const SpeechBubbleSpec(tail: BubbleTail.curved));
  final split = shape.copyWith(cornerRadius: 8, radTL: 20);
  final worded = shape.copyWith(text: "Hi");
  final padded = shape.copyWith(padding: 8, padT: 20);
  final patterned =
      shape.copyWith(painted: const TextFill(kind: TextFillKind.pattern));
  final pictured = shape.copyWith(
      painted: const TextFill(kind: TextFillKind.image, assetId: "a"));
  const line = LineElement(
      ElementBase(id: "l", x: 100, y: 300, width: 300, height: 100),
      startEnd: LineEnd.circle,
      endEnd: LineEnd.arrow);
  final bowed = line.withBase(
      track: ElementTrack(const [
    Keyframe(frame: 0, values: {KeyframeChannel.bow: 0.2}),
  ])) as LineElement;
  // Unevenly timed, so spacing its points evenly changes them.
  final path = PathElement(
      const ElementBase(id: "p", x: 100, y: 300, width: 300, height: 200),
      nodes: [
        for (var (i, n) in PathElement.defaultNodes(frames: 96).indexed)
          n.copyWith(frame: const [0, 10, 95][i]),
      ],
      startEnd: LineEnd.circle);
  final follower = TextElement(
      const ElementBase(id: "f", x: 40, y: 40, width: 80, height: 40),
      text: "Runner");
  final followed = path.copyWith(follow: const PathFollow(elementId: "f"));
  // Closed and timed ten frames a side but the first, which is three.
  final loop = path.copyWith(closed: true, nodes: [
    for (var (i, n) in path.nodes.indexed)
      n.copyWith(frame: const [0, 3, 13][i]),
  ]);

  ShapeElement shapeIn(CanvasDocument d) => d.elementById("s") as ShapeElement;
  LineElement lineIn(CanvasDocument d) => d.elementById("l") as LineElement;
  PathElement pathIn(CanvasDocument d) => d.elementById("p") as PathElement;

  const row = controlRow;

  return [
    // A shape.
    row(
        "a shape's quick Shape",
        shape,
        chosen(keyed("quickShape"), ShapeKind.ellipse),
        (d) => expect(shapeIn(d).shape, ShapeKind.ellipse)),
    row("a shape's tiles", shape, pressed(keyed("shapeKind-star")),
        (d) => expect(shapeIn(d).shape, ShapeKind.star)),
    row("a shape's quick Fill", shape, coloured(keyed("quickFill")),
        (d) => expect(shapeIn(d).fill, rowRed)),
    row(
        "a shape's quick Fill's fade",
        shape,
        coloured(keyed("quickFill"), fade: true),
        (d) => expect(shapeIn(d).fillFade, rowFade)),
    row(
        "a shape's quick Outline",
        shape,
        typedIn(stepperIn(quickStrip, "Outline"), 5),
        (d) => expect(shapeIn(d).strokeWidth, 5)),
    row("a shape's quick Outline colour", shape,
        coloured(keyed("quickStrokeColour")), (d) {
      expect(shapeIn(d).strokeColor, rowRed);
      expect(shapeIn(d).strokeWidth, greaterThan(0));
    }),
    row(
        "a shape's quick Outline colour's fade",
        shape,
        coloured(keyed("quickStrokeColour"), fade: true),
        (d) => expect(shapeIn(d).strokeFade, rowFade)),
    row("a shape's Fill", shape, coloured(colourIn(lookSection, "Fill")),
        (d) => expect(shapeIn(d).fill, rowRed)),
    row(
        "a shape's Fill's fade",
        shape,
        coloured(colourIn(lookSection, "Fill"), fade: true),
        (d) => expect(shapeIn(d).fillFade, rowFade)),
    row(
        "a shape's Painted with",
        shape,
        chosen(keyed("shapeFillKind"), TextFillKind.pattern),
        (d) => expect(shapeIn(d).painted.kind, TextFillKind.pattern)),
    row("a shape's Stroke", shape, typedIn(numberIn(lookSection, "Stroke"), 7),
        (d) => expect(shapeIn(d).strokeWidth, 7)),
    row(
        "a shape's outline Colour",
        shape,
        coloured(colourIn(lookSection, "Colour")),
        (d) => expect(shapeIn(d).strokeColor, rowRed)),
    row(
        "a shape's outline Colour's fade",
        shape,
        coloured(colourIn(lookSection, "Colour"), fade: true),
        (d) => expect(shapeIn(d).strokeFade, rowFade)),
    row(
        "a star's Points",
        star,
        typedIn(numberIn("elementSection-content", "Points"), 7),
        (d) => expect(shapeIn(d).points, 7)),
    row(
        "a star's Depth",
        star,
        typedIn(numberIn("elementSection-content", "Depth"), 0.6),
        (d) => expect(shapeIn(d).innerRatio, 0.6)),
    row("a shape's Corners", shape, keyTyped("shapeRadius", 12),
        (d) => expect(shapeIn(d).cornerRadius, 12)),
    for (var (glyph, corner) in [
      ("↖", (Corners c) => c.topLeft),
      ("↗", (Corners c) => c.topRight),
      ("↘", (Corners c) => c.bottomRight),
      ("↙", (Corners c) => c.bottomLeft),
    ])
      row("a shape's corner $glyph", split, keyTyped("shapeRadius$glyph", 30),
          (d) => expect(corner(shapeIn(d).corners), 30)),
    row("a shape's corners joined", split, pressed(keyed("shapeRadiusLink")),
        (d) => expect(shapeIn(d).corners.even, 20)),
    row("a shape's Padding", shape, keyTyped("shapePadding", 10),
        (d) => expect(shapeIn(d).padding, 10)),
    for (var (side, room) in [
      ("Top", (Room r) => r.top),
      ("Right", (Room r) => r.right),
      ("Bottom", (Room r) => r.bottom),
      ("Left", (Room r) => r.left),
    ])
      row(
          "a shape's padding at its $side",
          padded,
          keyTyped("shapePad$side", 30),
          (d) => expect(room(shapeIn(d).pad), 30)),
    row("a shape's padding joined", padded, pressed(keyed("shapePaddingLink")),
        (d) => expect(shapeIn(d).pad.even, 20)),
    row(
        "a patterned shape's fill Opacity",
        patterned,
        keyTyped("shapeFillOpacity", 0.5),
        (d) => expect(shapeIn(d).painted.opacity, 0.5)),
    row(
        "a pictured shape's fill Saturation",
        pictured,
        keyTyped("shapeFillSaturation", 2),
        (d) => expect(shapeIn(d).painted.saturation, 2)),
    row("a shape's Words", shape, (tester) async {
      var w = tester.widget<CanvasTextField>(widgetIn<CanvasTextField>(
          "elementSection-content", (w) => w.hint == "Type text on the shape"));
      w.onChanged("Hello");
      w.onCommit?.call();
    }, (d) => expect(shapeIn(d).text, "Hello")),
    row(
        "a shape's label Size",
        worded,
        typedIn(
            find.descendant(
                of: keyed("shapeLabelType"), matching: keyed("typeSize")),
            30),
        (d) => expect(shapeIn(d).textSpec.fontSize, 30)),
    row(
        "a bubble's Body",
        bubble,
        chosen(dropdownIn("elementSection-content", "Body"), BubbleBody.cloud),
        (d) => expect(shapeIn(d).bubble.body, BubbleBody.cloud)),
    row(
        "a bubble's Tail",
        bubble,
        chosen(
            dropdownIn("elementSection-content", "Tail"), BubbleTail.thought),
        (d) => expect(shapeIn(d).bubble.tail, BubbleTail.thought)),
    row("a bubble's Points to", bubble, keyTyped("bubbleTailAngle", 200),
        (d) => expect(shapeIn(d).bubble.tailAngle, 200)),
    row(
        "a bubble's Length",
        bubble,
        typedIn(numberIn("elementSection-content", "Length"), 0.9),
        (d) => expect(shapeIn(d).bubble.tailLength, 0.9)),
    row(
        "a bubble's Width",
        bubble,
        typedIn(numberIn("elementSection-content", "Width"), 0.6),
        (d) => expect(shapeIn(d).bubble.tailWidth, 0.6)),
    row(
        "a bubble's Curl",
        bubble,
        typedIn(numberIn("elementSection-content", "Curl"), 1),
        (d) => expect(shapeIn(d).bubble.curl, 1)),

    // A line.
    row("a line's quick Colour", line, coloured(keyed("quickLineColour")),
        (d) => expect(lineIn(d).color, rowRed)),
    row(
        "a line's quick Colour's fade",
        line,
        coloured(keyed("quickLineColour"), fade: true),
        (d) => expect(lineIn(d).fade, rowFade)),
    row("a line's quick Width", line, keyTyped("quickLineWidth", 9),
        (d) => expect(lineIn(d).strokeWidth, 9)),
    row(
        "a line's quick End",
        line,
        chosen(keyed("quickLineEnd"), LineEnd.diamond),
        (d) => expect(lineIn(d).endEnd, LineEnd.diamond)),
    row("a line's quick Dash", line, keyTyped("quickLineDash", 15),
        (d) => expect(lineIn(d).dash, 15)),
    row("a line's Colour", line, coloured(colourIn(lookSection, "Colour")),
        (d) => expect(lineIn(d).color, rowRed)),
    row(
        "a line's Colour's fade",
        line,
        coloured(colourIn(lookSection, "Colour"), fade: true),
        (d) => expect(lineIn(d).fade, rowFade)),
    row("a line's Width", line, typedIn(numberIn(lookSection, "Width"), 11),
        (d) => expect(lineIn(d).strokeWidth, 11)),
    row("a line's Curve", line, typedIn(numberIn(lookSection, "Curve"), 0.4),
        (d) => expect(lineIn(d).curvature, 0.4)),
    row("a line's keyed Curve", bowed,
        typedIn(numberIn(lookSection, "Curve"), 0.4), (d) {
      expect(lineIn(d).track!.keyAt(0)!.values[KeyframeChannel.bow], 0.4);
      expect(lineIn(d).curvature, 0, reason: "the key, not where it rests");
    }),
    row(
        "a line's Curve diamond",
        line,
        pressed(widgetIn<CanvasKeyframeDot>(lookSection, (_) => true)),
        (d) =>
            expect(lineIn(d).track!.keyAt(0)!.values[KeyframeChannel.bow], 0)),
    row(
        "a line's Stroke end",
        line,
        chosen(dropdownIn(lookSection, "Stroke end"), LineStrokeCap.round),
        (d) => expect(lineIn(d).cap, LineStrokeCap.round)),
    row(
        "a line's Start",
        line,
        chosen(dropdownIn(lookSection, "Start"), LineEnd.square),
        (d) => expect(lineIn(d).startEnd, LineEnd.square)),
    row(
        "a line's End",
        line,
        chosen(dropdownIn(lookSection, "End"), LineEnd.bar),
        (d) => expect(lineIn(d).endEnd, LineEnd.bar)),
    row(
        "a line's End size",
        line,
        typedIn(numberIn(lookSection, "End size"), 3),
        (d) => expect(lineIn(d).endSize, 3)),
    row(
        "a line's Swap ends",
        line,
        pressed(keyed("strokeSwapEnds")),
        (d) => expect((lineIn(d).startEnd, lineIn(d).endEnd),
            (LineEnd.arrow, LineEnd.circle))),
    row("a line's Slope the other way", line, switched(keyed("lineFlipped")),
        (d) => expect(lineIn(d).flipped, isTrue)),
    row("a line's Dash", line, keyTyped("lineDash", 8),
        (d) => expect(lineIn(d).dash, 8)),
    row("a line's Length", line, keyTyped("lineLength", 250),
        (d) => expect(lineIn(d).length, closeTo(250, 1e-6))),
    row("a line's Direction", line, keyTyped("lineAngle", 45),
        (d) => expect(lineIn(d).angle, closeTo(45, 1e-6))),
    row("a line's Level", line, pressed(keyed("lineLevel")),
        (d) => expect(lineIn(d).angle, closeTo(0, 0.01))),
    row("a line's Upright", line, pressed(keyed("linePlumb")),
        (d) => expect(lineIn(d).angle, closeTo(90, 0.01))),

    // A path.
    row("a path's quick Colour", path, coloured(keyed("quickPathColour")),
        (d) => expect(pathIn(d).color, rowRed)),
    row(
        "a path's quick Colour's fade",
        path,
        coloured(keyed("quickPathColour"), fade: true),
        (d) => expect(pathIn(d).fade, rowFade)),
    row("a path's quick Width", path, keyTyped("quickPathWidth", 4),
        (d) => expect(pathIn(d).strokeWidth, 4)),
    row("a path's quick Closed", path, switched(keyed("quickPathClosed")),
        (d) => expect(pathIn(d).closed, isTrue)),
    row("a path's Colour", path, coloured(colourIn(lookSection, "Colour")),
        (d) => expect(pathIn(d).color, rowRed)),
    row(
        "a path's Colour's fade",
        path,
        coloured(colourIn(lookSection, "Colour"), fade: true),
        (d) => expect(pathIn(d).fade, rowFade)),
    row("a path's Width", path, typedIn(numberIn(lookSection, "Width"), 6),
        (d) => expect(pathIn(d).strokeWidth, 6)),
    row(
        "a path's Closed",
        path,
        switched(
            widgetIn<CanvasToggle>(lookSection, (w) => w.label == "Closed")),
        (d) => expect(pathIn(d).closed, isTrue)),
    row(
        "a path's Guide only",
        path,
        switched(widgetIn<CanvasToggle>(
            lookSection, (w) => w.label == "Guide only")),
        (d) => expect(pathIn(d).guide, isTrue)),
    row(
        "a path's Stroke end",
        path,
        chosen(dropdownIn(lookSection, "Stroke end"), LineStrokeCap.square),
        (d) => expect(pathIn(d).cap, LineStrokeCap.square)),
    row(
        "a path's Start",
        path,
        chosen(dropdownIn(lookSection, "Start"), LineEnd.diamond),
        (d) => expect(pathIn(d).startEnd, LineEnd.diamond)),
    row(
        "a path's End",
        path,
        chosen(dropdownIn(lookSection, "End"), LineEnd.hollowArrow),
        (d) => expect(pathIn(d).endEnd, LineEnd.hollowArrow)),
    row(
        "a path's End size",
        path,
        typedIn(numberIn(lookSection, "End size"), 2.5),
        (d) => expect(pathIn(d).endSize, 2.5)),
    row(
        "a path's Swap ends",
        path,
        pressed(keyed("strokeSwapEnds")),
        (d) => expect((pathIn(d).startEnd, pathIn(d).endEnd),
            (LineEnd.arrow, LineEnd.circle))),
    row("a path's Dash", path, typedIn(numberIn(lookSection, "Dash"), 14),
        (d) => expect(pathIn(d).dash, 14)),
    row(
        "a path's Who follows",
        path,
        chosen(dropdownIn("elementSection-more", "Who follows"),
            const PathFollow(elementId: "f")), (d) {
      expect(pathIn(d).follow, const PathFollow(elementId: "f"));
      expect(pathIn(d).guide, isTrue, reason: "a route is a guide");
      expect(d.elementById("f")!.track, isNotNull, reason: "and baked");
    }, beside: [follower]),
    row(
        "a path's Who follows, set to nothing",
        followed,
        chosen(dropdownIn("elementSection-more", "Who follows"),
            const PathFollow(elementId: "")),
        (d) => expect(pathIn(d).follow, isNull),
        beside: [follower]),
    row("a path's run Start", path, keyTyped("pathStartFrame", 20),
        (d) => expect(pathIn(d).firstFrame, 20)),
    row("a path's run End", path, keyTyped("pathEndFrame", 80),
        (d) => expect(pathIn(d).lastFrame, 80)),
    row("a path's Space the points evenly", path, pressed(keyed("pathSpread")),
        (d) => expect([for (var n in pathIn(d).nodes) n.frame], [0, 48, 95])),
    row("a path's Apply again", followed, pressed(keyed("pathRelink")),
        (d) => expect(d.elementById("f")!.track, isNotNull),
        beside: [follower]),
    row("a path's Carry it on", path, pressed(keyed("pathCarryOn")),
        (d) => expect(pathIn(d).nodes, hasLength(4))),
    row("a path's point's frame", path, keyTyped("node-frame-1-p", 30),
        (d) => expect(pathIn(d).nodes[1].frame, 30)),
    row("a path's point's X", path, keyTyped("node-x-0-p", 160),
        (d) => expect(pathIn(d).pointOf(pathIn(d).nodes[0]).dx, 160)),
    row("a path's point's Y", path, keyTyped("node-y-0-p", 420),
        (d) => expect(pathIn(d).pointOf(pathIn(d).nodes[0]).dy, 420)),
    row("a path's point's add", path, pressed(_nodeButton(0, Icons.add)),
        (d) => expect(pathIn(d).nodes, hasLength(4))),
    row("a path's point's remove", path, pressed(_nodeButton(1, Icons.close)),
        (d) => expect(pathIn(d).nodes, hasLength(2))),

    // A closed path: its run goes round to the start again, on frame 23.
    row("a closed path's run Start", loop, keyTyped("pathStartFrame", 5), (d) {
      expect(pathIn(d).firstFrame, 5);
      expect(pathIn(d).endFrame, 23, reason: "its end where it was");
    }),
    row("a closed path's run End", loop, keyTyped("pathEndFrame", 60), (d) {
      expect(pathIn(d).endFrame, 60);
      expect(pathIn(d).firstFrame, 0);
    }),
    row(
        "a closed path's Space the points evenly",
        loop,
        pressed(keyed("pathSpread")),
        (d) => expect([for (var n in pathIn(d).nodes) n.frame], [0, 7, 15])),
    row("a closed path's last point's add", loop,
        pressed(_nodeButton(2, Icons.add)), (d) {
      expect(pathIn(d).nodes, hasLength(4));
      expect(pathIn(d).nodes[3].frame, 18, reason: "half-way back");
      expect(pathIn(d).endFrame, 23);
    }),
    row(
        "a closed path's added last point's remove",
        loop.insertAfter(2),
        pressed(_nodeButton(3, Icons.close)),
        (d) => expect(pathIn(d).nodes, hasLength(3))),
  ];
}
