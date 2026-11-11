import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/edge_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/edge_mask_painter.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
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
      // Its rim and handle, where the glass goes near the edge.
      MotionDeviceKind.lens => 160.0,
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
    {double turn = 0,
    double scale = 1,
    Offset velocity = Offset.zero,
    double time = 0,
    double presence = 1}) {
  var reach = looksReach(looks);
  var room = bounds.inflate(reach / math.max(0.05, scale) + 2);
  var k = 1 / math.max(0.05, scale);
  void drawn(ui.Canvas on, int i) {
    if (i < 0) {
      paint(on);
      return;
    }
    _look(on, room, bounds, looks[i], (c) => drawn(c, i - 1), turn, k, velocity,
        time, presence);
  }

  drawn(canvas, looks.length - 1);
}

/// _look draws [under] -- everything to its left -- with look [d] on it.
/// [k] turns the page's pixels into the canvas's, as it is sized.
void _look(
    ui.Canvas canvas,
    Rect room,
    Rect bounds,
    MotionDevice d,
    void Function(ui.Canvas on) draw,
    double turn,
    double k,
    Offset velocity,
    double time,
    double presence) {
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
    case MotionDeviceKind.wear:
      if (d.value("amount") <= 0) return under();
      canvas.saveLayer(room, Paint());
      under();
      paintTexture(canvas, room, wearTexture(d), blendMode: BlendMode.dstOut);
      canvas.restore();
    case MotionDeviceKind.edges:
      paintEdgeMasked(
          canvas,
          bounds,
          EdgeMask(
              feather: d.value("feather"),
              fade: EdgeFade.values[
                  d.value("fade").round().clamp(0, EdgeFade.values.length - 1)],
              reach: d.value("reach")),
          under);
    case MotionDeviceKind.lens:
      // A glass is something of its own, drawn whatever is under it: only
      // as much of it as the element is there -- not before it arrives,
      // nor after it has gone (a table leaves by itself, hiding its cells
      // and leaving its glass behind).
      if (presence <= 0.002) return under();
      var picture = recorded();
      lay(picture);
      var at = lensAt(d, bounds, time);
      var r = lensRadius(d, bounds);
      var glass = Rect.fromCircle(center: at, radius: r);
      // What is under the glass, bigger about the glass's middle.
      canvas.save();
      canvas.clipPath(Path()..addOval(glass));
      canvas.translate(at.dx, at.dy);
      canvas.scale(math.max(1.0, d.value("zoom")));
      canvas.translate(-at.dx, -at.dy);
      canvas.saveLayer(room,
          Paint()..color = Color.fromRGBO(255, 255, 255, presence.clamp(0, 1)));
      lay(picture);
      canvas.restore();
      canvas.restore();
      picture.dispose();
      canvas.saveLayer(room.inflate(r * 2),
          Paint()..color = Color.fromRGBO(255, 255, 255, presence.clamp(0, 1)));
      _paintGlass(canvas, at, r);
      canvas.restore();
    default:
      // A pose device: nothing to how it looks.
      under();
  }
}

/// lensRadius is a Lens's glass's radius, in its element's box [bounds].
double lensRadius(MotionDevice d, Rect bounds) =>
    math.max(4.0, d.value("size") * bounds.shortestSide / 2);

/// lensAt is where a Lens's glass is centred at [time] seconds: round its
/// middle (Across, Down), Goes round of the way to the box's edge, so many
/// Laps a second -- clockwise, from the right.
Offset lensAt(MotionDevice d, Rect bounds, double time) {
  var middle = Offset(bounds.left + bounds.width * d.value("x"),
      bounds.top + bounds.height * d.value("y"));
  var a = 2 * math.pi * d.value("laps") * time;
  var orbit = d.value("orbit");
  return middle +
      Offset(math.cos(a) * orbit * bounds.width / 2,
          math.sin(a) * orbit * bounds.height / 2);
}

/// _paintGlass draws a magnifying glass's rim, sheen and handle round the
/// glass at [at], [r] across.
void _paintGlass(ui.Canvas canvas, Offset at, double r) {
  var rim = r * 0.11;
  // The handle first, under the rim: out to the lower right.
  var way = Offset(math.cos(math.pi / 4), math.sin(math.pi / 4));
  var from = at + way * (r + rim * 0.4);
  var to = at + way * (r * 2.0);
  canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeWidth = rim * 2.4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF1B1E23));
  canvas.drawLine(
      from - Offset(rim * 0.4, rim * 0.4),
      to - Offset(rim * 0.4, rim * 0.4),
      Paint()
        ..strokeWidth = rim * 0.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x33FFFFFF));
  // A shadow round the glass, as it stands off the page.
  canvas.drawCircle(
      at + Offset(rim, rim),
      r + rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim * 1.5
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rim));
  // The rim: dark metal, lit along its top.
  canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim
        ..shader = ui.Gradient.linear(
            at - Offset(0, r),
            at + Offset(0, r),
            const [Color(0xFFD4D8DE), Color(0xFF6B717A), Color(0xFF2A2E34)],
            const [0, 0.45, 1]));
  // The sheen on the glass, upper left.
  canvas.drawCircle(
      at,
      r - rim / 2,
      Paint()
        ..shader = ui.Gradient.radial(at + Offset(-r * 0.35, -r * 0.4), r * 0.9,
            const [Color(0x33FFFFFF), Color(0x00FFFFFF)], const [0, 1]));
}

/// wearTexture is what a Wear device takes out of its element: one of the
/// pictures' textures, drawn as marks on nothing (see texture.frag), and
/// as heavy and as coarse as its Amount and Size.
TextureSpec wearTexture(MotionDevice d) {
  var amount = d.value("amount"), size = d.value("size");
  var seed = d.value("seed").round();
  return switch (d.value("texture").round()) {
    1 => TextureSpec(kind: TextureKind.dust, seed: seed, values: {
        "specks": amount,
        "scratches": amount * 0.7,
        "size": 2 * size,
      }),
    2 => TextureSpec(kind: TextureKind.halftone, seed: seed, values: {
        "cell": 8 * size,
        "angle": 45,
        "dot": amount,
      }),
    _ => TextureSpec(kind: TextureKind.grunge, seed: seed, values: {
        "scale": 120 * size,
        "cover": amount,
        "roughness": 0.65,
      }),
  };
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
