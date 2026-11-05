import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/model3d/model_scene.dart';
import 'package:bruig/plugin_system/canvas/render/model3d/model3d_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/edge_cleaning.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_scene.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/character3d_painter.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_character.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_gpu.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';

// image_store.dart decodes the pictures a canvas uses, and cuts their
// backgrounds out.
//
// It is the asynchronous half of drawing an image: the renderer is synchronous
// and cannot wait for a file, so it asks this for a decoded picture and draws
// a placeholder when the answer is null. The store then loads it and notifies,
// and the next frame has it, so a late image never stalls a frame.
//
// Entries are keyed by the *result*, not the source: a picture with a colour
// key applied is a different entry from the same picture without one, so
// toggling a removal mode is instant after the first time and elements
// sharing picture and settings share one decode.

/// _budget bounds the cache, in bytes of decoded pixels (a 4000x3000
/// photograph is 48MB of RGBA).
///
/// The least recently asked for is evicted once the pixels pass it -- but
/// never one asked for within [_inUse], which is on screen: a canvas showing
/// more than the budget is drawn at the cost of the memory rather than
/// reloading pictures every frame.
const int _budget = 640 << 20;

/// _inUse is how recently a picture has to have been asked for to be kept
/// over the budget.
const Duration _inUse = Duration(seconds: 4);

/// _longest is the most pixels a picture is decoded at along its longer
/// side. A canvas is exported at a few thousand pixels at most, so more is
/// memory for detail no export can show.
const int _longest = 4096;

/// _thumbSide is how big a [CanvasImageStore.thumbnail] is along its longer
/// side: a tile's worth, at twice its size for a sharp screen.
const int _thumbSide = 192;

/// CanvasImageStore holds decoded pictures for a canvas being edited.
class CanvasImageStore extends ChangeNotifier
    implements
        CanvasImageSource,
        CleansEdges,
        CanvasCharacterSource,
        CanvasModelSource,
        CanvasStageSource {
  /// _edges makes and keeps pictures with their edges cleaned -- see
  /// edge_cleaning.dart.
  late final EdgeCleaner _edges = EdgeCleaner(
      subjectOf: (id) => resolve(id, const BackgroundRemoval()),
      onReady: () {
        if (!_disposed) notifyListeners();
      });

  @override
  ui.Image? cleaned(ImageElement look, ui.Image picture) =>
      _edges.cleaned(look, picture);

  final Map<String, ui.Image> _images = {};

  /// _order is the keys in least-recently-used order, for [_evict]; _asked
  /// is when each was last asked for.
  final List<String> _order = [];
  final Map<String, DateTime> _asked = {};

  /// _bytes is how many bytes of pixels [_images] holds.
  int _bytes = 0;

  /// bytes is [_bytes], for whoever is watching the memory.
  int get bytes => _bytes;

  int _sizeOf(ui.Image image) => image.width * image.height * 4;

  /// _pending is the loads in flight, so several elements asking for one
  /// picture in a frame start one decode. Non-empty means [loading].
  final Set<String> _pending = {};

  /// _failed remembers what could not be loaded, so a missing picture is not
  /// asked for again on every frame.
  final Set<String> _failed = {};

  /// _vectors is the assets that are drawings rather than bitmaps, kept as
  /// drawings and loaded apart from [_images], so a table of badges
  /// rasterises none of them. Only a caller that needs pixels (the image
  /// element, for its remover and filters) makes a bitmap.
  final Map<String, CanvasVector> _vectors = {};

  bool _disposed = false;

  /// putForTest seeds the store with an already-decoded picture, for widget
  /// tests of the retouching brush, which has no file or async decode to
  /// load one from.
  @visibleForTesting
  void putForTest(String assetId, ui.Image image) {
    _images[assetId] = image;
    _bytes += _sizeOf(image);
  }

  /// hold keeps [image] as the picture [assetId] -- one just made here, a
  /// sprite's sheet painted on -- so it is drawn at once, not read back
  /// from the file it was stored to.
  void hold(String assetId, ui.Image image) {
    if (_disposed || _images.containsKey(assetId)) return;
    _images[assetId] = image;
    _bytes += _sizeOf(image);
    _touch(assetId);
    _evict();
    notifyListeners();
  }

  /// notifyForTest is the store saying a picture arrived, as a late load
  /// does.
  @visibleForTesting
  void notifyForTest() => notifyListeners();

  /// original is the picture as it was loaded, with nothing taken out.
  ///
  /// The retouching brush measures against this: removal only rewrites
  /// alpha, so the coordinates are the same, and [resolve] would return null
  /// until the treated copy was built, losing the first stroke.
  ui.Image? original(String assetId) {
    var image = _images[assetId];
    if (image != null) _touch(assetId);
    return image;
  }

  /// _thumbs is a small copy of each picture held, made the first time a
  /// tile asks for one and let go of with the picture.
  final Map<ui.Image, ui.Image> _thumbs = Map.identity();

  /// thumbnail is [image] -- one this store handed out -- small enough for a
  /// tile, so filter tiles and layer thumbnails do not draw the full decode
  /// into a tiny box every frame. A picture not this store's is returned as
  /// it is: nothing here would know when to let a copy of it go.
  ui.Image thumbnail(ui.Image image) {
    if (math.max(image.width, image.height) <= _thumbSide) return image;
    var kept = _thumbs[image];
    if (kept != null) return kept;
    if (!_images.values.any((i) => identical(i, image))) return image;
    var scale = _thumbSide / math.max(image.width, image.height);
    var w = math.max(1, (image.width * scale).round());
    var h = math.max(1, (image.height * scale).round());
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    var picture = recorder.endRecording();
    var thumb = picture.toImageSync(w, h);
    picture.dispose();
    return _thumbs[image] = thumb;
  }

  @override
  bool get loading => _pending.isNotEmpty || _edges.busy;

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

  @override
  CanvasVector? resolveVector(String assetId) {
    if (assetId.isEmpty) return null;
    var vector = _vectors[assetId];
    // A drawing with an empty or infinite size (an .svg with no width,
    // height or viewBox) cannot be scaled to fit. Refused here so every
    // caller falls back to the rasterised copy instead of drawing nothing.
    if (vector != null) {
      var size = vector.size;
      var usable = size.width.isFinite &&
          size.height.isFinite &&
          size.width > 0 &&
          size.height > 0;
      return usable ? vector : null;
    }
    var key = "vector:$assetId";
    if (!_pending.contains(key) && !_failed.contains(key)) {
      _pending.add(key);
      _loadVector(assetId, key);
    }
    return null;
  }

  final Map<String, ImageSilhouette> _outlines = {};

  // The 3D characters: a scene per element drawn (a body read, shaped and
  // dressed), kept until the store goes or more than [_mostCharacters] are
  // kept, when the one drawn longest ago goes.

  /// _gpu is whether 3D can be drawn here: null until found out.
  bool? _gpu;
  final Map<String, (CharacterScene, String)> _characters = {};
  static const int _mostCharacters = 8;

  @override
  bool get noCharacters3d => _gpu == false;

  // 3D stages' sets, one scene per stage id, kept as long as the store is.
  final Map<String, StageScene> _stages = {};

  @override
  StageScene? resolveStage(StageElement stage) {
    if (!_gpuKnown()) return null;
    return _stages[stage.id] ??= StageScene();
  }

  /// _gpuKnown is whether 3D can be drawn here, finding out first if that
  /// is not known yet -- and telling the listeners once it is.
  bool _gpuKnown() {
    if (_gpu == null) {
      if (_pending.add("gpu")) {
        flutterGpuReady().then((ok) {
          _gpu = ok;
          _pending.remove("gpu");
          if (!_disposed) notifyListeners();
        });
      }
      return false;
    }
    return _gpu!;
  }

  // The 3D objects: a scene per element drawn, its model read once, at most
  // [_mostModels] kept.
  final Map<String, (ModelScene, String)> _models = {};
  static const int _mostModels = 12;

  @override
  bool get noModels3d => _gpu == false;

  @override
  ModelScene? resolveModel(Object3dElement e) {
    if (e.assetId.isEmpty || !_gpuKnown()) return null;
    var held = _models.remove(e.id);
    if (held != null && held.$2 == e.assetId) {
      _models[e.id] = held;
      return held.$1;
    }
    held?.$1.dispose();
    if (_models.length >= _mostModels) {
      _models.remove(_models.keys.first)!.$1.dispose();
    }
    var scene = ModelScene()..addListener(_characterChanged);
    _models[e.id] = (scene, e.assetId);
    // Pending from now, so an export waits; read once this frame is done.
    var key = "object3d:${e.id}";
    _pending.add(key);
    var id = e.assetId;
    scheduleMicrotask(() async {
      try {
        var bytes = await CanvasMedia.load(MediaKind.model, id);
        if (bytes == null) {
          scene.error = "This model is not in the library.";
        } else if (!_disposed) {
          await scene.load(Uint8List.fromList(bytes));
        }
      } finally {
        _pending.remove(key);
        if (!_disposed) notifyListeners();
      }
    });
    return scene;
  }

  /// _wornKey is what [e] wears, as a key: remembered for its design and
  /// quick change, rather than every point of its sculpting written out at
  /// every paint.
  static String _wornKey(Character3dElement e) {
    var wearing = e.performance.wearing;
    if (_wornKeys[e.design] case (var w, var key) when w == wearing) {
      return key;
    }
    var key = jsonEncode(e.worn.toJson()..remove("updated"));
    _wornKeys[e.design] = (wearing, key);
    return key;
  }

  static final Expando<(String, String)> _wornKeys = Expando();

  @override
  CharacterScene? resolveCharacter3d(Character3dElement e) {
    if (!_gpuKnown()) return null;
    final worn = e.worn;
    var key = _wornKey(e);
    var held = _characters.remove(e.id);
    var scene = held?.$1;
    if (scene == null) {
      if (_characters.length >= _mostCharacters) {
        var oldest = _characters.keys.first;
        _characters.remove(oldest)!.$1.dispose();
      }
      scene = CharacterScene(loadDecal: loadDecalPicture, paper: false)
        ..addListener(_characterChanged);
    }
    _characters[e.id] = (scene, key);
    if (held?.$2 != key) {
      // Pending from now, for an export to wait for; started after the
      // frame being painted, since starting notifies listeners and nothing
      // may be rebuilt mid-paint.
      _pending.add("character3d:${e.id}");
      var first = held == null, design = worn;
      scheduleMicrotask(() {
        if (_disposed) return;
        scene!.showDesign(design);
        _readyCharacter(e.id, scene, first: first);
      });
    }
    return scene;
  }

  bool _characterNews = false;

  /// _characterChanged passes on a character's news after the frame being
  /// painted, and once however much of it there was.
  void _characterChanged() {
    if (_characterNews || _disposed) return;
    _characterNews = true;
    scheduleMicrotask(() {
      _characterNews = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// _readyCharacter is loading until [scene] has everything it was asked
  /// for -- what an export waits for -- and then draws it again.
  Future<void> _readyCharacter(String id, CharacterScene scene,
      {required bool first}) async {
    var key = "character3d:$id";
    _pending.add(key);
    try {
      // One turn for the change to start: a body asked for is not loading
      // until its file is being read, so ready() would pass too early.
      await Future<void>.delayed(Duration.zero);
      await scene.ready();
      if (first && !_disposed) scene.settle();
    } finally {
      _pending.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) {
    if (assetId.isEmpty) return null;
    var key = removal.active ? removal.cacheKey(assetId) : assetId;
    var outline = _outlines[key];
    if (outline != null) return outline;

    // The picture has to be decoded before its alpha can be read; asking
    // starts that. Both arrive by notification, so a caller gets the box
    // first and the shape on a later frame.
    var image = resolve(assetId, removal);
    if (image == null) return null;

    var pending = "outline:$key";
    if (!_pending.contains(pending) && !_failed.contains(pending)) {
      _pending.add(pending);
      _loadOutline(image, key, pending);
    }
    return null;
  }

  Future<void> _loadOutline(ui.Image image, String key, String pending) async {
    try {
      var outline = await silhouetteOf(image);
      if (_disposed || outline == null) {
        _failed.add(pending);
        return;
      }
      _outlines[key] = outline;
      notifyListeners();
    } catch (exception) {
      debugPrint("Unable to read a canvas picture's outline: $exception");
      _failed.add(pending);
    } finally {
      _pending.remove(pending);
    }
  }

  Future<void> _loadVector(String assetId, String key) async {
    try {
      var bytes = await CanvasMedia.load(MediaKind.vector, assetId);
      if (bytes == null || !_looksLikeSvg(Uint8List.fromList(bytes))) {
        _failed.add(key);
        return;
      }
      var info = await vg.loadPicture(
          SvgStringLoader(String.fromCharCodes(bytes)), null);
      if (_disposed) {
        info.picture.dispose();
        return;
      }
      _vectors[assetId] = CanvasVector(info.picture, info.size);
      notifyListeners();
    } catch (exception) {
      debugPrint("Unable to read the canvas vector $assetId: $exception");
      _failed.add(key);
    } finally {
      _pending.remove(key);
    }
  }

  void _touch(String key) {
    _order.remove(key);
    _order.add(key);
    _asked[key] = DateTime.now();
  }

  Future<void> _load(
      String assetId, BackgroundRemoval removal, String key) async {
    try {
      // Falls back to the Vectors store for a drawing used as a picture (a
      // text element's icon, a badge).
      var bytes = await CanvasAssets.load(assetId) ??
          await CanvasMedia.load(MediaKind.vector, assetId);
      if (bytes == null) {
        _failed.add(key);
        return;
      }

      var image = await _decode(Uint8List.fromList(bytes));
      if (image == null) {
        _failed.add(key);
        return;
      }

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

      _drop(key);
      _images[key] = image;
      _bytes += _sizeOf(image);
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
    var now = DateTime.now();
    var i = 0;
    while (_bytes > _budget && i < _order.length) {
      var key = _order[i];
      var asked = _asked[key];
      if (asked != null && now.difference(asked) < _inUse) {
        i++;
        continue;
      }
      _order.removeAt(i);
      _asked.remove(key);
      _drop(key);
    }
  }

  void _drop(String key) {
    var image = _images.remove(key);
    if (image == null) return;
    _bytes -= _sizeOf(image);
    _thumbs.remove(image)?.dispose();
    image.dispose();
  }

  /// forget drops one asset's entries, so that replacing a picture in place
  /// shows the new one rather than the cached old one.
  void forget(String assetId) {
    var keys = _images.keys.where((k) => k.startsWith(assetId)).toList();
    for (var key in keys) {
      _order.remove(key);
      _asked.remove(key);
      _drop(key);
    }
    _failed.removeWhere((k) =>
        k.startsWith(assetId) ||
        k == "vector:$assetId" ||
        k.startsWith("outline:$assetId"));
    _outlines.removeWhere((k, _) => k.startsWith(assetId));
    var drawing = _vectors.remove(assetId);
    drawing?.picture.dispose();
    if (keys.isNotEmpty || drawing != null) notifyListeners();
  }

  /// release lets go of every picture, drawing and 3D scene held, the store
  /// staying usable: what is asked for again is loaded again. For the Canvas
  /// page left, whose store lives on with the session.
  void release() {
    _clear();
    _failed.clear();
    _outlines.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _edges.dispose();
    _clear();
    super.dispose();
  }

  void _clear() {
    for (var (scene, _) in _characters.values) {
      scene.dispose();
    }
    _characters.clear();
    for (var (scene, _) in _models.values) {
      scene.dispose();
    }
    _models.clear();
    for (var stage in _stages.values) {
      stage.dispose();
    }
    _stages.clear();
    for (var vector in _vectors.values) {
      vector.picture.dispose();
    }
    _vectors.clear();
    for (var thumb in _thumbs.values) {
      thumb.dispose();
    }
    _thumbs.clear();
    for (var image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _order.clear();
    _asked.clear();
    _bytes = 0;
  }
}

/// _decode turns stored bytes into a picture, whatever kind of picture they
/// are.
///
/// Vectors come out as a bitmap, because everything downstream (the
/// background remover, export, canvas) works on pixels. Rasterised once at
/// [_vectorSize] rather than at the drawn size, which changes per frame and
/// per export and would put a decode inside the paint loop.
Future<ui.Image?> _decode(Uint8List bytes) async {
  if (_looksLikeSvg(bytes)) return _rasterise(bytes);
  try {
    // Measured before it is decoded, and decoded smaller where it is huge.
    var buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    var descriptor = await ui.ImageDescriptor.encoded(buffer);
    var w = descriptor.width, h = descriptor.height;
    var longer = w > h ? w : h;
    var codec = longer > _longest
        ? await descriptor.instantiateCodec(
            targetWidth: (w * _longest / longer).round(),
            targetHeight: (h * _longest / longer).round())
        : await descriptor.instantiateCodec();
    var frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  } catch (exception) {
    debugPrint("Unable to decode a canvas picture: $exception");
    // The SVG sniff is a guess: anything the codec refuses is offered to
    // the vector loader before it is given up on.
    return _rasterise(bytes);
  }
}

/// _vectorSize is how large a vector is rasterised on its longest side.
const int _vectorSize = 512;

/// _looksLikeSvg is whether `<svg` appears in the first 4KB. A drawing
/// program's export can carry most of a kilobyte of XML declaration,
/// doctype, licence and metadata before the tag.
bool _looksLikeSvg(Uint8List bytes) =>
    String.fromCharCodes(bytes.take(4096)).toLowerCase().contains("<svg");

Future<ui.Image?> _rasterise(Uint8List bytes) async {
  try {
    var info = await vg.loadPicture(
        SvgStringLoader(String.fromCharCodes(bytes)), null);
    try {
      var size = info.size;
      if (size.isEmpty) return null;
      var scale = _vectorSize / math.max(size.width, size.height);
      var width = math.max(1, (size.width * scale).round());
      var height = math.max(1, (size.height * scale).round());

      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      var picture = recorder.endRecording();
      try {
        return await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
    } finally {
      info.picture.dispose();
    }
  } catch (exception) {
    debugPrint("Unable to draw a canvas vector: $exception");
    return null;
  }
}

Future<ui.Image?> _removeBackground(
    ui.Image image, BackgroundRemoval removal) async {
  if (!removal.active) return null;

  // At the working size, like the preview (see [workingSize]). Brush
  // measurements are fractions of the picture, so a stroke lands in the
  // same place whichever size this is.
  var working = await _atWorkingSize(image);
  var data = await working.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;

  var pixels = data.buffer.asUint8List();
  var width = working.width, height = working.height;

  applyRemovalForTest(pixels, width, height, removal);

  // decodeImageFromPixels rather than a PNG round trip, which on a large
  // photograph is most of a second for no change.
  var completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// _alphaFor turns a distance and the tolerance into an alpha.
///
/// Inside the tolerance a pixel is fully removed; over the next [softness] it
/// fades back in, so a cut-out has no hard one-pixel jagged edge.
int _alphaFor(double distance, double tolerance, double softness, int current) {
  if (distance <= tolerance) return 0;
  if (softness <= 0 || distance >= tolerance + softness) return current;
  var t = (distance - tolerance) / softness;
  return (current * t).round().clamp(0, 255);
}

/// _premultiply scales the colours to match the alpha they now have.
///
/// The pixels either side of this file are premultiplied (a half-transparent
/// red is (128, 0, 0, 128)), but the removal passes write alpha and leave
/// colour alone. Unscaled, a removed pixel keeps its colour at zero alpha,
/// which Skia may draw as the colour, and feathered edges glow. [was] is the
/// alpha before removal.
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
/// It is the whole of the work without the decoding either side, and is
/// also what [_removeBackground] calls; exposed so tests can run it on
/// synthetic pixels (see canvas_removal_test).
@visibleForTesting
void applyRemovalForTest(
    Uint8List pixels, int width, int height, BackgroundRemoval removal) {
  // The alpha before anything was taken out, for [_premultiply]. Kept in
  // here rather than around the call so no caller can forget it.
  var was = Uint8List(width * height);
  for (var i = 0; i < was.length; i++) {
    was[i] = pixels[i * 4 + 3];
  }

  switch (removal.mode) {
    case RemovalMode.none:
      // Not a return: the brush still runs, since painting the background
      // out by hand with no method chosen is a legitimate use.
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

  // Last, so a stroke always has the final word over the automatic pass.
  _paintStrokes(pixels, width, height, removal.strokes);

  _premultiply(pixels, was);
}

/// workingSize is the largest a picture is worked on at, along its longer
/// side.
///
/// Background removal is several passes over every pixel, and the brush
/// preview repeats them on every adjustment. The result is drawn into a few
/// hundred pixels on screen, so the work is done on a copy no bigger than
/// this and scaled back up.
const int workingSize = 1600;

/// scaleForWork is how much a picture has to shrink to be worked on, or 1 when
/// it is already small enough.
double scaleForWork(int width, int height) {
  var longest = math.max(width, height);
  return longest <= workingSize ? 1 : workingSize / longest;
}

/// _workingPixels remembers the shrunk-down bytes of a picture, since
/// getting them is a GPU readback and the preview asks on every adjustment.
///
/// Keyed by identity rather than asset id: a reloaded picture is a different
/// object, and the old bytes go with the old object.
final Map<ui.Image, _Working> _workingPixels = {};

/// clearWorkingPixels forgets every picture's shrunk-down bytes.
void clearWorkingPixels() => _workingPixels.clear();

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

  // One picture at a time: only the one being edited is asked for.
  _workingPixels.clear();
  var made = _Working(data.buffer.asUint8List(), working.width, working.height);
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

/// snapForStroke works out how far [stroke] should cling on [source]; see
/// [suggestSnap], which does the work once the pixels are to hand.
Future<double?> snapForStroke(ui.Image source, RemovalStroke stroke) async {
  var working = await _workingCopy(source);
  if (working == null) return null;
  return suggestSnap(working.pixels, working.width, working.height, stroke);
}

/// strokePreview is a picture of what [stroke] would do, for showing on the
/// canvas before it is applied.
///
/// It runs the brush itself ([strokeEffect]) rather than drawing a shape from
/// the settings, because a stroke that clings to or fills from an edge
/// depends on the picture; so preview and result cannot drift apart.
///
/// Returned as premultiplied RGBA at the working size, transparent where the
/// stroke does not reach. Sized to the whole picture so the caller draws it
/// through the same placement the picture uses.
Future<ui.Image?> strokePreview(ui.Image source, RemovalStroke stroke) async {
  // From the cached working copy: a preview is rebuilt on every adjustment.
  var working = await _workingCopy(source);
  if (working == null) return null;

  // Copied, so the cached working copy is left as it was for the next
  // adjustment.
  var pixels = Uint8List.fromList(working.pixels);
  var width = working.width, height = working.height;

  var cover = strokeEffect(pixels, width, height, stroke);

  var out = Uint8List(width * height * 4);
  for (var i = 0; i < cover.length; i++) {
    var strength = cover[i];
    if (strength == 0) continue;

    // Coloured by brush strength rather than tinted flat, so the falloff
    // can be judged:
    //
    //   blue    fully taken -- inside the hard core
    //   yellow  barely taken -- the outer rim of the falloff
    //
    // The width of the yellow band is the softness; at hardness one there is
    // none.
    var t = strength / 255;
    var r = ((1 - t) * 255).round();
    var g = ((1 - t) * 210 + t * 90).round();
    var b = (t * 255).round();

    // Three-quarter alpha, so the picture underneath stays visible.
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

/// _markClingEdge draws a dashed green line round the edge of what the
/// stroke reaches, so where cling stopped it (following the picture) can be
/// told from where the brush's own round rim ran out.
void _markClingEdge(Uint8List out, Uint8List cover, int width, int height) {
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
/// Cling wants "how different from the background must a pixel be", which
/// cannot be read off a photograph by eye. So the pixels under the stroke
/// are histogrammed by distance from the colour it started on, and Otsu's
/// method finds the gap between the two clusters.
///
/// Returns null when there is no gap: a stroke drawn wholly on the
/// background has one cluster, and a split in it would cut the background.
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

  // How many pixels sit at each distance from that colour, in 256 steps up
  // to the RGB diagonal (the furthest two colours can be apart).
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

    // Every third pixel: enough for a histogram, and this runs while the
    // user waits.
    for (var y = top; y <= bottom; y += 3) {
      for (var x = left; x <= right; x += 3) {
        var dx = x - at.dx, dy = y - at.dy;
        if (dx * dx + dy * dy > radius * radius) continue;
        var p = (y * width + x) * 4;
        var away = _distance([
          pixels[p].toDouble(),
          pixels[p + 1].toDouble(),
          pixels[p + 2].toDouble()
        ], reference);
        var bin = (away / diagonal * 255).round().clamp(0, 255);
        counts[bin]++;
        total++;
      }
    }
  }
  if (total < 32) return null;

  var split = _otsu(counts, total);
  if (split == null) return null;

  // A little past the split, so the blend along an outline falls inside the
  // fading part of the tolerance rather than outside it.
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
  // The first and last thresholds that are equally the best. With two flat
  // colours every threshold between is as good, and the first sits hard
  // against the background (no tolerance); the middle of the run is used.
  int? first, last;

  for (var i = 0; i < counts.length; i++) {
    belowWeight += counts[i];
    if (belowWeight == 0) continue;
    var aboveWeight = total - belowWeight;
    if (aboveWeight == 0) break;

    belowSum += i * counts[i];
    var belowMean = belowSum / belowWeight;
    var aboveMean = (sum - belowSum) / aboveWeight;
    var between = belowWeight *
        aboveWeight *
        (belowMean - aboveMean) *
        (belowMean - aboveMean);
    if (between > best) {
      best = between;
      first = i;
      last = i;
    } else if (between == best) {
      last = i;
    }
  }

  // One cluster (a stroke drawn wholly on one thing) has no useful split.
  if (first == null || last == null || best <= 0) return null;
  return (first + last) ~/ 2;
}

/// strokeCoverage is how strongly a stroke touches each pixel, from 0 to 255.
///
/// It is the *most* any dab reaches a pixel, not the sum, which is why this
/// is a separate pass: blending dab by dab drives overlapping pixels to the
/// target and collapses the feathered rim into a hard edge.
Uint8List strokeCoverage(
    Uint8List pixels, int width, int height, RemovalStroke stroke) {
  var cover = Uint8List(width * height);
  if (stroke.points.isEmpty) return cover;

  var shorter = math.min(width, height);
  var radius = math.max(1.0, stroke.radius * shorter);

  // What the stroke is clinging *to*, sampled once where it began: sampled
  // per dab it would re-learn the subject as soon as it crossed onto it.
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

  // Where the dabs go: every third of a radius of distance travelled, not
  // one per reported point (a drag reports hundreds, and each dab is a
  // flood over its own square).
  var spacing = math.max(1.0, radius / 3);
  var path = [
    for (var point in stroke.points)
      ui.Offset(point.dx * width, point.dy * height),
  ];

  for (var at in _alongPath(path, spacing)) {
    // The reference drifts with the background (a sky shading across is
    // still background), but only towards colours within tolerance; it
    // does not follow onto the subject.
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
/// The preview and the picture both go through this. For an ordinary stroke
/// it is [strokeCoverage]; for a fill it is that *plus* everything the
/// picture's border can reach without crossing it.
Uint8List strokeEffect(
    Uint8List pixels, int width, int height, RemovalStroke stroke) {
  var cover = strokeCoverage(pixels, width, height, stroke);
  if (!stroke.fill) return cover;

  // A boundary is all or nothing, however soft the brush: a soft rim would
  // leave a band of half-removed pixels inside the line. Softness is applied
  // to the finished cut below instead.
  for (var i = 0; i < cover.length; i++) {
    if (cover[i] != 0) cover[i] = 255;
  }

  // Everything reachable from the border without crossing the line. A line
  // that does not quite close fails visibly: the flood leaks through the gap
  // and takes more, which can be seen and undone.
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

  // Inside out for fillInside: a hole cut out, being everything the outside
  // could not reach.
  if (stroke.fillInside) {
    for (var i = 0; i < reached.length; i++) {
      reached[i] = reached[i] == 0 ? 255 : 0;
    }
  }

  // The line goes with the side being taken, so the cut lands on it.
  for (var i = 0; i < reached.length; i++) {
    if (cover[i] > reached[i]) reached[i] = cover[i];
  }

  // Then softened by hardness, independent of the brush's size on purpose:
  // how thick the boundary is drawn and how soft the cut is are separate.
  var feather = ((1 - stroke.hardness.clamp(0.0, 1.0)) * _cutFeather).round();
  return feather <= 0 ? reached : _blur(reached, width, height, feather);
}

/// _cutFeather is how far the softest cut edge reaches, in working-size
/// pixels, counting both sides of the line.
const int _cutFeather = 12;

/// _blur is a box blur of running sums run twice, close to a smooth
/// falloff. Each pass is half of [reach], so the two together reach it.
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
    // Positions off the edge count as the edge pixel, so a mask reaching
    // the border is not dimmed.
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
void _paintStrokes(
    Uint8List pixels, int width, int height, List<RemovalStroke> strokes) {
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
List<ui.Offset> _alongPath(List<ui.Offset> path, double spacing) {
  if (path.isEmpty) return const [];
  if (path.length == 1) return [path.first];

  var out = <ui.Offset>[path.first];

  // How much further before the next dab is due, carried across segment
  // joins: a drag is hundreds of segments a pixel or two long, and spacing
  // within each separately would put a dab at every point.
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

  // Always the end, so a stroke finishes where the pointer finished.
  if (out.last != path.last) out.add(path.last);
  return out;
}

/// _averageAround is the mean colour of a small patch, steadier than one
/// pixel against a photograph's noise.
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
/// A strength rather than yes or no: outline pixels are blends of subject
/// and background, so all-or-nothing leaves a fringe of background. Fading
/// across the last part of the tolerance takes them partly.
///
/// The flood stays inside the brush's disc, so it costs what the brush costs.
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
  // Within this is wholly background; between here and the tolerance it
  // fades.
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

    // Against what the stroke set out to remove, not the pixel under the
    // pointer -- see [strokeCoverage].
    var p = (y * width + x) * 4;
    var dr = pixels[p] - reference[0];
    var dg = pixels[p + 1] - reference[1];
    var db = pixels[p + 2] - reference[2];
    var away = math.sqrt(dr * dr + dg * dg + db * db);
    if (away > tolerance) continue;

    seen[local] = 1;
    out[local] = (away <= solid ? 255 : (255 * (tolerance - away) / fade))
        .round()
        .clamp(0, 255);

    if (lx > 0) stack.add(local - 1);
    if (lx < boxWidth - 1) stack.add(local + 1);
    if (ly > 0) stack.add(local - boxWidth);
    if (ly < boxHeight - 1) stack.add(local + boxWidth);
  }
  return out;
}

/// _dab is one press of the brush, recorded into [cover] rather than applied.
///
/// It fades towards its rim by [RemovalStroke.hardness], and with
/// [RemovalStroke.snap] spreads only through pixels like [reference], so
/// brushing along a shoulder takes the sky and stops at the coat.
void _dab(
    Uint8List cover,
    Uint8List pixels,
    int width,
    int height,
    ui.Offset at,
    double radius,
    RemovalStroke stroke,
    List<double>? reference) {
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
    var l =
        (pixels[i] * 0.2126 + pixels[i + 1] * 0.7152 + pixels[i + 2] * 0.0722) /
            255;
    // How far past the threshold this pixel is, positive when it should go,
    // negated into a distance for the same [_alphaFor] ramp as a colour key.
    var over = removal.invert ? removal.threshold - l : l - removal.threshold;
    pixels[i + 3] = _alphaFor(-over, 0, removal.softness, pixels[i + 3]);
  }
}

/// _cornerFlood removes the connected region touching the picture's edges.
///
/// It walks in from the border and stops **where the picture changes
/// suddenly**, not where the colour stops matching one reference colour: a
/// background is usually smooth (out of focus, a wall, a sky) while the
/// subject has a crisp outline, and a background running from bright bokeh
/// to near-black is near no single colour.
///
/// [BackgroundRemoval.edge] is the local step: how much the picture may change
/// from one pixel to the next and still count as the same region.
/// [BackgroundRemoval.tolerance] is a drift budget from the seed on top of
/// it, so a gradual ramp cannot creep through the subject.
///
/// An explicit stack rather than recursion: a full-frame flood would
/// overflow.
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

  // Each entry is three ints: the pixel, the pixel it was reached from (for
  // the local step) and the chain's seed (for the drift budget).
  var stack = <int>[];
  void push(int index, int from, int seed) {
    stack
      ..add(index)
      ..add(from)
      ..add(seed);
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

    // A big step from the pixel this was reached through is an edge.
    if (index != from && distance(index, from) > step) continue;
    // And no further from where this chain started than the budget allows.
    if (distance(index, seed) > budget) continue;

    // Marked only once accepted: a pixel rejected from one neighbour may
    // still be reached from another, and marking on sight left a halo when
    // inverted.
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
/// the user has drawn on each, for photographs where no threshold separates
/// them.
///
///   1. Collect the colours under each set of marks, to five bits a channel
///      (about as fine as a photograph's noise allows).
///   2. Classify each of the 32768 colours once ([_classify]), not per pixel.
///   3. Flood from the background marks and the border through pixels the
///      table calls background.
///
/// The flood means a subject colour that also appears in the background is
/// only removed where background-looking pixels connect to it, and a subject
/// mark blocks the way.
void _learn(
    Uint8List pixels, int width, int height, BackgroundRemoval removal) {
  var background = _paletteOf(pixels, width, height, removal.backgroundHints);
  var subject = _paletteOf(pixels, width, height, removal.subjectHints);
  // Nothing to compare until both kinds of mark exist; a guess would remove
  // something arbitrary the moment the mode was chosen.
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
  // ...and from the border, so the user need not trace all four sides.
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
Set<int> _paletteOf(
    Uint8List pixels, int width, int height, Iterable<RemovalStroke> marks) {
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
/// Once per colour rather than per pixel, so the cost does not grow with the
/// picture. [bias] shifts the boundary: at a half it is even, higher takes
/// more as background.
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
      var from =
          ui.Offset(mark.points[i].dx * width, mark.points[i].dy * height);
      var to = i + 1 < mark.points.length
          ? ui.Offset(
              mark.points[i + 1].dx * width, mark.points[i + 1].dy * height)
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
/// A flood is all or nothing, a staircase on soft outlines such as hair.
/// This averages alpha over a small neighbourhood, but only where the
/// neighbours disagree, so the inside of the subject and of the hole are
/// left as they were.
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
      // Nothing to soften: every neighbour agrees.
      if (!mixed || seen == 0) continue;
      pixels[index * 4 + 3] = (total / seen).round().clamp(0, 255);
    }
  }
}
