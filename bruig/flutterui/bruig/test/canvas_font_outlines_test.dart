import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/font_outlines.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_font_outlines_test.dart is the font reader checked against Flutter's
// own drawing of the same letters from the same file: what it reads has to
// be what the font draws, letter by letter.

const size = 220.0;
const box = 320;

/// faces are the fonts checked -- one of each kind of outline -- and where
/// to find them; a system face that is not on this machine is skipped.
final faces = <(String, String, int)>[
  ("Inter (CFF)", "assets/fonts/Inter-Regular.otf", 0),
  ("Inter Bold (CFF)", "assets/fonts/Inter-Bold.otf", 0),
  ("RobotoMono (TrueType)", "assets/fonts/RobotoMono-VariableFont_wght.ttf", 0),
  ("PT Serif (TrueType)", "assets/fonts/PTSerif-Regular.ttf", 0),
  ("Arial", "/System/Library/Fonts/Supplemental/Arial.ttf", 0),
  ("Georgia", "/System/Library/Fonts/Supplemental/Georgia.ttf", 0),
  ("Helvetica (collection)", "/System/Library/Fonts/Helvetica.ttc", 0),
];

Future<Uint8List> pixels(void Function(Canvas) paint) async {
  var rec = ui.PictureRecorder();
  var canvas = Canvas(rec);
  paint(canvas);
  var img = await rec.endRecording().toImage(box, box);
  return (await img.toByteData())!.buffer.asUint8List();
}

/// overlap is how much of what either drew both drew, at the best of the
/// shifts of up to two pixels either way, and that shift: text is put on
/// the pixel grid as it is drawn, an outline is not.
(double, int, int) overlap(Uint8List a, Uint8List b) {
  var best = (0.0, 0, 0);
  for (var sy = -2; sy <= 2; sy++) {
    for (var sx = -2; sx <= 2; sx++) {
      var both = 0, either = 0;
      for (var y = 2; y < box - 2; y++) {
        for (var x = 2; x < box - 2; x++) {
          var p = a[(y * box + x) * 4 + 3] > 127;
          var q = b[((y + sy) * box + x + sx) * 4 + 3] > 127;
          if (p || q) either++;
          if (p && q) both++;
        }
      }
      var o = either == 0 ? 1.0 : both / either;
      if (o > best.$1) best = (o, sx, sy);
    }
  }
  return best;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var (name, path, index) in faces) {
    test("$name: every letter is the shape the font draws", () async {
      var file = File(path);
      if (!file.existsSync()) {
        markTestSkipped("$path is not on this machine");
        return;
      }
      var bytes = file.readAsBytesSync();
      var face = FontFace.parse(bytes, index: index);
      expect(face, isNotNull);
      var family = "check_${name.hashCode}";
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();

      var worst = 1.0;
      var worstChar = "";
      for (var ch in "AaBgQRS&%8@?jkwxyz".split("")) {
        var painter = TextPainter(
            text: TextSpan(
                text: ch,
                style: TextStyle(
                    fontFamily: family, fontSize: size, color: Colors.black)),
            textDirection: TextDirection.ltr)
          ..layout();
        var baseline =
            painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        var theirs =
            await pixels((c) => painter.paint(c, const Offset(20, 20)));

        var glyph = face!.glyphFor(ch.codeUnitAt(0));
        expect(glyph, isNot(0), reason: "$name has $ch");
        var k = size / face.unitsPerEm;
        var path = Path();
        for (var contour in face.outline(glyph)) {
          Offset at(Offset p) =>
              Offset(20 + p.dx * k, 20 + baseline - p.dy * k);
          var s = at(contour.start);
          path.moveTo(s.dx, s.dy);
          for (var seg in contour.segments) {
            var to = at(seg.to);
            if (seg.line) {
              path.lineTo(to.dx, to.dy);
            } else {
              var c1 = at(seg.c1), c2 = at(seg.c2);
              path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
            }
          }
          path.close();
        }
        var mine = await pixels(
            (c) => c.drawPath(path, Paint()..color = Colors.black));
        var (o, sx, sy) = overlap(theirs, mine);
        expect(sx.abs() <= 1 && sy.abs() <= 1, isTrue,
            reason: "$name $ch: within a pixel of where the font draws it");
        if (o < worst) {
          worst = o;
          worstChar = ch;
        }
        // The advance: where Flutter puts the next letter.
        expect(face.advance(glyph) * k, closeTo(painter.width, 1.5),
            reason: "$name $ch advance");
      }
      expect(worst, greaterThan(0.92), reason: "$name, worst at '$worstChar'");
    });
  }
}
