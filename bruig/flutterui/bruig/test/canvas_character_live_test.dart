import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_live.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_character_live_test.dart is a layer drawn on that its sliders go
// on shaping: its edits kept as it was drawn, carried onto it as it is made
// now. See character_live.dart.

CharacterElement _sketch() => CharacterElement(
    const ElementBase(id: "c", x: 20, y: 20, width: 160, height: 340),
    dna: characterCast.first.dna,
    views: CharacterView.all);

String _key(CharacterElement e) => drawnKey(e, 0, 12);

/// _head is [e]'s head layer's first shape on the view seen, and where.
(int, VectorShape) _head(CharacterElement e) {
  var (d, _) = e.drawingAt(_key(e));
  for (var i = 0; i < d.shapes.length; i++) {
    if (d.layerOf(i) == BodyLayer.head.name && d.shapes[i].origin != null) {
      return (i, d.shapes[i]);
    }
  }
  throw StateError("no head shape");
}

VectorShape _moved(VectorShape s, Offset by) => s.copyWith(paths: [
      for (var p in s.paths)
        p.copyWith(nodes: [
          for (var (k, n) in p.nodes.indexed)
            k == 0 ? n.copyWith(x: n.x + by.dx, y: n.y + by.dy) : n,
        ]),
    ]);

CharacterElement _withShapeAt(CharacterElement e, String key, int i, VectorShape s) {
  var (d, _) = e.drawingAt(key);
  return e.withDrawingAt(
      key, d.copyWith(shapes: [for (var (k, x) in d.shapes.indexed) k == i ? s : x]));
}

CharacterElement _withShape(CharacterElement e, int i, VectorShape s) {
  var (d, _) = e.drawingAt(_key(e));
  return e.withDrawingAt(
      _key(e), d.copyWith(shapes: [for (var (k, x) in d.shapes.indexed) k == i ? s : x]));
}

void main() {
  test("taken apart, a layer keeps its base, each shape marked from it", () {
    var e = takeApartLayer(_sketch(), BodyLayer.head.name, 0, 12);
    var (d, _) = e.drawingAt(_key(e));
    var base = d.bases[BodyLayer.head.name];
    expect(base, isNotNull);
    var mine = [
      for (var i = 0; i < d.shapes.length; i++)
        if (d.layerOf(i) == BodyLayer.head.name) d.shapes[i],
    ];
    expect(mine.length, base!.shapes.length);
    expect([for (var s in mine) s.origin], [for (var j = 0; j < mine.length; j++) "$j"]);
    // Saved, and back.
    var back = CharacterDrawing.fromJson(d.toJson());
    expect(back.bases[BodyLayer.head.name]!.shapes.length, base.shapes.length);
    expect(back.shapes.first.origin, d.shapes.first.origin);
    expect(d.mirrored.bases.length, d.bases.length);
    // Put back: its base goes with it.
    var put = putLayerBack(e, BodyLayer.head.name, 0, 12);
    expect(put.drawingAt(_key(put)).$1.bases, isEmpty);
  });

  test("unedited, it follows the sliders; edited, the edit goes with it", () {
    var e = takeApartLayer(_sketch(), BodyLayer.head.name, 0, 12);
    var (i, shape) = _head(e);
    var edited = _withShape(e, i, _moved(shape, const Offset(0.1, 0.05)));
    CharacterElement jawed(CharacterElement x) =>
        x.copyWith(dna: x.dna.copyWith(look: x.dna.look.withValue(Look.jaw, 1)));
    // As the character draws a squarer jaw: taken apart afresh with it.
    var (_, made) = _head(takeApartLayer(jawed(_sketch()), BodyLayer.head.name, 0, 12));
    var (_, live) = _head(liveCharacter(jawed(e), 0, 12));
    // How far apart two outlines are, round them.
    double apart(VectorShape a, VectorShape b) {
      var pa = a.path.computeMetrics().first, pb = b.path.computeMetrics().first;
      var sum = 0.0;
      for (var k = 0; k < 40; k++) {
        var qa = pa.getTangentForOffset(pa.length * k / 40)!.position;
        var qb = pb.getTangentForOffset(pb.length * k / 40)!.position;
        sum += (qa - qb).distance;
      }
      return sum / 40;
    }

    expect(apart(live, made), lessThan(0.01), reason: "the sliders still shape it");
    expect(apart(live, shape), greaterThan(0.01), reason: "and it has changed");
    // The edit carried: its first point as far from where the slider puts
    // it as it was dragged.
    var (_, carriedOn) = _head(liveCharacter(jawed(edited), 0, 12));
    var p0 = carriedOn.paths.first.nodes.first, m0 = live.paths.first.nodes.first;
    expect(p0.x - m0.x, closeTo(0.1, 1e-6));
    expect(p0.y - m0.y, closeTo(0.05, 1e-6));
  });

  test("drawn on again, what is seen is what is edited", () {
    var e = takeApartLayer(_sketch(), BodyLayer.head.name, 0, 12);
    var (i, shape) = _head(e);
    var edited = _withShape(e, i, _moved(shape, const Offset(0.1, 0)));
    var wider = edited.copyWith(
        dna: edited.dna.copyWith(look: edited.dna.look.withValue(Look.jaw, 1)));
    var shown = _head(liveCharacter(wider, 0, 12)).$2;
    var rebased = rebasedCharacter(wider, 0, 12);
    var stored = _head(rebased).$2;
    expect(stored.paths.first.nodes.first.x, closeTo(shown.paths.first.nodes.first.x, 1e-9),
        reason: "the stored shape is the one shown");
    var again = _head(liveCharacter(rebased, 0, 12)).$2;
    expect(again.paths.first.nodes.first.x, closeTo(shown.paths.first.nodes.first.x, 1e-6),
        reason: "and still shown so");
  });

  test("a colour kept follows the slider; a colour changed is kept", () {
    var e = takeApartLayer(_sketch(), BodyLayer.head.name, 0, 12);
    var (i, shape) = _head(e);
    var tan = const Color(0xFF8D5A3B);
    var darker = e.copyWith(dna: e.dna.copyWith(skin: tan));
    expect(_head(liveCharacter(darker, 0, 12)).$2.fill, isNot(shape.fill));
    var mine = _withShape(e, i, shape.copyWith(fill: const Color(0xFF00FF00)));
    var mineDarker = mine.copyWith(dna: mine.dna.copyWith(skin: tan));
    expect(_head(liveCharacter(mineDarker, 0, 12)).$2.fill, const Color(0xFF00FF00));
  });

  test("painted: a slider changes a layer taken apart", () async {
    Future<List<int>> pixels(CharacterElement e) async {
      var rec = PictureRecorder();
      paintElement(Canvas(rec), e, 0);
      var img = await rec.endRecording().toImage(200, 380);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    var e = takeApartLayer(_sketch(), BodyLayer.head.name, 0, 12);
    var jawed = e.copyWith(dna: e.dna.copyWith(look: e.dna.look.withValue(Look.jaw, 1)));
    expect(await pixels(jawed), isNot(await pixels(e)));
  });

  test("taken apart, a layer lies where it did: under the eyes, the hair", () async {
    // Painted, how many points of [a] and [b] are plainly not alike.
    Future<int> apart(CharacterElement a, CharacterElement b) async {
      Future<List<int>> pixels(CharacterElement e) async {
        var rec = PictureRecorder();
        paintElement(Canvas(rec), e, 0);
        var img = await rec.endRecording().toImage(200, 380);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var pa = await pixels(a), pb = await pixels(b);
      var n = 0;
      for (var i = 0; i < pa.length; i += 4) {
        var d = (pa[i] - pb[i]).abs() + (pa[i + 1] - pb[i + 1]).abs() + (pa[i + 2] - pb[i + 2]).abs();
        if (d > 90) n++;
      }
      return n;
    }

    var e = _sketch();
    var head = takeApartLayer(e, BodyLayer.head.name, 0, 12);
    expect(await apart(e, head), lessThan(300), reason: "the head under its face, not over it");
    // A garment, and the hair over it.
    var more = takeApartLayer(takeApartLayer(head, garmentLayer(0), 0, 12),
        BodyLayer.hairFront.name, 0, 12);
    expect(await apart(e, more), lessThan(300));
  });

  test("an edit copied to another view is that edit, on that view's own shape", () {
    var e = takeApartLayer(_sketch(), BodyLayer.head.name, 0, 12);
    var (i, shape) = _head(e);
    var edited = _withShape(e, i, _moved(shape, const Offset(0.1, 0.05)));
    var copied = copyLayerEdits(edited, BodyLayer.head.name, "0,0", "45,0", 0, 12);
    expect(layerEditedAt(copied, BodyLayer.head.name, "45,0"), isTrue);
    var (there, _) = copied.drawingAt("45,0");
    var base = there.bases[BodyLayer.head.name]!;
    var j = [
      for (var k = 0; k < there.shapes.length; k++)
        if (there.layerOf(k) == BodyLayer.head.name && there.shapes[k].origin == shape.origin) k,
    ].single;
    var made = base.shapes[int.parse(shape.origin!)];
    var p0 = there.shapes[j].paths.first.nodes.first, b0 = made.paths.first.nodes.first;
    expect(p0.x - b0.x, closeTo(0.1, 1e-6), reason: "the same edit");
    expect(p0.y - b0.y, closeTo(0.05, 1e-6));
    expect(there.shapes[j].paths.first.nodes.length, shape.paths.first.nodes.length,
        reason: "the edited shape's own points");
    // The view it came from, as it was.
    expect(copied.drawingAt("0,0").$1.shapes[i].paths.first.nodes.first.x,
        edited.drawingAt("0,0").$1.shapes[i].paths.first.nodes.first.x);
    // Every view.
    var all = edited;
    for (var v in CharacterView.start) {
      for (var k in [v.key, if (oppositeKey(v.key) case var o?) o]) {
        all = copyLayerEdits(all, BodyLayer.head.name, "0,0", k, 0, 12);
      }
    }
    for (var k in ["90,0", "-90,0", "180,0"]) {
      expect(layerEditedAt(all, BodyLayer.head.name, k), isTrue, reason: k);
    }
  });

  test("mirrored, a side's edits go to the other side, flipped", () {
    var side = turnedToView(_sketch(), "90,0", 0);
    var e = takeApartLayer(side, BodyLayer.eyes.name, 0, 12);
    var (d, _) = e.drawingAt("90,0");
    var eye = [
      for (var k = 0; k < d.shapes.length; k++)
        if (d.layerOf(k) == BodyLayer.eyes.name) k,
    ].first;
    var moved = _withShapeAt(e, "90,0", eye, _moved(d.shapes[eye], const Offset(0.2, 0)));
    expect(moved.drawingAt("-90,0").$2, isTrue, reason: "the other way a mirror, until now");
    var mirrored = mirrorLayerEdits(moved, BodyLayer.eyes.name, "90,0");
    var (other, isMirror) = mirrored.drawingAt("-90,0");
    expect(isMirror, isFalse, reason: "its own from now on");
    var flipped = moved.drawingAt("90,0").$1.mirrored;
    var theirs = [
      for (var k = 0; k < other.shapes.length; k++)
        if (other.layerOf(k) == BodyLayer.eyes.name) other.shapes[k],
    ];
    var mine = [
      for (var k = 0; k < flipped.shapes.length; k++)
        if (flipped.layerOf(k) == BodyLayer.eyes.name) flipped.shapes[k],
    ];
    expect(theirs.length, mine.length);
    expect(theirs.first.paths.first.nodes.first.y, closeTo(mine.first.paths.first.nodes.first.y, 1e-9));
    // Drawn there by these, the rest as the character draws it.
    expect(other.hiddenLayers, contains(BodyLayer.eyes.name));
    expect(other.bases[BodyLayer.eyes.name], isNotNull);
  });
}
