import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// area_sides.dart holds SideValues, the "split into four" form of each of an
// area's spacing settings. See AreaStyle for the fields themselves.

// SideValues is one spacing setting given a separate value per side (border
// width, padding, margin) or per corner (border radius), for when the user
// splits that setting's single slider into four. On AreaStyle each of these
// is nullable, and null -- not "four equal values" -- is what means "not
// split": the single slider's own value then applies all round, so
// collapsing the four back into one is lossless and the saved preset stays
// as small as it was before this feature existed.
@immutable
class SideValues {
  // Exactly four values, in the order the editor lays them out: left, top,
  // right, bottom for a setting measured along the edges (border width,
  // padding, margin), or clockwise from the top-left for border radius's
  // corners. Which of the two a given field means is fixed per setting, so
  // both namings below read off the same slots.
  final List<double> values;

  const SideValues(this.values) : assert(values.length == 4);
  SideValues.all(double v) : values = [v, v, v, v];

  double get left => values[0];
  double get top => values[1];
  double get right => values[2];
  double get bottom => values[3];

  double get topLeft => values[0];
  double get topRight => values[1];
  double get bottomRight => values[2];
  double get bottomLeft => values[3];

  double operator [](int i) => values[i];

  // isUniform matters for borders specifically: Flutter can only paint a
  // Border together with a borderRadius when every side matches (Border
  // .paint throws otherwise), so a non-uniform border has to be drawn a
  // different way -- see AreaStyle.buildContainer.
  bool get isUniform => values.every((v) => v == values[0]);
  bool get isZero => values.every((v) => v <= 0);
  double get largest => values.reduce(math.max);

  EdgeInsets get insets =>
      EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);

  BorderRadius get radius => BorderRadius.only(
        topLeft: Radius.circular(topLeft),
        topRight: Radius.circular(topRight),
        bottomRight: Radius.circular(bottomRight),
        bottomLeft: Radius.circular(bottomLeft),
      );

  SideValues withValue(int i, double v) =>
      SideValues([...values]..[i] = math.max(0, v));

  List<double> toJson() => values;

  // fromJson tolerates anything that isn't a 4-number list by returning
  // null ("not split"), so a hand-edited or older preset file can't leave
  // an area with a half-built override.
  static SideValues? fromJson(dynamic j) {
    if (j is! List || j.length != 4) return null;
    if (j.any((v) => v is! num)) return null;
    return SideValues(j.map((v) => (v as num).toDouble()).toList());
  }

  @override
  bool operator ==(Object other) =>
      other is SideValues && listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);
}

// sideLabels/cornerLabels name the four slots for the editor, in slot order.
const List<String> sideLabels = ["Left", "Top", "Right", "Bottom"];
const List<String> cornerLabels = [
  "Top left",
  "Top right",
  "Bottom right",
  "Bottom left"
];
