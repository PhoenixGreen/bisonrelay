import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_character_layers_test.dart is a sketch as a stack of layers: each
// part of the body, face and hair and each garment drawn as its own, so it
// can be hidden, soloed and taken apart alone.

const _box = Rect.fromLTWH(0, 0, 160, 340);

Future<List<int>> _pixels(CharacterDna dna, {LayerView layers = LayerView.all}) async {
  var rec = PictureRecorder();
  paintCharacterFigure(Canvas(rec), _box, dna, CharacterElement.restPose, layers: layers);
  var img = await rec.endRecording().toImage(160, 340);
  return (await img.toByteData())!.buffer.asUint8List();
}

/// _opaque is how many pixels are drawn on.
int _opaque(List<int> px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 200) n++;
  }
  return n;
}

void main() {
  var dna = characterCast.first.dna;
  var hoodie = dna.wardrobe.indexWhere((g) => g.kind == GarmentKind.hoodie);

  test("as all of it, the same as ever", () async {
    expect(await _pixels(dna, layers: const LayerView()), await _pixels(dna));
  });

  test("a layer hidden is left out; one inside it stays", () async {
    var all = await _pixels(dna);
    var noHoodie = await _pixels(dna, layers: LayerView(hidden: {garmentLayer(hoodie)}));
    expect(noHoodie, isNot(all));
    var noHands = await _pixels(dna,
        layers: LayerView(hidden: {BodyLayer.handL.name, BodyLayer.handR.name}));
    expect(_opaque(noHands), lessThan(_opaque(all)));
    // The arms hidden: the sleeves are the hoodie's, and stay.
    var noArms = await _pixels(dna,
        layers: LayerView(hidden: {BodyLayer.armL.name, BodyLayer.armR.name}));
    var noArmsOrHoodie = await _pixels(dna,
        layers: LayerView(hidden: {BodyLayer.armL.name, BodyLayer.armR.name, garmentLayer(hoodie)}));
    expect(_opaque(noArms), greaterThan(_opaque(noArmsOrHoodie)));
    // Every body layer can go without breaking the rest.
    for (var l in BodyLayer.values) {
      await _pixels(dna, layers: LayerView(hidden: {l.name}));
    }
  });

  test("a layer soloed is drawn whole over the rest, faint", () async {
    var all = await _pixels(dna);
    var solo = await _pixels(dna, layers: const LayerView(solo: "eyes"));
    expect(solo, isNot(all));
    // The eyes are drawn as they are: the darkest pixels are still there.
    int dark(List<int> px) {
      var n = 0;
      for (var i = 0; i < px.length; i += 4) {
        if (px[i + 3] > 200 && px[i] + px[i + 1] + px[i + 2] < 200) n++;
      }
      return n;
    }

    // As dark as the eyes drawn alone, and no more: the rest is faint.
    var eyesAlone = await _pixels(dna,
        layers: LayerView(hidden: {
          for (var l in BodyLayer.values)
            if (l != BodyLayer.eyes) l.name,
          for (var i = 0; i < dna.wardrobe.length; i++) garmentLayer(i),
        }));
    expect(dark(eyesAlone), greaterThan(40));
    expect(dark(solo), greaterThanOrEqualTo((dark(eyesAlone) * 0.9).round()));
    expect(dark(solo), lessThan(dark(all) ~/ 4), reason: "the hair and the lines round the rest are faint");
  });

  test("taken apart, every shape knows its layer", () {
    var rig = CharacterRig.of(dna, CharacterElement.restPose, _box);
    var shapes = captureFigure(rig, dna, CharacterFace.rest, LifeAt.none, CharacterStyle.featureCartoon);
    var layers = {for (var c in shapes) c.layer};
    expect(layers, containsAll([
      BodyLayer.eyes.name,
      BodyLayer.head.name,
      BodyLayer.hairFront.name,
      BodyLayer.mouth.name,
      garmentLayer(hoodie),
    ]));
    expect(layers.contains(null), isFalse, reason: "nothing drawn outside a layer");
  });

  test("hidden is kept with the character, and a garment's with the garment", () {
    var e = CharacterElement(const ElementBase(id: "c", width: 160, height: 340), dna: dna)
        .withLayerShown(BodyLayer.ears.name, false)
        .withLayerShown(garmentLayer(hoodie), false);
    expect(e.hiddenLayers, {BodyLayer.ears.name});
    expect(e.dna.wardrobe[hoodie].hidden, isTrue);
    expect(e.layerView().hidden, {BodyLayer.ears.name, garmentLayer(hoodie)});
    var back = elementFromJson(e.toJson()) as CharacterElement;
    expect(back.layerView().hidden, e.layerView().hidden);
    expect((e.withBase(x: 5) as CharacterElement).hiddenLayers, e.hiddenLayers);
    expect(e.withLayerShown(BodyLayer.ears.name, true).hiddenLayers, isEmpty);
  });
}
