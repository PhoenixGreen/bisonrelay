import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';

// parallax_painter.dart draws parallax scenery: every layer moved by the
// camera times its own scroll scale, plus its own drift, and laid side by
// side for as far as the page needs where it repeats.
//
// Drawn scenery is made to repeat without a seam: a ridge is a sum of sines
// whose every frequency is a whole number of waves across one tile, so its
// two ends meet at the same height, and trees, buildings and clouds are
// placed in a tile and drawn again a tile along -- one that leans over the
// edge is completed by the next tile's copy of itself.

/// paintParallax draws [p] as it is on [frame], filling [box].
void paintParallax(ui.Canvas canvas, Rect box, ParallaxElement p, int frame,
    {double frameRate = 30, CanvasImageSource? images}) {
  if (box.isEmpty) return;
  var camera = p.cameraAt(frame);
  var time = frame / (frameRate <= 0 ? 1 : frameRate);
  canvas.save();
  canvas.clipRect(box);
  for (var layer in p.layers) {
    if (!layer.visible || layer.opacity <= 0.002) continue;
    _paintLayer(canvas, box, layer, camera, time, frameRate, images);
  }
  canvas.restore();
}

/// layerShift is how far [layer] has moved from where it starts: the camera
/// times its scroll scale, against the camera, and its own drift by [time].
Offset layerShift(ParallaxLayer layer, ParallaxCamera camera, double time) =>
    Offset(-camera.x * layer.scrollX + layer.autoX * time + layer.offset.dx,
        -camera.y * layer.scrollY + layer.autoY * time + layer.offset.dy);

/// layerZoom is how much nearer [layer] looks for the camera's zoom: the
/// sky not at all, the ground by all of it.
double layerZoom(ParallaxLayer layer, ParallaxCamera camera) => math.max(
    0.05,
    1 +
        (camera.zoom - 1) *
            math.max(layer.scrollX, layer.scrollY).clamp(0.0, 4.0));

/// tileSize is one tile of [layer] in a page of [box]: a page across, by
/// its size; a picture as wide as its shape makes it.
Size tileSize(ParallaxLayer layer, Rect box, ui.Image? picture) {
  var h = box.height * layer.size;
  if (picture != null && picture.height > 0) {
    return Size(h * picture.width / picture.height, h);
  }
  return Size(box.width * layer.size, h);
}

void _paintLayer(
    ui.Canvas canvas,
    Rect box,
    ParallaxLayer layer,
    ParallaxCamera camera,
    double time,
    double frameRate,
    CanvasImageSource? images) {
  var picture = layer.kind == SceneryKind.picture && layer.assetId.isNotEmpty
      ? images?.resolve(layer.assetId, const BackgroundRemoval())
      : null;
  if (layer.kind == SceneryKind.picture && picture == null) return;
  var tile = tileSize(layer, box, picture);
  if (tile.width < 1 || tile.height < 1) return;
  var shift = layerShift(layer, camera, time);
  var zoom = layerZoom(layer, camera);

  // Where its first tile is, before anything moves it.
  var top = switch (layer.anchor) {
    LayerAnchor.bottom => box.bottom - tile.height,
    LayerAnchor.top => box.top,
    LayerAnchor.fill => box.top,
  };
  var origin = Offset(box.left, top) + shift;

  // The part of the layer that is seen, which the zoom grows or shrinks.
  var c = box.center;
  var seen = Rect.fromCenter(
      center: c, width: box.width / zoom, height: box.height / zoom);

  (int, int) range(
          double from, double to, double start, double step, bool repeat) =>
      repeat
          ? (((from - start) / step).floor() - 1, ((to - start) / step).ceil())
          : (0, 0);
  var (x0, x1) =
      range(seen.left, seen.right, origin.dx, tile.width, layer.repeatX);
  var (y0, y1) =
      range(seen.top, seen.bottom, origin.dy, tile.height, layer.repeatY);
  // A sky or a fill that does not repeat down still covers the page above
  // and below it rather than ending in a hard line.
  if (x1 - x0 > 400 || y1 - y0 > 400) return;

  var faded = layer.opacity < 0.999;
  if (faded) {
    canvas.saveLayer(
        box, Paint()..color = Color.fromRGBO(255, 255, 255, layer.opacity));
  } else {
    canvas.save();
  }
  canvas.translate(c.dx, c.dy);
  canvas.scale(zoom);
  canvas.translate(-c.dx, -c.dy);

  var drawn = layer.kind.drawn ? _sceneryOf(layer, tile) : null;
  for (var j = y0; j <= y1; j++) {
    for (var i = x0; i <= x1; i++) {
      var at = origin + Offset(i * tile.width, j * tile.height);
      var rect = at & tile;
      switch (layer.kind) {
        case SceneryKind.picture:
          canvas.drawImageRect(
              picture!,
              Rect.fromLTWH(
                  0, 0, picture.width.toDouble(), picture.height.toDouble()),
              rect,
              Paint()..filterQuality = FilterQuality.medium);
        case SceneryKind.pattern:
          _paintPattern(canvas, rect, layer, time, frameRate, images);
        default:
          canvas.save();
          canvas.translate(at.dx, at.dy);
          for (var (path, paint) in drawn!) {
            canvas.drawPath(path, paint);
          }
          canvas.restore();
      }
    }
  }
  canvas.restore();
}

/// _patterns are still patterns drawn once for a tile size, since a
/// generator is the most expensive thing on a canvas and a repeating layer
/// asks for the same tile many times over.
final Map<String, ui.Image> _patterns = {};

void _paintPattern(ui.Canvas canvas, Rect rect, ParallaxLayer layer,
    double time, double frameRate, CanvasImageSource? images) {
  if (layer.spec.animated) {
    paintProcedural(canvas, rect, layer.spec,
        time: time, frameRate: frameRate, images: images);
    return;
  }
  var w = rect.width.round().clamp(1, 4096),
      h = rect.height.round().clamp(1, 4096);
  var key = "${jsonEncode(layer.spec.toJson())}|$w|$h";
  var image = _patterns[key];
  if (image == null) {
    var rec = ui.PictureRecorder();
    paintProcedural(ui.Canvas(rec),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), layer.spec,
        images: images);
    image = rec.endRecording().toImageSync(w, h);
    if (_patterns.length >= 8)
      _patterns.remove(_patterns.keys.first)?.dispose();
    _patterns[key] = image;
  }
  canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.low);
}

/// _drawn are drawn scenery tiles already worked out, by layer and size:
/// the camera moves them every frame, and moving is all that changes.
final Map<String, List<(Path, Paint)>> _drawn = {};

List<(Path, Paint)> _sceneryOf(ParallaxLayer layer, Size tile) {
  var key =
      "${jsonEncode(layer.copyWith(scrollX: 0, scrollY: 0, autoX: 0, autoY: 0, offset: Offset.zero, opacity: 1).toJson())}"
      "|${tile.width.round()}|${tile.height.round()}";
  var hit = _drawn[key];
  if (hit != null) return hit;
  var made = scenery(layer, tile);
  if (_drawn.length >= 48) _drawn.remove(_drawn.keys.first);
  return _drawn[key] = made;
}

/// _rand is a number in [0, 1) that is always the same for the same [seed]
/// and [i] -- never Random, which would redraw the hills on every frame.
double _rand(int seed, int i) {
  var h = (seed * 0x9E3779B1 + i * 0x85EBCA77) & 0xFFFFFFFF;
  h ^= h >> 15;
  h = (h * 0x2C1B3C6D) & 0xFFFFFFFF;
  h ^= h >> 12;
  h = (h * 0x297A2D39) & 0xFFFFFFFF;
  h ^= h >> 15;
  return (h & 0xFFFFFF) / 0x1000000;
}

/// ridge is a silhouette's height at [u] across one tile, from 0 to 1, for
/// [layer]: sharp peaks for mountains, rolls for hills. It comes back to
/// where it started at u = 1, which is what makes the tiles join.
double ridge(ParallaxLayer layer, double u) {
  var sharp = layer.kind == SceneryKind.mountains;
  var waves = sharp ? 7 : 4;
  var rough = 0.35 + layer.amount * 0.9;
  var sum = 0.0, most = 0.0;
  for (var k = 1; k <= waves; k++) {
    var a = math.pow(rough / (sharp ? 1.6 : 2.2), k - 1).toDouble() *
        (0.6 + 0.8 * _rand(layer.seed, k));
    var phase = _rand(layer.seed, 100 + k) * math.pi * 2;
    // Upside-down |sin| for mountains: its cusps are the peaks.
    var s = sharp
        ? 1 - (math.sin(math.pi * k * u + phase / 2)).abs()
        : 0.5 + 0.5 * math.sin(2 * math.pi * k * u + phase);
    sum += a * s;
    most += a;
  }
  return most <= 0 ? 0 : sum / most;
}

/// scenery is [layer] drawn into one tile of [tile] at the origin, as paths
/// with their paints, back to front.
List<(Path, Paint)> scenery(ParallaxLayer layer, Size tile) {
  var w = tile.width, h = tile.height;
  var out = <(Path, Paint)>[];
  Paint fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;
  var band = h * layer.height;
  var base = h - band;
  switch (layer.kind) {
    case SceneryKind.sky:
      out.add((
        Path()..addRect(Offset.zero & tile),
        Paint()
          ..shader = ui.Gradient.linear(
              Offset.zero, Offset(0, h), [layer.color, layer.color2]),
      ));
      // A sun, or a moon, as big as the amount says; none at nought.
      if (layer.amount > 0.05) {
        var r = h * 0.07 * layer.amount * 1.6;
        var at = Offset(w * (0.2 + 0.6 * _rand(layer.seed, 1)),
            h * (0.18 + 0.25 * _rand(layer.seed, 2)));
        var glow = Color.lerp(layer.color2, const Color(0xFFFFFFFF), 0.6)!;
        out.add((
          Path()..addOval(Rect.fromCircle(center: at, radius: r * 3)),
          Paint()
            ..shader = ui.Gradient.radial(at, r * 3,
                [glow.withValues(alpha: 0.45), glow.withValues(alpha: 0)]),
        ));
        out.add((
          Path()..addOval(Rect.fromCircle(center: at, radius: r)),
          fill(glow),
        ));
      }
    case SceneryKind.clouds:
      var n = 2 + (layer.amount * 9).round();
      for (var i = 0; i < n; i++) {
        var cx = w * (i + _rand(layer.seed, i * 7)) / n;
        var cy = h * (0.16 + 0.3 * _rand(layer.seed, i * 7 + 1));
        var size = h * (0.05 + 0.07 * _rand(layer.seed, i * 7 + 2));
        var puff = Path();
        var puffs = 4 + (_rand(layer.seed, i * 7 + 3) * 3).floor();
        for (var k = 0; k < puffs; k++) {
          var dx = (k - (puffs - 1) / 2) * size * 0.9;
          var r = size * (0.6 + 0.6 * math.sin(math.pi * (k + 0.5) / puffs));
          puff.addOval(Rect.fromCircle(
              center: Offset(cx + dx, cy - r * 0.35), radius: r));
        }
        puff.addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - size * puffs * 0.5, cy - size * 0.3,
                size * puffs, size * 0.6),
            Radius.circular(size * 0.3)));
        var b = puff.getBounds();
        out.add((
          puff,
          Paint()
            ..shader = ui.Gradient.linear(
                b.topCenter, b.bottomCenter, [layer.color, layer.color2]),
        ));
      }
    case SceneryKind.mountains || SceneryKind.hills:
      // Stretched so the highest peak stands at the layer's height and the
      // lowest dip is a fifth of the way up it: whatever the sum of waves
      // came to, Height is how tall the range is.
      const steps = 160;
      var r = [for (var s = 0; s <= steps; s++) ridge(layer, s / steps)];
      var lo = r.reduce(math.min), hi = r.reduce(math.max);
      var span = hi - lo < 1e-9 ? 1.0 : hi - lo;
      var path = Path()..moveTo(0, h);
      for (var s = 0; s <= steps; s++) {
        var t = 0.2 + 0.8 * (r[s] - lo) / span;
        path.lineTo(s / steps * w, base + band * (1 - t));
      }
      path
        ..lineTo(w, h)
        ..close();
      out.add((
        path,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, base), Offset(0, h),
              [layer.color2, layer.color], [0, 0.45]),
      ));
    case SceneryKind.trees:
      // A strip of ground the trees stand in, so a gap between them is not
      // a hole through to the layer behind.
      var foot = band * 0.14;
      out.add((
        Path()..addRect(Rect.fromLTRB(-1, h - foot, w + 1, h)),
        fill(layer.color)
      ));
      var n = 5 + (layer.amount * 28).round();
      var trees = Path();
      for (var i = 0; i < n; i++) {
        var x = w * (i + 0.15 + 0.7 * _rand(layer.seed, i * 5)) / n;
        var tall = band * (0.55 + 0.45 * _rand(layer.seed, i * 5 + 1));
        var wide = tall * (0.32 + 0.12 * _rand(layer.seed, i * 5 + 2));
        var ground = h - foot * 0.5;
        trees.addRect(Rect.fromLTWH(
            x - wide * 0.06, ground - tall * 0.18, wide * 0.12, tall * 0.18));
        for (var tier = 0; tier < 3; tier++) {
          var t0 = ground - tall * (0.15 + tier * 0.25);
          var t1 =
              ground - tall * (0.55 + tier * 0.15 + (tier == 2 ? 0.15 : 0));
          var half = wide * (0.5 - tier * 0.12);
          trees.addPolygon(
              [Offset(x - half, t0), Offset(x, t1), Offset(x + half, t0)],
              true);
        }
      }
      out.add((trees, fill(layer.color)));
    case SceneryKind.city:
      var n = 4 + (layer.amount * 20).round();
      var weights = [
        for (var i = 0; i < n; i++) 0.5 + _rand(layer.seed, i * 3)
      ];
      var total = weights.fold(0.0, (a, b) => a + b);
      var x = 0.0;
      var blocks = Path();
      var lit = Path();
      for (var i = 0; i < n; i++) {
        var bw = w * weights[i] / total;
        var bh = band * (0.3 + 0.7 * _rand(layer.seed, i * 3 + 1));
        var r = Rect.fromLTWH(x, h - bh, bw + 0.5, bh);
        blocks.addRect(r);
        // A roof that is not flat, now and then.
        if (_rand(layer.seed, i * 3 + 2) > 0.75) {
          blocks.addRect(Rect.fromLTWH(
              x + bw * 0.4, h - bh - band * 0.06, bw * 0.2, band * 0.06));
        }
        var win = math.max(1.5, bw * 0.08);
        if (bw > win * 4) {
          var cols = ((bw - win) / (win * 2.2)).floor();
          var rows = ((bh - win * 2) / (win * 2.4)).floor();
          for (var cx = 0; cx < cols; cx++) {
            for (var ry = 0; ry < rows; ry++) {
              if (_rand(layer.seed + i, cx * 131 + ry) > 0.45) continue;
              lit.addRect(Rect.fromLTWH(x + win + cx * win * 2.2,
                  h - bh + win * 1.5 + ry * win * 2.4, win, win * 1.2));
            }
          }
        }
        x += bw;
      }
      out.add((blocks, fill(layer.color)));
      out.add((lit, fill(layer.color2)));
    case SceneryKind.ground:
      var path = Path()..moveTo(0, h);
      const steps = 80;
      for (var s = 0; s <= steps; s++) {
        var u = s / steps;
        var wave = math.sin(2 * math.pi * 3 * u + layer.seed) * 0.5 +
            math.sin(2 * math.pi * 7 * u + layer.seed * 2) * 0.25;
        path.lineTo(u * w, base + band * 0.12 * layer.amount * wave);
      }
      path
        ..lineTo(w, h)
        ..close();
      out.add((
        path,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, base), Offset(0, h),
              [layer.color2, layer.color], [0, 0.35]),
      ));
    case SceneryKind.picture || SceneryKind.pattern:
      break;
  }
  return out;
}
