import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble, jsonStr, jsonString;
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';

// play.dart is a canvas played as a game: what each element does and the
// controls that drive it, each an action pressed by keys and controller
// buttons, as Godot's input map has them. Distances are canvas units,
// times seconds.

enum PlayAs {
  none("Not played"),
  platformer("Platformer"),
  topDown("Top-down"),
  camera("Camera"),
  solid("Something solid"),

  /// pickup is taken by a player touching it (a coin, a key), and hazard
  /// hurts one (spikes, water). Each does its [PlaySpec.touched].
  pickup("Pickup"),
  hazard("Hazard");

  final String label;
  const PlayAs(this.label);

  bool get moves => this == platformer || this == topDown || this == camera;

  bool get touched => this == pickup || this == hazard;

  static PlayAs fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => none);
}

class PlaySpec {
  final PlayAs as;

  /// speed is in canvas units a second; jump is how high a platformer jumps,
  /// and gravity how fast it falls.
  final double speed;
  final double jump;
  final double gravity;

  final bool follow;

  /// zoom is how close the view follows it, 1 (the page as it is) to 3;
  /// zoomOut how far it draws back while it moves, 0 (not at all) to 1 (the
  /// whole page). Eased, so the view breathes with it.
  final double zoom;
  final double zoomOut;

  /// player is which player drives it, 1 to 4 (see
  /// CanvasDocument.controlsFor).
  final int player;

  /// touched is what a pickup or hazard does when touched; sound the sound
  /// element played, by id; stays whether a pickup remains (else it goes until
  /// the game restarts); sendsBack whether a hazard returns the player home.
  final GameEffect touched;
  final String sound;
  final bool stays;
  final bool sendsBack;

  /// touchWhole touches the whole box, not only a sprite's drawn part (see
  /// SpriteElement.touchIn).
  final bool touchWhole;

  /// pressSound is a sound, slot or channel stop heard when it is pressed.
  final String pressSound;

  /// pressedBy is the action that presses it, by id ("" none), from
  /// anywhere, or with [reach] set only with a player within that many units;
  /// and press what that does. A Button pressed does its own.
  final String pressedBy;
  final double reach;
  final ButtonAction press;

  /// hits is how many punches or kicks defeat it; 0 means it cannot be hit.
  /// Defeated, it is gone as a taken pickup is, and does [defeated]; each hit
  /// plays [hitSound] and starts its clips that start on a hit.
  final int hits;
  final GameEffect defeated;
  final String hitSound;

  /// struck is what each hit does before any defeat (a boss's health).
  final GameEffect struck;

  bool get hittable => hits > 0;

  const PlaySpec({
    this.as = PlayAs.none,
    this.speed = 320,
    this.jump = 180,
    this.gravity = 2200,
    this.follow = true,
    this.zoom = 1,
    this.zoomOut = 0,
    this.player = 1,
    this.touched = const GameEffect(),
    this.sound = "",
    this.stays = false,
    this.sendsBack = true,
    this.touchWhole = false,
    this.pressSound = "",
    this.pressedBy = "",
    this.reach = 0,
    this.press = const ButtonAction(kind: ButtonActionKind.toggleElement),
    this.hits = 0,
    this.defeated = const GameEffect(),
    this.hitSound = "",
    this.struck = const GameEffect(),
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = PlaySpec();

  /// isNone is whether it does nothing in a game: not played, pressed or hit.
  bool get isNone => as == PlayAs.none && pressedBy.isEmpty && hits == 0;

  PlaySpec copyWith(
          {PlayAs? as,
          double? speed,
          double? jump,
          double? gravity,
          bool? follow,
          double? zoom,
          double? zoomOut,
          int? player,
          GameEffect? touched,
          String? sound,
          bool? stays,
          bool? sendsBack,
          bool? touchWhole,
          String? pressSound,
          String? pressedBy,
          double? reach,
          ButtonAction? press,
          int? hits,
          GameEffect? defeated,
          String? hitSound,
          GameEffect? struck}) =>
      PlaySpec(
        as: as ?? this.as,
        speed: (speed ?? this.speed).clamp(10.0, 5000.0),
        jump: (jump ?? this.jump).clamp(0.0, 5000.0),
        gravity: (gravity ?? this.gravity).clamp(0.0, 20000.0),
        follow: follow ?? this.follow,
        zoom: (zoom ?? this.zoom).clamp(1.0, 3.0),
        zoomOut: (zoomOut ?? this.zoomOut).clamp(0.0, 1.0),
        player: (player ?? this.player).clamp(1, 4),
        touched: touched ?? this.touched,
        sound: sound ?? this.sound,
        stays: stays ?? this.stays,
        sendsBack: sendsBack ?? this.sendsBack,
        touchWhole: touchWhole ?? this.touchWhole,
        pressSound: pressSound ?? this.pressSound,
        pressedBy: pressedBy ?? this.pressedBy,
        reach: (reach ?? this.reach).clamp(0.0, 100000.0),
        press: press ?? this.press,
        hits: (hits ?? this.hits).clamp(0, 99),
        defeated: defeated ?? this.defeated,
        hitSound: hitSound ?? this.hitSound,
        struck: struck ?? this.struck,
      );

  Map<String, dynamic> toJson() => {
        "as": as.name,
        if (speed != _defaults.speed) "speed": speed,
        if (jump != _defaults.jump) "jump": jump,
        if (gravity != _defaults.gravity) "gravity": gravity,
        if (!follow) "follow": false,
        if (zoom != _defaults.zoom) "zoom": zoom,
        if (zoomOut != _defaults.zoomOut) "zoomOut": zoomOut,
        if (player != _defaults.player) "player": player,
        if (as.touched) "touched": touched.toJson(),
        if (sound.isNotEmpty) "sound": sound,
        if (stays) "stays": true,
        if (!sendsBack) "sendsBack": false,
        if (touchWhole) "touchWhole": true,
        if (pressedBy.isNotEmpty) ...{
          "pressedBy": pressedBy,
          if (reach != _defaults.reach) "reach": reach,
          "press": press.toJson(),
          if (pressSound.isNotEmpty) "pressSound": pressSound,
        },
        if (hits > 0) ...{
          "hits": hits,
          "defeated": defeated.toJson(),
          if (hitSound.isNotEmpty) "hitSound": hitSound,
          if (struck.does != GameDoes.nothing) "struck": struck.toJson(),
        },
      };

  factory PlaySpec.fromJson(Object? json) {
    if (json is! Map) return const PlaySpec();
    return const PlaySpec().copyWith(
      as: PlayAs.fromName(jsonStr(json["as"])),
      speed: jsonDouble(json["speed"], _defaults.speed),
      jump: jsonDouble(json["jump"], _defaults.jump),
      gravity: jsonDouble(json["gravity"], _defaults.gravity),
      follow: json["follow"] != false,
      zoom: jsonDouble(json["zoom"], _defaults.zoom),
      zoomOut: jsonDouble(json["zoomOut"], _defaults.zoomOut),
      player: json["player"] is num ? (json["player"] as num).toInt() : 1,
      touched: GameEffect.fromJson(json["touched"]),
      sound: jsonString(json["sound"], _defaults.sound),
      stays: json["stays"] == true,
      sendsBack: json["sendsBack"] != false,
      touchWhole: json["touchWhole"] == true,
      pressSound:
          json["pressSound"] is String ? json["pressSound"] as String : "",
      pressedBy: jsonString(json["pressedBy"], _defaults.pressedBy),
      reach: jsonDouble(json["reach"], _defaults.reach),
      press: json["press"] is Map<String, dynamic>
          ? ButtonAction.fromJson(json["press"] as Map<String, dynamic>)
          : null,
      hits: json["hits"] is num ? (json["hits"] as num).toInt() : 0,
      defeated: GameEffect.fromJson(json["defeated"]),
      hitSound: jsonString(json["hitSound"], _defaults.hitSound),
      struck: GameEffect.fromJson(json["struck"]),
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
      other.zoom == zoom &&
      other.zoomOut == zoomOut &&
      other.player == player &&
      other.touched == touched &&
      other.sound == sound &&
      other.stays == stays &&
      other.sendsBack == sendsBack &&
      other.touchWhole == touchWhole &&
      other.pressSound == pressSound &&
      other.pressedBy == pressedBy &&
      other.reach == reach &&
      other.press.kind == press.kind &&
      other.press.frame == press.frame &&
      other.press.elementId == press.elementId &&
      other.press.url == press.url &&
      other.hits == hits &&
      other.defeated == defeated &&
      other.hitSound == hitSound &&
      other.struck == struck;

  @override
  int get hashCode => Object.hash(
      as,
      speed,
      jump,
      gravity,
      Object.hash(follow, zoom, zoomOut),
      player,
      touched,
      sound,
      stays,
      sendsBack,
      touchWhole,
      pressSound,
      pressedBy,
      reach,
      press.kind,
      press.elementId,
      hits,
      defeated,
      hitSound,
      struck);
}

/// GameSound is a game's sound choice: a canvas sound by element id, a
/// mixer slot by its clip's id, or a channel's slots stopped by its key.
sealed class GameSound {
  const GameSound();
}

class GameSoundElement extends GameSound {
  final String id;
  const GameSoundElement(this.id);
}

class GameSoundSlot extends GameSound {
  final String clip;
  const GameSoundSlot(this.clip);
}

class GameSoundStop extends GameSound {
  final String channel;
  const GameSoundStop(this.channel);
}

/// gameSoundSlot and gameSoundStop write a slot and a stop as a game keeps
/// them; gameSoundOf reads one back, null for none.
String gameSoundSlot(String clip) => "slot:$clip";
String gameSoundStop(String channel) => "stop:$channel";
GameSound? gameSoundOf(String ref) {
  if (ref.isEmpty) return null;
  if (ref.startsWith("slot:")) return GameSoundSlot(ref.substring(5));
  if (ref.startsWith("stop:")) return GameSoundStop(ref.substring(5));
  return GameSoundElement(ref);
}

/// PlayFeel names a platformer's speed, jump and gravity together; Custom
/// is any other three.
enum PlayFeel {
  floaty("Floaty", 280, 240, 1400),
  normal("Normal", 330, 220, 2400),
  snappy("Snappy", 380, 200, 3400),
  custom("Custom", 0, 0, 0);

  final String label;
  final double speed;
  final double jump;
  final double gravity;
  const PlayFeel(this.label, this.speed, this.jump, this.gravity);

  static PlayFeel of(PlaySpec spec) => values.firstWhere(
      (f) =>
          f != custom &&
          f.speed == spec.speed &&
          f.jump == spec.jump &&
          f.gravity == spec.gravity,
      orElse: () => custom);
}

/// GameDoes is something that happens: a count changed, a move to another
/// scene, or the game restarted or ended.
enum GameDoes {
  nothing("Nothing"),
  add("Add to a count"),
  take("Take from a count"),

  /// show and hide another element: a door opened, a "You win!" on the HUD.
  show("Show something"),
  hide("Hide something"),
  scene("Go to a scene"),
  next("Go to the next scene"),
  restart("Start the game again"),
  stop("End the game");

  final String label;
  const GameDoes(this.label);

  bool get counts => this == add || this == take;

  bool get shows => this == show || this == hide;

  static GameDoes fromName(String? name) =>
      values.firstWhere((d) => d.name == name, orElse: () => nothing);
}

/// GameEffect is one thing that happens: [does], to the count [count] by
/// [amount], to the scene [scene], or to the element [element]. Each is held
/// by id, so reordering scenes does not retarget it.
class GameEffect {
  final GameDoes does;
  final String count;
  final int amount;
  final String scene;
  final String element;

  /// sound is a sound, slot or channel stop heard as it happens.
  final String sound;

  const GameEffect(
      {this.does = GameDoes.nothing,
      this.count = "",
      this.amount = 1,
      this.scene = "",
      this.element = "",
      this.sound = ""});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = GameEffect();

  GameEffect copyWith(
          {GameDoes? does,
          String? count,
          int? amount,
          String? scene,
          String? element,
          String? sound}) =>
      GameEffect(
          does: does ?? this.does,
          count: count ?? this.count,
          amount: (amount ?? this.amount).clamp(1, 1000000),
          scene: scene ?? this.scene,
          element: element ?? this.element,
          sound: sound ?? this.sound);

  Map<String, dynamic> toJson() => {
        "does": does.name,
        if (count.isNotEmpty) "count": count,
        if (amount != _defaults.amount) "amount": amount,
        if (scene.isNotEmpty) "scene": scene,
        if (element.isNotEmpty) "element": element,
        if (sound.isNotEmpty) "sound": sound,
      };

  factory GameEffect.fromJson(Object? json) {
    if (json is! Map) return const GameEffect();
    return GameEffect(
        does: GameDoes.fromName(jsonStr(json["does"])),
        count: jsonString(json["count"], _defaults.count),
        amount: json["amount"] is num
            ? (json["amount"] as num).toInt().clamp(1, 1000000)
            : 1,
        scene: jsonString(json["scene"], _defaults.scene),
        element: jsonString(json["element"], _defaults.element),
        sound: jsonString(json["sound"], _defaults.sound));
  }

  @override
  bool operator ==(Object other) =>
      other is GameEffect &&
      other.does == does &&
      other.count == count &&
      other.amount == amount &&
      other.scene == scene &&
      other.element == element &&
      other.sound == sound;

  @override
  int get hashCode => Object.hash(does, count, amount, scene, element, sound);
}

/// GameCount is a number the game keeps (coins, lives) from [start], and
/// where [reach] is set what happens when it gets there: lives down to 0
/// restarting the game.
class GameCount {
  final String id;
  final String name;
  final int start;
  final int? reach;
  final GameEffect then;

  const GameCount(this.id, this.name,
      {this.start = 0, this.reach, this.then = const GameEffect()});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = GameCount("", "");

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
        if (start != _defaults.start) "start": start,
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

/// ControlAction is something a player does (move left, jump) and the keys
/// (by LogicalKeyboardKey.keyId) and controller inputs that press it.
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
const int _space = 0x20, _enter = 0x10000000d;
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
  // Punch and kick hit elements: see PlaySpec.hits.
  ControlAction("punch", "Punch",
      keys: [_letter("j")], pad: const [PadInput.b]),
  ControlAction("kick", "Kick", keys: [_letter("k")], pad: const [PadInput.y]),
];

/// sharedDefaultControls are the first player's controls when a second
/// shares the keyboard: arrows, Space and Enter, leaving WASD, F and E.
final List<ControlAction> sharedDefaultControls = [
  for (var a in defaultControls)
    a.copyWith(
        keys: a.id == "act"
            ? const [_enter]
            : [
                for (var k in a.keys)
                  if (k > 0xFF || k == _space) k
              ]),
];

/// defaultControlsFor is [player]'s usual controls: the first's are
/// [defaultControls], the second's WASD with F to jump and E to act, and the
/// third's and fourth's controller only. Controller buttons are the same
/// for all: each player has their own controller.
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
