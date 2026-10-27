import 'dart:ui' show Canvas, PictureRecorder;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_layer_apart_test.dart is one layer of a sketch taken
// apart on one view: its shapes, and only its, standing in for its own
// drawing there, drawn on with the drawing tools, and put back.

CharacterElement _sketch({double turn = 0}) {
  var e = CharacterElement(
      const ElementBase(id: "c", x: 20, y: 20, width: 160, height: 340),
      dna: characterCast.first.dna);
  // Every view, for the panels at three-quarters and above.
  return e.copyWith(pose: e.pose.withTurn(turn), views: CharacterView.all);
}

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(200, 380);
  return (await img.toByteData())!.buffer.asUint8List();
}

double _coverMiss(List<int> a, List<int> b) {
  var miss = 0, n = a.length ~/ 4;
  for (var i = 0; i < n; i++) {
    if ((a[i * 4 + 3] > 128) != (b[i * 4 + 3] > 128)) miss++;
  }
  return miss / n;
}

void main() {
  var eyes = BodyLayer.eyes.name;

  test("a body layer taken apart on its own", () async {
    var e = _sketch();
    var apart = takeApartLayer(e, eyes, 0, 24);
    var (d, _) = apart.drawingFor(0, 0);
    expect(d.hiddenLayers, {eyes});
    expect(d.hidden, isEmpty, reason: "the rest is drawn as it is made");
    expect(d.shapes, isNotEmpty);
    expect(d.layers.toSet(), {eyes});
    for (var p in d.parts) {
      expect(p, CharacterPart.head);
    }
    expect(isLayerTakenApart(apart, eyes, panelKey(0, 0)), isTrue);
    expect(isLayerTakenApart(apart, BodyLayer.mouth.name, panelKey(0, 0)), isFalse);
    expect(isLayerTakenApart(apart, eyes, panelKey(90, 0)), isFalse, reason: "this view only");
    expect(_coverMiss(await _pixels(apart), await _pixels(e)), lessThan(0.005));
    // Again: taken afresh, not twice.
    var again = takeApartLayer(apart, eyes, 0, 24);
    expect(again.drawingFor(0, 0).$1.shapes.length, d.shapes.length);
    // Put back: exactly as made.
    var back = putLayerBack(apart, eyes, 0, 24);
    expect(back.drawings, isEmpty);
    expect(await _pixels(back), await _pixels(e));
  });

  test("a garment's layer is that garment taken apart", () async {
    var e = _sketch();
    var hoodie = e.dna.wardrobe.indexWhere((g) => g.kind == GarmentKind.hoodie);
    var apart = takeApartLayer(e, garmentLayer(hoodie), 0, 24);
    var d = apart.dna.wardrobe[hoodie].drawingFor(0, 0).$1;
    expect(d.replaces, isTrue);
    for (var p in d.parts) {
      expect(GarmentKind.hoodie.covers, contains(p));
    }
    expect(_coverMiss(await _pixels(apart), await _pixels(e)), lessThan(0.02));
  });

  test("the whole panel taken apart marks each shape with its layer", () {
    var apart = takeApartPanel(_sketch(), 0, 24);
    var d = apart.drawingFor(0, 0).$1;
    expect(d.layers.toSet(), containsAll([eyes, BodyLayer.head.name, BodyLayer.hairFront.name]));
    expect(d.layers.any((l) => l != null && garmentOfLayer(l) != null), isFalse,
        reason: "what it wears is on what it wears");
  });

  test("mirrored to the other side, left for right", () {
    var arm = BodyLayer.armL.name;
    var apart = takeApartLayer(_sketch(turn: 45), arm, 0, 24);
    var (other, mirrored) = apart.drawingFor(-45, 0);
    expect(mirrored, isTrue);
    expect(other.hiddenLayers, {BodyLayer.armR.name});
    expect(other.layers.toSet(), {BodyLayer.armR.name});
  });

  test("hidden and soloed with its layer", () async {
    var apart = takeApartLayer(_sketch(), eyes, 0, 24);
    var hidden = apart.withLayerShown(eyes, false);
    expect(await _pixels(hidden), isNot(await _pixels(apart)));
    expect(_coverMiss(await _pixels(hidden), await _pixels(apart)), lessThan(0.01));
    var saved = elementFromJson(apart.toJson()) as CharacterElement;
    var d = saved.drawingFor(0, 0).$1;
    expect(d.hiddenLayers, {eyes});
    expect(d.layers.toSet(), {eyes});
  });

  test("drawn on as that layer alone, the panel's others left be", () {
    var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
    c.takeApartCharacterLayer("c", eyes);
    c.takeApartCharacterLayer("c", BodyLayer.mouth.name);
    var before = (c.document.elementById("c") as CharacterElement).drawingFor(0, 0).$1;
    var eyeCount = before.layers.where((l) => l == eyes).length;
    var mouthCount = before.layers.where((l) => l == BodyLayer.mouth.name).length;
    c.drawOnCharacter("c", layer: eyes);
    expect(c.drawingLayer, eyes);
    expect(c.drawnTakenApart, isTrue);
    var proxy = c.editingVector!;
    expect(proxy.shapes!.length, eyeCount, reason: "the eyes' shapes, only");
    var dot = const VectorShape(paths: [
      VectorPath([VectorNode(80, 60), VectorNode(84, 60), VectorNode(84, 64)], closed: true)
    ], fill: Color(0xFFFF0000));
    c.replaceElement(proxy.copyWith(shapes: [...proxy.shapes!.skip(1), dot]));
    var after = (c.document.elementById("c") as CharacterElement).drawingFor(0, 0).$1;
    expect(after.layers.where((l) => l == eyes).length, eyeCount, reason: "one gone, one drawn");
    expect(after.layers.where((l) => l == BodyLayer.mouth.name).length, mouthCount);
    expect(after.hiddenLayers, {eyes, BodyLayer.mouth.name});
  });

  group("the layer's view card", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    testWidgets("takes it apart, draws on it, puts it back", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
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
      Future<void> tap(String key) async {
        var f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap("characterLayerTakeApart");
      expect(c.layerTakenApart("c", eyes), isTrue);
      await tap("characterLayerDraw");
      expect(c.drawingOn, "c");
      expect(c.drawingLayer, eyes);
      await tap("characterLayerDraw");
      expect(c.drawingOn, isNull);
      await tap("characterLayerPutBack");
      expect(c.layerTakenApart("c", eyes), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
