import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';

// lightroom_preset.dart reads a Lightroom (or Camera Raw) preset -- an .xmp
// file of "crs:" settings -- as an image action: each setting it has onto
// the adjustment that does the same, in Lightroom's order. What has no
// counterpart here (lens corrections, masks, a raw file's sharpening) is
// named, not guessed at.
//
// Read as text with patterns, never as XML with entities, so a file cannot
// make the reader fetch or expand anything.

/// maxPresetBytes is the largest preset file read; they are a few kilobytes.
const int maxPresetBytes = 2 * 1024 * 1024;

/// LightroomPreset is a preset read in: its name, the action (lookData),
/// and the settings it had that the action does not.
class LightroomPreset {
  final String name;
  final Map<String, dynamic> data;
  final List<String> left;
  const LightroomPreset(this.name, this.data, this.left);
}

/// _carried are the settings read; any other non-zero setting is left.
const _carried = {
  "Exposure2012",
  "Contrast2012",
  "Highlights2012",
  "Shadows2012",
  "Whites2012",
  "Blacks2012",
  "Clarity2012",
  "Dehaze",
  "Vibrance",
  "Saturation",
  "IncrementalTemperature",
  "IncrementalTint",
  "Temperature",
  "Tint",
  "ConvertToGrayscale",
  "GrainAmount",
  "GrainSize",
  "PostCropVignetteAmount",
  "PostCropVignetteMidpoint",
  "PostCropVignetteFeather",
  "SplitToningShadowHue",
  "SplitToningShadowSaturation",
  "SplitToningHighlightHue",
  "SplitToningHighlightSaturation",
  "SplitToningBalance",
  "ColorGradeMidtoneHue",
  "ColorGradeMidtoneSat",
  "ColorGradeShadowLum",
  "ColorGradeMidtoneLum",
  "ColorGradeHighlightLum",
  "ColorGradeBlending",
  "ColorGradeGlobalHue",
  "ColorGradeGlobalSat",
  "ColorGradeGlobalLum",
  "ColorGradeBalance",
};

/// _bookkeeping are settings that say how a preset is kept, not what it
/// does; never named as left out.
const _bookkeeping = {
  "PresetType",
  "Cluster",
  "UUID",
  "SupportsAmount",
  "SupportsAmount2",
  "SupportsColor",
  "SupportsMonochrome",
  "SupportsHighDynamicRange",
  "SupportsNormalDynamicRange",
  "SupportsSceneReferred",
  "SupportsOutputReferred",
  "CameraModelRestriction",
  "Copyright",
  "ContactInfo",
  "Version",
  "ProcessVersion",
  "HasSettings",
  "Name",
  "ShortName",
  "SortName",
  "Group",
  "Description",
  "RequiresRGBTables",
  "ToneCurveName2012",
  "CameraProfile",
  "LookTable",
  "ProfileName",
  "HasCrop",
  "AlreadyApplied",
  "WhiteBalance",
  "OverrideLookVignette",
  "Look",
  "Amount",
  "ToneMapStrength",
  "ConvertToGrayscale",
};

const _bands = [
  ("Red", "red"),
  ("Orange", "orange"),
  ("Yellow", "yellow"),
  ("Green", "green"),
  ("Aqua", "aqua"),
  ("Blue", "blue"),
  ("Purple", "purple"),
  ("Magenta", "magenta"),
];

/// readLightroomPreset is the preset in [text], or why there is none.
/// [fallback] names it when it has no name of its own.
(LightroomPreset?, String?) readLightroomPreset(String text, String fallback) {
  if (!text.contains("crs:")) {
    return (null, "That is not a Lightroom preset.");
  }
  var settings = <String, String>{};
  for (var m in RegExp(r'crs:(\w+)="([^"]*)"').allMatches(text)) {
    settings[m.group(1)!] = m.group(2)!;
  }
  for (var m in RegExp(r"<crs:(\w+)>([^<]*)</crs:\1>").allMatches(text)) {
    settings[m.group(1)!] = m.group(2)!.trim();
  }
  double n(String key) =>
      double.tryParse((settings[key] ?? "").replaceAll("+", "")) ?? 0;
  bool has(String key) => n(key) != 0;

  var name = RegExp(r"<crs:Name>\s*<rdf:Alt>\s*<rdf:li[^>]*>([^<]*)</rdf:li>")
          .firstMatch(text)
          ?.group(1)
          ?.trim() ??
      "";
  if (name.isEmpty) name = fallback;
  if (name.length > 80) name = name.substring(0, 80);

  var layers = <ImageLayer>[];
  void adjust(AdjustKind kind, Map<String, double> values) {
    var kept = {
      for (var e in values.entries)
        if (e.value != 0 || kind == AdjustKind.channelMixer) e.key: e.value
    };
    if (kept.isEmpty) return;
    var a = ImageAdjustment(kind: kind);
    for (var e in kept.entries) {
      a = a.withValue(e.key, e.value);
    }
    layers.add(ImageLayer.adjusting(kind).copyWith(adjust: a));
  }

  if ((settings["ConvertToGrayscale"] ?? "").toLowerCase() == "true") {
    layers.add(ImageLayer.adjusting(AdjustKind.blackWhite));
  }
  // White balance: Incremental for a JPEG's preset; a raw one's is in
  // kelvin, read from daylight.
  var warmth = has("IncrementalTemperature")
      ? n("IncrementalTemperature") / 100
      : has("Temperature")
          ? (n("Temperature") - 5500) / 3000
          : 0.0;
  var tint =
      has("IncrementalTint") ? n("IncrementalTint") / 100 : n("Tint") / 150;
  adjust(AdjustKind.temperature, {
    "warmth": warmth.clamp(-1.0, 1.0),
    // Lightroom's tint runs green to magenta; ours magenta to green.
    "tint": (-tint).clamp(-1.0, 1.0),
  });
  adjust(AdjustKind.exposure, {"stops": n("Exposure2012")});
  adjust(AdjustKind.brightness, {"contrast": n("Contrast2012") / 100 * 0.35});
  adjust(AdjustKind.shadowsHighlights, {
    "shadows": math.max(0.0, n("Shadows2012")) / 100,
    "highlights": math.max(0.0, -n("Highlights2012")) / 100,
  });
  // What recovery cannot do -- deeper shadows, brighter highlights, the
  // white and black points -- as a gentle curve.
  var b = n("Blacks2012") / 100, w = n("Whites2012") / 100;
  var s = math.min(0.0, n("Shadows2012")) / 100;
  var h = math.max(0.0, n("Highlights2012")) / 100;
  if (b != 0 || w != 0 || s != 0 || h != 0) {
    layers.add(ImageLayer.adjusting(AdjustKind.curves).copyWith(
        adjust: const ImageAdjustment(kind: AdjustKind.curves)
            .withCurve(CurveChannel.rgb, [
      Offset(0, math.max(0.0, b * 0.1)),
      Offset(0.06, (0.06 + b * 0.06).clamp(0.0, 1.0)),
      Offset(0.25, (0.25 + s * 0.08).clamp(0.0, 1.0)),
      Offset(0.75, (0.75 + h * 0.08).clamp(0.0, 1.0)),
      Offset(0.94, (0.94 + w * 0.06).clamp(0.0, 1.0)),
      Offset(1, math.min(1.0, 1 + w * 0.1)),
    ])));
  }
  _curves(text, layers);
  adjust(AdjustKind.clarity, {
    "clarity": n("Clarity2012") / 100,
    "dehaze": n("Dehaze") / 100,
  });
  adjust(AdjustKind.vibrance, {
    "vibrance": n("Vibrance") / 100,
    "saturation": n("Saturation") / 100,
  });
  adjust(AdjustKind.colourMixer, {
    for (var (lr, ours) in _bands) ...{
      "${ours}Hue": n("HueAdjustment$lr") / 100,
      "${ours}Sat": n("SaturationAdjustment$lr") / 100,
      "${ours}Lum": n("LuminanceAdjustment$lr") / 100,
    }
  });
  // Split toning, or colour grading's wheels: a hue and how much of it in
  // the shadows, midtones and highlights.
  (double, double, double) push(double hue, double amount) {
    var c = HSLColor.fromAHSL(1, hue % 360, 1, 0.5).toColor();
    var mean = (c.r + c.g + c.b) / 3;
    var k = amount / 100 * 1.6;
    return ((c.r - mean) * k, (c.g - mean) * k, (c.b - mean) * k);
  }

  var shadows = push(
      n(has("SplitToningShadowHue")
          ? "SplitToningShadowHue"
          : "ColorGradeShadowHue"),
      n(has("SplitToningShadowSaturation")
          ? "SplitToningShadowSaturation"
          : "ColorGradeShadowSat"));
  var mids = push(n("ColorGradeMidtoneHue"), n("ColorGradeMidtoneSat"));
  var highs = push(
      n(has("SplitToningHighlightHue")
          ? "SplitToningHighlightHue"
          : "ColorGradeHighlightHue"),
      n(has("SplitToningHighlightSaturation")
          ? "SplitToningHighlightSaturation"
          : "ColorGradeHighlightSat"));
  adjust(AdjustKind.colourBalance, {
    "shadowsRed": shadows.$1,
    "shadowsGreen": shadows.$2,
    "shadowsBlue": shadows.$3,
    "midsRed": mids.$1,
    "midsGreen": mids.$2,
    "midsBlue": mids.$3,
    "highsRed": highs.$1,
    "highsGreen": highs.$2,
    "highsBlue": highs.$3,
  });
  if (has("GrainAmount")) {
    var grain = ImageLayer.texturing(TextureKind.grain);
    layers.add(grain.copyWith(
        texture: grain.texture.copyWith(values: {
      "amount": (n("GrainAmount") / 100).clamp(0.0, 1.0),
      "size": 1 +
          (settings.containsKey("GrainSize") ? n("GrainSize") : 25) / 100 * 3,
    })));
  }
  if (has("PostCropVignetteAmount")) {
    var amount = n("PostCropVignetteAmount") / 100;
    var vignette = ImageLayer.texturing(TextureKind.vignette);
    layers.add(vignette.copyWith(
      opacity: amount.abs().clamp(0.0, 1.0),
      // Lightroom's lighter vignette is white, screened.
      blend: amount > 0 ? LayerBlend.screen : null,
      texture: vignette.texture.copyWith(
        colour: amount > 0 ? const Color(0xFFFFFFFF) : null,
        values: {
          "radius": (settings.containsKey("PostCropVignetteMidpoint")
                  ? n("PostCropVignetteMidpoint")
                  : 50) /
              100,
          "softness": (settings.containsKey("PostCropVignetteFeather")
                  ? n("PostCropVignetteFeather")
                  : 50) /
              100,
        },
      ),
    ));
  }

  var left = <String>{
    for (var e in settings.entries)
      if (!_carried.contains(e.key) &&
          !_bookkeeping.contains(e.key) &&
          !RegExp(r"^(Hue|Saturation|Luminance)Adjustment").hasMatch(e.key) &&
          !e.key.startsWith("ToneCurve") &&
          e.value.isNotEmpty &&
          e.value != "0" &&
          e.value != "+0" &&
          e.value.toLowerCase() != "false")
        _plain(e.key)
  }.toList()
    ..sort();
  if (layers.isEmpty) {
    return (null, "Nothing in that preset can be done here.");
  }
  const stand = ImageElement(
      ElementBase(id: "stand-in", width: 1000, height: 1000),
      assetId: "stand-in");
  return (
    LightroomPreset(
        name, lookData(stand.withLayers([ImageLayer.base, ...layers])), left),
    null
  );
}

/// _curves adds the preset's tone curves to [layers]: the whole curve and
/// each channel's, 0 to 255 in the file.
void _curves(String text, List<ImageLayer> layers) {
  var a = const ImageAdjustment(kind: AdjustKind.curves);
  var any = false;
  for (var (suffix, channel) in [
    ("", CurveChannel.rgb),
    ("Red", CurveChannel.red),
    ("Green", CurveChannel.green),
    ("Blue", CurveChannel.blue),
  ]) {
    var block = RegExp(
            "<crs:ToneCurvePV2012$suffix>(.*?)</crs:ToneCurvePV2012$suffix>",
            dotAll: true)
        .firstMatch(text)
        ?.group(1);
    if (block == null) continue;
    var points = <Offset>[
      for (var m in RegExp(r"<rdf:li>\s*([\d.]+)\s*,\s*([\d.]+)\s*</rdf:li>")
          .allMatches(block)
          .take(64))
        Offset(double.parse(m.group(1)!) / 255, double.parse(m.group(2)!) / 255)
    ];
    var straight = points.every((p) => (p.dx - p.dy).abs() < 1e-6);
    if (points.length < 2 || straight) continue;
    a = a.withCurve(channel, points);
    any = true;
  }
  if (any) {
    layers.add(ImageLayer.adjusting(AdjustKind.curves).copyWith(adjust: a));
  }
}

/// _plain is a setting's name in words: "LensProfileEnable" is "lens
/// profile enable".
String _plain(String key) => key
    .replaceAll(RegExp(r"2012$"), "")
    .replaceAllMapped(RegExp(r"(?<=[a-z])(?=[A-Z])"), (_) => " ")
    .toLowerCase();
