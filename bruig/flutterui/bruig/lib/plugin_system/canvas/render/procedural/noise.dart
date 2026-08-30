import 'dart:math' as math;

// noise.dart is the randomness every generated background draws from.
//
// Two kinds, and the difference matters. [hash] is white noise: given the same
// three integers it always returns the same number, and neighbouring inputs
// are unrelated. That is what scatters things -- which cell is lit, how big
// this disc is, which glyph falls here. [ValueNoise] is smooth: neighbouring
// inputs return *nearly* the same number, so it makes fields that flow --
// contours, waves, blooms of colour.
//
// Both are pure functions of a seed and a position. Nothing here holds state
// and nothing calls Random(), which is the whole reason a background is
// reproducible: the same document renders the same picture on the stage at
// 400px, in the export at 2400px, and on somebody else's machine a year later.
// A Random() walked in draw order would give a different picture the moment
// anything was drawn in a different order or skipped.

/// hash returns a deterministic value in 0..1 from three integers.
///
/// A cheap integer mix rather than anything cryptographic. What is wanted is
/// that adjacent inputs look unrelated to the eye, which this does, and that
/// it costs nothing -- it runs a few hundred thousand times per frame of a
/// dense background.
double hash(int seed, int x, int y) {
  var h = seed * 374761393 + x * 668265263 + y * 2147483647;
  h = (h ^ (h >> 13)) * 1274126177;
  h = h ^ (h >> 16);
  return (h & 0x7FFFFFFF) / 0x7FFFFFFF;
}

/// hashRange is [hash] mapped onto a span, for the many places that want "a
/// size between this and that".
double hashRange(int seed, int x, int y, double lo, double hi) =>
    lo + hash(seed, x, y) * (hi - lo);

/// SeededRandom is a stream of numbers from a seed, for the generators that
/// scatter a fixed count of things rather than filling a grid.
///
/// Deliberately not dart:math's Random even though that also takes a seed: a
/// generator that draws N discs wants to be able to draw the first 40 of 200
/// when the density is turned down and have them be *the same* first 40, and
/// that only works if the sequence is fixed and consumed in a fixed order.
/// Writing the generator out makes that guarantee visible instead of implied.
class SeededRandom {
  int _state;

  SeededRandom(int seed) : _state = (seed * 2654435761) & 0x7FFFFFFF {
    if (_state == 0) _state = 1;
  }

  /// next is the next value in 0..1.
  double next() {
    _state ^= (_state << 13) & 0x7FFFFFFF;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0x7FFFFFFF;
    return (_state & 0x7FFFFFFF) / 0x7FFFFFFF;
  }

  double range(double lo, double hi) => lo + next() * (hi - lo);
  int intRange(int lo, int hi) =>
      hi <= lo ? lo : lo + (next() * (hi - lo)).floor();
}

/// ValueNoise is smooth 2D noise: a lattice of random values, interpolated.
///
/// Value noise rather than Perlin or simplex. Perlin's gradients give a
/// slightly nicer distribution and simplex is faster in high dimensions;
/// neither difference is visible in a background, and both are considerably
/// more code to read.
class ValueNoise {
  final int seed;
  const ValueNoise(this.seed);

  /// at samples the field. [x] and [y] are in lattice units -- one unit is one
  /// cell of the underlying grid, so the caller scales the coordinates to
  /// choose how large the features are.
  double at(double x, double y) {
    var x0 = x.floor(), y0 = y.floor();
    var fx = _smooth(x - x0), fy = _smooth(y - y0);

    var a = hash(seed, x0, y0);
    var b = hash(seed, x0 + 1, y0);
    var c = hash(seed, x0, y0 + 1);
    var d = hash(seed, x0 + 1, y0 + 1);

    return _lerp(_lerp(a, b, fx), _lerp(c, d, fx), fy);
  }

  /// fbm sums several octaves of [at], each half the amplitude and twice the
  /// frequency of the last. It is what turns noise that looks like a blurred
  /// grid into noise that looks like landscape, and every generator here that
  /// wants an organic field uses it rather than a single octave.
  double fbm(double x, double y, {int octaves = 4}) {
    var sum = 0.0, amp = 1.0, norm = 0.0, freq = 1.0;
    for (var i = 0; i < octaves; i++) {
      sum += at(x * freq, y * freq) * amp;
      norm += amp;
      amp *= 0.5;
      freq *= 2;
    }
    return norm == 0 ? 0 : sum / norm;
  }

  /// _smooth is the smoothstep that removes the creases. Interpolating the
  /// lattice linearly leaves a visible diamond grid, because the derivative
  /// jumps at every cell boundary.
  static double _smooth(double t) => t * t * (3 - 2 * t);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// angleNoise is a flow field: a direction at every point, varying smoothly.
///
/// What bends the ribbons in the wave styles. Its own function because the
/// mapping from a 0..1 field onto an angle wants more than a full turn of
/// range -- with less, the field never doubles back and the ribbons all drift
/// the same way.
double angleNoise(ValueNoise noise, double x, double y, double turns) =>
    noise.fbm(x, y, octaves: 3) * turns * 2 * math.pi;
