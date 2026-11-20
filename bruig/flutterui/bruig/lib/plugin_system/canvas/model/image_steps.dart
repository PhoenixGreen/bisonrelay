import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/presets/film_tables.dart';

// image_steps.dart is a picture's actions written as plain steps -- "an
// adjustment of this kind with these settings", "a copy of the picture,
// screened and blurred" -- for an assistant or a script to do to a picture
// without knowing how its layers are saved. Read forgivingly: a step it
// cannot make is named, and the rest are made. imageReference says what
// every step can be.

/// ImageSteps is steps read: the action they make (see lookData), and what
/// could not be made of them.
class ImageSteps {
  final Map<String, dynamic> data;
  final List<String> problems;
  const ImageSteps(this.data, this.problems);

  int get count => lookSteps(data);
}

const _stand = ImageElement(ElementBase(id: "steps", width: 1000, height: 1000),
    assetId: "steps-picture");

/// imageStepsFrom reads [raw], a list of steps, into an action.
ImageSteps imageStepsFrom(Object? raw) {
  var problems = <String>[];
  var under = <ImageLayer>[], over = <ImageLayer>[];
  var effects = <LayerEffect>[];
  if (raw is! List) {
    return const ImageSteps({}, ["Steps are a list."]);
  }
  for (var (i, item) in raw.take(48).indexed) {
    if (item is! Map) {
      problems.add("Step ${i + 1} is not an object.");
      continue;
    }
    var step = Map<String, dynamic>.from(item);
    var (layer, effect, problem) = _step(step);
    if (problem != null) problems.add("Step ${i + 1}: $problem");
    if (effect != null) effects.add(effect);
    if (layer == null) continue;
    layer = layer.copyWith(
      opacity: _num(step["opacity"]),
      blend: step["blend"] is String ? _blend("${step["blend"]}") : null,
      clip: step["clip"] is bool ? step["clip"] as bool : null,
      name: step["name"] is String ? "${step["name"]}" : null,
    );
    (step["under"] == true ? under : over).add(layer);
  }
  var e = _stand.withLayers([
    ...under,
    ImageLayer.base.copyWith(effects: effects.take(16).toList()),
    ...over,
  ]);
  return ImageSteps(lookData(e), problems);
}

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

LayerBlend? _blend(String name) =>
    LayerBlend.values.where((b) => b.name == name).firstOrNull;

Color? _colour(Object? v) {
  if (v is! String) return null;
  var hex = v.replaceFirst("#", "");
  if (hex.length == 3) hex = [for (var c in hex.split("")) "$c$c"].join();
  if (hex.length == 6) hex = "FF$hex";
  var n = int.tryParse(hex, radix: 16);
  return hex.length == 8 && n != null ? Color(n) : null;
}

Map<String, double> _values(Object? v) => {
      if (v is Map)
        for (var e in v.entries)
          if (e.key is String && e.value is num && (e.value as num).isFinite)
            e.key as String: (e.value as num).toDouble()
    };

/// _fade is [colours], dark to light, spread evenly.
PaintSpec? _fade(Object? v) {
  if (v is! List) return null;
  var colours =
      [for (var c in v.take(8)) _colour(c)].whereType<Color>().toList();
  if (colours.isEmpty) return null;
  if (colours.length == 1) return PaintSpec(colours.single);
  return PaintSpec(colours.first,
      gradient:
          GradientSpec(to: colours[1], end: 1 / (colours.length - 1), more: [
        for (var i = 2; i < colours.length; i++)
          GradientStop(colours[i], i / (colours.length - 1))
      ]));
}

(ImageLayer?, LayerEffect?, String?) _step(Map<String, dynamic> step) {
  var kind = "${step["kind"] ?? ""}";
  var values = _values(step["values"]);
  switch ("${step["step"] ?? step["type"] ?? ""}") {
    case "adjust" || "adjustment":
      var k = AdjustKind.values.where((a) => a.name == kind).firstOrNull;
      if (k == null) {
        return (null, null, "no adjustment called \"$kind\".");
      }
      var a = ImageAdjustment(kind: k);
      String? problem;
      for (var e in values.entries) {
        if (!k.params.any((p) => p.key == e.key) &&
            !(e.key == "keepLight" || e.key == "colourise")) {
          problem = "${k.name} has no setting \"${e.key}\".";
          continue;
        }
        a = a.withValue(e.key, e.value);
      }
      if (_colour(step["colour"]) case var c?) a = a.copyWith(colour: c);
      if (_fade(step["colours"]) case var f?) a = a.copyWith(fade: f);
      if (step["table"] is String) {
        var table = "${step["table"]}";
        if (filmTables.any((t) => t.id == table)) {
          a = a.copyWith(table: table);
        } else {
          problem = "no film table called \"$table\".";
        }
      }
      if (step["points"] is List) {
        var points = <Offset>[
          for (var p in (step["points"] as List).take(64))
            if (p case [num x, num y]) Offset(x.toDouble(), y.toDouble())
        ];
        var channel = CurveChannel.values
                .where((c) => c.name == step["channel"])
                .firstOrNull ??
            CurveChannel.rgb;
        if (points.length >= 2) a = a.withCurve(channel, points);
      }
      return (ImageLayer.adjusting(k).copyWith(adjust: a), null, problem);
    case "curve":
      var points = <Offset>[
        for (var p in (step["points"] is List ? step["points"] as List : []))
          if (p case [num x, num y]) Offset(x.toDouble(), y.toDouble())
      ];
      if (points.length < 2) return (null, null, "a curve needs two points.");
      var channel = CurveChannel.values
              .where((c) => c.name == step["channel"])
              .firstOrNull ??
          CurveChannel.rgb;
      return (
        ImageLayer.adjusting(AdjustKind.curves).copyWith(
            adjust: const ImageAdjustment(kind: AdjustKind.curves)
                .withCurve(channel, points)),
        null,
        null
      );
    case "texture":
      var k = TextureKind.values.where((t) => t.name == kind).firstOrNull;
      if (k == null) return (null, null, "no texture called \"$kind\".");
      var layer = ImageLayer.texturing(k);
      var t = layer.texture;
      for (var e in values.entries) {
        t = t.withValue(e.key, e.value);
      }
      t = t.copyWith(
          colour: _colour(step["colour"]), second: _colour(step["second"]));
      return (layer.copyWith(texture: t), null, null);
    case "fill":
      var plain = _colour(step["colour"]);
      var fill =
          _fade(step["colours"]) ?? (plain == null ? null : PaintSpec(plain));
      if (fill == null) return (null, null, "a fill needs a colour.");
      return (ImageLayer.solid(fill), null, null);
    case "copy":
      var shift = switch (step["shift"]) {
        [num x, num y, num w, num h] when w > 0 && h > 0 => [
            x.toDouble().clamp(-4.0, 4.0),
            y.toDouble().clamp(-4.0, 4.0),
            w.toDouble().clamp(0.05, 8.0),
            h.toDouble().clamp(0.05, 8.0),
          ],
        _ => const [0.0, 0.0, 1.0, 1.0],
      };
      var copy = pictureCopy(_stand, shift: shift);
      return (
        copy.copyWith(
            flipX: step["flipX"] == true ? true : null,
            flipY: step["flipY"] == true ? true : null,
            effects: [
              if (step["effects"] case List list)
                for (var f in list.take(8))
                  if (f is Map) _effect(Map<String, dynamic>.from(f)).$1
            ].whereType<LayerEffect>().toList()),
        null,
        null
      );
    case "effect":
      var (effect, problem) = _effect(step);
      return (null, effect, problem);
    default:
      return (
        null,
        null,
        "a step is one of adjust, curve, texture, fill, copy or effect."
      );
  }
}

(LayerEffect?, String?) _effect(Map<String, dynamic> step) {
  var kind = "${step["kind"] ?? ""}";
  var k = EffectKind.values.where((e) => e.name == kind).firstOrNull;
  if (k == null) return (null, "no effect called \"$kind\".");
  var effect = LayerEffect(kind: k, colour: _colour(step["colour"]));
  for (var e in _values(step["values"]).entries) {
    effect = effect.withValue(e.key, e.value);
  }
  return (effect, null);
}

Map<String, Object?> _param(AdjustParam p) => {
      "key": p.key,
      "label": p.label,
      "min": p.min,
      "max": p.max,
      "default": p.initial,
    };

/// imageReference is every step a picture's action can hold, and what each
/// is set by: for an assistant, so it writes steps that are made.
Map<String, Object?> imageReference() => {
      "steps": {
        "adjust": "An adjustment layer: kind, values; colour for "
            "photoFilter/keepColour/blackWhite; colours (dark to light) for "
            "gradientMap; table for colourTable; points [[x,y]...] and "
            "channel (rgb/red/green/blue) for curves. It changes every layer "
            "under it, or with clip: true only the layer just under it.",
        "curve": "A curves adjustment: points [[x,y]...] 0 to 1, channel.",
        "texture": "A texture drawn over the frame: kind, values, colour.",
        "fill": "A colour layer: colour, or colours for a fade.",
        "copy": "A copy of the picture itself: blend, opacity, effects "
            "[{kind, values}], shift [across, down, width, height] as "
            "fractions of the picture (0,0,1,1 is in place), flipX.",
        "effect": "An effect on the picture itself: kind, values, colour.",
        "every step": "Also: blend, opacity (0 to 1), clip, under (true "
            "puts a layer under the picture), name.",
      },
      "adjustments": {
        for (var k in AdjustKind.values)
          k.name: {
            "label": k.label,
            "settings": [for (var p in k.params) _param(p)],
            if (k.neighbours)
              "sizes": "thousandths of the picture's shorter side",
          }
      },
      "textures": {
        for (var k in TextureKind.values)
          k.name: {
            "label": k.label,
            "blend": k.blend,
            "settings": [for (var p in k.params) _param(p)],
          }
      },
      "effects": {
        for (var k in EffectKind.values)
          k.name: {
            "label": k.label,
            "settings": [for (var p in k.params) _param(p)],
          }
      },
      "blends": [for (var b in LayerBlend.values) b.name],
      "filmTables": [
        for (var t in filmTables) {"id": t.id, "name": t.name, "group": t.group}
      ],
      "filmTablesCredit": filmTablesCredit,
    };
