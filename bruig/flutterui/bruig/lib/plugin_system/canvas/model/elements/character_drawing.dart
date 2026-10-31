import 'dart:ui' show Offset;

import 'package:bruig/plugin_system/canvas/model/elements/character_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';

// character_drawing.dart is what is drawn by hand on a sketched character:
// for each panel it is seen from -- turned every 45 degrees, from four
// heights; see CharacterPose.inPanel -- shapes drawn with the drawing
// tools, each tied to the part of the body it was drawn on, so it moves
// with that part when the character is posed.
//
// Each shape is kept in its part's own measure: along the bone from its
// root and across it, in head units. A pose puts the part somewhere else;
// the shape goes with it. A panel seen from the other side -- turned -45
// against 45 -- is, until it is drawn itself, its mirror: the same shapes,
// flipped across each bone, on the part on the other side.

/// CharacterPart is a part of the body a drawn shape belongs to.
enum CharacterPart {
  head("Head"),
  torso("Body"),
  upperArmL("Left upper arm"),
  foreArmL("Left forearm"),
  handL("Left hand"),
  upperArmR("Right upper arm"),
  foreArmR("Right forearm"),
  handR("Right hand"),
  thighL("Left thigh"),
  shinL("Left shin"),
  footL("Left foot"),
  thighR("Right thigh"),
  shinR("Right shin"),
  footR("Right foot");

  final String label;
  const CharacterPart(this.label);

  static CharacterPart? fromName(String? name) {
    for (var p in values) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// mirrored is the part on the other side: the left hand for the right.
  CharacterPart get mirrored => switch (this) {
        upperArmL => upperArmR,
        foreArmL => foreArmR,
        handL => handR,
        upperArmR => upperArmL,
        foreArmR => foreArmL,
        handR => handL,
        thighL => thighR,
        shinL => shinR,
        footL => footR,
        thighR => thighL,
        shinR => shinL,
        footR => footL,
        _ => this,
      };

  /// region is the stretch of the body this part is in -- what hiding the
  /// generated drawing takes away.
  CharacterRegion get region => switch (this) {
        head => CharacterRegion.head,
        torso => CharacterRegion.torso,
        upperArmL || foreArmL || handL => CharacterRegion.armL,
        upperArmR || foreArmR || handR => CharacterRegion.armR,
        thighL || shinL || footL => CharacterRegion.legL,
        thighR || shinR || footR => CharacterRegion.legR,
      };
}

/// CharacterRegion is a stretch of the body the generated drawing can be
/// hidden in, for a drawing of its own to take its place.
enum CharacterRegion {
  head("Head"),
  torso("Body"),
  armL("Left arm"),
  armR("Right arm"),
  legL("Left leg"),
  legR("Right leg");

  final String label;
  const CharacterRegion(this.label);

  static CharacterRegion? fromName(String? name) {
    for (var r in values) {
      if (r.name == name) return r;
    }
    return null;
  }

  CharacterRegion get mirrored => switch (this) {
        armL => armR,
        armR => armL,
        legL => legR,
        legR => legL,
        _ => this,
      };
}

/// panelKey names the panel seen turned [turn] and tilted [tilt] -- both on
/// a panel already; see CharacterPose.inPanel.
String panelKey(double turn, double tilt) => "${turn.round()},${tilt.round()}";

/// panelLabel is a panel's name as the panel list shows it.
String panelLabel(double turn, double tilt) {
  var side = switch (turn.round()) {
    0 => "Front",
    45 => "Front, turned left",
    90 => "Side, facing left",
    135 => "Back, turned left",
    180 || -180 => "Back",
    -45 => "Front, turned right",
    -90 => "Side, facing right",
    -135 => "Back, turned right",
    _ => "${turn.round()}°",
  };
  var height = switch (tilt.round()) {
    -45 => "from below",
    45 => "from above",
    85 => "from the top",
    _ => "",
  };
  return height.isEmpty ? side : "$side, $height";
}

/// CharacterDrawing is what is drawn on one panel: the shapes, each with
/// the part it belongs to, and where the generated drawing is hidden.
class CharacterDrawing {
  /// shapes are in each one's part's own measure -- see the note at the top
  /// of the file -- and parts says whose, shape by shape.
  final List<VectorShape> shapes;
  final List<CharacterPart> parts;
  final Set<CharacterRegion> hidden;

  /// order is where each shape is drawn among all a panel's -- the
  /// character's and what it wears -- lowest first: a panel taken apart
  /// keeps the order the figure was drawn in, so hair lies over a collar
  /// and a hand over a sleeve. Empty for a drawing made before, whose
  /// shapes go as orderOf says.
  final List<double> order;

  /// replaces is a garment's drawing standing in for its own on the panel:
  /// a garment taken apart there.
  final bool replaces;

  /// layers is the layer each shape is drawn as -- see character_layers.dart
  /// -- shape by shape: null for one drawn over the whole figure. Empty for
  /// a drawing made before, all of whose shapes are.
  final List<String?> layers;

  /// hiddenLayers is the body layers drawn by their shapes here, in place
  /// of their own drawing: layers taken apart on the panel.
  final Set<String> hiddenLayers;

  /// keyed is the layers of the panel shaped by a slider through drawings
  /// kept at its values -- see LayerKeys -- by layer.
  final Map<String, LayerKeys> keyed;

  /// bases is each layer taken apart here as the character drew it then,
  /// by layer: what its shapes -- each marked with which of these it began
  /// as, see VectorShape.origin -- have been edited from. The character
  /// drawn as it is now, the edits are carried onto it, so its sliders go
  /// on shaping a layer drawn on. See character_live.dart.
  final Map<String, CharacterDrawing> bases;

  const CharacterDrawing(
      {this.shapes = const [],
      this.parts = const [],
      this.hidden = const {},
      this.order = const [],
      this.replaces = false,
      this.layers = const [],
      this.hiddenLayers = const {},
      this.keyed = const {},
      this.bases = const {}});

  /// layerOf is the layer shape [i] is drawn as, or null.
  String? layerOf(int i) => i < layers.length ? layers[i] : null;

  /// orderOf is where shape [i] is drawn: as kept, or -- for a drawing
  /// without -- after everything taken apart, from [base] on.
  double orderOf(int i, double base) =>
      i < order.length ? order[i] : base + i;

  static const CharacterDrawing empty = CharacterDrawing();

  bool get isEmpty =>
      shapes.isEmpty && hidden.isEmpty && !replaces && hiddenLayers.isEmpty && keyed.isEmpty;

  CharacterDrawing copyWith(
          {List<VectorShape>? shapes,
          List<CharacterPart>? parts,
          Set<CharacterRegion>? hidden,
          List<double>? order,
          bool? replaces,
          List<String?>? layers,
          Set<String>? hiddenLayers,
          Map<String, LayerKeys>? keyed,
          Map<String, CharacterDrawing>? bases}) =>
      CharacterDrawing(
          shapes: shapes ?? this.shapes,
          parts: parts ?? this.parts,
          hidden: hidden ?? this.hidden,
          order: order ?? this.order,
          replaces: replaces ?? this.replaces,
          layers: layers ?? this.layers,
          hiddenLayers: hiddenLayers ?? this.hiddenLayers,
          keyed: keyed ?? this.keyed,
          bases: bases ?? this.bases);

  /// mirrored is this drawing seen from the other side: each shape flipped
  /// across its bone and put on the part opposite.
  CharacterDrawing get mirrored => CharacterDrawing(
        shapes: [for (var s in shapes) mapShape(s, (x, y) => (x, -y), 1)],
        parts: [for (var p in parts) p.mirrored],
        hidden: {for (var r in hidden) r.mirrored},
        order: order,
        replaces: replaces,
        layers: [for (var l in layers) l == null ? null : _mirroredLayer(l)],
        hiddenLayers: {for (var l in hiddenLayers) _mirroredLayer(l)},
        keyed: {for (var e in keyed.entries) _mirroredLayer(e.key): e.value.mirrored},
        bases: {for (var e in bases.entries) _mirroredLayer(e.key): e.value.mirrored},
      );

  static String _mirroredLayer(String l) =>
      BodyLayer.fromName(l)?.mirrored.name ?? l;

  Map<String, dynamic> toJson() => {
        "shapes": [for (var s in shapes) s.toJson()],
        "parts": [for (var p in parts) p.name],
        if (hidden.isNotEmpty) "hidden": [for (var r in hidden) r.name],
        if (order.isNotEmpty) "order": order,
        if (replaces) "replaces": true,
        if (layers.any((l) => l != null)) "layers": layers,
        if (hiddenLayers.isNotEmpty) "hiddenLayers": hiddenLayers.toList()..sort(),
        if (keyed.isNotEmpty)
          "keyed": {for (var e in keyed.entries) e.key: e.value.toJson()},
        if (bases.isNotEmpty)
          "bases": {for (var e in bases.entries) e.key: e.value.toJson()},
      };

  factory CharacterDrawing.fromJson(Map<String, dynamic> json) {
    var shapes = <VectorShape>[];
    var parts = <CharacterPart>[];
    var named = json["parts"] as List? ?? const [];
    for (var (i, s) in (json["shapes"] as List? ?? const []).indexed) {
      if (VectorShape.fromJson(s) case var shape?) {
        shapes.add(shape);
        // A shape without its part is on the body.
        parts.add(CharacterPart.fromName(
                i < named.length ? named[i] as String? : null) ??
            CharacterPart.torso);
      }
    }
    var order = [
      for (var o in json["order"] as List? ?? const [])
        if (o is num) o.toDouble(),
    ];
    var layers = [
      for (var l in json["layers"] as List? ?? const []) l is String ? l : null,
    ];
    return CharacterDrawing(
      bases: {
        if (json["bases"] case Map raw)
          for (var e in raw.entries)
            if (e.value is Map<String, dynamic>)
              "${e.key}": CharacterDrawing.fromJson(e.value as Map<String, dynamic>),
      },
      keyed: {
        if (json["keyed"] case Map raw)
          for (var e in raw.entries)
            if (LayerKeys.fromJson(e.value) case var k?) "${e.key}": k,
      },
      layers: layers.length == shapes.length ? layers : const [],
      hiddenLayers: {
        for (var l in json["hiddenLayers"] as List? ?? const [])
          if (l is String) l,
      },
      shapes: shapes,
      parts: parts,
      // Kept only whole: a shape's place is no use without the rest's.
      order: order.length == shapes.length ? order : const [],
      replaces: json["replaces"] == true,
      hidden: {
        for (var r in (json["hidden"] as List? ?? const []))
          if (CharacterRegion.fromName(r as String?) case var region?) region,
      },
    );
  }
}

/// mapShape is [shape] with every point it is drawn through moved by [to],
/// and its line widths scaled by [scale]: for taking a shape from one
/// measure to another.
VectorShape mapShape(VectorShape shape,
    (double, double) Function(double x, double y) to, double scale) {
  // A node's handles are offsets from it: their ends are moved, and the
  // node taken back off them. Its width is a share of the shape's line, so
  // it stays as it is.
  VectorNode node(VectorNode n) {
    var (x, y) = to(n.x, n.y);
    var (ix, iy) = n.hasIn ? to(n.x + n.inX, n.y + n.inY) : (x, y);
    var (ox, oy) = n.hasOut ? to(n.x + n.outX, n.y + n.outY) : (x, y);
    return n.copyWith(
        x: x, y: y, inX: ix - x, inY: iy - y, outX: ox - x, outY: oy - y);
  }

  // The tint, shadow and highlight laid on it, and what was rubbed out of
  // it, are strokes of their own over it: moved as its points are.
  Offset point(Offset p) {
    var (x, y) = to(p.dx, p.dy);
    return Offset(x, y);
  }

  return shape.copyWith(
    paths: [
      for (var p in shape.paths)
        p.copyWith(nodes: [for (var n in p.nodes) node(n)]),
    ],
    strokeWidth: shape.strokeWidth * scale,
    tints: [for (var t in shape.tints) t.mapped(point, scale: scale)],
    erasures: [for (var t in shape.erasures) t.mapped(point, scale: scale)],
  );
}

/// drawingProxyId names the drawing that stands in for character [id]'s
/// panel while it is drawn on: a Vector element laid over it, which the
/// drawing tools edit as they edit any drawing. It is never saved -- see
/// isDrawingProxy -- and what is drawn on it goes into the character.
String drawingProxyId(String id) => "$id$_proxySuffix";

const String _proxySuffix = "~drawing";

bool isDrawingProxy(String id) => id.endsWith(_proxySuffix);

/// drawnCharacterOf is the character the stand-in [id] draws on, by id, or
/// null when [id] is not one.
String? drawnCharacterOf(String id) => isDrawingProxy(id)
    ? id.substring(0, id.length - _proxySuffix.length)
    : null;

/// CharacterZoom is a stretch of the body the view can be zoomed onto in
/// one click, to draw there.
enum CharacterZoom {
  fullBody("Full body"),
  head("Head"),
  headAndChest("Head and chest"),
  upperBody("Upper body"),
  lowerBody("Lower body"),
  hands("Hands"),
  feet("Feet");

  final String label;
  const CharacterZoom(this.label);
}

/// viewKeyOf is the key a view's drawings are kept by: its panel's -- see
/// panelKey -- and, for a view of a pose, "@" and the pose's name.
String viewKeyOf(double turn, double tilt, [String? pose]) =>
    pose == null ? panelKey(turn, tilt) : "${panelKey(turn, tilt)}@$pose";

/// oppositeKey is the key of the view turned the other way -- the one [key]
/// is the mirror of -- or null for one with no other way: front or back.
String? oppositeKey(String key) {
  var at = key.indexOf("@");
  var panel = at < 0 ? key : key.substring(0, at);
  var rest = at < 0 ? "" : key.substring(at);
  var comma = panel.indexOf(",");
  if (comma < 0) return null;
  var turn = double.tryParse(panel.substring(0, comma));
  if (turn == null || turn.round() % 180 == 0) return null;
  return "${(-turn).round()},${panel.substring(comma + 1)}$rest";
}

/// baseKeyOf is a pose view's key without its pose -- the view it is drawn
/// as until it is drawn itself -- or null for a view with none.
String? baseKeyOf(String key) {
  var at = key.indexOf("@");
  return at < 0 ? null : key.substring(0, at);
}

/// atViewKey is what [kept] has for the view [key]: its own; or the view
/// turned the other way's, [mirror]ed; or, for a view of a pose, its view's
/// with no pose -- and whether it is a mirror.
(T?, bool) atViewKey<T>(Map<String, T> kept, String key, T Function(T) mirror) {
  if (kept[key] case var own?) return (own, false);
  if (oppositeKey(key) case var other? when kept[other] != null) {
    return (mirror(kept[other] as T), true);
  }
  if (baseKeyOf(key) case var base?) return atViewKey(kept, base, mirror);
  return (null, false);
}

/// drawingOnPanel is what [drawings] has on the panel turned [turn] and
/// tilted [tilt]: its own, or the panel opposite's mirrored -- and whether
/// it is that mirror. See CharacterElement.drawingFor.
(CharacterDrawing, bool) drawingOnPanel(
        Map<String, CharacterDrawing> drawings, double turn, double tilt) =>
    drawingAtKey(drawings, panelKey(turn, tilt));

(CharacterDrawing, bool) drawingAtKey(Map<String, CharacterDrawing> drawings, String key) {
  var (d, mirrored) = atViewKey(drawings, key, (d) => d.mirrored);
  return (d ?? CharacterDrawing.empty, mirrored);
}

/// withPanelDrawing is [drawings] with [drawing] on the panel turned [turn]
/// and tilted [tilt]. An empty one takes the panel's own away -- unless the
/// panel opposite has a drawing, which it would then mirror: there it is
/// kept, blank, as it was left. withoutDrawingAtKey puts the mirror back.
Map<String, CharacterDrawing> withPanelDrawing(Map<String, CharacterDrawing> drawings,
        double turn, double tilt, CharacterDrawing drawing) =>
    withDrawingAtKey(drawings, panelKey(turn, tilt), drawing);

Map<String, CharacterDrawing> withDrawingAtKey(
    Map<String, CharacterDrawing> drawings, String key, CharacterDrawing drawing) {
  var next = {...drawings};
  // Every shape rubbed out of a panel that mirrors the other side: left
  // blank, as it was made -- not the other side's again (Ken's gap).
  var other = oppositeKey(key);
  var mirrors = other != null && drawings[other]?.isEmpty == false;
  if (drawing.isEmpty && !mirrors) {
    next.remove(key);
  } else {
    next[key] = drawing;
  }
  return next;
}

/// withoutDrawingAtKey is [drawings] with the view [key]'s own drawing
/// taken away, blank or not: drawn again as the other side's mirror, or as
/// it is made.
Map<String, CharacterDrawing> withoutDrawingAtKey(Map<String, CharacterDrawing> drawings, String key) =>
    {...drawings}..remove(key);

/// keptBlankAtKey is whether the view [key] is left blank on purpose: a
/// drawing of its own with nothing in it, where it would mirror the other
/// side's.
bool keptBlankAtKey(Map<String, CharacterDrawing> drawings, String key) =>
    drawings[key]?.isEmpty == true;

/// LayerKeys is a layer of a panel shaped by a slider through drawings:
/// its shapes as drawn at each of the slider's values kept -- keyforms, as
/// Live2D calls them -- blended between, point by point, at any value in
/// between, and held beyond the first and the last.
///
/// Every keyform starts as a copy of the shapes at the value it is made at,
/// so they have the same shapes and the same points, and blend.
class LayerKeys {
  /// look is the slider, by its Look name.
  final String look;

  /// keys is each value kept and the layer's shapes there, lowest first --
  /// each a drawing of that layer's shapes alone.
  final List<(double, CharacterDrawing)> keys;
  const LayerKeys(this.look, [this.keys = const []]);

  /// at is the layer's shapes at [value]: the keyform there, or the two
  /// either side blended.
  CharacterDrawing at(double value) {
    if (keys.isEmpty) return CharacterDrawing.empty;
    if (value <= keys.first.$1) return keys.first.$2;
    if (value >= keys.last.$1) return keys.last.$2;
    for (var i = 0; i + 1 < keys.length; i++) {
      var (a, da) = keys[i];
      var (b, db) = keys[i + 1];
      if (value <= b) return blendDrawings(da, db, b == a ? 0 : (value - a) / (b - a));
    }
    return keys.last.$2;
  }

  /// keyAt is the index of the keyform at [value], or -1.
  int keyAt(double value) => keys.indexWhere((k) => (k.$1 - value).abs() < 0.005);

  /// withKey is this with [d] kept at [value]: in place of the keyform
  /// there, or added. A shape added or taken away goes for every keyform:
  /// shapes added are given to the others as they are; with shapes taken
  /// away, the others are made as this one.
  LayerKeys withKey(double value, CharacterDrawing d) {
    var next = <(double, CharacterDrawing)>[];
    for (var (v, k) in keys) {
      if ((v - value).abs() < 0.005) continue;
      if (k.shapes.length < d.shapes.length) {
        var extra = d.shapes.length - k.shapes.length;
        k = k.copyWith(
          shapes: [...k.shapes, ...d.shapes.skip(d.shapes.length - extra)],
          parts: [...k.parts, ...d.parts.skip(d.parts.length - extra)],
          order: [
            for (var i = 0; i < k.shapes.length; i++) k.orderOf(i, 2e6),
            ...d.order.skip(d.order.length - extra),
          ],
          layers: [
            for (var i = 0; i < k.shapes.length; i++) k.layerOf(i),
            ...d.layers.skip(d.layers.length - extra),
          ],
        );
      } else if (k.shapes.length > d.shapes.length) {
        k = d;
      }
      next.add((v, k));
    }
    next.add((value, d));
    next.sort((a, b) => a.$1.compareTo(b.$1));
    return LayerKeys(look, next);
  }

  /// without is this without the keyform at [value].
  LayerKeys without(double value) =>
      LayerKeys(look, [for (var k in keys) if ((k.$1 - value).abs() >= 0.005) k]);

  LayerKeys get mirrored => LayerKeys(look, [for (var (v, d) in keys) (v, d.mirrored)]);

  Map<String, dynamic> toJson() => {
        "look": look,
        "keys": [
          for (var (v, d) in keys) {"at": v, "drawing": d.toJson()}
        ],
      };

  static LayerKeys? fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json["look"] is! String) return null;
    return LayerKeys(json["look"] as String, [
      for (var k in json["keys"] as List? ?? const [])
        if (k is Map<String, dynamic> && k["at"] is num && k["drawing"] is Map<String, dynamic>)
          ((k["at"] as num).toDouble(),
              CharacterDrawing.fromJson(k["drawing"] as Map<String, dynamic>)),
    ]..sort((a, b) => a.$1.compareTo(b.$1)));
  }
}

/// blendDrawings is [a] and [b] mixed [t] of the way from one to the other,
/// point by point: each shape's points where the two have the same points,
/// and the nearer's shape where they do not.
CharacterDrawing blendDrawings(CharacterDrawing a, CharacterDrawing b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  if (a.shapes.length != b.shapes.length) return t < 0.5 ? a : b;
  double mix(double x, double y) => x + (y - x) * t;
  VectorShape shape(VectorShape sa, VectorShape sb) {
    if (sa.paths.length != sb.paths.length) return t < 0.5 ? sa : sb;
    var paths = <VectorPath>[];
    for (var (i, pa) in sa.paths.indexed) {
      var pb = sb.paths[i];
      if (pa.nodes.length != pb.nodes.length) return t < 0.5 ? sa : sb;
      paths.add(pa.copyWith(nodes: [
        for (var (j, na) in pa.nodes.indexed)
          na.copyWith(
            x: mix(na.x, pb.nodes[j].x),
            y: mix(na.y, pb.nodes[j].y),
            inX: mix(na.inX, pb.nodes[j].inX),
            inY: mix(na.inY, pb.nodes[j].inY),
            outX: mix(na.outX, pb.nodes[j].outX),
            outY: mix(na.outY, pb.nodes[j].outY),
          ),
      ]));
    }
    return (t < 0.5 ? sa : sb).copyWith(
        paths: paths, strokeWidth: mix(sa.strokeWidth, sb.strokeWidth));
  }

  return (t < 0.5 ? a : b).copyWith(shapes: [
    for (var (i, sa) in a.shapes.indexed) shape(sa, b.shapes[i]),
  ]);
}

/// keyedAt is [d] with each keyed layer's shapes as its keyforms make them
/// at the slider's value -- [valueOf] a Look's value by its name.
CharacterDrawing keyedAt(CharacterDrawing d, double Function(String look) valueOf) {
  if (d.keyed.isEmpty) return d;
  var shapes = <VectorShape>[];
  var parts = <CharacterPart>[];
  var order = <double>[];
  var layers = <String?>[];
  for (var i = 0; i < d.shapes.length; i++) {
    if (d.keyed.containsKey(d.layerOf(i))) continue;
    shapes.add(d.shapes[i]);
    parts.add(d.parts[i]);
    order.add(d.orderOf(i, 2e6));
    layers.add(d.layerOf(i));
  }
  for (var MapEntry(key: layer, value: k) in d.keyed.entries) {
    var at = k.at(valueOf(k.look));
    for (var i = 0; i < at.shapes.length; i++) {
      shapes.add(at.shapes[i]);
      parts.add(at.parts[i]);
      order.add(at.orderOf(i, 2e6));
      layers.add(layer);
    }
  }
  return d.copyWith(shapes: shapes, parts: parts, order: order, layers: layers);
}
