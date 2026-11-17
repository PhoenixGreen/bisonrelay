part of 'epub_layers.dart';

// CSS keyframes for the page as a whole (the Camera's framing, lens and
// vignette), kept only where a value changes, and the flat-matrix maths and
// number formatting they use. Part of epub_layers.dart.

/// cameraKeys is how [page]'s Camera frames it on each of its [frames], as
/// a stage transform: a key at each move and hold end, played straight so
/// the easing is the canvas's. Empty with none, or one on a 3D stage.
List<EpubKey> cameraKeys(
    CanvasDocument page, int frames, double pixels, int width, int height) {
  var cam = cameraOf(page);
  if (cam == null || isStageScene(page)) return const [];
  String at(int f) {
    var (zoom, c) = cameraFraming(cam, f, page);
    var roll = cameraLookAt(cam, f, page).roll;
    if (roll == 0) {
      var tx = width / 2 - c.dx * pixels * zoom;
      var ty = height / 2 - c.dy * pixels * zoom;
      return "translate(${tx.toStringAsFixed(2)}px,${ty.toStringAsFixed(2)}px) "
          "scale(${zoom.toStringAsFixed(5)})";
    }
    // Rolled: about the middle of the page, the picture turned back.
    return "translate(${(width / 2).toStringAsFixed(2)}px,"
        "${(height / 2).toStringAsFixed(2)}px) "
        "rotate(${(-roll).toStringAsFixed(3)}deg) "
        "scale(${zoom.toStringAsFixed(5)}) "
        "translate(${(-c.dx * pixels).toStringAsFixed(2)}px,"
        "${(-c.dy * pixels).toStringAsFixed(2)}px)";
  }

  var all = [for (var f = 0; f < frames; f++) at(f)];
  var keys = <EpubKey>[];
  for (var f = 0; f < frames; f++) {
    var changes = f == 0 ||
        f == frames - 1 ||
        all[f] != all[f - 1] ||
        all[f] != all[f + 1];
    if (changes) keys.add(EpubKey(f, {"transform": all[f]}));
  }
  // Never moving: a still framing is one key.
  if (all.toSet().length == 1) return [keys.first];
  return keys;
}

/// lensKeys are what [page]'s Camera's lens does to [elements] by depth,
/// frame by frame where it changes: parallax as a transform (see
/// parallaxed), depth of field as a blur; only those it touches.
Map<String, List<EpubKey>> lensKeys(CanvasDocument page,
    List<CanvasElement> elements, int frames, double pixels) {
  var cam = cameraOf(page);
  if (cam == null || isStageScene(page) || !cam.hasLens) return const {};
  var rect = page.size.rect;
  var looks = [for (var f = 0; f < frames; f++) cameraLookAt(cam, f, page)];
  var framings = [for (var f = 0; f < frames; f++) cameraFraming(cam, f, page)];
  var out = <String, List<EpubKey>>{};
  for (var e in elements) {
    if (e is CameraElement) continue;
    var depth = e.base.depth;
    if (depth == 0 && looks.every((l) => l.blurAt(0) <= 0.25)) continue;
    var sways = looks.any((l) => l.sways(depth));
    var blurs = looks.any((l) => l.blurAt(depth) > 0.25);
    if (!sways && !blurs) continue;
    Map<String, String> at(int f) {
      var look = looks[f];
      var (zoom, focus) = framings[f];
      var css = <String, String>{};
      if (sways) {
        var (z, c) = parallaxed(zoom, focus, rect, depth, look.parallax);
        var k = z / zoom;
        var tx = (focus.dx - k * c.dx) * pixels;
        var ty = (focus.dy - k * c.dy) * pixels;
        css["transform"] =
            "translate(${tx.toStringAsFixed(2)}px,${ty.toStringAsFixed(2)}px) "
            "scale(${k.toStringAsFixed(5)})";
      }
      if (blurs) {
        var sigma = look.blurAt(depth) * pixels;
        css["filter"] = "blur(${sigma.toStringAsFixed(2)}px)";
      }
      return css;
    }

    var all = [for (var f = 0; f < frames; f++) at(f)];
    bool same(int a, int b) =>
        all[a].length == all[b].length &&
        all[a].entries.every((x) => all[b][x.key] == x.value);
    var keys = <EpubKey>[
      for (var f = 0; f < frames; f++)
        if (f == 0 || f == frames - 1 || !same(f, f - 1) || !same(f, f + 1))
          EpubKey(f, all[f]),
    ];
    out[e.id] = keys.length > 1 && keys.every((k) => same(k.frame, 0))
        ? [keys.first]
        : keys;
  }
  return out;
}

/// vignetteKeys is [page]'s Camera's vignette, as the overlay's opacity on
/// each frame it changes; empty for none.
List<EpubKey> vignetteKeys(CanvasDocument page, int frames) {
  var cam = cameraOf(page);
  if (cam == null || isStageScene(page)) return const [];
  var all = [
    for (var f = 0; f < frames; f++)
      cameraLookAt(cam, f, page).vignette.toStringAsFixed(3)
  ];
  if (all.every((v) => double.parse(v) <= 0)) return const [];
  if (all.toSet().length == 1) {
    return [
      EpubKey(0, {"opacity": all.first})
    ];
  }
  return [
    for (var f = 0; f < frames; f++)
      if (f == 0 ||
          f == frames - 1 ||
          all[f] != all[f - 1] ||
          all[f] != all[f + 1])
        EpubKey(f, {"opacity": all[f]}),
  ];
}

String _cssColour(ui.Color c) =>
    "rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},"
    "${c.a.toStringAsFixed(3)})";

/// _compact is a value a frame as keyframes: only where something changes,
/// and either end of a stretch where nothing does.
List<EpubKey> _compact(List<Map<String, String>> byFrame) {
  bool same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((x) => b[x.key] == x.value);
  var out = <EpubKey>[];
  for (var f = 0; f < byFrame.length; f++) {
    var here = byFrame[f];
    var keep = f == 0 ||
        f == byFrame.length - 1 ||
        !same(here, byFrame[f - 1]) ||
        !same(here, byFrame[f + 1]);
    if (keep) out.add(EpubKey(f, here));
  }
  // A value that never changes is one key.
  if (out.every((k) => same(k.css, out.first.css))) return [out.first];
  return out;
}

String _n(double v, int places) {
  var s = v.toStringAsFixed(places);
  if (s.contains(".")) {
    s = s.replaceFirst(RegExp(r"0+$"), "").replaceFirst(RegExp(r"\.$"), "");
  }
  return s == "-0" ? "0" : s;
}

/// _mul is a times b, for the canvas's column-major 4x4 matrices.
Float64List _mul(Float64List a, Float64List b) {
  var out = Float64List(16);
  for (var c = 0; c < 4; c++) {
    for (var r = 0; r < 4; r++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[k * 4 + r] * b[c * 4 + k];
      }
      out[c * 4 + r] = sum;
    }
  }
  return out;
}

/// _invert is the inverse of a canvas transform, which is flat: a turn, a
/// scale and a shift, and nothing in depth.
Float64List _invert(Float64List m) {
  var a = m[0], b = m[1], c = m[4], d = m[5], e = m[12], f = m[13];
  var det = a * d - b * c;
  if (det.abs() < 1e-12) det = 1e-12;
  var out = Float64List(16)
    ..[10] = 1
    ..[15] = 1;
  out[0] = d / det;
  out[1] = -b / det;
  out[4] = -c / det;
  out[5] = a / det;
  out[12] = (c * f - d * e) / det;
  out[13] = (b * e - a * f) / det;
  return out;
}

Offset _mapPoint(Float64List m, Offset p) => Offset(
    m[0] * p.dx + m[4] * p.dy + m[12], m[1] * p.dx + m[5] * p.dy + m[13]);

Rect _mapRect(Float64List m, Rect r) {
  var ps = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]
      .map((p) => _mapPoint(m, p))
      .toList();
  return Rect.fromLTRB(
      ps.map((p) => p.dx).reduce(math.min),
      ps.map((p) => p.dy).reduce(math.min),
      ps.map((p) => p.dx).reduce(math.max),
      ps.map((p) => p.dy).reduce(math.max));
}
