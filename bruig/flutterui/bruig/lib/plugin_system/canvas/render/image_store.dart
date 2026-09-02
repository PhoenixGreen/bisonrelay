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

  /// putForTest seeds the store with an already-decoded picture.
  ///
  /// The retouching brush cannot do anything without one -- a stroke is stored
  /// in the picture's own coordinates, so with nothing loaded there is nothing
  /// to convert against and the stroke goes nowhere. Loading normally means a
  /// file on disk and an asynchronous decode, neither of which a widget test
  /// has, so this is the seam.
  @visibleForTesting
  void putForTest(String assetId, ui.Image image) {
    _images[assetId] = image;
  }

  /// original is the picture as it was loaded, with nothing taken out.
  ///
  /// What the retouching brush measures against: a stroke is stored in the
  /// picture's own pixels, and those do not change when a background is
  /// removed -- the removal only rewrites the alpha. Asking [resolve] instead
  /// would hand back null until the treated copy had been built, so the first
  /// stroke of a session would land nowhere.
  ui.Image? original(String assetId) => _images[assetId];

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

  if (!removal.active) return null;
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
      // Not a return: the brush still has to run. Painting the background out
      // by hand with no method chosen is a legitimate way to use this, and on
      // a photograph no automatic method can do it is the only way.
      break;
    case RemovalMode.chromaKey:
      _chromaKey(pixels, removal);
    case RemovalMode.luminance:
      _luminance(pixels, removal);
    case RemovalMode.cornerFlood:
      _cornerFlood(pixels, width, height, removal);
    case RemovalMode.learn:
      _learn(pixels, width, height, removal);
  }

  // Last, so a stroke is always the final word: the reader can put back a hand
  // the automatic pass ate and take out a patch it missed without changing the
  // settings, and without one undoing the other.
  _paintStrokes(pixels, width, height, removal.strokes);
}

/// _paintStrokes rubs the brush's marks into the alpha channel.
///
/// Each stroke is a run of dabs along its points, which is what a brush is:
/// stamping only at the recorded points leaves a dotted line whenever the
/// pointer moved faster than the samples arrived, so the gap between each pair
/// is filled in.
void _paintStrokes(Uint8List pixels, int width, int height,
    List<RemovalStroke> strokes) {
  if (strokes.isEmpty) return;
  var shorter = math.min(width, height);

  for (var stroke in strokes) {
    var radius = math.max(1.0, stroke.radius * shorter);
    if (stroke.points.isEmpty) continue;

    for (var i = 0; i < stroke.points.length; i++) {
      var from =
          ui.Offset(stroke.points[i].dx * width, stroke.points[i].dy * height);
      var to = i + 1 < stroke.points.length
          ? ui.Offset(stroke.points[i + 1].dx * width,
              stroke.points[i + 1].dy * height)
          : from;

      // One dab per third of a radius along the segment: closer than that is
      // wasted work, further apart and a soft brush beads into a string of
      // blobs rather than reading as one stroke.
      var span = (to - from).distance;
      var steps = math.max(1, (span / (radius / 3)).ceil());
      for (var step = 0; step <= steps; step++) {
        _dab(pixels, width, height, ui.Offset.lerp(from, to, step / steps)!,
            radius, stroke);
      }
    }
  }
}

/// _dab is one press of the brush.
///
/// Two things make it a brush rather than a rubber stamp. It fades towards its
/// rim, so strokes blend into one another and into whatever the automatic pass
/// left, and it can be told to spread only through pixels like the one it
/// started on -- see RemovalStroke.snap -- so brushing along a shoulder takes
/// the sky and stops at the coat.
void _dab(Uint8List pixels, int width, int height, ui.Offset at, double radius,
    RemovalStroke stroke) {
  var left = math.max(0, (at.dx - radius).floor());
  var right = math.min(width - 1, (at.dx + radius).ceil());
  var top = math.max(0, (at.dy - radius).floor());
  var bottom = math.min(height - 1, (at.dy + radius).ceil());
  if (right < left || bottom < top) return;

  var centreX = at.dx.round().clamp(0, width - 1);
  var centreY = at.dy.round().clamp(0, height - 1);
  var reachable =
      stroke.snap > 0 ? _reachable(pixels, width, left, right, top, bottom,
          centreX, centreY, stroke.snap, radius) : null;

  var target = stroke.keep ? 255.0 : 0.0;
  // Everything within this is fully affected; beyond it the dab fades out.
  var solid = radius * stroke.hardness.clamp(0.0, 1.0);
  var fade = math.max(0.001, radius - solid);

  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      var dx = x - at.dx, dy = y - at.dy;
      var distance = math.sqrt(dx * dx + dy * dy);
      if (distance > radius) continue;

      var index = y * width + x;
      if (reachable != null &&
          reachable[(y - top) * (right - left + 1) + (x - left)] == 0) {
        continue;
      }

      var strength = distance <= solid ? 1.0 : (radius - distance) / fade;
      if (strength <= 0) continue;

      var p = index * 4 + 3;
      var now = pixels[p].toDouble();
      pixels[p] = (now + (target - now) * strength).round().clamp(0, 255);
    }
  }
}

/// _reachable is the part of a dab's disc joined to its centre by pixels of a
/// similar colour.
///
/// A flood inside the brush and nowhere else, so it costs what the brush costs
/// and cannot run away across the picture the way a full-frame one can.
Uint8List _reachable(Uint8List pixels, int width, int left, int right, int top,
    int bottom, int centreX, int centreY, double snap, double radius) {
  var boxWidth = right - left + 1;
  var boxHeight = bottom - top + 1;
  var out = Uint8List(boxWidth * boxHeight);

  const diagonal = 441.6729559300637;
  var tolerance = snap * diagonal;
  var centre = (centreY * width + centreX) * 4;
  var stack = <int>[(centreY - top) * boxWidth + (centreX - left)];

  while (stack.isNotEmpty) {
    var local = stack.removeLast();
    if (local < 0 || local >= out.length || out[local] != 0) continue;
    var lx = local % boxWidth, ly = local ~/ boxWidth;
    var x = left + lx, y = top + ly;

    var dx = x - centreX, dy = y - centreY;
    if (math.sqrt(dx * dx + dy * dy) > radius) continue;

    var p = (y * width + x) * 4;
    var dr = pixels[p] - pixels[centre];
    var dg = pixels[p + 1] - pixels[centre + 1];
    var db = pixels[p + 2] - pixels[centre + 2];
    if (math.sqrt(dr * dr + dg * dg + db * db) > tolerance) continue;

    out[local] = 1;
    if (lx > 0) stack.add(local - 1);
    if (lx < boxWidth - 1) stack.add(local + 1);
    if (ly > 0) stack.add(local - boxWidth);
    if (ly < boxHeight - 1) stack.add(local + boxWidth);
  }
  return out;
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
/// It walks outwards from the border and stops **where the picture changes
/// suddenly**, not where the colour stops matching something. That is the
/// whole idea, and it is what makes this usable on a photograph rather than
/// only on a flat backdrop: a background is nearly always smooth -- out of
/// focus, or a wall, or a sky -- while the subject has a crisp outline, so
/// "keep going while it changes gently, stop where it changes sharply"
/// separates them far better than any judgement about colour can.
///
/// Two earlier versions judged each pixel against a fixed colour instead: the
/// picture's top-left pixel, and then each edge seed's own. Both fail on the
/// same photograph for the same reason -- a background running from bright
/// bokeh to near-black is nowhere near any one colour, so the tolerance that
/// reaches the dark half has already eaten the subject. On the reported
/// stadium shot it had to be set so low that half the background survived and
/// the shirt was still being nibbled.
///
/// [BackgroundRemoval.edge] is the local step: how much the picture may change
/// from one pixel to the next and still count as the same region.
/// [BackgroundRemoval.tolerance] is a drift budget on top of it, so a very
/// gradual ramp cannot creep from the border all the way through the subject
/// and out the other side. Neither alone is enough: the local step follows
/// gradients but would follow one anywhere, and the budget bounds it.
///
/// An explicit stack rather than recursion: a full-frame flood on a large
/// picture is millions of pixels deep and would overflow.
void _cornerFlood(
    Uint8List pixels, int width, int height, BackgroundRemoval removal) {
  var count = width * height;
  var seen = Uint8List(count);
  var removed = Uint8List(count);

  const diagonal = 441.6729559300637;
  var step = math.max(removal.edge, 0.002) * diagonal;
  var budget = math.max(removal.tolerance, removal.edge) * diagonal;

  double distance(int a, int b) {
    var p = a * 4, q = b * 4;
    var dr = pixels[p] - pixels[q];
    var dg = pixels[p + 1] - pixels[q + 1];
    var db = pixels[p + 2] - pixels[q + 2];
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  // Each entry is the pixel to consider, the pixel it was reached from, and
  // the seed the whole chain started at -- the first for the local step, the
  // last for the drift budget.
  var stack = <int>[];
  void push(int index, int from, int seed) {
    stack..add(index)..add(from)..add(seed);
  }

  // Seeded from every edge pixel rather than from the four corners, so a
  // subject that touches one corner does not stop the rest of the background
  // being found.
  for (var x = 0; x < width; x++) {
    push(x, x, x);
    var bottom = (height - 1) * width + x;
    push(bottom, bottom, bottom);
  }
  for (var y = 0; y < height; y++) {
    push(y * width, y * width, y * width);
    var right = y * width + width - 1;
    push(right, right, right);
  }

  while (stack.isNotEmpty) {
    var seed = stack.removeLast();
    var from = stack.removeLast();
    var index = stack.removeLast();
    if (index < 0 || index >= count || seen[index] != 0) continue;

    // The step from the pixel this was reached through. An edge in the picture
    // is a big step, and an edge is where the background ends.
    if (index != from && distance(index, from) > step) continue;
    // And no further from where this chain started than the budget allows.
    if (distance(index, seed) > budget) continue;

    // Marked only once it is accepted. Marking on sight -- which is what the
    // shared visited array did -- also marked every pixel the flood merely
    // looked at and rejected, so inverting the mask kept the subject *and* a
    // halo of everything the flood had touched around it.
    seen[index] = 1;
    removed[index] = 1;
    pixels[index * 4 + 3] = 0;

    var x = index % width, y = index ~/ width;
    if (x > 0) push(index - 1, index, seed);
    if (x < width - 1) push(index + 1, index, seed);
    if (y > 0) push(index - width, index, seed);
    if (y < height - 1) push(index + width, index, seed);
  }

  if (removal.invert) {
    for (var i = 0; i < count; i++) {
      pixels[i * 4 + 3] = removed[i] != 0 ? 255 : 0;
    }
  }

  if (removal.softness > 0) _featherAlpha(pixels, width, height, removal);
}

/// _learn removes the background by comparing it with the subject, from marks
/// the reader has drawn on each.
///
/// The other three methods ask for a number that stands for something nobody
/// can see: how far apart two colours are, how sharply an edge changes. On a
/// photograph there is usually no such number -- the reported stadium shot has
/// a white shirt touching bright highlights and a soft outline against a dark
/// crowd, and every threshold that keeps the background out also takes part of
/// the player. This asks instead for the one thing anybody can see perfectly
/// well: which part is the background.
///
/// Three steps, none of them clever:
///
///   1. Collect the colours under each set of marks, coarsely -- to five bits
///      a channel, which is about as finely as a photograph's noise allows
///      anything to be told apart anyway.
///   2. Decide, once per colour rather than once per pixel, which side of the
///      evidence it falls on. That is a table of 32768 entries built in a few
///      milliseconds and then read for free.
///   3. Flood outwards from the background marks and from any border that
///      looks like background, through pixels the table calls background.
///
/// The flood in step three is what stops a white shirt going when the
/// background also has white in it: the shirt is only removed if there is a
/// path to it through other background-looking pixels, and a subject mark
/// blocks the way.
void _learn(
    Uint8List pixels, int width, int height, BackgroundRemoval removal) {
  var background = _paletteOf(pixels, width, height, removal.backgroundHints);
  var subject = _paletteOf(pixels, width, height, removal.subjectHints);
  // With nothing to compare there is nothing to learn, and taking a guess here
  // would remove something arbitrary the moment the mode was chosen.
  if (background.isEmpty || subject.isEmpty) return;

  var table = _classify(background, subject, removal.tolerance);

  var count = width * height;
  var seen = Uint8List(count);
  var removed = Uint8List(count);
  var stack = <int>[];

  // A subject mark is a barrier: whatever is under it is kept, and the flood
  // cannot pass through it to reach what is behind.
  var blocked = Uint8List(count);
  _markPixels(blocked, width, height, removal.subjectHints, 1);

  void seed(int index) {
    if (index < 0 || index >= count || blocked[index] != 0) return;
    stack.add(index);
  }

  // From the marks themselves, which are background by definition...
  var marked = Uint8List(count);
  _markPixels(marked, width, height, removal.backgroundHints, 1);
  for (var i = 0; i < count; i++) {
    if (marked[i] != 0) seed(i);
  }
  // ...and from any edge that looks like background, so the reader does not
  // have to trace all four sides to have the obvious parts taken out.
  for (var x = 0; x < width; x++) {
    seed(x);
    seed((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }

  while (stack.isNotEmpty) {
    var index = stack.removeLast();
    if (index < 0 || index >= count || seen[index] != 0) continue;
    if (blocked[index] != 0) continue;
    seen[index] = 1;

    // A background mark is taken on trust; anything else has to look like
    // background according to the table.
    if (marked[index] == 0 && table[_bin(pixels, index)] == 0) continue;

    removed[index] = 1;
    pixels[index * 4 + 3] = 0;

    var x = index % width, y = index ~/ width;
    if (x > 0) stack.add(index - 1);
    if (x < width - 1) stack.add(index + 1);
    if (y > 0) stack.add(index - width);
    if (y < height - 1) stack.add(index + width);
  }

  if (removal.invert) {
    for (var i = 0; i < count; i++) {
      pixels[i * 4 + 3] = removed[i] != 0 ? 255 : 0;
    }
  }

  if (removal.softness > 0) _featherAlpha(pixels, width, height, removal);
}

/// _bin is a pixel's colour reduced to five bits a channel.
int _bin(Uint8List pixels, int index) {
  var p = index * 4;
  return ((pixels[p] >> 3) << 10) |
      ((pixels[p + 1] >> 3) << 5) |
      (pixels[p + 2] >> 3);
}

/// _paletteOf is the set of coarse colours found under [marks].
Set<int> _paletteOf(Uint8List pixels, int width, int height,
    Iterable<RemovalStroke> marks) {
  var found = Uint8List(32768);
  var canvas = Uint8List(width * height);
  _markPixels(canvas, width, height, marks, 1);
  for (var i = 0; i < canvas.length; i++) {
    if (canvas[i] != 0) found[_bin(pixels, i)] = 1;
  }
  var out = <int>{};
  for (var i = 0; i < found.length; i++) {
    if (found[i] != 0) out.add(i);
  }
  return out;
}

/// _classify decides, for every colour there is, whether it belongs to the
/// background or the subject.
///
/// Once per colour rather than once per pixel: 32768 entries against a few
/// hundred samples is a few million comparisons and happens once, where the
/// same work per pixel on a twelve-megapixel photograph would not finish.
///
/// [bias] shifts the boundary between the two. At a half it is a fair fight;
/// higher takes more, which is the dial to reach for when a little background
/// survives.
Uint8List _classify(Set<int> background, Set<int> subject, double bias) {
  var table = Uint8List(32768);
  var backgroundList = background.toList();
  var subjectList = subject.toList();
  var lean = 0.5 + bias.clamp(0.0, 1.0);

  double nearest(List<int> palette, int r, int g, int b) {
    var best = double.infinity;
    for (var colour in palette) {
      var dr = r - ((colour >> 10) & 31);
      var dg = g - ((colour >> 5) & 31);
      var db = b - (colour & 31);
      var d = (dr * dr + dg * dg + db * db).toDouble();
      if (d < best) best = d;
    }
    return math.sqrt(best);
  }

  for (var i = 0; i < table.length; i++) {
    var r = (i >> 10) & 31, g = (i >> 5) & 31, b = i & 31;
    var toBackground = nearest(backgroundList, r, g, b);
    var toSubject = nearest(subjectList, r, g, b);
    table[i] = toBackground < toSubject * lean ? 1 : 0;
  }
  return table;
}

/// _markPixels rasterises brush marks into a per-pixel flag.
void _markPixels(Uint8List into, int width, int height,
    Iterable<RemovalStroke> marks, int value) {
  var shorter = math.min(width, height);
  for (var mark in marks) {
    var radius = math.max(1.0, mark.radius * shorter);
    for (var i = 0; i < mark.points.length; i++) {
      var from = ui.Offset(
          mark.points[i].dx * width, mark.points[i].dy * height);
      var to = i + 1 < mark.points.length
          ? ui.Offset(mark.points[i + 1].dx * width,
              mark.points[i + 1].dy * height)
          : from;
      var span = (to - from).distance;
      var steps = math.max(1, (span / (radius / 2)).ceil());
      for (var step = 0; step <= steps; step++) {
        var at = ui.Offset.lerp(from, to, step / steps)!;
        var left = math.max(0, (at.dx - radius).floor());
        var right = math.min(width - 1, (at.dx + radius).ceil());
        var top = math.max(0, (at.dy - radius).floor());
        var bottom = math.min(height - 1, (at.dy + radius).ceil());
        var squared = radius * radius;
        for (var y = top; y <= bottom; y++) {
          for (var x = left; x <= right; x++) {
            var dx = x - at.dx, dy = y - at.dy;
            if (dx * dx + dy * dy > squared) continue;
            into[y * width + x] = value;
          }
        }
      }
    }
  }
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
