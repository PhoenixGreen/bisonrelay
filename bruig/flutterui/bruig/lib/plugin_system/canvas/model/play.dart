import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble;

// play.dart is a canvas played as a game: what each element does when it is
// -- walks and jumps, walks every way, moves the view, or is something to
// stand on -- and the controls that drive it, each an action pressed by keys
// and controller buttons, as Godot's input map has them.
//
// Distances are the canvas's own units, times are seconds.

/// PlayAs is what an element does when the canvas is played.
enum PlayAs {
  none("Not played"),
  platformer("Platformer"),
  topDown("Top-down"),
  camera("Camera"),
  solid("Something solid");

  final String label;
  const PlayAs(this.label);

  bool get moves => this == platformer || this == topDown || this == camera;

  static PlayAs fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => none);
}

/// PlaySpec is how an element is played.
class PlaySpec {
  final PlayAs as;

  /// speed is how fast it goes, in canvas units a second; jump how high a
  /// platformer jumps, and gravity how fast it falls.
  final double speed;
  final double jump;
  final double gravity;

  /// follow is whether the view follows it.
  final bool follow;

  const PlaySpec({
    this.as = PlayAs.none,
    this.speed = 320,
    this.jump = 180,
    this.gravity = 2200,
    this.follow = true,
  });

  bool get isNone => as == PlayAs.none;

  PlaySpec copyWith(
          {PlayAs? as,
          double? speed,
          double? jump,
          double? gravity,
          bool? follow}) =>
      PlaySpec(
        as: as ?? this.as,
        speed: (speed ?? this.speed).clamp(10.0, 5000.0),
        jump: (jump ?? this.jump).clamp(0.0, 5000.0),
        gravity: (gravity ?? this.gravity).clamp(0.0, 20000.0),
        follow: follow ?? this.follow,
      );

  Map<String, dynamic> toJson() => {
        "as": as.name,
        if (speed != 320) "speed": speed,
        if (jump != 180) "jump": jump,
        if (gravity != 2200) "gravity": gravity,
        if (!follow) "follow": false,
      };

  factory PlaySpec.fromJson(Object? json) {
    if (json is! Map) return const PlaySpec();
    return const PlaySpec().copyWith(
      as: PlayAs.fromName(json["as"] as String?),
      speed: jsonDouble(json["speed"], 320),
      jump: jsonDouble(json["jump"], 180),
      gravity: jsonDouble(json["gravity"], 2200),
      follow: json["follow"] != false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaySpec &&
      other.as == as &&
      other.speed == speed &&
      other.jump == jump &&
      other.gravity == gravity &&
      other.follow == follow;

  @override
  int get hashCode => Object.hash(as, speed, jump, gravity, follow);
}

/// PadInput is a controller's button, or one way of one of its sticks.
enum PadInput {
  a("A"),
  b("B"),
  x("X"),
  y("Y"),
  leftBumper("LB"),
  rightBumper("RB"),
  leftTrigger("LT"),
  rightTrigger("RT"),
  back("Back"),
  start("Start"),
  dpadUp("D-pad ▲"),
  dpadDown("D-pad ▼"),
  dpadLeft("D-pad ◀"),
  dpadRight("D-pad ▶"),
  leftStickLeft("Left stick ◀"),
  leftStickRight("Left stick ▶"),
  leftStickUp("Left stick ▲"),
  leftStickDown("Left stick ▼"),
  rightStickLeft("Right stick ◀"),
  rightStickRight("Right stick ▶"),
  rightStickUp("Right stick ▲"),
  rightStickDown("Right stick ▼");

  final String label;
  const PadInput(this.label);

  static PadInput? fromName(String? name) =>
      values.where((p) => p.name == name).firstOrNull;
}

/// ControlAction is something a player does -- move left, jump -- and what
/// presses it: keys, by their key ids (see LogicalKeyboardKey.keyId), and
/// controller inputs.
class ControlAction {
  final String id;
  final String name;
  final List<int> keys;
  final List<PadInput> pad;

  const ControlAction(this.id, this.name,
      {this.keys = const [], this.pad = const []});

  ControlAction copyWith(
          {String? name, List<int>? keys, List<PadInput>? pad}) =>
      ControlAction(id, name ?? this.name,
          keys: keys ?? this.keys, pad: pad ?? this.pad);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "keys": keys,
        "pad": [for (var p in pad) p.name],
      };

  static ControlAction? fromJson(Object? json) {
    if (json is! Map || json["id"] is! String) return null;
    return ControlAction(json["id"] as String,
        json["name"] is String ? json["name"] as String : json["id"] as String,
        keys: [
          if (json["keys"] case List list)
            for (var k in list)
              if (k is int) k,
        ],
        pad: [
          if (json["pad"] case List list)
            for (var p in list)
              if (PadInput.fromName(p as String?) case var input?) input,
        ]);
  }
}

// The keys, by LogicalKeyboardKey id, the defaults are pressed by.
const int _left = 0x100000302, _right = 0x100000303;
const int _up = 0x100000304, _down = 0x100000301;
const int _space = 0x20;
int _letter(String c) => c.codeUnitAt(0);

/// defaultControls are a game's usual six: move four ways, jump, act -- on
/// the arrows and WASD, and the controller's left stick, d-pad, A and X.
final List<ControlAction> defaultControls = [
  ControlAction("left", "Move left",
      keys: [_left, _letter("a")],
      pad: const [PadInput.leftStickLeft, PadInput.dpadLeft]),
  ControlAction("right", "Move right",
      keys: [_right, _letter("d")],
      pad: const [PadInput.leftStickRight, PadInput.dpadRight]),
  ControlAction("up", "Up",
      keys: [_up, _letter("w")],
      pad: const [PadInput.leftStickUp, PadInput.dpadUp]),
  ControlAction("down", "Down",
      keys: [_down, _letter("s")],
      pad: const [PadInput.leftStickDown, PadInput.dpadDown]),
  const ControlAction("jump", "Jump", keys: [_space], pad: [PadInput.a]),
  ControlAction("act", "Action", keys: [_letter("e")], pad: const [PadInput.x]),
];
