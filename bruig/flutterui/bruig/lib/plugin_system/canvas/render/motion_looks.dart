import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:flutter/painting.dart';

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
      MotionDeviceKind.blur => d.value("amount") * 2,
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
void paintWithLooks(ui.Canvas canvas, Rect bounds, List<MotionDevice> looks,
    void Function() paint,
    {double turn = 0, double scale = 1}) {
  var reach = looksReach(looks);
  var room = bounds.inflate(reach / math.max(0.05, scale) + 2);
  var k = 1 / math.max(0.05, scale);
  void drawn(int i) {
    if (i < 0) {
      paint();
      return;
    }
    _look(canvas, room, looks[i], () => drawn(i - 1), turn, k);
  }

  drawn(looks.length - 1);
}

/// _look draws [under] -- everything to its left -- with look [d] on it.
/// [k] turns the page's pixels into the canvas's, as it is sized.
void _look(ui.Canvas canvas, Rect room, MotionDevice d, void Function() under,
    double turn, double k) {
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
      if (amount <= 0) return under();
      canvas.saveLayer(room, Paint()..imageFilter = blurOf(amount));
      under();
      canvas.restore();
    case MotionDeviceKind.shadow:
      // Cast where the light puts it, whichever way the element turns.
      var angle = (d.value("angle") - 90 - turn) * math.pi / 180;
      var away = d.value("distance") * k;
      var colour = colourOr(const Color(0xFF000000));
      canvas.save();
      canvas.translate(math.cos(angle) * away, math.sin(angle) * away);
      canvas.saveLayer(
          room.inflate(away),
          Paint()
            ..imageFilter = blurOf(d.value("blur"))
            ..colorFilter = ColorFilter.mode(
                colour.withValues(alpha: colour.a * d.value("strength")),
                BlendMode.srcIn));
      under();
      canvas.restore();
      canvas.restore();
      under();
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
      canvas.saveLayer(room, glow);
      under();
      canvas.restore();
      under();
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
      under();
      canvas.restore();
      under();
    case MotionDeviceKind.time:
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
