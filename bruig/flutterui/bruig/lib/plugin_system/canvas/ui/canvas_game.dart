import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_pose.dart'
    show kickSeconds, punchSeconds;
import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';

// canvas_game.dart is a canvas played as a game: keys and controllers read
// as the document's actions, each played element moved by them a step at a
// time (falling and landing on what is solid), the view following the
// player, and the canvas as it now looks, for the stage to draw.
//
// What is not played moves as its clips move it -- placed on the timeline,
// or launched live from its slots (see motion_player.dart) -- and is solid,
// touched and pressed where they have it.
//
// Nothing here is written into the document: stopped, everything is where
// it was put.

/// GameInput is what is held down: keys by id, and each controller's
/// inputs. Controllers go to the players in the order they were first used,
/// one each; any more go to the first player.
class GameInput {
  final Set<int> keys = {};
  final Set<String> _was = {};

  /// players is how many players there are to hand controllers to.
  int players = 1;

  final List<String> _devices = [];
  final Map<String, Set<PadInput>> _pads = {};

  /// padOf is what [player]'s controllers hold down.
  Set<PadInput> padOf(int player) => {
        for (var (i, id) in _devices.indexed)
          if ((i < players ? i + 1 : 1) == player) ...?_pads[id],
      };

  /// pad is what the first player's controllers hold down.
  Set<PadInput> get pad => padOf(1);

  /// down is whether [action] is held -- by [player]'s controller, or a key.
  bool down(ControlAction action, [int player = 1]) =>
      action.keys.any(keys.contains) ||
      (action.pad.isNotEmpty && action.pad.any(padOf(player).contains));

  /// pressed is whether [action] went down since the last step.
  bool pressed(ControlAction action, [int player = 1]) =>
      down(action, player) && !_was.contains("$player:${action.id}");

  /// endStep remembers what [player] holds, for [pressed].
  void endStep(List<ControlAction> actions, [int player = 1]) {
    _was.removeWhere((k) => k.startsWith("$player:"));
    _was.addAll([
      for (var a in actions)
        if (down(a, player)) "$player:${a.id}"
    ]);
  }

  /// deadZone is how far a stick goes before it counts.
  static const double deadZone = 0.35;

  /// stick sets a stick axis's two directions on [pad] from its value.
  void stick(
      Set<PadInput> pad, PadInput negative, PadInput positive, double value) {
    pad.remove(negative);
    pad.remove(positive);
    if (value <= -deadZone) pad.add(negative);
    if (value >= deadZone) pad.add(positive);
  }

  /// gamepad takes a controller's event.
  void gamepad(NormalizedGamepadEvent e) {
    if (!_devices.contains(e.gamepadId)) _devices.add(e.gamepadId);
    var pad = _pads.putIfAbsent(e.gamepadId, () => {});
    if (e.button case var b?) {
      var input = switch (b) {
        GamepadButton.a => PadInput.a,
        GamepadButton.b => PadInput.b,
        GamepadButton.x => PadInput.x,
        GamepadButton.y => PadInput.y,
        GamepadButton.leftBumper => PadInput.leftBumper,
        GamepadButton.rightBumper => PadInput.rightBumper,
        GamepadButton.leftTrigger => PadInput.leftTrigger,
        GamepadButton.rightTrigger => PadInput.rightTrigger,
        GamepadButton.back => PadInput.back,
        GamepadButton.start => PadInput.start,
        GamepadButton.dpadUp => PadInput.dpadUp,
        GamepadButton.dpadDown => PadInput.dpadDown,
        GamepadButton.dpadLeft => PadInput.dpadLeft,
        GamepadButton.dpadRight => PadInput.dpadRight,
        _ => null,
      };
      if (input == null) return;
      e.value > 0.5 ? pad.add(input) : pad.remove(input);
      return;
    }
    switch (e.axis) {
      case GamepadAxis.leftStickX:
        stick(pad, PadInput.leftStickLeft, PadInput.leftStickRight, e.value);
      // Up is negative on a screen, whatever the stick reports.
      case GamepadAxis.leftStickY:
        stick(pad, PadInput.leftStickUp, PadInput.leftStickDown, e.value);
      case GamepadAxis.rightStickX:
        stick(pad, PadInput.rightStickLeft, PadInput.rightStickRight, e.value);
      case GamepadAxis.rightStickY:
        stick(pad, PadInput.rightStickUp, PadInput.rightStickDown, e.value);
      case GamepadAxis.leftTrigger:
        e.value > 0.5
            ? pad.add(PadInput.leftTrigger)
            : pad.remove(PadInput.leftTrigger);
      case GamepadAxis.rightTrigger:
        e.value > 0.5
            ? pad.add(PadInput.rightTrigger)
            : pad.remove(PadInput.rightTrigger);
      case null:
        break;
    }
  }

  void clear() {
    keys.clear();
    _pads.clear();
    _devices.clear();
    _was.clear();
  }
}

/// GameBody is a played element as it is now: how far it has moved from
/// where it was put, how fast it is going, whether it stands on something,
/// and which way it faces.
class GameBody {
  Offset at = Offset.zero;
  Offset velocity = Offset.zero;
  bool onGround = false;
  int facing = 1;

  /// heading is the way it last went, across and down (nought until it has
  /// moved); a character turns to it.
  Offset heading = Offset.zero;

  /// move3d is the name of the motion a 3D character is moving with (null,
  /// standing), and [since] the game's clock when it began, so it runs on
  /// unbroken.
  String? move3d;
  double since = 0;

  /// strike is the punch or kick it is throwing ("Punch", "Kick"), and
  /// [struckAt] the game's clock when it was thrown; null between them.
  String? strike;
  double struckAt = 0;

  /// striking is whether a strike is still being thrown at [clock].
  bool striking(double clock) =>
      strike != null && clock - struckAt < strikeSeconds(strike!);
}

/// strikeSeconds is how long a strike takes, once through.
double strikeSeconds(String strike) =>
    strike == "Kick" ? kickSeconds : punchSeconds;

/// strikeReach is how far beyond a player's front a strike reaches, in
/// points: a kick further than a punch.
double strikeReach(String strike) => strike == "Kick" ? 56 : 36;

/// GameRun is a game going.
class GameRun extends ChangeNotifier {
  final GameInput input = GameInput();
  final Map<String, GameBody> bodies = {};
  Offset camera = Offset.zero;

  /// clock is how long the game has run, in seconds.
  double clock = 0;

  /// controllers are the controllers connected when [listen] ran, by name.
  List<String> get controllers => List.unmodifiable(_controllers);
  final List<String> _controllers = [];
  StreamSubscription<NormalizedGamepadEvent>? _pads;

  /// listen takes the controllers' events, where there are any to take.
  Future<void> listen() async {
    try {
      var list = await Gamepads.list();
      // Stopped while it asked: nothing to listen for.
      if (_disposed) return;
      _controllers
        ..clear()
        ..addAll([for (var c in list) c.name]);
      _pads = Gamepads.normalizedEvents.listen((e) {
        input.gamepad(e);
      });
      notifyListeners();
    } catch (exception) {
      debugPrint("Controllers are not available: $exception");
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _pads?.cancel();
    super.dispose();
  }

  GameBody _body(String id) => bodies.putIfAbsent(id, GameBody.new);

  /// _ground is each tile map's ground as last worked out (its layers, where
  /// it stood, and the boxes), kept while neither changes rather than redone
  /// sixty times a second.
  final Map<String, (List<TileLayer>, Rect, List<Rect>)> _ground = {};

  List<Rect> _groundOf(TileMapElement map, Rect box) {
    if (_ground[map.id] case (var layers, var at, var boxes)
        when identical(layers, map.layers) && at == box) {
      return boxes;
    }
    var boxes = tileGround(map, 0, at: box);
    _ground[map.id] = (map.layers, box, boxes);
    return boxes;
  }

  /// _live is what plays live from the slots on this step (see
  /// motion_player.dart), or null.
  LiveMotion? _live;

  /// _boxOf is where [e] is on [frame]: moved by its clips -- on the
  /// timeline, or live -- as well as its keyframes.
  Rect _boxOf(CanvasDocument doc, CanvasElement e, int frame) => !movesAtAll(e)
      ? e.boundsAt(frame)
      : e.movedBoundsAt(frame, doc, live: _live);

  /// _boxesOf is where [e] is on [frame], by name: its own box, or -- an
  /// element reused -- each instance's not gone (see instanceKey), each
  /// a pickup, a hazard or a platform of its own.
  Map<String, Rect> _boxesOf(CanvasDocument doc, CanvasElement e, int frame) {
    var set = e.base.motion.instances;
    if (set == null) return {e.id: _boxOf(doc, e, frame)};
    return {
      for (var (i, item) in set.items.indexed)
        if (!gone.contains(instanceKey(e.id, item.id)))
          instanceKey(e.id, item.id): e.boundsWith(
              poseWithMotion(e, frame, doc, live: _live, instance: i)),
    };
  }

  /// fadedOut is how faint a thing's motion leaves it before it is as good
  /// as not there: a blinking laser at its dim, a coin not yet faded up.
  static const fadedOut = 0.2;

  /// _presentOf is _boxesOf less each that its motion -- clips, keyframes, a
  /// loop -- has faded below [fadedOut]: what can be touched or hit. Only a
  /// fade the element moves by counts: one left at opacity 0 on purpose (an
  /// unseen trap) is there still.
  Map<String, Rect> _presentOf(CanvasDocument doc, CanvasElement e, int frame) {
    if (!movesAtAll(e)) {
      return (e.track?.at(frame).opacity ?? 1) < fadedOut
          ? const {}
          : _boxesOf(doc, e, frame);
    }
    var set = e.base.motion.instances;
    if (set == null) {
      var pose = poseWithMotion(e, frame, doc, live: _live);
      return pose.opacity < fadedOut ? const {} : {e.id: e.boundsWith(pose)};
    }
    return {
      for (var (i, item) in set.items.indexed)
        if (!gone.contains(instanceKey(e.id, item.id)))
          if (poseWithMotion(e, frame, doc, live: _live, instance: i)
              case var pose when pose.opacity >= fadedOut)
            instanceKey(e.id, item.id): e.boundsWith(pose),
    };
  }

  /// _movesLive is whether [e] is moved by clips launched from its slots,
  /// on their own clock rather than the timeline's.
  bool _movesLive(CanvasElement e) => _live?.of(e.id) != null;

  /// step moves everything played in [doc] on by [dt] seconds, on [frame],
  /// with [live] what plays from the slots.
  void step(CanvasDocument doc, int frame, double dt, {LiveMotion? live}) {
    _live = live;
    if (!_started) _begin(doc);
    clock += dt;
    // Each player's controls. One keyboard is shared: the first player's keys
    // that another player has are that player's.
    var players = doc.players;
    input.players = players.reduce(math.max);
    var claimed = {
      for (var p in players)
        if (p != 1)
          for (var a in doc.controlsFor(p)) ...a.keys,
    };
    List<ControlAction> controlsOf(int p) => p == 1
        ? [
            for (var a in doc.controlsNow)
              a.copyWith(keys: [
                for (var k in a.keys)
                  if (!claimed.contains(k)) k
              ])
          ]
        : doc.controlsFor(p);
    var byPlayer = {
      for (var p in players) p: {for (var a in controlsOf(p)) a.id: a},
    };
    bool downBy(int p, String id) =>
        byPlayer[p]?[id] != null && input.down(byPlayer[p]![id]!, p);
    bool pressedBy(int p, String id) =>
        byPlayer[p]?[id] != null && input.pressed(byPlayer[p]![id]!, p);
    bool pressed(String id) => players.any((p) => pressedBy(p, id));

    var solids = [
      for (var e in doc.elements)
        if (e.base.play.as == PlayAs.solid && shown(e) && !gone.contains(e.id))
          ..._boxesOf(doc, e, frame).values,
      // A tile map's solid layers: the tiles are the ground.
      for (var e in doc.elements)
        if (e is TileMapElement && shown(e))
          ..._groundOf(e, _boxOf(doc, e, frame)),
    ];
    // A moving solid (a platform moved by keyframes or clips) carries what
    // stands on it. On the timeline, only while it goes on a frame or two:
    // not as it loops back to its start, or jumps. Live, on the slots' own
    // clock, always.
    var onward =
        _frameWas != null && frame >= _frameWas! && frame - _frameWas! <= 2;
    _frameWas = frame;
    var moving = {
      for (var e in doc.elements)
        if (e.base.play.as == PlayAs.solid &&
            shown(e) &&
            !gone.contains(e.id) &&
            (e.track != null || movesAtAll(e)) &&
            (onward || _movesLive(e)))
          ..._boxesOf(doc, e, frame),
    };
    var page = doc.size.rect;
    // The ground under everything: the canvas's bottom edge.
    var floor = Rect.fromLTRB(-1e6, page.bottom, 1e6, page.bottom + 1e5);

    var followed = <Offset>[];
    for (var e in doc.elements) {
      var spec = e.base.play;
      if (!spec.as.moves) continue;
      var p = spec.player;
      var dx = (downBy(p, "right") ? 1 : 0) - (downBy(p, "left") ? 1 : 0);
      var dy = (downBy(p, "down") ? 1 : 0) - (downBy(p, "up") ? 1 : 0);
      var body = _body(e.id);
      var box = e.boundsAt(frame);
      switch (spec.as) {
        case PlayAs.platformer:
          if (body.onGround) _ride(body, box, moving);
          body.velocity =
              Offset(dx * spec.speed, body.velocity.dy + spec.gravity * dt);
          if (pressedBy(p, "jump") && body.onGround) {
            body.velocity = Offset(
                body.velocity.dx, -math.sqrt(2 * spec.gravity * spec.jump));
          }
          _move(body, box, dt, [...solids, floor], gravity: true);
        case PlayAs.topDown:
          var v = Offset(dx.toDouble(), dy.toDouble());
          if (v.distance > 0) v = v / v.distance;
          body.velocity = v * spec.speed;
          _move(body, box, dt, [...solids, floor], gravity: false);
        case PlayAs.camera:
          camera += Offset(dx.toDouble(), dy.toDouble()) * spec.speed * dt;
        case PlayAs.none || PlayAs.solid || PlayAs.pickup || PlayAs.hazard:
          break;
      }
      if (dx != 0) body.facing = dx.sign;
      // A punch or a kick, one at a time (Ken, 2026-11-10).
      if (spec.as == PlayAs.platformer || spec.as == PlayAs.topDown) {
        for (var (action, kind) in const [
          ("punch", "Punch"),
          ("kick", "Kick")
        ]) {
          if (!pressedBy(p, action) || body.striking(clock)) continue;
          body
            ..strike = kind
            ..struckAt = clock;
          _strike(doc, frame, e, body, kind);
        }
        if (body.strike != null && !body.striking(clock)) body.strike = null;
      }
      if (spec.as != PlayAs.camera && (dx != 0 || dy != 0)) {
        body.heading = Offset(
            dx.toDouble(), spec.as == PlayAs.topDown ? dy.toDouble() : 0);
      }
      if (e is Character3dElement) _move3dOf(e, body);
      if (spec.follow && spec.as != PlayAs.camera) {
        followed.add(box.center + body.at);
      }
    }
    // The view follows the player (between the players, where there are
    // more): across always, up and down only for a game seen from above; never
    // left of where the canvas starts.
    if (followed.isNotEmpty) {
      var f = followed.reduce((a, b) => a + b) / followed.length.toDouble();
      var topDown = doc.elements
          .any((e) => e.base.play.as == PlayAs.topDown && e.base.play.follow);
      camera = Offset(math.max(0, f.dx - page.width / 2),
          topDown ? math.max(0, f.dy - page.height / 2) : 0);
    }
    _platformsWere
      ..clear()
      ..addAll(moving);
    _presses(doc, frame, pressed);
    _touches(doc, frame);
    if (_again) {
      _again = false;
      _begin(doc);
    }
    for (var p in players) {
      input.endStep(controlsOf(p), p);
    }
    notifyListeners();
  }

  /// _platformsWere is where each moving solid was on the last step, and
  /// _frameWas the frame it was on.
  final Map<String, Rect> _platformsWere = {};
  int? _frameWas;

  /// _ride moves [body] (on the ground, its box as put [box]) with the
  /// platform it stands on, as far as that went since the last step.
  void _ride(GameBody body, Rect box, Map<String, Rect> platforms) {
    var feet = box.shift(body.at);
    for (var MapEntry(key: id, value: now) in platforms.entries) {
      var was = _platformsWere[id];
      if (was == null || was == now) continue;
      if ((feet.bottom - was.top).abs() > 2 ||
          feet.right <= was.left ||
          feet.left >= was.right) {
        continue;
      }
      body.at += now.topLeft - was.topLeft;
      return;
    }
  }

  /// counts are where each of the game's counts has got to, by id; gone is
  /// the pickups taken, by id.
  final Map<String, int> counts = {};
  final Set<String> gone = {};

  /// events are what the game has asked of the canvas since they were last
  /// taken (a sound, another scene, the end), for the controller to do.
  final List<GameEvent> events = [];

  bool _started = false, _again = false;

  /// _touching is each player and pickup or hazard touching on the last
  /// step: a touch is counted once, as it starts.
  final Set<(String, String)> _touching = {};

  /// toggled are the elements shown or hidden by a press, against how
  /// they were put: a gate opened. Gone when the game stops.
  final Set<String> toggled = {};

  /// shown is whether [e] is there in the game: as it was put, unless a
  /// press has turned it.
  bool shown(CanvasElement e) => e.visible != toggled.contains(e.id);

  /// toggle shows [id] if it is hidden, and hides it if not.
  void toggle(String id) =>
      toggled.contains(id) ? toggled.remove(id) : toggled.add(id);

  /// _presses is each element pressed by an action pressed on this step:
  /// from anywhere, or with a player in its reach.
  void _presses(
      CanvasDocument doc, int frame, bool Function(String id) pressed) {
    var players = [
      for (var e in doc.elements)
        if ((e.base.play.as == PlayAs.platformer ||
                e.base.play.as == PlayAs.topDown) &&
            bodies[e.id] != null)
          e.boundsAt(frame).shift(bodies[e.id]!.at),
    ];
    for (var e in doc.elements) {
      var spec = e.base.play;
      if (spec.pressedBy.isEmpty || !shown(e) || !pressed(spec.pressedBy)) {
        continue;
      }
      var near = [
        for (var b in _boxesOf(doc, e, frame).values) b.inflate(spec.reach)
      ];
      if (spec.reach > 0 &&
          !players.any((p) => near.any((n) => p.overlaps(n)))) {
        continue;
      }
      events.add(GameEvent(press: e.id));
    }
  }

  /// countOf is where [id] has got to: its start, before the game has run.
  int countOf(CanvasDocument doc, String id) =>
      counts[id] ?? doc.counts.where((c) => c.id == id).firstOrNull?.start ?? 0;

  /// _begin starts the game from the beginning: every count at its start,
  /// every pickup back, every player where it was put.
  void _begin(CanvasDocument doc) {
    _started = true;
    counts
      ..clear()
      ..addAll({for (var c in doc.counts) c.id: c.start});
    gone.clear();
    toggled.clear();
    _touching.clear();
    _platformsWere.clear();
    _frameWas = null;
    bodies.clear();
    camera = Offset.zero;
    hitsTaken.clear();
  }

  /// hitsTaken is how many hits each element (or copy) has taken, by name:
  /// at its [PlaySpec.hits], it is defeated.
  final Map<String, int> hitsTaken = {};

  /// strikeArea is where [kind] thrown by a player at [box] reaches: in
  /// front of it the way it faces (seen from above, the way it goes), a
  /// punch at its chest, a kick lower and further.
  static Rect strikeArea(Rect box, String kind, GameBody body,
      {bool topDown = false}) {
    var reach = strikeReach(kind);
    var h = body.heading;
    if (topDown && h != Offset.zero && h.dx == 0) {
      // Up or down the page.
      return h.dy < 0
          ? Rect.fromLTRB(box.left, box.top - reach, box.right, box.center.dy)
          : Rect.fromLTRB(
              box.left, box.center.dy, box.right, box.bottom + reach);
    }
    var top = box.top + box.height * (kind == "Kick" ? 0.35 : 0.12);
    var bottom = box.bottom - box.height * (kind == "Kick" ? 0.05 : 0.4);
    return body.facing < 0
        ? Rect.fromLTRB(box.left - reach, top, box.center.dx, bottom)
        : Rect.fromLTRB(box.center.dx, top, box.right + reach, bottom);
  }

  /// _strike is [player] throwing [kind]: everything that can be hit in
  /// its reach is -- each copy of one reused its own -- and what has taken
  /// all the hits it takes is defeated.
  void _strike(CanvasDocument doc, int frame, CanvasElement player,
      GameBody body, String kind) {
    var area = strikeArea(player.boundsAt(frame).shift(body.at), kind, body,
        topDown: player.base.play.as == PlayAs.topDown);
    for (var t in doc.elements) {
      var spec = t.base.play;
      if (!spec.hittable || t.id == player.id) continue;
      if (!shown(t) || gone.contains(t.id)) continue;
      for (var MapEntry(key: name, value: box)
          in _presentOf(doc, t, frame).entries) {
        if (gone.contains(name) || !area.overlaps(_touchOf(t, box))) continue;
        var taken = (hitsTaken[name] ?? 0) + 1;
        hitsTaken[name] = taken;
        events.add(GameEvent(hit: name));
        if (spec.hitSound.isNotEmpty) {
          events.add(GameEvent(
              sound: spec.hitSound,
              soundFrom: name == t.id ? null : box.center.dx));
        }
        _do(doc, spec.struck);
        if (taken >= spec.hits) {
          gone.add(name);
          _do(doc, spec.defeated);
        }
      }
    }
  }

  /// newScene is the game gone on to another scene: its players where they
  /// were put, its pickups all there, the counts carried on.
  void newScene() {
    hitsTaken.clear();
    gone.clear();
    toggled.clear();
    _touching.clear();
    _platformsWere.clear();
    _frameWas = null;
    bodies.clear();
    camera = Offset.zero;
  }

  /// _touches does what each pickup or hazard a player starts to touch does,
  /// and starts the clips of whatever it touches that start on a touch.
  void _touches(CanvasDocument doc, int frame) {
    var things = [
      for (var e in doc.elements)
        if ((e.base.play.as.touched || _startsOnTouch(e)) &&
            !gone.contains(e.id) &&
            shown(e))
          e,
    ];
    // Each thing by name, and each instance of one reused its own.
    var boxes = [
      for (var t in things)
        for (var MapEntry(key: name, value: box)
            in _presentOf(doc, t, frame).entries)
          (t, name, _touchOf(t, box)),
    ];
    var now = <(String, String)>{};
    for (var e in doc.elements) {
      var spec = e.base.play;
      if (spec.as != PlayAs.platformer && spec.as != PlayAs.topDown) continue;
      var body = bodies[e.id];
      if (body == null) continue;
      var box = _touchOf(e, e.boundsAt(frame).shift(body.at));
      for (var (t, name, thing) in boxes) {
        if (gone.contains(name) || !box.overlaps(thing)) continue;
        var key = (e.id, name);
        now.add(key);
        if (_touching.contains(key)) continue;
        // One copy of an element reused touched: that copy, by its key.
        if (_startsOnTouch(t)) events.add(GameEvent(touched: name));
        var touched = t.base.play;
        if (!touched.as.touched) continue;
        if (touched.sound.isNotEmpty) {
          // An instance's sound comes from that instance.
          events.add(GameEvent(
              sound: touched.sound,
              soundFrom: name == t.id ? null : thing.center.dx));
        }
        if (touched.as == PlayAs.pickup && !touched.stays) gone.add(name);
        if (touched.as == PlayAs.hazard && touched.sendsBack) {
          body
            ..at = Offset.zero
            ..velocity = Offset.zero;
        }
        _do(doc, touched.touched);
      }
    }
    _touching
      ..clear()
      ..addAll(now);
  }

  Rect _touchOf(CanvasElement e, Rect box) => gameTouchArea(e, box);

  /// _startsOnTouch is whether [e] has a clip that starts when a player
  /// touches it.
  static bool _startsOnTouch(CanvasElement e) => e.base.motion.clips
      .any((c) => c.triggers.any((t) => t.kind == ClipTriggerKind.touched));

  /// _do does [effect], and, where a count it changes reaches its number,
  /// what that count then does, once.
  void _do(CanvasDocument doc, GameEffect effect, [int depth = 0]) {
    if (depth > 8) return;
    if (effect.sound.isNotEmpty) events.add(GameEvent(sound: effect.sound));
    switch (effect.does) {
      case GameDoes.nothing:
        break;
      case GameDoes.add || GameDoes.take:
        var count = doc.counts.where((c) => c.id == effect.count).firstOrNull;
        if (count == null) return;
        var was = countOf(doc, count.id);
        var next = was +
            (effect.does == GameDoes.add ? effect.amount : -effect.amount);
        counts[count.id] = next;
        events.add(GameEvent(counted: (count.id, next)));
        if (count.reach case var at?) {
          var reached = effect.does == GameDoes.add
              ? was < at && next >= at
              : was > at && next <= at;
          if (reached) _do(doc, count.then, depth + 1);
        }
      case GameDoes.show || GameDoes.hide:
        var e = [...doc.elements, ...?doc.master?.elements]
            .where((e) => e.id == effect.element)
            .firstOrNull;
        if (e != null && shown(e) != (effect.does == GameDoes.show)) {
          toggle(e.id);
        }
      case GameDoes.scene:
        if (effect.scene.isNotEmpty) events.add(GameEvent(scene: effect.scene));
      case GameDoes.next:
        events.add(const GameEvent(next: true));
      case GameDoes.restart:
        _again = true;
        events.add(const GameEvent(restart: true));
      case GameDoes.stop:
        events.add(const GameEvent(stop: true));
    }
  }

  /// _move moves [body] by its velocity, across then down, stopping
  /// against [solids]: landing on a top, bumping a side or a ceiling.
  void _move(GameBody body, Rect box, double dt, List<Rect> solids,
      {required bool gravity}) {
    var r = box.shift(body.at + Offset(body.velocity.dx * dt, 0));
    for (var s in solids) {
      if (!r.overlaps(s) || box.shift(body.at).overlaps(s)) continue;
      r = body.velocity.dx > 0
          ? r.shift(Offset(s.left - r.right, 0))
          : r.shift(Offset(s.right - r.left, 0));
      body.velocity = Offset(0, body.velocity.dy);
    }
    var before = r;
    r = r.shift(Offset(0, body.velocity.dy * dt));
    body.onGround = false;
    for (var s in solids) {
      if (!r.overlaps(s)) continue;
      if (body.velocity.dy >= 0 && before.bottom <= s.top + 0.5) {
        r = r.shift(Offset(0, s.top - r.bottom));
        body.onGround = true;
        body.velocity = Offset(body.velocity.dx, 0);
      } else if (body.velocity.dy < 0 && before.top >= s.bottom - 0.5) {
        r = r.shift(Offset(0, s.bottom - r.top));
        body.velocity = Offset(body.velocity.dx, 0);
      }
    }
    body.at = r.topLeft - box.topLeft;
  }

  /// view is [doc] as the game has it now: each played element moved, a
  /// sprite walking, standing or jumping the way it faces, everything but
  /// the backgrounds seen from the camera, and the parallax moved with it.
  CanvasDocument view(CanvasDocument doc,
      {int frame = 0, bool Function(String id)? playing}) {
    var shifted = <CanvasElement>[];
    for (var e in doc.elements) {
      // A pickup taken is gone until the game starts again -- once a clip
      // it started (a coin's pop) has played.
      if (gone.contains(e.id) && !(playing?.call(e.id) ?? false)) continue;
      // An element reused: its instances taken are gone, the rest stay --
      // each one taken until the clip its touch started has played.
      if (e.base.motion.instances case var set?
          when !(playing?.call(e.id) ?? false)) {
        var left = [
          for (var item in set.items)
            if (!gone.contains(instanceKey(e.id, item.id)) ||
                (playing?.call(instanceKey(e.id, item.id)) ?? false))
              item,
        ];
        if (left.isEmpty) continue;
        if (left.length < set.items.length) {
          e = e.withBase(
              motion:
                  e.base.motion.copyWith(instances: set.copyWith(items: left)));
        }
      }
      if (e is BackgroundElement) {
        shifted.add(_withCamera(e));
        continue;
      }
      var body = bodies[e.id];
      var move = (body?.at ?? Offset.zero) - camera;
      var base = e.base.copyWith(x: e.x + move.dx, y: e.y + move.dy);
      // Shown or hidden by a press.
      if (toggled.contains(e.id)) base = base.copyWith(visible: !e.visible);
      // A played element is the game's, not the timeline's: its keyframes
      // and its clips' places on the timeline set aside. Its clips stay, to
      // be launched live.
      if (body != null) {
        base = base.copyWith(
            clearTrack: true, motion: base.motion.copyWith(placed: const []));
      }
      CanvasElement next = e.rebase(base);
      if (next is SpriteElement && body != null) next = _animated(next, body);
      if (next is Character3dElement && body != null) {
        next = _moving3d(next, body, doc.frameRate, frame);
      }
      shifted.add(next);
    }
    // The parallax moves with the view, wherever the backdrop is kept: the
    // document's, this scene's own, or the master's.
    CanvasBackground? moved(CanvasBackground? b) => switch (b?.parallax) {
          var p? => b!.copyWith(parallax: _parallaxAt(p)),
          null => null,
        };
    var out = doc.copyWith(
        elements: shifted, background: moved(doc.background) ?? doc.background);
    if (moved(out.scene.background) case var b?) {
      out = out.withScene(out.at, out.scene.copyWith(background: b));
    }
    if (out.master case var m? when out.masterOn) {
      // The HUD's own shown or hidden elements (a "You win!"), which are not
      // seen from the camera.
      if (m.elements.any((e) => toggled.contains(e.id))) {
        m = m.copyWith(elements: [
          for (var e in m.elements)
            toggled.contains(e.id)
                ? e.rebase(e.base.copyWith(visible: !e.visible))
                : e,
        ]);
      }
      var b = moved(m.background);
      if (b != null) m = m.copyWith(background: b);
      if (b != null || !identical(m, out.master)) out = out.withMaster(m);
    }
    return out;
  }

  ParallaxElement _parallaxAt(ParallaxElement p) =>
      (p.rebase(p.base.copyWith(clearTrack: true)) as ParallaxElement)
          .copyWith(camera: p.camera.copyWith(x: camera.dx, y: camera.dy));

  BackgroundElement _withCamera(BackgroundElement e) {
    var p = e.parallax;
    if (p == null) return e;
    return (e.rebase(e.base.copyWith(clearTrack: true)) as BackgroundElement)
        .copyWith(parallax: _parallaxAt(p));
  }

  /// _animated is [s] moving as [body] is: its walk, jump or standing action
  /// (whichever is called that), facing the way it goes.
  SpriteElement _animated(SpriteElement s, GameBody body) {
    String? named(List<String> words) {
      for (var w in words) {
        for (var a in s.actions) {
          if (a.name.toLowerCase().contains(w)) return a.name;
        }
      }
      return null;
    }

    var moving = body.velocity.dx.abs() > 1 || body.velocity.dy.abs() > 1;
    // A punch or a kick: its own action, or an attack.
    var strike = body.striking(clock)
        ? named([body.strike!.toLowerCase(), "attack", "hit"])
        : null;
    var action = strike ??
        (!body.onGround && body.velocity.dy.abs() > 1
            ? named(["jump", "fall"])
            : moving
                ? named(["walk", "run", "move"])
                : named(["idle", "stand"]));
    // Turned the way it goes whether or not it was drawn with a way to face:
    // a pack's figure, its frames all walking right, faces left by being
    // mirrored.
    return s.copyWith(
        action: action ?? s.action,
        cues: const [],
        directions: true,
        facing: body.facing < 0 ? SpriteFacing.left : SpriteFacing.right);
  }

  /// _move3dOf sets the motion 3D character [c] moves with as [body] goes: a
  /// jump in the air; on the ground a walk, or a run above its own height a
  /// second; none when still. It notes when the motion began, if it changed.
  void _move3dOf(Character3dElement c, GameBody body) {
    var topDown = c.base.play.as == PlayAs.topDown;
    var pace = topDown ? body.velocity.distance : body.velocity.dx.abs();
    var airborne = !topDown && !body.onGround && body.velocity.dy.abs() > 1;
    // A punch or a kick thrown, before anything else, from when it was.
    if (body.striking(clock)) {
      body
        ..move3d = body.strike
        ..since = body.struckAt;
      return;
    }
    var kind = airborne
        ? "Jump"
        : pace > 1
            ? (pace > math.max(1.0, c.height) ? "Run" : "Walk")
            : null;
    if (kind != body.move3d) {
      body.move3d = kind;
      body.since = clock;
    }
  }

  /// _moving3d is 3D character [c] moving as [body] is, with the motion
  /// _move3dOf chose, its feet keeping up with the ground; turned side on the
  /// way it goes, and in a game seen from above, its back to the reader going
  /// up. Its scene's own motions give way to the game's; standing, it does
  /// what it was made to.
  Character3dElement _moving3d(
      Character3dElement c, GameBody body, int frameRate, int frame) {
    var h = body.heading;
    // Its view's turn, in half turns: a quarter round puts its side to the
    // reader.
    var turn = h == Offset.zero
        ? c.turn
        : h.dy < 0 && h.dx == 0
            ? 1.0
            : h.dy > 0 && h.dx == 0
                ? 0.0
                : h.dx < 0
                    ? 0.5
                    : -0.5;
    var kind = body.move3d;
    var rate = math.max(1, frameRate);
    var start = frame / rate - (clock - body.since);
    var pace = c.base.play.as == PlayAs.topDown
        ? body.velocity.distance
        : body.velocity.dx.abs();
    var height = math.max(1.0, c.height);
    // A walk carries a body about 0.8 of its height a second, a run 1.9.
    var stride = kind == "Run" ? 1.9 : 0.8;
    var strike = kind == "Punch" || kind == "Kick";
    var p = c.performance.copyWith(clips: [
      if (kind != null)
        MotionClip3d(
            kind: kind,
            start: start,
            // A strike once through, as quick as it is.
            length: strike ? strikeSeconds(kind) : 3600,
            speed: kind == "Jump" || strike
                ? 1
                : (pace / (stride * height)).clamp(0.5, 2.5).toDouble()),
    ]);
    return c.performing(p).copyWith(turn: turn);
  }

  void reset() {
    bodies.clear();
    clock = 0;
    camera = Offset.zero;
    input.clear();
    _started = false;
    counts.clear();
    gone.clear();
    toggled.clear();
    _touching.clear();
    events.clear();
    hitsTaken.clear();
  }
}

/// GameEvent is something the game asks of the canvas: a sound element
/// played from its start, another scene, an element pressed, the game
/// started again, or ended.
class GameEvent {
  final String? sound;

  /// scene is a scene to go to, by id or name; [next] the one after this,
  /// and [restart] the game's first (see CanvasDocument.gameStart).
  final String? scene;
  final bool next;
  final bool restart;
  final String? press;

  /// touched is an element a player has started to touch, whose clips
  /// start on a touch.
  final String? touched;

  /// hit is an element (or one copy of one reused, by its key) a player
  /// has punched or kicked, whose clips start on a hit.
  final String? hit;

  /// counted is a count changed, by id, and where it has got to.
  final (String, int)? counted;
  final bool stop;

  /// soundFrom is where across the page [sound] is set off -- the instance
  /// of an element reused that was touched -- or null for its own place.
  final double? soundFrom;
  const GameEvent(
      {this.sound,
      this.soundFrom,
      this.scene,
      this.next = false,
      this.restart = false,
      this.press,
      this.touched,
      this.hit,
      this.counted,
      this.stop = false});
}

/// gameTouchArea is the part of [box] ([e]'s, where it is now) a game
/// touches: a sprite's drawn part unless it is set to be touched all over;
/// all of anything else.
Rect gameTouchArea(CanvasElement e, Rect box) =>
    e is SpriteElement && !e.base.play.touchWhole ? e.touchIn(box) : box;

/// tileGround is [map]'s solid layers' tiles on [frame] as boxes on the
/// canvas, only those inside the map's box. Each run of tiles along a row is
/// one box, so a player walking along it never catches on a seam. A solid
/// layer is taken to move with the rest of the map: its parallax is not
/// followed.
///
/// [at] is where the map is, where it is not where its keyframes put it: as
/// its clips have it.
List<Rect> tileGround(TileMapElement map, int frame, {Rect? at}) {
  var rows = <int, Set<int>>{};
  var (c0, r0, c1, r1) = map.window;
  for (var l in map.layers) {
    if (!l.solid || !l.visible || l.isObjects) continue;
    for (var k in l.cells.keys) {
      var c = colOf(k), r = rowOf(k);
      if (c < c0 || c > c1 || r < r0 || r > r1) continue;
      (rows[r] ??= {}).add(c);
    }
  }
  var shift = (at ?? map.boundsAt(frame)).topLeft - map.bounds.topLeft;
  var out = <Rect>[];
  for (var MapEntry(key: r, value: set) in rows.entries) {
    var cols = set.toList()..sort();
    var start = cols.first, end = cols.first;
    void close() => out.add(Rect.fromPoints(
            map.cellRect(start, r).topLeft, map.cellRect(end, r).bottomRight)
        .shift(shift));
    for (var c in cols.skip(1)) {
      if (c == end + 1) {
        end = c;
        continue;
      }
      close();
      start = end = c;
    }
    close();
  }
  return out;
}
