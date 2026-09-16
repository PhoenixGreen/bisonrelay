import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:flutter/foundation.dart';

// procedural_cache.dart keeps the last generated background as a picture, so
// the editor draws it once rather than once a frame.
//
// A generated background is the most expensive thing on a canvas by a wide
// margin -- flowWaves, the one under the Banner preset, was the best part of a
// second a frame before it was made cheaper, and is still a tenth of one --
// and the editor repaints for everything: a pointer moving over the stage, a
// dropdown opening, a settings panel rebuilding. Every one of those was
// waiting on the background being generated again to produce exactly the
// pixels it produced last time.
//
// So it is generated into an image, and while the design and the size hold
// still that image is what gets drawn. The exporter does not use this: it
// wants exact pixels at a size of its choosing and renders each frame once
// anyway.

/// ProceduralCache is one background, rasterised.
///
/// One rather than a map of them, deliberately. There is a single canvas open
/// at a time and its background changes when somebody edits it -- a cache of
/// several would be several megabytes of pixels kept for designs nobody is
/// looking at any more.
class ProceduralCache extends ChangeNotifier {
  ui.Image? _image;
  String? _for;

  /// _making is the key currently being rasterised, so a slow generator is
  /// not started again on every frame while the first one is still running.
  String? _making;

  bool _disposed = false;

  /// keyFor is what makes two requests the same request: the design, the size
  /// it is wanted at, -- for a background that moves -- the moment, and which
  /// of the pictures it uses have arrived.
  ///
  /// The pictures matter because they arrive late: a design that carries an
  /// icon is first drawn without it, while the file is still being read, and
  /// the drawing that comes back a moment later is a different picture of the
  /// same design. Left out of the key, the first answer was kept and the icon
  /// never appeared at all.
  static String keyFor(ProceduralSpec spec, ui.Size size, double time,
          [CanvasImageSource? images]) =>
      "${spec.toJson()}|${size.width.round()}x${size.height.round()}"
      "|${spec.animated ? time.toStringAsFixed(3) : ""}"
      "|${_ready(spec, images)}";

  /// _ready is which of a design's pictures can be drawn right now.
  static String _ready(ProceduralSpec spec, CanvasImageSource? images) {
    if (images == null) return "";
    var assets = [
      for (var icon in spec.rings.icons) ...[
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
  /// Asking for one that is not ready starts it, and hands back the last one
  /// while it is being made. The last one is a design or two behind -- for
  /// the length of one raster -- and that is the better answer: the
  /// alternative is the caller generating the new design itself, on the frame
  /// it was asked for and on every frame after it until the raster lands,
  /// which for an expensive generator is the whole of a drag.
  ///
  /// It used to return null there, on the grounds that a late frame is worse
  /// than an expensive one. That was written when the dearest generator cost
  /// a tenth of a second; the Metal texture shades a point per pixel, and
  /// dragging its Roughness slider re-shaded the sheet on every frame of the
  /// drag. A background one raster out of date is not something anybody can
  /// see. A canvas that stops moving is.
  ///
  /// Only at the size asked for. A picture of the right design at the wrong
  /// shape is a stretched background, which is something anybody can see.
  ui.Image? imageFor(ProceduralSpec spec, ui.Size size, double time,
      [CanvasImageSource? images]) {
    // A background that moves is a different picture every frame, so caching
    // it would be a raster per frame plus the drawing -- worse than simply
    // drawing it.
    if (spec.animated) return null;
    if (size.width < 1 || size.height < 1) return null;

    var key = keyFor(spec, size, time, images);
    if (key == _for) return _image;
    if (key != _making) _make(spec, size, time, key, images);

    var last = _image;
    if (last != null &&
        last.width == size.width.round().clamp(1, 8192) &&
        last.height == size.height.round().clamp(1, 8192)) {
      return last;
    }
    return null;
  }

  Future<void> _make(ProceduralSpec spec, ui.Size size, double time, String key,
      CanvasImageSource? images) async {
    _making = key;
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
      // Whatever was there goes: it is a picture of a design nobody is
      // looking at any more, and these are megabytes each.
      _image?.dispose();
      _image = image;
      _for = key;
      notifyListeners();
    } finally {
      if (_making == key) _making = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
