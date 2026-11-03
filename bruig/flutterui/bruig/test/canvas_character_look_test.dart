import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_colour.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_look.dart';
import 'package:bruig/plugin_system/canvas/ui/character_look_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// How a new 3D character is drawn: its look -- lines, shading, light,
// colour and finish -- and the colours picked for its hair, skin and eyes,
// with the pictures changed to draw them. The finish's shader and the
// materials it sets run on the GPU, which tests do not have, so what they
// are given is checked here and the drawing itself in the app.

Uint8List _pixels(List<List<int>> rgba) =>
    Uint8List.fromList([for (final p in rgba) ...p]);

void main() {
  group('the look', () {
    test('every look to start from is there, kept and read back the same', () {
      expect(characterLooks.keys, [
        'Anime cel', 'Clean ink', 'Flat', 'Soft 3D', 'Manga', 'Pencil', //
        'Watercolour', 'Painterly', 'Comic', 'Ink sketch', 'Pastel', 'Noir',
      ]);
      for (final l in characterLooks.values) {
        expect(
            CharacterLook.fromJson(
                jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>),
            l);
        for (final e in l.choices.entries) {
          expect(lookOptions[e.key]!.map((o) => o.$1), contains(e.value));
        }
      }
    });

    test('a setting changed by name changes only it, and junk is dropped', () {
      const l = CharacterLook();
      final ink = l
          .withNumber('width', 0.9)
          .withChoice('render', 'comic')
          .withLineColour(0x112233);
      expect((ink.width, ink.render, ink.lineColour, ink.inner),
          (0.9, 'comic', 0x112233, l.inner));
      final junk = CharacterLook.fromJson({
        'width': 'thick',
        'sat': -7,
        'render': 'oils',
        'paperColour': 'cream'
      });
      expect((junk.width, junk.sat, junk.render, junk.paperColour),
          (l.width, -1.0, l.render, l.paperColour));
    });
  });

  group('the finish', () {
    test('lines, finish and paper are given to the shader as it reads them',
        () {
      final u = finishUniforms(characterLooks['Comic']!, 2);
      expect(u.length, 32, reason: 'eight vec4s');
      expect(u[0], closeTo(0.85, 1e-6), reason: 'inner lines');
      expect(u[1], closeTo((0.7 + 0.95 * 0.9) * 2, 1e-6),
          reason: 'their reach, on a screen of two pixels a point');
      expect(u[4], closeTo((0.6 + 0.95 * 3.2) * 2, 1e-5),
          reason: 'the outline');
      expect(u[6], 5, reason: 'comic');
      expect(u.sublist(24, 27), [0, 0, 0], reason: 'black ink');
      expect(u[28], closeTo(0xf7 / 255, 1e-6), reason: 'cream paper');
      final none = finishUniforms(characterLooks['Soft 3D']!, 1);
      expect((none[0], none[2], none[4]), (0, 0, 0), reason: 'no lines at all');
      final pencil = finishUniforms(characterLooks['Pencil']!, 1);
      expect([pencil[2], pencil[3], pencil[4], pencil[5]],
          [closeTo(0.85, 1e-6), closeTo(1.4, 1e-6), 0, closeTo(0.8, 1e-6)],
          reason: 'a pencil outline wanders and is grainy, and is drawn by '
              'the silhouette, not round it');
    });

    test('the light comes from where the look says, as the viewer sees it', () {
      final left = lightDirection(const CharacterLook(light: 'left'));
      final right = lightDirection(const CharacterLook(light: 'right'));
      expect(left.length, closeTo(1, 1e-6));
      expect(left.x, -right.x, reason: 'mirror images');
      expect(left.y, lessThan(0), reason: 'shining down');
      expect(
          lightDirection(const CharacterLook(light: 'top')).y, lessThan(-0.9));
    });
  });

  group('the pictures', () {
    test('grey keeps the shading at an even lightness, and the transparency',
        () {
      final g = greyPixels(_pixels([
        [200, 40, 40, 255],
        [100, 20, 20, 255],
        [0, 0, 0, 0],
      ]));
      expect(g[0], g[1]);
      expect(g[1], g[2]);
      expect(g[0], greaterThan(g[4]), reason: 'the lighter stays lighter');
      expect((g[0] + g[4]) / 2, closeTo(215, 25));
      expect(g[11], 0);
    });

    test('flat tones move a colour only a little, toward its nearest tone', () {
      final f = flatPixels(
          _pixels([
            [240, 200, 180, 255],
            [90, 60, 40, 255],
          ]),
          4);
      for (var i = 0; i < 2; i++) {
        final before = [
          [240, 200, 180],
          [90, 60, 40]
        ][i];
        for (var c = 0; c < 3; c++) {
          expect((f[i * 4 + c] - before[c]).abs(), lessThan(40));
        }
      }
      expect(f[3], 255);
    });

    test('a picture\'s average, as the material colours it', () {
      final avg = averageColour(_pixels([
        [188, 189, 188, 255],
        [188, 189, 188, 255],
        [0, 0, 0, 0],
      ]));
      expect(avg, 0xbcbdbc);
      // VRoid draws hair in grey, coloured navy by its material.
      final navy = timesColour(avg, 0.02, 0.03, 0.12);
      expect((navy >> 16) & 0xff, lessThan(navy & 0xff), reason: 'blue');
      expect(timesColour(0xffffff, 1, 1, 1), 0xffffff);
      expect(mixColour(0x000000, 0xffffff, 0.5), 0x808080);
      final (r, g, b) = linearOf(0xffffff);
      expect((r, g, b), (1.0, 1.0, 1.0));
    });
  });

  group('colours', () {
    test('a colour is picked, and put back as made', () {
      final s = const CharacterShape().withColour('colour.hair', 0xa01a52);
      expect(s.colour('colour.hair'), 0xa01a52);
      final hair = characterShapeParts.firstWhere((p) => p.id == 'hair');
      expect(s.changed(hair), isTrue);
      expect(s.withColour('colour.hair', null).colour('colour.hair'), isNull);
      expect(s.reset(hair).colour('colour.hair'), isNull);
      expect(
          characterShapeParts.firstWhere((p) => p.id == 'skin').controls.single,
          isA<ShapeColour>());
    });

    test('hair greys from the forties, and is white by the seventies', () {
      expect(ageGrey(25), 0);
      expect(ageGrey(57), closeTo(0.5, 1e-9));
      expect(ageGrey(85), 1);
    });
  });

  group('the settings', () {
    Future<void> show(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
            home: Scaffold(body: SizedBox(width: 330, child: child))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a look, its dials, and each finish\'s own', (tester) async {
      var look = characterLooks['Anime cel']!;
      var name = 'Anime cel';
      await show(
          tester,
          StatefulBuilder(
              builder: (context, set) => CharacterLookControls(
                  look: look,
                  name: name,
                  onChanged: (l, n) => set(() {
                        look = l;
                        name = n;
                      }))));
      expect(find.byKey(const ValueKey('studioPartReset')), findsNothing);
      expect(find.byKey(const ValueKey('look-levels')), findsNothing,
          reason: 'Tones is for flat colour');
      expect(find.byKey(const ValueKey('look-tone')), findsNothing);
      await tester
          .tap(find.byKey(const ValueKey('studioPill-look-looks-Manga')));
      await tester.pumpAndSettle();
      expect((name, look.render), ('Manga', 'manga'));
      expect(find.byKey(const ValueKey('look-tone')), findsOneWidget,
          reason: 'screentone, for manga');
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('look-width')))
          .onChanged(0.2);
      await tester.pumpAndSettle();
      expect((look.width, name), (0.2, 'Manga'));
      expect(find.byKey(const ValueKey('studioPartReset')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('studioPill-look-fill-flat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('look-levels')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('look-paper-2a2a30')));
      await tester.pumpAndSettle();
      expect(look.paperColour, 0x2a2a30);
      await tester.tap(find.byKey(const ValueKey('studioPartReset')));
      await tester.pumpAndSettle();
      expect(look, characterLooks['Manga']);
    });

    testWidgets('colours are picked on their parts, as made first',
        (tester) async {
      var s = const CharacterShape();
      await show(
          tester,
          StatefulBuilder(
              builder: (context, set) => CharacterShapeControls(
                  part: characterShapeParts.firstWhere((p) => p.id == 'eyes'),
                  shape: s,
                  onChanged: (n) => set(() => s = n))));
      await tester.tap(find.byKey(const ValueKey('shape-colour.eyes-8a3d8f')));
      await tester.pumpAndSettle();
      expect(s.colour('colour.eyes'), 0x8a3d8f);
      await tester.tap(find.byKey(const ValueKey('shape-colour.eyes-made')));
      await tester.pumpAndSettle();
      expect(s.colour('colour.eyes'), isNull);
    });

    testWidgets('the Drawing style is in the list, marked once changed',
        (tester) async {
      String? picked;
      await show(
          tester,
          CharacterShapeList(
              shape: const CharacterShape(),
              styled: true,
              selected: 'age',
              onSelect: (id) => picked = id));
      expect(find.byKey(const ValueKey('shapeChanged-$stylePartId')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shapePart-$stylePartId')));
      expect(picked, stylePartId);
    });

    testWidgets('at every text size, nothing overflows', (tester) async {
      for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
        for (final l in const ['Watercolour', 'Comic']) {
          await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
            create: (_) => ThemeNotifier(doLoad: false),
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                    size: const Size(1000, 800),
                    textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Row(children: [
                    SizedBox(
                        width: 330,
                        child: CharacterLookControls(
                            look: characterLooks[l]!.withChoice('fill', 'flat'),
                            name: l,
                            onChanged: (_, __) {})),
                  ]),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$l at ${scale}x');
        }
      }
    });
  });
}
