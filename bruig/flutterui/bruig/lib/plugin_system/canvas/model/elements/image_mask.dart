import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// image_mask.dart is what of a picture is shown: a mask, which every picture
// -- the element's own, and every picture layer -- has one of.
//
// Kept apart from BackgroundRemoval, which goes on doing what it was good at
// (a logo's flat colour keyed out, a scan's paper taken away) and is applied
// first. The mask is the photograph's tool, and is built the way an image
// editor builds one: a subject found in the picture, then painted, lassoed
// and faded by hand, with its edge refined last.
//
// It is a recipe, like everything else in a canvas, with one exception. The
// subject a picture was found to have is a picture of its own -- a grey mask
// kept in the picture store beside the picture -- because finding it is the
// work of a model that a later version of the operating system might do
// differently, and a cut-out must not change under a document that was
// finished last year. Everything after it is marks, kept as marks.

/// MaskMarkKind is what one mark on a mask is.
enum MaskMarkKind {
  /// brush is a painted stroke: soft or hard, light or heavy, wide or thin
  /// as the pen was pressed.
  brush,

  /// lasso is a shape drawn round something, filled.
  lasso,

  /// fade is a gradient: the picture fading out across a line or away from
  /// a middle.
  fade;

  static MaskMarkKind fromName(String? name) => values
      .firstWhere((k) => k.name == name, orElse: () => MaskMarkKind.brush);
}

/// MaskMark is one mark made on a mask, in the order it was made.
///
/// Points are fractions of the picture's own width and height, so a mark
/// stays on the shoulder it was made on however the picture is resized,
/// cropped or reframed -- as the old removal brush's strokes did.
class MaskMark {
  final MaskMarkKind kind;

  /// hide is true for a mark that takes the picture away and false for one
  /// that puts it back.
  final bool hide;

  /// points are a brush's path, a lasso's outline, or a fade's two ends --
  /// for a radial fade, its middle and a point on its rim.
  final List<Offset> points;

  /// pressure is how hard the pen pressed at each of a brush's points, 0 to
  /// 1. Empty for a mouse, which presses as hard at every point.
  final List<double> pressure;

  /// radius is a brush's, as a fraction of the picture's shorter side.
  final double radius;

  /// hardness is how abruptly a brush stops at its own rim: 1 a cut edge,
  /// lower a fade towards it.
  final double hardness;

  /// strength is how much a mark does at most: a brush's or a fade's
  /// opacity, 1 for all the way.
  final double strength;

  /// radial makes a fade spread from a middle rather than across a line.
  final bool radial;

  const MaskMark({
    required this.kind,
    required this.points,
    this.hide = true,
    this.pressure = const [],
    this.radius = 0.03,
    this.hardness = 0.6,
    this.strength = 1,
    this.radial = false,
  });

  MaskMark copyWith(
          {List<Offset>? points, List<double>? pressure, double? radius}) =>
      MaskMark(
        kind: kind,
        points: points ?? this.points,
        hide: hide,
        pressure: pressure ?? this.pressure,
        radius: radius ?? this.radius,
        hardness: hardness,
        strength: strength,
        radial: radial,
      );

  Map<String, dynamic> toJson() => {
        "k": kind.name,
        // Flat pairs, rounded: a stroke is hundreds of points, and five
        // places of a fraction is finer than any picture's pixels.
        "p": [
          for (var p in points) ...[_round(p.dx), _round(p.dy)]
        ],
        if (!hide) "show": true,
        if (pressure.isNotEmpty) "pr": [for (var v in pressure) _round(v)],
        if (kind == MaskMarkKind.brush) "r": radius,
        if (kind == MaskMarkKind.brush) "h": hardness,
        if (strength != 1) "s": strength,
        if (radial) "radial": true,
      };

  static double _round(double v) => (v * 100000).round() / 100000;

  factory MaskMark.fromJson(Map<String, dynamic> json) {
    var flat = json["p"];
    var points = <Offset>[];
    if (flat is List) {
      for (var i = 0; i + 1 < flat.length; i += 2) {
        var x = flat[i], y = flat[i + 1];
        if (x is num && y is num) {
          points.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    return MaskMark(
      kind: MaskMarkKind.fromName(json["k"] as String?),
      points: points,
      hide: !jsonBool(json["show"], false),
      pressure: [
        if (json["pr"] case List raw)
          for (var v in raw)
            if (v is num) v.toDouble().clamp(0.0, 1.0)
      ],
      radius: jsonDouble(json["r"], 0.03).clamp(0.0005, 1.0),
      hardness: jsonDouble(json["h"], 0.6).clamp(0.0, 1.0),
      strength: jsonDouble(json["s"], 1).clamp(0.0, 1.0),
      radial: jsonBool(json["radial"], false),
    );
  }
}

/// MaskRefine is what is done to the mask's edge, last, in the picture's own
/// pixels -- the units every editor gives these in, and the ones that mean
/// the same thing at every size the picture is drawn.
class MaskRefine {
  /// shift moves the edge out (above nought) or in (below), to take a halo
  /// off or give back a rim that was cut too close.
  final double shift;

  /// smooth rounds off a jagged edge without softening it.
  final double smooth;

  /// feather softens the edge.
  final double feather;

  /// contrast hardens a soft edge, 0 to 1.
  final double contrast;

  /// decontaminate takes the background's colour out of the edge -- the
  /// green fringe on a player cut off a pitch -- 0 to 1.
  final double decontaminate;

  const MaskRefine({
    this.shift = 0,
    this.smooth = 0,
    this.feather = 0,
    this.contrast = 0,
    this.decontaminate = 0,
  });

  bool get any =>
      shift != 0 ||
      smooth > 0 ||
      feather > 0 ||
      contrast > 0 ||
      decontaminate > 0;

  MaskRefine copyWith({
    double? shift,
    double? smooth,
    double? feather,
    double? contrast,
    double? decontaminate,
  }) =>
      MaskRefine(
        shift: (shift ?? this.shift).clamp(-100.0, 100.0),
        smooth: (smooth ?? this.smooth).clamp(0.0, 100.0),
        feather: (feather ?? this.feather).clamp(0.0, 200.0),
        contrast: (contrast ?? this.contrast).clamp(0.0, 1.0),
        decontaminate: (decontaminate ?? this.decontaminate).clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() => {
        if (shift != 0) "shift": shift,
        if (smooth > 0) "smooth": smooth,
        if (feather > 0) "feather": feather,
        if (contrast > 0) "contrast": contrast,
        if (decontaminate > 0) "decon": decontaminate,
      };

  factory MaskRefine.fromJson(Map<String, dynamic> json) =>
      const MaskRefine().copyWith(
        shift: jsonDouble(json["shift"], 0),
        smooth: jsonDouble(json["smooth"], 0),
        feather: jsonDouble(json["feather"], 0),
        contrast: jsonDouble(json["contrast"], 0),
        decontaminate: jsonDouble(json["decon"], 0),
      );
}

/// ImageMask is a picture's mask. See the top of this file.
class ImageMask {
  /// subject is the picture-store id of the grey mask a subject was found to
  /// have -- white what is kept -- or empty to start from the whole picture.
  final String subject;

  /// marks are made over the subject, in order.
  final List<MaskMark> marks;

  final MaskRefine refine;

  /// invert shows what the mask hides and hides what it shows: the sky
  /// rather than the player.
  final bool invert;

  /// on is false to see the picture whole without losing the mask.
  final bool on;

  const ImageMask({
    this.subject = "",
    this.marks = const [],
    this.refine = const MaskRefine(),
    this.invert = false,
    this.on = true,
  });

  /// empty is whether there is a mask at all.
  bool get empty => subject.isEmpty && marks.isEmpty && !invert && !refine.any;

  /// active is whether it changes what is drawn.
  bool get active => on && !empty;

  ImageMask copyWith({
    String? subject,
    List<MaskMark>? marks,
    MaskRefine? refine,
    bool? invert,
    bool? on,
  }) =>
      ImageMask(
        subject: subject ?? this.subject,
        marks: marks ?? this.marks,
        refine: refine ?? this.refine,
        invert: invert ?? this.invert,
        on: on ?? this.on,
      );

  /// withMark is this mask with [mark] made last.
  ImageMask withMark(MaskMark mark) => copyWith(marks: [...marks, mark]);

  /// withLastMark is this mask with its last mark replaced by [mark] -- a
  /// stroke growing as it is drawn.
  ImageMask withLastMark(MaskMark mark) => marks.isEmpty
      ? withMark(mark)
      : copyWith(marks: [...marks.sublist(0, marks.length - 1), mark]);

  Map<String, dynamic> toJson() => {
        if (subject.isNotEmpty) "subject": subject,
        if (marks.isNotEmpty) "marks": [for (var m in marks) m.toJson()],
        if (refine.any) "refine": refine.toJson(),
        if (invert) "invert": true,
        if (!on) "off": true,
      };

  factory ImageMask.fromJson(Map<String, dynamic> json) => ImageMask(
        subject: jsonString(json["subject"], ""),
        marks: [
          if (json["marks"] case List raw)
            for (var m in raw)
              if (m is Map<String, dynamic>) MaskMark.fromJson(m)
        ],
        refine:
            jsonSpec(json["refine"], MaskRefine.fromJson, const MaskRefine()),
        invert: jsonBool(json["invert"], false),
        on: !jsonBool(json["off"], false),
      );
}
