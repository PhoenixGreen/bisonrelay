import 'dart:math' as math;
import 'dart:typed_data';

// gif_encoder.dart writes an animated GIF89a by hand: there is no
// Flutter-native encoder, and ffmpeg is absent on most machines.
//
// One palette is chosen by median cut for the whole animation, since a
// palette that changes between frames makes flat areas crawl. Floyd-Steinberg
// dithering is optional: it hides banding in gradients but adds noise to
// flat-coloured work that quantises perfectly without it.

/// gifMaxColors is what the format allows in one palette.
const int gifMaxColors = 256;

/// GifFrame is one frame's pixels, as straight RGBA.
class GifFrame {
  final Uint8List rgba;
  final int width;
  final int height;

  /// delayMs is how long this frame is shown. GIF stores hundredths of a
  /// second, so anything finer is rounded.
  final int delayMs;

  const GifFrame({
    required this.rgba,
    required this.width,
    required this.height,
    required this.delayMs,
  });
}

/// encodeGif turns frames into a GIF89a file. [loop] is how many times it
/// plays, 0 for forever.
Uint8List encodeGif(
  List<GifFrame> frames, {
  int loop = 0,
  bool dither = true,
  int maxColors = gifMaxColors,
}) {
  if (frames.isEmpty) return Uint8List(0);

  var width = frames.first.width;
  var height = frames.first.height;
  var colors = maxColors.clamp(2, gifMaxColors);

  // GIF has one bit of alpha: any pixel under half opacity becomes the
  // transparent index.
  var needsTransparency = frames.any((f) {
    for (var i = 3; i < f.rgba.length; i += 4) {
      if (f.rgba[i] < 128) return true;
    }
    return false;
  });

  // Frames after the first carry only what changed, the rest transparent so
  // the frame beneath shows through; a canvas is mostly still, so this is
  // most of the file's size. Only where the art is opaque: patched frames
  // stay until drawn over, so a see-through element moving would leave a
  // trail. With real transparency every frame is written in full and
  // disposed before the next.
  var differencing = frames.length > 1 && !needsTransparency;
  var spare = needsTransparency || differencing;

  var palette = _medianCut(frames, spare ? colors - 1 : colors);
  var transparentIndex = spare ? palette.length ~/ 3 : -1;
  if (spare) {
    palette = Uint8List.fromList([...palette, 0, 0, 0]);
  }

  var lookup = _NearestColor(palette);
  var out = _ByteSink();

  // Header and logical screen descriptor.
  out.addString("GIF89a");
  out.addUint16(width);
  out.addUint16(height);

  var bits = _paletteBits(palette.length ~/ 3);
  var tableSize = 1 << bits;
  out.addByte(0xF0 | (bits - 1)); // Global table present, 8 bits per channel.
  out.addByte(0); // Background colour index.
  out.addByte(0); // Pixel aspect ratio: none given.

  for (var i = 0; i < tableSize; i++) {
    var p = i * 3;
    out.addByte(p < palette.length ? palette[p] : 0);
    out.addByte(p + 1 < palette.length ? palette[p + 1] : 0);
    out.addByte(p + 2 < palette.length ? palette[p + 2] : 0);
  }

  // The Netscape extension (not in the specification, but universal) says
  // "loop". Its count is of repeats after the first play, so once is none.
  if (frames.length > 1 && loop != 1) {
    out.addByte(0x21);
    out.addByte(0xFF);
    out.addByte(11);
    out.addString("NETSCAPE2.0");
    out.addByte(3);
    out.addByte(1);
    out.addUint16(loop <= 0 ? 0 : loop - 1);
    out.addByte(0);
  }

  // Only the frame before is kept, never all of them.
  Uint8List? previous;

  for (var frame in frames) {
    var indices = _quantise(frame, lookup, transparentIndex, dither, palette);

    // The whole frame, or the rectangle that differs from the frame before.
    var left = 0;
    var top = 0;
    var width_ = frame.width;
    var height_ = frame.height;
    var payload = indices;

    if (differencing && previous != null) {
      var box = _changedBox(previous, indices, frame.width, frame.height);
      if (box == null) {
        // Nothing moved: one transparent pixel holds the frame for another
        // delay.
        left = 0;
        top = 0;
        width_ = 1;
        height_ = 1;
        payload = Uint8List.fromList([transparentIndex]);
      } else {
        var (x0, y0, x1, y1) = box;
        left = x0;
        top = y0;
        width_ = x1 - x0 + 1;
        height_ = y1 - y0 + 1;
        payload = Uint8List(width_ * height_);
        for (var y = 0; y < height_; y++) {
          var from = (y0 + y) * frame.width + x0;
          var to = y * width_;
          for (var x = 0; x < width_; x++) {
            var value = indices[from + x];
            // Unchanged pixels inside the rectangle are see-through too, so a
            // diagonal move costs its line rather than its box.
            payload[to + x] =
                value == previous[from + x] ? transparentIndex : value;
          }
        }
      }
    }

    // Graphic control extension: the delay and the transparent index.
    out.addByte(0x21);
    out.addByte(0xF9);
    out.addByte(4);
    // Disposal 1 (leave in place) while differencing; 2 (restore to
    // background) for full frames with transparency, so a moving
    // see-through element does not smear.
    var disposal = differencing ? 0x05 : (transparentIndex >= 0 ? 0x09 : 0x04);
    out.addByte(disposal);
    out.addUint16((frame.delayMs / 10).round().clamp(1, 65535));
    out.addByte(transparentIndex >= 0 ? transparentIndex : 0);
    out.addByte(0);

    // Image descriptor: where this frame's pixels go, and no local table.
    out.addByte(0x2C);
    out.addUint16(left);
    out.addUint16(top);
    out.addUint16(width_);
    out.addUint16(height_);
    out.addByte(0);

    _lzwCompress(out, payload, bits < 2 ? 2 : bits);
    if (differencing) previous = indices;
  }

  out.addByte(0x3B); // Trailer.
  return out.toBytes();
}

int _paletteBits(int count) {
  var bits = 1;
  while ((1 << bits) < count && bits < 8) {
    bits++;
  }
  return bits;
}

// --------------------------------------------------------------------------
// Quantisation
// --------------------------------------------------------------------------

/// _medianCut chooses a palette covering every frame: the box with the
/// widest channel spread is split at its median until there are [wanted]
/// boxes, each becoming the average of its colours. Unlike a popularity
/// count, it keeps rare bright colours as well as shades of a dominant one.
Uint8List _medianCut(List<GifFrame> frames, int wanted) {
  // Sampled at a stride: about 20,000 pixels a frame, and no more than
  // [_mostSamples] in all, so a long animation is not millions of them.
  var each = math.max(1000, math.min(20000, _mostSamples ~/ frames.length));
  var samples = <int>[];
  for (var frame in frames) {
    var pixels = frame.rgba;
    var stride = 4 * (1 + pixels.length ~/ (4 * each));
    for (var i = 0; i < pixels.length; i += stride) {
      if (pixels[i + 3] < 128) continue;
      samples.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
    }
  }
  if (samples.isEmpty) return Uint8List.fromList([0, 0, 0]);

  // Each box knows its widest channel from when it was made, rather than
  // every box being measured again at every split.
  var boxes = <_Box>[_Box(samples)];
  while (boxes.length < wanted) {
    var bestIndex = -1, bestSpread = 0;
    for (var i = 0; i < boxes.length; i++) {
      var b = boxes[i];
      if (b.colours.length >= 2 && b.spread > bestSpread) {
        bestSpread = b.spread;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) break;

    var box = boxes.removeAt(bestIndex);
    var shift = box.channel == 0 ? 16 : (box.channel == 1 ? 8 : 0);
    var colours = box.colours
      ..sort((a, b) => ((a >> shift) & 255).compareTo((b >> shift) & 255));
    var mid = colours.length ~/ 2;
    boxes.add(_Box(colours.sublist(0, mid)));
    boxes.add(_Box(colours.sublist(mid)));
  }

  var palette = Uint8List(boxes.length * 3);
  for (var i = 0; i < boxes.length; i++) {
    var box = boxes[i].colours;
    if (box.isEmpty) continue;
    var r = 0, g = 0, b = 0;
    for (var c in box) {
      r += (c >> 16) & 255;
      g += (c >> 8) & 255;
      b += c & 255;
    }
    palette[i * 3] = r ~/ box.length;
    palette[i * 3 + 1] = g ~/ box.length;
    palette[i * 3 + 2] = b ~/ box.length;
  }
  return palette;
}

/// _mostSamples is the most pixels a palette is chosen from.
const int _mostSamples = 200000;

/// _Box is a median cut's box: its colours, and the channel they spread
/// widest along and by how much.
class _Box {
  final List<int> colours;
  int channel = 0, spread = 0;

  _Box(this.colours) {
    var lr = 255, lg = 255, lb = 255, hr = 0, hg = 0, hb = 0;
    for (var c in colours) {
      var r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
      if (r < lr) lr = r;
      if (r > hr) hr = r;
      if (g < lg) lg = g;
      if (g > hg) hg = g;
      if (b < lb) lb = b;
      if (b > hb) hb = b;
    }
    for (var (k, d) in [(0, hr - lr), (1, hg - lg), (2, hb - lb)]) {
      if (d > spread) {
        spread = d;
        channel = k;
      }
    }
  }
}

/// _NearestColor maps a colour onto the closest palette entry, cached over
/// the top five bits per channel: without the cache, a linear scan per
/// pixel is the encoder's slowest step by far.
class _NearestColor {
  final Uint8List palette;
  final Int16List _cache = Int16List(1 << 15)..fillRange(0, 1 << 15, -1);

  _NearestColor(this.palette);

  int of(int r, int g, int b) {
    var key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    var cached = _cache[key];
    if (cached >= 0) return cached;

    var best = 0, bestDistance = 1 << 30;
    for (var i = 0; i * 3 + 2 < palette.length; i++) {
      var dr = r - palette[i * 3];
      var dg = g - palette[i * 3 + 1];
      var db = b - palette[i * 3 + 2];
      var d = dr * dr + dg * dg + db * db;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
        if (d == 0) break;
      }
    }
    _cache[key] = best;
    return best;
  }
}

/// _quantise turns one frame's pixels into palette indices.
Uint8List _quantise(GifFrame frame, _NearestColor lookup, int transparentIndex,
    bool dither, Uint8List palette) {
  var width = frame.width, height = frame.height;
  var out = Uint8List(width * height);

  if (!dither) {
    for (var i = 0; i < out.length; i++) {
      var p = i * 4;
      if (transparentIndex >= 0 && frame.rgba[p + 3] < 128) {
        out[i] = transparentIndex;
        continue;
      }
      out[i] = lookup.of(frame.rgba[p], frame.rgba[p + 1], frame.rgba[p + 2]);
    }
    return out;
  }

  // Floyd-Steinberg over a signed working copy, clamped only when read:
  // clamping the neighbours as error is pushed would lose that error.
  var work = Int32List(width * height * 3);
  for (var i = 0; i < width * height; i++) {
    work[i * 3] = frame.rgba[i * 4];
    work[i * 3 + 1] = frame.rgba[i * 4 + 1];
    work[i * 3 + 2] = frame.rgba[i * 4 + 2];
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var i = y * width + x;
      if (transparentIndex >= 0 && frame.rgba[i * 4 + 3] < 128) {
        out[i] = transparentIndex;
        continue;
      }

      var r = work[i * 3].clamp(0, 255);
      var g = work[i * 3 + 1].clamp(0, 255);
      var b = work[i * 3 + 2].clamp(0, 255);
      var index = lookup.of(r, g, b);
      out[i] = index;

      var er = r - palette[index * 3];
      var eg = g - palette[index * 3 + 1];
      var eb = b - palette[index * 3 + 2];

      void spread(int nx, int ny, int numerator) {
        if (nx < 0 || nx >= width || ny >= height) return;
        var n = (ny * width + nx) * 3;
        work[n] += er * numerator ~/ 16;
        work[n + 1] += eg * numerator ~/ 16;
        work[n + 2] += eb * numerator ~/ 16;
      }

      spread(x + 1, y, 7);
      spread(x - 1, y + 1, 3);
      spread(x, y + 1, 5);
      spread(x + 1, y + 1, 1);
    }
  }
  return out;
}

// --------------------------------------------------------------------------
// LZW
// --------------------------------------------------------------------------

/// _lzwCompress writes one frame's image data: GIF's variable-width LZW,
/// codes up to 12 bits, a clear code when the dictionary reaches 4096,
/// packed least-significant-bit first into sub-blocks of up to 255 bytes.
void _lzwCompress(_ByteSink out, Uint8List indices, int minimumCodeSize) {
  out.addByte(minimumCodeSize);

  var clearCode = 1 << minimumCodeSize;
  var endCode = clearCode + 1;
  var nextCode = endCode + 1;
  var codeSize = minimumCodeSize + 1;

  var dictionary = <int, int>{};
  var blocks = _BlockSink(out);
  var bitBuffer = 0, bitCount = 0;

  void emit(int code) {
    bitBuffer |= code << bitCount;
    bitCount += codeSize;
    while (bitCount >= 8) {
      blocks.add(bitBuffer & 0xFF);
      bitBuffer >>= 8;
      bitCount -= 8;
    }
  }

  emit(clearCode);
  if (indices.isEmpty) {
    emit(endCode);
    while (bitCount > 0) {
      blocks.add(bitBuffer & 0xFF);
      bitBuffer >>= 8;
      bitCount -= 8;
    }
    blocks.finish();
    return;
  }

  var current = indices[0];
  for (var i = 1; i < indices.length; i++) {
    var next = indices[i];
    // Keyed by (prefix code, next byte) packed into one int.
    var key = (current << 8) | next;
    var found = dictionary[key];
    if (found != null) {
      current = found;
      continue;
    }

    emit(current);
    if (nextCode < 4096) {
      dictionary[key] = nextCode++;
      if (nextCode > (1 << codeSize) && codeSize < 12) codeSize++;
    } else {
      emit(clearCode);
      dictionary.clear();
      nextCode = endCode + 1;
      codeSize = minimumCodeSize + 1;
    }
    current = next;
  }

  emit(current);
  emit(endCode);
  while (bitCount > 0) {
    blocks.add(bitBuffer & 0xFF);
    bitBuffer >>= 8;
    bitCount -= 8;
  }
  blocks.finish();
}

/// _BlockSink cuts a byte stream into GIF's sub-blocks: a length byte then up
/// to 255 bytes, ending with a zero-length block.
class _BlockSink {
  final _ByteSink out;
  final List<int> _buffer = [];

  _BlockSink(this.out);

  void add(int byte) {
    _buffer.add(byte);
    if (_buffer.length == 255) _flush();
  }

  void _flush() {
    if (_buffer.isEmpty) return;
    out.addByte(_buffer.length);
    out.addBytes(_buffer);
    _buffer.clear();
  }

  void finish() {
    _flush();
    out.addByte(0);
  }
}

/// _ByteSink is a growable byte buffer.
class _ByteSink {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void addByte(int b) => _builder.addByte(b & 0xFF);
  void addBytes(List<int> bytes) => _builder.add(bytes);
  void addString(String s) => _builder.add(s.codeUnits);
  void addUint16(int v) {
    // Little endian, which is what every multi-byte field in a GIF is.
    _builder.addByte(v & 0xFF);
    _builder.addByte((v >> 8) & 0xFF);
  }

  Uint8List toBytes() => _builder.toBytes();
}

/// _changedBox is the inclusive rectangle two frames differ in, or null
/// where they do not differ.
(int, int, int, int)? _changedBox(
    Uint8List before, Uint8List after, int width, int height) {
  var left = width;
  var right = -1;
  var top = height;
  var bottom = -1;
  for (var y = 0; y < height; y++) {
    var row = y * width;
    for (var x = 0; x < width; x++) {
      if (before[row + x] == after[row + x]) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      bottom = y;
    }
  }
  if (right < 0) return null;
  return (left, top, right, bottom);
}
