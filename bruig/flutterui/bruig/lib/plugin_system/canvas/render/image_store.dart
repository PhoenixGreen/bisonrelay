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
  if (!removal.active) return null;

  // At the working size, like the preview. The result is drawn into a few
  // hundred pixels on a canvas and published at whatever the canvas is, so a
  // twelve-megapixel pass buys nothing anybody can see and costs the whole
  // wait -- and, worse, costs it again on every adjustment.
  //
  // The brush's own measurements are fractions of the picture rather than
  // pixel counts, so a stroke lands in the same place whichever size this is.
  var working = await _atWorkingSize(image);
  var data = await working.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;

  var pixels = data.buffer.asUint8List();
  var width = working.width, height = working.height;

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

/// _premultiply scales the colours to match the alpha they now have.
///
/// The pixel format either side of this file is premultiplied: a pixel's
/// colour channels are already multiplied by its own alpha, so a fully
/// transparent pixel is all zeroes and a half-transparent red is (128, 0, 0,
/// 128) rather than (255, 0, 0, 128).
///
/// Everything that removes a background writes alpha and leaves the colour
/// alone, which breaks that. A pixel taken out entirely kept its full colour
/// at zero alpha -- data that means nothing in premultiplied form, and which
/// Skia is free to draw as the colour rather than as nothing. That is a whole
/// picture washing over in whatever it happened to be, and it is why every
/// feathered edge glowed: a half-transparent pixel was carrying twice the
/// colour it should.
void _premultiply(Uint8List pixels, Uint8List was) {
  for (var i = 0; i < was.length; i++) {
    var before = was[i];
    if (before == 0) continue;
    var now = pixels[i * 4 + 3];
    if (now == before) continue;
    var scale = now / before;
    var p = i * 4;
    pixels[p] = (pixels[p] * scale).round().clamp(0, 255);
    pixels[p + 1] = (pixels[p + 1] * scale).round().clamp(0, 255);
    pixels[p + 2] = (pixels[p + 2] * scale).round().clamp(0, 255);
  }
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
  // What the alpha was before anything was taken out, so the colours can be
  // put back into the form Flutter expects afterwards. See _premultiply --
  // and note it belongs in here rather than around the call, because this
  // function claims to be the whole of the work and a caller that forgot the
  // other half would draw a picture washed over in its own colour.
  var was = Uint8List(width * height);
  for (var i = 0; i < was.length; i++) {
    was[i] = pixels[i * 4 + 3];
  }

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

  _premultiply(pixels, was);
}

/// strokePreview is a picture of what [stroke] would do, for showing on the
/// canvas before it is applied.
///
/// It runs the brush itself over a blank alpha channel rather than describing
/// what the brush would do, so the preview and the result cannot drift apart.
/// A stroke that clings to an edge is not a shape anybody can draw from its
/// settings -- it depends on the picture -- so the only honest preview is the
/// real thing.
///
/// Returned as RGBA in [colour], transparent where the stroke does not reach.
/// Sized to the whole picture: cropping to the stroke would mean carrying its
/// offset around, and the caller draws it through the same placement the
/// picture uses.
/// workingSize is the largest a picture is worked on at.
///
/// Background removal is a pass over every pixel, and several of them: a
/// twelve-megapixel photograph is twelve million pixels flooded, feathered and
/// premultiplied, and the brush's preview does the same again on every
/// adjustment. That is where the waiting was. Nothing here needs the full
/// resolution -- the result is drawn into a few hundred pixels on screen and
/// published at whatever the canvas is -- so the work is done on a copy no
/// bigger than this and scaled back up.
///
/// Sixteen hundred is a good deal more than a canvas ever shows and about
/// fifty times less work than a modern camera's output.
const int workingSize = 1600;

/// scaleForWork is how much a picture has to shrink to be worked on, or 1 when
/// it is already small enough.
double scaleForWork(int width, int height) {
  var longest = math.max(width, height);
  return longest <= workingSize ? 1 : workingSize / longest;
}

/// _workingPixels remembers the shrunk-down bytes of each picture.
///
/// Getting them is a draw onto a new surface and then a read back off the GPU
/// -- seven megabytes for a picture this size -- and the preview asks for them
/// again on every adjustment of every setting. The picture itself does not
/// change while a brush is being tuned, so this is asked once and kept.
///
/// Keyed by identity rather than by asset id: a picture that has been reloaded
/// is a different object, and the old bytes go with the old object.
final Map<ui.Image, _Working> _workingPixels = {};

class _Working {
  final Uint8List pixels;
  final int width;
  final int height;
  const _Working(this.pixels, this.width, this.height);
}

/// _workingCopy is [source] at the working size, as raw premultiplied bytes.
Future<_Working?> _workingCopy(ui.Image source) async {
  var cached = _workingPixels[source];
  if (cached != null) return cached;

  var working = await _atWorkingSize(source);
  var data = await working.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;

  // One picture at a time is all this is ever asked for, and holding several
  // megabytes for pictures nobody is editing is not worth the lookup it saves.
  _workingPixels.clear();
  var made = _Working(
      data.buffer.asUint8List(), working.width, working.height);
  _workingPixels[source] = made;
  return made;
}

/// _atWorkingSize returns [source] shrunk to something worth working on, or
/// the picture itself when it is already small.
Future<ui.Image> _atWorkingSize(ui.Image source) async {
  var scale = scaleForWork(source.width, source.height);
  if (scale >= 1) return source;

  var width = math.max(1, (source.width * scale).round());
  var height = math.max(1, (source.height * scale).round());
  var recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  return recorder.endRecording().toImage(width, height);
}

/// snapForStroke works out how far [stroke] should cling on [source]. See
/// suggestSnap, which does the work once the pixels are to hand.
Future<double?> snapForStroke(ui.Image source, RemovalStroke stroke) async {
  var working = await _workingCopy(source);
  if (working == null) return null;
  return suggestSnap(
      working.pixels, working.width, working.height, stroke);
}

Future<ui.Image?> strokePreview(ui.Image source, RemovalStroke stroke) async {
  // At the working size, and from the copy that was already made: a preview is
  // looked at rather than published, and it is rebuilt on every adjustment of
  // every setting.
  var working = await _workingCopy(source);
  if (working == null) return null;

  // Copied, because the coverage pass reads the picture and the tinting pass
  // below writes over it -- and the next adjustment wants the picture back.
  var pixels = Uint8List.fromList(working.pixels);
  var width = working.width, height = working.height;

  // The same arithmetic the stroke will be applied with, not a description of
  // it: neither a stroke that clings to an edge nor one that fills from it is a
  // shape anybody can draw from its settings, because both depend on what is
  // in the picture.
  var cover = strokeEffect(pixels, width, height, stroke);

  var out = Uint8List(width * height * 4);
  for (var i = 0; i < cover.length; i++) {
    var strength = cover[i];
    if (strength == 0) continue;

    // Coloured by how hard the brush is at that pixel rather than tinted
    // flat, because the thing being judged is where the falloff starts and
    // how far it runs. A flat wash showed neither: hardness could be moved
    // from end to end and the picture looked identical.
    //
    //   blue    fully taken -- inside the hard core
    //   yellow  barely taken -- the outer rim of the falloff
    //
    // So the width of the yellow band *is* the softness, and at a hardness of
    // one there is no yellow at all.
    var t = strength / 255;
    var r = ((1 - t) * 255).round();
    var g = ((1 - t) * 210 + t * 90).round();
    var b = (t * 255).round();

    // Half again on the alpha, so the picture underneath stays visible: this
    // is a guide over the work rather than a replacement for looking at it.
    var alpha = (strength * 0.75).round().clamp(0, 255);
    var scale = alpha / 255;
    out[i * 4] = (r * scale).round();
    out[i * 4 + 1] = (g * scale).round();
    out[i * 4 + 2] = (b * scale).round();
    out[i * 4 + 3] = alpha;
  }

  if (stroke.snap > 0) _markClingEdge(out, cover, width, height);

  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      out, width, height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _markClingEdge draws a dashed green line where cling decided to stop.
///
/// The one thing about cling nobody can otherwise see. Where the brush's own
/// rim runs out, the edge is a circle and obviously the brush; where cling
/// stopped it, the edge follows something in the picture -- and being able to
/// tell which is which is the difference between a setting that can be tuned
/// and a number that is guessed at.
void _markClingEdge(
    Uint8List out, Uint8List cover, int width, int height) {
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      var i = y * width + x;
      if (cover[i] == 0) continue;
      // On the boundary of what the stroke reaches.
      var edge = cover[i - 1] == 0 ||
          cover[i + 1] == 0 ||
          cover[i - width] == 0 ||
          cover[i + width] == 0;
      if (!edge) continue;
      // Dashed, so it reads as a guide rather than as part of the picture.
      if (((x + y) ~/ 4) % 2 == 0) continue;
      out[i * 4] = 0;
      out[i * 4 + 1] = 220;
      out[i * 4 + 2] = 90;
      out[i * 4 + 3] = 220;
      // Premultiplied, like everything else that goes into a Flutter image.
      var scale = 220 / 255;
      out[i * 4 + 1] = (220 * scale).round();
      out[i * 4 + 2] = (90 * scale).round();
    }
  }
}

/// suggestSnap works out how far a stroke should cling, from the picture
/// under it.
///
/// The number cling wants is "how different from the background does a pixel
/// have to be before it is not the background", and nobody can read that off a
/// photograph -- which is why setting it by hand never worked. But it is
/// visible in the picture: gather every pixel the stroke passes over, measure
/// how far each is from what the stroke started on, and the two things the
/// stroke crossed show up as two clusters of distances with a gap between.
///
/// Otsu's method finds that gap. It is the standard way to split a histogram
/// into two groups -- pick the threshold that leaves the least variation
/// *within* each group -- and it needs nothing to be told about either.
///
/// Returns null when there is no gap worth calling one: a stroke drawn
/// entirely on the background has one cluster, and inventing a split in it
/// would cut the background in half for no reason.
double? suggestSnap(
    Uint8List pixels, int width, int height, RemovalStroke stroke) {
  if (stroke.points.isEmpty) return null;

  var shorter = math.min(width, height);
  var radius = math.max(1.0, stroke.radius * shorter);
  var reference = _averageAround(
      pixels,
      width,
      height,
      (stroke.points.first.dx * width).round(),
      (stroke.points.first.dy * height).round(),
      math.max(1, radius ~/ 3));

  // How many pixels sit at each distance from that colour, in 256 steps of the
  // furthest two colours can be apart.
  const diagonal = 441.6729559300637;
  var counts = List<int>.filled(256, 0);
  var total = 0;

  for (var at in _alongPath([
    for (var point in stroke.points)
      ui.Offset(point.dx * width, point.dy * height),
  ], math.max(1.0, radius / 3))) {
    var left = math.max(0, (at.dx - radius).floor());
    var right = math.min(width - 1, (at.dx + radius).ceil());
    var top = math.max(0, (at.dy - radius).floor());
    var bottom = math.min(height - 1, (at.dy + radius).ceil());

    // Every third pixel: a histogram does not need all of them, and this is
    // run while somebody is waiting for the line to move.
    for (var y = top; y <= bottom; y += 3) {
      for (var x = left; x <= right; x += 3) {
        var dx = x - at.dx, dy = y - at.dy;
        if (dx * dx + dy * dy > radius * radius) continue;
        var p = (y * width + x) * 4;
        var away = _distance(
            [pixels[p].toDouble(), pixels[p + 1].toDouble(), pixels[p + 2].toDouble()],
            reference);
        var bin = (away / diagonal * 255).round().clamp(0, 255);
        counts[bin]++;
        total++;
      }
    }
  }
  if (total < 32) return null;

  var split = _otsu(counts, total);
  if (split == null) return null;

  // A little past the split, so the pixels sitting exactly on the boundary --
  // the blend along an outline -- fall inside the fading part of the tolerance
  // rather than outside it altogether.
  return ((split + 1.5) / 255).clamp(0.01, 0.6);
}

/// _otsu is the threshold that leaves the least variation within each of the
/// two groups it makes, or null when one group would be empty.
int? _otsu(List<int> counts, int total) {
  var sum = 0.0;
  for (var i = 0; i < counts.length; i++) {
    sum += i * counts[i];
  }

  var belowWeight = 0, best = -1.0;
  var belowSum = 0.0;
  // The first and last thresholds that are equally the best.
  //
  // On a picture of two flat colours every threshold between the two is
  // exactly as good, and taking the first of them puts the line hard against
  // the background -- so a faint edge came out as no tolerance at all. The
  // middle of the run is the one that sits between the two things.
  int? first, last;

  for (var i = 0; i < counts.length; i++) {
    belowWeight += counts[i];
    if (belowWeight == 0) continue;
    var aboveWeight = total - belowWeight;
    if (aboveWeight == 0) break;

    belowSum += i * counts[i];
    var belowMean = belowSum / belowWeight;
    var aboveMean = (sum - belowSum) / aboveWeight;
    var between =
        belowWeight * aboveWeight * (belowMean - aboveMean) * (belowMean - aboveMean);
    if (between > best) {
      best = between;
      first = i;
      last = i;
    } else if (between == best) {
      last = i;
    }
  }

  // A stroke drawn entirely on one thing has one cluster, and the best split
  // of one cluster separates nothing. Everything here is measured in 256ths of
  // the furthest two colours can be apart, so this is a real separation rather
  // than the noise inside a single surface.
  if (first == null || last == null || best <= 0) return null;
  return (first + last) ~/ 2;
}

/// strokeCoverage is how strongly a stroke touches each pixel, from 0 to 255.
///
/// The *most* any of the stroke's dabs reach a pixel, not the sum of them.
/// That is the whole reason this is a separate pass. Applying each dab to the
/// picture as it went meant a pixel under six overlapping dabs was blended
/// towards the target six times, and repeated blending arrives at the target
/// however gentle each step is -- so the feathered rim collapsed into a hard
/// edge everywhere except the two ends of the stroke, and hardness appeared to
/// do nothing at all.
///
/// Shared with the preview, so what is shown and what will happen are the same
/// arithmetic rather than two descriptions of it.
Uint8List strokeCoverage(
    Uint8List pixels, int width, int height, RemovalStroke stroke) {
  var cover = Uint8List(width * height);
  if (stroke.points.isEmpty) return cover;

  var shorter = math.min(width, height);
  var radius = math.max(1.0, stroke.radius * shorter);

  // What the stroke is clinging *to*, sampled where it began.
  //
  // Once for the stroke, not once per dab. Per dab, the brush took its
  // reference from whatever happened to be under the pointer at that moment --
  // so the instant the stroke crossed onto the subject it re-learnt the
  // subject and started clinging to that instead, which is the opposite of the
  // whole idea.
  var reference = stroke.snap > 0
      ? _averageAround(
          pixels,
          width,
          height,
          (stroke.points.first.dx * width).round(),
          (stroke.points.first.dy * height).round(),
          math.max(1, radius ~/ 3))
      : null;

  const diagonal = 441.6729559300637;
  var tolerance = stroke.snap * diagonal;

  // Where the dabs go: every third of a radius along the stroke, measured by
  // distance travelled rather than per point.
  //
  // Per point was the whole of the slowness. A drag reports a couple of
  // hundred positions, and a dab was placed at each end of every one of the
  // segments between them -- so a stroke was six hundred dabs whether it
  // crossed the picture or wobbled in one place, and each dab is a flood over
  // its own square of the picture. Walking the length instead makes a long
  // stroke a dozen dabs and a short one two, which is what the spacing was
  // meant to say in the first place.
  var spacing = math.max(1.0, radius / 3);
  var path = [
    for (var point in stroke.points)
      ui.Offset(point.dx * width, point.dy * height),
  ];

  for (var at in _alongPath(path, spacing)) {
    // The reference is allowed to drift with the background -- a sky that
    // shades from one side to the other is still the background -- but only
    // towards colours it already agrees with. A pixel it does not recognise is
    // the subject, and the reference does not follow it.
    if (reference != null) {
      var here = _averageAround(pixels, width, height, at.dx.round(),
          at.dy.round(), math.max(1, radius ~/ 6));
      if (_distance(here, reference) <= tolerance) {
        reference = [
          reference[0] * 0.85 + here[0] * 0.15,
          reference[1] * 0.85 + here[1] * 0.15,
          reference[2] * 0.85 + here[2] * 0.15,
        ];
      }
    }

    _dab(cover, pixels, width, height, at, radius, stroke, reference);
  }
  return cover;
}

/// strokeEffect is everything a stroke reaches, from 0 to 255.
///
/// The same for a mark and for a boundary, so that the preview and the picture
/// go through one function and cannot come out differently. For an ordinary
/// stroke it is where the brush went; for a fill it is that *plus* everything
/// the picture's own edge can reach without crossing it.
Uint8List strokeEffect(
    Uint8List pixels, int width, int height, RemovalStroke stroke) {
  var cover = strokeCoverage(pixels, width, height, stroke);
  if (!stroke.fill) return cover;

  // A boundary is all or nothing, however soft the brush drawing it is.
  //
  // Left soft, the line's feathered rim carried partial coverage *inwards*
  // past the cut -- so a band of half-removed pixels hugged the inside of the
  // line and read as a strange outline drawn around the subject. A soft edge
  // is right for a mark, where it blends into what is around it; here there is
  // nothing on the inside to blend into, because the inside is being kept.
  for (var i = 0; i < cover.length; i++) {
    if (cover[i] != 0) cover[i] = 255;
  }

  // Everything reachable from the outside without crossing the line.
  //
  // From the edge inwards rather than from a point the reader picked: what is
  // being taken out is the background, and the background is what surrounds
  // the thing that is not. It also means a line that does not quite close --
  // and no line drawn by hand quite closes -- fails safe: the flood leaks
  // through the gap and takes more, which is visible and undoable, rather than
  // silently doing nothing.
  var reached = Uint8List(width * height);
  var stack = <int>[];

  void seed(int index) {
    if (index < 0 || index >= reached.length) return;
    if (reached[index] != 0 || cover[index] != 0) return;
    stack.add(index);
  }

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
    if (index < 0 || index >= reached.length) continue;
    if (reached[index] != 0 || cover[index] != 0) continue;
    reached[index] = 255;

    var x = index % width, y = index ~/ width;
    if (x > 0) stack.add(index - 1);
    if (x < width - 1) stack.add(index + 1);
    if (y > 0) stack.add(index - width);
    if (y < height - 1) stack.add(index + width);
  }

  // Inside out, when that is what was asked for: a hole cut out of something
  // rather than something cut free of its surroundings. What the boundary
  // encloses is simply everything the outside could not get to.
  if (stroke.fillInside) {
    for (var i = 0; i < reached.length; i++) {
      reached[i] = reached[i] == 0 ? 255 : 0;
    }
  }

  // The line itself goes with whichever side is being taken, so the cut lands
  // on the line rather than just to one side of it.
  for (var i = 0; i < reached.length; i++) {
    if (cover[i] > reached[i]) reached[i] = cover[i];
  }

  // Then softened, if a soft cut was asked for.
  //
  // The softness is applied to the finished outline rather than being carried
  // in from the brush that drew it. Carried in, the brush's own feathered rim
  // reached *past* the cut and left a band of half-removed pixels hugging the
  // inside of the line. Applied here it is what it sounds like: the edge of
  // the cut, blurred.
  //
  // Independent of the brush's size on purpose. How thickly the boundary is
  // drawn and how soft the cut is are two different decisions, and tying them
  // together meant a fat boundary brush gave a cut nobody could aim.
  var feather = ((1 - stroke.hardness.clamp(0.0, 1.0)) * _cutFeather).round();
  return feather <= 0 ? reached : _blur(reached, width, height, feather);
}

/// _cutFeather is how far the softest cut edge reaches, in working-size
/// pixels, counting both sides of the line.
const int _cutFeather = 12;

/// _blur is a box blur run twice, which is close enough to a smooth falloff
/// and is two passes of running sums rather than a kernel per pixel. Each
/// pass is half the asked-for radius, so the two together reach it.
Uint8List _blur(Uint8List mask, int width, int height, int reach) {
  var radius = (reach ~/ 2).clamp(1, reach);
  var out = mask;
  for (var pass = 0; pass < 2; pass++) {
    out = _blurAxis(out, width, height, radius, true);
    out = _blurAxis(out, width, height, radius, false);
  }
  return out;
}

Uint8List _blurAxis(
    Uint8List mask, int width, int height, int radius, bool horizontal) {
  var out = Uint8List(mask.length);
  var span = radius * 2 + 1;
  var outer = horizontal ? height : width;
  var inner = horizontal ? width : height;

  for (var o = 0; o < outer; o++) {
    int at(int i) => horizontal ? o * width + i : i * width + o;

    var sum = 0;
    // The window starts hanging off the near edge, with the edge pixel
    // counted for every position outside -- so a mask that reaches the border
    // is not dimmed by nothing lying beyond it.
    for (var i = -radius; i <= radius; i++) {
      sum += mask[at(i.clamp(0, inner - 1))];
    }
    for (var i = 0; i < inner; i++) {
      out[at(i)] = sum ~/ span;
      sum -= mask[at((i - radius).clamp(0, inner - 1))];
      sum += mask[at((i + radius + 1).clamp(0, inner - 1))];
    }
  }
  return out;
}

/// _paintStrokes rubs the brush's marks into the alpha channel.
void _paintStrokes(Uint8List pixels, int width, int height,
    List<RemovalStroke> strokes) {
  for (var stroke in strokes) {
    var effect = strokeEffect(pixels, width, height, stroke);
    var target = stroke.keep ? 255.0 : 0.0;
    for (var i = 0; i < effect.length; i++) {
      var strength = effect[i];
      if (strength == 0) continue;
      var p = i * 4 + 3;
      var now = pixels[p].toDouble();
      pixels[p] =
          (now + (target - now) * (strength / 255)).round().clamp(0, 255);
    }
  }
}

/// _alongPath is a point every [spacing] of distance travelled, starting at
/// the beginning and always including the end.
///
/// The end matters: a stroke has to finish where the pointer finished, or
/// letting go a little past something leaves it untouched.
List<ui.Offset> _alongPath(List<ui.Offset> path, double spacing) {
  if (path.isEmpty) return const [];
  if (path.length == 1) return [path.first];

  var out = <ui.Offset>[path.first];

  // How much further before the next dab is due. Carried across the joins
  // between segments, which is the whole difficulty: a drag is hundreds of
  // segments a pixel or two long, and a spacing measured within each one
  // separately would put a dab at every single point.
  //
  // The first attempt carried the *unwalked remainder* of a segment and then
  // used it as a starting offset in the next -- wrong in meaning and in sign,
  // so on a real stroke the dabs landed almost anywhere and most of the line
  // was never covered at all. That is what turned a swept line into a row of
  // blobs.
  var until = spacing;

  for (var i = 1; i < path.length; i++) {
    var from = path[i - 1], to = path[i];
    var span = (to - from).distance;
    if (span <= 0) continue;

    var walked = 0.0;
    while (walked + until <= span) {
      walked += until;
      out.add(ui.Offset.lerp(from, to, walked / span)!);
      until = spacing;
    }
    until -= span - walked;
  }

  // Always the end, so a stroke finishes where the pointer finished: letting
  // go a little past something would otherwise leave it untouched.
  if (out.last != path.last) out.add(path.last);
  return out;
}

/// _averageAround is the mean colour of a small patch, which is steadier than
/// one pixel: a photograph's noise moves a single pixel around by more than
/// some of the distinctions being drawn here.
List<double> _averageAround(
    Uint8List pixels, int width, int height, int cx, int cy, int radius) {
  var r = 0.0, g = 0.0, b = 0.0, seen = 0;
  for (var y = math.max(0, cy - radius);
      y <= math.min(height - 1, cy + radius);
      y++) {
    for (var x = math.max(0, cx - radius);
        x <= math.min(width - 1, cx + radius);
        x++) {
      var p = (y * width + x) * 4;
      r += pixels[p];
      g += pixels[p + 1];
      b += pixels[p + 2];
      seen++;
    }
  }
  if (seen == 0) return [0, 0, 0];
  return [r / seen, g / seen, b / seen];
}

double _distance(List<double> a, List<double> b) {
  var dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
  return math.sqrt(dr * dr + dg * dg + db * db);
}

/// _reachable is how strongly each pixel of a dab's disc belongs to the thing
/// the stroke is clinging to, from 0 to 255.
///
/// A strength rather than a yes or no, and that is what puts the edge in the
/// right place. All-or-nothing at the tolerance left a halo: the pixels along
/// an outline are blends of the subject and what is behind it, so they fall
/// outside any tolerance tight enough to protect the subject and were left
/// behind as a fringe of background. Fading out across the last part of the
/// tolerance takes those pixels partly, which is exactly what they are --
/// partly background.
///
/// A flood inside the brush and nowhere else, so it costs what the brush costs
/// and cannot run away across the picture the way a full-frame one can.
Uint8List _reachable(
    Uint8List pixels,
    int width,
    int left,
    int right,
    int top,
    int bottom,
    int centreX,
    int centreY,
    double snap,
    double radius,
    List<double> reference) {
  var boxWidth = right - left + 1;
  var boxHeight = bottom - top + 1;
  var out = Uint8List(boxWidth * boxHeight);
  var seen = Uint8List(boxWidth * boxHeight);

  const diagonal = 441.6729559300637;
  var tolerance = snap * diagonal;
  // Everything within this is wholly the background; between here and the
  // tolerance it fades. A blended edge pixel is half of each and is treated as
  // half of each.
  var solid = tolerance * 0.6;
  var fade = math.max(0.001, tolerance - solid);

  var stack = <int>[(centreY - top) * boxWidth + (centreX - left)];

  while (stack.isNotEmpty) {
    var local = stack.removeLast();
    if (local < 0 || local >= out.length || seen[local] != 0) continue;
    var lx = local % boxWidth, ly = local ~/ boxWidth;
    var x = left + lx, y = top + ly;

    var dx = x - centreX, dy = y - centreY;
    if (math.sqrt(dx * dx + dy * dy) > radius) continue;

    // Against what the stroke set out to remove, not against the pixel under
    // the pointer -- see _paintStrokes.
    var p = (y * width + x) * 4;
    var dr = pixels[p] - reference[0];
    var dg = pixels[p + 1] - reference[1];
    var db = pixels[p + 2] - reference[2];
    var away = math.sqrt(dr * dr + dg * dg + db * db);
    if (away > tolerance) continue;

    seen[local] = 1;
    out[local] =
        (away <= solid ? 255 : (255 * (tolerance - away) / fade)).round().clamp(0, 255);

    if (lx > 0) stack.add(local - 1);
    if (lx < boxWidth - 1) stack.add(local + 1);
    if (ly > 0) stack.add(local - boxWidth);
    if (ly < boxHeight - 1) stack.add(local + boxWidth);
  }
  return out;
}

/// _dab is one press of the brush, recorded into [cover] rather than applied.
///
/// Two things make it a brush rather than a rubber stamp. It fades towards its
/// rim, so strokes blend into one another and into whatever the automatic pass
/// left, and it can be told to spread only through pixels like the one the
/// stroke started on -- see RemovalStroke.snap -- so brushing along a shoulder
/// takes the sky and stops at the coat.
void _dab(Uint8List cover, Uint8List pixels, int width, int height,
    ui.Offset at, double radius, RemovalStroke stroke, List<double>? reference) {
  var left = math.max(0, (at.dx - radius).floor());
  var right = math.min(width - 1, (at.dx + radius).ceil());
  var top = math.max(0, (at.dy - radius).floor());
  var bottom = math.min(height - 1, (at.dy + radius).ceil());
  if (right < left || bottom < top) return;

  var centreX = at.dx.round().clamp(0, width - 1);
  var centreY = at.dy.round().clamp(0, height - 1);
  var reachable = stroke.snap > 0 && reference != null
      ? _reachable(pixels, width, left, right, top, bottom, centreX, centreY,
          stroke.snap, radius, reference)
      : null;

  // Everything within this is fully affected; beyond it the dab fades out.
  var solid = radius * stroke.hardness.clamp(0.0, 1.0);
  var fade = math.max(0.001, radius - solid);

  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      var dx = x - at.dx, dy = y - at.dy;
      var distance = math.sqrt(dx * dx + dy * dy);
      if (distance > radius) continue;

      var index = y * width + x;
      var cling = 1.0;
      if (reachable != null) {
        cling = reachable[(y - top) * (right - left + 1) + (x - left)] / 255;
        if (cling <= 0) continue;
      }

      var strength =
          (distance <= solid ? 1.0 : (radius - distance) / fade) * cling;
      if (strength <= 0) continue;

      var value = (strength * 255).round().clamp(0, 255);
      if (value > cover[index]) cover[index] = value;
    }
  }
}

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
