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

  const CharacterDrawing(
      {this.shapes = const [], this.parts = const [], this.hidden = const {}});

  static const CharacterDrawing empty = CharacterDrawing();

  bool get isEmpty => shapes.isEmpty && hidden.isEmpty;

  CharacterDrawing copyWith(
          {List<VectorShape>? shapes,
          List<CharacterPart>? parts,
          Set<CharacterRegion>? hidden}) =>
      CharacterDrawing(
          shapes: shapes ?? this.shapes,
          parts: parts ?? this.parts,
          hidden: hidden ?? this.hidden);

  /// mirrored is this drawing seen from the other side: each shape flipped
  /// across its bone and put on the part opposite.
  CharacterDrawing get mirrored => CharacterDrawing(
        shapes: [for (var s in shapes) mapShape(s, (x, y) => (x, -y), 1)],
        parts: [for (var p in parts) p.mirrored],
        hidden: {for (var r in hidden) r.mirrored},
      );

  Map<String, dynamic> toJson() => {
        "shapes": [for (var s in shapes) s.toJson()],
        "parts": [for (var p in parts) p.name],
        if (hidden.isNotEmpty) "hidden": [for (var r in hidden) r.name],
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
    return CharacterDrawing(
      shapes: shapes,
      parts: parts,
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

  return shape.copyWith(
    paths: [
      for (var p in shape.paths)
        p.copyWith(nodes: [for (var n in p.nodes) node(n)]),
    ],
    strokeWidth: shape.strokeWidth * scale,
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
