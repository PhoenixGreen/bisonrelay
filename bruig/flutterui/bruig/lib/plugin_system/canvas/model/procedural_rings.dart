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

  /// fadeIn and fadeOut are how much of a ring's travel is spent arriving
  /// and leaving, as fractions of it. edge is whether that happens as a roll
  /// or as a switch.
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
    this.fadeIn = 0.12,
    this.fadeOut = 0.25,
    this.edge = RingEdge.soft,
    this.noise = 0,
    this.glitch = 0,
    this.distortion = 0,
    this.grunge = 0,
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
    double? fadeIn,
    double? fadeOut,
    RingEdge? edge,
    double? noise,
    double? glitch,
    double? distortion,
    double? grunge,
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
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
        edge: edge ?? this.edge,
        noise: noise ?? this.noise,
        glitch: glitch ?? this.glitch,
        distortion: distortion ?? this.distortion,
        grunge: grunge ?? this.grunge,
      );

  /// spread is where ring [index] of [count] sits in its travel at [t], from
  /// nought at its birth to one where it dies.
  ///
  /// The rings are evenly spread through one life and all of them move
  /// together, so what is seen is a steady procession rather than the whole
  /// set jumping back to the start. The old one shifted every ring by up to
  /// one gap and wrapped, which is what "they expand a little and reset"
  /// was.
  double spread(int index, double t, {double jitter = 0}) {
    var many = count <= 0 ? 1 : count;
    var at = (index + jitter) / many + t;
    var wrapped = at % 1;
    return wrapped < 0 ? wrapped + 1 : wrapped;
  }

  /// alphaAt is how strongly a ring shows at a point in its travel.
  double alphaAt(double through) {
    var on = 1.0;
    if (fadeIn > 0 && through < fadeIn) on = through / fadeIn;
    if (fadeOut > 0 && through > 1 - fadeOut) on = (1 - through) / fadeOut;
    on = on.clamp(0.0, 1.0);
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
        "fadeIn": fadeIn,
        "fadeOut": fadeOut,
        "edge": edge.name,
        if (noise != 0) "noise": noise,
        if (glitch != 0) "glitch": glitch,
        if (distortion != 0) "distortion": distortion,
        if (grunge != 0) "grunge": grunge,
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
        fadeIn: jsonDouble(json["fadeIn"], 0.12).clamp(0.0, 1.0),
        fadeOut: jsonDouble(json["fadeOut"], 0.25).clamp(0.0, 1.0),
        edge: RingEdge.fromName(json["edge"] as String?),
        noise: jsonDouble(json["noise"], 0).clamp(0.0, 1.0),
        glitch: jsonDouble(json["glitch"], 0).clamp(0.0, 1.0),
        distortion: jsonDouble(json["distortion"], 0).clamp(0.0, 1.0),
        grunge: jsonDouble(json["grunge"], 0).clamp(0.0, 1.0),
      );
}
