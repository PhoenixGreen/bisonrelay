import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble, jsonStr;

// surround.dart is the speaker layouts, a channel's place among them, and
// pairwise constant-power panning (2D VBAP) between the two speakers either
// side of an angle.
//
// Angles are in degrees: nought ahead, positive to the right, 180 behind.
// Speakers stand where ITU-R BS.775 puts them. The editor plays surround
// folded down to stereo ([foldDown]); an export writes every speaker.

/// SpeakerLayout is the speakers a piece is mixed for.
enum SpeakerLayout {
  stereo("Stereo", "stereo", [
    ("L", -30),
    ("R", 30),
  ]),
  // ffmpeg's "5.1" order: FL FR FC LFE BL BR.
  surround51("5.1 surround", "5.1", [
    ("L", -30),
    ("R", 30),
    ("C", 0),
    ("LFE", null),
    ("Ls", -110),
    ("Rs", 110),
  ]),
  // ffmpeg's "7.1" order: FL FR FC LFE BL BR SL SR.
  surround71("7.1 surround", "7.1", [
    ("L", -30),
    ("R", 30),
    ("C", 0),
    ("LFE", null),
    ("Lb", -150),
    ("Rb", 150),
    ("Ls", -90),
    ("Rs", 90),
  ]);

  final String label;

  /// ffmpeg is the layout's name to ffmpeg.
  final String ffmpeg;

  /// speakers are each speaker in file order, with its angle (null for the
  /// LFE).
  final List<(String, int?)> speakers;
  const SpeakerLayout(this.label, this.ffmpeg, this.speakers);

  int get channels => speakers.length;
  bool get isSurround => this != stereo;

  /// lfe is the LFE's place among the channels, or null.
  int? get lfe {
    for (var (i, (_, a)) in speakers.indexed) {
      if (a == null) return i;
    }
    return null;
  }

  static SpeakerLayout fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => stereo);
}

/// SurroundPan is a channel's place among the speakers: the angle its
/// middle is heard from, and how wide its two sides are spread about it.
class SurroundPan {
  final double angle;

  /// width is how far apart its left and right are heard, in degrees: 60 is
  /// the front pair (stereo as mixed), nought a single point.
  final double width;

  const SurroundPan({this.angle = 0, this.width = 60});

  bool get isDefault => angle == 0 && width == 60;

  SurroundPan copyWith({double? angle, double? width}) => SurroundPan(
      angle: wrapAngle(angle ?? this.angle),
      width: (width ?? this.width).clamp(0.0, 180.0));

  Map<String, dynamic> toJson() => {"angle": angle, "width": width};

  factory SurroundPan.fromJson(Map<String, dynamic> json) => const SurroundPan()
      .copyWith(
          angle: jsonDouble(json["angle"], 0),
          width: jsonDouble(json["width"], 60));

  @override
  bool operator ==(Object other) =>
      other is SurroundPan && other.angle == angle && other.width == width;

  @override
  int get hashCode => Object.hash(angle, width);
}

/// wrapAngle is [degrees] brought into -180 to 180.
double wrapAngle(double degrees) {
  var a = (degrees + 180) % 360;
  if (a < 0) a += 360;
  return a - 180;
}

/// panGains are [layout]'s channel gains for a sound heard from [angle], the
/// two speakers either side sharing it with powers summing to one. In
/// stereo an angle behind is mirrored to the front, then held to the pair.
Float64List panGains(SpeakerLayout layout, double angle) {
  var out = Float64List(layout.channels);
  var a = wrapAngle(angle);
  var ring = <(int, double)>[
    for (var (i, (_, deg)) in layout.speakers.indexed)
      if (deg != null) (i, deg.toDouble()),
  ]..sort((x, y) => x.$2.compareTo(y.$2));
  if (layout == SpeakerLayout.stereo) {
    // Folded to the front: behind the listener is the same side, mirrored.
    if (a > 90) a = 180 - a;
    if (a < -90) a = -180 - a;
    a = a.clamp(-30.0, 30.0);
  }
  for (var k = 0; k < ring.length; k++) {
    var (i, from) = ring[k];
    var (j, to) = ring[(k + 1) % ring.length];
    var span = to - from;
    if (span <= 0) span += 360;
    var into = a - from;
    if (into < 0) into += 360;
    if (into > span + 1e-9) continue;
    var t = span == 0 ? 0.0 : into / span;
    out[i] = math.cos(t * math.pi / 2);
    out[j] = math.sin(t * math.pi / 2);
    return out;
  }
  return out;
}

/// foldDown is each of [layout]'s channels' (left, right) gains in the
/// ITU-R BS.775 stereo fold-down: centre and surrounds 3 dB down, no LFE.
List<(double, double)> foldDown(SpeakerLayout layout) {
  const half = 0.7071067811865476;
  return [
    for (var (_, deg) in layout.speakers)
      if (deg == null)
        (0.0, 0.0)
      else if (deg == 0)
        (half, half)
      else if (deg.abs() == 30)
        deg < 0 ? (1.0, 0.0) : (0.0, 1.0)
      else
        deg < 0 ? (half, 0.0) : (0.0, half),
  ];
}

/// loudnessWeights are BS.1770's channel weights for [layout]: 1.41 (+1.5
/// dB) for side and rear speakers, none for the LFE.
List<double> loudnessWeights(SpeakerLayout layout) => [
      for (var (_, deg) in layout.speakers)
        if (deg == null)
          0.0
        else if (deg.abs() > 60)
          1.41
        else
          1.0,
    ];

/// PlaceBy is what a sound's place is taken from.
enum PlaceBy {
  off("Not placed"),
  canvas("Where it is on the canvas"),
  stage("A spot on a stage"),
  follow("With another element");

  final String label;
  const PlaceBy(this.label);

  static PlaceBy fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => off);
}

/// SoundPlacement is where a sound is heard from, taken from the picture:
/// across the canvas, a spot on a 3D stage, or another element. When on it
/// replaces the channel's own pan. See render/sound_placement.dart.
class SoundPlacement {
  final PlaceBy by;

  /// arc is how wide the canvas is heard, in degrees, edge to edge: 60 is the
  /// front pair; more wraps round the listener in surround.
  final double arc;

  /// stage is the stage a spot is on; x and z the spot on its floor and y
  /// its height, in metres.
  final String stage;
  final double x, y, z;

  /// follow is the element followed.
  final String follow;

  /// near is how far from the camera, in metres, a stage sound keeps full
  /// level (nought: the stage's middle); rolloff how fast it falls beyond:
  /// one is the inverse-distance law (6 dB per doubling), nought none.
  final double near;
  final double rolloff;

  const SoundPlacement({
    this.by = PlaceBy.off,
    this.arc = 60,
    this.stage = "",
    this.x = 0,
    this.y = 1.2,
    this.z = 3,
    this.follow = "",
    this.near = 0,
    this.rolloff = 1,
  });

  bool get isOff => by == PlaceBy.off;

  SoundPlacement copyWith({
    PlaceBy? by,
    double? arc,
    String? stage,
    double? x,
    double? y,
    double? z,
    String? follow,
    double? near,
    double? rolloff,
  }) =>
      SoundPlacement(
        by: by ?? this.by,
        arc: (arc ?? this.arc).clamp(0.0, 360.0),
        stage: stage ?? this.stage,
        x: x ?? this.x,
        y: y ?? this.y,
        z: z ?? this.z,
        follow: follow ?? this.follow,
        near: (near ?? this.near).clamp(0.0, 100.0),
        rolloff: (rolloff ?? this.rolloff).clamp(0.0, 2.0),
      );

  Map<String, dynamic> toJson() => {
        "by": by.name,
        if (arc != 60) "arc": arc,
        if (stage.isNotEmpty) "stage": stage,
        if (x != 0) "x": x,
        if (y != 1.2) "y": y,
        if (z != 3) "z": z,
        if (follow.isNotEmpty) "follow": follow,
        if (near != 0) "near": near,
        if (rolloff != 1) "rolloff": rolloff,
      };

  factory SoundPlacement.fromJson(Map<String, dynamic> json) =>
      const SoundPlacement().copyWith(
        by: PlaceBy.fromName(jsonStr(json["by"])),
        arc: jsonDouble(json["arc"], 60),
        stage: json["stage"] is String ? json["stage"] as String : "",
        x: jsonDouble(json["x"], 0),
        y: jsonDouble(json["y"], 1.2),
        z: jsonDouble(json["z"], 3),
        follow: json["follow"] is String ? json["follow"] as String : "",
        near: jsonDouble(json["near"], 0),
        rolloff: jsonDouble(json["rolloff"], 1),
      );
}

/// Heard is a placed sound's angle and distance level at a moment.
class Heard {
  final double angle;
  final double gain;
  const Heard(this.angle, [this.gain = 1]);

  @override
  bool operator ==(Object other) =>
      other is Heard && other.angle == angle && other.gain == gain;

  @override
  int get hashCode => Object.hash(angle, gain);

  @override
  String toString() => "Heard($angle°, $gain)";
}

/// distanceGain is the level of a sound [distance] metres away, full up to
/// [near] and falling away by [rolloff] beyond.
double distanceGain(double distance, double near, double rolloff) {
  if (rolloff <= 0 || distance <= near) return 1;
  return math.pow(near / distance, rolloff).toDouble();
}
