import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/ui/character_move_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The Character Studio's Move step: how the character stands -- a stance,
// its hands, its feet, its body turned by hand. Standing it is solved on
// the avatar's own bones (vrm_pose.dart), which needs the GPU's scene and is
// checked in the app; what is kept, and the panel, are checked here.

void main() {
  test('kept with the character, and read back the same', () {
    const m = CharacterMove(
        stance: 'Fighting guard',
        handL: 'fist',
        handR: 'point',
        body: {'twist': 0.4, 'headNod': -0.2},
        footL: {'flex': -1, 'heel': 0.5},
        footR: {'toes': 0.3},
        motion: 'Run',
        speed: 1.5,
        walk: {'stride': 0.9},
        physics: {'hair': 1.8, 'wind': 0.4},
        offsets: {
          'handL': [0.1, -0.05, 0.2],
          'hips': [0, -0.1, 0]
        });
    final d = CharacterDesign(
        id: 'c', name: '', body: 'Vivi', move: m, updated: DateTime(2026));
    expect(
        CharacterDesign.fromJson(jsonDecode(jsonEncode(d.toJson())))!.move, m);
    expect(
        CharacterDesign(
                id: 'c', name: '', body: 'Vivi', updated: DateTime(2026))
            .toJson()
            .containsKey('move'),
        isFalse);
  });

  test('what cannot be read is kept to its range, or as made', () {
    final m = CharacterMove.fromJson({
      'stance': 'Handstand',
      'handL': 'claw',
      'body': {'twist': 4, 'wobble': 1, 'lean': 'far'},
      'footL': {'heel': -1},
    });
    expect((m.stance, m.handL, m.footOf('L', 'heel')),
        ('Relaxed', 'relaxed', -1.0));
    expect(m.body, {'twist': 1.0});
    expect(const CharacterMove().withBody('lean', 0.3).withBody('lean', 0).body,
        isEmpty);
    final odd = CharacterMove.fromJson({
      'motion': 'Moonwalk',
      'speed': 9,
      'walk': {'pace': 3, 'stride': 0.5},
      'physics': {'hair': 5, 'wind': -1},
    });
    expect((odd.motion, odd.speed), ('Idle', 2.0));
    expect(odd.walk, {'pace': 1.0}, reason: 'as made is not kept');
    expect(odd.physics, {'hair': 2.0, 'wind': 0.0});
    expect(odd.walkOf('stride'), 0.5);
    final dragged = CharacterMove.fromJson({
      'offsets': {
        'handL': [0.1, 0.2, 9],
        'elbow': [1, 1, 1],
        'footR': [1, 'up', 0],
      }
    });
    expect(dragged.offsets.keys, ['handL'], reason: 'only the dots, whole');
    expect(dragged.offsetOf('handL'), [0.1, 0.2, 1.0]);
    expect(dragged.offsetOf('footL'), [0.0, 0.0, 0.0]);
    expect(dragged.withOffset('handL', [0, 0, 0]).offsets, isEmpty,
        reason: 'dragged back is not kept');
    expect(
        const CharacterMove()
            .withPhysics('hair', 1.4)
            .withPhysics('hair', 1)
            .physics,
        isEmpty,
        reason: 'back to as made');
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

    testWidgets('a stance, hands, a foot and the body; each put back',
        (tester) async {
      var m = const CharacterMove();
      var part = 'stance';
      await show(
          tester,
          StatefulBuilder(
              builder: (context, set) => Row(children: [
                    SizedBox(
                        width: 220,
                        child: CharacterMoveList(
                            move: m,
                            selected: part,
                            onSelect: (p) => set(() => part = p),
                            onReset: (n) => set(() => m = n))),
                    SizedBox(
                        width: 330,
                        child: CharacterMoveControls(
                            part: part,
                            move: m,
                            onChanged: (n) => set(() => m = n))),
                  ])));
      m = m.withOffset('hips', [0, -0.1, 0]);
      await tester.tap(find.byKey(const ValueKey('movePart-stance')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('studioPill-move-stance-Wave')));
      await tester.pumpAndSettle();
      expect(m.stance, 'Wave');
      expect(m.offsets, isEmpty,
          reason: 'a new stance puts the hands and feet where it has them');
      expect(find.byKey(const ValueKey('moveChanged-stance')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('movePart-hands')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('studioPill-move-handR-thumbsup')));
      await tester.pumpAndSettle();
      expect((m.handL, m.handR), ('relaxed', 'thumbsup'));

      await tester.tap(find.byKey(const ValueKey('movePart-feet')));
      await tester.pumpAndSettle();
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('move-footL-heel')))
          .onChanged(0.7);
      await tester.pumpAndSettle();
      expect(m.footOf('L', 'heel'), 0.7);

      // Dragged dots, put back by the panel; and a new stance starts clean.
      m = m.withOffset('handR', [0.1, 0.1, 0.1]);
      await tester.tap(find.byKey(const ValueKey('movePart-body')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('moveChanged-body')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moveOffsetsReset')));
      await tester.pumpAndSettle();
      expect(m.offsets, isEmpty);
      expect(find.byKey(const ValueKey('moveOffsetsReset')), findsNothing);
      m = m.withOffset('footL', [0, 0.1, 0]);
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('move-body-lean')))
          .onChanged(-0.4);
      await tester.pumpAndSettle();
      expect(m.bodyOf('lean'), -0.4);
      await tester.tap(find.byKey(const ValueKey('studioPartReset')));
      await tester.pumpAndSettle();
      expect(m.body, isEmpty);

      // A motion, slowed; the walk; the physics.
      await tester.tap(find.byKey(const ValueKey('movePart-motion')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('studioPill-move-motion-Dance')));
      await tester.pumpAndSettle();
      expect(m.motion, 'Dance');
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('move-speed')))
          .onChanged(0.5);
      await tester.pumpAndSettle();
      expect(m.speed, 0.5);
      await tester.tap(find.byKey(const ValueKey('movePart-walk')));
      await tester.pumpAndSettle();
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('move-walk-bounce')))
          .onChanged(0.9);
      await tester.tap(find.byKey(const ValueKey('movePart-physics')));
      await tester.pumpAndSettle();
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('move-physics-wind')))
          .onChanged(0.6);
      await tester.pumpAndSettle();
      expect((m.walkOf('bounce'), m.physicsOf('wind')), (0.9, 0.6));
      await tester.tap(find.byKey(const ValueKey('moveChanged-motion')));
      await tester.pumpAndSettle();
      expect((m.motion, m.speed), ('Idle', 1.0));

      // Put back by the marks in the list.
      await tester.tap(find.byKey(const ValueKey('moveChanged-feet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('moveChanged-stance')));
      await tester.pumpAndSettle();
      expect(
          (m.stance, m.footL.isEmpty, m.handR), ('Relaxed', true, 'thumbsup'));
    });

    testWidgets('at every text size, every part fits', (tester) async {
      for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
        for (final (id, _, _, _) in moveParts) {
          await show(
              tester,
              Row(children: [
                SizedBox(
                    width: 220,
                    child: CharacterMoveList(
                        move: const CharacterMove(stance: 'Shy'),
                        selected: id,
                        onSelect: (_) {})),
                SizedBox(
                    width: 330,
                    child: CharacterMoveControls(
                        part: id,
                        move: const CharacterMove(stance: 'Shy'),
                        onChanged: (_) {})),
              ]),
              scale: scale);
          expect(tester.takeException(), isNull, reason: '$id at ${scale}x');
        }
      }
    });
  });
}
