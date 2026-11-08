import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

// motion_looks.dart draws an element's looks: the devices right of its
// drawing in its Chain's Motion view (glow, shadow, blur, colour, outline).
// Each takes what is to its left -- the element drawn, with the looks before
// it -- and changes how it looks, so the order they are in is the order they
// are laid on: a shadow after a glow casts the glow's shadow too.

/// looksReach is how far, in the page's pixels, [looks] can reach outside
/// the element's box: for the layer they are drawn in, and an export's
/// picture of the element, to hold them.
double looksReach(List<MotionDevice> looks) {
  var reach = 0.0;
  for (var d in looks) {
    reach += switch (d.kind) {
      MotionDeviceKind.glow => d.value("radius") * 2,
      MotionDeviceKind.shadow => d.value("distance") + d.value("blur") * 2,
      MotionDeviceKind.blur => d.value("amount") * 2 + d.value("motion") * 40,
      MotionDeviceKind.outline => d.value("width") * (1 + d.value("softness")),
      _ => 0.0,
    };
  }
  return reach;
}

/// paintWithLooks draws [paint] -- the element, in its own box [bounds] on
/// a canvas already moved, turned and sized as it is -- with [looks] on it,
/// in order. [turn] (degrees) and [scale] are how it is turned and sized,
/// so that a shadow falls the same way, and as far, however it turns.
///
/// [velocity] is how fast it moves, in the page's pixels a second: what a
/// Blur's Motion blur smears it along.
void paintWithLooks(ui.Canvas canvas, Rect bounds, List<MotionDevice> looks,
    void Function(ui.Canvas on) paint,
    {double turn = 0, double scale = 1, Offset velocity = Offset.zero}) {
  var reach = looksReach(looks);
  var room = bounds.inflate(reach / math.max(0.05, scale) + 2);
  var k = 1 / math.max(0.05, scale);
  void drawn(ui.Canvas on, int i) {
    if (i < 0) {
      paint(on);
      return;
    }
    _look(on, room, looks[i], (c) => drawn(c, i - 1), turn, k, velocity);
  }

  drawn(canvas, looks.length - 1);
}

/// _look draws [under] -- everything to its left -- with look [d] on it.
/// [k] turns the page's pixels into the canvas's, as it is sized.
void _look(ui.Canvas canvas, Rect room, MotionDevice d,
    void Function(ui.Canvas on) draw, double turn, double k, Offset velocity) {
  void under() => draw(canvas);
  // What is under it, recorded once for a look that lays it twice -- a
  // shadow, a glow, an outline, then the element over it -- so three of
  // them draw the element once each, not eight times (Ken's systems
  // review, 2026-11-08).
  //
  // Recorded in the canvas's own transform, so what is drawn at the size it
  // is seen (a 3D model, a raster) is as sharp; laid back through the
  // inverse of it.
  var seen = canvas.getTransform();
  ui.Picture recorded() {
    var rec = ui.PictureRecorder();
    draw(ui.Canvas(rec)..transform(seen));
    return rec.endRecording();
  }

  // A copy: fromFloat64List wraps the list it is given, and inverting it
  // would turn [seen] round too.
  var back = Matrix4.fromFloat64List(seen.sublist(0))..invert();
  void lay(ui.Picture picture) {
    canvas.save();
    canvas.transform(back.storage);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  Color colourOr(Color fallback) =>
      d.colour == null ? fallback : Color(d.colour!);
  ui.ImageFilter blurOf(double px) => ui.ImageFilter.blur(
      sigmaX: math.max(0.01, px * k / 2),
      sigmaY: math.max(0.01, px * k / 2),
      tileMode: TileMode.decal);
  switch (d.kind) {
    case MotionDeviceKind.colour:
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter = ColorFilter.matrix(colourMatrix(
                d.value("hue"), d.value("saturation"), d.value("brightness"))));
      under();
      canvas.restore();
    case MotionDeviceKind.blur:
      var amount = d.value("amount");
      // Motion blur: a fiftieth of a second's travel, along it -- turned
      // into the element's own way round, as the canvas is.
      var smear = d.value("motion");
      var a = -turn * math.pi / 180;
      var along = Offset(velocity.dx * math.cos(a) - velocity.dy * math.sin(a),
              velocity.dx * math.sin(a) + velocity.dy * math.cos(a)) *
          (smear / 50);
      var sx = amount + along.dx.abs(), sy = amount + along.dy.abs();
      if (sx <= 0.01 && sy <= 0.01) return under();
      canvas.saveLayer(
          room.inflate(math.max(along.dx.abs(), along.dy.abs()) * k),
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: math.max(0.01, sx * k / 2),
                sigmaY: math.max(0.01, sy * k / 2),
                tileMode: TileMode.decal));
      under();
      canvas.restore();
    case MotionDeviceKind.shadow:
      // Cast where the light puts it, whichever way the element turns --
      // or, Turns with it, as if the light were fixed to the element.
      var turnsWith = d.value("turns").round() == 1;
      var angle =
          (d.value("angle") - 90 - (turnsWith ? 0 : turn)) * math.pi / 180;
      var away = d.value("distance") * k;
      var colour = colourOr(const Color(0xFF000000));
      var picture = recorded();
      canvas.save();
      canvas.translate(math.cos(angle) * away, math.sin(angle) * away);
      canvas.saveLayer(
          room.inflate(away),
          Paint()
            ..imageFilter = blurOf(d.value("blur"))
            ..colorFilter = ColorFilter.mode(
                colour.withValues(alpha: colour.a * d.value("strength")),
                BlendMode.srcIn));
      lay(picture);
      canvas.restore();
      canvas.restore();
      lay(picture);
      picture.dispose();
    case MotionDeviceKind.glow:
      // Its own colours, spread and laid under it, unless given one.
      var strength = d.value("strength");
      var glow = Paint()..imageFilter = blurOf(d.value("radius"));
      if (d.colour != null) {
        var c = Color(d.colour!);
        glow.colorFilter = ColorFilter.mode(
            c.withValues(alpha: c.a * strength), BlendMode.srcIn);
      } else {
        glow.color = Color.fromRGBO(255, 255, 255, strength);
      }
      var picture = recorded();
      canvas.saveLayer(room, glow);
      lay(picture);
      canvas.restore();
      lay(picture);
      picture.dispose();
    case MotionDeviceKind.outline:
      var width = d.value("width");
      if (width <= 0) return under();
      var soft = d.value("softness");
      var spread =
          ui.ImageFilter.dilate(radiusX: width * k, radiusY: width * k);
      canvas.saveLayer(
          room,
          Paint()
            ..imageFilter = soft <= 0
                ? spread
                : ui.ImageFilter.compose(
                    outer: blurOf(width * soft), inner: spread)
            ..colorFilter = ColorFilter.mode(
                colourOr(const Color(0xFF000000)), BlendMode.srcIn));
      var picture = recorded();
      lay(picture);
      canvas.restore();
      lay(picture);
      picture.dispose();
    default:
      // A pose device: nothing to how it looks.
      under();
  }
}

/// colourMatrix is a colour matrix turning hue by [hue] degrees, scaling
/// saturation by [saturation] and adding [brightness] (-1 to 1).
List<double> colourMatrix(double hue, double saturation, double brightness) {
  // Luminance weights (Rec. 709).
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  var a = hue * math.pi / 180, c = math.cos(a), s = math.sin(a);
  // The hue turn about the grey axis.
  var h = [
    lr + c * (1 - lr) + s * (-lr), lg + c * (-lg) + s * (-lg),
    lb + c * (-lb) + s * (1 - lb), //
    lr + c * (-lr) + s * 0.143, lg + c * (1 - lg) + s * 0.140,
    lb + c * (-lb) + s * (-0.283), //
    lr + c * (-lr) + s * (-(1 - lr)), lg + c * (-lg) + s * lg,
    lb + c * (1 - lb) + s * lb,
  ];
  // Then saturation: towards grey, or away.
  var t = saturation;
  var sat = [
    lr * (1 - t) + t, lg * (1 - t), lb * (1 - t), //
    lr * (1 - t), lg * (1 - t) + t, lb * (1 - t), //
    lr * (1 - t), lg * (1 - t), lb * (1 - t) + t,
  ];
  var m = List<double>.filled(9, 0);
  for (var r = 0; r < 3; r++) {
    for (var col = 0; col < 3; col++) {
      var v = 0.0;
      for (var i = 0; i < 3; i++) {
        v += sat[r * 3 + i] * h[i * 3 + col];
      }
      m[r * 3 + col] = v;
    }
  }
  var add = brightness * 255;
  return [
    m[0], m[1], m[2], 0, add, //
    m[3], m[4], m[5], 0, add, //
    m[6], m[7], m[8], 0, add, //
    0, 0, 0, 1, 0,
  ];
}
