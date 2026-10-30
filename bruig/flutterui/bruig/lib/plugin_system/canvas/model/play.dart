import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble;
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';

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
  solid("Something solid"),

  /// pickup is taken by a player touching it -- a coin, a key, a heart --
  /// and hazard hurts one -- spikes, water. Each does its [PlaySpec.touched].
  pickup("Pickup"),
  hazard("Hazard");

  final String label;
  const PlayAs(this.label);

  bool get moves => this == platformer || this == topDown || this == camera;

  /// touched is whether a player touching it does something.
  bool get touched => this == pickup || this == hazard;

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

  /// player is which player drives it, one to four: each has controls of
  /// its own. See CanvasDocument.controlsFor.
  final int player;

  /// touched is what a pickup or a hazard does when a player touches it;
  /// sound the sound element played as it does, by id, if any; stays
  /// whether a pickup is still there after -- else it goes until the game
  /// starts again; and sendsBack whether a hazard puts the player back
  /// where it started.
  final GameEffect touched;
  final String sound;
  final bool stays;
  final bool sendsBack;

  /// pressedBy is the action that presses it, by id -- "" none -- from
  /// anywhere, or with [reach] set, only with a player within that many
  /// canvas units of it; and press what that does, as a button's press
  /// does. A Button pressed does its own.
  final String pressedBy;
  final double reach;
  final ButtonAction press;

  const PlaySpec({
    this.as = PlayAs.none,
    this.speed = 320,
    this.jump = 180,
    this.gravity = 2200,
    this.follow = true,
    this.player = 1,
    this.touched = const GameEffect(),
    this.sound = "",
    this.stays = false,
    this.sendsBack = true,
    this.pressedBy = "",
    this.reach = 0,
    this.press = const ButtonAction(kind: ButtonActionKind.toggleElement),
  });

  /// isNone is whether it does nothing in a game: not played, and pressed
  /// by nothing.
  bool get isNone => as == PlayAs.none && pressedBy.isEmpty;

  PlaySpec copyWith(
          {PlayAs? as,
          double? speed,
          double? jump,
          double? gravity,
          bool? follow,
          int? player,
          GameEffect? touched,
          String? sound,
          bool? stays,
          bool? sendsBack,
          String? pressedBy,
          double? reach,
          ButtonAction? press}) =>
      PlaySpec(
        as: as ?? this.as,
        speed: (speed ?? this.speed).clamp(10.0, 5000.0),
        jump: (jump ?? this.jump).clamp(0.0, 5000.0),
        gravity: (gravity ?? this.gravity).clamp(0.0, 20000.0),
        follow: follow ?? this.follow,
        player: (player ?? this.player).clamp(1, 4),
        touched: touched ?? this.touched,
        sound: sound ?? this.sound,
        stays: stays ?? this.stays,
        sendsBack: sendsBack ?? this.sendsBack,
        pressedBy: pressedBy ?? this.pressedBy,
        reach: (reach ?? this.reach).clamp(0.0, 100000.0),
        press: press ?? this.press,
      );

  Map<String, dynamic> toJson() => {
        "as": as.name,
        if (speed != 320) "speed": speed,
        if (jump != 180) "jump": jump,
        if (gravity != 2200) "gravity": gravity,
        if (!follow) "follow": false,
        if (player != 1) "player": player,
        if (as.touched) "touched": touched.toJson(),
        if (sound.isNotEmpty) "sound": sound,
        if (stays) "stays": true,
        if (!sendsBack) "sendsBack": false,
        if (pressedBy.isNotEmpty) ...{
          "pressedBy": pressedBy,
          if (reach != 0) "reach": reach,
          "press": press.toJson(),
        },
      };

  factory PlaySpec.fromJson(Object? json) {
    if (json is! Map) return const PlaySpec();
    return const PlaySpec().copyWith(
      as: PlayAs.fromName(json["as"] as String?),
      speed: jsonDouble(json["speed"], 320),
      jump: jsonDouble(json["jump"], 180),
      gravity: jsonDouble(json["gravity"], 2200),
      follow: json["follow"] != false,
      player: json["player"] is num ? (json["player"] as num).toInt() : 1,
      touched: GameEffect.fromJson(json["touched"]),
      sound: json["sound"] is String ? json["sound"] as String : "",
      stays: json["stays"] == true,
      sendsBack: json["sendsBack"] != false,
      pressedBy: json["pressedBy"] is String ? json["pressedBy"] as String : "",
      reach: jsonDouble(json["reach"], 0),
      press: json["press"] is Map<String, dynamic>
          ? ButtonAction.fromJson(json["press"] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaySpec &&
      other.as == as &&
      other.speed == speed &&
      other.jump == jump &&
      other.gravity == gravity &&
      other.follow == follow &&
      other.player == player &&
      other.touched == touched &&
      other.sound == sound &&
      other.stays == stays &&
      other.sendsBack == sendsBack &&
      other.pressedBy == pressedBy &&
      other.reach == reach &&
      other.press.kind == press.kind &&
      other.press.frame == press.frame &&
      other.press.elementId == press.elementId &&
      other.press.url == press.url;

  @override
  int get hashCode => Object.hash(
      as,
      speed,
      jump,
      gravity,
      follow,
      player,
      touched,
      sound,
      stays,
      sendsBack,
      pressedBy,
      reach,
      press.kind,
      press.elementId);
}

/// GameDoes is something that happens in a game: a count added to or taken
/// from, another scene -- a chosen one, or the next: levels one after
/// another -- the game started again or ended.
enum GameDoes {
  nothing("Nothing"),
  add("Add to a count"),
  take("Take from a count"),
  scene("Go to a scene"),
  next("Go to the next scene"),
  restart("Start the game again"),
  stop("End the game");

  final String label;
  const GameDoes(this.label);

  /// counts is whether it is done to a count.
  bool get counts => this == add || this == take;

  static GameDoes fromName(String? name) =>
      values.firstWhere((d) => d.name == name, orElse: () => nothing);
}

/// GameEffect is one thing that happens: [does], to the count [count] by
/// [amount], or to the scene [scene] -- by its id, as a button keeps its
/// own, so moving the scenes about does not point it at another.
class GameEffect {
  final GameDoes does;
  final String count;
  final int amount;
  final String scene;

  const GameEffect(
      {this.does = GameDoes.nothing,
      this.count = "",
      this.amount = 1,
      this.scene = ""});

  GameEffect copyWith(
          {GameDoes? does, String? count, int? amount, String? scene}) =>
      GameEffect(
          does: does ?? this.does,
          count: count ?? this.count,
          amount: (amount ?? this.amount).clamp(1, 1000000),
          scene: scene ?? this.scene);

  Map<String, dynamic> toJson() => {
        "does": does.name,
        if (count.isNotEmpty) "count": count,
        if (amount != 1) "amount": amount,
        if (scene.isNotEmpty) "scene": scene,
      };

  factory GameEffect.fromJson(Object? json) {
    if (json is! Map) return const GameEffect();
    return GameEffect(
        does: GameDoes.fromName(json["does"] as String?),
        count: json["count"] is String ? json["count"] as String : "",
        amount: json["amount"] is num
            ? (json["amount"] as num).toInt().clamp(1, 1000000)
            : 1,
        scene: json["scene"] is String ? json["scene"] as String : "");
  }

  @override
  bool operator ==(Object other) =>
      other is GameEffect &&
      other.does == does &&
      other.count == count &&
      other.amount == amount &&
      other.scene == scene;

  @override
  int get hashCode => Object.hash(does, count, amount, scene);
}

/// GameCount is a number the game keeps -- coins, lives, keys -- from
/// [start]; and, where [reach] is set, what happens when it gets there:
/// lives down to nought starting the game again.
class GameCount {
  final String id;
  final String name;
  final int start;
  final int? reach;
  final GameEffect then;

  const GameCount(this.id, this.name,
      {this.start = 0, this.reach, this.then = const GameEffect()});

  GameCount copyWith(
          {String? name,
          int? start,
          int? reach,
          bool noReach = false,
          GameEffect? then}) =>
      GameCount(id, name ?? this.name,
          start: start ?? this.start,
          reach: noReach ? null : reach ?? this.reach,
          then: then ?? this.then);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        if (start != 0) "start": start,
        if (reach case var r?) "reach": r,
        if (then.does != GameDoes.nothing) "then": then.toJson(),
      };

  static GameCount? fromJson(Object? json) {
    if (json is! Map || json["id"] is! String) return null;
    return GameCount(json["id"] as String,
        json["name"] is String ? json["name"] as String : "Count",
        start: json["start"] is num ? (json["start"] as num).toInt() : 0,
        reach: json["reach"] is num ? (json["reach"] as num).toInt() : null,
        then: GameEffect.fromJson(json["then"]));
  }

  @override
  bool operator ==(Object other) =>
      other is GameCount &&
      other.id == id &&
      other.name == name &&
      other.start == start &&
      other.reach == reach &&
      other.then == then;

  @override
  int get hashCode => Object.hash(id, name, start, reach, then);
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

/// defaultControlsFor is player [player]'s usual controls: the first
/// player's are [defaultControls]; the second's WASD with F to jump and E
/// to act -- one keyboard shared -- and the third's and fourth's a
/// controller's alone. Every player's controller buttons are the same: each
/// has a controller of its own.
List<ControlAction> defaultControlsFor(int player) {
  if (player <= 1) return defaultControls;
  if (player == 2) {
    return [
      ControlAction("left", "Move left",
          keys: [_letter("a")],
          pad: const [PadInput.leftStickLeft, PadInput.dpadLeft]),
      ControlAction("right", "Move right",
          keys: [_letter("d")],
          pad: const [PadInput.leftStickRight, PadInput.dpadRight]),
      ControlAction("up", "Up",
          keys: [_letter("w")],
          pad: const [PadInput.leftStickUp, PadInput.dpadUp]),
      ControlAction("down", "Down",
          keys: [_letter("s")],
          pad: const [PadInput.leftStickDown, PadInput.dpadDown]),
      ControlAction("jump", "Jump",
          keys: [_letter("f")], pad: const [PadInput.a]),
      ControlAction("act", "Action",
          keys: [_letter("e")], pad: const [PadInput.x]),
    ];
  }
  return [for (var a in defaultControls) a.copyWith(keys: const [])];
}
