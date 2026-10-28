import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';

// tile_terrain.dart is a terrain painted onto a map, as Godot paints one:
// each cell painted -- and each round it -- given the tile whose corners
// and sides match what is about it, so water painted into grass finds its
// own shore, a path its own bends. And a set's tiles tagged from their
// colours: each corner, side and middle of a tile told apart by which
// terrain's own tile it looks like, or as nothing where it is clear.
//
// A set told apart by corners keeps a terrain at each corner between
// cells: painting a cell makes its four that terrain, and every cell
// touching them takes the tile that matches its four -- into an empty
// cell too, an edge spreading out round a patch. A set told apart by sides
// keeps a terrain in each cell's middle: a cell joins its neighbours of
// the same terrain, and only cells already of the set are changed.

/// paintTerrain is [cells] -- one layer's, by [cellKey] -- with terrain
/// [terrain] of [set], of tile set [source], painted at [at]: the cells
/// painted, and the cells round them chosen again to match.
Map<int, int> paintTerrain(Map<int, int> cells,
    {required int source,
    required TerrainSet set,
    required int terrain,
    required Iterable<(int, int)> at,
    math.Random? rng}) {
  var out = Map.of(cells);
  var painted = at.toSet();
  if (painted.isEmpty || set.tags.isEmpty) return out;

  /// tagOf is the tag of the tile in a cell, when it is one of the set's,
  /// unturned; null when it is not -- a tile of another set, or turned --
  /// and so not this set's to change.
  List<int>? tagOf(int c, int r) {
    var w = cells[cellKey(c, r)];
    if (w == null) return null;
    var t = TileRef(w);
    if (t.source != source || t.turned) return null;
    return set.tags[t.index];
  }

  bool foreign(int c, int r) => cells.containsKey(cellKey(c, r)) && tagOf(c, r) == null;

  var around = <(int, int)>{
    for (var (c, r) in painted)
      for (var dr = -1; dr <= 1; dr++)
        for (var dc = -1; dc <= 1; dc++) (c + dc, r + dr),
  };

  if (set.mode == TerrainMode.corners) {
    // A corner between cells is named by the cell it is the top left of.
    var made = <(int, int), int>{
      for (var (c, r) in painted) ...{(c, r): terrain, (c + 1, r): terrain, (c, r + 1): terrain, (c + 1, r + 1): terrain},
    };
    int corner(int vx, int vy) {
      if (made[(vx, vy)] case var t?) return t;
      for (var (c, r, place) in [
        (vx - 1, vy - 1, tagBottomRight),
        (vx, vy - 1, tagBottomLeft),
        (vx - 1, vy, tagTopRight),
        (vx, vy, tagTopLeft),
      ]) {
        if (tagOf(c, r) case var tag?) return tag[place];
      }
      return -1;
    }

    for (var (c, r) in around) {
      if (!painted.contains((c, r)) && foreign(c, r)) continue;
      var want = {
        tagTopLeft: corner(c, r),
        tagTopRight: corner(c + 1, r),
        tagBottomRight: corner(c + 1, r + 1),
        tagBottomLeft: corner(c, r + 1),
      };
      var k = cellKey(c, r);
      if (want.values.every((t) => t < 0)) {
        // All nothing: no tile. A cell of the set left like that is cleared.
        if (tagOf(c, r) != null) out.remove(k);
        continue;
      }
      // An empty cell round the painting takes an edge only where one fits
      // exactly -- a patch's edge into nothing; a set with no edges into
      // nothing leaves it empty.
      var exact = !painted.contains((c, r)) && !cells.containsKey(k);
      if (_best(set, cells[k], source, rng, (tag) {
        var score = 0;
        for (var e in want.entries) {
          if (tag[e.key] == e.value) {
            score++;
          } else {
            if (exact) return null;
            score -= 10;
          }
        }
        return score;
      }) case var w?) {
        out[k] = w;
      }
    }
    return out;
  }

  // Told apart by sides: a terrain in each cell's middle.
  int? middle(int c, int r) => painted.contains((c, r)) ? terrain : tagOf(c, r)?[tagCentre];
  for (var (c, r) in around) {
    var x = middle(c, r);
    if (x == null || x < 0) continue;
    bool joins(int place) {
      var (dc, dr) = tagStep[place];
      return middle(c + dc, r + dr) == x;
    }

    // What each place wants: the cell's own terrain, or not -- null where
    // it does not matter: a corner of a set of 47 between two sides that
    // do not both join.
    var want = <int, bool?>{for (var p in tagSides) p: joins(p)};
    if (set.mode == TerrainMode.both) {
      for (var (p, a, b) in [
        (tagTopRight, tagTop, tagRight),
        (tagBottomRight, tagBottom, tagRight),
        (tagBottomLeft, tagBottom, tagLeft),
        (tagTopLeft, tagTop, tagLeft),
      ]) {
        want[p] = want[a]! && want[b]! ? joins(p) : null;
      }
    }
    var k = cellKey(c, r);
    if (_best(set, cells[k], source, rng, (tag) {
      if (tag[tagCentre] != x) return null;
      var score = 0;
      for (var e in want.entries) {
        if (e.value == null) continue;
        score += (tag[e.key] == x) == e.value ? 1 : -10;
      }
      return score;
    }) case var w?) {
      out[k] = w;
    }
  }
  return out;
}

/// _best is the set's tile that scores highest by [score] -- null for one
/// that will not do -- as a [TileRef] word: the one there already, of the
/// best, or one of them at random.
int? _best(TerrainSet set, int? now, int source, math.Random? rng, int? Function(List<int> tag) score) {
  int? top;
  var best = <int>[];
  for (var e in set.tags.entries) {
    var s = score(e.value);
    if (s == null) continue;
    if (top == null || s > top) {
      top = s;
      best = [e.key];
    } else if (s == top) {
      best.add(e.key);
    }
  }
  if (best.isEmpty) return null;
  if (now != null && TileRef(now).source == source && best.contains(TileRef(now).index)) return now;
  best.sort();
  var pick = rng == null ? best.first : best[rng.nextInt(best.length)];
  return TileRef.of(source, pick).word;
}

/// tagByColour is [set] with [tiles] of [s] tagged from their colours: at
/// each place its mode tells tiles apart by, the few pixels there taken as
/// the terrain whose sample tile's middle they are nearest in colour, or
/// as nothing where they are clear. [pixel] reads the sheet as measured.
TerrainSet tagByColour(TerrainSet set, TileSource s, Iterable<int> tiles, ui.Color Function(int x, int y) pixel) {
  var tw = s.tileW, th = s.tileH;
  // A few pixels at each place: the very corner, the middle of each edge,
  // the middle of the tile.
  var c = math.max(1, (math.min(tw, th) / 6).round());
  var zones = <int, ui.Rect>{
    tagCentre: ui.Rect.fromLTWH(tw / 4, th / 4, tw / 2, th / 2),
    tagTop: ui.Rect.fromLTWH(tw * 3 / 8, 0, tw / 4, c.toDouble()),
    tagBottom: ui.Rect.fromLTWH(tw * 3 / 8, th - c.toDouble(), tw / 4, c.toDouble()),
    tagLeft: ui.Rect.fromLTWH(0, th * 3 / 8, c.toDouble(), th / 4),
    tagRight: ui.Rect.fromLTWH(tw - c.toDouble(), th * 3 / 8, c.toDouble(), th / 4),
    tagTopLeft: ui.Rect.fromLTWH(0, 0, c.toDouble(), c.toDouble()),
    tagTopRight: ui.Rect.fromLTWH(tw - c.toDouble(), 0, c.toDouble(), c.toDouble()),
    tagBottomLeft: ui.Rect.fromLTWH(0, th - c.toDouble(), c.toDouble(), c.toDouble()),
    tagBottomRight: ui.Rect.fromLTWH(tw - c.toDouble(), th - c.toDouble(), c.toDouble(), c.toDouble()),
  };
  // A zone's colour, its clear pixels left out; null where mostly clear.
  (double, double, double)? colourOf(int tile, ui.Rect zone) {
    var at = s.tileRect(tile);
    double r = 0, g = 0, b = 0, a = 0;
    var n = 0;
    for (var y = zone.top.floor(); y < zone.bottom.ceil(); y++) {
      for (var x = zone.left.floor(); x < zone.right.ceil(); x++) {
        var p = pixel(at.left.toInt() + x, at.top.toInt() + y);
        n++;
        if (p.a < 0.5) continue;
        r += p.r;
        g += p.g;
        b += p.b;
        a += 1;
      }
    }
    if (n == 0 || a / n < 0.5) return null;
    return (r / a, g / a, b / a);
  }

  var samples = <int, (double, double, double)>{
    for (var (i, t) in set.terrains.indexed)
      if (t.sample case var tile?)
        if (colourOf(tile, zones[tagCentre]!) case var colour?) i: colour,
  };
  var next = set;
  for (var tile in tiles) {
    var tag = List.filled(9, -1);
    for (var place in set.places) {
      var colour = colourOf(tile, zones[place]!);
      if (colour == null || samples.isEmpty) continue;
      var (r, g, b) = colour;
      int? nearest;
      var d = double.infinity;
      for (var e in samples.entries) {
        var (sr, sg, sb) = e.value;
        var dd = (r - sr) * (r - sr) + (g - sg) * (g - sg) + (b - sb) * (b - sb);
        if (dd < d) {
          d = dd;
          nearest = e.key;
        }
      }
      tag[place] = nearest ?? -1;
    }
    var tags = {...next.tags};
    if (tag.every((x) => x < 0)) {
      tags.remove(tile);
    } else {
      tags[tile] = tag;
    }
    next = next.copyWith(tags: tags);
  }
  return next;
}
