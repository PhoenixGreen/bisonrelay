import 'package:bruig/plugin_system/canvas/model/mix.dart';

// strip_presets.dart is the presets a strip's own cards come with -- its EQ,
// its compressor, the master's limiter, a Ducker -- as the prototype's
// "Presets ▾" on every device: a few starting points by name, beside the
// ones saved (see device_presets.dart).

/// StripPart is one of a strip's own cards that has presets.
enum StripPart {
  eq("EQ"),
  comp("Compressor"),
  limiter("Limiter"),
  duck("Ducker");

  final String label;
  const StripPart(this.label);

  static StripPart? fromName(Object? name) =>
      values.where((p) => p.name == name).firstOrNull;
}

/// LimiterSet is a limiter's settings: its ceiling, look-ahead and release.
typedef LimiterSet = ({double ceilingDb, double aheadMs, double releaseMs});

/// eqPresets are an EQ's starting points, switched on.
const eqPresets = <(String, Eq)>[
  (
    "Voice clarity",
    Eq(
        on: true,
        lowCut: EqBand(80, on: true),
        lowMid: EqBand(300, gainDb: -2, q: 1),
        presence: EqBand(5000, gainDb: 3, q: 1)),
  ),
  (
    "Warm",
    Eq(on: true, low: EqBand(120, gainDb: 3), high: EqBand(8000, gainDb: -2)),
  ),
  (
    "Bright",
    Eq(
        on: true,
        presence: EqBand(5000, gainDb: 2, q: 1),
        high: EqBand(8000, gainDb: 3)),
  ),
  (
    "Telephone",
    Eq(
        on: true,
        lowCut: EqBand(300, on: true),
        mid: EqBand(1000, gainDb: 4, q: 1),
        highCut: EqBand(3400, on: true)),
  ),
];

/// compPresets are a compressor's.
const compPresets = <(String, Dynamics)>[
  (
    "Gentle",
    Dynamics(on: true, threshold: -18, ratio: 2, attackMs: 20, releaseMs: 200)
  ),
  (
    "Punchy",
    Dynamics(on: true, threshold: -20, ratio: 4, attackMs: 5, releaseMs: 80)
  ),
  (
    "Voice",
    Dynamics(
        on: true,
        threshold: -22,
        ratio: 3,
        attackMs: 10,
        releaseMs: 150,
        makeupDb: 3)
  ),
  (
    "Glue",
    Dynamics(on: true, threshold: -12, ratio: 2, attackMs: 30, releaseMs: 200)
  ),
];

/// limiterPresets are the master limiter's.
const limiterPresets = <(String, LimiterSet)>[
  ("Safe", (ceilingDb: -1, aheadMs: 5, releaseMs: 50)),
  ("Loud", (ceilingDb: -0.3, aheadMs: 3, releaseMs: 30)),
  ("Broadcast", (ceilingDb: -2, aheadMs: 5, releaseMs: 100)),
];

/// duckPresets are a Ducker's.
const duckPresets = <(String, Ducking)>[
  ("Gentle", Ducking(on: true, depthDb: -6, attack: 0.4, release: 1)),
  ("Deep", Ducking(on: true, depthDb: -15, attack: 0.2, release: 0.8)),
  ("Quick", Ducking(on: true, depthDb: -10, attack: 0.1, release: 0.4)),
];
