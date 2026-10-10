import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// procedural_effects.dart is what is done to a generated background after
// the pattern is drawn: grain, a glow, softening, scanlines, where the eye is
// drawn to, where the pattern keeps out of the way, and a colour grade.
//
// Every style has them and none of them knows about them, the way the light
// works -- which is what lifts all of the styles at once instead of one at a
// time, and what means a new style gets them for nothing.

/// ClearArea is where a background keeps its pattern out of the way, so that
/// what is put on top of it can be read.
enum ClearArea {
  none("None"),
  centre("Middle"),
  left("Left"),
  right("Right"),
  top("Top"),
  bottom("Bottom"),
  band("Across"),
  column("Down");

  final String label;
  const ClearArea(this.label);

  static ClearArea fromName(String? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => ClearArea.none);
}

/// EffectsSpec is the finishing done to a background's pattern.
///
/// All of it off by default -- nought, or none -- so that a document saved
/// before there were effects is the same picture after.
class EffectsSpec {
  /// opacity is how strongly the pattern is laid over the base colour.
  final double opacity;

  /// grain is film grain over the whole frame, and grainSize how coarse it
  /// is, in thousandths of the shorter side.
  final double grain;
  final double grainSize;

  /// grainMoves is whether the grain changes from frame to frame, as film
  /// grain does, where the background moves.
  final bool grainMoves;

  /// glow is a bloom round the bright parts of the pattern, and glowSize
  /// how far it spreads.
  final double glow;
  final double glowSize;

  /// blur softens the pattern, as if it were behind the lens's focus.
  final double blur;

  /// scanlines are the horizontal lines of a screen, and scanlineSize how far
  /// apart they are, in thousandths of the shorter side.
  final double scanlines;
  final double scanlineSize;

  /// focus is how far the pattern fades away from one point, at
  /// [focusX], [focusY] as fractions of the frame; [focusSize] is how far from
  /// it the pattern stays at full strength, as a fraction of the longer side.
  final double focus;
  final double focusX;
  final double focusY;
  final double focusSize;

  /// clear is where the pattern keeps away from: [clearSize] is how much of
  /// the frame that is, [clearSoftness] how gradually the pattern comes back
  /// at its edge, and [clearAmount] how completely it goes.
  final ClearArea clear;
  final double clearSize;
  final double clearSoftness;
  final double clearAmount;

  /// hue, saturation, contrast and brightness grade the finished frame,
  /// base and all. Hue is in degrees round the wheel; the other three run
  /// from minus one to one, nought leaving it as it is.
  final double hue;
  final double saturation;
  final double contrast;
  final double brightness;

  const EffectsSpec({
    this.opacity = 1,
    this.grain = 0,
    this.grainSize = 1.5,
    this.grainMoves = true,
    this.glow = 0,
    this.glowSize = 0.4,
    this.blur = 0,
    this.scanlines = 0,
    this.scanlineSize = 4,
    this.focus = 0,
    this.focusX = 0.5,
    this.focusY = 0.5,
    this.focusSize = 0.3,
    this.clear = ClearArea.none,
    this.clearSize = 0.4,
    this.clearSoftness = 0.5,
    this.clearAmount = 1,
    this.hue = 0,
    this.saturation = 0,
    this.contrast = 0,
    this.brightness = 0,
  });

  /// masks is whether anything decides where the pattern shows.
  bool get masks => focus > 0 || (clear != ClearArea.none && clearAmount > 0);

  /// grades is whether the colour of the finished frame is changed.
  bool get grades =>
      hue != 0 || saturation != 0 || contrast != 0 || brightness != 0;

  /// any is whether any of it is on, which is whether it is worth saving.
  bool get any =>
      opacity < 1 ||
      grain > 0 ||
      glow > 0 ||
      blur > 0 ||
      scanlines > 0 ||
      masks ||
      grades;

  EffectsSpec copyWith({
    double? opacity,
    double? grain,
    double? grainSize,
    bool? grainMoves,
    double? glow,
    double? glowSize,
    double? blur,
    double? scanlines,
    double? scanlineSize,
    double? focus,
    double? focusX,
    double? focusY,
    double? focusSize,
    ClearArea? clear,
    double? clearSize,
    double? clearSoftness,
    double? clearAmount,
    double? hue,
    double? saturation,
    double? contrast,
    double? brightness,
  }) =>
      EffectsSpec(
        opacity: opacity ?? this.opacity,
        grain: grain ?? this.grain,
        grainSize: grainSize ?? this.grainSize,
        grainMoves: grainMoves ?? this.grainMoves,
        glow: glow ?? this.glow,
        glowSize: glowSize ?? this.glowSize,
        blur: blur ?? this.blur,
        scanlines: scanlines ?? this.scanlines,
        scanlineSize: scanlineSize ?? this.scanlineSize,
        focus: focus ?? this.focus,
        focusX: focusX ?? this.focusX,
        focusY: focusY ?? this.focusY,
        focusSize: focusSize ?? this.focusSize,
        clear: clear ?? this.clear,
        clearSize: clearSize ?? this.clearSize,
        clearSoftness: clearSoftness ?? this.clearSoftness,
        clearAmount: clearAmount ?? this.clearAmount,
        hue: hue ?? this.hue,
        saturation: saturation ?? this.saturation,
        contrast: contrast ?? this.contrast,
        brightness: brightness ?? this.brightness,
      );

  /// toJson writes only what differs from the default: a background with one
  /// effect on is one number in the document, not twenty.
  Map<String, dynamic> toJson() {
    const d = EffectsSpec();
    return {
      if (opacity != d.opacity) "opacity": opacity,
      if (grain != d.grain) "grain": grain,
      if (grainSize != d.grainSize) "grainSize": grainSize,
      if (grainMoves != d.grainMoves) "grainMoves": grainMoves,
      if (glow != d.glow) "glow": glow,
      if (glowSize != d.glowSize) "glowSize": glowSize,
      if (blur != d.blur) "blur": blur,
      if (scanlines != d.scanlines) "scanlines": scanlines,
      if (scanlineSize != d.scanlineSize) "scanlineSize": scanlineSize,
      if (focus != d.focus) "focus": focus,
      if (focusX != d.focusX) "focusX": focusX,
      if (focusY != d.focusY) "focusY": focusY,
      if (focusSize != d.focusSize) "focusSize": focusSize,
      if (clear != d.clear) "clear": clear.name,
      if (clearSize != d.clearSize) "clearSize": clearSize,
      if (clearSoftness != d.clearSoftness) "clearSoftness": clearSoftness,
      if (clearAmount != d.clearAmount) "clearAmount": clearAmount,
      if (hue != d.hue) "hue": hue,
      if (saturation != d.saturation) "saturation": saturation,
      if (contrast != d.contrast) "contrast": contrast,
      if (brightness != d.brightness) "brightness": brightness,
    };
  }

  factory EffectsSpec.fromJson(Map<String, dynamic> json) => EffectsSpec(
        opacity: jsonDouble(json["opacity"], 1).clamp(0.0, 1.0),
        grain: jsonDouble(json["grain"], 0).clamp(0.0, 1.0),
        grainSize: jsonDouble(json["grainSize"], 1.5).clamp(0.3, 12.0),
        grainMoves: jsonBool(json["grainMoves"], true),
        glow: jsonDouble(json["glow"], 0).clamp(0.0, 2.0),
        glowSize: jsonDouble(json["glowSize"], 0.4).clamp(0.0, 1.0),
        blur: jsonDouble(json["blur"], 0).clamp(0.0, 1.0),
        scanlines: jsonDouble(json["scanlines"], 0).clamp(0.0, 1.0),
        scanlineSize: jsonDouble(json["scanlineSize"], 4).clamp(1.0, 40.0),
        focus: jsonDouble(json["focus"], 0).clamp(0.0, 1.0),
        focusX: jsonDouble(json["focusX"], 0.5),
        focusY: jsonDouble(json["focusY"], 0.5),
        focusSize: jsonDouble(json["focusSize"], 0.3).clamp(0.0, 2.0),
        clear: ClearArea.fromName(json["clear"] as String?),
        clearSize: jsonDouble(json["clearSize"], 0.4).clamp(0.0, 1.0),
        clearSoftness: jsonDouble(json["clearSoftness"], 0.5).clamp(0.0, 1.0),
        clearAmount: jsonDouble(json["clearAmount"], 1).clamp(0.0, 1.0),
        hue: jsonDouble(json["hue"], 0).clamp(-180.0, 180.0),
        saturation: jsonDouble(json["saturation"], 0).clamp(-1.0, 1.0),
        contrast: jsonDouble(json["contrast"], 0).clamp(-1.0, 1.0),
        brightness: jsonDouble(json["brightness"], 0).clamp(-1.0, 1.0),
      );
}
