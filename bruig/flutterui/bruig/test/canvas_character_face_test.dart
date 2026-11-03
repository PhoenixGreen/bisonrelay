import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/ui/character_face_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The Character Studio's Face step: an expression made from the face's own
// shapes, kept mixes, where the eyes look, a line said, and a scene's
// choice of expression on the canvas. Wearing it needs the GPU, and is
// checked in the app; what is worn, and the panel, are checked here.

void main() {
  group('the face', () {
    test('kept with the character, and read back the same', () {
      final f = CharacterFace(
          name: 'Grin',
          mix: faceExpressions['Shy']!.withUnit('MTH_Fun', 0.4),
          kept: {'Grin': faceExpressions['Laughing']!},
          blinks: false,
          glances: true);
      final d = CharacterDesign(
          id: 'c', name: '', body: 'Vivi', face: f, updated: DateTime(2026));
      final back =
          CharacterDesign.fromJson(jsonDecode(jsonEncode(d.toJson())))!.face;
      expect(back, f);
      expect(
          CharacterDesign.fromJson(jsonDecode(jsonEncode(CharacterDesign(
                      id: 'c', name: '', body: 'Vivi', updated: DateTime(2026))
                  .toJson())))!
              .face,
          const CharacterFace());
    });

    test('what cannot be read is kept to its range', () {
      final f = CharacterFace.fromJson({
        'mix': {
          'w': {'EYE_Joy': 3, 'MTH_A': 'wide'},
          'gazeX': -9,
          'tilt': 'left'
        },
        'blinks': 'no',
      });
      expect((f.mix.unit('EYE_Joy'), f.mix.w.length, f.mix.gazeX, f.mix.tilt),
          (1.0, 1, -1.0, 0.0));
      expect(f.blinks, isTrue);
    });

    test('an expression worn: its own, one to start from, or one kept', () {
      final f = CharacterFace(
          mix: const FaceMix(blush: 0.2),
          kept: {'Mine': const FaceMix(gazeX: 0.5)});
      expect(f.wearing(null).blush, 0.2);
      expect(f.wearing('Happy'), faceExpressions['Happy']);
      expect(f.wearing('Mine').gazeX, 0.5);
      expect(f.wearing('Gone').blush, 0.2, reason: 'its own, for one it lacks');
      expect(const FaceMix().withUnit('MTH_A', 0.3).withUnit('MTH_A', 0).w,
          isEmpty);
      expect(faceExpressions['Furious']!.withoutRegion('mouth').w.keys,
          unorderedEquals(['BRW_Angry', 'EYE_Angry', 'HA_Fung2']));
    });

    test('every shape it is made of is one of the face\'s', () {
      final all = {
        for (final r in faceUnits.values)
          for (final u in r) u.$1
      };
      for (final e in faceExpressions.values) {
        expect(all.containsAll(e.w.keys), isTrue);
      }
    });
  });

  group('a line said', () {
    test('opens the mouth for its vowels, shuts it between, then stops', () {
      final l = SpokenLine.of('Ha, ma.');
      // "H a , _ m a ." -- a beat each, the stops longer.
      double at(int beat, double into) =>
          (l.beats[beat].at + l.beats[beat].long * into) /
          SpokenLine.beatsPerSecond;
      expect(l.mouthAt(at(1, 0.3))!['MTH_A'], 1, reason: 'the a');
      expect(l.mouthAt(at(2, 0.3))!['MTH_A'] ?? 0, 0, reason: 'the comma');
      expect(l.beats[2].long, greaterThan(l.beats[3].long),
          reason: 'a comma is longer than a space');
      expect(l.mouthAt(at(4, 0.3))!, isEmpty, reason: 'm shuts it');
      expect(l.mouthAt(l.seconds + 0.1), isNull, reason: 'said');
      expect(l.mouthAt(at(1, 0.9))!['MTH_A']!, lessThan(1),
          reason: 'easing into the next');
    });
  });

  group('on the canvas', () {
    test('a scene\'s expression is kept, and put back as made', () {
      final e = Character3dElement(const ElementBase(id: 'c'),
              design: CharacterDesign(
                  id: 'd', name: '', body: 'Vivi', updated: DateTime(2026)))
          .wearing('Sad');
      final back = elementFromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)
          as Character3dElement;
      expect(back.expression, 'Sad');
      expect(back.copyWith(zoom: 2).expression, 'Sad');
      expect(back.wearing(null).toJson().containsKey('expression'), isFalse);
    });
  });

  group('the panel', () {
    Future<void> show(WidgetTester tester, Widget child,
        {double scale = 1}) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(
              size: const Size(900, 1800),
              textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: child),
        )),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an expression picked, changed, kept and forgotten',
        (tester) async {
      var f = const CharacterFace();
      var part = 'expressions';
      final said = <String>[];
      await show(
          tester,
          StatefulBuilder(
              builder: (context, set) => Row(children: [
                    SizedBox(
                        width: 220,
                        child: CharacterFaceList(
                            face: f,
                            selected: part,
                            onSelect: (p) => set(() => part = p),
                            onReset: (n) => set(() => f = n))),
                    SizedBox(
                        width: 330,
                        child: CharacterFaceControls(
                            key: ValueKey(part),
                            part: part,
                            face: f,
                            onChanged: (n) => set(() => f = n),
                            onSay: said.add)),
                  ])));
      await tester
          .tap(find.byKey(const ValueKey('studioPill-face-expr-Happy')));
      await tester.pumpAndSettle();
      expect((f.name, f.mix), ('Happy', faceExpressions['Happy']));
      expect(find.byKey(const ValueKey('faceChanged-expressions')),
          findsOneWidget);

      // The brows changed: marked, and put back.
      await tester.tap(find.byKey(const ValueKey('facePart-brows')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('faceChanged-brows')), findsNothing);
      tester
          .widget<StudioSlider>(
              find.byKey(const ValueKey('face-unit-BRW_Angry')))
          .onChanged(0.7);
      await tester.pumpAndSettle();
      expect(f.mix.unit('BRW_Angry'), 0.7);
      expect(find.byKey(const ValueKey('faceChanged-brows')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('studioPartReset')));
      await tester.pumpAndSettle();
      expect(f.mix, faceExpressions['Happy']);
      // And by its mark in the list.
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('face-unit-BRW_Joy')))
          .onChanged(0.1);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('faceChanged-brows')));
      await tester.pumpAndSettle();
      expect(f.mix, faceExpressions['Happy']);
      expect(find.byKey(const ValueKey('faceChanged-brows')), findsNothing);

      // Kept by a name, worn as it, and forgotten.
      await tester.tap(find.byKey(const ValueKey('facePart-blush')));
      await tester.pumpAndSettle();
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('face-blush')))
          .onChanged(0.9);
      await tester.tap(find.byKey(const ValueKey('facePart-expressions')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('faceKeepName')), 'Flustered');
      await tester.tap(find.byKey(const ValueKey('faceKeep')));
      await tester.pumpAndSettle();
      expect((f.name, f.kept['Flustered']?.blush), ('Flustered', 0.9));
      expect(find.byKey(const ValueKey('studioPill-face-expr-Flustered')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('faceForget')));
      await tester.pumpAndSettle();
      expect(f.name, 'Neutral');
      expect(f.kept, isEmpty);

      // Where it looks: dragged in the pad.
      await tester.tap(find.byKey(const ValueKey('facePart-look')));
      await tester.pumpAndSettle();
      final pad = tester.getRect(find.byKey(const ValueKey('faceLookPad')));
      await tester.tapAt(pad.topRight + const Offset(-1, 1));
      await tester.pumpAndSettle();
      expect(f.mix.gazeX, greaterThan(0.95));
      expect(f.mix.gazeY, greaterThan(0.95));

      // A line said; blinking switched off.
      await tester.tap(find.byKey(const ValueKey('facePart-speak')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('faceLine')), 'Hi there');
      await tester.tap(find.byKey(const ValueKey('faceSay')));
      expect(said, ['Hi there']);
      await tester.tap(find.byKey(const ValueKey('facePart-idle')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('studioPill-face-blinks-false')));
      await tester.pumpAndSettle();
      expect(f.blinks, isFalse);
      expect(find.byKey(const ValueKey('faceChanged-idle')), findsOneWidget);
    });

    testWidgets('at every text size, every part fits', (tester) async {
      for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
        for (final (id, _, _, _) in faceParts) {
          await show(
              tester,
              Row(children: [
                SizedBox(
                    width: 220,
                    child: CharacterFaceList(
                        face: const CharacterFace(),
                        selected: id,
                        onSelect: (_) {})),
                SizedBox(
                    width: 330,
                    child: CharacterFaceControls(
                        key: ValueKey('$id$scale'),
                        part: id,
                        face: const CharacterFace(name: 'Shy'),
                        onChanged: (_) {},
                        onSay: (_) {})),
              ]),
              scale: scale);
          expect(tester.takeException(), isNull, reason: '$id at ${scale}x');
        }
      }
    });
  });

  test('the face is in a design\'s document unchanged', () {
    // A canvas holding a character with a kept expression reads back with it.
    final d = CharacterDesign(
        id: 'd',
        name: 'Jess',
        body: 'Vivi',
        face: CharacterFace(kept: {'Mine': faceExpressions['Wink']!}),
        updated: DateTime(2026));
    final doc = CanvasDocument().addElement(Character3dElement(
        const ElementBase(id: 'c'),
        design: d,
        expression: 'Mine'));
    final back = CanvasDocument.fromJson(
        jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
    final e = back.elements.single as Character3dElement;
    expect(e.design.face.wearing(e.expression), faceExpressions['Wink']);
  });
}
