import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/pdf_writer.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_pdf_test.dart reads the PDF back rather than looking at its bytes.
//
// The same discipline as canvas_gif_test.dart, and for the same reason: a
// hand-written container is exactly the kind of thing that produces a file
// which passes a header check and which no reader will open. The two ways that
// happens with a PDF are a cross-reference offset that does not point at the
// object it claims, and a stream whose /Length disagrees with the bytes -- so
// the parser below checks both, follows the catalogue down to the page the way
// a reader does, and inflates the picture to see whether the pixels arrived.

/// _Pdf is enough of a PDF reader to check one.
class _Pdf {
  final Uint8List bytes;
  final String text;

  /// offsets is the cross-reference table: object number to byte offset.
  final Map<int, int> offsets = {};

  _Pdf(this.bytes) : text = latin1.decode(bytes) {
    var marker = text.lastIndexOf("startxref");
    expect(marker, greaterThan(0), reason: "no startxref");
    var start =
        int.parse(text.substring(marker + 9).trim().split("\n").first.trim());

    var table = text.substring(start);
    expect(table.startsWith("xref"), isTrue,
        reason: "startxref does not point at the table");
    var lines = table.split("\n");
    var count = int.parse(lines[1].trim().split(" ")[1]);
    // lines[0] is "xref", lines[1] is "0 <count>", and lines[2] is object
    // zero's free entry -- so object i's row is lines[2 + i].
    for (var i = 1; i < count; i++) {
      // "0000000123 00000 n" -- ten digits, a generation, and a flag.
      offsets[i] = int.parse(lines[2 + i].substring(0, 10));
    }
  }

  /// object is the body of one, found the way a reader finds it: by seeking to
  /// the offset the table gave and expecting the object to be there.
  String object(int number) {
    var at = offsets[number]!;
    expect(text.startsWith("$number 0 obj", at), isTrue,
        reason: "object $number is not at the offset the xref table gives");
    var end = text.indexOf("endobj", at);
    return text.substring(at, end);
  }

  /// stream is the raw bytes of an object's stream, taken by the /Length in
  /// its own dictionary rather than by looking for "endstream" -- which is
  /// what a reader does, and is the only way a wrong length is caught.
  Uint8List stream(int number) {
    var body = object(number);
    var length =
        int.parse(RegExp(r"/Length (\d+)").firstMatch(body)!.group(1)!);
    var from = offsets[number]! + body.indexOf("stream\n") + "stream\n".length;
    expect(text.startsWith("\nendstream", from + length), isTrue,
        reason: "the /Length of object $number does not reach its endstream");
    return bytes.sublist(from, from + length);
  }

  int refIn(String body, String key) =>
      int.parse(RegExp("$key (\\d+) 0 R").firstMatch(body)!.group(1)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CanvasDocument red({int width = 100}) => CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.square, width: width),
        background: const CanvasBackground(
          spec: ProceduralSpec(
              style: ProceduralStyle.plain,
              background: Color(0xFFFF0000),
              vignette: 0),
        ),
      );

  test("a reader can find its way from the trailer to the picture", () async {
    var export = await renderPdf(red());
    expect(export, isNotNull);
    expect(export!.mime, "application/pdf");

    var pdf = _Pdf(export.data);
    expect(pdf.text.startsWith("%PDF-1.7"), isTrue);
    expect(pdf.text.trimRight().endsWith("%%EOF"), isTrue);

    // The path a reader actually takes. Every step asserts the offset in the
    // table really points at the object it says it does.
    var root =
        pdf.refIn(pdf.text.substring(pdf.text.lastIndexOf("trailer")), "/Root");
    var catalogue = pdf.object(root);
    expect(catalogue, contains("/Type /Catalog"));

    var pages = pdf.object(pdf.refIn(catalogue, "/Pages"));
    expect(pages, contains("/Count 1"));

    var page = pdf.object(
        int.parse(RegExp(r"/Kids \[(\d+) 0 R\]").firstMatch(pages)!.group(1)!));
    expect(page, contains("/Type /Page"));

    var image = pdf.object(pdf.refIn(page, "/Im0"));
    expect(image, contains("/Subtype /Image"));
    expect(image, contains("/ColorSpace /DeviceRGB"));
  });

  test("the picture in the page is the canvas", () async {
    var export = await renderPdf(red(width: 40));
    var pdf = _Pdf(export!.data);
    var page = pdf.object(3);
    var number = pdf.refIn(page, "/Im0");
    var image = pdf.object(number);

    var width = int.parse(RegExp(r"/Width (\d+)").firstMatch(image)!.group(1)!);
    var height =
        int.parse(RegExp(r"/Height (\d+)").firstMatch(image)!.group(1)!);
    expect(width, 40);
    expect(height, 40);

    // Inflated with the same codec any reader would use. Three bytes a pixel
    // and every one of them the red the canvas was painted.
    var pixels = ZLibCodec().decode(pdf.stream(number));
    expect(pixels.length, width * height * 3);
    var middle = ((height ~/ 2) * width + width ~/ 2) * 3;
    expect(pixels[middle], 255);
    expect(pixels[middle + 1], 0);
    expect(pixels[middle + 2], 0);
  });

  test("an opaque canvas carries no mask, a transparent one does", () async {
    var opaque = _Pdf((await renderPdf(red(width: 20)))!.data);
    expect(opaque.object(4), isNot(contains("/SMask")),
        reason: "a megabyte of 255s that changes nothing");

    // Nothing painted at all: the frame is empty, so every pixel is clear.
    var clear = _Pdf((await renderPdf(const CanvasDocument(
      size: CanvasSize(ratio: CanvasRatio.square, width: 20),
      background: CanvasBackground(
        spec: ProceduralSpec(
            style: ProceduralStyle.plain,
            background: Color(0x00000000),
            vignette: 0),
      ),
    )))!
        .data);
    expect(clear.object(4), contains("/SMask 6 0 R"));
    expect(ZLibCodec().decode(clear.stream(6)).length, 20 * 20);
  });

  group("the page it goes on", () {
    test("a canvas page is the design at 96 to the inch", () {
      // A 1280-pixel canvas is a thirteen-inch page, not a seventeen-inch one:
      // a canvas is laid out in screen pixels, and a point is a 72nd of an
      // inch where a pixel is a 96th.
      var page = pageFor(PdfPaper.canvas, const Size(1280, 720));
      expect(page.width, closeTo(960, 0.01));
      expect(page.height, closeTo(540, 0.01));
      expect(page.margin, 0, reason: "a border nobody asked for");
    });

    test("paper turns to match the canvas", () {
      expect(pageFor(PdfPaper.a4, const Size(1280, 720)).width,
          greaterThan(pageFor(PdfPaper.a4, const Size(1280, 720)).height),
          reason: "a landscape design on a landscape sheet");
      expect(pageFor(PdfPaper.a4, const Size(720, 1280)).width,
          lessThan(pageFor(PdfPaper.a4, const Size(720, 1280)).height));
      expect(pageFor(PdfPaper.letter, const Size(100, 100)).width, 612);
    });

    test("the sheet is the paper's size, whatever the canvas is", () async {
      var export = await renderPdf(red(width: 40), paper: PdfPaper.a4);
      var pdf = _Pdf(export!.data);
      expect(pdf.object(3), contains("/MediaBox [0 0 595.28 841.89]"),
          reason: "a square canvas leaves A4 portrait");
    });

    test("more scale is more pixels on the same page", () async {
      var small = _Pdf((await renderPdf(red(width: 40)))!.data);
      var large = _Pdf((await renderPdf(red(width: 40), scale: 2))!.data);

      expect(large.object(4), contains("/Width 80"));
      expect(small.object(3).contains("/MediaBox"), isTrue);
      expect(RegExp(r"/MediaBox \[[^\]]+\]").firstMatch(small.object(3))![0],
          RegExp(r"/MediaBox \[[^\]]+\]").firstMatch(large.object(3))![0],
          reason: "scale is the print resolution, not the page size");
    });
  });

  test("a PDF is saved as one", () {
    expect(extensionFor("application/pdf"), ".pdf");
  });

  test("a picture that does not match its size is refused", () {
    expect(
        () =>
            writePdf(Uint8List(10), width: 100, height: 100, page: PdfPage.a4),
        throwsArgumentError);
  });
}
