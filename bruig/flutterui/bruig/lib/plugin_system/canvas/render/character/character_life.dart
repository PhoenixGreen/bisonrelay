import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_life.dart is what a character does on its own: blinking every
// few seconds, breathing, glancing about.
//
// None of it is in the document. It is worked out from the time and a
// number made from the character's id, so two characters do not blink
// together, the same character blinks on the same frames every time it is
// played, and an exported video blinks where the stage did. A random number
// would do none of those.

/// LifeAt is a character's own movement at one moment.
class LifeAt {
  /// blink is how shut the eyes are, 0 to 1.
  final double blink;

  /// breath is how far into a breath, 0 (out) to 1 (in).
  final double breath;

  /// lookX and lookY are added to where the eyes look.
  final double lookX;
  final double lookY;

  const LifeAt(
      {this.blink = 0, this.breath = 0, this.lookX = 0, this.lookY = 0});

  static const LifeAt none = LifeAt();
}

/// lifeAt is [e]'s own movement on [frame], at [frameRate].
LifeAt lifeAt(CharacterElement e, int frame, int frameRate) {
  var life = e.life;
  if (!life.any) return LifeAt.none;
  var t = frame / (frameRate <= 0 ? 12 : frameRate);
  var seed = _fnv(e.id);
  return LifeAt(
    blink: life.blink ? _blinkAt(t, seed) : 0,
    breath: life.breathe
        ? (1 - math.cos(2 * math.pi * t / _breathSeconds)) / 2
        : 0,
    lookX: life.glance ? _glanceAt(t, seed, 0) : 0,
    lookY: life.glance ? _glanceAt(t, seed, 1) * 0.5 : 0,
  );
}

const double _breathSeconds = 3.8;

/// _blinkSeconds is how long a blink takes, shut and open again.
const double _blinkSeconds = 0.18;

/// _blinkAt is how shut the eyes are at [t]: the first blink a second and a
/// bit in, so a character is never caught blinking on the first frame, and
/// each next one 2.6 to 5 seconds after the last.
double _blinkAt(double t, int seed) {
  var at = 1.2 + _unit(seed, 0) * 0.8;
  for (var k = 1; at <= t; k++) {
    var into = t - at;
    if (into < _blinkSeconds) {
      // Shut quickly, open a little more slowly.
      var half = _blinkSeconds * 0.4;
      return into < half ? into / half : 1 - (into - half) / (_blinkSeconds - half);
    }
    at += 2.6 + _unit(seed, k) * 2.4;
  }
  return 0;
}

/// _glanceAt is where the eyes have wandered to on one axis at [t]: a new
/// spot every 2.5 to 5 seconds, moved to quickly, held, and back to the
/// middle every third glance.
double _glanceAt(double t, int seed, int axis) {
  var at = 0.0, from = 0.0, to = 0.0;
  for (var k = 0;; k++) {
    var next = at + 2.5 + _unit(seed, 1000 + k) * 2.5;
    if (next > t) {
      var into = ((t - at) / 0.12).clamp(0.0, 1.0);
      return from + (to - from) * into;
    }
    from = to;
    to = k % 3 == 2 ? 0 : (_unit(seed, 2000 + k * 2 + axis) - 0.5) * 0.7;
    at = next;
  }
}

/// _unit is a number from 0 to 1 that depends only on [seed] and [n].
double _unit(int seed, int n) {
  var h = (seed ^ (n * 0x9E3779B1)) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
  h = h ^ (h >> 16);
  return h / 0xFFFFFFFF;
}

/// _fnv is a hash of [s] that is the same on every machine and every run,
/// which String.hashCode is not promised to be.
int _fnv(String s) {
  var h = 0x811C9DC5;
  for (var c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}
