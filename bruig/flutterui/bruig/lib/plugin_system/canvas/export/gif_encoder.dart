import 'dart:typed_data';

// gif_encoder.dart writes an animated GIF.
//
// Written out rather than reached for, because there is no Flutter-native GIF
// encoder and the alternatives were shelling out to ffmpeg -- absent on most
// machines, and a silent failure for everybody who does not have it -- or
// adding a dependency for one file's worth of work. GIF89a is a small, fully
// specified, thirty-year-old format, and the whole of it that matters here is
// three things: a palette, LZW, and a loop extension.
//
// The three pieces, in the order they are hard:
//
//   Quantisation  a GIF holds at most 256 colours and a canvas holds
//                 millions. _medianCut chooses the 256, once for the whole
//                 animation rather than per frame -- a palette that changed
//                 between frames makes flat areas crawl, which is far more
//                 noticeable than any single frame being slightly off.
//
//   Dithering     with 256 colours a gradient bands visibly. Floyd-Steinberg
//                 spreads each pixel's error into its neighbours, trading the
//                 bands for a fine noise the eye reads as the original. It is
//                 optional because on flat-coloured work -- a tactics diagram,
//                 a chart -- it adds noise to something that quantised
//                 perfectly without it.
//
//   LZW           the compression the format specifies. Variable-width codes
//                 from 9 to 12 bits, with a clear code emitted when the
//                 dictionary fills. Fiddly, and completely mechanical.

/// gifMaxColors is what the format allows in one palette.
const int gifMaxColors = 256;

/// GifFrame is one frame's pixels, as straight RGBA.
class GifFrame {
  final Uint8List rgba;
  final int width;
  final int height;

  /// delayMs is how long this frame is shown. GIF stores it in hundredths of a
  /// second, so anything finer is rounded on the way out -- which is why the
  /// exporter warns about frame rates a GIF cannot actually hold.
  final int delayMs;

  const GifFrame({
    required this.rgba,
    required this.width,
    required this.height,
    required this.delayMs,
  });
}

/// encodeGif turns frames into a GIF89a file.
///
/// [loop] is how many times to repeat: 0 means forever, which is what almost
/// every animated GIF wants and what the exporter defaults to.
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

  // Any pixel that is not close to opaque becomes the transparent index. GIF
  // has one bit of alpha and no more, so a soft edge is either kept or cut;
  // 128 puts the boundary where a half-transparent pixel goes, which is the
  // least wrong place for it.
  var needsTransparency = frames.any((f) {
    for (var i = 3; i < f.rgba.length; i += 4) {
      if (f.rgba[i] < 128) return true;
    }
    return false;
  });

  var palette = _medianCut(frames, needsTransparency ? colors - 1 : colors);
  var transparentIndex = needsTransparency ? palette.length ~/ 3 : -1;
  if (needsTransparency) {
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

  // The Netscape application extension, which is how a GIF says "loop". It is
  // not in the specification; it is what every decoder implements instead.
  if (frames.length > 1) {
    out.addByte(0x21);
    out.addByte(0xFF);
    out.addByte(11);
    out.addString("NETSCAPE2.0");
    out.addByte(3);
    out.addByte(1);
    out.addUint16(loop);
    out.addByte(0);
  }

  for (var frame in frames) {
    var indices = _quantise(frame, lookup, transparentIndex, dither, palette);

    // Graphic control extension: the delay and the transparent index.
    out.addByte(0x21);
    out.addByte(0xF9);
    out.addByte(4);
    // Disposal 2 (restore to background) when there is transparency, so a
    // moving see-through element does not smear across the frames behind it.
    out.addByte((transparentIndex >= 0 ? 0x09 : 0x04));
    out.addUint16((frame.delayMs / 10).round().clamp(1, 65535));
    out.addByte(transparentIndex >= 0 ? transparentIndex : 0);
    out.addByte(0);

    // Image descriptor: the whole frame, no local table.
    out.addByte(0x2C);
    out.addUint16(0);
    out.addUint16(0);
    out.addUint16(frame.width);
    out.addUint16(frame.height);
    out.addByte(0);

    _lzwCompress(out, indices, bits < 2 ? 2 : bits);
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

/// _medianCut chooses a palette covering every frame.
///
/// The classic algorithm: put every colour in one box, then repeatedly split
/// the box with the widest spread along that widest channel, at its median,
/// until there are as many boxes as colours wanted. Each box becomes the
/// average of what is in it.
///
/// Median cut rather than a uniform cube or a popularity count, because it
/// spends its colours where the picture actually has them -- a canvas that is
/// mostly one green pitch and a few bright shirts gets shades of green *and*
/// the shirts, where a popularity count would spend all 256 on the grass.
Uint8List _medianCut(List<GifFrame> frames, int wanted) {
  // Sampled rather than exhaustive. A 1280x720 frame is nearly a million
  // pixels and thirty of them is thirty million; a stride keeps this to tens
  // of thousands, and a colour that appears in fewer than one pixel in
  // sixteen was never going to earn a palette entry.
  var samples = <int>[];
  for (var frame in frames) {
    var pixels = frame.rgba;
    var stride = 4 * (1 + pixels.length ~/ (4 * 20000));
    for (var i = 0; i < pixels.length; i += stride) {
      if (pixels[i + 3] < 128) continue;
      samples.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
    }
  }
  if (samples.isEmpty) return Uint8List.fromList([0, 0, 0]);

  var boxes = <List<int>>[samples];
  while (boxes.length < wanted) {
    var bestIndex = -1, bestSpread = -1, bestChannel = 0;
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].length < 2) continue;
      var lo = [255, 255, 255], hi = [0, 0, 0];
      for (var c in boxes[i]) {
        var rgb = [(c >> 16) & 255, (c >> 8) & 255, c & 255];
        for (var k = 0; k < 3; k++) {
          if (rgb[k] < lo[k]) lo[k] = rgb[k];
          if (rgb[k] > hi[k]) hi[k] = rgb[k];
        }
      }
      for (var k = 0; k < 3; k++) {
        var spread = hi[k] - lo[k];
        if (spread > bestSpread) {
          bestSpread = spread;
          bestIndex = i;
          bestChannel = k;
        }
      }
    }
    if (bestIndex < 0 || bestSpread <= 0) break;

    var box = boxes.removeAt(bestIndex);
    var shift = bestChannel == 0 ? 16 : (bestChannel == 1 ? 8 : 0);
    box.sort((a, b) => ((a >> shift) & 255).compareTo((b >> shift) & 255));
    var mid = box.length ~/ 2;
    boxes.add(box.sublist(0, mid));
    boxes.add(box.sublist(mid));
  }

  var palette = Uint8List(boxes.length * 3);
  for (var i = 0; i < boxes.length; i++) {
    var box = boxes[i];
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

/// _NearestColor maps a colour onto the closest palette entry.
///
/// Backed by a 32768-entry cache over the colour cube's top five bits per
/// channel. Without it this is the slowest thing in the encoder by an order of
/// magnitude -- a linear scan of 256 entries per pixel, a million pixels a
/// frame -- and with it almost every lookup is an array read.
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

  // Floyd-Steinberg over a working copy in signed space, because the error
  // pushed into a neighbour routinely takes it outside 0..255 and clamping it
  // at every step -- rather than only when it is read -- loses exactly the
  // error the algorithm exists to carry.
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

/// _lzwCompress writes the image data blocks for one frame.
///
/// The variable-width LZW the GIF specification defines: codes start one bit
/// wider than the palette, the dictionary grows as strings are seen, the code
/// width steps up as it fills, and a clear code resets it when it reaches
/// 4096. The output is a bit stream packed least-significant-bit first, cut
/// into sub-blocks of at most 255 bytes.
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
    // The dictionary is keyed by (prefix code, next byte) packed into one int,
    // which is what keeps it a plain int map rather than a map of lists.
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

/// _ByteSink is a growable byte buffer with the two writes this file needs.
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
