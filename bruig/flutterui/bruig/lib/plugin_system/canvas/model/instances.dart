import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble, jsonStr;

// instances.dart is an element reused: drawn many times -- twenty coins --
// as one element, one channel and one row, each instance with its own place
// and start. Rule 3 of the motion chain: left of the Instances device is
// shared by every instance; right of it, each has its own.

/// VaryHow is how a setting differs from instance to instance.
enum VaryHow {
  same("Same for all"),
  byOrder("By order"),
  random("Random"),
  fromMiddle("From the middle");

  final String label;
  const VaryHow(this.label);

  static VaryHow fromName(String? name) =>
      values.where((h) => h.name == name).firstOrNull ?? same;
}

/// VaryWhat is a setting that can differ from instance to instance, with
/// how far it goes at most.
enum VaryWhat {
  /// starts: seconds later, at most.
  starts("Starts", 0, 10, 0.5, "s"),

  /// size: a share bigger (smaller, negative), at most.
  size("Size", -0.9, 2, 0.3, ""),

  /// speed: a share faster (slower, negative), at most.
  speed("Speed", -0.9, 2, 0.3, ""),

  /// colour: degrees round the hue, at most.
  colour("Colour", -180, 180, 60, "°");

  final String label;
  final double min, max, initial;
  final String unit;
  const VaryWhat(this.label, this.min, this.max, this.initial, this.unit);
}

/// Vary is how one setting differs: how, and by at most how much.
class Vary {
  final VaryHow how;
  final double amount;
  const Vary(this.how, this.amount);
}

/// ElementInstance is one instance: its own id, kept as instances come and
/// go (a game's collected coin is this id), its place from the element's,
/// and how much later than the others it starts.
class ElementInstance {
  final String id;
  final double dx, dy;
  final double start;

  const ElementInstance(this.id, {this.dx = 0, this.dy = 0, this.start = 0});

  ElementInstance copyWith({double? dx, double? dy, double? start}) =>
      ElementInstance(id,
          dx: dx ?? this.dx, dy: dy ?? this.dy, start: start ?? this.start);

  Map<String, dynamic> toJson() => {
        "id": id,
        if (dx != 0) "dx": dx,
        if (dy != 0) "dy": dy,
        if (start != 0) "start": start,
      };

  static ElementInstance? fromJson(Object? json) {
    if (json is! Map) return null;
    var id = jsonStr(json["id"]);
    if (id == null || id.isEmpty) return null;
    return ElementInstance(id,
        dx: jsonDouble(json["dx"], 0),
        dy: jsonDouble(json["dy"], 0),
        start: jsonDouble(json["start"], 0).clamp(0.0, 3600.0));
  }
}

/// instanceKey names instance [instance] of element [element] wherever a
/// game keeps its state by name: a coin collected is gone by this.
String instanceKey(String element, String instance) => "$element#$instance";

/// maxInstances is the most instances an element has.
const int maxInstances = 500;

/// InstanceLayout is how Lay out places the instances.
enum InstanceLayout {
  line("In a line"),
  grid("In a grid"),
  circle("In a circle"),
  scatter("Scattered");

  final String label;
  const InstanceLayout(this.label);
}

/// InstanceSet is an element's instances (ElementMotion.instances): each
/// one's place and start, how the rest differs between them, and the seed
/// Random draws from. Immutable.
class InstanceSet {
  final List<ElementInstance> items;
  final Map<VaryWhat, Vary> vary;
  final int seed;

  const InstanceSet(
      {this.items = const [], this.vary = const {}, this.seed = 1});

  int get count => items.length;

  Vary varyOf(VaryWhat w) => vary[w] ?? Vary(VaryHow.same, w.initial);

  /// share is how far along instance [i] is for [w], nought to one.
  double share(VaryWhat w, int i) {
    var n = items.length;
    switch (varyOf(w).how) {
      case VaryHow.same:
        return 0;
      case VaryHow.byOrder:
        return n <= 1 ? 0 : i / (n - 1);
      case VaryHow.random:
        return _random(seed * 7919 + w.index * 104729 + i);
      case VaryHow.fromMiddle:
        if (n <= 1) return 0;
        var mid = (n - 1) / 2;
        return (i - mid).abs() / mid;
    }
  }

  double _by(VaryWhat w, int i) => share(w, i) * varyOf(w).amount;

  /// startOf is how many seconds later than the element instance [i]
  /// starts.
  double startOf(int i) =>
      (i < items.length ? items[i].start : 0) + _by(VaryWhat.starts, i);

  double speedOf(int i) => math.max(0.05, 1 + _by(VaryWhat.speed, i));

  double sizeOf(int i) => math.max(0.05, 1 + _by(VaryWhat.size, i));

  /// hueOf is how many degrees instance [i]'s colours are turned.
  double hueOf(int i) => _by(VaryWhat.colour, i);

  /// uniform is whether the instances differ only in where they are: drawn
  /// once and stamped at each place.
  bool get uniform =>
      items.every((x) => x.start == 0) &&
      VaryWhat.values
          .every((w) => varyOf(w).how == VaryHow.same || varyOf(w).amount == 0);

  InstanceSet copyWith(
          {List<ElementInstance>? items,
          Map<VaryWhat, Vary>? vary,
          int? seed}) =>
      InstanceSet(
          items: items ?? this.items,
          vary: vary ?? this.vary,
          seed: seed ?? this.seed);

  InstanceSet withVary(VaryWhat w, Vary v) => copyWith(vary: {...vary, w: v});

  /// withCount is [n] instances: those kept, and new ones carrying on the
  /// last two's step -- or [gap] to the right, from one.
  InstanceSet withCount(int n, {double gap = 60}) {
    n = n.clamp(1, maxInstances);
    if (n <= items.length) return copyWith(items: items.sublist(0, n));
    var out = [...items];
    var taken = {for (var x in items) x.id};
    var next = 0;
    String fresh() {
      while (taken.contains("i$next")) {
        next++;
      }
      taken.add("i$next");
      return "i$next";
    }

    if (out.isEmpty) out.add(ElementInstance(fresh()));
    var (sx, sy) = out.length >= 2
        ? (
            out.last.dx - out[out.length - 2].dx,
            out.last.dy - out[out.length - 2].dy
          )
        : (gap, 0.0);
    while (out.length < n) {
      var last = out.last;
      out.add(ElementInstance(fresh(), dx: last.dx + sx, dy: last.dy + sy));
    }
    return copyWith(items: out);
  }

  /// laidOut is the instances placed by [layout], [gap] apart -- [columns]
  /// across in a grid; a circle's [gap] is the step round it; a scatter's
  /// over a square [gap] times the count's root on a side.
  InstanceSet laidOut(InstanceLayout layout,
      {double gap = 60, int columns = 5}) {
    var n = items.length;
    var placed = <(double, double)>[];
    switch (layout) {
      case InstanceLayout.line:
        for (var i = 0; i < n; i++) {
          placed.add((i * gap, 0));
        }
      case InstanceLayout.grid:
        var cols = math.max(1, columns);
        for (var i = 0; i < n; i++) {
          placed.add(((i % cols) * gap, (i ~/ cols) * gap));
        }
      case InstanceLayout.circle:
        var r = n <= 1 ? 0.0 : gap * n / (2 * math.pi);
        for (var i = 0; i < n; i++) {
          var a = 2 * math.pi * i / math.max(1, n) - math.pi / 2;
          // The first at the element's own place, the circle round from it.
          placed.add((r * math.cos(a), r * math.sin(a) + r));
        }
      case InstanceLayout.scatter:
        var side = gap * math.sqrt(n.toDouble());
        for (var i = 0; i < n; i++) {
          placed.add(i == 0
              ? (0, 0)
              : (
                  _random(seed * 31 + i * 2) * side,
                  _random(seed * 31 + i * 2 + 1) * side
                ));
        }
    }
    return copyWith(items: [
      for (var (i, x) in items.indexed)
        x.copyWith(dx: placed[i].$1, dy: placed[i].$2),
    ]);
  }

  Map<String, dynamic> toJson() => {
        "items": [for (var x in items) x.toJson()],
        if (vary.isNotEmpty)
          "vary": {
            for (var e in vary.entries)
              e.key.name: {"how": e.value.how.name, "amount": e.value.amount},
          },
        if (seed != 1) "seed": seed,
      };

  static InstanceSet? fromJson(Object? json) {
    if (json is! Map) return null;
    var items = <ElementInstance>[];
    var ids = <String>{};
    if (json["items"] case List raw) {
      for (var x in raw.take(maxInstances)) {
        if (ElementInstance.fromJson(x) case var i? when ids.add(i.id)) {
          items.add(i);
        }
      }
    }
    if (items.isEmpty) return null;
    return InstanceSet(
      items: items,
      vary: {
        if (json["vary"] case Map raw)
          for (var w in VaryWhat.values)
            if (raw[w.name] case Map v)
              w: Vary(VaryHow.fromName(jsonStr(v["how"])),
                  jsonDouble(v["amount"], w.initial).clamp(w.min, w.max)),
      },
      seed: json["seed"] is int ? json["seed"] as int : 1,
    );
  }
}

/// _random is a number from nought to one, the same for the same [n].
double _random(int n) {
  var x = (n * 0x9E3779B1) & 0xFFFFFFFF;
  x ^= x >> 15;
  x = (x * 0x85EBCA77) & 0xFFFFFFFF;
  x ^= x >> 13;
  x = (x * 0xC2B2AE3D) & 0xFFFFFFFF;
  x ^= x >> 16;
  return x / 0xFFFFFFFF;
}
