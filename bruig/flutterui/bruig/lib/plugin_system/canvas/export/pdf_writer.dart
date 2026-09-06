import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

// pdf_writer.dart writes a one-page PDF holding a picture.
//
// Hand-written, for the same reason gif_encoder.dart is: the alternative was a
// dependency for a file format this needs one page of. What is written here is
// the smallest PDF that is actually a PDF -- a catalogue, a page, an image and
// a content stream that draws it -- and nothing else. No fonts, no annotations,
// no compression of anything but the pixels.
//
// The picture is a *raster*, deliberately, and that is worth defending. A
// vector PDF would mean drawing the canvas a second time in PDF's own
// operators, which is precisely the second renderer the whole export path
// exists to avoid -- and it could not draw most of a canvas anyway: a
// photograph, a procedural background, a blur, a background taken out of a
// picture. So the page carries what the canvas actually looks like, at
// whatever resolution was asked for, and the scale control on the publish
// sheet is the print resolution.
//
// Everything is written as bytes with the offsets tracked as they go, because
// a PDF's cross-reference table is a list of byte offsets into itself and
// there is no way to know one until the bytes before it exist.

/// PdfPage is the size of the sheet, in points, and how much of it is left
/// empty round the picture.
///
/// A point is a seventy-second of an inch, which is what a PDF measures
/// everything in.
class PdfPage {
  final String label;
  final double width;
  final double height;

  /// margin is the white edge on a paper size. Zero for a page cut to the
  /// canvas, where a margin would be a border nobody asked for.
  final double margin;

  const PdfPage(this.label, this.width, this.height, {this.margin = 0});

  /// a4 and letter are portrait. A canvas wider than it is tall gets them
  /// turned round -- see [pageFor], because a landscape design on a portrait
  /// sheet is a third of a page of picture and two thirds of nothing.
  static const a4 = PdfPage("A4", 595.28, 841.89, margin: 36);
  static const letter = PdfPage("Letter", 612, 792, margin: 36);

  PdfPage get turned => PdfPage(label, height, width, margin: margin);
}

/// PdfPaper is what the publish sheet offers.
enum PdfPaper {
  canvas("Same as the canvas"),
  a4("A4"),
  letter("Letter");

  final String label;
  const PdfPaper(this.label);

  /// turns is whether this is a sheet of paper, and so has an orientation to
  /// argue about. A page cut to the canvas is already the canvas's shape.
  bool get turns => this != PdfPaper.canvas;
}

/// PdfOrientation is which way up the paper goes.
///
/// Following the canvas is the sensible default and is not always what is
/// wanted: a wide design on a portrait sheet is a band across the top of the
/// page with room under it for everything else that is going on that page --
/// a heading, a table, a signature -- and somebody printing a report wants
/// exactly that far more often than they want a sideways sheet.
enum PdfOrientation {
  auto("Match the canvas"),
  portrait("Portrait"),
  landscape("Landscape");

  final String label;
  const PdfOrientation(this.label);
}

/// pointsPerPixel converts a canvas's own pixels to points.
///
/// A canvas is laid out in the same pixels a screen uses, which are 96 to the
/// inch; a PDF counts 72 to the inch. So a 1280-pixel canvas is a 960-point
/// page -- thirteen and a third inches -- which is the size the design would
/// print at if it were a web page. Treating a pixel as a point instead would
/// make every canvas a third larger than it was drawn.
const double pointsPerPixel = 72 / 96;

/// pageFor is the sheet a canvas of [size] pixels goes on.
///
/// [orientation] is ignored for a page cut to the canvas, which is the
/// canvas's shape by definition and has no second way up.
PdfPage pageFor(PdfPaper paper, Size size,
    {PdfOrientation orientation = PdfOrientation.auto}) {
  switch (paper) {
    case PdfPaper.canvas:
      return PdfPage(
        "Canvas",
        size.width * pointsPerPixel,
        size.height * pointsPerPixel,
      );
    case PdfPaper.a4:
    case PdfPaper.letter:
      var sheet = paper == PdfPaper.a4 ? PdfPage.a4 : PdfPage.letter;
      var wide = switch (orientation) {
        PdfOrientation.auto => size.width > size.height,
        PdfOrientation.landscape => true,
        PdfOrientation.portrait => false,
      };
      return wide ? sheet.turned : sheet;
  }
}

/// writePdf is one page carrying [rgba], straight (not premultiplied) RGBA of
/// [width] by [height] pixels.
///
/// The picture is centred on the page and made as large as it can be inside
/// the margin without changing shape -- so a wide canvas on a portrait sheet
/// fills the width and leaves the room above and below, which is the whole
/// reason somebody would choose that. A page cut to the canvas has no margin
/// and no letterboxing, so the two are the same thing there.
Uint8List writePdf(
  Uint8List rgba, {
  required int width,
  required int height,
  required PdfPage page,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    throw ArgumentError("the picture and its size do not agree");
  }

  // RGB and alpha are separated because PDF keeps them apart: the colours are
  // one image and the transparency is another, attached to it as a soft mask.
  var rgb = Uint8List(width * height * 3);
  var alpha = Uint8List(width * height);
  var opaque = true;
  for (var i = 0, to = 0; i < width * height; i++, to += 3) {
    rgb[to] = rgba[i * 4];
    rgb[to + 1] = rgba[i * 4 + 1];
    rgb[to + 2] = rgba[i * 4 + 2];
    var a = rgba[i * 4 + 3];
    alpha[i] = a;
    if (a != 255) opaque = false;
  }

  var deflate = ZLibCodec(level: 6);
  var colours = Uint8List.fromList(deflate.encode(rgb));
  // A canvas with no transparency anywhere is the common case, and its mask
  // would be a megabyte of 255s that changes nothing.
  var mask = opaque ? null : Uint8List.fromList(deflate.encode(alpha));

  var box = _fit(
    Size(width.toDouble(), height.toDouble()),
    Rect.fromLTWH(page.margin, page.margin,
        page.width - page.margin * 2, page.height - page.margin * 2),
  );

  var out = _PdfBuilder();
  out.header();

  var maskRef = mask == null ? 0 : 6;
  out.object(1, "<< /Type /Catalog /Pages 2 0 R >>");
  out.object(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
  out.object(
      3,
      "<< /Type /Page /Parent 2 0 R "
      "/MediaBox [0 0 ${_n(page.width)} ${_n(page.height)}] "
      "/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>");
  out.stream(
      4,
      "<< /Type /XObject /Subtype /Image /Width $width /Height $height "
      "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode"
      "${maskRef == 0 ? "" : " /SMask $maskRef 0 R"} >>",
      colours);

  // PDF's origin is the bottom left and its y counts upwards, so the image is
  // placed by its bottom edge. The matrix is a scale and a translation in one:
  // an image XObject is always drawn into the unit square, and this is what
  // says how big that square is and where it goes.
  out.stream(
      5,
      "<< /Filter /FlateDecode >>",
      Uint8List.fromList(deflate.encode(ascii.encode(
          "q\n${_n(box.width)} 0 0 ${_n(box.height)} "
          "${_n(box.left)} ${_n(page.height - box.bottom)} cm\n"
          "/Im0 Do\nQ\n"))));

  if (mask != null) {
    out.stream(
        6,
        "<< /Type /XObject /Subtype /Image /Width $width /Height $height "
        "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode >>",
        mask);
  }

  return out.finish();
}

/// _fit is the largest rectangle of [size]'s shape that fits in [into],
/// centred.
Rect _fit(Size size, Rect into) {
  if (into.width <= 0 || into.height <= 0) return into;
  var scale = (into.width / size.width) < (into.height / size.height)
      ? into.width / size.width
      : into.height / size.height;
  var width = size.width * scale;
  var height = size.height * scale;
  return Rect.fromLTWH(
    into.left + (into.width - width) / 2,
    into.top + (into.height - height) / 2,
    width,
    height,
  );
}

/// _n prints a number the way a PDF wants it: a plain decimal, never an
/// exponent, which is what Dart produces for a small enough double and which
/// no PDF reader accepts.
String _n(double value) {
  var text = value.toStringAsFixed(3);
  // Trailing zeroes are legal and are just noise in a file that carries a few
  // hundred of these.
  text = text.replaceFirst(RegExp(r"\.?0+$"), "");
  return text.isEmpty || text == "-" ? "0" : text;
}

/// _PdfBuilder collects the objects and remembers where each one started.
class _PdfBuilder {
  final BytesBuilder _bytes = BytesBuilder();

  /// _offsets is object number to byte offset, which is the whole content of
  /// the cross-reference table at the end.
  final Map<int, int> _offsets = {};

  void header() {
    _bytes.add(ascii.encode("%PDF-1.7\n"));
    // Four bytes above 127 on the second line. It is a comment, and it is
    // there to tell anything transferring the file that this is binary and
    // must not have its line endings helpfully corrected.
    _bytes.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  }

  void object(int number, String body) {
    _offsets[number] = _bytes.length;
    _bytes.add(ascii.encode("$number 0 obj\n$body\nendobj\n"));
  }

  void stream(int number, String dict, Uint8List data) {
    _offsets[number] = _bytes.length;
    // The length goes in the dictionary that precedes the bytes it describes,
    // which is why the data has to be complete before any of this is written.
    var head = dict.substring(0, dict.length - 3);
    _bytes.add(ascii
        .encode("$number 0 obj\n$head /Length ${data.length} >>\nstream\n"));
    _bytes.add(data);
    _bytes.add(ascii.encode("\nendstream\nendobj\n"));
  }

  Uint8List finish() {
    var count = _offsets.keys.fold(0, (m, k) => k > m ? k : m) + 1;
    var start = _bytes.length;

    var table = StringBuffer("xref\n0 $count\n");
    // Object zero is always the head of the free list, and is always written
    // exactly like this.
    table.write("0000000000 65535 f \n");
    for (var i = 1; i < count; i++) {
      var at = _offsets[i] ?? 0;
      table.write("${at.toString().padLeft(10, "0")} 00000 n \n");
    }
    table.write("trailer\n<< /Size $count /Root 1 0 R >>\n"
        "startxref\n$start\n%%EOF\n");
    _bytes.add(ascii.encode(table.toString()));
    return _bytes.takeBytes();
  }
}
