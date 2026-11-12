import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
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
  DeviceParam("gridColour", "Grid colour", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("barGap", "Bar gap", 0, 0.95, 0.3),
  DeviceParam("pointSize", "Point size", 0, 60, 4, "px"),
  DeviceParam("pointColour", "Point colour", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("headerFill", "Header fill", 0, 4294967295, 0, "argb"),
  DeviceParam("cellFill", "Cell fill", 0, 4294967295, 0, "argb"),
  // Pictures, video and drawings.
  DeviceParam("tint", "Tint", 0, 4294967295, 0, "argb"),
  DeviceParam("saturation", "Saturation", 0, 3, 1, "×"),
  DeviceParam("brightness", "Brightness", 0, 3, 1, "×"),
  DeviceParam("overlay", "Overlay", 0, 4294967295, 0, "argb"),
  DeviceParam("outline", "Outline", 0, 100, 0, "px"),
  DeviceParam(
      "outlineColour", "Outline colour", 0, 4294967295, 4294967295, "argb"),
  // Sound and music.
  DeviceParam("iconColour", "Icon colour", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("accent", "Accent", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("paper", "Paper", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("ink", "Ink", 0, 4294967295, 4278190080, "argb"),
  // A team.
  DeviceParam("playerColour", "Players", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("keeperColour", "Keeper", 0, 4294967295, 4294967295, "argb"),
  DeviceParam(
      "secondColour", "Second colour", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("dotWidth", "Token width", 2, 400, 40, "px"),
  DeviceParam("dotHeight", "Token height", 2, 400, 40, "px"),
  DeviceParam("ring", "Ring", 0, 60, 2, "px"),
  DeviceParam("nameGap", "Name gap", -100, 200, 4, "px"),
  DeviceParam("labelTurn", "Label turn", -180, 180, 0, "°"),
  // 3D.
  DeviceParam("zoom", "Zoom", 0.1, 10, 1, "×"),
  DeviceParam("spin", "Spin", -1440, 1440, 0, "°"),
  DeviceParam("tilt", "Tilt", -89, 89, 0, "°"),
  // A background: its pattern, and the stage or scenery it carries.
  DeviceParam("backColour", "Background", 0, 4294967295, 4278190080, "argb"),
  DeviceParam("foreColour", "Foreground", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("density", "Density", 0, 1, 0.5),
  DeviceParam("patternScale", "Scale", 0.001, 1, 0.05),
  DeviceParam("intensity", "Intensity", 0, 2, 0.8),
  DeviceParam("variation", "Variation", 0, 1, 0.5),
  DeviceParam("rotation", "Rotation", -360, 360, 0, "°"),
  DeviceParam("speed", "Speed", 0, 10, 1, "×"),
  DeviceParam("floor", "Floor", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("wallColour", "Wall", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("sky", "Sky", 0, 4294967295, 4294967295, "argb"),
  DeviceParam("stageSize", "Floor size", 1, 50, 10, "m"),
  DeviceParam("viewX", "View across", -10000, 10000, 0, "px"),
  DeviceParam("viewY", "View down", -10000, 10000, 0, "px"),
  DeviceParam("viewZoom", "View zoom", 0.1, 10, 1, "×"),
  // Sprites and tile maps.
  DeviceParam("cell", "Tile size", 2, 512, 32, "px"),
  DeviceParam("light", "Light", 0, 4294967295, 0, "argb"),
  DeviceParam("lightTo", "Light to", 0, 4294967295, 0, "argb"),
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

/// _orNone is a colour that may be left off -- a drawing's tint, a tile
/// map's light -- as Design reads it: clear where there is none, so keying
/// it starts from nothing.
double _orNone(Color? c) => c == null ? 0 : _argb(c);

/// _picture is a picture's own look Design animates, read from and written
/// to the ImageElement [of] gives and [put] lays back: a photograph's, or
/// the one a video is drawn with.
List<DesignSetting> _picture(
  ImageElement Function(CanvasElement e) of,
  CanvasElement Function(CanvasElement e, ImageElement i) put,
) =>
    [
      DesignSetting("tint", "Colour", (e) => _argb(of(e).tint),
          (e, v) => put(e, of(e).copyWith(tint: _colour(v)))),
      DesignSetting("saturation", "Colour", (e) => of(e).saturation,
          (e, v) => put(e, of(e).copyWith(saturation: v))),
      DesignSetting("brightness", "Colour", (e) => of(e).brightness,
          (e, v) => put(e, of(e).copyWith(brightness: v))),
      DesignSetting("overlay", "Colour", (e) => _argb(of(e).overlay),
          (e, v) => put(e, of(e).copyWith(overlay: _colour(v)))),
      DesignSetting(
          "outline",
          "Outline",
          (e) => of(e).outline.width,
          (e, v) => put(
              e, of(e).copyWith(outline: of(e).outline.copyWith(width: v)))),
      DesignSetting(
          "outlineColour",
          "Outline",
          (e) => _argb(of(e).outline.color),
          (e, v) => put(
              e,
              of(e).copyWith(
                  outline: of(e).outline.copyWith(color: _colour(v))))),
      ..._box((e) => of(e).box, (e, b) => put(e, of(e).copyWith(box: b))),
    ];

/// designTable is [e]'s own settings Design animates, grouped as its
/// settings panel groups them. A camera has its place only: its view is
/// read where the stage is filmed, not where elements are drawn.
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
      ChartElement _ => [
          DesignSetting(
              "stroke",
              "Series",
              (e) => (e as ChartElement).strokeWidth,
              (e, v) => (e as ChartElement).copyWith(strokeWidth: v)),
          DesignSetting("barGap", "Series", (e) => (e as ChartElement).barGap,
              (e, v) => (e as ChartElement).copyWith(barGap: v)),
          DesignSetting(
              "corners",
              "Series",
              (e) => (e as ChartElement).barRadius,
              (e, v) => (e as ChartElement).copyWith(barRadius: v)),
          DesignSetting(
              "pointSize",
              "Series",
              (e) => (e as ChartElement).pointSize,
              (e, v) => (e as ChartElement).copyWith(pointSize: v)),
          DesignSetting(
              "pointColour",
              "Series",
              (e) => _argb((e as ChartElement).pointColor),
              (e, v) => (e as ChartElement).copyWith(pointColor: _colour(v))),
          DesignSetting(
              "gridColour",
              "Grid",
              (e) => _argb((e as ChartElement).gridColor),
              (e, v) => (e as ChartElement).copyWith(gridColor: _colour(v))),
          ..._type("Title", (e) => (e as ChartElement).titleSpec,
              (e, t) => (e as ChartElement).copyWith(titleSpec: t),
              letters: false),
          ..._type("Labels", (e) => (e as ChartElement).labelSpec,
              (e, t) => (e as ChartElement).copyWith(labelSpec: t),
              size: "wordsSize", colour: "wordsColour", letters: false),
        ],
      TableElement _ => [
          DesignSetting(
              "headerFill",
              "Colours",
              (e) => _argb((e as TableElement).headerFill),
              (e, v) => (e as TableElement).copyWith(headerFill: _colour(v))),
          DesignSetting(
              "cellFill",
              "Colours",
              (e) => _argb((e as TableElement).cellFill),
              (e, v) => (e as TableElement).copyWith(cellFill: _colour(v))),
          DesignSetting(
              "gridColour",
              "Colours",
              (e) => _argb((e as TableElement).gridColor),
              (e, v) => (e as TableElement).copyWith(gridColor: _colour(v))),
          DesignSetting("pad", "Cells", (e) => (e as TableElement).cellPadding,
              (e, v) => (e as TableElement).copyWith(cellPadding: v)),
          ..._type("Header type", (e) => (e as TableElement).headerSpec,
              (e, t) => (e as TableElement).copyWith(headerSpec: t),
              letters: false),
          ..._type("Cell type", (e) => (e as TableElement).cellSpec,
              (e, t) => (e as TableElement).copyWith(cellSpec: t),
              size: "wordsSize", colour: "wordsColour", letters: false),
        ],
      ImageElement _ => _picture((e) => e as ImageElement, (e, i) => i),
      VideoElement _ => _picture((e) => (e as VideoElement).picture,
          (e, i) => (e as VideoElement).copyWith(look: i)),
      VectorElement _ => [
          DesignSetting(
              "tint",
              "Colour",
              (e) => _orNone((e as VectorElement).tint),
              (e, v) => v == 0
                  ? (e as VectorElement).copyWith(clearTint: true)
                  : (e as VectorElement).copyWith(tint: _colour(v))),
        ],
      AudioElement _ => [
          DesignSetting(
              "iconColour",
              "Icon",
              (e) => _argb((e as AudioElement).iconColor),
              (e, v) => (e as AudioElement).copyWith(iconColor: _colour(v))),
          DesignSetting(
              "accent",
              "Icon",
              (e) => _argb((e as AudioElement).accent),
              (e, v) => (e as AudioElement).copyWith(accent: _colour(v))),
          ..._box((e) => (e as AudioElement).box,
              (e, b) => (e as AudioElement).copyWith(box: b)),
        ],
      SheetElement _ => [
          DesignSetting(
              "paper",
              "Sheet",
              (e) => _argb((e as SheetElement).paper),
              (e, v) => (e as SheetElement).copyWith(paper: _colour(v))),
          DesignSetting("ink", "Sheet", (e) => _argb((e as SheetElement).ink),
              (e, v) => (e as SheetElement).copyWith(ink: _colour(v))),
        ],
      TeamElement _ => [
          for (var (id, read, write) in <(
            String,
            Color Function(TeamElement),
            TeamElement Function(TeamElement, Color)
          )>[
            (
              "playerColour",
              (t) => t.playerColor,
              (t, c) => t.copyWith(playerColor: c)
            ),
            (
              "secondColour",
              (t) => t.secondaryColor,
              (t, c) => t.copyWith(secondaryColor: c)
            ),
            (
              "keeperColour",
              (t) => t.keeperColor,
              (t, c) => t.copyWith(keeperColor: c)
            ),
            (
              "outlineColour",
              (t) => t.outlineColor,
              (t, c) => t.copyWith(outlineColor: c)
            ),
          ])
            DesignSetting(id, "Kit", (e) => _argb(read(e as TeamElement)),
                (e, v) => write(e as TeamElement, _colour(v))),
          for (var (id, read, write) in <(
            String,
            double Function(TeamElement),
            TeamElement Function(TeamElement, double)
          )>[
            ("dotWidth", (t) => t.dotWidth, (t, v) => t.copyWith(dotWidth: v)),
            (
              "dotHeight",
              (t) => t.dotHeight,
              (t, v) => t.copyWith(dotHeight: v)
            ),
            ("ring", (t) => t.ringWidth, (t, v) => t.copyWith(ringWidth: v)),
          ])
            DesignSetting(id, "Tokens", (e) => read(e as TeamElement),
                (e, v) => write(e as TeamElement, v)),
          DesignSetting("nameGap", "Names", (e) => (e as TeamElement).nameGap,
              (e, v) => (e as TeamElement).copyWith(nameGap: v)),
          DesignSetting(
              "labelTurn",
              "Names",
              (e) => (e as TeamElement).labelRotation,
              (e, v) => (e as TeamElement).copyWith(labelRotation: v)),
          ..._type("Names", (e) => (e as TeamElement).labelSpec,
              (e, t) => (e as TeamElement).copyWith(labelSpec: t),
              size: "wordsSize", colour: "wordsColour", letters: false),
        ],
      Character3dElement _ => [
          DesignSetting("zoom", "View", (e) => (e as Character3dElement).zoom,
              (e, v) => (e as Character3dElement).copyWith(zoom: v)),
        ],
      Object3dElement _ => [
          DesignSetting("spin", "Seen", (e) => (e as Object3dElement).turn,
              (e, v) => (e as Object3dElement).copyWith(turn: v)),
          DesignSetting("tilt", "Seen", (e) => (e as Object3dElement).tilt,
              (e, v) => (e as Object3dElement).copyWith(tilt: v)),
          DesignSetting("zoom", "Seen", (e) => (e as Object3dElement).zoom,
              (e, v) => (e as Object3dElement).copyWith(zoom: v)),
        ],
      SpriteElement _ => [
          DesignSetting(
              "tint",
              "Colour",
              (e) => _orNone((e as SpriteElement).tint),
              (e, v) => v == 0
                  ? (e as SpriteElement).copyWith(noTint: true)
                  : (e as SpriteElement).copyWith(tint: _colour(v))),
        ],
      TileMapElement _ => [
          DesignSetting("cell", "Tiles", (e) => (e as TileMapElement).cell,
              (e, v) => (e as TileMapElement).copyWith(cell: v)),
          DesignSetting(
              "light",
              "Light",
              (e) => _orNone((e as TileMapElement).light),
              (e, v) => v == 0
                  ? (e as TileMapElement).copyWith(noLight: true)
                  : (e as TileMapElement).copyWith(light: _colour(v))),
          DesignSetting(
              "lightTo",
              "Light",
              (e) => _orNone((e as TileMapElement).lightTo),
              (e, v) => v == 0
                  ? (e as TileMapElement).copyWith(noLightTo: true)
                  : (e as TileMapElement).copyWith(lightTo: _colour(v))),
        ],
      BackgroundElement b => [
          DesignSetting(
              "corners",
              "Panel",
              (e) => (e as BackgroundElement).cornerRadius,
              (e, v) => (e as BackgroundElement).copyWith(cornerRadius: v)),
          ..._pattern(),
          if (b.stage != null) ..._stage(),
          if (b.parallax != null) ..._scenery(),
        ],
      _ => const [],
    };

/// _pattern is a background's pattern Design animates: its colours and its
/// numbers, as the Pattern section has them.
List<DesignSetting> _pattern() {
  ProceduralSpec of(CanvasElement e) => (e as BackgroundElement).spec;
  CanvasElement put(CanvasElement e, ProceduralSpec s) =>
      (e as BackgroundElement).copyWith(spec: s);
  return [
    DesignSetting("backColour", "Pattern", (e) => _argb(of(e).background),
        (e, v) => put(e, of(e).copyWith(background: _colour(v)))),
    DesignSetting("foreColour", "Pattern", (e) => _argb(of(e).foreground),
        (e, v) => put(e, of(e).copyWith(foreground: _colour(v)))),
    DesignSetting("accent", "Pattern", (e) => _argb(of(e).accent),
        (e, v) => put(e, of(e).copyWith(accent: _colour(v)))),
    DesignSetting("density", "Pattern", (e) => of(e).density,
        (e, v) => put(e, of(e).copyWith(density: v))),
    DesignSetting("patternScale", "Pattern", (e) => of(e).scale,
        (e, v) => put(e, of(e).copyWith(scale: v))),
    DesignSetting("intensity", "Pattern", (e) => of(e).intensity,
        (e, v) => put(e, of(e).copyWith(intensity: v))),
    DesignSetting("variation", "Pattern", (e) => of(e).variation,
        (e, v) => put(e, of(e).copyWith(variation: v))),
    DesignSetting("rotation", "Pattern", (e) => of(e).rotation,
        (e, v) => put(e, of(e).copyWith(rotation: v))),
    DesignSetting("speed", "Pattern", (e) => of(e).speed,
        (e, v) => put(e, of(e).copyWith(speed: v))),
  ];
}

/// _stage is the 3D stage a background carries, as Design animates it.
List<DesignSetting> _stage() {
  StageElement of(CanvasElement e) => (e as BackgroundElement).stage!;
  CanvasElement put(CanvasElement e, StageElement s) =>
      (e as BackgroundElement).copyWith(stage: s);
  return [
    DesignSetting("floor", "Stage", (e) => _argb(of(e).floor),
        (e, v) => put(e, of(e).copyWith(floor: _colour(v)))),
    DesignSetting("wallColour", "Stage", (e) => _argb(of(e).wallColor),
        (e, v) => put(e, of(e).copyWith(wallColor: _colour(v)))),
    DesignSetting("sky", "Stage", (e) => _argb(of(e).sky),
        (e, v) => put(e, of(e).copyWith(sky: _colour(v)))),
    DesignSetting("stageSize", "Stage", (e) => of(e).size,
        (e, v) => put(e, of(e).copyWith(size: v))),
  ];
}

/// _scenery is the parallax scenery a background carries: where its view
/// looks, as Design animates it.
List<DesignSetting> _scenery() {
  ParallaxElement of(CanvasElement e) => (e as BackgroundElement).parallax!;
  CanvasElement put(CanvasElement e, ParallaxElement p) =>
      (e as BackgroundElement).copyWith(parallax: p);
  return [
    DesignSetting("viewX", "Scenery", (e) => of(e).camera.x,
        (e, v) => put(e, of(e).copyWith(camera: of(e).camera.copyWith(x: v)))),
    DesignSetting("viewY", "Scenery", (e) => of(e).camera.y,
        (e, v) => put(e, of(e).copyWith(camera: of(e).camera.copyWith(y: v)))),
    DesignSetting(
        "viewZoom",
        "Scenery",
        (e) => of(e).camera.zoom,
        (e, v) =>
            put(e, of(e).copyWith(camera: of(e).camera.copyWith(zoom: v)))),
  ];
}

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
