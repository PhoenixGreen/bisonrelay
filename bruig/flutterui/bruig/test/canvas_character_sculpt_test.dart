import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_paint.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_shape.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_touchup_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// A new 3D character shaped by hand: strokes of a brush, kept with the
// character, raising, lowering or flattening the surface under them. Picking
// the place on the body and drawing it need a GPU, so they are checked in
// the app; what a stroke does to the mesh, and the panel, are checked here.

/// _sheet is two flat sheets of skin a centimetre apart, 20 cm square with
/// a point every centimetre: the front facing +z at z = 0, the back facing
/// -z behind it, as the two sides of something thin are.
VrmMeshData _sheet() {
  const n = 21;
  final pos = <double>[], nrm = <double>[], idx = <int>[], uv = <double>[];
  for (final (z, nz, u0) in const [(0.0, 1.0, 0.0), (-0.01, -1.0, 0.5)]) {
    final base = pos.length ~/ 3;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        pos.addAll([-0.1 + i * 0.01, 1.0 + j * 0.01, z]);
        nrm.addAll([0, 0, nz]);
        // The front laid out on the left half of a picture, the back on
        // the right, each a half-picture square from the top down.
        uv.addAll([u0 + i / (n - 1) * 0.5, 1 - j / (n - 1)]);
      }
    }
    for (var j = 0; j + 1 < n; j++) {
      for (var i = 0; i + 1 < n; i++) {
        final a = base + j * n + i;
        idx.addAll([a, a + 1, a + n, a + 1, a + n + 1, a + n]);
      }
    }
  }
  final count = pos.length ~/ 3;
  final p = VrmPrimitive(
    material: 'Body_SKIN',
    vertices: VrmVertices(
        positions: Float32List.fromList(pos),
        normals: Float32List.fromList(nrm),
        uv0: Float32List.fromList(uv),
        uv1: Float32List(count * 2),
        colors: Float32List(count * 4)..fillRange(0, count * 4, 1),
        tangents: Float32List(count * 4),
        joints: Float32List(0),
        weights: Float32List(0),
        skinned: false),
    indices: Uint32List.fromList(idx),
    indices32: true,
  );
  return VrmMeshData([
    VrmMeshNode('Body', [p], const [])
  ], const {}, const {});
}

/// _at is the index of the front vertex at ([x], [y]) in centimetres from
/// the sheet's middle and bottom; [back] the one behind it.
int _at(int x, int y, {bool back = false}) =>
    (back ? 21 * 21 : 0) + y * 21 + x + 10;

SculptStroke _stroke(SculptTool tool,
        {List<(double, double)> at = const [(0, 1.1)],
        bool mirror = false,
        double strength = 0.9}) =>
    SculptStroke(
        tool: tool,
        radius: 0.03,
        strength: strength,
        mirror: mirror,
        points: [for (final (x, y) in at) SculptPoint(x, y, 0, 0, 0, 1)]);

void main() {
  final rig = VrmShapeRig(_sheet());
  final g = rig.groups.single;
  Float32List shaped(List<SculptStroke> strokes) =>
      rig.shape(g, StrokeDeformer.of(strokes))?.positions ??
      g.vertices.positions;
  double z(Float32List p, int i) => p[i * 3 + 2];

  group('a stroke', () {
    test('raises the surface under it, most in the middle, to its edge', () {
      final p = shaped([_stroke(SculptTool.raise)]);
      // A third of the radius at full strength: 0.03 * 0.9 / 3.
      expect(z(p, _at(0, 10)), closeTo(0.009, 1e-6));
      expect(z(p, _at(1, 10)), inExclusiveRange(0, 0.009));
      expect(z(p, _at(4, 10)), 0, reason: 'past the brush');
      expect(z(p, _at(0, 10, back: true)), closeTo(-0.01, 1e-7),
          reason: 'not the far side of something thin');
    });

    test('lowers it, the same way down', () {
      final p = shaped([_stroke(SculptTool.lower)]);
      expect(z(p, _at(0, 10)), closeTo(-0.009, 1e-6));
    });

    test('drawn slowly is no deeper than drawn fast', () {
      final slow = shaped([
        _stroke(SculptTool.raise, at: [
          for (var k = 0; k < 10; k++) (0.0005 * k, 1.1),
        ])
      ]);
      expect(z(slow, _at(0, 10)), lessThanOrEqualTo(0.009 + 1e-6));
    });

    test('drawn on both sides, as a mirror image', () {
      final one = shaped([
        _stroke(SculptTool.raise, at: [(0.06, 1.1)])
      ]);
      final both = shaped([
        _stroke(SculptTool.raise, at: [(0.06, 1.1)], mirror: true)
      ]);
      expect(z(one, _at(-6, 10)), 0);
      expect(z(both, _at(-6, 10)), closeTo(z(both, _at(6, 10)), 1e-7));
      expect(z(both, _at(6, 10)), greaterThan(0));
    });

    test('flattens toward the surface where it passed', () {
      // A bump, then pressed flat from its edge.
      final bump = _stroke(SculptTool.raise);
      final pressed = shaped([
        bump,
        _stroke(SculptTool.flatten, at: [(0.03, 1.1)], strength: 1),
      ]);
      expect(z(pressed, _at(1, 10)), lessThan(z(shaped([bump]), _at(1, 10))));
    });

    test('changes the shaping\'s key, so the body is shaped again', () {
      final a = StrokeDeformer.of([_stroke(SculptTool.raise)]);
      final b = StrokeDeformer.of([
        _stroke(SculptTool.raise).withPoint(const SculptPoint(0, 1, 0, 0, 0, 1))
      ]);
      expect(a.single.key, isNot(b.single.key));
      expect(StrokeDeformer.of([_stroke(SculptTool.raise, mirror: true)]),
          hasLength(2));
    });
  });

  group('kept', () {
    test('with the character, and read back the same', () {
      final d = CharacterDesign(
          id: 'c',
          name: 'Jess',
          body: 'Vivi',
          sculpt: [
            _stroke(SculptTool.flatten, at: [(0.1234567, 1.1), (0.2, 1.2)])
          ],
          updated: DateTime(2026, 11, 3));
      final back =
          CharacterDesign.fromJson(jsonDecode(jsonEncode(d.toJson())))!;
      final s = back.sculpt.single;
      expect((s.tool, s.radius, s.strength, s.points.length),
          (SculptTool.flatten, 0.03, 0.9, 2));
      expect(s.points.first.x, closeTo(0.12346, 1e-9),
          reason: 'to a hundredth of a millimetre');
      expect(
          CharacterDesign.fromJson(jsonDecode(jsonEncode(CharacterDesign(
                      id: 'c', name: '', body: 'Vivi', updated: DateTime(2026))
                  .toJson())))!
              .sculpt,
          isEmpty);
    });

    test('what is not a stroke is passed over', () {
      expect(SculptStroke.fromJson({'radius': 0.1, 'strength': 1}), isNull);
      expect(
          SculptStroke.fromJson({
            'radius': 0.1,
            'strength': 1,
            'points': [1, 2, 3]
          }),
          isNull,
          reason: 'six numbers a point');
      final s = SculptStroke.fromJson({
        'tool': 'chisel',
        'radius': 9,
        'strength': -1,
        'points': [0, 1, 0, 0, 0, 1]
      })!;
      expect((s.tool, s.radius, s.strength), (SculptTool.raise, 0.5, 0.0));
    });
  });

  group('the panel', () {
    Future<void> show(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
            home: Scaffold(body: SizedBox(width: 330, child: child))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the brush, taking back a stroke, and clearing them',
        (tester) async {
      var brush = const TouchBrush();
      var strokes = [_stroke(SculptTool.raise), _stroke(SculptTool.lower)];
      await show(
          tester,
          StatefulBuilder(
              builder: (context, set) => CharacterTouchUpControls(
                  brush: brush,
                  strokes: strokes,
                  onBrush: (b) => set(() => brush = b),
                  onStrokes: (s) => set(() => strokes = s))));
      expect(find.text('2 strokes.'), findsOneWidget);
      await tester.tap(find
          .byKey(const ValueKey('studioPill-sculpt-tool-SculptTool.flatten')));
      await tester.pumpAndSettle();
      expect(brush.tool, SculptTool.flatten);
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('sculpt-size')))
          .onChanged(0.1);
      await tester.pumpAndSettle();
      expect(brush.size, 0.1);
      await tester
          .tap(find.byKey(const ValueKey('studioPill-sculpt-mirror-false')));
      await tester.pumpAndSettle();
      expect(brush.mirror, isFalse);
      await tester.tap(find.byKey(const ValueKey('sculptUndo')));
      await tester.pumpAndSettle();
      expect(strokes.single.tool, SculptTool.raise);
      await tester.tap(find.byKey(const ValueKey('studioPartReset')));
      await tester.pumpAndSettle();
      expect(strokes, isEmpty);
      expect(find.text('Nothing touched up yet.'), findsOneWidget);
    });

    testWidgets('Touch up is in the list, marked once the body is touched',
        (tester) async {
      String? picked;
      await show(
          tester,
          CharacterShapeList(
              shape: const CharacterShape(),
              touched: true,
              selected: 'age',
              onSelect: (id) => picked = id));
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('shapePart-$touchUpPartId')), 200);
      expect(find.byKey(const ValueKey('shapeChanged-$touchUpPartId')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shapePart-$touchUpPartId')));
      expect(picked, touchUpPartId);
    });

    testWidgets('at every text size, nothing overflows', (tester) async {
      for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
        await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
          create: (_) => ThemeNotifier(doLoad: false),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                  size: const Size(1000, 800),
                  textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SizedBox(
                    width: 330,
                    child: CharacterTouchUpControls(
                        brush: const TouchBrush(),
                        strokes: [_stroke(SculptTool.raise)],
                        onBrush: (_) {},
                        onStrokes: (_) {})),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${scale}x');
      }
    });
  });

  group('paint', () {
    final vs = g.vertices;
    PaintLayer? layer(List<PaintStroke> strokes,
            {bool cells = false, int size = 256}) =>
        paintLayer(
            positions: vs.positions,
            normals: vs.normals,
            uv: vs.uv0,
            triangles: g.triangles,
            strokes: strokes,
            size: size,
            cells: cells);
    PaintStroke stroke(
            {List<(double, double)> at = const [(0, 1.1)],
            PaintTool tool = PaintTool.paint,
            double opacity = 1,
            double softness = 0,
            bool mirror = false}) =>
        PaintStroke(
            on: 'skin',
            tool: tool,
            colour: 0xff0000,
            radius: 0.02,
            opacity: opacity,
            softness: softness,
            mirror: mirror,
            points: [for (final (x, y) in at) SculptPoint(x, y, 0, 0, 0, 1)]);
    // The pixel of a 256 picture where the front is at ([x], [y]).
    List<int> px(PaintLayer l, double x, double y) {
      final u = (x + 0.1) / 0.2 * 0.5, v = 1 - (y - 1.0) / 0.2;
      final i = ((v * l.size).floor().clamp(0, l.size - 1) * l.size +
              (u * l.size).floor().clamp(0, l.size - 1)) *
          4;
      return l.rgba.sublist(i, i + 4);
    }

    test('lies where the stroke passed, in its colour, to its edge', () {
      final l = layer([stroke()])!;
      expect(px(l, 0, 1.1), [255, 0, 0, 255]);
      expect(px(l, 0.015, 1.1)[3], 255, reason: 'inside the brush');
      expect(px(l, 0.04, 1.1)[3], 0, reason: 'past it');
      // Not on the back: the right half of the picture is clear.
      for (var i = 0; i < l.size * l.size; i++) {
        if (i % l.size >= l.size / 2 + 2) expect(l.rgba[i * 4 + 3], 0);
      }
      expect(l.triangles.length, lessThan(g.triangles.length ~/ 4),
          reason: 'only the triangles painted');
    });

    test('a soft brush fades from the middle', () {
      final l = layer([stroke(softness: 1)])!;
      expect(px(l, 0, 1.1)[3], greaterThan(px(l, 0.01, 1.1)[3]));
      expect(px(l, 0.01, 1.1)[3], greaterThan(0));
    });

    test('a stroke over itself is no thicker than its opacity', () {
      final l = layer([
        stroke(opacity: 0.5, at: [for (var k = 0; k < 8; k++) (0.001 * k, 1.1)])
      ])!;
      expect(px(l, 0.003, 1.1)[3], closeTo(128, 2));
    });

    test('mirrored, on both sides; rubbed out, gone', () {
      final both = layer([
        stroke(at: [(0.05, 1.1)], mirror: true)
      ])!;
      expect(px(both, -0.05, 1.1)[3], 255);
      final rubbed = layer([
        stroke(),
        stroke(tool: PaintTool.rubOut),
      ])!;
      expect(px(rubbed, 0, 1.1)[3], 0);
      expect(
          layer([
            stroke(at: [(0.5, 1.1)])
          ]),
          isNull,
          reason: 'off it');
    });

    test('laid out in cells of its own, each triangle its own corners', () {
      final l = layer([stroke()], cells: true)!;
      final src = l.source!, uv = l.uv!;
      expect(l.triangles.length, src.length);
      expect(uv.length, src.length * 2);
      expect(uv.every((v) => v >= 0 && v <= 1), isTrue);
      expect(l.rgba.where((v) => v == 255).length, greaterThan(100),
          reason: 'painted');
      // Each corner is one of the surface's vertices near the stroke.
      for (final o in src) {
        final x = vs.positions[o * 3], y = vs.positions[o * 3 + 1];
        expect((x * x + (y - 1.1) * (y - 1.1)), lessThan(0.04 * 0.04));
      }
    });

    test('kept with the character, and what is not a stroke passed over', () {
      final d = CharacterDesign(
          id: 'c',
          name: '',
          body: 'Vivi',
          paint: [stroke(mirror: true, softness: 0.3)],
          updated: DateTime(2026));
      final back =
          CharacterDesign.fromJson(jsonDecode(jsonEncode(d.toJson())))!;
      final p = back.paint.single;
      expect((p.on, p.colour, p.radius, p.softness, p.mirror, p.points.length),
          ('skin', 0xff0000, 0.02, 0.3, true, 1));
      expect(
          PaintStroke.fromJson({
            'radius': 0.1,
            'points': [0, 0, 0, 0, 0, 1]
          }),
          isNull,
          reason: 'on nothing');
    });

    testWidgets('the panel paints: its colours, opacity, softness',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var brush = const TouchBrush();
      var painted = [stroke(), stroke()];
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 330,
                    child: StatefulBuilder(
                        builder: (context, set) => CharacterTouchUpControls(
                            brush: brush,
                            strokes: const [],
                            paint: painted,
                            onBrush: (b) => set(() => brush = b),
                            onStrokes: (_) {},
                            onPaint: (p) => set(() => painted = p)))))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paint-opacity')), findsNothing);
      await tester.tap(
          find.byKey(const ValueKey('studioPill-touch-mode-TouchMode.paint')));
      await tester.pumpAndSettle();
      expect(brush.mode, TouchMode.paint);
      expect(brush.size, lessThanOrEqualTo(0.02), reason: 'a finer brush');
      expect(find.text('2 strokes.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('paint-colour-e88aa8')));
      await tester.pumpAndSettle();
      expect(brush.colour, 0xe88aa8);
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('paint-softness')))
          .onChanged(0.8);
      await tester.pumpAndSettle();
      expect(brush.softness, 0.8);
      await tester.tap(
          find.byKey(const ValueKey('studioPill-paint-tool-PaintTool.rubOut')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paint-colour-e88aa8')), findsNothing,
          reason: 'rubbing out has no colour');
      await tester.tap(find.byKey(const ValueKey('sculptUndo')));
      await tester.pumpAndSettle();
      expect(painted, hasLength(1));
    });
  });
}
