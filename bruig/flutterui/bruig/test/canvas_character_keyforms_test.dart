import 'dart:ui' show Canvas, PictureRecorder;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_keyforms_test.dart is a layer of a sketch shaped by a
// slider through drawings kept at its values: blended between them point
// by point, held past them, kept as they are drawn, and saved.

CharacterElement _sketch() => CharacterElement(
    const ElementBase(id: "c", x: 20, y: 20, width: 160, height: 340),
    dna: characterCast.first.dna);

VectorShape _square(double x, {double size = 10}) => VectorShape(paths: [
      VectorPath([
        VectorNode(x, 0),
        VectorNode(x + size, 0),
        VectorNode(x + size, size),
      ], closed: true)
    ], fill: const Color(0xFF000000));

CharacterDrawing _one(VectorShape s) =>
    CharacterDrawing(shapes: [s], parts: const [CharacterPart.head], order: const [1], layers: const ["eyes"]);

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(200, 380);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  var eyes = BodyLayer.eyes.name;
  var size = Look.eyeSize;

  test("blended point by point between keyforms, held past them", () {
    var k = const LayerKeys("eyeSize")
        .withKey(0, _one(_square(0)))
        .withKey(1, _one(_square(20)));
    expect(k.at(0.5).shapes.single.paths.single.nodes.first.x, closeTo(10, 1e-9));
    expect(k.at(-1).shapes.single.paths.single.nodes.first.x, 0);
    expect(k.at(2).shapes.single.paths.single.nodes.first.x, 20);
    // Another between: the blend runs through it.
    var k3 = k.withKey(0.5, _one(_square(4)));
    expect(k3.keys.length, 3);
    expect(k3.at(0.25).shapes.single.paths.single.nodes.first.x, closeTo(2, 1e-9));
    // Points that do not match: the nearer's shape, not a tangle.
    var odd = blendDrawings(_one(_square(0)),
        _one(const VectorShape(paths: [VectorPath([VectorNode(5, 5)])])), 0.4);
    expect(odd.shapes.single.paths.single.nodes.length, 3);
  });

  test("a shape added goes to every keyform; one taken away, they follow", () {
    var k = const LayerKeys("eyeSize")
        .withKey(0, _one(_square(0)))
        .withKey(1, _one(_square(20)));
    var two = CharacterDrawing(
        shapes: [_square(20), _square(50)],
        parts: const [CharacterPart.head, CharacterPart.head],
        order: const [1, 2],
        layers: const ["eyes", "eyes"]);
    var added = k.withKey(1, two);
    expect(added.keys.first.$2.shapes.length, 2);
    expect(added.keys.first.$2.shapes.last.paths.single.nodes.first.x, 50);
    var fewer = added.withKey(0, _one(_square(3)));
    expect(fewer.keys.last.$2.shapes.length, 1);
  });

  test("a taken apart layer keyed: the slider reshapes the drawing", () async {
    var e = takeApartLayer(_sketch(), eyes, 0, 24);
    e = keyLayer(e, eyes, size.name, 0, 24);
    expect(keysOf(e, eyes, 0, 24)!.keys.length, 1);
    // A second keyform, at a bigger size, drawn bigger.
    e = e.copyWith(dna: e.dna.copyWith(look: e.dna.look.withValue(size, 1)));
    e = withKeyform(e, eyes, 0, 24);
    var k = keysOf(e, eyes, 0, 24)!;
    expect(k.keys.length, 2);
    var big = k.keys.last.$2;
    var scaled = big.copyWith(shapes: [
      for (var s in big.shapes) mapShape(s, (x, y) => (x * 1.6, y * 1.6), 1.6)
    ]);
    var (d, _) = e.drawingFor(0, 0);
    e = e.withDrawing(0, 0, d.copyWith(keyed: {eyes: k.withKey(1, scaled)}));
    Future<List<int>> at(double v) =>
        _pixels(e.copyWith(dna: e.dna.copyWith(look: e.dna.look.withValue(size, v))));
    var small = await at(0), mid = await at(0.5), large = await at(1);
    expect(mid, isNot(small));
    expect(mid, isNot(large));
    // Saved and loaded, mirrored to the other side's panel.
    var saved = elementFromJson(e.toJson()) as CharacterElement;
    expect(saved.drawingFor(0, 0).$1.keyed[eyes]!.keys.length, 2);
    // Put back: the keyforms go with it.
    expect(putLayerBack(e, eyes, 0, 24).drawings, isEmpty);
  });

  test("drawn on at a keyform changes it; elsewhere keeps another", () {
    var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
    CharacterElement get() => c.document.elementById("c") as CharacterElement;
    c.takeApartCharacterLayer("c", eyes);
    c.keyCharacterLayer("c", eyes, size.name);
    c.drawOnCharacter("c", layer: eyes);
    var proxy = c.editingVector!;
    var moved = [
      for (var s in proxy.shapes!) mapShape(s, (x, y) => (x + 2, y), 1),
    ];
    c.replaceElement(proxy.copyWith(shapes: moved));
    expect(keysOf(get(), eyes, 0, 24)!.keys.length, 1, reason: "changed, not added");
    c.stopDrawingOnCharacter();
    c.goToKeyform("c", size.name, 0.6);
    c.drawOnCharacter("c", layer: eyes);
    proxy = c.editingVector!;
    c.replaceElement(proxy.copyWith(shapes: [
      for (var s in proxy.shapes!) mapShape(s, (x, y) => (x, y + 1), 1),
    ]));
    var k = keysOf(get(), eyes, 0, 24)!;
    expect(k.keys.map((k) => k.$1), [0, 0.6]);
  });

  group("the keyforms card", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    testWidgets("keys a layer by a slider and keeps keyforms", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.takeApartCharacterLayer("c", eyes);
      c.pickCharacterLayer(eyes);
      tester.view.physicalSize = const Size(900, 14000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      CharacterElement get() => c.document.elementById("c") as CharacterElement;
      tester.widget<CanvasDropdown<Look?>>(find.byKey(const ValueKey("characterLayerKeyLook")))
          .onChanged(size);
      await tester.pumpAndSettle();
      expect(keysOf(get(), eyes, 0, 24)?.look, size.name);
      expect(find.text("Size ◆ keyed"), findsOneWidget);
      c.goToKeyform("c", size.name, 0.8);
      await tester.pumpAndSettle();
      var add = find.byKey(const ValueKey("characterLayerKeyAdd"));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(keysOf(get(), eyes, 0, 24)!.keys.length, 2);
      Future<void> tap(String key) async {
        var f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap("characterLayerKey-0%");
      expect(get().dna.look[size], 0);
      await tap("characterLayerKeyOff-80%");
      await tester.pumpAndSettle();
      expect(keysOf(get(), eyes, 0, 24)!.keys.length, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
