import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:flutter/foundation.dart';

// procedural_cache.dart keeps generated backgrounds as pictures, so the
// editor draws each once rather than once a frame. A generated background is
// the most expensive thing on a canvas, and the editor repaints for every
// pointer move and panel rebuild. The exporter does not use this: it wants
// exact pixels at its own size and renders each frame once anyway.

/// ProceduralCache is a few backgrounds, rasterised, oldest out first.
///
/// More than one canvas can draw at once: facing pages, both scenes of a
/// transition, and a page turn's four leaves plus the next spread's two
/// warmed ahead. Too small a cache makes them evict each other every frame,
/// which shows as flicker. Each is megabytes, so no more than that.
class ProceduralCache extends ChangeNotifier {
  /// _keep is how many are held: six, for a page turn (see the class doc).
  static const int _keep = 6;

  /// _images is the rasters, least recently asked for first: a Dart map
  /// keeps insertion order, so re-inserting a key moves it to the end.
  final Map<String, ui.Image> _images = {};

  /// _making is the keys being rasterised, so a slow generator is not started
  /// again on every frame while the first one is still running.
  final Set<String> _making = {};

  bool _disposed = false;

  /// moves is whether [spec] changes from one frame to the next: animated
  /// and a style (or visible layer, or grain) that can move. The `animated`
  /// switch alone is not enough: it survives a change to a still style.
  static bool moves(ProceduralSpec spec) =>
      spec.animated &&
      (spec.style.canAnimate ||
          spec.layers.any((l) => l.visible && l.spec.style.canAnimate) ||
          spec.effects.grainMoves && spec.effects.grain > 0);

  /// _specKey is [spec] written out, memoised per spec object (specs are
  /// immutable) because it is asked for on every paint.
  static final Expando<String> _specKeys = Expando("proceduralKey");
  static String _specKey(ProceduralSpec spec) =>
      _specKeys[spec] ??= "${spec.toJson()}";

  /// keyFor is what makes two requests the same: the design, the size, the
  /// moment (for a background that moves), and which of its pictures have
  /// arrived -- an icon arrives late, and without it in the key the first,
  /// icon-less raster would be kept for ever.
  static String keyFor(ProceduralSpec spec, ui.Size size, double time,
          [CanvasImageSource? images]) =>
      "${_specKey(spec)}|${size.width.round()}x${size.height.round()}"
      "|${moves(spec) ? time.toStringAsFixed(3) : ""}"
      "|${_ready(spec, images)}";

  /// _ready is which of a design's pictures can be drawn right now.
  static String _ready(ProceduralSpec spec, CanvasImageSource? images) {
    if (images == null) return "";
    // The background's own rings, and any laid over it as a layer.
    var assets = [
      for (var s in [spec, for (var l in spec.layers) l.spec])
        for (var icon in s.rings.icons) ...[
          icon.asset,
          for (var pick in icon.also) pick.asset,
        ],
    ];
    if (assets.isEmpty) return "";
    return [
      for (var asset in assets)
        images.resolveVector(asset) != null ||
                images.resolve(asset, const BackgroundRemoval()) != null
            ? "1"
            : "0",
    ].join();
  }

  /// imageFor is the picture to draw, or null when there is not one yet.
  ///
  /// Asking for one that is not ready starts it and, when [standIn], hands
  /// back the most recent raster of the same pixel size while it is made: a
  /// background one raster out of date is invisible, whereas the caller
  /// generating it itself every frame until the raster lands stalls a drag
  /// (the Metal texture shades every pixel). Never a raster of another
  /// size, which would show as a stretched background.
  ui.Image? imageFor(ProceduralSpec spec, ui.Size size, double time,
      [CanvasImageSource? images, bool make = true, bool standIn = true]) {
    // A moving background is a new picture every frame; caching would only
    // add a raster to the drawing.
    if (moves(spec)) return null;
    if (size.width < 1 || size.height < 1) return null;

    var key = keyFor(spec, size, time, images);
    var held = _images.remove(key);
    if (held != null) {
      // Back to the end of the queue.
      _images[key] = held;
      return held;
    }
    if (make && !_making.contains(key)) _make(spec, size, time, key, images);

    // A stand-in of the same size while this one is made. Not for an
    // element: two panels the same size would each flash the other's pattern.
    if (!standIn) return null;
    var wide = size.width.round().clamp(1, 8192);
    var high = size.height.round().clamp(1, 8192);
    for (var last in _images.values.toList().reversed) {
      if (last.width == wide && last.height == high) return last;
    }
    return null;
  }

  Future<void> _make(ProceduralSpec spec, ui.Size size, double time, String key,
      CanvasImageSource? images) async {
    _making.add(key);
    try {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      paintProcedural(canvas, ui.Offset.zero & size, spec,
          time: time, images: images);
      var picture = recorder.endRecording();
      ui.Image image;
      try {
        image = await picture.toImage(size.width.round().clamp(1, 8192),
            size.height.round().clamp(1, 8192));
      } finally {
        picture.dispose();
      }

      if (_disposed) {
        image.dispose();
        return;
      }
      _images.remove(key)?.dispose();
      _images[key] = image;
      // Oldest out once over [_keep].
      while (_images.length > _keep) {
        var oldest = _images.keys.first;
        _images.remove(oldest)?.dispose();
      }
      notifyListeners();
    } finally {
      _making.remove(key);
    }
  }

  /// latestFor is the most recent picture made of [spec] at any size, for
  /// a gesture to stretch while it resizes one rather than generating the
  /// pattern at every size it passes through.
  ui.Image? latestFor(ProceduralSpec spec) {
    if (moves(spec)) return null;
    var prefix = "${_specKey(spec)}|";
    for (var key in _images.keys.toList().reversed) {
      if (key.startsWith(prefix)) return _images[key];
    }
    return null;
  }

  /// warm starts [spec] being rasterised at [size] if it is not held, for a
  /// backdrop about to be needed. Otherwise its first frame shows
  /// [imageFor]'s stand-in, which during playback is a page's paper flashing
  /// the colour of the page before it.
  void warm(ProceduralSpec spec, ui.Size size, [CanvasImageSource? images]) {
    if (moves(spec) || size.width < 1 || size.height < 1) return;
    var key = keyFor(spec, size, 0, images);
    var held = _images.remove(key);
    if (held != null) {
      _images[key] = held;
      return;
    }
    if (!_making.contains(key)) _make(spec, size, 0, key, images);
  }

  @override
  void dispose() {
    _disposed = true;
    for (var image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
