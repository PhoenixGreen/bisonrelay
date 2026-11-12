import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe;
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';

// design_device.dart is the Chain's Design device (Ken, 2026-11-12): the
// element's own settings, animated in its arrival, leaving and loop or
// independently. The settings panel sets how each rests; Design keys them.
//
// Two kinds of setting:
//  - its place -- Across, Down, Turn, Size, Opacity, Skew -- kept on the
//    device, as a move from where it rests: nought (one for Size and
//    Opacity) leaves it be. Joined to the pose after the pose devices.
//  - the element's own -- a text's font size, colour, box -- as the panel
//    has them: they rest at the panel's value and are only changed where
//    keyed. See designed.

/// designParams are every setting Design can animate, of any element.
/// Which an element offers is designChoices.
const designParams = [
  DeviceParam("x", "Across", -4000, 4000, 0, "px"),
  DeviceParam("y", "Down", -4000, 4000, 0, "px"),
  DeviceParam("turn", "Turn", -1440, 1440, 0, "°"),
  DeviceParam("size", "Size", 0, 2, 1),
  DeviceParam("opacity", "Opacity", 0, 1, 1),
  DeviceParam("skewX", "Skew X", -60, 60, 0, "°"),
  DeviceParam("skewY", "Skew Y", -60, 60, 0, "°"),
  DeviceParam("fontSize", "Font size", 1, 1000, 48, "px"),
  DeviceParam("weight", "Weight", 100, 900, 400, "#"),
  DeviceParam("letter", "Letter", -50, 200, 0, "px"),
  DeviceParam("line", "Line", 0.5, 3, 1.2, "×"),
  DeviceParam("colour", "Colour", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("fill", "Fill", 0, 4294967295, 0, "argb"),
  DeviceParam(
      "borderColour", "Border colour", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("border", "Border", 0, 100, 0, "px"),
  DeviceParam("corners", "Corners", 0, 400, 0, "px"),
  DeviceParam("pad", "Padding", 0, 400, 0, "px"),
];

/// designPlace are Design's settings kept on the device: moves from where
/// the element rests.
const designPlace = {"x", "y", "turn", "size", "opacity", "skewX", "skewY"};

/// designChoices are the settings Design offers for [e], grouped as its
/// settings panel groups them: the "+ Setting" list.
List<(String, List<String>)> designChoices(CanvasElement e) => [
      ("Place", const ["x", "y", "turn", "size", "opacity", "skewX", "skewY"]),
      if (e is TextElement) ...[
        ("Letters", const ["fontSize", "weight", "letter", "line", "colour"]),
        ("Box", const ["fill", "borderColour", "border", "corners", "pad"]),
      ],
    ];

/// designShownDefault is what a new Design card shows.
const designShownDefault = ["x", "y", "turn", "size", "opacity"];

/// designRest is setting [id] of [e] as its settings panel has it: where
/// it rests, and what a first key starts from. Place settings rest on
/// [d] itself.
double designRest(CanvasElement e, MotionDevice d, String id) {
  if (designPlace.contains(id)) return d.value(id);
  if (e is TextElement) {
    var t = e.textSpec, b = e.box;
    switch (id) {
      case "fontSize":
        return t.fontSize;
      case "weight":
        return t.weight.toDouble();
      case "letter":
        return t.letterSpacing;
      case "line":
        return t.lineHeight;
      case "colour":
        return t.color.toARGB32().toDouble();
      case "fill":
        return b.fill.toARGB32().toDouble();
      case "borderColour":
        return b.borderColor.toARGB32().toDouble();
      case "border":
        return b.borderWidth;
      case "corners":
        return b.borderRadius;
      case "pad":
        return b.padding;
    }
  }
  return d.kind.param(id).initial;
}

/// designValueAt is setting [id] of [e] at [t] seconds: by Design's keys
/// playing then, or where it rests.
double designValueAt(CanvasElement e, MotionDevice d, String id, double t,
        {PhaseSpans spans = PhaseSpans.none}) =>
    d.liveIn(id, t, spans) != null
        ? d.valueAt(id, t, spans: spans)
        : designRest(e, d, id);

/// designPose is [pose] moved by Design [d] as it is now ([d] already at
/// the moment: see MotionDevice.at).
Keyframe designPose(Keyframe pose, MotionDevice d) {
  var x = d.value("x"), y = d.value("y"), turn = d.value("turn");
  var size = d.value("size"), opacity = d.value("opacity");
  if (x == 0 && y == 0 && turn == 0 && size == 1 && opacity == 1) return pose;
  return pose.copyWith(
      dx: pose.dx + x,
      dy: pose.dy + y,
      rotate: pose.rotate + turn,
      scale: pose.scale * size,
      opacity: (pose.opacity * opacity).clamp(0.0, 1.0).toDouble());
}

/// designed is [e] with its own settings as Design has them at [t]
/// seconds: those keyed and playing then, and its skew. Itself where
/// Design changes nothing.
CanvasElement designed(CanvasElement e, MotionDevice d, double t,
    {PhaseSpans spans = PhaseSpans.none}) {
  var now = d.at(t, spans: spans);
  var out = e;
  var sx = now.value("skewX"), sy = now.value("skewY");
  if (sx != 0 || sy != 0) {
    out = out.withBase(skewX: e.base.skewX + sx, skewY: e.base.skewY + sy);
  }
  if (out is TextElement) {
    bool live(String id) => d.liveIn(id, t, spans) != null;
    double v(String id) => now.value(id);
    Color c(String id) => Color(v(id).toInt());
    var mine = const [
      "fontSize", "weight", "letter", "line", "colour", //
      "fill", "borderColour", "border", "corners", "pad",
    ].where(live).toSet();
    if (mine.isNotEmpty) {
      var t0 = out.textSpec, b0 = out.box;
      out = out.copyWith(
        textSpec: t0.copyWith(
          fontSize: mine.contains("fontSize") ? v("fontSize") : null,
          weight: mine.contains("weight")
              ? ((v("weight") / 100).round() * 100).clamp(100, 900)
              : null,
          letterSpacing: mine.contains("letter") ? v("letter") : null,
          lineHeight: mine.contains("line") ? v("line") : null,
          color: mine.contains("colour") ? c("colour") : null,
        ),
        box: b0.copyWith(
          fill: mine.contains("fill") ? c("fill") : null,
          borderColor: mine.contains("borderColour") ? c("borderColour") : null,
          borderWidth: mine.contains("border") ? v("border") : null,
          borderRadius: mine.contains("corners") ? v("corners") : null,
          padding: mine.contains("pad") ? v("pad") : null,
        ),
      );
    }
  }
  return out;
}

/// designWritten is [e] with its own setting [id] made [v], as its settings
/// panel would make it: what a Design setting not keyed changes. Itself for
/// a setting of Design's own (see designPlace) or one it does not have.
CanvasElement designWritten(CanvasElement e, String id, double v) {
  if (e is! TextElement) return e;
  var t = e.textSpec, b = e.box;
  Color c() => Color(v.toInt());
  return switch (id) {
    "fontSize" => e.copyWith(textSpec: t.copyWith(fontSize: v)),
    "weight" => e.copyWith(
        textSpec:
            t.copyWith(weight: ((v / 100).round() * 100).clamp(100, 900))),
    "letter" => e.copyWith(textSpec: t.copyWith(letterSpacing: v)),
    "line" => e.copyWith(textSpec: t.copyWith(lineHeight: v)),
    "colour" => e.copyWith(textSpec: t.copyWith(color: c())),
    "fill" => e.copyWith(box: b.copyWith(fill: c())),
    "borderColour" => e.copyWith(box: b.copyWith(borderColor: c())),
    "border" => e.copyWith(box: b.copyWith(borderWidth: v)),
    "corners" => e.copyWith(box: b.copyWith(borderRadius: v)),
    "pad" => e.copyWith(box: b.copyWith(padding: v)),
    _ => e,
  };
}
