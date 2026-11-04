import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';

// image_look.dart is what a picture is made to look like: a named filter and
// the two sliders, as colour matrices.
//
// Shared by picture elements, pictures in letters, and pictures behind boxes
// or inside shapes.

/// presetMatrix is a named look as a colour matrix, or null for none.
/// Matrices compose into one colour filter, where layered draws would each
/// need an off-screen layer.
List<double>? presetMatrix(ImageFilterPreset filter) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  switch (filter) {
    case ImageFilterPreset.none:
      return null;
    case ImageFilterPreset.greyscale:
      return [
        lr, lg, lb, 0, 0, //
        lr, lg, lb, 0, 0, //
        lr, lg, lb, 0, 0, //
        0, 0, 0, 1, 0,
      ];
    case ImageFilterPreset.sepia:
      return [
        0.393, 0.769, 0.189, 0, 0, //
        0.349, 0.686, 0.168, 0, 0, //
        0.272, 0.534, 0.131, 0, 0, //
        0, 0, 0, 1, 0,
      ];
    case ImageFilterPreset.noir:
      // Grey, then contrast about the midpoint: a scale plus an offset.
      const c = 1.7;
      const o = (1 - c) * 0.5 * 255;
      return [
        lr * c, lg * c, lb * c, 0, o, //
        lr * c, lg * c, lb * c, 0, o, //
        lr * c, lg * c, lb * c, 0, o, //
        0, 0, 0, 1, 0,
      ];
    case ImageFilterPreset.invert:
      return [
        -1, 0, 0, 0, 255, //
        0, -1, 0, 0, 255, //
        0, 0, -1, 0, 255, //
        0, 0, 0, 1, 0,
      ];
    case ImageFilterPreset.cool:
      return [
        0.9, 0, 0, 0, 0, //
        0, 0.98, 0, 0, 0, //
        0, 0, 1.15, 0, 8, //
        0, 0, 0, 1, 0,
      ];
    case ImageFilterPreset.warm:
      return [
        1.15, 0, 0, 0, 8, //
        0, 1.0, 0, 0, 0, //
        0, 0, 0.88, 0, 0, //
        0, 0, 0, 1, 0,
      ];
    case ImageFilterPreset.faded:
      // Lifted blacks and pulled-in whites.
      const g = 0.72;
      const lift = 38.0;
      return [
        g, 0, 0, 0, lift, //
        0, g, 0, 0, lift, //
        0, 0, g, 0, lift, //
        0, 0, 0, 1, 0,
      ];
  }
}

/// combineMatrices multiplies two 4x5 colour matrices, [a] applied first.
///
/// Null means no change, in and out, so an untouched picture gets no colour
/// filter at all rather than an identity one.
List<double>? combineMatrices(List<double>? a, List<double>? b) {
  if (a == null) return b;
  if (b == null) return a;
  var out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += b[row * 5 + k] * a[k * 5 + col];
      }
      // The fifth column is a constant, so b's own offset carries through.
      if (col == 4) sum += b[row * 5 + 4];
      out[row * 5 + col] = sum;
    }
  }
  return out;
}

/// colorMatrix is saturation and brightness as one 4x5 filter, or null when
/// both are 1. It uses perceptual luminance weights, not equal thirds.
List<double>? colorMatrix(double sat, double bri) {
  if (sat == 1 && bri == 1) return null;
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  var s = sat.clamp(0.0, 4.0);
  var b = bri.clamp(0.0, 4.0);
  return [
    (lr + (1 - lr) * s) * b,
    (lg - lg * s) * b,
    (lb - lb * s) * b,
    0,
    0,
    (lr - lr * s) * b,
    (lg + (1 - lg) * s) * b,
    (lb - lb * s) * b,
    0,
    0,
    (lr - lr * s) * b,
    (lg - lg * s) * b,
    (lb + (1 - lb) * s) * b,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}
