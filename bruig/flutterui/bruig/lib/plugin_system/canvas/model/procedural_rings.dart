import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// procedural_rings.dart is the Rings background's own settings, beyond the
// density/scale/variation every generator shares: where each ring starts,
// where it ends and what happens to it on the way.

/// RingEdge is what happens at the two ends of a ring's life.
enum RingEdge {
  /// hard is on and off: a ring appears at full strength and vanishes.
  hard("Hard"),

  /// soft rolls it in and out, so rings read as light rather than as drawn
  /// circles.
  soft("Soft");

  final String label;
  const RingEdge(this.label);

  static RingEdge fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => soft);
}

/// RingIconPlace is where an icon sits on the ring it belongs to.
enum RingIconPlace {
  /// middle puts one in the middle, sized against its ring, so it grows and
  /// fades with that ring.
  middle("In the middle"),

  /// around spaces several along the ring itself.
  around("Around the ring");

  final String label;
  const RingIconPlace(this.label);

  static RingIconPlace fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => middle);
}

/// RingDrift is a range each icon around a ring takes its own number from,
/// so the icons scatter rather than reading as one drawn shape. Nought to
/// nought (the default) is no scatter.
class RingDrift {
  /// least and most are the two ends of the range. Either may be negative,
  /// and they may be given either way round.
  final double least;
  final double most;

  const RingDrift({this.least = 0, this.most = 0});

  /// resting is whether the range is just [rest], the value that means no
  /// scatter: nought where the number is added, one where it multiplies.
  bool resting(double rest) => least == rest && most == rest;

  bool get none => resting(0);

  /// at is the number for one icon, given its own roll of nought to one.
  double at(double roll) => least + (most - least) * roll.clamp(0.0, 1.0);

  /// within is this range clamped to two limits, for numbers read back that
  /// must stay meaningful (a fade share of nought draws nothing).
  RingDrift within(double lowest, double highest) => RingDrift(
        least: least.clamp(lowest, highest),
        most: most.clamp(lowest, highest),
      );

  RingDrift copyWith({double? least, double? most}) =>
      RingDrift(least: least ?? this.least, most: most ?? this.most);

  List<double> toJson() => [least, most];

  factory RingDrift.fromJson(dynamic json, {double rest = 0}) =>
      json is List && json.length >= 2
          ? RingDrift(
              least: jsonDouble(json[0], rest),
              most: jsonDouble(json[1], rest),
            )
          : RingDrift(least: rest, most: rest);
}

/// RingPick is one more picture an icon may be drawn as, and how often.
///
/// Each place around the ring takes a picture at random by weight: two comes
/// up twice as often as one, and nought never.
class RingPick {
  final String asset;
  final double weight;

  const RingPick({this.asset = "", this.weight = 1});

  RingPick copyWith({String? asset, double? weight}) =>
      RingPick(asset: asset ?? this.asset, weight: weight ?? this.weight);

  Map<String, dynamic> toJson() => {
        "asset": asset,
        if (weight != 1) "weight": weight,
      };

  factory RingPick.fromJson(Map<String, dynamic> json) => RingPick(
        asset: jsonString(json["asset"], ""),
        weight: jsonDouble(json["weight"], 1).clamp(0, 100),
      );
}

/// RingIcon is a picture carried by one of the rings. It inherits the ring's
/// place, size and fade, so it arrives, swells and dissolves with it.
class RingIcon {
  /// asset is a picture in the canvas's own store: a drawing or a bitmap.
  final String asset;

  /// ring is which ring carries it, counted from one. Past the last ring it
  /// is not drawn.
  ///
  /// Nought ties it to the movement instead: it lives one run rather than one
  /// ring's life and is sized against the page, so with both fades held it
  /// simply stays while rings come and go.
  final int ring;

  final RingIconPlace place;

  /// count is how many are spaced around the ring, for
  /// [RingIconPlace.around].
  final int count;

  /// size is how big it is drawn, as a fraction of its ring's radius.
  final double size;

  /// tinted paints it in one colour, [tint], rather than its own.
  final bool tinted;
  final Color tint;

  /// turn is an extra rotation in degrees. Around the ring, each icon is
  /// already turned to face out of it.
  final double turn;

  /// The drift ranges say how far each icon around a ring may differ from
  /// the rest (see [RingDrift]).
  ///
  /// driftWhen is in ring lives, so an icon sits ahead of or behind its ring
  /// and arrives at its own moment. driftWhere is in gaps between icons (a
  /// half is halfway to the neighbour). driftSize is added to one. driftTurn
  /// is in degrees.
  ///
  /// driftFade is a share of the ring's strength (one is the ring's own), not
  /// an offset: an offset could not brighten a ring at full strength, and a
  /// share never lifts an icon above its ring, so a fade out still reaches
  /// nothing.
  final RingDrift driftWhen;
  final RingDrift driftWhere;
  final RingDrift driftSize;
  final RingDrift driftTurn;
  final RingDrift driftFade;

  /// also is more pictures this one may be drawn as (see [RingPick]);
  /// [weight] is how often [asset] itself comes up.
  final List<RingPick> also;
  final double weight;

  /// opacity, smallest and largest override what the icon inherits from its
  /// ring; null inherits.
  ///
  /// opacity replaces the ring's strength, so a picture can sit steadily
  /// behind rings that come and go. smallest and largest hold its size
  /// between two fractions of the page.
  final double? opacity;
  final double? smallest;
  final double? largest;

  /// holdIn and holdOut leave out the ring's arrival or departure: an icon
  /// there from the first frame, or one that stays once arrived.
  final bool holdIn;
  final bool holdOut;

  /// firstRunOnly draws it only during the first run of the movement, like
  /// a title card.
  final bool firstRunOnly;

  const RingIcon({
    this.asset = "",
    this.ring = 1,
    this.place = RingIconPlace.middle,
    this.count = 6,
    this.size = 0.5,
    this.tinted = false,
    this.tint = const Color(0xFFFFFFFF),
    this.turn = 0,
    this.driftWhen = const RingDrift(),
    this.driftWhere = const RingDrift(),
    this.driftSize = const RingDrift(),
    this.driftTurn = const RingDrift(),
    this.driftFade = const RingDrift(least: 1, most: 1),
    this.also = const [],
    this.weight = 1,
    this.opacity,
    this.smallest,
    this.largest,
    this.holdIn = false,
    this.holdOut = false,
    this.firstRunOnly = false,
  });

  RingIcon copyWith({
    String? asset,
    int? ring,
    RingIconPlace? place,
    int? count,
    double? size,
    bool? tinted,
    Color? tint,
    double? turn,
    RingDrift? driftWhen,
    RingDrift? driftWhere,
    RingDrift? driftSize,
    RingDrift? driftTurn,
    RingDrift? driftFade,
    List<RingPick>? also,
    double? weight,
    // The three nullable fields take a set flag: null is a real value here,
    // so it cannot also mean "not given".
    bool setOpacity = false,
    double? opacity,
    bool setSmallest = false,
    double? smallest,
    bool setLargest = false,
    double? largest,
    bool? holdIn,
    bool? holdOut,
    bool? firstRunOnly,
  }) =>
      RingIcon(
        asset: asset ?? this.asset,
        ring: ring ?? this.ring,
        place: place ?? this.place,
        count: count ?? this.count,
        size: size ?? this.size,
        tinted: tinted ?? this.tinted,
        tint: tint ?? this.tint,
        turn: turn ?? this.turn,
        driftWhen: driftWhen ?? this.driftWhen,
        driftWhere: driftWhere ?? this.driftWhere,
        driftSize: driftSize ?? this.driftSize,
        driftTurn: driftTurn ?? this.driftTurn,
        driftFade: driftFade ?? this.driftFade,
        also: also ?? this.also,
        weight: weight ?? this.weight,
        opacity: setOpacity ? opacity : this.opacity,
        smallest: setSmallest ? smallest : this.smallest,
        largest: setLargest ? largest : this.largest,
        holdIn: holdIn ?? this.holdIn,
        holdOut: holdOut ?? this.holdOut,
        firstRunOnly: firstRunOnly ?? this.firstRunOnly,
      );

  Map<String, dynamic> toJson() => {
        "asset": asset,
        "ring": ring,
        "place": place.name,
        "count": count,
        "size": size,
        if (tinted) "tinted": true,
        if (tinted) "tint": colorToJson(tint),
        if (turn != 0) "turn": turn,
        if (!driftWhen.none) "driftWhen": driftWhen.toJson(),
        if (!driftWhere.none) "driftWhere": driftWhere.toJson(),
        if (!driftSize.none) "driftSize": driftSize.toJson(),
        if (!driftTurn.none) "driftTurn": driftTurn.toJson(),
        // A key of its own: this setting was once an offset saved under
        // another key, and those numbers read as a share would hide the icon.
        if (!driftFade.resting(1)) "fadeShare": driftFade.toJson(),
        if (also.isNotEmpty) "also": [for (var pick in also) pick.toJson()],
        if (weight != 1) "weight": weight,
        if (opacity != null) "opacity": opacity,
        if (smallest != null) "smallest": smallest,
        if (largest != null) "largest": largest,
        if (holdIn) "holdIn": true,
        if (holdOut) "holdOut": true,
        if (firstRunOnly) "firstRunOnly": true,
      };

  factory RingIcon.fromJson(Map<String, dynamic> json) => RingIcon(
        asset: jsonString(json["asset"], ""),
        ring: jsonInt(json["ring"], 1).clamp(0, 200),
        place: RingIconPlace.fromName(jsonStr(json["place"])),
        count: jsonInt(json["count"], 6).clamp(1, 60),
        size: jsonDouble(json["size"], 0.5).clamp(0.01, 4),
        tinted: jsonBool(json["tinted"], false),
        tint: colorFromJson(json["tint"], const Color(0xFFFFFFFF)),
        turn: jsonDouble(json["turn"], 0),
        driftWhen: RingDrift.fromJson(json["driftWhen"]),
        driftWhere: RingDrift.fromJson(json["driftWhere"]),
        driftSize: RingDrift.fromJson(json["driftSize"]),
        driftTurn: RingDrift.fromJson(json["driftTurn"]),
        driftFade: RingDrift.fromJson(json["fadeShare"], rest: 1).within(0, 1),
        also: [
          for (var pick in (json["also"] as List?) ?? [])
            if (pick is Map<String, dynamic>) RingPick.fromJson(pick),
        ],
        weight: jsonDouble(json["weight"], 1).clamp(0, 100),
        opacity: json["opacity"] == null
            ? null
            : jsonDouble(json["opacity"], 1).clamp(0.0, 1.0),
        smallest: json["smallest"] == null
            ? null
            : jsonDouble(json["smallest"], 0).clamp(0.0, 4.0),
        largest: json["largest"] == null
            ? null
            : jsonDouble(json["largest"], 1).clamp(0.0, 4.0),
        holdIn: jsonBool(json["holdIn"], false),
        holdOut: jsonBool(json["holdOut"], false),
        firstRunOnly: jsonBool(json["firstRunOnly"], false),
      );
}

/// RingSpec is the Rings style's own settings.
class RingSpec {
  /// count is how many rings are on the page at once.
  final int count;

  /// width is how thick each one is, as a fraction of the shorter side.
  final double width;

  /// from and to are where a ring is born and dies, measured outwards:
  /// nought is the middle of the page and one the far corner, so a ring
  /// going to one leaves the picture entirely.
  final double from;
  final double to;

  /// centreX and centreY are where they come from, across and down the page.
  final double centreX;
  final double centreY;

  /// inward runs the whole thing backwards: rings shrink towards the middle
  /// rather than growing out of it.
  final bool inward;

  /// spacing bunches the rings towards their start (below a half) or towards
  /// their end (above it). A half spaces them evenly.
  final double spacing;

  /// spacingJitter, widthJitter and colorJitter are how much each ring is
  /// allowed to differ from the next: where it sits, how thick it is, and
  /// which of the two colours it leans towards.
  final double spacingJitter;
  final double widthJitter;
  final double colorJitter;

  /// accentEvery is how often a ring is drawn in the accent colour rather
  /// than the main one. Nought is never.
  final int accentEvery;

  /// buildUp starts the animation on an empty screen and lets the rings
  /// arrive one at a time, rather than opening on the full set. Read only
  /// when the background is animated: a still shows the set at work.
  final bool buildUp;

  /// fadeIn and fadeOut are the fractions of a ring's travel spent arriving
  /// and leaving; edge is whether that is a roll or a switch.
  ///
  /// About a third each by default, the least that reads as a fade: early in
  /// its travel a ring is only a few pixels across, so a shorter fade is
  /// over before the ring is big enough to see.
  final double fadeIn;
  final double fadeOut;
  final RingEdge edge;

  /// noise wobbles a ring's own outline, so it is drawn rather than struck.
  final double noise;

  /// glitch knocks slices of a ring sideways.
  final double glitch;

  /// distortion squashes the rings into ellipses and leans them over.
  final double distortion;

  /// grunge eats the stroke away: gaps, speckles, and a thinner line where
  /// the ink ran out.
  final double grunge;

  /// icons are the pictures the rings carry. See RingIcon.
  final List<RingIcon> icons;

  const RingSpec({
    this.count = 12,
    this.width = 0.004,
    this.from = 0.05,
    this.to = 1,
    this.centreX = 0.5,
    this.centreY = 0.5,
    this.inward = false,
    this.spacing = 0.5,
    this.spacingJitter = 0,
    this.widthJitter = 0,
    this.colorJitter = 0,
    this.accentEvery = 5,
    this.buildUp = true,
    this.fadeIn = 0.35,
    this.fadeOut = 0.35,
    this.edge = RingEdge.soft,
    this.noise = 0,
    this.glitch = 0,
    this.distortion = 0,
    this.grunge = 0,
    this.icons = const [],
  });

  RingSpec copyWith({
    int? count,
    double? width,
    double? from,
    double? to,
    double? centreX,
    double? centreY,
    bool? inward,
    double? spacing,
    double? spacingJitter,
    double? widthJitter,
    double? colorJitter,
    int? accentEvery,
    bool? buildUp,
    double? fadeIn,
    double? fadeOut,
    RingEdge? edge,
    double? noise,
    double? glitch,
    double? distortion,
    double? grunge,
    List<RingIcon>? icons,
  }) =>
      RingSpec(
        count: count ?? this.count,
        width: width ?? this.width,
        from: from ?? this.from,
        to: to ?? this.to,
        centreX: centreX ?? this.centreX,
        centreY: centreY ?? this.centreY,
        inward: inward ?? this.inward,
        spacing: spacing ?? this.spacing,
        spacingJitter: spacingJitter ?? this.spacingJitter,
        widthJitter: widthJitter ?? this.widthJitter,
        colorJitter: colorJitter ?? this.colorJitter,
        accentEvery: accentEvery ?? this.accentEvery,
        buildUp: buildUp ?? this.buildUp,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
        edge: edge ?? this.edge,
        noise: noise ?? this.noise,
        glitch: glitch ?? this.glitch,
        distortion: distortion ?? this.distortion,
        grunge: grunge ?? this.grunge,
        icons: icons ?? this.icons,
      );

  /// ageOf is how far through its life ring [index] is at [t], in lives;
  /// negative for a ring not yet born while the set builds up.
  ///
  /// Rings are spaced one life divided by [count] apart, so they arrive in
  /// order as a steady procession.
  double ageOf(int index, double t, {double jitter = 0}) {
    var many = count <= 0 ? 1 : count;
    return t - (index + jitter) / many;
  }

  /// spread is where ring [index] sits in its travel: nought at its birth and
  /// one where it dies, whatever life it is on.
  double spread(int index, double t, {double jitter = 0}) {
    var wrapped = ageOf(index, t, jitter: jitter) % 1;
    return wrapped < 0 ? wrapped + 1 : wrapped;
  }

  /// alphaAt is how strongly a ring shows at a point in its travel.
  ///
  /// [arriving] and [leaving] are false for an icon that holds one end: see
  /// [RingIcon.holdIn].
  double alphaAt(double through, {bool arriving = true, bool leaving = true}) {
    // The weaker of the two ends wins, so fades that overlap both apply.
    var came =
        arriving && fadeIn > 0 ? (through / fadeIn).clamp(0.0, 1.0) : 1.0;
    var goes = leaving && fadeOut > 0
        ? ((1 - through) / fadeOut).clamp(0.0, 1.0)
        : 1.0;
    var on = math.min(came, goes);
    if (edge == RingEdge.hard) return on <= 0 ? 0 : 1;
    // Smoothed at both ends, so a ring arrives and leaves rather than
    // switching on and then dimming at an even rate.
    return on * on * (3 - 2 * on);
  }

  Map<String, dynamic> toJson() => {
        "count": count,
        "width": width,
        "from": from,
        "to": to,
        "cx": centreX,
        "cy": centreY,
        if (inward) "inward": true,
        "spacing": spacing,
        if (spacingJitter != 0) "spacingJitter": spacingJitter,
        if (widthJitter != 0) "widthJitter": widthJitter,
        if (colorJitter != 0) "colorJitter": colorJitter,
        "accentEvery": accentEvery,
        if (!buildUp) "buildUp": false,
        "fadeIn": fadeIn,
        "fadeOut": fadeOut,
        "edge": edge.name,
        if (noise != 0) "noise": noise,
        if (glitch != 0) "glitch": glitch,
        if (distortion != 0) "distortion": distortion,
        if (grunge != 0) "grunge": grunge,
        if (icons.isNotEmpty) "icons": [for (var icon in icons) icon.toJson()],
      };

  factory RingSpec.fromJson(Map<String, dynamic> json) => RingSpec(
        count: jsonInt(json["count"], 12).clamp(1, 200),
        width: jsonDouble(json["width"], 0.004).clamp(0.0005, 0.2),
        from: jsonDouble(json["from"], 0.05).clamp(0.0, 2.0),
        to: jsonDouble(json["to"], 1).clamp(0.0, 2.0),
        centreX: jsonDouble(json["cx"], 0.5),
        centreY: jsonDouble(json["cy"], 0.5),
        inward: jsonBool(json["inward"], false),
        spacing: jsonDouble(json["spacing"], 0.5).clamp(0.05, 0.95),
        spacingJitter: jsonDouble(json["spacingJitter"], 0).clamp(0.0, 1.0),
        widthJitter: jsonDouble(json["widthJitter"], 0).clamp(0.0, 1.0),
        colorJitter: jsonDouble(json["colorJitter"], 0).clamp(0.0, 1.0),
        accentEvery: jsonInt(json["accentEvery"], 5).clamp(0, 50),
        buildUp: jsonBool(json["buildUp"], true),
        fadeIn: jsonDouble(json["fadeIn"], 0.35).clamp(0.0, 1.0),
        fadeOut: jsonDouble(json["fadeOut"], 0.35).clamp(0.0, 1.0),
        edge: RingEdge.fromName(jsonStr(json["edge"])),
        noise: jsonDouble(json["noise"], 0).clamp(0.0, 1.0),
        glitch: jsonDouble(json["glitch"], 0).clamp(0.0, 1.0),
        distortion: jsonDouble(json["distortion"], 0).clamp(0.0, 1.0),
        grunge: jsonDouble(json["grunge"], 0).clamp(0.0, 1.0),
        icons: [
          for (var one in (json["icons"] as List?) ?? const [])
            if (one is Map) RingIcon.fromJson(one.cast<String, dynamic>()),
        ],
      );
}
