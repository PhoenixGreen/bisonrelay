import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';
import 'package:flutter/painting.dart';

// vector_writers.dart writes what a VectorCanvas recorded as SVG or as a
// one-page PDF. Shapes are paths; words are words, in the app's typefaces in
// an SVG and PDF's standard faces in a PDF, each line stretched to its
// on-screen width so nothing moves; what had no vector form is a picture.

String _n(double v) {
  if (v.isNaN || v.isInfinite) return "0";
  var s = v.toStringAsFixed(2);
  if (s.contains(".")) {
    s = s.replaceFirst(RegExp(r"0+$"), "");
    if (s.endsWith(".")) s = s.substring(0, s.length - 1);
  }
  return s == "-0" ? "0" : s;
}

String _hex(Color c) =>
    "#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, "0")}";

String _esc(String s) => s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

String _svgPath(List<VPoly> polys) {
  var b = StringBuffer();
  for (var p in polys) {
    if (p.points.isEmpty) continue;
    b.write("M${_n(p.points.first.dx)} ${_n(p.points.first.dy)}");
    for (var q in p.points.skip(1)) {
      b.write("L${_n(q.dx)} ${_n(q.dy)}");
    }
    if (p.closed) b.write("Z");
  }
  return b.toString();
}

Future<Uint8List> _png(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();

/// vectorSvg is [v]'s drawing as an SVG document.
Future<String> vectorSvg(VectorCanvas v) async {
  var w = v.size.width, h = v.size.height;
  var b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="${_n(w)}" height="${_n(h)}" viewBox="0 0 ${_n(w)} ${_n(h)}">');
  if (v.clips.isNotEmpty) {
    b.writeln("<defs>");
    for (var (i, c) in v.clips.indexed) {
      var parent = c.parent >= 0 ? ' clip-path="url(#c${c.parent})"' : "";
      b.writeln('<clipPath id="c$i" clipPathUnits="userSpaceOnUse"$parent>'
          '<path d="${_svgPath(c.polys)}"/></clipPath>');
    }
    b.writeln("</defs>");
  }
  var open = -1;
  for (var op in v.ops) {
    if (op.clip != open) {
      if (open >= 0) b.writeln("</g>");
      if (op.clip >= 0) b.writeln('<g clip-path="url(#c${op.clip})">');
      open = op.clip;
    }
    switch (op) {
      case VShape s:
        var d = _svgPath(s.polys);
        if (d.isEmpty) continue;
        if (s.fill case var f?) {
          b.writeln('<path d="$d" fill="${_hex(f)}"'
              '${f.a * s.alpha < 1 ? ' fill-opacity="${_n(f.a * s.alpha)}"' : ""}'
              '${s.evenOdd ? ' fill-rule="evenodd"' : ""}/>');
        } else if (s.stroke case var k?) {
          b.writeln('<path d="$d" fill="none" stroke="${_hex(k)}" '
              'stroke-width="${_n(s.strokeWidth)}"'
              '${k.a * s.alpha < 1 ? ' stroke-opacity="${_n(k.a * s.alpha)}"' : ""}'
              ' stroke-linecap="${switch (s.cap) {
            StrokeCap.round => "round",
            StrokeCap.square => "square",
            _ => "butt"
          }}" stroke-linejoin="${switch (s.join) {
            StrokeJoin.round => "round",
            StrokeJoin.bevel => "bevel",
            _ => "miter"
          }}"/>');
        }
      case VText t:
        var m = t.matrix;
        var a = t.colour.a * t.alpha;
        b.writeln(
            '<text x="0" y="0" transform="matrix(${m.map(_n).join(" ")})" '
            'font-family="${_esc(t.family)}, sans-serif" '
            'font-size="${_n(t.size)}" font-weight="${t.weight}"'
            '${t.italic ? ' font-style="italic"' : ""}'
            ' fill="${_hex(t.colour)}"${a < 1 ? ' fill-opacity="${_n(a)}"' : ""}'
            '${t.letterSpacing != 0 ? ' letter-spacing="${_n(t.letterSpacing)}"' : ""}'
            ' textLength="${_n(t.width)}" lengthAdjust="spacingAndGlyphs"'
            ' xml:space="preserve">${_esc(t.text)}</text>');
      case VImage i:
        var png = base64Encode(await _png(i.image));
        b.writeln('<image x="${_n(i.rect.left)}" y="${_n(i.rect.top)}" '
            'width="${_n(i.rect.width)}" height="${_n(i.rect.height)}"'
            '${i.alpha < 1 ? ' opacity="${_n(i.alpha)}"' : ""}'
            ' preserveAspectRatio="none" '
            'href="data:image/png;base64,$png"/>');
    }
  }
  if (open >= 0) b.writeln("</g>");
  b.writeln("</svg>");
  return b.toString();
}

// ---------------------------------------------------------------- PDF

/// _helvetica is the standard face's printable ASCII widths, in
/// thousandths of its size, to stretch a line to its on-screen width.
const _helvetica = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, //
  278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, //
  584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, //
  500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, //
  667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, //
  278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, //
  278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
];

/// _winAnsi is a letter's code in PDF's standard encoding, or "?".
int _winAnsi(int code) {
  if (code >= 32 && code < 127) return code;
  if (code >= 0xA0 && code <= 0xFF) return code;
  return switch (code) {
    0x20AC => 0x80,
    0x2026 => 0x85,
    0x2018 => 0x91,
    0x2019 => 0x92,
    0x201C => 0x93,
    0x201D => 0x94,
    0x2022 => 0x95,
    0x2013 => 0x96,
    0x2014 => 0x97,
    0x2122 => 0x99,
    0x203A => 0x9B,
    0x2039 => 0x8B,
    0x2212 => 0x2D,
    _ => 0x3F,
  };
}

/// _face is the standard face standing in for [t]'s.
String _face(VText t) {
  var f = t.family.toLowerCase();
  var bold = t.weight >= 600;
  if (f.contains("mono") || f.contains("courier")) {
    return bold
        ? (t.italic ? "Courier-BoldOblique" : "Courier-Bold")
        : (t.italic ? "Courier-Oblique" : "Courier");
  }
  if (f.contains("serif") && !f.contains("sans") ||
      f.contains("georgia") ||
      f.contains("times") ||
      f.contains("garamond") ||
      f.contains("playfair") ||
      f.contains("merriweather")) {
    return bold
        ? (t.italic ? "Times-BoldItalic" : "Times-Bold")
        : (t.italic ? "Times-Italic" : "Times-Roman");
  }
  return bold
      ? (t.italic ? "Helvetica-BoldOblique" : "Helvetica-Bold")
      : (t.italic ? "Helvetica-Oblique" : "Helvetica");
}

String _pdfString(String s) {
  var b = StringBuffer("(");
  for (var r in s.runes) {
    var c = _winAnsi(r);
    if (c == 0x28 || c == 0x29 || c == 0x5C) {
      b.write("\\${String.fromCharCode(c)}");
    } else if (c >= 32 && c < 127) {
      b.writeCharCode(c);
    } else {
      b.write("\\${c.toRadixString(8).padLeft(3, "0")}");
    }
  }
  b.write(")");
  return b.toString();
}

double _naturalWidth(String s, double size) {
  var w = 0.0;
  for (var r in s.runes) {
    var c = _winAnsi(r);
    w += c >= 32 && c < 127 ? _helvetica[c - 32] : 556;
  }
  return w / 1000 * size;
}

String _rg(Color c) => "${_n(c.r)} ${_n(c.g)} ${_n(c.b)}";

/// vectorPdf is [v]'s drawing as a one-page PDF, a canvas pixel to three
/// quarters of a point (96 to the inch, as on screen).
Future<Uint8List> vectorPdf(VectorCanvas v) async {
  const k = 0.75;
  var w = v.size.width * k, h = v.size.height * k;
  var fonts = <String, int>{};
  var states = <String, int>{};
  var images = <VImage, int>{};
  String gs(double a) {
    var key = _n(a.clamp(0.0, 1.0));
    return "/G${states.putIfAbsent(key, () => states.length)} gs";
  }

  var c = StringBuffer()..writeln("${_n(k)} 0 0 ${_n(-k)} 0 ${_n(h)} cm");
  void path(List<VPoly> polys) {
    for (var p in polys) {
      if (p.points.isEmpty) continue;
      c.write("${_n(p.points.first.dx)} ${_n(p.points.first.dy)} m ");
      for (var q in p.points.skip(1)) {
        c.write("${_n(q.dx)} ${_n(q.dy)} l ");
      }
      if (p.closed) c.write("h ");
    }
  }

  List<int> chain(int id) {
    var out = <int>[];
    for (var i = id; i >= 0; i = v.clips[i].parent) {
      out.insert(0, i);
    }
    return out;
  }

  var open = -2;
  for (var op in v.ops) {
    if (op.clip != open) {
      if (open != -2) c.writeln("Q");
      c.writeln("q");
      for (var id in chain(op.clip)) {
        path(v.clips[id].polys);
        c.writeln("W n");
      }
      open = op.clip;
    }
    switch (op) {
      case VShape s:
        c.writeln("q");
        if (s.fill case var f?) {
          c.writeln("${gs(f.a * s.alpha)} ${_rg(f)} rg");
          path(s.polys);
          c.writeln(s.evenOdd ? "f*" : "f");
        } else if (s.stroke case var st?) {
          c.writeln(
              "${gs(st.a * s.alpha)} ${_rg(st)} RG ${_n(s.strokeWidth)} w "
              "${switch (s.cap) {
            StrokeCap.round => 1,
            StrokeCap.square => 2,
            _ => 0
          }} J ${switch (s.join) {
            StrokeJoin.round => 1,
            StrokeJoin.bevel => 2,
            _ => 0
          }} j");
          path(s.polys);
          c.writeln("S");
        }
        c.writeln("Q");
      case VText t:
        var face = _face(t);
        var f = fonts.putIfAbsent(face, () => fonts.length);
        var m = t.matrix;
        var natural = _naturalWidth(t.text, t.size);
        var stretch = natural <= 0 ? 100.0 : t.width / natural * 100;
        c.writeln("q ${gs(t.colour.a * t.alpha)} BT /F$f ${_n(t.size)} Tf "
            "${_n(stretch.clamp(20.0, 400.0))} Tz ${_rg(t.colour)} rg "
            "${_n(m[0])} ${_n(m[1])} ${_n(-m[2])} ${_n(-m[3])} ${_n(m[4])} ${_n(m[5])} Tm "
            "${_pdfString(t.text)} Tj ET Q");
      case VImage i:
        var id = images.putIfAbsent(i, () => images.length);
        var r = i.rect;
        // An image is drawn into the unit square, upside down here.
        c.writeln("q ${gs(i.alpha)} ${_n(r.width)} 0 0 ${_n(-r.height)} "
            "${_n(r.left)} ${_n(r.bottom)} cm /I$id Do Q");
    }
  }
  if (open != -2) c.writeln("Q");

  // The objects: catalogue, pages, page, content, then fonts, states and
  // pictures, each numbered in turn.
  var objects = <List<int>>[];
  int add(List<int> body) {
    objects.add(body);
    return objects.length;
  }

  List<int> ascii(String s) => latin1.encode(s);
  List<int> stream(String dict, List<int> data) => [
        ...ascii("$dict /Length ${data.length} >>\nstream\n"),
        ...data,
        ...ascii("\nendstream"),
      ];
  var deflate = ZLibCodec(level: 6);

  add(ascii("<< /Type /Catalog /Pages 2 0 R >>")); // 1
  add(ascii("<< /Type /Pages /Kids [3 0 R] /Count 1 >>")); // 2
  add(const []); // 3, the page, written once its resources are known
  add(stream(
      "<< /Filter /FlateDecode", deflate.encode(ascii(c.toString())))); // 4
  var fontRefs = <String, int>{};
  for (var MapEntry(key: face, value: i) in fonts.entries) {
    fontRefs["F$i"] = add(ascii("<< /Type /Font /Subtype /Type1 /BaseFont "
        "/$face /Encoding /WinAnsiEncoding >>"));
  }
  var stateRefs = <String, int>{};
  for (var MapEntry(key: a, value: i) in states.entries) {
    stateRefs["G$i"] = add(ascii("<< /Type /ExtGState /ca $a /CA $a >>"));
  }
  var imageRefs = <String, int>{};
  for (var MapEntry(key: img, value: i) in images.entries) {
    var data = (await img.image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    var iw = img.image.width, ih = img.image.height;
    var rgb = Uint8List(iw * ih * 3), alpha = Uint8List(iw * ih);
    for (var p = 0; p < iw * ih; p++) {
      var a = data[p * 4 + 3];
      alpha[p] = a;
      // Unpremultiplied, as PDF wants with a soft mask.
      for (var ch = 0; ch < 3; ch++) {
        var x = data[p * 4 + ch];
        rgb[p * 3 + ch] = a == 0 ? 0 : math.min(255, (x * 255 / a).round());
      }
    }
    var mask = add(stream(
        "<< /Type /XObject /Subtype /Image /Width $iw /Height $ih "
        "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode",
        deflate.encode(alpha)));
    imageRefs["I$i"] = add(stream(
        "<< /Type /XObject /Subtype /Image /Width $iw /Height $ih "
        "/ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask $mask 0 R "
        "/Filter /FlateDecode",
        deflate.encode(rgb)));
  }
  String dict(Map<String, int> refs) => "<< ${[
        for (var e in refs.entries) "/${e.key} ${e.value} 0 R"
      ].join(" ")} >>";
  objects[2] = ascii("<< /Type /Page /Parent 2 0 R "
      "/MediaBox [0 0 ${_n(w)} ${_n(h)}] /Contents 4 0 R "
      "/Resources << /Font ${dict(fontRefs)} /ExtGState ${dict(stateRefs)} "
      "/XObject ${dict(imageRefs)} >> >>");

  var out = BytesBuilder();
  out.add(ascii("%PDF-1.4\n%âãÏÓ\n"));
  var offsets = <int>[];
  for (var (i, body) in objects.indexed) {
    offsets.add(out.length);
    out.add(ascii("${i + 1} 0 obj\n"));
    out.add(body);
    out.add(ascii("\nendobj\n"));
  }
  var xref = out.length;
  out.add(ascii("xref\n0 ${objects.length + 1}\n0000000000 65535 f \n"));
  for (var o in offsets) {
    out.add(ascii("${o.toString().padLeft(10, "0")} 00000 n \n"));
  }
  out.add(ascii("trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n"
      "startxref\n$xref\n%%EOF\n"));
  return out.toBytes();
}
