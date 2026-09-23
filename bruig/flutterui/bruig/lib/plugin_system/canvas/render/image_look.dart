import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';

// image_look.dart is what a picture is made to look like: a named filter and
// the two sliders, as colour matrices.
//
// Its own file because three things ask for it now -- a picture element, a
// picture showing through the letters, and a picture behind a box or inside a
// shape -- and a second copy of a sepia matrix is a second sepia.

/// colorMatrix is saturation and brightness as one 4x5 filter.
///
/// The luminance weights are the usual perceptual ones -- desaturating with
/// equal thirds turns a red shirt and a blue shirt into the same grey, which
/// on a tactics diagram is the whole point of the two colours gone.
/// presetMatrix is a named look as a colour matrix, or null for none.
///
/// Matrices rather than layered draws: one 4x5 matrix is one uniform in the
/// shader, where each extra effect drawn on top of the last is another
/// off-screen layer, and a canvas may hold a dozen pictures.
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
      // Grey, then pushed hard about the midpoint: contrast is a gain either
      // side of 0.5, which as a matrix is a scale and an offset that undoes
      // half of it.
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
      // Lifted blacks and pulled-in whites, which is what a faded print is.
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
/// Null in means "no change", and null out means neither did anything -- so a
/// picture with no filter and no sliders touched gets no colour filter at all
/// rather than an identity one, which is a shader either way but only one of
/// them is free.
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
