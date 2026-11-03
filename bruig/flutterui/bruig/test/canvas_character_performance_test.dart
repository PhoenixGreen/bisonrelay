import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// What a new 3D character does in one scene of the canvas: its pose and
// keys, the motions it plays and when, the walks that carry it across, its
// face and what it says -- kept with the element, and set in its settings.

Character3dElement _element({CharacterPerformance? p}) => Character3dElement(
    const ElementBase(id: "c", width: 200, height: 400, name: "Jess"),
    design: CharacterDesign(
        id: "d1", name: "Jess", body: "Vivi", updated: DateTime(2026, 11, 3)),
    performance: p ?? const CharacterPerformance());

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  test('kept with the element, and read back the same', () {
    final p = CharacterPerformance(
      wearing: "Swimwear",
      stance: "Hero",
      lean: 0.2,
      keys: const [
        PoseKey(t: 1, stance: "Wave", feeling: "Happy"),
      ],
      clips: const [
        MotionClip3d(kind: "Walk", start: 0.5, dir: 1, strength: 0.7),
        MotionClip3d(kind: "Wave", start: 3, mirror: true),
      ],
      feeling: "Sad",
      mixTo: "Angry",
      mixAmount: 0.4,
      mouth: "O",
      blink: false,
      shadow: "Hard",
      line: "Hello there",
      lineAt: 2,
    );
    final e = _element(p: p);
    final back = Character3dElement.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>, e.base);
    expect(back.performance, p);
    expect(back.expression, "Sad");
    expect(e.toJson().containsKey("performance"), isTrue);
    expect(_element().toJson().containsKey("performance"), isFalse,
        reason: 'nothing kept for as designed');
  });

  test('an expression kept before performances is its feeling', () {
    final j = _element().toJson()..["expression"] = "Happy";
    final e = Character3dElement.fromJson(j, _element().base);
    expect(e.performance.feeling, "Happy");
    expect(e.wearing(null).performance.feeling, isNull);
  });

  test('what cannot be read is left as made, or kept to its range', () {
    final p = CharacterPerformance.fromJson({
      "wearing": "A ball gown",
      "clips": [
        {"kind": "Somersault", "start": 1},
        {"kind": "Nod", "start": -4, "length": 0, "strength": 9, "dir": 7},
      ],
      "mouth": "Q",
      "shadow": "Purple",
    });
    expect(p.wearing, "As designed");
    expect(
        p.clips.single,
        const MotionClip3d(
            kind: "Nod", start: 0, length: 0.3, strength: 1.5, dir: 1));
    expect((p.mouth, p.shadow), ("rest", "Soft"));
  });

  test('a motion fades in and out, and the last playing is the one seen', () {
    const p = CharacterPerformance(clips: [
      MotionClip3d(kind: "Wave", start: 1, length: 2),
      MotionClip3d(kind: "Nod", start: 2.5, length: 1),
    ]);
    expect(p.clipAt(0.5), isNull);
    expect(p.clipAt(1.15)!.$2, closeTo(0.5, 1e-9));
    expect(p.clipAt(2)!.$1.kind, "Wave");
    expect(p.clipAt(2)!.$2, 1);
    expect(p.clipAt(2.7)!.$1.kind, "Nod");
    expect(p.clipAt(4), isNull);
  });

  test('keys hold from their time until the next', () {
    const p = CharacterPerformance(keys: [
      PoseKey(t: 1, stance: "Wave"),
      PoseKey(t: 3, stance: "Shy"),
    ]);
    expect(p.keyAt(0.5), isNull);
    expect(p.keyAt(1)!.stance, "Wave");
    expect(p.keyAt(2.9)!.stance, "Wave");
    expect(p.keyAt(5)!.stance, "Shy");
  });

  test('walks carry it across, turned the way it goes, kept on the page', () {
    const p = CharacterPerformance(clips: [
      MotionClip3d(kind: "Walk", start: 0, length: 2, dir: 1),
      MotionClip3d(kind: "Wave", start: 2, length: 1),
      MotionClip3d(kind: "Run", start: 4, length: 100, dir: -1),
    ]);
    double pace(MotionClip3d c) => c.kind == "Run" ? 2 : 1;
    expect(p.travelAt(1, pace), (x: 1.0, turn: 1.0));
    expect(p.travelAt(3, pace), (x: 2.0, turn: 0.0),
        reason: 'stopped where the walk left it, facing the front');
    expect(p.travelAt(60, pace).x, -2.6, reason: 'kept on the page');
    expect(p.travelAt(60, pace).turn, -1);
  });

  test('copyWith puts the stance and feeling back as designed with null', () {
    const p = CharacterPerformance(stance: "Hero", feeling: "Sad", lean: 1);
    expect(p.copyWith(lean: 0).stance, "Hero");
    expect(p.copyWith(stance: null).stance, isNull);
    expect(p.copyWith(feeling: null).feeling, isNull);
    expect(p.copyWith(stance: null, feeling: null, lean: 0).isEmpty, isTrue);
  });

  test('a quick change of clothes for the scene, the design left as it is', () {
    final e =
        _element(p: const CharacterPerformance(wearing: "Underwear only"));
    expect(e.worn.outfit[WearSlot.top].source, WearSource.none);
    expect(e.worn.outfit[WearSlot.underwear].made, isTrue);
    expect(e.design.outfit, CharacterOutfit.asDesigned);
    final plain = _element();
    expect(identical(plain.worn, plain.design), isTrue);
  });

  test('Done in the Studio keeps the Test step on the element: one undo', () {
    final c = CanvasController(CanvasDocument()
        .addElement(_element(p: const CharacterPerformance(stance: "Hero"))));
    c.openStudio3d(element: "c");
    expect(c.studio3dPerformance?.stance, "Hero");
    const tried = CharacterPerformance(
        stance: "Shy", clips: [MotionClip3d(kind: "Wave", start: 1)]);
    c.closeStudio3d(null, tried);
    expect(
        (c.document.elements.single as Character3dElement).performance, tried);
    c.undo();
    expect(
        (c.document.elements.single as Character3dElement).performance.stance,
        "Hero");
    // Kept with the character as well, in the same step.
    c.openStudio3d(element: "c");
    c.closeStudio3d(
        CharacterDesign(
            id: "d1", name: "Jessie", body: "Vivi", updated: DateTime(2026)),
        tried);
    final e = c.document.elements.single as Character3dElement;
    expect((e.design.name, e.performance), ("Jessie", tried));
    c.undo();
    expect(
        (c.document.elements.single as Character3dElement).design.name, "Jess");
  });

  Future<CanvasController> show(WidgetTester tester,
      {CharacterPerformance? p, double scale = 1}) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c =
        CanvasController(CanvasDocument(frames: 96).addElement(_element(p: p)));
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(
            size: const Size(800, 3000), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
            body: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                    child: ListenableBuilder(
                        listenable: c,
                        builder: (context, _) => Column(
                            children: elementSettings(
                                context, c, c.document.elements.single)))))),
      )),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  Character3dElement now(CanvasController c) =>
      c.document.elements.single as Character3dElement;

  Future<void> pick(WidgetTester tester, String key, String option) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    tester.widget<CanvasDropdown<String>>(f).onChanged(option);
    await tester.pumpAndSettle();
  }

  testWidgets('a motion added at the playhead, changed and taken out',
      (tester) async {
    final c = await show(tester);
    c.frame = 36; // 1.5 s at 24 frames a second
    await tester.pumpAndSettle();
    await pick(tester, "character3dMotionAdd", "Walk:1");
    expect(now(c).performance.clips.single,
        const MotionClip3d(kind: "Walk", start: 1.5, dir: 1));
    final mirror = find.byKey(const ValueKey("character3dClipMirror-0"));
    await tester.ensureVisible(mirror);
    tester.widget<CanvasToggle>(mirror).onChanged(true);
    await tester.pumpAndSettle();
    expect(now(c).performance.clips.single.mirror, isTrue);
    tester
        .widget<CanvasSlider>(
            find.byKey(const ValueKey("character3dClipStrength-0")))
        .onChanged(0.5);
    await tester.pumpAndSettle();
    expect(now(c).performance.clips.single.strength, 0.5);
    final out = find.byKey(const ValueKey("character3dClipRemove-0"));
    await tester.ensureVisible(out);
    await tester.tap(out);
    await tester.pumpAndSettle();
    expect(now(c).performance.clips, isEmpty);
  });

  testWidgets('a key made at the playhead is what the pose settings change',
      (tester) async {
    final c = await show(tester,
        p: const CharacterPerformance(stance: "Hero", feeling: "Sad"));
    c.frame = 48;
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey("character3dKeyAdd"));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(now(c).performance.keys.single,
        const PoseKey(t: 2, stance: "Hero", feeling: "Sad"));
    await pick(tester, "character3dStance", "Shy");
    expect(now(c).performance.keys.single.stance, "Shy");
    expect(now(c).performance.stance, "Hero", reason: 'between keys kept');
    await pick(tester, "character3dExpression", "Happy");
    expect(now(c).performance.keys.single.feeling, "Happy");
    expect(now(c).performance.feeling, "Sad");
    // Away from the key, the settings are how it stands between keys.
    c.frame = 0;
    await tester.pumpAndSettle();
    await pick(tester, "character3dStance", "");
    expect(now(c).performance.stance, isNull);
    expect(now(c).performance.keys.single.stance, "Shy");
    // The key's button takes the playhead to it.
    final go = find.byKey(const ValueKey("character3dKey-0"));
    await tester.ensureVisible(go);
    await tester.tap(go);
    await tester.pumpAndSettle();
    expect(c.frame, 48);
  });

  testWidgets('the face, the line, and what it does by itself', (tester) async {
    final c = await show(tester);
    await pick(tester, "character3dExpression", "Happy");
    expect(now(c).expression, "Happy");
    await pick(tester, "character3dMouth", "A");
    expect(now(c).performance.mouth, "A");
    tester
        .widget<CanvasToggle>(find.byKey(const ValueKey("character3dBlink")))
        .onChanged(false);
    await tester.pumpAndSettle();
    expect(now(c).performance.blink, isFalse);
    await pick(tester, "character3dWearing", "Casual");
    expect(now(c).performance.wearing, "Casual");
    final hard = find.byKey(const ValueKey("character3dShadow-Hard"));
    await tester.ensureVisible(hard);
    await tester.tap(hard);
    await tester.pumpAndSettle();
    expect(now(c).performance.shadow, "Hard");
  });

  testWidgets('at every text size, with motions and keys, nothing overflows',
      (tester) async {
    for (final scale in const [0.65, 1.0, 1.25, 1.5]) {
      await show(tester,
          scale: scale,
          p: const CharacterPerformance(keys: [
            PoseKey(t: 0, stance: "Fighting guard")
          ], clips: [
            MotionClip3d(kind: "Run", start: 0, dir: -1),
            MotionClip3d(kind: "Look around", start: 2),
          ], line: "A rather long line for the field to hold"));
      expect(tester.takeException(), isNull, reason: '${scale}x');
    }
  });
}
