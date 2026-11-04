import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

// pdf_writer.dart writes a PDF of pictures, one to a page: a catalogue, a
// page tree, and per page an image (with a soft mask where it has
// transparency) and a content stream that draws it. No fonts.
//
// The pages are rasters on purpose: a vector PDF would be a second renderer,
// and could not draw photographs, procedural backgrounds or blurs anyway.
// The publish sheet's scale is the print resolution.

/// PdfPage is the size of the sheet in points (1/72 inch) and the margin
/// round the picture.
class PdfPage {
  final String label;
  final double width;
  final double height;

  /// margin is the white edge on a paper size; zero for a page cut to the
  /// canvas.
  final double margin;

  const PdfPage(this.label, this.width, this.height, {this.margin = 0});

  /// a4 and letter are portrait; [pageFor] turns them for a wide canvas.
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

  /// turns is whether this paper has an orientation to choose: a page cut
  /// to the canvas does not.
  bool get turns => this != PdfPaper.canvas;
}

/// PdfOrientation is which way up the paper goes. Portrait for a wide
/// canvas leaves room on the page for other printed matter.
enum PdfOrientation {
  auto("Match the canvas"),
  portrait("Portrait"),
  landscape("Landscape");

  final String label;
  const PdfOrientation(this.label);
}

/// pointsPerPixel converts canvas pixels (96 to the inch, as on screen) to
/// PDF points (72 to the inch).
const double pointsPerPixel = 72 / 96;

/// pageFor is the sheet a canvas of [size] pixels goes on. [orientation] is
/// ignored for a page cut to the canvas.
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

/// PdfPicture is one page's pixels: straight (not premultiplied) RGBA.
class PdfPicture {
  final Uint8List rgba;
  final int width;
  final int height;

  const PdfPicture(this.rgba, {required this.width, required this.height});
}

/// writePdf writes [pictures], one to a page, each centred and made as
/// large as fits inside the margin without changing shape.
Uint8List writePdf(List<PdfPicture> pictures, {required PdfPage page}) {
  if (pictures.isEmpty) throw ArgumentError("a PDF needs at least one page");
  for (var picture in pictures) {
    if (picture.width <= 0 ||
        picture.height <= 0 ||
        picture.rgba.length < picture.width * picture.height * 4) {
      throw ArgumentError("the picture and its size do not agree");
    }
  }

  var deflate = ZLibCodec(level: 6);
  var out = _PdfBuilder();
  out.header();

  // Object numbers are handed out up front, as a page names the image that
  // follows it: catalogue 1, page tree 2, then per page the page, image,
  // content stream and, where needed, the mask.
  var pageRefs = <int>[];
  var next = 3;
  var plan = <(int, int, int, int, Uint8List, Uint8List?, Rect)>[];
  for (var picture in pictures) {
    var rgb = Uint8List(picture.width * picture.height * 3);
    var alpha = Uint8List(picture.width * picture.height);
    var opaque = true;
    for (var i = 0, to = 0; i < picture.width * picture.height; i++, to += 3) {
      rgb[to] = picture.rgba[i * 4];
      rgb[to + 1] = picture.rgba[i * 4 + 1];
      rgb[to + 2] = picture.rgba[i * 4 + 2];
      var a = picture.rgba[i * 4 + 3];
      alpha[i] = a;
      if (a != 255) opaque = false;
    }
    var colours = Uint8List.fromList(deflate.encode(rgb));
    // No mask for a fully opaque picture.
    var mask = opaque ? null : Uint8List.fromList(deflate.encode(alpha));

    var box = _fit(
      Size(picture.width.toDouble(), picture.height.toDouble()),
      Rect.fromLTWH(page.margin, page.margin, page.width - page.margin * 2,
          page.height - page.margin * 2),
    );

    var pageRef = next++;
    var imageRef = next++;
    var contentRef = next++;
    var maskRef = mask == null ? 0 : next++;
    pageRefs.add(pageRef);
    plan.add((pageRef, imageRef, contentRef, maskRef, colours, mask, box));
  }

  out.object(1, "<< /Type /Catalog /Pages 2 0 R >>");
  out.object(
      2,
      "<< /Type /Pages /Kids [${pageRefs.map((r) => "$r 0 R").join(" ")}] "
      "/Count ${pageRefs.length} >>");

  for (var i = 0; i < plan.length; i++) {
    var (pageRef, imageRef, contentRef, maskRef, colours, mask, box) = plan[i];
    var picture = pictures[i];
    out.object(
        pageRef,
        "<< /Type /Page /Parent 2 0 R "
        "/MediaBox [0 0 ${_n(page.width)} ${_n(page.height)}] "
        "/Resources << /XObject << /Im0 $imageRef 0 R >> >> "
        "/Contents $contentRef 0 R >>");
    out.stream(
        imageRef,
        "<< /Type /XObject /Subtype /Image /Width ${picture.width} "
        "/Height ${picture.height} "
        "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode"
        "${maskRef == 0 ? "" : " /SMask $maskRef 0 R"} >>",
        colours);

    // PDF's y counts up from the bottom, so the image is placed by its
    // bottom edge; the matrix maps the image's unit square onto [box].
    out.stream(
        contentRef,
        "<< /Filter /FlateDecode >>",
        Uint8List.fromList(deflate
            .encode(ascii.encode("q\n${_n(box.width)} 0 0 ${_n(box.height)} "
                "${_n(box.left)} ${_n(page.height - box.bottom)} cm\n"
                "/Im0 Do\nQ\n"))));

    if (mask != null) {
      out.stream(
          maskRef,
          "<< /Type /XObject /Subtype /Image /Width ${picture.width} "
          "/Height ${picture.height} "
          "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode >>",
          mask);
    }
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

/// _n prints a number as a PDF wants it: a plain decimal, never the
/// exponent Dart gives a small double.
String _n(double value) {
  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r"\.?0+$"), "");
  return text.isEmpty || text == "-" ? "0" : text;
}

/// _PdfBuilder collects the objects and remembers where each one started.
class _PdfBuilder {
  final BytesBuilder _bytes = BytesBuilder();

  /// _offsets is object number to byte offset, for the cross-reference
  /// table.
  final Map<int, int> _offsets = {};

  void header() {
    _bytes.add(ascii.encode("%PDF-1.7\n"));
    // A comment of bytes above 127, marking the file as binary to anything
    // that would correct its line endings.
    _bytes.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  }

  void object(int number, String body) {
    _offsets[number] = _bytes.length;
    _bytes.add(ascii.encode("$number 0 obj\n$body\nendobj\n"));
  }

  void stream(int number, String dict, Uint8List data) {
    _offsets[number] = _bytes.length;
    // The length goes in the dictionary before the data, so the data must
    // be complete first.
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
    // Object zero is always the head of the free list.
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
