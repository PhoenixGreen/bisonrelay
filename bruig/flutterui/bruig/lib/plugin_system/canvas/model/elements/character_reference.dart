import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// character_reference.dart is what a Sketch character is drawn from and
// with, in the Character Studio: a model sheet -- a turnaround, a sketch, a
// photo of a drawing -- cut into the views it shows, laid over each view to
// trace and to check against; and the character's own palette, its colours
// named, each the one paint for every part painted with it. See
// ui/character_studio.dart.

/// referenceFaces is the key of a reference's cut that holds its faces --
/// an expression sheet -- rather than a view of the whole figure.
const String referenceFaces = "faces";

/// CharacterReference is a model sheet: the picture, the part of it each
/// view is drawn from -- by view key, in the picture's own pixels -- and
/// how strongly it is shown over the drawing.
class CharacterReference {
  final String assetId;

  /// cutout is the picture with its sheet's background taken out, as it is
  /// laid over the views -- the figure alone, as on a light table -- or ""
  /// to lay the picture itself.
  final String cutout;
  final Map<String, Rect> cuts;

  /// skulls are where the head's own top is in each cut, in the picture's
  /// pixels -- under the hair piled on it -- for the cut to be laid with it
  /// on the top of the character's head, and its feet on the ground.
  final Map<String, double> skulls;

  /// heads is how many heads tall the front figure stands, measured from
  /// its skull to its feet -- nought where it was not measured.
  final double heads;
  final double strength;

  /// shown is whether it is shown over the views at all.
  final bool shown;

  const CharacterReference(this.assetId,
      {this.cutout = "",
      this.cuts = const {},
      this.skulls = const {},
      this.heads = 0,
      this.strength = 0.5,
      this.shown = true});

  CharacterReference copyWith(
          {String? cutout,
          Map<String, Rect>? cuts,
          Map<String, double>? skulls,
          double? heads,
          double? strength,
          bool? shown}) =>
      CharacterReference(assetId,
          cutout: cutout ?? this.cutout,
          cuts: cuts ?? this.cuts,
          skulls: skulls ?? this.skulls,
          heads: heads ?? this.heads,
          strength: (strength ?? this.strength).clamp(0.0, 1.0),
          shown: shown ?? this.shown);

  /// laid is the picture laid over the views: its cutout, where it has one.
  String get laid => cutout.isEmpty ? assetId : cutout;

  /// scale is how the sheet's figures are drawn: the front's height from
  /// its skull to its feet -- every figure on one sheet drawn to it -- or
  /// null where the front was not measured.
  double? get figureHeight {
    var front = cuts["0,0"];
    var skull = skulls["0,0"];
    if (front == null || skull == null) return null;
    var h = front.bottom - skull;
    return h > 1 ? h : null;
  }

  /// cutFor is the part of the picture view [key] is drawn from: its own,
  /// or the one turned the other way -- a side drawn facing right serves
  /// facing left, mirrored -- with the key it is kept under, or null.
  (Rect, bool, String)? cutFor(String key) {
    var panel = key.split("@").first;
    if (cuts[panel] case var r?) return (r, false, panel);
    var turn = double.tryParse(panel.split(",").first);
    if (turn == null) return null;
    var other = (360 - turn) % 360;
    for (var MapEntry(key: k, value: r) in cuts.entries) {
      if (double.tryParse(k.split(",").first) case var t?
          when (t - other).abs() < 0.5) {
        return (r, true, k);
      }
    }
    return null;
  }

  /// laidOver is where view [key]'s cut lies over [box] -- [head] and
  /// [ground] its figure's top of head and ground, across the box -- as
  /// the Studio lays it: to the front's scale, its skull at the head's
  /// height, stood on the ground, centred across. The cut, where it lies,
  /// and whether it is laid mirrored; null where the view has no cut.
  ({Rect cut, Rect laid, bool mirrored})? laidOver(
      String key, Rect box, double head, double ground) {
    var found = cutFor(key);
    if (found == null) return null;
    var (cut, mirrored, kept) = found;
    if (cut.height <= 0) return null;
    // Every figure on the sheet to the front's scale -- a back's skull,
    // under its hair, measures badly -- each stood on the ground by its
    // feet.
    var skull = (skulls[kept] ?? cut.top).clamp(cut.top, cut.bottom - 1);
    var tall = figureHeight ?? (cut.bottom - skull);
    var s = (ground - head) / (tall < 1 ? 1 : tall);
    var w = cut.width * s, h = cut.height * s;
    return (
      cut: cut,
      laid: Rect.fromLTWH(box.center.dx - w / 2, ground - h, w, h),
      mirrored: mirrored
    );
  }

  /// onBox is where point [q] of the sheet, in [cut], lies over the view
  /// laid as [laidOver] says.
  static Offset onBox(Offset q, ({Rect cut, Rect laid, bool mirrored}) at) {
    var s = at.laid.height / at.cut.height;
    var x = (q.dx - at.cut.left) * s;
    return Offset(at.mirrored ? at.laid.right - x : at.laid.left + x,
        at.laid.top + (q.dy - at.cut.top) * s);
  }

  Map<String, dynamic> toJson() => {
        "asset": assetId,
        if (cutout.isNotEmpty) "cutout": cutout,
        if (cuts.isNotEmpty)
          "cuts": {
            for (var MapEntry(:key, value: r) in cuts.entries)
              key: [r.left, r.top, r.width, r.height],
          },
        if (skulls.isNotEmpty) "skulls": skulls,
        if (heads > 0) "heads": heads,
        if (strength != 0.5) "strength": strength,
        if (!shown) "shown": false,
      };

  static CharacterReference? fromJson(Object? json) {
    if (json is! Map || json["asset"] is! String) return null;
    return CharacterReference(json["asset"] as String,
        cutout: json["cutout"] is String ? json["cutout"] as String : "",
        cuts: {
          if (json["cuts"] case Map raw)
            for (var MapEntry(:key, :value) in raw.entries)
              if (value case [num l, num t, num w, num h])
                "$key": Rect.fromLTWH(
                    l.toDouble(), t.toDouble(), w.toDouble(), h.toDouble()),
        },
        skulls: {
          if (json["skulls"] case Map raw)
            for (var MapEntry(:key, :value) in raw.entries)
              if (value is num) "$key": value.toDouble(),
        },
        heads: jsonDouble(json["heads"], 0),
        strength: jsonDouble(json["strength"], 0.5).clamp(0.0, 1.0),
        shown: json["shown"] != false);
  }

  @override
  bool operator ==(Object other) =>
      other is CharacterReference &&
      other.assetId == assetId &&
      other.cutout == cutout &&
      other.strength == strength &&
      other.heads == heads &&
      other.shown == shown &&
      other.cuts.length == cuts.length &&
      cuts.entries.every((e) => other.cuts[e.key] == e.value) &&
      other.skulls.length == skulls.length &&
      skulls.entries.every((e) => other.skulls[e.key] == e.value);

  @override
  int get hashCode => Object.hash(assetId, strength, shown, cuts.length);
}

/// Swatch is one of a character's colours, named: skin, hair, the T-shirt.
class Swatch {
  final String name;
  final Color color;
  const Swatch(this.name, this.color);

  Swatch copyWith({String? name, Color? color}) =>
      Swatch(name ?? this.name, color ?? this.color);

  Map<String, dynamic> toJson() => {"name": name, "color": colorToJson(color)};

  static Swatch? fromJson(Object? json) {
    if (json is! Map || json["name"] is! String) return null;
    return Swatch(json["name"] as String,
        colorFromJson(json["color"], const Color(0xFF808080)));
  }

  @override
  bool operator ==(Object other) =>
      other is Swatch && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(name, color);
}
