import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/world_shapes.dart';

// world_map.dart is the world's countries as shapes, for the tile map's
// drawn way (Ken, 2026-11-17: the improvements report's leftovers): read
// from world_shapes.dart once, the first time a map is drawn, and found by
// a sheet's place names -- two- or three-letter codes, or names.

/// WorldCountry is one country: its codes, its name, and its outlines in
/// degrees (longitude, latitude).
class WorldCountry {
  final String a2, a3, name;
  final List<List<Offset>> rings;
  final Rect bounds;

  /// main is the box of its largest outline: its main land, not the
  /// islands far off it (France without French Guiana), for framing and
  /// for its label.
  Rect get main {
    Rect? best;
    for (var r in rings) {
      var b = _boxOf(r);
      if (best == null || b.width * b.height > best.width * best.height) {
        best = b;
      }
    }
    return best ?? bounds;
  }

  WorldCountry(this.a2, this.a3, this.name, this.rings)
      : bounds = rings.expand((r) => r).fold<Rect?>(
                null,
                (b, p) => b == null
                    ? Rect.fromLTWH(p.dx, p.dy, 0, 0)
                    : b.expandToInclude(Rect.fromLTWH(p.dx, p.dy, 0, 0))) ??
            Rect.zero;
}

Rect _boxOf(List<Offset> ring) {
  var l = ring.first.dx, r = l, t = ring.first.dy, b = t;
  for (var p in ring) {
    if (p.dx < l) l = p.dx;
    if (p.dx > r) r = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dy > b) b = p.dy;
  }
  return Rect.fromLTRB(l, t, r, b);
}

List<WorldCountry>? _countries;
Map<String, WorldCountry>? _byKey;

/// worldCountries is every country, read once.
List<WorldCountry> get worldCountries {
  if (_countries case var c?) return c;
  var out = <WorldCountry>[];
  for (var line in worldShapesData.trim().split("\n")) {
    var parts = line.split("|");
    if (parts.length < 4) continue;
    var rings = <List<Offset>>[];
    for (var ring in parts[3].split(";")) {
      var x = 0, y = 0;
      var pts = <Offset>[];
      for (var step in ring.split(" ")) {
        var xy = step.split(",");
        if (xy.length != 2) continue;
        x += int.parse(xy[0]);
        y += int.parse(xy[1]);
        pts.add(Offset(x / 10, y / 10));
      }
      if (pts.length >= 3) rings.add(pts);
    }
    // Antarctica wraps the pole: no use on a flat map of where things are.
    if (parts[0] == "AQ") continue;
    out.add(WorldCountry(parts[0], parts[1], parts[2], rings));
  }
  _countries = out;
  return out;
}

/// countryFor is the country [place] names: its two- or three-letter code
/// (GB and UK, GR and EL alike) or its name, any case; null for none.
WorldCountry? countryFor(String place) {
  _byKey ??= {
    for (var c in worldCountries) ...{
      if (c.a2.isNotEmpty) c.a2: c,
      if (c.a3.isNotEmpty) c.a3: c,
      c.name.toUpperCase(): c,
    },
  };
  var key = place.trim().toUpperCase();
  const aliases = {
    "UK": "GB",
    "EL": "GR",
    "USA": "US",
    "UNITED KINGDOM": "GB",
    "ENGLAND": "GB",
    "SCOTLAND": "GB",
    "WALES": "GB",
    "UNITED STATES": "US",
    "RUSSIA": "RU",
    "SOUTH KOREA": "KR",
    "NORTH KOREA": "KP",
    "CZECH REPUBLIC": "CZ",
    "IVORY COAST": "CI",
  };
  return _byKey![aliases[key] ?? key];
}

/// mapView is the part of the world to show for [countries]: their outlines'
/// box with room round it, or the whole world for none.
Rect mapView(Iterable<WorldCountry> countries) {
  Rect? box;
  for (var c in countries) {
    box = box == null ? c.main : box.expandToInclude(c.main);
  }
  if (box == null) return const Rect.fromLTRB(-170, -58, 180, 84);
  var padX = math.max(4.0, box.width * 0.12),
      padY = math.max(3.0, box.height * 0.12);
  return Rect.fromLTRB(
      box.left - padX, box.top - padY, box.right + padX, box.bottom + padY);
}
