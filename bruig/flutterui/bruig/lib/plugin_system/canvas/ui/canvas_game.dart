import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';

// canvas_game.dart is a canvas played as a game: what is pressed -- keys, a
// controller -- read as the document's actions; each played element moved
// by them a step at a time, falling and landing on what is solid; the view
// following the player; and the canvas as it now looks, for the stage to
// draw.
//
// Nothing here is written into the document. A game played is somebody
// playing it; stopped, everything is where it was put.

/// GameInput is what is held down: keys by id, and controller inputs.
class GameInput {
  final Set<int> keys = {};
  final Set<PadInput> pad = {};
  final Set<String> _was = {};

  /// down is whether [action] is held.
  bool down(ControlAction action) =>
      action.keys.any(keys.contains) || action.pad.any(pad.contains);

  /// pressed is whether [action] went down since the last step.
  bool pressed(ControlAction action) =>
      down(action) && !_was.contains(action.id);

  /// endStep remembers what is held, for [pressed].
  void endStep(List<ControlAction> actions) {
    _was
      ..clear()
      ..addAll([for (var a in actions) if (down(a)) a.id]);
  }

  /// deadZone is how far a stick goes before it counts.
  static const double deadZone = 0.35;

  /// stick sets a stick axis's two directions from its value.
  void stick(PadInput negative, PadInput positive, double value) {
    pad.remove(negative);
    pad.remove(positive);
    if (value <= -deadZone) pad.add(negative);
    if (value >= deadZone) pad.add(positive);
  }

  /// gamepad takes a controller's event.
  void gamepad(NormalizedGamepadEvent e) {
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
        stick(PadInput.leftStickLeft, PadInput.leftStickRight, e.value);
      // Up is negative on a screen, whatever the stick reports.
      case GamepadAxis.leftStickY:
        stick(PadInput.leftStickUp, PadInput.leftStickDown, e.value);
      case GamepadAxis.rightStickX:
        stick(PadInput.rightStickLeft, PadInput.rightStickRight, e.value);
      case GamepadAxis.rightStickY:
        stick(PadInput.rightStickUp, PadInput.rightStickDown, e.value);
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
    pad.clear();
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
}

/// GameRun is a game going.
class GameRun extends ChangeNotifier {
  final GameInput input = GameInput();
  final Map<String, GameBody> bodies = {};
  Offset camera = Offset.zero;

  /// controllers are the controllers connected, by name.
  List<String> get controllers => List.unmodifiable(_controllers);
  final List<String> _controllers = [];
  StreamSubscription<NormalizedGamepadEvent>? _pads;

  /// listen takes the controllers' events -- where there are any to take.
  Future<void> listen() async {
    try {
      var list = await Gamepads.list();
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

  @override
  void dispose() {
    _pads?.cancel();
    super.dispose();
  }

  GameBody _body(String id) => bodies.putIfAbsent(id, GameBody.new);

  /// step moves everything played in [doc] on by [dt] seconds, on [frame].
  void step(CanvasDocument doc, int frame, double dt) {
    var actions = {for (var a in doc.controlsNow) a.id: a};
    bool down(String id) => actions[id] != null && input.down(actions[id]!);
    bool pressed(String id) =>
        actions[id] != null && input.pressed(actions[id]!);
    var dx = (down("right") ? 1 : 0) - (down("left") ? 1 : 0);
    var dy = (down("down") ? 1 : 0) - (down("up") ? 1 : 0);

    var solids = [
      for (var e in doc.elements)
        if (e.base.play.as == PlayAs.solid) e.boundsAt(frame),
    ];
    var page = doc.size.rect;
    // The ground under everything: the canvas's bottom edge.
    var floor = Rect.fromLTRB(-1e6, page.bottom, 1e6, page.bottom + 1e5);

    Offset? follow;
    for (var e in doc.elements) {
      var spec = e.base.play;
      if (!spec.as.moves) continue;
      var body = _body(e.id);
      var box = e.boundsAt(frame);
      switch (spec.as) {
        case PlayAs.platformer:
          body.velocity = Offset(dx * spec.speed,
              body.velocity.dy + spec.gravity * dt);
          if (pressed("jump") && body.onGround) {
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
        case PlayAs.none || PlayAs.solid:
          break;
      }
      if (dx != 0) body.facing = dx.sign;
      if (spec.follow && spec.as != PlayAs.camera && follow == null) {
        follow = box.center + body.at;
      }
    }
    // The view, over the player: across always, up and down for a game
    // seen from above -- never left of where the canvas starts.
    if (follow case var f?) {
      var topDown = doc.elements
          .any((e) => e.base.play.as == PlayAs.topDown && e.base.play.follow);
      camera = Offset(math.max(0, f.dx - page.width / 2),
          topDown ? math.max(0, f.dy - page.height / 2) : 0);
    }
    input.endStep(doc.controlsNow);
    notifyListeners();
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
  CanvasDocument view(CanvasDocument doc) {
    var shifted = <CanvasElement>[];
    for (var e in doc.elements) {
      if (e is BackgroundElement) {
        shifted.add(_withCamera(e));
        continue;
      }
      var body = bodies[e.id];
      var move = (body?.at ?? Offset.zero) - camera;
      var base = e.base.copyWith(x: e.x + move.dx, y: e.y + move.dy);
      // A played element is the game's, not the timeline's.
      if (body != null) base = base.copyWith(clearTrack: true);
      CanvasElement next = e.rebase(base);
      if (next is SpriteElement && body != null) next = _animated(next, body);
      shifted.add(next);
    }
    var background = doc.background;
    if (background.parallax case var p?) {
      background = background.copyWith(parallax: _parallaxAt(p));
    }
    return doc.copyWith(elements: shifted, background: background);
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

  /// _animated is [s] moving as [body] is: its walk, its jump or standing
  /// still -- whichever of its actions is called that -- facing the way it
  /// goes.
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
    var action = !body.onGround && body.velocity.dy.abs() > 1
        ? named(["jump", "fall"])
        : moving
            ? named(["walk", "run", "move"])
            : named(["idle", "stand"]);
    return s.copyWith(
        action: action ?? s.action,
        cues: const [],
        facing: body.facing < 0 ? SpriteFacing.left : SpriteFacing.right);
  }

  void reset() {
    bodies.clear();
    camera = Offset.zero;
    input.clear();
  }
}
