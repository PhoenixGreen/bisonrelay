import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_outline.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';

// character_parts.dart is where each part of a sketched character's body is
// on the page as the rig has it -- a frame for each: a root, the way down
// the bone, and a size -- for the shapes drawn on it by hand to be kept in
// the part's own measure and drawn wherever the pose puts it. See
// character_drawing.dart.

/// PartFrame is a part's measure on the page: [origin] its root, [along]
/// the way down it, and [scale] how big a unit of it is.
class PartFrame {
  final Offset origin;
  final Offset along;
  final double scale;
  const PartFrame(this.origin, this.along, this.scale);

  /// across is square to [along]: what the other measure runs along.
  Offset get across => Offset(-along.dy, along.dx);

  Offset toPage(double a, double b) =>
      origin + along * (a * scale) + across * (b * scale);

  (double, double) toLocal(Offset p) {
    var d = p - origin;
    var s = scale == 0 ? 1.0 : scale;
    return (
      (d.dx * along.dx + d.dy * along.dy) / s,
      (d.dx * across.dx + d.dy * across.dy) / s,
    );
  }
}

Offset _unit(Offset d, [Offset otherwise = const Offset(0, 1)]) {
  var l = d.distance;
  return l < 1e-9 ? otherwise : d / l;
}

/// partFrames is every part's frame as [rig] has the body.
Map<CharacterPart, PartFrame> partFrames(CharacterRig rig) {
  var u = rig.unit;
  var down = const Offset(0, 1);
  var turn = rig.headTurn * math.pi / 180;
  // Down the face, as the head is tipped.
  var face = Offset(-math.sin(turn), math.cos(turn));
  PartFrame bone(Offset from, Offset to) =>
      PartFrame(from, _unit(to - from), u);
  var frames = <CharacterPart, PartFrame>{
    CharacterPart.head: PartFrame(rig.headCentre, face, u * rig.headScale),
    CharacterPart.torso: bone(rig.chest, rig.hips),
  };
  for (var (limb, upper, lower, end) in [
    (
      CharacterLimb.armL,
      CharacterPart.upperArmL,
      CharacterPart.foreArmL,
      CharacterPart.handL
    ),
    (
      CharacterLimb.armR,
      CharacterPart.upperArmR,
      CharacterPart.foreArmR,
      CharacterPart.handR
    ),
    (
      CharacterLimb.legL,
      CharacterPart.thighL,
      CharacterPart.shinL,
      CharacterPart.footL
    ),
    (
      CharacterLimb.legR,
      CharacterPart.thighR,
      CharacterPart.shinR,
      CharacterPart.footR
    ),
  ]) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    frames[upper] = bone(a, b);
    frames[lower] = bone(b, c);
    // A hand goes on the way the forearm points; a foot keeps to the floor.
    frames[end] =
        limb.isArm ? PartFrame(c, _unit(c - b), u) : PartFrame(c, down, u);
  }
  return frames;
}

double _toSegment(Offset p, Offset a, Offset b) {
  var ab = b - a;
  var len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-9) return (p - a).distance;
  var t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// partAt is the part of the body [rig] has nearest [p] -- what a shape
/// drawn there is drawn on -- of [among], where it is given: the parts a
/// garment covers.
CharacterPart partAt(CharacterRig rig, Offset p, {Set<CharacterPart>? among}) {
  var best = among == null || among.isEmpty ? CharacterPart.torso : among.first;
  var bestD = double.infinity;
  void consider(CharacterPart part, double d) {
    if (among != null && among.isNotEmpty && !among.contains(part)) return;
    if (d < bestD) {
      bestD = d;
      best = part;
    }
  }

  var r = rig.headRadii;
  var h = rig.headScale;
  consider(CharacterPart.head,
      (p - rig.headCentre).distance - math.max(r.width, r.height) * h);
  consider(CharacterPart.torso,
      _toSegment(p, rig.chest, rig.hips) - rig.shoulderHalf * 0.8);
  for (var (limb, upper, lower, end) in [
    (
      CharacterLimb.armL,
      CharacterPart.upperArmL,
      CharacterPart.foreArmL,
      CharacterPart.handL
    ),
    (
      CharacterLimb.armR,
      CharacterPart.upperArmR,
      CharacterPart.foreArmR,
      CharacterPart.handR
    ),
    (
      CharacterLimb.legL,
      CharacterPart.thighL,
      CharacterPart.shinL,
      CharacterPart.footL
    ),
    (
      CharacterLimb.legR,
      CharacterPart.thighR,
      CharacterPart.shinR,
      CharacterPart.footR
    ),
  ]) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    var half = (limb.isArm ? rig.limbWidth : rig.legWidth) / 2;
    consider(upper, _toSegment(p, a, b) - half);
    consider(lower, _toSegment(p, b, c) - half * 0.8);
    var reach = limb.isArm ? rig.handRadius * 2 : rig.legWidth * 1.4;
    var tip =
        limb.isArm ? c + _unit(c - b) * reach : c + Offset(0, reach * 0.5);
    consider(end, _toSegment(p, c, tip) - half * 0.7);
  }
  return best;
}

/// shapeCentre is the middle of [shape]'s points: what decides its part.
Offset shapeCentre(VectorShape shape) {
  var sum = Offset.zero;
  var n = 0;
  for (var path in shape.paths) {
    for (var node in path.nodes) {
      sum += node.point;
      n++;
    }
  }
  return n == 0 ? Offset.zero : sum / n.toDouble();
}

/// drawingOnPage is [drawing]'s shapes on the page, each where [frames] put
/// its part.
List<VectorShape> drawingOnPage(
        CharacterDrawing drawing, Map<CharacterPart, PartFrame> frames) =>
    [
      for (var (i, shape) in drawing.shapes.indexed)
        if (frames[drawing.parts[i]] case var f?)
          mapShape(shape, (a, b) {
            var p = f.toPage(a, b);
            return (p.dx, p.dy);
          }, f.scale),
    ];

/// shapesOnParts is [shapes] -- on the page -- each put on the part of
/// [rig]'s body it was drawn on, in that part's measure: the reverse of
/// drawingOnPage. [keep] are the parts already known, shape by shape, to
/// keep where there is one; a new shape is put on the part under it.
CharacterDrawing shapesOnParts(List<VectorShape> shapes, CharacterRig rig,
    {List<CharacterPart> keep = const [],
    Set<CharacterRegion> hidden = const {},
    Set<CharacterPart>? among}) {
  var frames = partFrames(rig);
  var parts = <CharacterPart>[];
  var local = <VectorShape>[];
  for (var (i, shape) in shapes.indexed) {
    var part = i < keep.length
        ? keep[i]
        : partAt(rig, shapeCentre(shape), among: among);
    var f = frames[part]!;
    parts.add(part);
    local.add(mapShape(shape, (x, y) => f.toLocal(Offset(x, y)),
        1 / (f.scale == 0 ? 1 : f.scale)));
  }
  return CharacterDrawing(shapes: local, parts: parts, hidden: hidden);
}

/// paintPanelShapes draws the shapes [onPanel] names -- each a place in the
/// panel's order, a drawing and which of its shapes -- lowest first, each
/// where [rig] has its part, as a drawing element draws its shapes.
void paintPanelShapes(Canvas canvas, CharacterRig rig,
    List<(double, CharacterDrawing, int)> onPanel, Rect room) {
  if (onPanel.isEmpty) return;
  var frames = partFrames(rig);
  var sorted = [...onPanel]..sort((a, b) => a.$1.compareTo(b.$1));
  var shapes = <VectorShape>[
    for (var (_, d, i) in sorted)
      if (frames[d.parts[i]] case var f?)
        mapShape(d.shapes[i], (a, b) {
          var p = f.toPage(a, b);
          return (p.dx, p.dy);
        }, f.scale),
  ];
  paintVector(
      canvas,
      room,
      VectorElement(
          ElementBase(id: "drawn", width: room.width, height: room.height),
          viewBox: room,
          shapes: shapes),
      null);
}

/// paintDrawing draws what is drawn by hand on the panel, where [rig] has
/// the body, as a drawing element draws its shapes.
void paintDrawing(
    Canvas canvas, CharacterRig rig, CharacterDrawing drawing, Rect room) {
  if (drawing.shapes.isEmpty) return;
  var shapes = drawingOnPage(drawing, partFrames(rig));
  paintVector(
      canvas,
      room,
      VectorElement(
          ElementBase(id: "drawn", width: room.width, height: room.height),
          viewBox: room,
          shapes: shapes),
      null);
}

/// drawnRig is where [e]'s body is on [frame] -- in its own box, from its
/// corner -- as it is drawn there, and the panel it is seen from: what a
/// drawing on it is laid against. See paintCharacter, which it follows.
(CharacterRig, double turn, double tilt) drawnRig(
    CharacterElement e, int frame, int frameRate) {
  frame = e.style.frameOf(frame);
  var (pose, _) = e.performanceAt(frame, frameRate);
  pose = pose.inPanel;
  var box = characterBox(e, frame, Offset.zero & Size(e.width, e.height));
  var rig = CharacterRig.of(e.style.dnaOf(e.dna), pose, box,
      breath: lifeAt(e, frame, frameRate).breath);
  return (rig, pose.panelTurn, pose.panelTilt);
}

/// drawingProxy is the drawing that stands in for [e]'s panel on [frame]
/// while it is drawn on -- see drawingProxyId -- laid exactly over it: the
/// shapes drawn on the panel, where the pose has them, in the character's
/// own box. It draws nothing itself; the character draws what is on it.
///
/// With [garment], the drawing on that garment of its wardrobe instead;
/// with [layer], only the shapes drawn as that body layer.
VectorElement drawingProxy(CharacterElement e, int frame, int frameRate,
    {int? garment, String? layer}) {
  var (rig, turn, tilt) = drawnRig(e, frame, frameRate);
  var (drawing, _) = _garmentOf(e, garment)?.drawingFor(turn, tilt) ??
      e.drawingShown(turn, tilt);
  if (layer != null) drawing = _only(drawing, layer).$1;
  return VectorElement(
    // Where the character is, and moved as it is moved.
    e.base.copyWith(
        id: drawingProxyId(e.id),
        name: "Drawing on ${e.name}",
        opacity: 0,
        locked: false),
    viewBox: Rect.fromLTWH(0, 0, e.width, e.height),
    fit: VectorFit.stretch,
    shapes: drawingOnPage(drawing, partFrames(rig)),
  );
}

/// _only is [d]'s shapes drawn as [layer], as a drawing of their own, and
/// which of [d]'s they are.
(CharacterDrawing, List<int>) _only(CharacterDrawing d, String layer) {
  var at = [
    for (var i = 0; i < d.shapes.length; i++)
      if (d.layerOf(i) == layer) i,
  ];
  return (
    CharacterDrawing(
      shapes: [for (var i in at) d.shapes[i]],
      parts: [for (var i in at) d.parts[i]],
      order: [for (var i in at) d.orderOf(i, 2e6)],
      layers: [for (var _ in at) layer],
    ),
    at
  );
}

/// drawnFromProxy is [e] with what is on [proxy] -- see drawingProxy --
/// taken onto the panel it is seen from on [frame]: each shape on the part
/// it is over. [before] is the stand-in as it was: a shape found on it as
/// it was keeps its part, its layer and its place in the order.
///
/// With [garment], onto that garment of its wardrobe, each shape on the
/// part under it of those the garment covers; with [layer], as the shapes
/// of that body layer, the panel's others left as they are.
CharacterElement drawnFromProxy(
    CharacterElement e, VectorElement proxy, int frame, int frameRate,
    {VectorElement? before, int? garment, String? layer}) {
  var (rig, turn, tilt) = drawnRig(e, frame, frameRate);
  var g = _garmentOf(e, garment);
  // A mirrored panel's drawing is laid out mirrored, parts and all: what is
  // drawn on it is kept as it is shown, and is its own from then on.
  var (whole, _) = g?.drawingFor(turn, tilt) ?? e.drawingShown(turn, tilt);
  var (old, mine) = layer == null
      ? (whole, [for (var i = 0; i < whole.shapes.length; i++) i])
      : _only(whole, layer);
  var base = _orderBase(e, g);
  var shapes = proxy.shapes ?? const <VectorShape>[];
  var was = before?.shapes ?? const <VectorShape>[];
  var sameCount = was.length == shapes.length && old.shapes.length == shapes.length;
  // Each shape keeps the part, layer and place in the order it had: found
  // as the very shape it was, or -- as many as there were -- edited where
  // it was. A shape new to it goes on the part under it, as the layer drawn
  // on, and in the order between the shapes either side -- or, at the end,
  // over everything.
  var parts = <CharacterPart?>[];
  var order = <double?>[];
  var layers = <String?>[];
  for (var (i, shape) in shapes.indexed) {
    var j = i < was.length && identical(was[i], shape)
        ? i
        : was.indexWhere((w) => identical(w, shape));
    if (j < 0 && sameCount) j = i;
    if (j >= 0 && j < old.shapes.length) {
      parts.add(old.parts[j]);
      order.add(old.orderOf(j, base));
      layers.add(old.layerOf(j));
    } else {
      parts.add(null);
      order.add(null);
      layers.add(layer);
    }
  }
  var top = panelOrderTop(e, turn, tilt);
  for (var i = 0; i < order.length; i++) {
    if (order[i] != null) continue;
    var before = i > 0 ? order[i - 1] : null;
    double? after;
    for (var k = i + 1; k < order.length; k++) {
      if (order[k] != null) {
        after = order[k];
        break;
      }
    }
    order[i] = before != null && after != null && after > before
        ? (before + after) / 2
        : (top = top + 1);
  }
  var placed = shapesOnParts(shapes, rig,
      keep: [
        for (var (i, p) in parts.indexed)
          p ?? partAt(rig, shapeCentre(shapes[i]), among: g?.kind.covers)
      ],
      among: g?.kind.covers);
  // The panel's other shapes, as they were, beside these.
  var others = [
    for (var i = 0; i < whole.shapes.length; i++)
      if (!mine.contains(i)) i,
  ];
  var drawing = whole.copyWith(
    shapes: [for (var i in others) whole.shapes[i], ...placed.shapes],
    parts: [for (var i in others) whole.parts[i], ...placed.parts],
    order: [for (var i in others) whole.orderOf(i, base), for (var o in order) o!],
    layers: [for (var i in others) whole.layerOf(i), ...layers],
  );
  if (g == null) return e.withDrawing(turn, tilt, _keptAsKeyed(e, drawing, layer));
  var wardrobe = [...e.dna.wardrobe];
  wardrobe[garment!] = g.withDrawing(turn, tilt, drawing);
  return e.copyWith(dna: e.dna.copyWith(wardrobe: wardrobe));
}

/// _keptAsKeyed is [drawing] -- edited where the sliders are now -- with
/// each keyed layer's shapes kept as its keyform at the slider's value: the
/// keyform there changed, or one added. With [only], that layer alone; for
/// the rest, only those changed.
CharacterDrawing _keptAsKeyed(CharacterElement e, CharacterDrawing drawing, String? only) {
  if (drawing.keyed.isEmpty) return drawing;
  var keyed = {...drawing.keyed};
  for (var MapEntry(key: layer, value: k) in drawing.keyed.entries) {
    if (only != null && layer != only) continue;
    var v = e.lookValue(k.look);
    var (mine, _) = _only(drawing, layer);
    if (only == null && _sameShapes(mine, k.at(v))) continue;
    keyed[layer] = k.withKey(v, mine);
  }
  return drawing.copyWith(keyed: keyed);
}

bool _sameShapes(CharacterDrawing a, CharacterDrawing b) {
  if (a.shapes.length != b.shapes.length) return false;
  for (var i = 0; i < a.shapes.length; i++) {
    if (a.parts[i] != b.parts[i]) return false;
    if (jsonEncode(a.shapes[i].toJson()) != jsonEncode(b.shapes[i].toJson())) return false;
  }
  return true;
}

/// keyLayer is [e] with [layer] -- taken apart on the panel seen on
/// [frame] -- shaped by the slider [look] through keyforms, its first kept
/// at the slider's value now: its shapes as they are.
CharacterElement keyLayer(
    CharacterElement e, String layer, String look, int frame, int frameRate) {
  var (_, turn, tilt) = drawnRig(e, frame, frameRate);
  var (d, _) = e.drawingShown(turn, tilt);
  var (mine, _) = _only(d, layer);
  if (mine.shapes.isEmpty) return e;
  return e.withDrawing(turn, tilt,
      d.copyWith(keyed: {...d.keyed, layer: LayerKeys(look).withKey(e.lookValue(look), mine)}));
}

/// unkeyLayer is [e] with [layer] no longer keyed on the panel seen on
/// [frame]: its shapes kept as they are at the slider's value now.
CharacterElement unkeyLayer(CharacterElement e, String layer, int frame, int frameRate) {
  var (_, turn, tilt) = drawnRig(e, frame, frameRate);
  var (d, _) = e.drawingShown(turn, tilt);
  return e.withDrawing(turn, tilt, d.copyWith(keyed: {...d.keyed}..remove(layer)));
}

/// withKeyform is [e] with a keyform of [layer] kept at its slider's value
/// now -- its shapes as they are there, to edit -- and withoutKeyform
/// without the one at [value].
CharacterElement withKeyform(CharacterElement e, String layer, int frame, int frameRate) {
  var (_, turn, tilt) = drawnRig(e, frame, frameRate);
  var (d, _) = e.drawingShown(turn, tilt);
  var k = d.keyed[layer];
  if (k == null) return e;
  var v = e.lookValue(k.look);
  return e.withDrawing(turn, tilt, d.copyWith(keyed: {...d.keyed, layer: k.withKey(v, k.at(v))}));
}

CharacterElement withoutKeyform(
    CharacterElement e, String layer, double value, int frame, int frameRate) {
  var (_, turn, tilt) = drawnRig(e, frame, frameRate);
  var (d, _) = e.drawingShown(turn, tilt);
  var k = d.keyed[layer];
  if (k == null) return e;
  var next = k.without(value);
  // The last gone, it is shaped by no slider: as it is.
  return e.withDrawing(
      turn,
      tilt,
      d.copyWith(
          keyed: next.keys.isEmpty ? ({...d.keyed}..remove(layer)) : {...d.keyed, layer: next}));
}

/// keysOf is [layer]'s keyforms on the panel seen on [frame], or null.
LayerKeys? keysOf(CharacterElement e, String layer, int frame, int frameRate) {
  var (_, turn, tilt) = drawnRig(e, frame, frameRate);
  return e.drawingFor(turn, tilt).$1.keyed[layer];
}

/// _orderBase is where the shapes of a drawing kept without an order go:
/// a garment's over what is taken apart, the character's over those.
/// See paintCharacterFigure, which draws them so.
double _orderBase(CharacterElement e, Garment? g) {
  if (g == null) return 2e6;
  var i = e.dna.worn.indexOf(g);
  return 1e6 + math.max(0, i) * 1e4;
}

/// panelOrderTop is the highest place in the order of anything drawn on
/// [e]'s panel turned [turn] and tilted [tilt] -- what a new shape goes
/// over.
double panelOrderTop(CharacterElement e, double turn, double tilt) {
  var top = 0.0;
  void of(CharacterDrawing d, double base) {
    for (var i = 0; i < d.shapes.length; i++) {
      top = math.max(top, d.orderOf(i, base));
    }
  }

  of(e.drawingFor(turn, tilt).$1, 2e6);
  for (var g in e.dna.worn) {
    of(g.drawingFor(turn, tilt).$1, _orderBase(e, g));
  }
  return top;
}

/// isTakenApart is whether [e]'s panel turned [turn] and tilted [tilt] is
/// drawn by its shapes -- see takeApartPanel -- or, with [garment], that
/// garment of its wardrobe is.
bool isTakenApart(CharacterElement e, double turn, double tilt, {int? garment}) {
  if (_garmentOf(e, garment) case var g?) {
    return g.drawingFor(turn, tilt).$1.replaces;
  }
  return e.drawingFor(turn, tilt).$1.hidden.length == CharacterRegion.values.length;
}

/// isLayerTakenApart is whether [layer] of [e] is drawn by its shapes on
/// the panel turned [turn] and tilted [tilt]: taken apart there alone, or
/// with the whole panel.
bool isLayerTakenApart(CharacterElement e, String layer, double turn, double tilt) {
  if (garmentOfLayer(layer) case var i?) return isTakenApart(e, turn, tilt, garment: i);
  return isTakenApart(e, turn, tilt) ||
      e.drawingFor(turn, tilt).$1.hiddenLayers.contains(layer);
}

/// _captured is [e]'s figure on the panel seen on [frame], taken apart,
/// every shape marked with the layer it is drawn as.
List<CapturedShape> _captured(CharacterElement e, int frame, int frameRate) {
  var (rig, turn, tilt) = drawnRig(e, frame, frameRate);
  var shown = e.style.frameOf(frame);
  var (_, face) = e.performanceAt(shown, frameRate);
  return captureFigure(rig, e.style.dnaOf(e.dna), face, lifeAt(e, shown, frameRate),
      e.style, faceRig: e.faceRigFor(turn, tilt).$1);
}

/// _wornIndices is which of [e]'s wardrobe is drawn by its own drawing --
/// worn, and not drawn by hand alone.
List<int> _wornIndices(CharacterElement e) {
  var worn = e.dna.worn;
  return [
    for (var (i, g) in e.dna.wardrobe.indexed)
      if (worn.contains(g) && !g.drawnOnly) i,
  ];
}

/// _taken is [shapes] -- captured, each with its place in the order it was
/// drawn in -- put on the parts of [rig]'s body under them, [among] those
/// a garment covers, as the start of a drawing, with [kept] after them:
/// what was drawn on the panel by hand, over everything at [top] on.
CharacterDrawing _taken(CharacterRig rig, List<(int, CapturedShape)> shapes,
    CharacterDrawing kept, double top,
    {Set<CharacterPart>? among, String? layer}) {
  var on = shapesOnParts([for (var (_, c) in shapes) c.shape], rig, among: among);
  return kept.copyWith(
    shapes: [...on.shapes, ...kept.shapes],
    parts: [...on.parts, ...kept.parts],
    order: [
      for (var (z, _) in shapes) z.toDouble(),
      for (var i = 0; i < kept.shapes.length; i++) kept.orderOf(i, top + 1),
    ],
    layers: [
      for (var (_, c) in shapes) layer ?? c.layer,
      for (var i = 0; i < kept.shapes.length; i++) kept.layerOf(i),
    ],
  );
}

/// takeApartPanel is [e] with the panel it is seen from on [frame] taken
/// apart into shapes, to edit point by point with the drawing tools: the
/// body's on the character's drawing for the panel, each marked with its
/// layer, with the drawing it is made from left out there; each garment's
/// on that garment's drawing, standing in for it. In the order the figure
/// was drawn in, each shape on the part of the body under it. What was
/// drawn on the panel by hand stays, over it. Changes to the character's
/// settings no longer show on the panel until it is put back -- see
/// putPanelBack.
CharacterElement takeApartPanel(CharacterElement e, int frame, int frameRate) {
  var (rig, turn, tilt) = drawnRig(e, frame, frameRate);
  var garments = _wornIndices(e);
  var full = _captured(e, frame, frameRate);
  var top = full.length.toDouble();
  var body = <(int, CapturedShape)>[];
  var worn = <int, List<(int, CapturedShape)>>{};
  for (var (z, c) in full.indexed) {
    var gi = c.layer == null ? null : garmentOfLayer(c.layer!);
    (gi == null ? body : (worn[gi] ??= [])).add((z, c));
  }
  var (own, ownMirrored) = e.drawingFor(turn, tilt);
  // Layers taken apart alone before: their shapes are taken again.
  var kept = ownMirrored ? CharacterDrawing.empty : own;
  kept = _without(kept, kept.hiddenLayers).copyWith(hiddenLayers: const {});
  var next = e.withDrawing(turn, tilt,
      _taken(rig, body, kept, top).copyWith(hidden: CharacterRegion.values.toSet()));
  var wardrobe = [...next.dna.wardrobe];
  for (var gi in garments) {
    var g = wardrobe[gi];
    var (d, mirrored) = g.drawingFor(turn, tilt);
    var keep = mirrored || d.replaces ? CharacterDrawing.empty : d;
    wardrobe[gi] = g.withDrawing(turn, tilt,
        _taken(rig, worn[gi] ?? const [], keep, top, among: g.kind.covers)
            .copyWith(replaces: true));
  }
  return next.copyWith(dna: next.dna.copyWith(wardrobe: wardrobe));
}

/// _without is [d] without the shapes drawn as any of [layers].
CharacterDrawing _without(CharacterDrawing d, Set<String> layers) {
  if (layers.isEmpty) return d;
  var keep = [
    for (var i = 0; i < d.shapes.length; i++)
      if (!layers.contains(d.layerOf(i))) i,
  ];
  return d.copyWith(
    shapes: [for (var i in keep) d.shapes[i]],
    parts: [for (var i in keep) d.parts[i]],
    order: [for (var i in keep) d.orderOf(i, 2e6)],
    layers: [for (var i in keep) d.layerOf(i)],
  );
}

/// takeApartLayer is [e] with [layer] taken apart on the panel it is seen
/// from on [frame]: its shapes -- and only its -- in the order the figure
/// is drawn in, standing in for its own drawing there. A body layer's go
/// on the character's drawing for the panel, a garment's on the garment's.
/// The rest of the figure is drawn as it is made.
CharacterElement takeApartLayer(
    CharacterElement e, String layer, int frame, int frameRate) {
  var (rig, turn, tilt) = drawnRig(e, frame, frameRate);
  var full = _captured(e, frame, frameRate);
  var top = full.length.toDouble();
  var mine = [
    for (var (z, c) in full.indexed)
      if (c.layer == layer) (z, c),
  ];
  if (garmentOfLayer(layer) case var gi?) {
    var g = _garmentOf(e, gi);
    if (g == null || g.drawnOnly || !e.dna.worn.contains(g)) return e;
    var (d, mirrored) = g.drawingFor(turn, tilt);
    var keep = mirrored || d.replaces ? CharacterDrawing.empty : d;
    var wardrobe = [...e.dna.wardrobe];
    wardrobe[gi] = g.withDrawing(turn, tilt,
        _taken(rig, mine, keep, top, among: g.kind.covers).copyWith(replaces: true));
    return e.copyWith(dna: e.dna.copyWith(wardrobe: wardrobe));
  }
  // As shown -- a mirror is kept as it is, its own from now on -- without
  // this layer's shapes from before.
  var (own, _) = e.drawingFor(turn, tilt);
  var kept = _without(own, {layer});
  var taken = _taken(rig, mine, CharacterDrawing.empty, top, layer: layer);
  return e.withDrawing(
      turn,
      tilt,
      kept.copyWith(
        shapes: [...kept.shapes, ...taken.shapes],
        parts: [...kept.parts, ...taken.parts],
        order: [
          for (var i = 0; i < kept.shapes.length; i++) kept.orderOf(i, 2e6),
          ...taken.order,
        ],
        layers: [
          for (var i = 0; i < kept.shapes.length; i++) kept.layerOf(i),
          ...taken.layers,
        ],
        hiddenLayers: {...kept.hiddenLayers, layer},
        // Taken afresh: keyforms of the shapes before no longer fit.
        keyed: {...kept.keyed}..remove(layer),
      ));
}

/// putLayerBack is [e] with [layer] drawn as it is made again on the panel
/// seen on [frame]: its shapes there gone.
CharacterElement putLayerBack(
    CharacterElement e, String layer, int frame, int frameRate) {
  if (garmentOfLayer(layer) case var gi?) {
    return putPanelBack(e, frame, frameRate, garment: gi);
  }
  var (_, turn, tilt) = drawnRig(e, frame, frameRate);
  var (own, _) = e.drawingFor(turn, tilt);
  var kept = _without(own, {layer});
  return e.withDrawing(
      turn,
      tilt,
      kept.copyWith(
          hiddenLayers: {...kept.hiddenLayers}..remove(layer),
          keyed: {...kept.keyed}..remove(layer)));
}

/// takeApartGarment is [e] with garment [garment] of its wardrobe taken
/// apart on the panel it is seen from on [frame]. See takeApartLayer.
CharacterElement takeApartGarment(
        CharacterElement e, int garment, int frame, int frameRate) =>
    takeApartLayer(e, garmentLayer(garment), frame, frameRate);

/// putPanelBack is [e] with the panel it is seen from on [frame] drawn as
/// it is made again -- and what was drawn on it gone -- or, with
/// [garment], that garment there.
CharacterElement putPanelBack(CharacterElement e, int frame, int frameRate,
    {int? garment}) {
  var (_, turn, tilt) = drawnRig(e, frame, frameRate);
  if (_garmentOf(e, garment) case var g?) {
    var wardrobe = [...e.dna.wardrobe];
    wardrobe[garment!] = g.withDrawing(turn, tilt, CharacterDrawing.empty);
    return e.copyWith(dna: e.dna.copyWith(wardrobe: wardrobe));
  }
  var next = e.withDrawing(turn, tilt, CharacterDrawing.empty);
  var wardrobe = [
    for (var g in next.dna.wardrobe)
      g.drawingFor(turn, tilt).$1.replaces
          ? g.withDrawing(turn, tilt, CharacterDrawing.empty)
          : g,
  ];
  return next.copyWith(dna: next.dna.copyWith(wardrobe: wardrobe));
}

/// _garmentOf is [e]'s garment [i], where there is one.
Garment? _garmentOf(CharacterElement e, int? i) =>
    i == null || i < 0 || i >= e.dna.wardrobe.length ? null : e.dna.wardrobe[i];

/// zoomRect is the stretch of the body [rig] has that [zoom] names, in the
/// rig's own measure, with room round it to draw in.
Rect zoomRect(CharacterRig rig, CharacterZoom zoom) {
  var r = rig.headRadii;
  var head = Rect.fromCenter(
      center: rig.headCentre,
      width: r.width * 2 * rig.headScale,
      height: r.height * 2 * rig.headScale);
  Rect round(Iterable<Offset> points, double pad) {
    var list = points.toList();
    var box = Rect.fromPoints(list.first, list.first);
    for (var p in list.skip(1)) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    return box.inflate(pad);
  }

  var hand = rig.handRadius * 2.4;
  var foot = rig.legWidth * 1.6;
  var feet = [rig.ankleL, rig.ankleR];
  var whole = round([
    rig.shoulderL,
    rig.shoulderR,
    rig.elbowL,
    rig.elbowR,
    rig.wristL,
    rig.wristR,
    rig.hipL,
    rig.hipR,
    rig.kneeL,
    rig.kneeR,
    ...feet,
  ], hand)
      .expandToInclude(head);
  return switch (zoom) {
    CharacterZoom.fullBody => whole.inflate(rig.unit * 0.3),
    CharacterZoom.head => head.inflate(r.width * rig.headScale * 0.5),
    CharacterZoom.headAndChest => head
        .expandToInclude(
            round([rig.shoulderL, rig.shoulderR, rig.chest], rig.unit * 0.3))
        .inflate(rig.unit * 0.2),
    CharacterZoom.upperBody => head.expandToInclude(
        round([rig.shoulderL, rig.shoulderR, rig.hips], rig.unit * 0.4)),
    CharacterZoom.lowerBody =>
      round([rig.hipL, rig.hipR, rig.kneeL, rig.kneeR, ...feet], foot),
    CharacterZoom.hands => round([rig.wristL, rig.wristR], hand),
    CharacterZoom.feet => round(feet, foot),
  };
}

/// PlacedRigPoint is one of a limb's points where the rig puts it: see
/// character_rig_points.dart.
class PlacedRigPoint {
  final RigPoint point;

  /// at is where it is drawn, and on where it would be unmoved: on its bone.
  final Offset at;
  final Offset on;

  /// dir is the way its bone runs.
  final Offset dir;

  /// t is how far down the whole limb it is, root 0 to end 1.
  final double t;
  const PlacedRigPoint(this.point, this.at, this.on, this.dir, this.t);

  Offset get across => Offset(-dir.dy, dir.dx);
}

/// placedRigPoints is [limb]'s points, root to end, where [rig] puts them,
/// as [points] has them changed.
List<PlacedRigPoint> placedRigPoints(
    CharacterRig rig, CharacterLimb limb, RigPoints points) {
  var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
  var (upper, lower) = rig.lengths(limb);
  var whole = upper + lower;
  var u = rig.unit;
  return [
    for (var p in points.of(limb.name))
      () {
        var (from, to) = p.bone == 0 ? (a, b) : (b, c);
        var dir = _unit(to - from, p.bone == 0 ? _unit(c - b) : _unit(b - a));
        var on = Offset.lerp(from, to, p.f)!;
        var across = Offset(-dir.dy, dir.dx);
        var t = whole == 0
            ? 0.0
            : (p.bone == 0 ? p.f * upper : upper + p.f * lower) / whole;
        return PlacedRigPoint(
            p, on + dir * (p.along * u) + across * (p.across * u), on, dir, t);
      }(),
  ];
}

/// rigPointFor is the point a limb would have at [page] -- a click on its
/// line -- unmoved: on the bone nearest, how far along it.
RigPoint rigPointFor(
    CharacterRig rig, CharacterLimb limb, RigPoints points, Offset page) {
  var placed = placedRigPoints(rig, limb, points);
  var best = (0, 0.5);
  var bestD = double.infinity;
  for (var i = 0; i + 1 < placed.length; i++) {
    var p = placed[i], q = placed[i + 1];
    var ab = q.at - p.at;
    var len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    var k = len2 < 1e-9
        ? 0.0
        : (((page - p.at).dx * ab.dx + (page - p.at).dy * ab.dy) / len2)
            .clamp(0.0, 1.0);
    var d = (page - (p.at + ab * k)).distance;
    if (d < bestD) {
      bestD = d;
      // Along the limb, between the two -- on the bone they share, or
      // across the joint between.
      var order = p.point.order + (q.point.order - p.point.order) * k;
      var bone = order >= 1 ? 1 : 0;
      best = (bone, (order - bone).clamp(0.02, 0.98));
    }
  }
  return RigPoint(best.$1, best.$2);
}
