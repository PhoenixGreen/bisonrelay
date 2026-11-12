import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe;
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// design_device.dart is the Chain's Design device (Ken, 2026-11-12): the
// element's own settings, animated in its arrival, leaving and loop or
// independently. The settings panel sets how each rests; Design keys them.
//
// Two kinds of setting:
//  - its place -- Across, Down, Turn, Size, Opacity, Skew -- kept on the
//    device, as a move from where it rests: nought (one for Size and
//    Opacity) leaves it be. Joined to the pose after the pose devices.
//  - the element's own -- a text's font size, a shape's fill, a line's
//    curve -- as its panel has them: they rest at the panel's value and
//    are only changed where keyed. Each kind of element says which it has,
//    and how each is read and written, in one table (designTable): "+
//    Setting", where they rest and how they are drawn all read it, so a
//    new element only fills in its table (Ken: "a full list of settings").

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
  DeviceParam("stroke", "Stroke", 0, 200, 1, "px"),
  DeviceParam(
      "strokeColour", "Stroke colour", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("points", "Points", 3, 24, 5, "#"),
  DeviceParam("depth", "Depth", 0.05, 0.95, 0.5),
  DeviceParam("curve", "Curve", -1, 1, 0),
  DeviceParam("dash", "Dash", 0, 400, 0, "px"),
  DeviceParam("endSize", "End size", 0.2, 8, 1, "×"),
  DeviceParam("wordsSize", "Words size", 1, 1000, 24, "px"),
  DeviceParam("wordsColour", "Words colour", 0, 4294967295, 4294967295, "argb"),
];

/// designPlace are Design's settings kept on the device: moves from where
/// the element rests.
const designPlace = {"x", "y", "turn", "size", "opacity", "skewX", "skewY"};

/// designShownDefault is what a new Design card shows.
const designShownDefault = ["x", "y", "turn", "size", "opacity"];

/// DesignSetting is one of an element's own settings as Design animates
/// it: which, the group its panel shows it in, and how it is read and
/// written.
class DesignSetting {
  final String id;
  final String group;
  final double Function(CanvasElement e) read;
  final CanvasElement Function(CanvasElement e, double v) write;
  const DesignSetting(this.id, this.group, this.read, this.write);
}

double _argb(Color c) => c.toARGB32().toDouble();
Color _colour(double v) => Color(v.toInt());
int _weight(double v) => ((v / 100).round() * 100).clamp(100, 900);

/// _type is a TextSpec's settings Design animates, read from and written
/// to the spec [of] gives and [put] lays back: one family of words.
List<DesignSetting> _type(
  String group,
  TextSpec Function(CanvasElement e) of,
  CanvasElement Function(CanvasElement e, TextSpec t) put, {
  String size = "fontSize",
  String colour = "colour",
  bool letters = true,
}) =>
    [
      DesignSetting(size, group, (e) => of(e).fontSize,
          (e, v) => put(e, of(e).copyWith(fontSize: v))),
      if (letters) ...[
        DesignSetting("weight", group, (e) => of(e).weight.toDouble(),
            (e, v) => put(e, of(e).copyWith(weight: _weight(v)))),
        DesignSetting("letter", group, (e) => of(e).letterSpacing,
            (e, v) => put(e, of(e).copyWith(letterSpacing: v))),
        DesignSetting("line", group, (e) => of(e).lineHeight,
            (e, v) => put(e, of(e).copyWith(lineHeight: v))),
      ],
      DesignSetting(colour, group, (e) => _argb(of(e).color),
          (e, v) => put(e, of(e).copyWith(color: _colour(v)))),
    ];

/// _box is a BoxSpec's settings Design animates.
List<DesignSetting> _box(
  BoxSpec Function(CanvasElement e) of,
  CanvasElement Function(CanvasElement e, BoxSpec b) put,
) =>
    [
      DesignSetting("fill", "Box", (e) => _argb(of(e).fill),
          (e, v) => put(e, of(e).copyWith(fill: _colour(v)))),
      DesignSetting("borderColour", "Box", (e) => _argb(of(e).borderColor),
          (e, v) => put(e, of(e).copyWith(borderColor: _colour(v)))),
      DesignSetting("border", "Box", (e) => of(e).borderWidth,
          (e, v) => put(e, of(e).copyWith(borderWidth: v))),
      DesignSetting("corners", "Box", (e) => of(e).borderRadius,
          (e, v) => put(e, of(e).copyWith(borderRadius: v))),
      DesignSetting("pad", "Box", (e) => of(e).padding,
          (e, v) => put(e, of(e).copyWith(padding: v))),
    ];

/// designTable is [e]'s own settings Design animates, grouped as its
/// settings panel groups them: none for a kind not yet given its list.
List<DesignSetting> designTable(CanvasElement e) => switch (e) {
      TextElement _ => [
          ..._type("Letters", (e) => (e as TextElement).textSpec,
              (e, t) => (e as TextElement).copyWith(textSpec: t)),
          ..._box((e) => (e as TextElement).box,
              (e, b) => (e as TextElement).copyWith(box: b)),
        ],
      ShapeElement _ => [
          DesignSetting("fill", "Fill", (e) => _argb((e as ShapeElement).fill),
              (e, v) => (e as ShapeElement).copyWith(fill: _colour(v))),
          DesignSetting(
              "stroke",
              "Outline",
              (e) => (e as ShapeElement).strokeWidth,
              (e, v) => (e as ShapeElement).copyWith(strokeWidth: v)),
          DesignSetting(
              "strokeColour",
              "Outline",
              (e) => _argb((e as ShapeElement).strokeColor),
              (e, v) => (e as ShapeElement).copyWith(strokeColor: _colour(v))),
          DesignSetting(
              "corners",
              "Shape",
              (e) => (e as ShapeElement).cornerRadius,
              (e, v) => (e as ShapeElement).copyWith(cornerRadius: v)),
          DesignSetting(
              "points",
              "Shape",
              (e) => (e as ShapeElement).points.toDouble(),
              (e, v) =>
                  (e as ShapeElement).copyWith(points: v.round().clamp(3, 24))),
          DesignSetting("depth", "Shape", (e) => (e as ShapeElement).innerRatio,
              (e, v) => (e as ShapeElement).copyWith(innerRatio: v)),
          DesignSetting("pad", "Label", (e) => (e as ShapeElement).padding,
              (e, v) => (e as ShapeElement).copyWith(padding: v)),
          ..._type("Label", (e) => (e as ShapeElement).textSpec,
              (e, t) => (e as ShapeElement).copyWith(textSpec: t),
              letters: false),
        ],
      LineElement _ => [
          DesignSetting(
              "strokeColour",
              "Stroke",
              (e) => _argb((e as LineElement).color),
              (e, v) => (e as LineElement).copyWith(color: _colour(v))),
          DesignSetting(
              "stroke",
              "Stroke",
              (e) => (e as LineElement).strokeWidth,
              (e, v) => (e as LineElement).copyWith(strokeWidth: v)),
          DesignSetting("curve", "Stroke", (e) => (e as LineElement).curvature,
              (e, v) => (e as LineElement).copyWith(curvature: v)),
          DesignSetting(
              "dash",
              "Ends and dashes",
              (e) => (e as LineElement).dash,
              (e, v) => (e as LineElement).copyWith(dash: v)),
          DesignSetting(
              "endSize",
              "Ends and dashes",
              (e) => (e as LineElement).endSize,
              (e, v) => (e as LineElement).copyWith(endSize: v)),
        ],
      PathElement _ => [
          DesignSetting(
              "strokeColour",
              "Stroke",
              (e) => _argb((e as PathElement).color),
              (e, v) => (e as PathElement).copyWith(color: _colour(v))),
          DesignSetting(
              "stroke",
              "Stroke",
              (e) => (e as PathElement).strokeWidth,
              (e, v) => (e as PathElement).copyWith(strokeWidth: v)),
          DesignSetting(
              "dash",
              "Ends and dashes",
              (e) => (e as PathElement).dash,
              (e, v) => (e as PathElement).copyWith(dash: v)),
          DesignSetting(
              "endSize",
              "Ends and dashes",
              (e) => (e as PathElement).endSize,
              (e, v) => (e as PathElement).copyWith(endSize: v)),
        ],
      ButtonElement _ => [
          ..._type("Label", (e) => (e as ButtonElement).textSpec,
              (e, t) => (e as ButtonElement).copyWith(textSpec: t)),
          ..._box((e) => (e as ButtonElement).box,
              (e, b) => (e as ButtonElement).copyWith(box: b)),
        ],
      CounterElement _ => [
          ..._type("Number", (e) => (e as CounterElement).numberSpec,
              (e, t) => (e as CounterElement).copyWith(numberSpec: t)),
          ..._type("Words", (e) => (e as CounterElement).affixSpec,
              (e, t) => (e as CounterElement).copyWith(affixSpec: t),
              size: "wordsSize", colour: "wordsColour", letters: false),
          ..._box((e) => (e as CounterElement).box,
              (e, b) => (e as CounterElement).copyWith(box: b)),
        ],
      _ => const [],
    };

DesignSetting? _settingOf(CanvasElement e, String id) =>
    designTable(e).where((s) => s.id == id).firstOrNull;

/// designChoices are the settings Design offers for [e], grouped as its
/// settings panel groups them: the "+ Setting" list.
List<(String, List<String>)> designChoices(CanvasElement e) {
  var groups = <String, List<String>>{
    "Place": const ["x", "y", "turn", "size", "opacity", "skewX", "skewY"],
  };
  for (var s in designTable(e)) {
    (groups[s.group] ??= []).add(s.id);
  }
  return [for (var MapEntry(:key, :value) in groups.entries) (key, value)];
}

/// designRest is setting [id] of [e] as its settings panel has it: where
/// it rests, and what a first key starts from. Place settings rest on
/// [d] itself.
double designRest(CanvasElement e, MotionDevice d, String id) {
  if (designPlace.contains(id)) return d.value(id);
  return _settingOf(e, id)?.read(e) ?? d.kind.param(id).initial;
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
  for (var s in designTable(out)) {
    if (d.liveIn(s.id, t, spans) != null) out = s.write(out, now.value(s.id));
  }
  return out;
}

/// designWritten is [e] with its own setting [id] made [v], as its settings
/// panel would make it: what a Design setting not keyed changes. Itself for
/// a setting of Design's own (see designPlace) or one it does not have.
CanvasElement designWritten(CanvasElement e, String id, double v) =>
    _settingOf(e, id)?.write(e, v) ?? e;
