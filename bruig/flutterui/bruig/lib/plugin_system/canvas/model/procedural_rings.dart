import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// procedural_rings.dart is everything the Rings background can be told.
//
// Its own settings rather than the handful every generator shares. Rings were
// drawn from density, scale and variation like the rest, which meant the only
// thing anybody could say about them was "more" or "bigger" -- and the one
// question a set of rings actually raises, which is where each ring starts,
// where it ends and what happens to it on the way, could not be asked at all.

/// RingEdge is what happens at the two ends of a ring's life.
enum RingEdge {
  /// hard is on and off: a ring appears at full strength and vanishes.
  hard("Hard"),

  /// soft rolls it in and out, which is what makes rings read as light
  /// rather than as a set of drawn circles.
  soft("Soft");

  final String label;
  const RingEdge(this.label);

  static RingEdge fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => soft);
}

/// RingIconPlace is where an icon sits on the ring it belongs to.
enum RingIconPlace {
  /// middle puts one in the middle of the rings, sized against the ring it
  /// is tied to -- so it grows and fades with that ring.
  middle("In the middle"),

  /// around spaces several of them along the ring itself, like beads on it.
  around("Around the ring");

  final String label;
  const RingIconPlace(this.label);

  static RingIconPlace fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => middle);
}

/// RingIcon is a picture carried by one of the rings.
///
/// It inherits the ring: where it is, how big it has grown, and how far
/// through its fade it is. That is the whole point of tying it to a ring
/// rather than placing it on the canvas -- an icon that arrives, swells and
/// dissolves with the ring around it belongs to the picture, and one that
/// merely sits on top of it does not.
class RingIcon {
  /// asset is a picture in the canvas's own store: a drawing or a bitmap.
  final String asset;

  /// ring is which of them carries it, counted the way people count -- one
  /// is the first ring. Beyond the last, it is carried by no ring and drawn
  /// by nothing.
  final int ring;

  final RingIconPlace place;

  /// count is how many are spaced around the ring, for the placing that goes
  /// around it.
  final int count;

  /// size is how big it is drawn, as a fraction of its ring's radius. So it
  /// grows with the ring, which is what "scales with it" means.
  final double size;

  /// tinted paints it in one colour rather than its own, which is what a
  /// line drawing usually wants; tint is that colour.
  final bool tinted;
  final Color tint;

  /// turn is an extra rotation in degrees. Around the ring, each icon is
  /// already turned to face out of it.
  final double turn;

  const RingIcon({
    this.asset = "",
    this.ring = 1,
    this.place = RingIconPlace.middle,
    this.count = 6,
    this.size = 0.5,
    this.tinted = false,
    this.tint = const Color(0xFFFFFFFF),
    this.turn = 0,
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
      };

  factory RingIcon.fromJson(Map<String, dynamic> json) => RingIcon(
        asset: jsonString(json["asset"], ""),
        ring: jsonInt(json["ring"], 1).clamp(1, 200),
        place: RingIconPlace.fromName(json["place"] as String?),
        count: jsonInt(json["count"], 6).clamp(1, 60),
        size: jsonDouble(json["size"], 0.5).clamp(0.01, 4),
        tinted: jsonBool(json["tinted"], false),
        tint: colorFromJson(json["tint"], const Color(0xFFFFFFFF)),
        turn: jsonDouble(json["turn"], 0),
      );
}

/// RingSpec is the Rings style's own settings.
class RingSpec {
  /// count is how many rings are on the page at once.
  final int count;

  /// width is how thick each one is, as a fraction of the shorter side.
  final double width;

  /// from and to are where a ring is born and where it dies, measured from
  /// the middle outwards: nought is the middle of the page and one is the
  /// far corner, so a ring going to one has left the picture entirely.
  ///
  /// The pair is what makes the setting mean anything: rings that expand a
  /// little and start again read as a stutter, and the way to say "out of
  /// the frame" is to be able to say where the frame ends.
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

  /// buildUp starts the animation with an empty screen and lets the rings
  /// arrive one at a time, rather than opening on a set that is already
  /// there.
  ///
  /// Which is what "fade in" meant and did not do. Every ring fades in as it
  /// is born -- that was always true -- but at the first frame the whole set
  /// was spread across its life already, so what anybody saw when the canvas
  /// started, and again every time it looped, was nine rings simply being
  /// there. Read only when the background is animated: a still has one
  /// moment, and the moment to show is the set at work rather than an empty
  /// page.
  final bool buildUp;

  /// fadeIn and fadeOut are how much of a ring's travel is spent arriving
  /// and leaving, as fractions of it. edge is whether that happens as a roll
  /// or as a switch.
  ///
  /// A third of the travel each by default, which sounds like a lot and is
  /// the least that reads as a fade. A ring spends the start of its life
  /// small and near the middle, where a few per cent of its travel is a few
  /// pixels of radius: over a tenth of the travel, as it was, a ring was
  /// already at three quarters of its strength by the time it was big enough
  /// to notice, and what anybody saw was a ring appearing.
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

  /// ageOf is how far through its life ring [index] is at [t], in lives --
  /// negative for a ring that has not been born yet, which happens only while
  /// the set is still building up at the start.
  ///
  /// The rings are one life apart divided between them, so they arrive in
  /// order and the picture is a steady procession rather than the whole set
  /// jumping back to the start. The first one shifted every ring by up to one
  /// gap and wrapped, which is what "they expand a little and reset" was.
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
  double alphaAt(double through) {
    // Both ends, and the weaker of the two wins.
    //
    // Written as two ifs, the second one overruled the first: a ring set to
    // fade in over the whole of its life *and* out over the whole of its
    // life was drawn at one minus its age, which is full strength at birth
    // and nothing at death -- no fade in at all. Turning the fade in up to
    // one was the surest way to switch it off, which is what "fade in does
    // not work" was.
    var arriving = fadeIn > 0 ? (through / fadeIn).clamp(0.0, 1.0) : 1.0;
    var leaving = fadeOut > 0 ? ((1 - through) / fadeOut).clamp(0.0, 1.0) : 1.0;
    var on = math.min(arriving, leaving);
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
        edge: RingEdge.fromName(json["edge"] as String?),
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
