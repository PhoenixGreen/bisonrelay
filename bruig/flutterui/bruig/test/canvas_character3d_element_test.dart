import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast3d.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/character3d_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/character_assets.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// A character made in the new Character Studio, on the canvas: kept in the
// canvas whole, placed from Assets, changed in the Studio with every copy
// following, and drawn -- in 3D in the app, and by a stand-in figure where
// there is no GPU, as here.

CharacterDesign _design(String id, String name, {double eyes = 0.3}) =>
    CharacterDesign(
      id: id,
      name: name,
      body: "Vivi",
      shape: const CharacterShape().withValue("eyes.size", eyes),
      decals: const [
        _Decals.picture,
        _Decals.vector,
      ],
      updated: DateTime(2026, 11, 3),
    );

/// The decals a design is given, one of each kind.
class _Decals {
  static const picture =
      CharacterDecal(id: "a", source: "picture:logo.png", name: "Logo");
  static const vector = CharacterDecal(id: "b", source: "vector:star");
}

Character3dElement _element(String id, CharacterDesign d) => Character3dElement(
    ElementBase(id: id, width: 200, height: 400, name: d.name),
    design: d);

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  test('kept in the canvas whole, and read back the same', () {
    final e = _element("c", _design("d1", "Jess")).copyWith(
        framing: Character3dFraming.waist,
        turn: 0.25,
        tilt: 0.1,
        zoom: 1.5,
        animation:
            const ElementAnimation(preset: ElementAnimationPreset.fadeIn));
    final back = elementFromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
    expect(back, isA<Character3dElement>());
    back as Character3dElement;
    expect((back.kind, back.framing, back.turn, back.tilt, back.zoom),
        (ElementKind.character3d, Character3dFraming.waist, 0.25, 0.1, 1.5));
    expect(back.animation.preset, ElementAnimationPreset.fadeIn);
    expect(jsonEncode(back.design.toJson()), jsonEncode(e.design.toJson()));
    expect(back.assetIds, {"logo.png"}, reason: 'its decal pictures are kept');
    expect(back.mediaIds, {"star"}, reason: 'and its decal vectors');
  });

  test('what cannot be read is kept to its range, or left as made', () {
    final back = elementFromJson({
      "kind": "character3d",
      "id": "x",
      "design": "not a character",
      "framing": "feet",
      "turn": 9,
      "tilt": -4,
      "zoom": "close",
    }) as Character3dElement;
    expect((back.design.id, back.design.body), ("", "Vivi"));
    expect((back.framing, back.turn, back.tilt, back.zoom),
        (Character3dFraming.body, 1.0, -0.5, 1.0));
  });

  test('without a GPU a figure stands in for it, and nothing throws', () {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    paintElement(canvas, _element("c", _design("d1", "Jess")), 0,
        editing: true);
    paintElement(canvas, _element("c", _design("d1", "Jess")), 0);
    rec.endRecording().dispose();
  });

  test('placed from the library: named for it, picked, one step to undo', () {
    final c = CanvasController(CanvasDocument());
    c.placeCharacter3d(_design("d1", "Jess"));
    final placed = c.document.elements.single as Character3dElement;
    expect((placed.name, placed.design.id, placed.base.lockAspect),
        ("Jess", "d1", true));
    expect(c.selection, {placed.id});
    c.undo();
    expect(c.document.elements, isEmpty);
  });

  // Ken, testing Ember Vale 2: "the game is currently not playable". Its
  // Vivi is "vivi" in every scene; Done in the Studio wrote each scene's
  // copy back by id -- into the open scene -- and gave every one the
  // performance of the one opened, so the woods' Vivi, overwritten by the
  // Dawn's, danced and was no longer a player.
  test("Done in the Studio keeps each scene's copy in its own scene", () {
    Character3dElement vivi(PlaySpec play, CharacterPerformance p) =>
        Character3dElement(
            ElementBase(
                id: "vivi", name: "Vivi", width: 90, height: 200, play: play),
            design: _design("d1", "Vivi"),
            performance: p);
    const hero = PlaySpec(as: PlayAs.platformer);
    const dance = CharacterPerformance(
        clips: [MotionClip3d(kind: "Dance", start: 1, length: 6)]);
    var doc =
        CanvasDocument().addElement(vivi(hero, const CharacterPerformance()));
    doc = doc.addScene().goToScene(1).addElement(vivi(const PlaySpec(), dance));
    final c = CanvasController(doc.goToScene(1));
    c.openStudio3d(element: "vivi");
    c.closeStudio3d(
        _design("d1", "Vivi", eyes: 0.8), dance.copyWith(shadow: "None"));
    Character3dElement inScene(int i) =>
        c.document.allScenes[i].elements.single as Character3dElement;
    expect(inScene(0).design.shape.get("eyes.size"), 0.8,
        reason: "the other scene's copy made as the character now is");
    expect(inScene(0).base.play.as, PlayAs.platformer,
        reason: "still the woods' player");
    expect(inScene(0).performance.clips, isEmpty,
        reason: "its own performance, not the one opened's");
    expect(inScene(1).performance.shadow, "None",
        reason: "the one opened does what the Studio left it doing");
    expect(inScene(1).base.play.as, PlayAs.none);
  });

  test(
      'Done in the Studio changes every copy, in every scene, and the one '
      'opened -- one step to undo', () {
    var doc = CanvasDocument()
        .addElement(_element("one", _design("d1", "Jess")))
        .addElement(_element("other", _design("d2", "Sam")))
        .addElement(_element("lost", _design("", "")));
    doc = doc.addScene().goToScene(1).addElement(
        _element("two", _design("d1", "Jess"))
            .rebase(const ElementBase(id: "two", name: "Jess on the left")));
    doc = doc.goToScene(0);
    final c = CanvasController(doc);
    c.openStudio3d(element: "one");
    expect(c.studio3dDesign?.id, "d1");
    expect(c.studio3dOpen.value, isTrue);
    final kept = _design("d1", "Jessie", eyes: 0.8);
    c.closeStudio3d(kept);
    expect(c.studio3dOpen.value, isFalse);
    Character3dElement get(String id) => [
          for (final s in c.document.allScenes) ...s.elements,
          ...c.document.elements,
        ].firstWhere((e) => e.id == id) as Character3dElement;
    expect(get("one").design.shape.get("eyes.size"), 0.8);
    expect(get("one").name, "Jessie", reason: 'named for the character');
    expect(get("two").design.shape.get("eyes.size"), 0.8,
        reason: 'in another scene');
    expect(get("two").name, "Jess on the left",
        reason: 'a name of its own is kept');
    expect(get("other").design.id, "d2", reason: 'another character');
    expect(get("lost").design.id, "", reason: 'not opened, not this one');
    c.undo();
    expect(get("one").design.shape.get("eyes.size"), 0.3);
    expect(get("two").design.shape.get("eyes.size"), 0.3);

    // One read from a canvas that could not be is given the one kept.
    c.openStudio3d(element: "lost");
    c.closeStudio3d(_design("d3", "New"));
    expect(get("lost").design.id, "d3");
    // Nothing kept, nothing changed.
    final before = c.document;
    c.openStudio3d(element: "one");
    c.closeStudio3d();
    expect(identical(c.document, before), isTrue);
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 340, child: SingleChildScrollView(child: child)))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('its settings: shown how, seen from where, and to the Studio',
      (tester) async {
    final c = CanvasController(
        CanvasDocument().addElement(_element("c", _design("d1", "Jess"))));
    Character3dElement now() =>
        c.document.elements.single as Character3dElement;
    await show(
        tester,
        ListenableBuilder(
            listenable: c,
            builder: (context, _) =>
                Column(children: elementSettings(context, c, now()))));
    final head = find.byKey(const ValueKey('character3dFraming-head'));
    await tester.ensureVisible(head);
    await tester.pumpAndSettle();
    await tester.tap(head);
    await tester.pumpAndSettle();
    expect(now().framing, Character3dFraming.head);
    tester
        .widget<CanvasSlider>(find.byKey(const ValueKey('character3dTurn')))
        .onChanged(0.5);
    await tester.pumpAndSettle();
    expect(now().turn, 0.5);
    await tester.ensureVisible(find.byKey(const ValueKey('character3dEdit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('character3dEdit')));
    await tester.pumpAndSettle();
    expect((c.studio3dOpen.value, c.studio3dElement), (true, "c"));
  });

  testWidgets('Assets lists the 3D characters, and a click places one',
      (tester) async {
    final placed = <String>[];
    await show(
        tester,
        Character3dAssetList(
            designs: () async => [_design("d1", "Jess"), _design("d2", "Sam")],
            onPlace: (d) => placed.add(d.id)));
    expect(find.text("Jess"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('character3dAsset-d2')));
    expect(placed, ["d2"]);
  });

  testWidgets('the ready-made cast is listed, and a click places one',
      (tester) async {
    final c = CanvasController(CanvasDocument());
    addTearDown(c.dispose);
    await show(
        tester,
        CharacterAssetSection(
            controller: c, designs: () async => const <CharacterDesign>[]));
    for (final m in readyMadeCast) {
      expect(find.byKey(ValueKey('characterCast-${m.design.name}')),
          findsOneWidget);
    }
    final tile = find.byKey(const ValueKey('characterCast-Theo'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    final placed = c.document.elements.single as Character3dElement;
    expect((placed.name, placed.design.body), ('Theo', 'HairSample_Male'));
    expect(placed.design.id, isEmpty,
        reason: 'a copy of the cast, made the user\'s when kept');
  });

  test('every one of the cast has its picture', () {
    for (final m in readyMadeCast) {
      expect(File(m.picture).existsSync(), isTrue, reason: m.picture);
    }
  });

  testWidgets('the Characters section scrolls in a short panel',
      (tester) async {
    final c = CanvasController(CanvasDocument());
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 284,
                  height: 265,
                  child: CharacterAssetSection(
                      controller: c,
                      designs: () async => [
                            for (var i = 0; i < 9; i++)
                              _design("d$i", "Character $i")
                          ])))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('characterAssetsScroll')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('character3dAsset-d8')), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('character3dAsset-d8')), findsOneWidget);
  });

  group('decals', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp("character3d_decals");
      CanvasStorage.rootOverride = root.path;
    });
    tearDown(() async {
      CanvasStorage.rootOverride = null;
      if (await root.exists()) await root.delete(recursive: true);
    });

    testWidgets('a picture and a vector from the library are read for one',
        (tester) async {
      final read = await tester.runAsync(() async {
        // A red square, eight by eight.
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 8, 8),
            Paint()..color = const Color(0xffff0000));
        final image = await rec.endRecording().toImage(8, 8);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final picture = await CanvasAssets.save(png!.buffer.asUint8List());
        final vector = await CanvasMedia.saveVector(utf8.encode(
            '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">'
            '<rect width="16" height="16" fill="#0000ff"/></svg>'));
        final sw = Stopwatch()..start();
        final p = await loadDecalPicture("picture:$picture");
        final v = await loadDecalPicture("vector:$vector");
        final none = await loadDecalPicture("picture:nothing.png");
        return (p, v, none, sw.elapsedMilliseconds);
      });
      final (p, v, none, ms) = read!;
      expect((p?.$2, p?.$3), (8, 8));
      expect(p!.$1.sublist(0, 4), [255, 0, 0, 255]);
      expect(v, isNotNull, reason: 'a vector is drawn as a picture');
      expect(v!.$1.sublist(2, 4), [255, 255]);
      expect(none, isNull);
      expect(ms, lessThan(5000),
          reason: 'not waiting out the time it is allowed');
    });
  });

  testWidgets('at every text size and panel height, nothing overflows',
      (tester) async {
    final c = CanvasController(
        CanvasDocument().addElement(_element("c", _design("d1", "Jess"))));
    for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
      for (final high in const [60.0, 140.0, 265.0]) {
        await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
          create: (_) => ThemeNotifier(doLoad: false),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                  size: const Size(1000, 800),
                  textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 284,
                          height: high,
                          child: CharacterAssetSection(
                              controller: c,
                              designs: () async => [
                                    for (var i = 0; i < 5; i++)
                                      _design("d$i", "A long character name $i")
                                  ])),
                      SizedBox(
                          width: 330,
                          child: SingleChildScrollView(
                              child: Builder(
                                  builder: (context) => Column(
                                      children: elementSettings(context, c,
                                          c.document.elements.single))))),
                    ]),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${scale}x, $high high');
      }
    }
  });
}
