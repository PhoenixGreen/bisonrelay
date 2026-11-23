import 'dart:convert';
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

// canvas_shape_line_path_panels_test.dart is a shape's, a line's and a
// path's settings, used in the real sidebar: a stroke's controls in the
// quick strip and in Look are one control twice, with the model's range; a
// line's Layout reads and sets the line as it is drawn, turned or slanted;
// a closed path offers no ends; a follower gone from the canvas is shown
// as missing; a square or a circle keeps its box square; Scale inside says
// what it scales on each; what the Chain's Design table writes stays
// within the same ranges; and
// every control of the three, pressed or set, changes what it says in one
// undo step (_rows: a new control is one row there).

const _doc = CanvasDocument(frames: 96, frameRate: 24);

/// _panel puts [e] up selected in the real sidebar, with [beside] on the
/// canvas too, every section open, and returns its controller.
Future<CanvasController> _panel(WidgetTester tester, CanvasElement e,
    {List<CanvasElement> beside = const []}) async {
  SharedPreferences.setMockInitialValues({});
  var doc = _doc;
  for (var b in beside) {
    doc = doc.addElement(b);
  }
  var c = CanvasController(doc.addElement(e));
  addTearDown(c.dispose);
  c.selectOnly(e.id);
  await pumpCanvasApp(tester, designSidebar(c), size: const Size(320, 9000));
  await openEverything(tester, find.byType(CanvasSidebarHost));
  return c;
}

/// _section is the part of the panel [name] is: "quickStrip" or a
/// section's "elementSection-look".
Finder _section(String name) => find.byKey(ValueKey(name));

/// _widget is the one [T] in [section] that [test] takes.
Finder _widget<T extends Widget>(String section, bool Function(T) test) =>
    find.descendant(
        of: _section(section),
        matching: find.byWidgetPredicate((w) => w is T && test(w)));

Finder _number(String section, String label) =>
    _widget<CanvasNumberField>(section, (w) => w.label == label);

Finder _stepper(String section, String label) =>
    _widget<CanvasStepper>(section, (w) => w.label == label);

Finder _dropdown(String section, String label) =>
    _widget<CanvasDropdown>(section, (w) => w.label == label);

Finder _colour(String section, String label) =>
    _widget<CanvasColorButton>(section, (w) => w.label == label);

const _look = "elementSection-look", _layout = "elementSection-layout";
const _quick = "quickStrip";

/// _set gives the number field or stepper [f] the value [v], as a typed
/// number does, and lets the panel rebuild.
Future<void> _set(WidgetTester tester, Finder f, double v) async {
  var w = tester.widget(f);
  if (w is CanvasNumberField) {
    w.onChanged(v);
    w.onCommit?.call();
  } else if (w is CanvasStepper) {
    w.onChanged(v);
    w.onCommit?.call();
  }
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// _range is the least and most a number field or stepper offers.
(double, double) _range(WidgetTester tester, Finder f) =>
    switch (tester.widget(f)) {
      CanvasNumberField w => (w.min, w.max),
      CanvasStepper w => (w.min, w.max),
      var w => throw StateError("$w is not a number"),
    };

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
        await _panel(tester, e);
        const range = (StrokeRange.minWidth, StrokeRange.maxWidth);
        expect(_range(tester, _stepper(_quick, "Width")), range);
        expect(_range(tester, _number(_look, "Width")), range);
      });

      testWidgets("a $kind's dash and end size offer the model's range",
          (tester) async {
        await _panel(tester, e);
        expect(
            _range(tester, _number(_look, "Dash")), (0.0, StrokeRange.maxDash));
        expect(_range(tester, _number(_look, "End size")),
            (StrokeRange.minEndSize, StrokeRange.maxEndSize));
      });

      testWidgets("a $kind's quick colour offers the fade its Look's does",
          (tester) async {
        await _panel(tester, e);
        var quick = tester.widget<CanvasColorButton>(_colour(_quick, "Colour"));
        var look = tester.widget<CanvasColorButton>(_colour(_look, "Colour"));
        expect(look.onGradientChanged, isNotNull);
        expect(quick.onGradientChanged, isNotNull);
      });
    }

    testWidgets("a line's quick dash offers the model's range too",
        (tester) async {
      await _panel(tester, line);
      expect(
          _range(tester, _stepper(_quick, "Dash")), (0.0, StrokeRange.maxDash));
    });

    testWidgets("a shape's two outline widths go from none to the most",
        (tester) async {
      await _panel(tester,
          const ShapeElement(ElementBase(id: "s", width: 200, height: 120)));
      const range = (0.0, StrokeRange.maxWidth);
      expect(_range(tester, _stepper(_quick, "Outline")), range);
      expect(_range(tester, _number(_look, "Stroke")), range);
    });

    testWidgets(
        "a shape's quick outline colour offers the fade its Look's does",
        (tester) async {
      var c = await _panel(tester,
          const ShapeElement(ElementBase(id: "s", width: 200, height: 120)));
      var quick =
          tester.widget<CanvasColorButton>(_colour(_quick, "Outline colour"));
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
      await _panel(tester, path(closed: true));
      expect(_dropdown(_look, "Start"), findsNothing);
      expect(_dropdown(_look, "End"), findsNothing);
      expect(_number(_look, "End size"), findsNothing);
      expect(_dropdown(_look, "Stroke end"), findsOneWidget,
          reason: "a dash still has a cap on each of its own ends");
    });

    testWidgets("and offers them again once it is opened", (tester) async {
      var c = await _panel(tester, path(closed: true));
      await _press(
          tester,
          _widget<CanvasToggle>(
              _quick, (w) => w.key == const ValueKey("quickPathClosed")));
      expect((c.document.elementById("p") as PathElement).closed, isFalse);
      expect(_dropdown(_look, "Start"), findsOneWidget);
      expect(_dropdown(_look, "End"), findsOneWidget);
      expect(_number(_look, "End size"), findsOneWidget);
    });
  });

  group("a follower no longer on the canvas", () {
    var path = PathElement(
        const ElementBase(id: "p", x: 100, y: 300, width: 300, height: 200),
        nodes: PathElement.defaultNodes(frames: 96),
        follow: const PathFollow(elementId: "gone"));
    const runner = TextElement(ElementBase(id: "f", name: "Runner"));
    Finder whoFollows() => _dropdown("elementSection-more", "Who follows");
    List<PathFollow> offered(WidgetTester tester) => [
          for (var (v, _) in tester
              .widget<CanvasDropdown<PathFollow>>(whoFollows())
              .options)
            v
        ];

    testWidgets("is shown in Who follows as missing", (tester) async {
      await _panel(tester, path, beside: [runner]);
      expect(find.descendant(of: whoFollows(), matching: find.text("Missing")),
          findsOneWidget);
    });

    testWidgets("and choosing it again changes nothing", (tester) async {
      var c = await _panel(tester, path, beside: [runner]);
      var before = c.document;
      await _chosen(whoFollows(), const PathFollow(elementId: "gone"))(tester);
      await tester.pumpAndSettle();
      expect(c.document, same(before));
    });

    testWidgets("and is not offered once another is chosen", (tester) async {
      var c = await _panel(tester, path, beside: [runner]);
      await _chosen(whoFollows(), const PathFollow(elementId: "f"))(tester);
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
      var c = await _panel(tester, turned);
      var (start, _) = _drawn(turned);
      await _press(tester, find.byKey(const ValueKey("lineLevel")));
      var (a, b) = _drawn(lineIn(c));
      expect(b.dy, closeTo(a.dy, 0.05));
      expect((b - a).distance, closeTo(turned.length, 0.05));
      expect(a.dx, closeTo(start.dx, 0.05), reason: "turned about its start");
      expect(a.dy, closeTo(start.dy, 0.05));
    });

    testWidgets("Upright stands a turned line upright where it is drawn",
        (tester) async {
      var c = await _panel(tester, turned);
      await _press(tester, find.byKey(const ValueKey("linePlumb")));
      var (a, b) = _drawn(lineIn(c));
      expect(b.dx, closeTo(a.dx, 0.05));
    });

    testWidgets("Direction shows which way the line is drawn pointing",
        (tester) async {
      await _panel(tester, turned);
      var (a, b) = _drawn(turned);
      var field = tester
          .widget<CanvasNumberField>(find.byKey(const ValueKey("lineAngle")));
      expect(field.value, closeTo(_degrees(b - a), 0.05));
    });

    testWidgets("and sets it, the start staying where it is drawn",
        (tester) async {
      var c = await _panel(tester, turned);
      var (start, _) = _drawn(turned);
      await _set(tester, find.byKey(const ValueKey("lineAngle")), 90);
      var (a, b) = _drawn(lineIn(c));
      expect(_degrees(b - a), closeTo(90, 0.05));
      expect((a - start).distance, closeTo(0, 0.05));
    });

    testWidgets("Length shows how long a slanted line is drawn",
        (tester) async {
      await _panel(tester, slanted);
      var (a, b) = _drawn(slanted);
      var field = tester
          .widget<CanvasNumberField>(find.byKey(const ValueKey("lineLength")));
      expect(field.value, closeTo((b - a).distance, 0.05));
    });

    testWidgets("and sets it, keeping where it starts and points",
        (tester) async {
      var c = await _panel(tester, turned);
      var (start, end) = _drawn(turned);
      await _set(tester, find.byKey(const ValueKey("lineLength")), 500);
      var (a, b) = _drawn(lineIn(c));
      expect((b - a).distance, closeTo(500, 0.05));
      expect((a - start).distance, closeTo(0, 0.05));
      expect(_degrees(b - a), closeTo(_degrees(end - start), 0.05));
    });

    testWidgets("its own direction is not a second field called Angle",
        (tester) async {
      await _panel(tester, turned);
      expect(
          tester
              .widget<CanvasNumberField>(
                  find.byKey(const ValueKey("lineAngle")))
              .label,
          "Direction");
      expect(
          _widget<Widget>(
              _layout,
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
      var c = await _panel(tester, line);
      await _press(tester, find.byKey(const ValueKey("strokeSwapEnds")));
      var after = lineIn(c);
      expect((after.startEnd, after.endEnd), (LineEnd.arrow, LineEnd.circle));
      expect((after.start, after.end), (line.start, line.end),
          reason: "the line itself stays where it is");
    });

    testWidgets("the slope switch says what it does", (tester) async {
      var c = await _panel(tester, line);
      var toggle = _widget<CanvasToggle>(
          _look, (w) => w.key == const ValueKey("lineFlipped"));
      expect(tester.widget<CanvasToggle>(toggle).label, "Slope the other way");
      var ends = tester.widget<CanvasControlGroup>(
          _widget<CanvasControlGroup>(_look, (w) => w.label == "Ends"));
      expect(ends.help, isNot(contains("swaps which end is the start")));
      await _press(tester, toggle);
      var after = lineIn(c);
      expect(after.flipped, isTrue);
      expect(after.startEnd, LineEnd.circle,
          reason: "the start keeps its mark, on the left");
      expect(after.start.dx, lessThan(after.end.dx));
    });
  });

  group("a bubble's tail", () {
    testWidgets("is said to point to, not to have points", (tester) async {
      await _panel(
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
      expect(s.base.lockAspect, isTrue, reason: "and held square");
      expect(s.keepsAspect, isTrue, reason: "which the handles honour");
    }

    for (var kind in ShapeKind.values.where((k) => k.isRegular)) {
      test("chosen as a ${kind.name}, a box is squared and held", () {
        expectSquared(oblong.withKind(kind));
      });
    }

    test("another kind after it leaves the box and lets it go", () {
      var other = oblong.withKind(ShapeKind.circle).withKind(ShapeKind.ellipse);
      expect((other.width, other.height), (120.0, 120.0));
      expect(other.base.lockAspect, isFalse);
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
      var made = newElement(ElementKind.shape, _doc) as ShapeElement;
      expect(made.width, made.height);
      var round = made.withKind(ShapeKind.circle);
      expect((round.x, round.y, round.width, round.height),
          (made.x, made.y, made.width, made.height));
      expect(round.base.lockAspect, isTrue);
    });

    testWidgets("picked from the tiles", (tester) async {
      var c = await _panel(tester, oblong);
      await _press(tester, find.byKey(const ValueKey("shapeKind-circle")));
      expectSquared(c.document.elementById("s") as ShapeElement);
    });

    testWidgets("picked from the quick strip", (tester) async {
      var c = await _panel(tester, oblong);
      tester
          .widget<CanvasDropdown<ShapeKind>>(
              find.byKey(const ValueKey("quickShape")))
          .onChanged(ShapeKind.square);
      await tester.pumpAndSettle();
      expectSquared(c.document.elementById("s") as ShapeElement);
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

  group("every control", () {
    for (var row in _rows()) {
      testWidgets("${row.what} changes what it says, in one step",
          (tester) async {
        var c = await _panel(tester, row.element, beside: row.beside);
        var before = jsonEncode(c.document.toJson());
        await row.press(tester);
        await tester.pumpAndSettle();
        row.check(c.document);
        expect(c.canUndo, isTrue, reason: "a step was made");
        c.undo();
        expect(jsonEncode(c.document.toJson()), before,
            reason: "and one undo takes it all back");
        expect(c.canUndo, isFalse, reason: "it was one step");
      });
    }
  });
}

/// _Row is one control of a shape's, a line's or a path's panel: what it
/// is, the element it is shown for (with [beside] on the canvas too), how it
/// is pressed or set, and what that must have changed.
typedef _Row = ({
  String what,
  CanvasElement element,
  List<CanvasElement> beside,
  Future<void> Function(WidgetTester) press,
  void Function(CanvasDocument) check,
});

const _red = Color(0xFFE53935);
const _fade = GradientSpec(to: Color(0xFF3D7EFF), angle: 30);

/// _typed sets the number field or stepper [f] to [v], as a typed number
/// does.
Future<void> Function(WidgetTester) _typed(Finder f, double v) =>
    (tester) => _set(tester, f, v);

Future<void> Function(WidgetTester) _key(String key, double v) =>
    _typed(find.byKey(ValueKey(key)), v);

/// _chosen picks [v] from the dropdown [f].
Future<void> Function(WidgetTester) _chosen<T>(Finder f, T v) =>
    (tester) async => tester.widget<CanvasDropdown<T>>(f).onChanged(v);

/// _coloured gives the colour button [f] the colour, or with [fade], the
/// fade, as its picker does.
Future<void> Function(WidgetTester) _coloured(Finder f, {bool fade = false}) =>
    (tester) async {
      var w = tester.widget<CanvasColorButton>(f);
      fade ? w.onGradientChanged!(_fade) : w.onChanged(_red);
    };

/// _switched turns the switch [f] over.
Future<void> Function(WidgetTester) _switched(Finder f) => (tester) async {
      var w = tester.widget<CanvasToggle>(f);
      w.onChanged(!w.value);
    };

Future<void> Function(WidgetTester) _pressed(Finder f) =>
    (tester) => _press(tester, f);

Finder _keyed(String key) => find.byKey(ValueKey(key));

/// _nodeButton is the button with [icon] on the path's point [i].
Finder _nodeButton(int i, IconData icon) => find.descendant(
    of: find.byKey(ValueKey("path-node-$i-p")),
    matching:
        find.byWidgetPredicate((w) => w is CanvasIconButton && w.icon == icon));

List<_Row> _rows() {
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
  final keyed = line.withBase(
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

  ShapeElement shapeIn(CanvasDocument d) => d.elementById("s") as ShapeElement;
  LineElement lineIn(CanvasDocument d) => d.elementById("l") as LineElement;
  PathElement pathIn(CanvasDocument d) => d.elementById("p") as PathElement;

  _Row row(
          String what,
          CanvasElement element,
          Future<void> Function(WidgetTester) press,
          void Function(CanvasDocument) check,
          {List<CanvasElement> beside = const []}) =>
      (
        what: what,
        element: element,
        beside: beside,
        press: press,
        check: check
      );

  return [
    // A shape.
    row(
        "a shape's quick Shape",
        shape,
        _chosen(_keyed("quickShape"), ShapeKind.ellipse),
        (d) => expect(shapeIn(d).shape, ShapeKind.ellipse)),
    row("a shape's tiles", shape, _pressed(_keyed("shapeKind-star")),
        (d) => expect(shapeIn(d).shape, ShapeKind.star)),
    row("a shape's quick Fill", shape, _coloured(_keyed("quickFill")),
        (d) => expect(shapeIn(d).fill, _red)),
    row(
        "a shape's quick Fill's fade",
        shape,
        _coloured(_keyed("quickFill"), fade: true),
        (d) => expect(shapeIn(d).fillFade, _fade)),
    row(
        "a shape's quick Outline",
        shape,
        _typed(_stepper(_quick, "Outline"), 5),
        (d) => expect(shapeIn(d).strokeWidth, 5)),
    row("a shape's quick Outline colour", shape,
        _coloured(_keyed("quickStrokeColour")), (d) {
      expect(shapeIn(d).strokeColor, _red);
      expect(shapeIn(d).strokeWidth, greaterThan(0));
    }),
    row(
        "a shape's quick Outline colour's fade",
        shape,
        _coloured(_keyed("quickStrokeColour"), fade: true),
        (d) => expect(shapeIn(d).strokeFade, _fade)),
    row("a shape's Fill", shape, _coloured(_colour(_look, "Fill")),
        (d) => expect(shapeIn(d).fill, _red)),
    row(
        "a shape's Fill's fade",
        shape,
        _coloured(_colour(_look, "Fill"), fade: true),
        (d) => expect(shapeIn(d).fillFade, _fade)),
    row(
        "a shape's Painted with",
        shape,
        _chosen(_keyed("shapeFillKind"), TextFillKind.pattern),
        (d) => expect(shapeIn(d).painted.kind, TextFillKind.pattern)),
    row("a shape's Stroke", shape, _typed(_number(_look, "Stroke"), 7),
        (d) => expect(shapeIn(d).strokeWidth, 7)),
    row("a shape's outline Colour", shape, _coloured(_colour(_look, "Colour")),
        (d) => expect(shapeIn(d).strokeColor, _red)),
    row(
        "a shape's outline Colour's fade",
        shape,
        _coloured(_colour(_look, "Colour"), fade: true),
        (d) => expect(shapeIn(d).strokeFade, _fade)),
    row(
        "a star's Points",
        star,
        _typed(_number("elementSection-content", "Points"), 7),
        (d) => expect(shapeIn(d).points, 7)),
    row(
        "a star's Depth",
        star,
        _typed(_number("elementSection-content", "Depth"), 0.6),
        (d) => expect(shapeIn(d).innerRatio, 0.6)),
    row("a shape's Corners", shape, _key("shapeRadius", 12),
        (d) => expect(shapeIn(d).cornerRadius, 12)),
    for (var (glyph, corner) in [
      ("↖", (Corners c) => c.topLeft),
      ("↗", (Corners c) => c.topRight),
      ("↘", (Corners c) => c.bottomRight),
      ("↙", (Corners c) => c.bottomLeft),
    ])
      row("a shape's corner $glyph", split, _key("shapeRadius$glyph", 30),
          (d) => expect(corner(shapeIn(d).corners), 30)),
    row("a shape's corners joined", split, _pressed(_keyed("shapeRadiusLink")),
        (d) => expect(shapeIn(d).corners.even, 20)),
    row("a shape's Padding", shape, _key("shapePadding", 10),
        (d) => expect(shapeIn(d).padding, 10)),
    for (var (side, room) in [
      ("Top", (Room r) => r.top),
      ("Right", (Room r) => r.right),
      ("Bottom", (Room r) => r.bottom),
      ("Left", (Room r) => r.left),
    ])
      row("a shape's padding at its $side", padded, _key("shapePad$side", 30),
          (d) => expect(room(shapeIn(d).pad), 30)),
    row(
        "a shape's padding joined",
        padded,
        _pressed(_keyed("shapePaddingLink")),
        (d) => expect(shapeIn(d).pad.even, 20)),
    row(
        "a patterned shape's fill Opacity",
        patterned,
        _key("shapeFillOpacity", 0.5),
        (d) => expect(shapeIn(d).painted.opacity, 0.5)),
    row(
        "a pictured shape's fill Saturation",
        pictured,
        _key("shapeFillSaturation", 2),
        (d) => expect(shapeIn(d).painted.saturation, 2)),
    row("a shape's Words", shape, (tester) async {
      var w = tester.widget<CanvasTextField>(_widget<CanvasTextField>(
          "elementSection-content", (w) => w.hint == "Type text on the shape"));
      w.onChanged("Hello");
      w.onCommit?.call();
    }, (d) => expect(shapeIn(d).text, "Hello")),
    row(
        "a shape's label Size",
        worded,
        _typed(
            find.descendant(
                of: _keyed("shapeLabelType"), matching: _keyed("typeSize")),
            30),
        (d) => expect(shapeIn(d).textSpec.fontSize, 30)),
    row(
        "a bubble's Body",
        bubble,
        _chosen(_dropdown("elementSection-content", "Body"), BubbleBody.cloud),
        (d) => expect(shapeIn(d).bubble.body, BubbleBody.cloud)),
    row(
        "a bubble's Tail",
        bubble,
        _chosen(
            _dropdown("elementSection-content", "Tail"), BubbleTail.thought),
        (d) => expect(shapeIn(d).bubble.tail, BubbleTail.thought)),
    row("a bubble's Points to", bubble, _key("bubbleTailAngle", 200),
        (d) => expect(shapeIn(d).bubble.tailAngle, 200)),
    row(
        "a bubble's Length",
        bubble,
        _typed(_number("elementSection-content", "Length"), 0.9),
        (d) => expect(shapeIn(d).bubble.tailLength, 0.9)),
    row(
        "a bubble's Width",
        bubble,
        _typed(_number("elementSection-content", "Width"), 0.6),
        (d) => expect(shapeIn(d).bubble.tailWidth, 0.6)),
    row(
        "a bubble's Curl",
        bubble,
        _typed(_number("elementSection-content", "Curl"), 1),
        (d) => expect(shapeIn(d).bubble.curl, 1)),

    // A line.
    row("a line's quick Colour", line, _coloured(_keyed("quickLineColour")),
        (d) => expect(lineIn(d).color, _red)),
    row(
        "a line's quick Colour's fade",
        line,
        _coloured(_keyed("quickLineColour"), fade: true),
        (d) => expect(lineIn(d).fade, _fade)),
    row("a line's quick Width", line, _key("quickLineWidth", 9),
        (d) => expect(lineIn(d).strokeWidth, 9)),
    row(
        "a line's quick End",
        line,
        _chosen(_keyed("quickLineEnd"), LineEnd.diamond),
        (d) => expect(lineIn(d).endEnd, LineEnd.diamond)),
    row("a line's quick Dash", line, _key("quickLineDash", 15),
        (d) => expect(lineIn(d).dash, 15)),
    row("a line's Colour", line, _coloured(_colour(_look, "Colour")),
        (d) => expect(lineIn(d).color, _red)),
    row(
        "a line's Colour's fade",
        line,
        _coloured(_colour(_look, "Colour"), fade: true),
        (d) => expect(lineIn(d).fade, _fade)),
    row("a line's Width", line, _typed(_number(_look, "Width"), 11),
        (d) => expect(lineIn(d).strokeWidth, 11)),
    row("a line's Curve", line, _typed(_number(_look, "Curve"), 0.4),
        (d) => expect(lineIn(d).curvature, 0.4)),
    row("a line's keyed Curve", keyed, _typed(_number(_look, "Curve"), 0.4),
        (d) {
      expect(lineIn(d).track!.keyAt(0)!.values[KeyframeChannel.bow], 0.4);
      expect(lineIn(d).curvature, 0, reason: "the key, not where it rests");
    }),
    row(
        "a line's Curve diamond",
        line,
        _pressed(_widget<CanvasKeyframeDot>(_look, (_) => true)),
        (d) =>
            expect(lineIn(d).track!.keyAt(0)!.values[KeyframeChannel.bow], 0)),
    row(
        "a line's Stroke end",
        line,
        _chosen(_dropdown(_look, "Stroke end"), LineStrokeCap.round),
        (d) => expect(lineIn(d).cap, LineStrokeCap.round)),
    row(
        "a line's Start",
        line,
        _chosen(_dropdown(_look, "Start"), LineEnd.square),
        (d) => expect(lineIn(d).startEnd, LineEnd.square)),
    row("a line's End", line, _chosen(_dropdown(_look, "End"), LineEnd.bar),
        (d) => expect(lineIn(d).endEnd, LineEnd.bar)),
    row("a line's End size", line, _typed(_number(_look, "End size"), 3),
        (d) => expect(lineIn(d).endSize, 3)),
    row(
        "a line's Swap ends",
        line,
        _pressed(_keyed("strokeSwapEnds")),
        (d) => expect((lineIn(d).startEnd, lineIn(d).endEnd),
            (LineEnd.arrow, LineEnd.circle))),
    row("a line's Slope the other way", line, _switched(_keyed("lineFlipped")),
        (d) => expect(lineIn(d).flipped, isTrue)),
    row("a line's Dash", line, _key("lineDash", 8),
        (d) => expect(lineIn(d).dash, 8)),
    row("a line's Length", line, _key("lineLength", 250),
        (d) => expect(lineIn(d).length, closeTo(250, 1e-6))),
    row("a line's Direction", line, _key("lineAngle", 45),
        (d) => expect(lineIn(d).angle, closeTo(45, 1e-6))),
    row("a line's Level", line, _pressed(_keyed("lineLevel")),
        (d) => expect(lineIn(d).angle, closeTo(0, 0.01))),
    row("a line's Upright", line, _pressed(_keyed("linePlumb")),
        (d) => expect(lineIn(d).angle, closeTo(90, 0.01))),

    // A path.
    row("a path's quick Colour", path, _coloured(_keyed("quickPathColour")),
        (d) => expect(pathIn(d).color, _red)),
    row(
        "a path's quick Colour's fade",
        path,
        _coloured(_keyed("quickPathColour"), fade: true),
        (d) => expect(pathIn(d).fade, _fade)),
    row("a path's quick Width", path, _key("quickPathWidth", 4),
        (d) => expect(pathIn(d).strokeWidth, 4)),
    row("a path's quick Closed", path, _switched(_keyed("quickPathClosed")),
        (d) => expect(pathIn(d).closed, isTrue)),
    row("a path's Colour", path, _coloured(_colour(_look, "Colour")),
        (d) => expect(pathIn(d).color, _red)),
    row(
        "a path's Colour's fade",
        path,
        _coloured(_colour(_look, "Colour"), fade: true),
        (d) => expect(pathIn(d).fade, _fade)),
    row("a path's Width", path, _typed(_number(_look, "Width"), 6),
        (d) => expect(pathIn(d).strokeWidth, 6)),
    row(
        "a path's Closed",
        path,
        _switched(_widget<CanvasToggle>(_look, (w) => w.label == "Closed")),
        (d) => expect(pathIn(d).closed, isTrue)),
    row(
        "a path's Guide only",
        path,
        _switched(_widget<CanvasToggle>(_look, (w) => w.label == "Guide only")),
        (d) => expect(pathIn(d).guide, isTrue)),
    row(
        "a path's Stroke end",
        path,
        _chosen(_dropdown(_look, "Stroke end"), LineStrokeCap.square),
        (d) => expect(pathIn(d).cap, LineStrokeCap.square)),
    row(
        "a path's Start",
        path,
        _chosen(_dropdown(_look, "Start"), LineEnd.diamond),
        (d) => expect(pathIn(d).startEnd, LineEnd.diamond)),
    row(
        "a path's End",
        path,
        _chosen(_dropdown(_look, "End"), LineEnd.hollowArrow),
        (d) => expect(pathIn(d).endEnd, LineEnd.hollowArrow)),
    row("a path's End size", path, _typed(_number(_look, "End size"), 2.5),
        (d) => expect(pathIn(d).endSize, 2.5)),
    row(
        "a path's Swap ends",
        path,
        _pressed(_keyed("strokeSwapEnds")),
        (d) => expect((pathIn(d).startEnd, pathIn(d).endEnd),
            (LineEnd.arrow, LineEnd.circle))),
    row("a path's Dash", path, _typed(_number(_look, "Dash"), 14),
        (d) => expect(pathIn(d).dash, 14)),
    row(
        "a path's Who follows",
        path,
        _chosen(_dropdown("elementSection-more", "Who follows"),
            const PathFollow(elementId: "f")), (d) {
      expect(pathIn(d).follow, const PathFollow(elementId: "f"));
      expect(pathIn(d).guide, isTrue, reason: "a route is a guide");
      expect(d.elementById("f")!.track, isNotNull, reason: "and baked");
    }, beside: [follower]),
    row(
        "a path's Who follows, set to nothing",
        followed,
        _chosen(_dropdown("elementSection-more", "Who follows"),
            const PathFollow(elementId: "")),
        (d) => expect(pathIn(d).follow, isNull),
        beside: [follower]),
    row("a path's run Start", path, _key("pathStartFrame", 20),
        (d) => expect(pathIn(d).firstFrame, 20)),
    row("a path's run End", path, _key("pathEndFrame", 80),
        (d) => expect(pathIn(d).lastFrame, 80)),
    row(
        "a path's Space the points evenly",
        path,
        _pressed(_keyed("pathSpread")),
        (d) => expect([for (var n in pathIn(d).nodes) n.frame], [0, 48, 95])),
    row("a path's Apply again", followed, _pressed(_keyed("pathRelink")),
        (d) => expect(d.elementById("f")!.track, isNotNull),
        beside: [follower]),
    row("a path's Carry it on", path, _pressed(_keyed("pathCarryOn")),
        (d) => expect(pathIn(d).nodes, hasLength(4))),
    row("a path's point's frame", path, _key("node-frame-1-p", 30),
        (d) => expect(pathIn(d).nodes[1].frame, 30)),
    row("a path's point's X", path, _key("node-x-0-p", 160),
        (d) => expect(pathIn(d).pointOf(pathIn(d).nodes[0]).dx, 160)),
    row("a path's point's Y", path, _key("node-y-0-p", 420),
        (d) => expect(pathIn(d).pointOf(pathIn(d).nodes[0]).dy, 420)),
    row("a path's point's add", path, _pressed(_nodeButton(0, Icons.add)),
        (d) => expect(pathIn(d).nodes, hasLength(4))),
    row("a path's point's remove", path, _pressed(_nodeButton(1, Icons.close)),
        (d) => expect(pathIn(d).nodes, hasLength(2))),
  ];
}
