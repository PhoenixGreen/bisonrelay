import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_mask_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/matting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// edge_cleaning.dart is a picture with the background's colour taken out of
// the edge its mask leaves -- see MaskRefine.decontaminate and matting.dart.
//
// It is pixel work, so it runs off the main thread once per picture and mask
// and is kept; the painter draws the picture uncleaned until it arrives.

/// CleansEdges is a picture source that can hand back a picture with its
/// edge colours cleaned. Separate from CanvasImageSource so sources that
/// never clean need not implement it.
abstract class CleansEdges {
  /// cleaned is [picture] -- [look]'s picture as decoded -- with its edge
  /// cleaned as [look]'s mask says, or null while that is being worked out.
  ui.Image? cleaned(ImageElement look, ui.Image picture);
}

final Expando<String> _maskKeys = Expando("maskKey");

/// _keyOf is a name for everything about [look] that its cleaned picture
/// depends on.
String _keyOf(ImageElement look) {
  var mask = look.mask;
  var key =
      _maskKeys[mask] ??= jsonEncode(mask.toJson()).hashCode.toRadixString(36);
  return "${look.assetId}|${look.removal.cacheKey(look.assetId)}|$key";
}

/// _side is the longest side a cleaned picture is made at.
const int _side = 2000;

/// EdgeCleaner keeps cleaned pictures for a picture store, and makes them.
class EdgeCleaner {
  /// subjectOf is how the store hands over a decoded subject mask.
  final ui.Image? Function(String id) subjectOf;

  /// onReady is called when a cleaned picture arrives.
  final VoidCallback onReady;

  EdgeCleaner({required this.subjectOf, required this.onReady});

  final Map<String, ui.Image> _made = {};
  final List<String> _order = [];

  /// _last is each picture's most recent cleaning, drawn while a newer one
  /// is made -- a stroke on the mask must not make the edge flash back.
  final Map<String, ui.Image> _last = {};
  final Map<String, Timer> _waiting = {};
  final Map<String, String> _waitingFor = {};
  final Set<String> _working = {};
  bool _disposed = false;

  bool get busy => _waiting.isNotEmpty || _working.isNotEmpty;

  ui.Image? cleaned(ImageElement look, ui.Image picture) {
    var amount = look.mask.refine.decontaminate;
    if (amount <= 0 || !look.mask.active) return null;
    var key = _keyOf(look);
    var made = _made[key];
    if (made != null) return made;
    // Debounced, so a slider drag asks once at the end. The wait restarts
    // only when the key changes: the painter asks every frame.
    if (!_working.contains(key) && _waitingFor[look.assetId] != key) {
      _waiting.remove(look.assetId)?.cancel();
      _waitingFor[look.assetId] = key;
      _waiting[look.assetId] = Timer(const Duration(milliseconds: 180), () {
        _waiting.remove(look.assetId);
        _waitingFor.remove(look.assetId);
        unawaited(_make(key, look, picture));
      });
    }
    return _last[look.assetId];
  }

  Future<void> _make(String key, ImageElement look, ui.Image picture) async {
    var mask = look.mask;
    var subject = mask.subject.isEmpty ? null : subjectOf(mask.subject);
    if (mask.subject.isNotEmpty && subject == null) return;
    _working.add(key);
    try {
      var size = Size(picture.width.toDouble(), picture.height.toDouble());
      var k = math.min(1.0, _side / math.max(size.width, size.height));
      var w = math.max(1, (size.width * k).round());
      var h = math.max(1, (size.height * k).round());
      var into = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      var rgba = await _read(w, h, (canvas) {
        canvas.drawImageRect(picture, Offset.zero & size, into,
            Paint()..filterQuality = FilterQuality.medium);
      }, straight: true);
      var shown = await _read(w, h, (canvas) {
        paintMaskLayer(canvas, mask, size, subject,
            placeImage(size, into, ImageFit.stretch),
            blend: BlendMode.srcOver);
      });
      var alpha = Uint8List(w * h);
      for (var i = 0; i < alpha.length; i++) {
        alpha[i] = shown[i * 4 + 3];
      }
      var out = await compute(
          decontaminate,
          DeconJob(rgba, alpha, w, h, mask.refine.decontaminate,
              math.max(2, (math.max(w, h) * 0.012).round())));
      var done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          out, w, h, ui.PixelFormat.rgba8888, done.complete);
      var image = await done.future;
      if (_disposed) {
        image.dispose();
        return;
      }
      _made[key] = image;
      _order.add(key);
      // Dispose the cleaning it replaces, unless still cached.
      var was = _last[look.assetId];
      _last[look.assetId] = image;
      if (was != null && !_made.values.contains(was)) was.dispose();
      // A few kept, so returning a slider to a past value is instant.
      while (_order.length > 6) {
        var old = _order.removeAt(0);
        var gone = _made.remove(old);
        if (gone != null && !_last.values.contains(gone)) gone.dispose();
      }
      onReady();
    } catch (_) {
      // The picture stays uncleaned.
    } finally {
      _working.remove(key);
    }
  }

  static Future<Uint8List> _read(int w, int h, void Function(ui.Canvas) draw,
      {bool straight = false}) async {
    var recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    var image = await recorder.endRecording().toImage(w, h);
    try {
      var data = await image.toByteData(
          format: straight
              ? ui.ImageByteFormat.rawStraightRgba
              : ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    for (var t in _waiting.values) {
      t.cancel();
    }
    _waiting.clear();
    var all = {..._made.values, ..._last.values};
    for (var image in all) {
      image.dispose();
    }
    _made.clear();
    _last.clear();
  }
}

/// cleanedFor is [picture] cleaned as [look]'s mask asks, where [images]
/// can clean and has it ready; [picture] itself otherwise.
ui.Image cleanedFor(Object? images, ImageElement look, ui.Image picture) {
  if (look.mask.refine.decontaminate <= 0 || images is! CleansEdges) {
    return picture;
  }
  return images.cleaned(look, picture) ?? picture;
}
