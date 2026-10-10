import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_layers.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_background_layers_test.dart is the patterns laid over a
// background: how they are saved, how they are drawn, and the list in the
// settings that adds, orders, hides and edits them.

const int _w = 160, _h = 90;
const Rect _page = Rect.fromLTWH(0, 0, 160, 90);

Future<List<int>> _pixels(ProceduralSpec spec) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec, time: 1, frameRate: 30);
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

const _base = ProceduralSpec(
  style: ProceduralStyle.dotGrid,
  background: Color(0xFF202020),
  foreground: Color(0xFFFFFFFF),
  accent: Color(0xFFFFFFFF),
  vignette: 0,
);

const _grid = BackgroundLayer(
  spec: ProceduralSpec(
    style: ProceduralStyle.lineGrid,
    foreground: Color(0xFF00FF00),
    accent: Color(0xFF00FF00),
    intensity: 1,
  ),
);

void main() {
  group("saved", () {
    test("with their opacity, blend and whether they are shown", () {
      var spec = _base.copyWith(layers: [
        _grid.copyWith(opacity: 0.4, blend: LayerBlend.multiply),
        _grid.copyWith(visible: false),
      ]);
      var back = ProceduralSpec.fromJson(spec.toJson());
      expect(back.layers, hasLength(2));
      expect(back.layers[0].opacity, 0.4);
      expect(back.layers[0].blend, LayerBlend.multiply);
      expect(back.layers[0].spec.style, ProceduralStyle.lineGrid);
      expect(back.layers[1].visible, isFalse);
      expect(_base.toJson().containsKey("layers"), isFalse);
    });

    test("never with layers of their own, and no more than three", () {
      var nested = _grid.copyWith(spec: _grid.spec.copyWith(layers: [_grid]));
      var json = _base.copyWith(layers: [nested, _grid, _grid, _grid]).toJson();
      var back = ProceduralSpec.fromJson(json);
      expect(back.layers, hasLength(maxBackgroundLayers));
      expect(back.layers.first.spec.layers, isEmpty);
    });
  });

  group("drawn", () {
    testWidgets("over the background, and not at all when hidden or clear",
        (tester) async {
      late List<int> none, shown, hidden, clear;
      await tester.runAsync(() async {
        none = await _pixels(_base);
        shown = await _pixels(_base.copyWith(layers: [_grid]));
        hidden = await _pixels(
            _base.copyWith(layers: [_grid.copyWith(visible: false)]));
        clear =
            await _pixels(_base.copyWith(layers: [_grid.copyWith(opacity: 0)]));
      });
      expect(shown, isNot(none));
      expect(hidden, none);
      expect(clear, none);
    });

    testWidgets("a plain layer is a wash of its colour", (tester) async {
      var wash = BackgroundLayer(
          spec: const ProceduralSpec(background: Color(0xFFFF0000)),
          opacity: 0.5);
      late List<int> px;
      await tester.runAsync(
          () async => px = await _pixels(_base.copyWith(layers: [wash])));
      // A corner the dots do not reach: half way from the grey to red.
      var p = px[0];
      expect((p >> 24) & 0xFF, closeTo(0x8F, 6));
      expect((p >> 16) & 0xFF, closeTo(0x10, 6));
    });

    testWidgets("multiplied, a layer can only darken", (tester) async {
      var dark = BackgroundLayer(
          spec: const ProceduralSpec(background: Color(0xFF808080)),
          blend: LayerBlend.multiply);
      late List<int> before, after;
      await tester.runAsync(() async {
        before = await _pixels(_base);
        after = await _pixels(_base.copyWith(layers: [dark]));
      });
      for (var i = 0; i < before.length; i += 97) {
        expect((after[i] >> 24) & 0xFF,
            lessThanOrEqualTo((before[i] >> 24) & 0xFF));
      }
    });
  });

  group("looks", () {
    test("keep the layers somebody laid over the background", () {
      var spec = _base.copyWith(layers: [_grid]);
      var look = looksFor(ProceduralStyle.bokeh).first;
      expect(withLook(spec, look).layers, hasLength(1));
      expect(lookMatching(withLook(spec, look)), same(look));
    });

    test("that are stacks bring their own layers with them", () {
      var stack = [
        for (var s in ProceduralStyle.values)
          for (var l in looksFor(s))
            if (l.spec.layers.isNotEmpty) l,
      ];
      expect(stack, isNotEmpty);
      for (var look in stack) {
        expect(withLook(_base.copyWith(layers: [_grid, _grid]), look).layers,
            look.spec.layers,
            reason: look.name);
      }
    });
  });

  group("the list", () {
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

    testWidgets("adds a layer, and goes straight to its settings",
        (tester) async {
      var spec = await pump(tester, _base);
      await tester.tap(find.byKey(const ValueKey("addLayer")));
      await tester.pumpAndSettle();
      expect(spec().layers, hasLength(1));
      expect(find.byKey(const ValueKey("layerOpacity")), findsOneWidget);
      // A layer's settings, not the background's: no light, no base.
      expect(find.text("LIGHTS"), findsNothing);
      expect(find.text("Base"), findsNothing);
    });

    testWidgets("edits a layer's blend and its own pattern", (tester) async {
      var spec = await pump(tester, _base.copyWith(layers: [_grid]));
      await tester.tap(find.byKey(const ValueKey("layerRow-1")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("layerBlend")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Overlay").last);
      await tester.pumpAndSettle();
      expect(spec().layers.single.blend, LayerBlend.overlay);

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey("param-major")),
              matching: find.byType(EditableText)),
          "7");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(spec().layers.single.spec.p("major"), 7);
      expect(spec().style, ProceduralStyle.dotGrid,
          reason: "the background itself is untouched");
    });

    testWidgets("orders, hides and removes them", (tester) async {
      var a = _grid;
      var b = _grid.copyWith(spec: _grid.spec.copyWith(seed: 9));
      var spec = await pump(tester, _base.copyWith(layers: [a, b]));
      // Row 1 is the bottom layer; up puts it on top.
      await tester.tap(find.byKey(const ValueKey("layerUp-1")));
      await tester.pumpAndSettle();
      expect(spec().layers[1].spec.seed, a.spec.seed);
      expect(spec().layers[0].spec.seed, 9);

      await tester.tap(find.byKey(const ValueKey("layerEye-2")));
      await tester.pumpAndSettle();
      expect(spec().layers[1].visible, isFalse);

      await tester.tap(find.byKey(const ValueKey("layerDelete-1")));
      await tester.pumpAndSettle();
      expect(spec().layers, hasLength(1));
    });

    testWidgets("stops at three", (tester) async {
      var spec = await pump(tester, _base.copyWith(layers: [_grid, _grid]));
      await tester.tap(find.byKey(const ValueKey("addLayer")));
      await tester.pumpAndSettle();
      expect(spec().layers, hasLength(3));
      await tester.tap(find.byKey(const ValueKey("addLayer")));
      await tester.pumpAndSettle();
      expect(spec().layers, hasLength(3));
    });
  });
}
