import 'dart:ui' show Canvas, PictureRecorder;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_take_apart_test.dart is a sketch's panel taken apart
// into shapes, to edit point by point: the body on the character's drawing
// and each garment on its own, in the order the figure is drawn in, drawn
// as it was, worn as it was, and put back as it was made.

CharacterElement _sketch() => CharacterElement(
    const ElementBase(id: "c", x: 20, y: 20, width: 160, height: 340),
    dna: characterCast.first.dna);

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(200, 380);
  return (await img.toByteData())!.buffer.asUint8List();
}

/// _coverMiss is the share of pixels drawn on in one and not the other.
double _coverMiss(List<int> a, List<int> b) {
  var miss = 0, n = a.length ~/ 4;
  for (var i = 0; i < n; i++) {
    if ((a[i * 4 + 3] > 128) != (b[i * 4 + 3] > 128)) miss++;
  }
  return miss / n;
}

void main() {
  test("taken apart, the panel is drawn as it was, by its shapes", () async {
    var e = _sketch();
    var apart = takeApartPanel(e, 0, 24);
    var (body, _) = apart.drawingFor(0, 0);
    expect(body.hidden, CharacterRegion.values.toSet(), reason: "its own drawing left out");
    expect(body.shapes, isNotEmpty);
    expect(body.order.length, body.shapes.length);
    for (var g in apart.dna.worn) {
      var (d, _) = g.drawingFor(0, 0);
      expect(d.replaces, isTrue, reason: g.title);
      expect(d.shapes, isNotEmpty, reason: "${g.title} has shapes of its own");
      for (var p in d.parts) {
        expect(g.kind.covers, contains(p), reason: "${g.title} on what it covers");
      }
    }
    expect(isTakenApart(apart, panelKey(0, 0)), isTrue);
    expect(isTakenApart(e, panelKey(0, 0)), isFalse);
    expect(_coverMiss(await _pixels(apart), await _pixels(e)), lessThan(0.02),
        reason: "the same figure");
    // In the order it was drawn in: something of the body over the hoodie
    // -- a hand over its sleeve, the head over its collar.
    var hoodie = apart.dna.worn.firstWhere((g) => g.kind == GarmentKind.hoodie);
    var lowestHoodie = hoodie.drawingFor(0, 0).$1.order.reduce((a, b) => a < b ? a : b);
    expect(body.order.any((o) => o > lowestHoodie), isTrue);
    // Other panels are as they were made.
    expect(isTakenApart(apart, panelKey(90, 0)), isFalse);
    // Put back, exactly as it was made.
    var back = putPanelBack(apart, 0, 24);
    expect(await _pixels(back), await _pixels(e));
  });

  test("posed, taken apart shapes go with the body", () async {
    var e = _sketch();
    var apart = takeApartPanel(e, 0, 24);
    CharacterElement raised(CharacterElement c) =>
        c.copyWith(pose: c.pose.withAngle(CharacterBone.upperArmR, -80));
    expect(_coverMiss(await _pixels(raised(apart)), await _pixels(raised(e))),
        lessThan(0.035));
  });

  test("one garment taken apart stands in for itself alone", () async {
    var e = _sketch();
    var hoodie = e.dna.wardrobe.indexWhere((g) => g.kind == GarmentKind.hoodie);
    var apart = takeApartGarment(e, hoodie, 0, 24);
    expect(isTakenApart(apart, panelKey(0, 0), garment: hoodie), isTrue);
    expect(isTakenApart(apart, panelKey(0, 0)), isFalse, reason: "the body as it is made");
    expect(apart.drawings, isEmpty);
    expect(_coverMiss(await _pixels(apart), await _pixels(e)), lessThan(0.02));
    var saved = elementFromJson(apart.toJson()) as CharacterElement;
    var d = saved.dna.wardrobe[hoodie].drawingFor(0, 0).$1;
    expect(d.replaces, isTrue);
    expect(d.order.length, d.shapes.length);
    expect(await _pixels(putPanelBack(apart, 0, 24, garment: hoodie)), await _pixels(e));
  });

  test("its points edited through the drawing laid over it, the rest kept", () {
    var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
    c.drawOnCharacter("c");
    expect(c.drawnTakenApart, isFalse);
    c.takeApartCharacter("c");
    expect(c.drawnTakenApart, isTrue);
    var e = c.document.elementById("c") as CharacterElement;
    var (body, _) = e.drawingFor(0, 0);
    var proxy = c.editingVector!;
    expect(proxy.shapes!.length, body.shapes.length, reason: "every shape's points to pick");
    // Move one point of one shape.
    var shapes = [...proxy.shapes!];
    var s = shapes[3];
    var path = s.paths.first;
    var nodes = [...path.nodes];
    nodes[0] = nodes[0].copyWith(x: nodes[0].x + 3);
    shapes[3] = s.copyWith(paths: [path.copyWith(nodes: nodes), ...s.paths.skip(1)]);
    c.replaceElement(proxy.copyWith(shapes: shapes));
    var (after, _) = (c.document.elementById("c") as CharacterElement).drawingFor(0, 0);
    expect(after.parts, body.parts, reason: "every shape on its part still");
    expect(after.order, body.order, reason: "and in its place in the order");
    expect(after.hidden, body.hidden);
    // A shape drawn new goes over everything.
    c.replaceElement(c.editingVector!.copyWith(shapes: [...c.editingVector!.shapes!, s]));
    var (added, _) = (c.document.elementById("c") as CharacterElement).drawingFor(0, 0);
    var top = panelOrderTop(e, panelKey(0, 0));
    expect(added.order.last, greaterThan(top - 1e-9));
  });
}
