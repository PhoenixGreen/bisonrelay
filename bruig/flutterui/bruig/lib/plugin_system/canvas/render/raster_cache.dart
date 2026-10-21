import 'dart:collection';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'dart:math' as math;

// raster_cache.dart keeps the pictures a layered picture is drawn through --
// what an adjustment makes of the layers under it, a layer flattened for its
// effects -- from one frame to the next.
//
// They were kept against the element object itself, and that was two
// problems. Every edit makes a new element, so a drag in the settings -- a
// new element every frame -- found nothing kept and rasterised every
// adjustment and every effect again, every frame. And the undo history holds
// on to every element there has been, so each one went on holding the
// rasters made for it: hundreds of megabytes of pictures nobody would see
// again, which is most of where the memory went.
//
// Here they are kept by name -- the element's id and the layer's, and the
// size drawn at -- with what each was drawn from beside it. A raster is used
// again only while every one of those is still the same object, or equal;
// anything changed, and it is drawn afresh. Where the element *is* on the
// page is not among them, so moving a picture moves its rasters with it
// rather than redrawing them. And the whole is held to a budget, the least
// recently drawn going first.

/// rasterBudget is how many bytes of pixels the cache holds at most.
const int rasterBudget = 384 << 20;

class _Kept {
  final List<Object?> from;
  final ui.Image image;
  final int bytes;
  _Kept(this.from, this.image) : bytes = image.width * image.height * 4;
}

/// RasterCache is the kept rasters, least recently drawn first.
class RasterCache {
  RasterCache._();
  static final RasterCache instance = RasterCache._();

  /// drafting is set while the canvas is drawn during a gesture: what is
  /// rasterised is drawn no bigger than [draftSide] across, so a picture
  /// resized from the settings follows the pointer, and drawn again at its
  /// full size the moment the gesture ends. See StagePainter.drafting.
  static bool drafting = false;
  static const double draftSide = 1024;

  final LinkedHashMap<String, _Kept> _kept = LinkedHashMap();
  int _bytes = 0;

  /// bytes is how much the cache holds now.
  int get bytes => _bytes;
  int get length => _kept.length;

  /// keys is what is kept, by name, for the tests.
  Iterable<String> get keys => _kept.keys;

  /// get is the raster kept as [key], if it was drawn from [from].
  ui.Image? get(String key, List<Object?> from) {
    var kept = _kept.remove(key);
    if (kept == null) return null;
    if (!_same(kept.from, from)) {
      if (CanvasPerf.on) {
        // Which part of what it was drawn from is not what it was.
        var at = -1;
        for (var i = 0; i < math.min(kept.from.length, from.length); i++) {
          if (!identical(kept.from[i], from[i]) && kept.from[i] != from[i]) {
            at = i;
            break;
          }
        }
        CanvasPerf.count("drop $key part $at "
            "${at < 0 ? "length" : from[at].runtimeType}");
      }
      _drop(kept);
      return null;
    }
    _kept[key] = kept;
    return kept.image;
  }

  /// sized is the raster kept for the layer [key] -- drawn from [from] --
  /// to draw at [w] by [h] pixels.
  ///
  /// A layer keeps two at most: one at its full size and, while a gesture
  /// is under way, a draft. They were named by their size, and every size a
  /// picture passed through while it was resized or zoomed -- each frame a
  /// new one -- was another raster kept, until the budget was full of
  /// pictures of sizes nobody would draw at again. While drafting, a full
  /// one still good is better than a draft and is used rather than drawing
  /// one.
  ///
  /// A full one near enough the size asked for is used rather than drawn
  /// again: within a third smaller and twice as large, it is scaled to fit.
  /// Asked for to the pixel, every frame of a sidebar sliding open -- the
  /// canvas a few pixels smaller each frame -- drew every layer under an
  /// adjustment again, and the panels crawled.
  ///
  /// A thumbnail of it -- the scene's, in the scenes list -- is kept apart
  /// from the one the canvas draws: kept as one, each was drawn again in
  /// turn for the other, and every change on the canvas drew everything
  /// under an adjustment twice over, a second of the graphics card's time
  /// each on a picture of six masked photographs.
  ui.Image? sized(String key, List<Object?> from, int w, int h) {
    key = "$key|${_sizeClass(w, h)}";
    var full = get("$key|full", from);
    if (drafting) return full ?? get("$key|draft", from);
    if (full != null &&
        nearEnough(full.width, w) &&
        nearEnough(full.height, h)) {
      return full;
    }
    return null;
  }

  /// _sizeClass is which size a raster [w] by [h] is kept as: one class to
  /// each four times larger -- 256 to 1023 across, 1024 to 4095 -- so a
  /// thumbnail and the canvas are kept apart, and a canvas drawn a little
  /// larger or smaller stays in its own.
  static String _sizeClass(int w, int h) =>
      "x${(math.log(math.max(1, math.max(w, h))) / math.ln2 / 2).floor()}";

  /// nearEnough is whether a raster [had] pixels across will do for [want]:
  /// not so much smaller it is blurred, nor so much larger it is waste.
  static bool nearEnough(int had, int want) =>
      had >= want * 0.75 - 1 && had <= want * 2 + 1;

  /// putSized keeps [image] as what [sized] finds for [key]: the draft while
  /// drafting, or the full one, with the draft let go of.
  void putSized(String key, List<Object?> from, ui.Image image) {
    key = "$key|${_sizeClass(image.width, image.height)}";
    if (!drafting) {
      var draft = _kept.remove("$key|draft");
      if (draft != null) _drop(draft);
    }
    put("$key|${drafting ? "draft" : "full"}", from, image);
  }

  /// drawn counts the rasters put, for the tests to tell a raster kept from
  /// one drawn again.
  int drawn = 0;

  /// put keeps [image] as [key], drawn from [from]. The cache owns it now.
  void put(String key, List<Object?> from, ui.Image image) {
    drawn++;
    CanvasPerf.count("rasterPut");
    var old = _kept.remove(key);
    if (old != null) _drop(old);
    var kept = _Kept(from, image);
    _kept[key] = kept;
    _bytes += kept.bytes;
    while (_bytes > rasterBudget && _kept.length > 1) {
      var first = _kept.keys.first;
      _drop(_kept.remove(first)!);
    }
  }

  /// forget drops everything kept for the element [id].
  void forget(String id) {
    var keys = [
      for (var k in _kept.keys)
        if (k.startsWith("$id|")) k
    ];
    for (var k in keys) {
      _drop(_kept.remove(k)!);
    }
  }

  /// clear drops everything.
  void clear() {
    for (var kept in _kept.values) {
      kept.image.dispose();
    }
    _kept.clear();
    _bytes = 0;
  }

  void _drop(_Kept kept) {
    _bytes -= kept.bytes;
    kept.image.dispose();
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) && a[i] != b[i]) return false;
    }
    return true;
  }
}

/// pictureLookFrom is what the base picture of [e] is drawn from -- its
/// picture and everything done to it -- and not where it is.
List<Object?> pictureLookFrom(ImageElement e) => [
      e.assetId,
      e.fit,
      e.crop,
      e.framing,
      e.filter,
      e.saturation,
      e.brightness,
      e.tint,
      e.overlay,
      e.blend,
      e.mask,
      e.retouch,
      e.removal,
      e.outline,
      e.frame,
      e.box,
    ];

/// layersFrom is what [layers] of [e] are drawn from, the base picture's
/// look among it where the base is one of them: each layer is a value that
/// is replaced, not changed, so the same layer object is the same layer.
List<Object?> layersFrom(ImageElement e, List<ImageLayer> layers) => [
      for (var l in layers) l,
      if (layers.any((l) => l.isBase)) ...pictureLookFrom(e),
    ];

/// deviceScaleOf is how many device pixels one unit of [canvas] is drawn
/// across: what a raster of something drawn on it is made at.
double deviceScaleOf(ui.Canvas canvas) {
  var m = canvas.getTransform();
  var sx = math.sqrt(m[0] * m[0] + m[1] * m[1]);
  var sy = math.sqrt(m[4] * m[4] + m[5] * m[5]);
  var dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
  return math.max(sx, sy) * math.max(1.0, dpr);
}
