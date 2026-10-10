import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_background_tech_test.dart is the Grids & tech family after its
// rework: the two styles folded into others, the settings each was given,
// and that a document saved before any of it is the same picture.

const int _w = 160, _h = 90;
const Rect _page = Rect.fromLTWH(0, 0, 160, 90);

Future<List<int>> _pixels(ProceduralSpec spec, {double time = 0}) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec, time: time, frameRate: 30);
  var picture = recorder.endRecording();
  var image = await picture.toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  var out = [
    for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i),
  ];
  image.dispose();
  picture.dispose();
  return out;
}

const _dark = ProceduralSpec(
  background: Color(0xFF000000),
  foreground: Color(0xFFFFFFFF),
  accent: Color(0xFFFF0000),
  vignette: 0,
  seed: 4,
  density: 0.7,
);

void main() {
  group("styles folded into others", () {
    testWidgets("an LED wall saved on its own opens as a dot grid, unchanged",
        (tester) async {
      var old = _dark.copyWith(style: ProceduralStyle.ledGrid);
      var json = old.toJson();
      expect(json["style"], "ledGrid");
      var opened = ProceduralSpec.fromJson(json);
      expect(opened.style, ProceduralStyle.dotGrid);
      expect(opened.choice("dotKind"), 1);
      late List<int> before, after;
      await tester.runAsync(() async {
        before = await _pixels(old);
        after = await _pixels(opened);
      });
      expect(after, before);
    });

    testWidgets("a symbol field opens as rain that scatters, unchanged",
        (tester) async {
      var old = _dark.copyWith(style: ProceduralStyle.symbolField);
      var opened = ProceduralSpec.fromJson(old.toJson());
      expect(opened.style, ProceduralStyle.rain);
      expect(opened.choice("mode"), 1);
      late List<int> before, after;
      await tester.runAsync(() async {
        before = await _pixels(old);
        after = await _pixels(opened);
      });
      expect(after, before);
    });

    test("are no longer offered, and have no looks of their own", () {
      expect(ProceduralStyle.ledGrid.hidden, isTrue);
      expect(ProceduralStyle.symbolField.hidden, isTrue);
      expect(looksFor(ProceduralStyle.ledGrid), isEmpty);
      expect(looksFor(ProceduralStyle.symbolField), isEmpty);
    });
  });

  group("the line grid", () {
    testWidgets("laid as a floor, draws nothing above its horizon",
        (tester) async {
      var floor = _dark.copyWith(
          style: ProceduralStyle.lineGrid,
          params: {"gridLayout": GridLayout.perspective.toDouble()});
      late List<int> px;
      await tester.runAsync(() async => px = await _pixels(floor));
      // The horizon is a little under half way down.
      bool lit(int p) => (p >> 8) & 0xFFFFFF != 0;
      var above = [
        for (var y = 0; y < 35; y++)
          for (var x = 0; x < _w; x++) px[y * _w + x]
      ];
      var below = [
        for (var y = 60; y < _h; y++)
          for (var x = 0; x < _w; x++) px[y * _w + x]
      ];
      expect(above.where(lit), isEmpty);
      expect(below.where(lit).length, greaterThan(200));
    });

    testWidgets("and with a sun, puts it above the horizon", (tester) async {
      var floor = _dark.copyWith(style: ProceduralStyle.lineGrid, params: {
        "gridLayout": GridLayout.perspective.toDouble(),
        "sun": 1,
      });
      late List<int> px;
      await tester.runAsync(() async => px = await _pixels(floor));
      var red = (px[30 * _w + 80] >> 24) & 0xFF;
      expect(red, greaterThan(120), reason: "the sun is the accent at its top");
    });

    testWidgets("moves when animated, which it could not before",
        (tester) async {
      var grid =
          _dark.copyWith(style: ProceduralStyle.lineGrid, animated: true);
      expect(ProceduralStyle.lineGrid.canAnimate, isTrue);
      late List<int> a, b;
      await tester.runAsync(() async {
        a = await _pixels(grid, time: 0);
        b = await _pixels(grid, time: 1.3);
      });
      expect(a, isNot(b));
    });
  });

  group("the other settings reach the picture", () {
    for (var (style, id, value) in [
      (ProceduralStyle.dotGrid, "dotShape", 1.0),
      (ProceduralStyle.dotGrid, "layout", 1.0),
      (ProceduralStyle.dotGrid, "shading", 2.0),
      (ProceduralStyle.hexGrid, "hexStyle", 2.0),
      (ProceduralStyle.hexGrid, "gap", 0.3),
      (ProceduralStyle.lineGrid, "major", 2.0),
      (ProceduralStyle.circuit, "corners", 1.0),
      (ProceduralStyle.circuit, "chips", 1.0),
      (ProceduralStyle.circuit, "pulses", 1.0),
      (ProceduralStyle.circuit, "pads", 1.0),
      (ProceduralStyle.rain, "direction", 1.0),
      (ProceduralStyle.rain, "trail", 2.0),
    ]) {
      testWidgets("${style.label}: $id", (tester) async {
        var plain = _dark.copyWith(style: style);
        late List<int> a, b;
        await tester.runAsync(() async {
          a = await _pixels(plain);
          b = await _pixels(plain.withParam(id, value));
        });
        expect(a, isNot(b));
      });
    }
  });

  group("the panel", () {
    Future<ProceduralSpec Function()> pump(
        WidgetTester tester, ProceduralSpec start) async {
      var current = start;
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasControlScope(
                maxWidth: 300,
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) => ProceduralSettings(
                      spec: current,
                      onChanged: (s) => setState(() => current = s),
                      onBegin: () {},
                      onCommit: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => current;
    }

    testWidgets("does not list the styles folded into others", (tester) async {
      await pump(tester, const ProceduralSpec());
      await tester.tap(find.byKey(const ValueKey("backgroundStyle")));
      await tester.pumpAndSettle();
      expect(find.text("Dot grid"), findsWidgets);
      expect(find.text("LED grid"), findsNothing);
      expect(find.text("Symbol field"), findsNothing);
    });

    testWidgets("offers sets of characters for the rain", (tester) async {
      var spec =
          await pump(tester, _dark.copyWith(style: ProceduralStyle.rain));
      await tester.tap(find.byKey(const ValueKey("glyphSet")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Binary").last);
      await tester.pumpAndSettle();
      expect(spec().glyphs, "01");
    });

    testWidgets("hides the dot settings behind an LED wall", (tester) async {
      await pump(
          tester,
          _dark.copyWith(
              style: ProceduralStyle.dotGrid, params: {"dotKind": 1}));
      expect(find.byKey(const ValueKey("param-dotShape")), findsNothing);
      expect(find.byKey(const ValueKey("param-unlit")), findsOneWidget);
    });
  });
}
