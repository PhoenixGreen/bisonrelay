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

/// RingDrift is a range one icon's own number is taken from.
///
/// Icons spaced around a ring are otherwise identical beads on a wire: same
/// size, same moment, same distance from the middle, and the eye reads the
/// whole set as one drawn shape rather than as things sitting on a ring.
/// Each of these says how far one of them is allowed to differ, and every
/// icon takes its own place in the range -- so they scatter rather than all
/// moving together.
///
/// Nought to nought is no scatter at all, which is why both ends default to
/// it: a setting nobody has touched changes nothing.
class RingDrift {
  /// least and most are the two ends of the range. Either may be negative,
  /// and they may be given the other way round -- the pair is a range, not
  /// an order.
  final double least;
  final double most;

  const RingDrift({this.least = 0, this.most = 0});

  /// rest is the value that means no scatter at all: nought where the number
  /// is added to something, one where it multiplies it.
  bool resting(double rest) => least == rest && most == rest;

  bool get none => resting(0);

  /// at is the number for one icon, given its own roll of nought to one.
  double at(double roll) => least + (most - least) * roll.clamp(0.0, 1.0);

  /// within is this range held inside two limits, for reading a number back
  /// that has to mean something: a share of nothing to nothing is a picture
  /// nobody can see and no way of finding out why.
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
/// Several pictures spaced around a ring are usually not meant to be the
/// same picture: a crest, a ball and a boot around a circle read as a set,
/// and six of one read as a pattern. Each place around the ring takes one of
/// these at random, and weight is how often it is taken -- a picture at two
/// comes up twice as often as one at one, and one at nought never.
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
  ///
  /// Nought is on no ring on purpose: the picture is tied to the movement
  /// instead. It lives the length of one run rather than of a ring and is
  /// sized against the page rather than a radius, which -- with both of its
  /// fades held -- is a picture that is simply there while rings come and go.
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

  /// How far each icon around a ring is allowed to differ from the rest.
  /// See RingDrift: every icon takes its own place in each range.
  ///
  /// driftWhen is measured in the ring's life, so an icon moved through it
  /// sits off the line -- ahead of the ring or behind it -- and arrives and
  /// leaves at its own moment. driftWhere is measured in the gap between one
  /// icon and the next, so a half is halfway to its neighbour. driftSize is
  /// added to one: a half is half as big again. driftTurn is in degrees.
  ///
  /// driftFade is a share of the strength the ring is drawn at rather than
  /// something added to it: one is the ring's own, and a half is half of it.
  /// A share rather than an offset because the other way round has a dead
  /// half -- a ring at full strength cannot be made brighter, so every
  /// positive number did nothing at all. It never lifts an icon above its
  /// ring either, which is what keeps a fade out going all the way to
  /// nothing.
  final RingDrift driftWhen;
  final RingDrift driftWhere;
  final RingDrift driftSize;
  final RingDrift driftTurn;
  final RingDrift driftFade;

  /// also is more pictures this one may be drawn as, each with how often it
  /// comes up. See RingPick. [weight] is how often [asset] itself does.
  final List<RingPick> also;
  final double weight;

  /// The four things an icon may be told rather than inheriting from its
  /// ring. Null is inherit, which is what every one of them is until it is
  /// switched on.
  ///
  /// opacity is drawn instead of the ring's own strength -- so a picture can
  /// sit steadily behind rings that come and go. smallest and largest hold
  /// its size between two fractions of the page: an icon grows with its ring
  /// and otherwise grows out of the picture with it.
  final double? opacity;
  final double? smallest;
  final double? largest;

  /// holdIn and holdOut leave out the ring's arrival or its departure: a
  /// badge in the middle that is there from the first frame, or one that
  /// stays once it has arrived.
  final bool holdIn;
  final bool holdOut;

  /// firstRunOnly draws it during the first run of the movement and not the
  /// ones after it, which is how a title card behaves: said once.
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
    // The four that may be unset take an "or leave it alone" of their own:
    // null is a real value here, so null cannot also mean "not given".
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
        // Under its own name, because it used to be something else. It was
        // an offset added to one, and the same pair of numbers read as a
        // share is a different setting entirely -- "a fifth less" becomes
        // "a fifth of nothing", which is a picture that never appears again
        // whatever else is done to it.
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
        place: RingIconPlace.fromName(json["place"] as String?),
        count: jsonInt(json["count"], 6).clamp(1, 60),
        size: jsonDouble(json["size"], 0.5).clamp(0.01, 4),
        tinted: jsonBool(json["tinted"], false),
        tint: colorFromJson(json["tint"], const Color(0xFFFFFFFF)),
        turn: jsonDouble(json["turn"], 0),
        driftWhen: RingDrift.fromJson(json["driftWhen"]),
        driftWhere: RingDrift.fromJson(json["driftWhere"]),
        driftSize: RingDrift.fromJson(json["driftSize"]),
        driftTurn: RingDrift.fromJson(json["driftTurn"]),
        driftFade:
            RingDrift.fromJson(json["fadeShare"], rest: 1).within(0, 1),
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
  ///
  /// [arriving] and [leaving] are there for a picture a ring carries that has
  /// been told to keep one of the two ends: see RingIcon.holdIn.
  double alphaAt(double through,
      {bool arriving = true, bool leaving = true}) {
    // Both ends, and the weaker of the two wins.
    //
    // Written as two ifs, the second one overruled the first: a ring set to
    // fade in over the whole of its life *and* out over the whole of its
    // life was drawn at one minus its age, which is full strength at birth
    // and nothing at death -- no fade in at all. Turning the fade in up to
    // one was the surest way to switch it off, which is what "fade in does
    // not work" was.
    var came = arriving && fadeIn > 0 ? (through / fadeIn).clamp(0.0, 1.0) : 1.0;
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
