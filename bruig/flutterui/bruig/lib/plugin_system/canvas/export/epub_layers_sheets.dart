part of 'epub_layers.dart';

// Packing a page's pictures onto few sprite sheets, each trimmed to its ink and
// named by its pixels so none is packed twice. Part of epub_layers.dart.

/// _Sheets packs a page's pictures onto few sheets, each trimmed to its
/// ink and named by its pixels so none is packed twice. Sprites come back
/// provisional; [placed] gives the final one after [close].
class _Sheets {
  final String stem;

  /// side is how large a sheet may grow: 16 MB decoded, fine on a tablet.
  static const int side = 2048;

  /// gap keeps neighbours out of a picture a reader scales and samples.
  static const int gap = 2;

  final List<EpubFile> files = [];
  final Map<String, EpubSprite> _byPixels = {};
  final Map<EpubSprite, EpubSprite> _final = {};
  final Map<EpubSprite, String> _hrefs = {};
  final List<Future<EpubFile?>> _encoding = [];

  _Sheets(this.stem);

  final List<(ui.Image, EpubSprite)> _pieces = [];
  int _x = 0, _y = 0, _row = 0, _wide = 0, _tall = 0;

  Future<Uint8List?> _pixels(ui.Picture picture, Rect region) async {
    var w = region.width.round(), h = region.height.round();
    if (w <= 0 || h <= 0) return null;
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(-region.left, -region.top)
      ..drawPicture(picture);
    var shifted = recorder.endRecording();
    try {
      var image = await shifted.toImage(w, h);
      try {
        var raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return raw?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      shifted.dispose();
    }
  }

  /// add draws [picture] over [region], trims it, and packs it -- or returns
  /// the same picture already packed, or null for one with nothing in it.
  Future<EpubSprite?> add(ui.Picture picture, Rect region) async {
    region = Rect.fromLTRB(
        region.left.floorToDouble(),
        region.top.floorToDouble(),
        region.right.ceilToDouble(),
        region.bottom.ceilToDouble());
    var w = region.width.round(), h = region.height.round();
    var rgba = await _pixels(picture, region);
    if (rgba == null) return null;
    var ink = _inkBounds(rgba, w, h);
    if (ink == null) return null;
    var cw = ink.width.round(), ch = ink.height.round();
    var cut = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      var from = ((ink.top.round() + y) * w + ink.left.round()) * 4;
      cut.setRange(y * cw * 4, (y + 1) * cw * 4, rgba, from);
    }
    var x = region.left + ink.left, y = region.top + ink.top;
    var name = "${_hashOf(cut)}:${cw}x$ch@$x,$y";
    var known = _byPixels[name];
    if (known == null) {
      known = await _pack(await _fromPixels(cut, cw, ch), x, y);
      _byPixels[name] = known;
    }
    return known;
  }

  /// alone draws [picture] over [region] as a sheet of its own, untrimmed.
  Future<EpubSprite?> alone(ui.Picture picture, Rect region) async {
    var w = region.width.round(), h = region.height.round();
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(-region.left, -region.top)
      ..drawPicture(picture);
    var shifted = recorder.endRecording();
    try {
      var image = await shifted.toImage(w, h);
      var sprite = EpubSprite(
          _write(image), region.left, region.top, w.toDouble(), h.toDouble());
      _final[sprite] = sprite;
      return sprite;
    } finally {
      shifted.dispose();
    }
  }

  Future<EpubSprite> _pack(ui.Image piece, double x, double y) async {
    var w = piece.width, h = piece.height;
    if (_x + w > side && _x > 0) {
      _x = 0;
      _y += _row + gap;
      _row = 0;
    }
    if (_y + h > side && _pieces.isNotEmpty) await _flush();
    var sprite = EpubSprite("", x, y, w.toDouble(), h.toDouble(),
        sx: _x.toDouble(), sy: _y.toDouble());
    _pieces.add((piece, sprite));
    _x += w + gap;
    _row = math.max(_row, h);
    _wide = math.max(_wide, _x - gap);
    _tall = math.max(_tall, _y + h);
    return sprite;
  }

  Future<void> _flush() async {
    if (_pieces.isEmpty) return;
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder);
    for (var (image, s) in _pieces) {
      canvas.drawImage(image, Offset(s.sx, s.sy), ui.Paint());
    }
    var picture = recorder.endRecording();
    try {
      var href = _write(await picture.toImage(_wide, _tall));
      for (var (_, s) in _pieces) {
        _hrefs[s] = href;
      }
    } finally {
      picture.dispose();
      for (var (image, _) in _pieces) {
        image.dispose();
      }
      _pieces.clear();
      _x = _y = _row = _wide = _tall = 0;
    }
  }

  /// _write names [image]'s file at once and encodes it while the next is
  /// drawn; only [close] waits. The writer disposes the image.
  String _write(ui.Image image) {
    var href = "$stem-${_encoding.length}.png";
    _encoding.add(() async {
      try {
        var png = await image.toByteData(format: ui.ImageByteFormat.png);
        return png == null
            ? null
            : EpubFile(href, png.buffer.asUint8List(), "image/png");
      } finally {
        image.dispose();
      }
    }());
    return href;
  }

  /// close writes the last sheet and waits for every one to be encoded.
  Future<void> close() async {
    await _flush();
    for (var f in await Future.wait(_encoding)) {
      if (f != null) files.add(f);
    }
  }

  /// placed is [sprite] on the sheet it was written to.
  EpubSprite placed(EpubSprite sprite) => _final[sprite] ??= EpubSprite(
      _hrefs[sprite] ?? sprite.href,
      sprite.x,
      sprite.y,
      sprite.width,
      sprite.height,
      sx: sprite.sx,
      sy: sprite.sy);
}

Future<ui.Image> _fromPixels(Uint8List rgba, int width, int height) {
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, width, height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _inkBounds is the box round every pixel of [rgba] not fully clear, or
/// null. Read a word a pixel, so a blank row is a quarter of the reads.
Rect? _inkBounds(Uint8List rgba, int width, int height) {
  var px = rgba.buffer.asUint32List(rgba.offsetInBytes, width * height);
  // Two pixels a read, to find the empty rows round an element.
  var pairs = width.isEven
      ? rgba.buffer.asUint64List(rgba.offsetInBytes, width * height >> 1)
      : null;
  const alphas = 0xFF000000FF000000;
  bool blank(int y) {
    if (pairs == null) return false;
    var from = y * width >> 1, to = from + (width >> 1);
    for (var i = from; i < to; i++) {
      if (pairs[i] & alphas != 0) return false;
    }
    return true;
  }

  // Alpha is the last byte of each pixel: the top of a little-endian word.
  const alpha = 0xFF000000;
  var left = width, right = -1, top = height, bottom = -1;
  for (var y = 0; y < height; y++) {
    if (blank(y)) continue;
    var row = y * width;
    var l = -1;
    for (var x = 0; x < width; x++) {
      if (px[row + x] & alpha != 0) {
        l = x;
        break;
      }
    }
    if (l < 0) continue;
    var r = l;
    for (var x = width - 1; x > l; x--) {
      if (px[row + x] & alpha != 0) {
        r = x;
        break;
      }
    }
    if (l < left) left = l;
    if (r > right) right = r;
    if (y < top) top = y;
    bottom = y;
  }
  if (right < 0) return null;
  return Rect.fromLTRB(
      left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

/// _hashOf names a picture's pixels: 64-bit FNV-1a, only compared between
/// same-sized pictures in one place on one page, so fast is enough.
int _hashOf(Uint8List rgba) {
  var words = rgba.buffer.asUint32List(rgba.offsetInBytes, rgba.length >> 2);
  var h = 0xcbf29ce484222325;
  for (var i = 0; i < words.length; i++) {
    h = (h ^ words[i]) * 0x100000001b3;
  }
  return h;
}
