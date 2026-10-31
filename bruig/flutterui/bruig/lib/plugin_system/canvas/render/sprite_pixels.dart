import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

// sprite_pixels.dart is a sprite sheet's pixels, held to paint on: a dot or
// a line of them in a colour -- or cleared -- a run of one colour filled,
// a colour picked up, a frame copied to another, the sheet made bigger for
// more frames; and the picture made of them again. What the Sprite
// element's painter draws with -- see the stage's sprite painting.

class SpritePixels {
  final int width;
  final int height;

  /// rgba is red, green, blue and alpha for each pixel, row by row.
  final Uint8List rgba;

  SpritePixels(this.width, this.height, this.rgba);

  /// blank is a sheet [width] by [height] pixels with nothing on it.
  factory SpritePixels.blank(int width, int height) =>
      SpritePixels(width, height, Uint8List((width < 1 ? 1 : width) * (height < 1 ? 1 : height) * 4));

  /// of is [image]'s pixels.
  static Future<SpritePixels?> of(ui.Image image) async {
    var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return SpritePixels(image.width, image.height, data.buffer.asUint8List());
  }

  SpritePixels copy() => SpritePixels(width, height, Uint8List.fromList(rgba));

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  /// at is the colour of pixel [x], [y].
  ui.Color at(int x, int y) {
    if (!inside(x, y)) return const ui.Color(0x00000000);
    var i = (y * width + x) * 4;
    return ui.Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  void _put(int x, int y, ui.Color c, ui.Rect? within) {
    if (!inside(x, y)) return;
    if (within != null && !within.contains(ui.Offset(x + 0.5, y + 0.5))) return;
    var i = (y * width + x) * 4;
    rgba[i] = (c.r * 255).round();
    rgba[i + 1] = (c.g * 255).round();
    rgba[i + 2] = (c.b * 255).round();
    rgba[i + 3] = (c.a * 255).round();
  }

  /// dab sets a square [size] pixels across at [x], [y] to [colour] --
  /// clear, to rub out -- kept [within] a frame.
  void dab(int x, int y, ui.Color colour, {int size = 1, ui.Rect? within}) {
    var half = (size - 1) ~/ 2;
    for (var dy = -half; dy < size - half; dy++) {
      for (var dx = -half; dx < size - half; dx++) {
        _put(x + dx, y + dy, colour, within);
      }
    }
  }

  /// line dabs every pixel from [x0], [y0] to [x1], [y1]: a line with no
  /// gaps, however fast the pen moved.
  void line(int x0, int y0, int x1, int y1, ui.Color colour, {int size = 1, ui.Rect? within}) {
    var dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    var sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    var x = x0, y = y0;
    while (true) {
      dab(x, y, colour, size: size, within: within);
      if (x == x1 && y == y1) break;
      var e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y += sy;
      }
    }
  }

  /// fill sets the run of one colour that [x], [y] is in -- touching side
  /// by side -- to [colour], kept [within] a frame.
  void fill(int x, int y, ui.Color colour, {ui.Rect? within}) {
    if (!inside(x, y)) return;
    var from = at(x, y).toARGB32();
    if (from == colour.toARGB32()) return;
    var bounds = within ?? ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    var left = math.max(0, bounds.left.floor()), top = math.max(0, bounds.top.floor());
    var right = math.min(width, bounds.right.ceil()), bottom = math.min(height, bounds.bottom.ceil());
    var stack = <int>[y * width + x];
    var seen = Uint8List(width * height);
    while (stack.isNotEmpty) {
      var p = stack.removeLast();
      if (seen[p] == 1) continue;
      seen[p] = 1;
      var px = p % width, py = p ~/ width;
      if (px < left || px >= right || py < top || py >= bottom) continue;
      if (at(px, py).toARGB32() != from) continue;
      _put(px, py, colour, null);
      if (px > 0) stack.add(p - 1);
      if (px < width - 1) stack.add(p + 1);
      if (py > 0) stack.add(p - width);
      if (py < height - 1) stack.add(p + width);
    }
  }

  /// copyFrame copies the pixels of [from] onto [to], the same size.
  void copyFrame(ui.Rect from, ui.Rect to) {
    var w = math.min(from.width, to.width).floor(), h = math.min(from.height, to.height).floor();
    var src = Uint8List.fromList(rgba);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sx = from.left.floor() + x, sy = from.top.floor() + y;
        var tx = to.left.floor() + x, ty = to.top.floor() + y;
        if (!inside(sx, sy) || !inside(tx, ty)) continue;
        var i = (sy * width + sx) * 4, j = (ty * width + tx) * 4;
        for (var k = 0; k < 4; k++) {
          rgba[j + k] = src[i + k];
        }
      }
    }
  }

  /// grown is this sheet made [w] by [h] pixels, what it had kept in its
  /// top left corner and the rest clear: room for more frames.
  SpritePixels grown(int w, int h) {
    var out = SpritePixels.blank(w, h);
    for (var y = 0; y < math.min(h, height); y++) {
      var n = math.min(w, width) * 4;
      out.rgba.setRange(y * w * 4, y * w * 4 + n, rgba, y * width * 4);
    }
    return out;
  }

  /// image is the picture of these pixels.
  Future<ui.Image> image() {
    var done = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  /// png is these pixels as a .png file's bytes.
  Future<Uint8List?> png() async {
    var img = await image();
    var data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data?.buffer.asUint8List();
  }
}

/// spriteDrawnPart is the part of [frames] -- each a frame's place on the
/// sheet [image] -- anything is drawn in, every frame's together, as shares
/// of a frame; or null with nothing drawn. What a game touches of a sprite
/// -- see SpriteElement.drawn.
Future<ui.Rect?> spriteDrawnPart(ui.Image image, List<ui.Rect> frames) async {
  var px = await SpritePixels.of(image);
  if (px == null || frames.isEmpty) return null;
  double? l, t, r, b;
  for (var f in frames) {
    var x0 = f.left.floor().clamp(0, px.width),
        x1 = f.right.ceil().clamp(0, px.width);
    var y0 = f.top.floor().clamp(0, px.height),
        y1 = f.bottom.ceil().clamp(0, px.height);
    if (x1 <= x0 || y1 <= y0) continue;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        // More than faintly there: a soft edge's last pixels are not it.
        if (px.rgba[(y * px.width + x) * 4 + 3] < 32) continue;
        var u = (x - f.left) / f.width, v = (y - f.top) / f.height;
        var u1 = (x + 1 - f.left) / f.width, v1 = (y + 1 - f.top) / f.height;
        l = l == null ? u : math.min(l, u);
        t = t == null ? v : math.min(t, v);
        r = r == null ? u1 : math.max(r, u1);
        b = b == null ? v1 : math.max(b, v1);
      }
    }
  }
  if (l == null) return null;
  return ui.Rect.fromLTRB(l, t!, r!, b!);
}
