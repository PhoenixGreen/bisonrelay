// canvas_vector_diagram_test.dart: what a drawing needs to be a technical
// diagram -- words set on a shape, arrowheads and dashes, shapes set to a
// time, repeats, Draw on, and a shape sized by a sheet -- read, written,
// drawn, timed, and changed from the panel.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart' hide Path;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/canvas_panel_helpers.dart';
import 'support/canvas_sidebar_host.dart';

VectorPath box(double x, double y, double w, double h) => VectorPath([
      VectorNode(x, y),
      VectorNode(x + w, y),
      VectorNode(x + w, y + h),
      VectorNode(x, y + h),
    ], closed: true);

VectorPath lineRun(Offset a, Offset b) =>
    VectorPath([VectorNode(a.dx, a.dy), VectorNode(b.dx, b.dy)]);

VectorElement drawingOf(List<VectorShape> shapes) => VectorElement(
    const ElementBase(id: "v", x: 0, y: 0, width: 200, height: 100),
    viewBox: const Rect.fromLTWH(0, 0, 200, 100),
    shapes: shapes);

/// rendered draws [e] into a 200 x 100 image, [drawn] of its lines along.
Future<ByteData> rendered(VectorElement e, {double drawn = 1}) async {
  var rec = ui.PictureRecorder();
  var canvas = Canvas(rec);
  withVectorDrawn(drawn,
      () => paintVector(canvas, const Rect.fromLTWH(0, 0, 200, 100), e, null));
  var image = await rec.endRecording().toImage(200, 100);
  var bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

/// alphaAt is the image's opacity at [x], [y], 0 to 255.
int alphaAt(ByteData b, int x, int y) => b.getUint8((y * 200 + x) * 4 + 3);

void main() {
  group("saved", () {
    test("every new field is written and read back", () {
      var s = VectorShape(
        paths: [lineRun(const Offset(0, 0), const Offset(10, 0))],
        stroke: const Color(0xFF00FF00),
        cue: VectorCue.at,
        cueAt: 30,
        label: const VectorLabel(
            text: "64 multiplies",
            size: 18,
            weight: 700,
            align: TextAlign.center,
            at: Offset(4, 5),
            width: 120,
            color: Color(0xFF0B0F14)),
        dash: const [6, 4],
        headStart: VectorHead.dot,
        headEnd: VectorHead.arrow,
        headSize: 5,
        repeat: const VectorRepeat(
            count: 16,
            columns: 4,
            step: Offset(20, 0),
            rowStep: 20,
            colours: [Color(0xFF112233), Color(0xFF445566)],
            each: 3),
        bind: const VectorBind(
            sheet: "s1", cell: "B2", max: 214, vertical: true, value: 29),
      );
      var back = VectorShape.fromJson(s.toJson())!;
      expect(back.cue, VectorCue.at);
      expect(back.cueAt, 30);
      expect(back.label!.text, "64 multiplies");
      expect(back.label!.align, TextAlign.center);
      expect(back.label!.at, const Offset(4, 5));
      expect(back.label!.width, 120);
      expect(back.label!.weight, 700);
      expect(back.label!.color, const Color(0xFF0B0F14));
      expect(back.dash, [6, 4]);
      expect(back.headStart, VectorHead.dot);
      expect(back.headEnd, VectorHead.arrow);
      expect(back.headSize, 5);
      expect(back.repeat!.count, 16);
      expect(back.repeat!.columns, 4);
      expect(back.repeat!.rowStep, 20);
      expect(back.repeat!.colours, hasLength(2));
      expect(back.repeat!.each, 3);
      expect(back.bind!.cell, "B2");
      expect(back.bind!.vertical, isTrue);
      expect(back.bind!.value, 29);
    });

    test("a shape without them is saved as before", () {
      var s = VectorShape(paths: [box(0, 0, 10, 10)]);
      var json = s.toJson();
      for (var k in [
        "cueAt",
        "label",
        "dash",
        "head0",
        "head1",
        "repeat",
        "bind"
      ]) {
        expect(json.containsKey(k), isFalse, reason: k);
      }
    });

    test("a repeat read from a file is bounded", () {
      var r = VectorRepeat.fromJson({"n": 1 << 30, "dx": 1})!;
      expect(r.count, VectorRepeat.maxCount);
    });
  });

  group("repeats", () {
    test("lay their copies out in rows, coloured in turn, each after the last",
        () {
      var shapes = [
        VectorShape(
            paths: [box(0, 0, 10, 10)],
            fill: const Color(0xFFFFFFFF),
            cueLength: 2,
            repeat: const VectorRepeat(
                count: 6,
                columns: 3,
                step: Offset(20, 0),
                rowStep: 30,
                colours: [Color(0xFFFF0000), Color(0xFF0000FF)])),
      ];
      var shown = vectorShown(shapes);
      expect(shown, hasLength(6));
      expect(shown[4].path.getBounds().topLeft, const Offset(20, 30));
      expect(shown[0].fill, const Color(0xFFFF0000));
      expect(shown[1].fill, const Color(0xFF0000FF));
      expect(shown[0].cue, VectorCue.together, reason: "the first keeps its");
      expect(shown[1].cue, VectorCue.after);
      expect(shown.every((s) => s.repeat == null), isTrue);
      // Each takes its two frames, one after another.
      var times = naturalTimes(shown, 24);
      expect([for (var t in times) t.$1], [0, 2, 4, 6, 8, 10]);
      expect(identical(vectorShown(shapes), vectorShown(shapes)), isTrue,
          reason: "worked out once per list");
    });

    test("a drawing with none is drawn from its own list", () {
      var shapes = [
        VectorShape(paths: [box(0, 0, 10, 10)])
      ];
      expect(identical(vectorShown(shapes), shapes), isTrue);
    });
  });

  group("set times", () {
    test("are real frames, not fitted to the arrival", () {
      var shapes = [
        VectorShape(paths: [box(0, 0, 10, 10)], cueLength: 10),
        VectorShape(
            paths: [box(20, 0, 10, 10)],
            cue: VectorCue.at,
            cueAt: 100,
            cueLength: 12),
      ];
      expect(vectorTimed(shapes), isTrue);
      expect(sequenced(shapes), isTrue);
      expect(cueTimes(shapes, 24), [(0.0, 10.0), (100.0, 12.0)],
          reason: "a 24-frame arrival doesn't squeeze frame 100 into it");
    });

    test("without one, shapes are still fitted as before", () {
      var shapes = [
        VectorShape(paths: [box(0, 0, 10, 10)], cueLength: 10),
        VectorShape(
            paths: [box(20, 0, 10, 10)], cue: VectorCue.after, cueLength: 10),
      ];
      expect(cueTimes(shapes, 40), [(0.0, 20.0), (20.0, 20.0)]);
    });
  });

  group("drawn", () {
    testWidgets("an arrowhead covers the tip, the line stops short of it",
        (tester) async {
      await tester.runAsync(() async {
        var e = drawingOf([
          VectorShape(
              paths: [lineRun(const Offset(20, 50), const Offset(180, 50))],
              stroke: const Color(0xFFFFFFFF),
              strokeWidth: 4,
              headEnd: VectorHead.arrow),
        ]);
        var b = await rendered(e);
        // The head is 16 wide at its back (4 x 4), 4.4 either side of the
        // line at 8 back from the tip: well past the 2-wide line.
        expect(alphaAt(b, 168, 46), greaterThan(100), reason: "head flank");
        expect(alphaAt(b, 100, 45), 0, reason: "the line itself is thin");
        expect(alphaAt(b, 100, 50), greaterThan(200));
      });
    });

    testWidgets("dashes leave gaps", (tester) async {
      await tester.runAsync(() async {
        var e = drawingOf([
          VectorShape(
              paths: [lineRun(const Offset(0, 50), const Offset(200, 50))],
              stroke: const Color(0xFFFFFFFF),
              strokeWidth: 2,
              dash: const [10, 10]),
        ]);
        var b = await rendered(e);
        expect(alphaAt(b, 5, 50), greaterThan(200), reason: "a dash");
        expect(alphaAt(b, 15, 50), 0, reason: "a gap");
        expect(alphaAt(b, 25, 50), greaterThan(200), reason: "the next dash");
      });
    });

    testWidgets("Draw on draws the line part of the way, the fill faint",
        (tester) async {
      await tester.runAsync(() async {
        var e = drawingOf([
          VectorShape(
              paths: [lineRun(const Offset(0, 20), const Offset(200, 20))],
              stroke: const Color(0xFFFFFFFF),
              strokeWidth: 4),
          VectorShape(
              paths: [box(0, 60, 200, 30)], fill: const Color(0xFFFFFFFF)),
        ]);
        var b = await rendered(e, drawn: 0.5);
        expect(alphaAt(b, 50, 20), greaterThan(200), reason: "drawn so far");
        expect(alphaAt(b, 150, 20), 0, reason: "not yet drawn");
        expect(alphaAt(b, 100, 75), closeTo(64, 3),
            reason: "the fill a quarter in at half way");
        var whole = await rendered(e);
        expect(alphaAt(whole, 150, 20), greaterThan(200));
        expect(alphaAt(whole, 100, 75), 255);
      });
    });

    testWidgets("a label-only shape is its words, with no box filled",
        (tester) async {
      await tester.runAsync(() async {
        var e = drawingOf([
          const VectorShape(
              paths: [],
              fill: Color(0xFFFFFFFF),
              label: VectorLabel(
                  text: "XX", size: 20, at: Offset(10, 10), width: 180)),
        ]);
        var b = await rendered(e);
        // The test font draws each letter as a block from the left.
        expect(alphaAt(b, 15, 20), greaterThan(200), reason: "a letter");
        expect(alphaAt(b, 150, 20), 0, reason: "no box behind the words");
        expect(vectorShapePath(e.shapes!.first).getBounds(),
            const Rect.fromLTWH(10, 10, 180, 24),
            reason: "picked and boxed by where its words sit");
      });
    });
  });

  group("bound to a sheet", () {
    var sheet = const DataSheet(id: "s1", name: "Bench", cells: [
      ["", "ns"],
      ["Before", "214"],
      ["After", "=B2/2"],
    ]);

    VectorShape bar(String cell) => VectorShape(
        paths: [box(0, 0, 200, 20)],
        fill: const Color(0xFFFFFFFF),
        bind: VectorBind(sheet: "s1", cell: cell, max: 214));

    test("reads its cell, a formula's worked out, and stretches from its left",
        () {
      expect(
          boundValue([sheet], const VectorBind(sheet: "s1", cell: "B3")), 107);
      expect(boundValue([sheet], const VectorBind(sheet: "Bench", cell: "b2")),
          214,
          reason: "by name, any case");
      var doc = const CanvasDocument()
          .copyWith(sheets: [sheet]).addElement(drawingOf([bar("B3")]));
      var bound = vectorsBound(doc);
      var v = bound.elementById("v") as VectorElement;
      expect(v.shapes!.first.bind!.value, 107);
      expect(vectorShown(v.shapes!).first.path.getBounds(),
          const Rect.fromLTWH(0, 0, 100, 20));
      expect(identical(vectorsBound(bound), bound), isTrue,
          reason: "nothing to do the second time");
    });

    test("a sheet changed re-reads every bound shape", () {
      var was = const CanvasDocument()
          .copyWith(sheets: [sheet]).addElement(drawingOf([bar("B2")]));
      was = vectorsBound(was);
      var next = was.copyWith(sheets: [
        DataSheet(id: "s1", name: "Bench", cells: [
          ...sheet.cells.take(1),
          ["Before", "53.5"],
          ...sheet.cells.skip(2),
        ]),
      ]);
      var synced = dataSynced(was, next);
      var v = synced.elementById("v") as VectorElement;
      expect(v.shapes!.first.bind!.value, 53.5);
    });

    test("with its sheet gone, a bound shape keeps its last value", () {
      var doc = const CanvasDocument().addElement(drawingOf([
        VectorShape(
            paths: [box(0, 0, 200, 20)],
            bind: const VectorBind(
                sheet: "gone", cell: "B2", max: 214, value: 29)),
      ]));
      var v = vectorsBound(doc).elementById("v") as VectorElement;
      expect(v.shapes!.first.bind!.value, 29);
    });
  });

  group("the panel", () {
    Future<CanvasController> show(WidgetTester tester, VectorElement e) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      setTestScreen(tester, const Size(1400, 1600));
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await tester.pumpAndSettle();
      c.editVector("v");
      c.pickVectorShape(0);
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> openMoreOf(WidgetTester tester, String remember) async {
      // In a card a "more" group shows everything: no button to press.
      var more = find.byKey(ValueKey("more-$remember"));
      if (more.evaluate().isEmpty) return;
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
    }

    VectorShape first(CanvasController c) =>
        (c.document.elementById("v") as VectorElement).shapes!.first;

    testWidgets("Words set the picked shape's label", (tester) async {
      var c = await show(
          tester,
          drawingOf([
            VectorShape(
                paths: [box(20, 20, 100, 40)], fill: const Color(0xFF888888)),
          ]));
      var words = find.descendant(
          of: find.byKey(const ValueKey("vectorLabelText")),
          matching: find.byType(EditableText));
      await tester.ensureVisible(words);
      await tester.enterText(words, "Limb");
      await tester.pumpAndSettle();
      expect(first(c).label?.text, "Limb");
      expect(first(c).label?.at, const Offset(20, 20),
          reason: "across the top of the shape");
    });

    testWidgets("line ends, dashes and copies change the shape",
        (tester) async {
      var c = await show(
          tester,
          drawingOf([
            VectorShape(
                paths: [lineRun(const Offset(10, 10), const Offset(90, 10))],
                stroke: const Color(0xFFFFFFFF),
                strokeWidth: 2),
          ]));
      await openMoreOf(tester, "vectorShapeMore");
      void pick<T>(String key, T value) => tester
          .widget<CanvasDropdown<T>>(find.byKey(ValueKey(key)))
          .onChanged(value);
      pick("vectorHeadEnd", VectorHead.arrow);
      await tester.pumpAndSettle();
      expect(first(c).headEnd, VectorHead.arrow);
      expect(find.byKey(const ValueKey("vectorHeadSize")), findsOneWidget,
          reason: "a head brings its size");
      pick("vectorDash", 1);
      await tester.pumpAndSettle();
      expect(first(c).dash, [6, 4]);

      await openMoreOf(tester, "vectorShapeExtrasMore");
      await typeNumber(tester, "vectorRepeatCount", "4");
      expect(first(c).repeat?.count, 4);
      expect(
          vectorShown((c.document.elementById("v") as VectorElement).shapes!),
          hasLength(4));
    });
  });

  test("Draw on is an arrival every element can take", () {
    expect(
        ElementAnimationPreset.values, contains(ElementAnimationPreset.drawOn));
  });
}
