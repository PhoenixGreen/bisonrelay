import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:flutter/foundation.dart';

// image_store.dart decodes the pictures a canvas uses, and cuts their
// backgrounds out.
//
// It is the asynchronous half of drawing an image: the renderer is synchronous
// and cannot wait for a file, so it asks this for a decoded picture and draws
// a placeholder when the answer is null. The store then loads it and notifies,
// and the next frame has it. That is the whole contract, and it is why an
// image arriving late never stalls a frame or leaves the rest of the document
// undrawn.
//
// Everything is keyed by the *result*, not the source: a picture with a colour
// key applied is a different entry from the same picture without one, so
// switching a removal mode on and off is instant after the first time and two
// elements sharing both the picture and the settings share one decode.

/// _maxEntries bounds the cache.
///
/// Pictures are large -- a decoded 4000x3000 photograph is 48MB of RGBA -- so
/// this is small on purpose and evicts the least recently asked for. A canvas
/// with more distinct pictures than this on it at once is possible, and the
/// cost is redecoding as they scroll through; the cost of not bounding it is
/// the app running out of memory, which is worse.
const int _maxEntries = 48;

/// CanvasImageStore holds decoded pictures for a canvas being edited.
class CanvasImageStore extends ChangeNotifier implements CanvasImageSource {
  final Map<String, ui.Image> _images = {};

  /// _order is the keys in least-recently-used order, which is what makes the
  /// bound above evict something sensible rather than something arbitrary.
  final List<String> _order = [];

  /// _pending stops the same picture being decoded four times when four
  /// elements ask for it in one frame.
  final Set<String> _pending = {};

  /// _failed remembers what could not be loaded, so a missing picture is asked
  /// for once rather than on every single frame forever.
  final Set<String> _failed = {};

  bool _disposed = false;

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) {
    if (assetId.isEmpty) return null;
    var key = removal.active ? removal.cacheKey(assetId) : assetId;

    var image = _images[key];
    if (image != null) {
      _touch(key);
      return image;
    }
    if (!_pending.contains(key) && !_failed.contains(key)) {
      _pending.add(key);
      _load(assetId, removal, key);
    }
    return null;
  }

  void _touch(String key) {
    _order.remove(key);
    _order.add(key);
  }

  Future<void> _load(
      String assetId, BackgroundRemoval removal, String key) async {
    try {
      var bytes = await CanvasAssets.load(assetId);
      if (bytes == null) {
        _failed.add(key);
        return;
      }

      var codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      var frame = await codec.getNextFrame();
      var image = frame.image;

      if (removal.active) {
        var cut = await _removeBackground(image, removal);
        if (cut != null) {
          image.dispose();
          image = cut;
        }
      }

      if (_disposed) {
        image.dispose();
        return;
      }

      _images[key] = image;
      _touch(key);
      _evict();
      notifyListeners();
    } catch (exception) {
      debugPrint("Unable to load the canvas picture $assetId: $exception");
      _failed.add(key);
    } finally {
      _pending.remove(key);
    }
  }

  void _evict() {
    while (_order.length > _maxEntries) {
      var key = _order.removeAt(0);
      _images.remove(key)?.dispose();
    }
  }

  /// forget drops one asset's entries, so that replacing a picture in place
  /// shows the new one rather than the cached old one.
  void forget(String assetId) {
    var keys = _images.keys.where((k) => k.startsWith(assetId)).toList();
    for (var key in keys) {
      _order.remove(key);
      _images.remove(key)?.dispose();
    }
    _failed.removeWhere((k) => k.startsWith(assetId));
    if (keys.isNotEmpty) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (var image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _order.clear();
    super.dispose();
  }
}

/// removeBackground applies [removal] to [image], returning a new picture with
/// an alpha channel cut into it.
///
/// Exposed for tests, which check the three modes against pictures whose
/// answer is known -- the alternative is discovering a broken colour key by
/// looking at one.
@visibleForTesting
Future<ui.Image?> removeBackground(
        ui.Image image, BackgroundRemoval removal) =>
    _removeBackground(image, removal);

Future<ui.Image?> _removeBackground(
    ui.Image image, BackgroundRemoval removal) async {
  var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;

  var pixels = data.buffer.asUint8List();
  var width = image.width, height = image.height;

  if (removal.mode == RemovalMode.none) return null;
  applyRemovalForTest(pixels, width, height, removal);

  // decodeImageFromPixels rather than re-encoding to PNG and decoding that:
  // the pixels are already exactly what is wanted, and a PNG round trip on a
  // twelve-megapixel photograph is most of a second for no change at all.
  var completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// _alphaFor turns a distance and the tolerance into an alpha.
///
/// Inside the tolerance a pixel is fully removed; over the next [softness] it
/// fades back in. That ramp is what stops a cut-out having a hard jagged
/// boundary one pixel wide, which is the single most obvious sign of a
/// mechanically removed background.
int _alphaFor(double distance, double tolerance, double softness, int current) {
  if (distance <= tolerance) return 0;
  if (softness <= 0 || distance >= tolerance + softness) return current;
  var t = (distance - tolerance) / softness;
  return (current * t).round().clamp(0, 255);
}

/// applyRemovalForTest runs a removal over raw RGBA pixels in place.
///
/// The whole of the work, with the image decoding either side of it left out.
/// Exposed because that is where every question worth asking of this code
/// lives -- does a two-tone background go, does a gradient creep into the
/// subject, does inverting keep a halo -- and none of them can be asked of a
/// photograph nobody can check into a repository. See canvas_removal_test.
@visibleForTesting
void applyRemovalForTest(
    Uint8List pixels, int width, int height, BackgroundRemoval removal) {
  switch (removal.mode) {
    case RemovalMode.none:
      return;
    case RemovalMode.chromaKey:
      _chromaKey(pixels, removal);
    case RemovalMode.luminance:
      _luminance(pixels, removal);
    case RemovalMode.cornerFlood:
      _cornerFlood(pixels, width, height, removal);
  }
}

/// _chromaKey removes everything close to one colour.
void _chromaKey(Uint8List pixels, BackgroundRemoval removal) {
  var kr = removal.keyColor.r * 255;
  var kg = removal.keyColor.g * 255;
  var kb = removal.keyColor.b * 255;
  // Normalised by the RGB cube's diagonal so that the tolerance slider means
  // the same thing wherever the key colour sits.
  const diagonal = 441.6729559300637;

  for (var i = 0; i < pixels.length; i += 4) {
    var dr = pixels[i] - kr;
    var dg = pixels[i + 1] - kg;
    var db = pixels[i + 2] - kb;
    var d = math.sqrt(dr * dr + dg * dg + db * db) / diagonal;
    var alpha =
        _alphaFor(d, removal.tolerance, removal.softness, pixels[i + 3]);
    pixels[i + 3] = removal.invert ? pixels[i + 3] - alpha : alpha;
  }
}

/// _luminance removes everything brighter (or, inverted, darker) than a
/// threshold.
void _luminance(Uint8List pixels, BackgroundRemoval removal) {
  for (var i = 0; i < pixels.length; i += 4) {
    var l = (pixels[i] * 0.2126 + pixels[i + 1] * 0.7152 + pixels[i + 2] * 0.0722) /
        255;
    // How far past the threshold this pixel is, positive when it should go.
    // Negated into a distance so the same ramp _alphaFor applies to a colour
    // key applies here: at or past the threshold the distance is zero or less
    // and the pixel is removed outright, and the softness fades the rest back
    // in.
    var over = removal.invert ? removal.threshold - l : l - removal.threshold;
    pixels[i + 3] = _alphaFor(-over, 0, removal.softness, pixels[i + 3]);
  }
}

/// _cornerFlood removes the connected region touching the picture's edges.
///
/// The one of the three that handles a background that is not flat: a
/// photograph on a wall that shades from light to dark is one connected region
/// within a tolerance of its neighbours, and a colour key would either leave
/// half of it or eat into the subject. It also cannot remove a colour that
/// happens to appear *inside* the subject, which a colour key always does --
/// the white of an eye going transparent along with the white background is
/// the commonest complaint about chroma keying a logo.
///
/// **Every edge pixel is its own seed, with its own colour.** That is the
/// difference between this working on a real photograph and not. It used to
/// compare the whole flood against one colour -- the picture's top-left pixel
/// -- so a stadium shot whose background runs from bright bokeh on one side to
/// near-black on the other could not be covered by any tolerance at all: raise
/// it enough to reach the dark and it eats the subject, leave it low and half
/// the background stays. Per seed, the bright region is found from the bright
/// edges and the dark region from the dark ones, and neither has to know about
/// the other.
///
/// The reference does *not* drift as the flood spreads. Comparing each pixel
/// to its neighbour instead would let a gradual gradient walk the whole way
/// into the subject one small step at a time, which is the failure the single
/// seed was avoiding -- this keeps that guarantee and drops the assumption
/// that the background is one colour.
///
/// An explicit stack rather than recursion: a full-frame flood on a large
/// picture is millions of pixels deep and would overflow.
void _cornerFlood(
    Uint8List pixels, int width, int height, BackgroundRemoval removal) {
  var count = width * height;
  var seen = Uint8List(count);
  var removed = Uint8List(count);

  // Each entry is a pixel and the colour it is to be judged against, so a
  // flood that started on a bright edge keeps comparing to that brightness
  // however far it travels.
  var stack = <int>[];
  void seed(int index) {
    stack..add(index)..add(index);
  }

  // Seeded from every edge pixel rather than from the four corners, so a
  // subject that touches one corner does not stop the rest of the background
  // being found.
  for (var x = 0; x < width; x++) {
    seed(x);
    seed((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }

  const diagonal = 441.6729559300637;
  var tolerance = removal.tolerance * diagonal;

  while (stack.isNotEmpty) {
    var reference = stack.removeLast();
    var index = stack.removeLast();
    if (index < 0 || index >= count || seen[index] != 0) continue;

    var p = index * 4;
    var r = reference * 4;
    var dr = pixels[p] - pixels[r];
    var dg = pixels[p + 1] - pixels[r + 1];
    var db = pixels[p + 2] - pixels[r + 2];
    if (math.sqrt(dr * dr + dg * dg + db * db) > tolerance) continue;

    // Marked only once it is accepted. Marking on sight -- which is what the
    // shared visited array did -- also marked every pixel the flood merely
    // looked at and rejected, so inverting the mask kept the subject *and*
    // a halo of everything the flood had touched around it.
    seen[index] = 1;
    removed[index] = 1;
    pixels[p + 3] = 0;

    var x = index % width, y = index ~/ width;
    if (x > 0) stack..add(index - 1)..add(reference);
    if (x < width - 1) stack..add(index + 1)..add(reference);
    if (y > 0) stack..add(index - width)..add(reference);
    if (y < height - 1) stack..add(index + width)..add(reference);
  }

  if (removal.invert) {
    for (var i = 0; i < count; i++) {
      pixels[i * 4 + 3] = removed[i] != 0 ? 255 : 0;
    }
  }

  if (removal.softness > 0) _featherAlpha(pixels, width, height, removal);
}

/// _featherAlpha softens the edge the removal left behind.
///
/// A flood gives every pixel all or nothing, which on anything with a soft
/// outline -- hair, most of all -- leaves a hard staircase where a photograph
/// had a gradual one. This averages the alpha over a small neighbourhood, but
/// only where there is an edge to soften: a pixel surrounded by pixels that
/// agree with it is left exactly as it was, so the middle of the subject stays
/// solid and the middle of the hole stays empty.
void _featherAlpha(
    Uint8List pixels, int width, int height, BackgroundRemoval removal) {
  var radius = (removal.softness * 3).round().clamp(1, 6);
  var count = width * height;
  var alpha = Uint8List(count);
  for (var i = 0; i < count; i++) {
    alpha[i] = pixels[i * 4 + 3];
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var index = y * width + x;
      var here = alpha[index];

      var total = 0;
      var seen = 0;
      var mixed = false;
      for (var dy = -radius; dy <= radius; dy++) {
        var ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (var dx = -radius; dx <= radius; dx++) {
          var nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          var value = alpha[ny * width + nx];
          if (value != here) mixed = true;
          total += value;
          seen++;
        }
      }
      // Nothing to soften: every neighbour agrees, so this is the inside of
      // the subject or the inside of the hole.
      if (!mixed || seen == 0) continue;
      pixels[index * 4 + 3] = (total / seen).round().clamp(0, 255);
    }
  }
}
