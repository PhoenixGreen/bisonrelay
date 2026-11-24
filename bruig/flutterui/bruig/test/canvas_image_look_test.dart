import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_look.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_image_look_test.dart is a picture's look as one colour matrix: its
// brightness and saturation first, as a photo is exposed, then the named
// look (Ken, 2026-11-24: a dark photo in noir came out near black, and
// brightness pushed all the way up only made it more contrasty).

/// _grey is what [m] makes of a mid-dark grey of [v] (0..255), clamped as
/// the screen clamps it.
double _grey(List<double>? m, double v) {
  if (m == null) return v;
  var out = m[0] * v + m[1] * v + m[2] * v + m[4];
  return out.clamp(0.0, 255.0);
}

void main() {
  const dark = 64.0;

  test("noir alone darkens a dark tone, as contrast about the middle does", () {
    expect(_grey(lookMatrix(ImageFilterPreset.noir, 1, 1), dark),
        lessThan(dark / 2));
  });

  test("brightness lifts a dark photo before noir is laid on it", () {
    var lifted = _grey(lookMatrix(ImageFilterPreset.noir, 1, 2), dark);
    expect(lifted, greaterThan(dark), reason: "brighter than it was, in noir");
    // The other way round -- the look, then brightness -- it could not be:
    // the brightness multiplied noir's dark offset as well.
    var after = _grey(
        combineMatrices(
            presetMatrix(ImageFilterPreset.noir), colorMatrix(1, 2)),
        dark);
    expect(after, lessThan(dark));
  });

  test("with no filter, or no sliders, nothing else changes", () {
    expect(lookMatrix(ImageFilterPreset.none, 1, 1), isNull);
    expect(lookMatrix(ImageFilterPreset.noir, 1, 1),
        presetMatrix(ImageFilterPreset.noir));
    expect(lookMatrix(ImageFilterPreset.none, 1.2, 0.8), colorMatrix(1.2, 0.8));
  });
}
