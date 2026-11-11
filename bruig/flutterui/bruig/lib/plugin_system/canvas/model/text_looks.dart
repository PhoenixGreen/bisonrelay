import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// text_looks.dart moves a text's own shadow, glow and outline -- set on its
// type, its words' and each piece's -- into looks on those layers (see
// MotionDevice.layer), so that each is kept in one place: the Chain's, which
// the panel shows too and the Chain can animate (Ken, 2026-11-11). Read as a
// text is read, so an old canvas, a pasted text and a saved design all come
// in with looks, drawn as they were.

/// textLayerChoices is what of [e] a look can be laid on, as (layer, name):
/// all of it, its own words, and each piece.
List<(String, String)> textLayerChoices(TextElement e) => [
      ("", "The whole text"),
      (MotionDevice.bodyLayer, "Its words"),
      for (var item in e.items) (item.id, item.says),
    ];

/// typeLooks is [spec]'s shadow, glow and outline as looks on [layer], drawn
/// as the type drew them: the outline under the letters, then the glow, then
/// the shadow behind both (softShadows).
List<MotionDevice> typeLooks(TextSpec spec, String layer) => [
      if (spec.outlineWidth > 0)
        MotionDevice(MotionDeviceKind.outline,
            values: {"width": spec.outlineWidth},
            colour: spec.outlineColor.toARGB32(),
            layer: layer),
      if (spec.glowBlur > 0)
        MotionDevice(MotionDeviceKind.glow,
            values: {"radius": _blurAsLook(spec.glowBlur), "strength": 1},
            colour: spec.glowColor.toARGB32(),
            layer: layer),
      if (spec.shadowBlur > 0 || spec.shadowDistance > 0)
        MotionDevice(MotionDeviceKind.shadow,
            values: {
              "distance": spec.shadowDistance,
              "blur": _blurAsLook(spec.shadowBlur),
              // The way it falls, where the type kept where the light comes
              // from; and turning with the text, as type shadows did.
              "angle": (spec.shadowAngle + 180) % 360,
              "strength": 1,
              "turns": 1,
            },
            colour: spec.shadowColor.toARGB32(),
            layer: layer),
    ];

/// withoutTypeLooks is [spec] with no shadow, glow or outline of its own.
TextSpec withoutTypeLooks(TextSpec spec) => spec.copyWith(
    outlineWidth: 0, shadowBlur: 0, shadowDistance: 0, glowBlur: 0);

/// hasTypeLooks is whether [spec] has a shadow, a glow or an outline.
bool hasTypeLooks(TextSpec spec) =>
    spec.outlineWidth > 0 ||
    spec.glowBlur > 0 ||
    spec.shadowBlur > 0 ||
    spec.shadowDistance > 0;

/// textLooksLifted is [e] with its words' and pieces' type looks moved to
/// looks on those layers; [e] itself where there are none. A layer that has
/// a look of that kind already has it set so instead, as restyling a text
/// does again and again (see CanvasController.updateTextStyle): one glow on
/// it, not one more each time.
TextElement textLooksLifted(TextElement e) {
  if (!hasTypeLooks(e.textSpec) && !e.items.any((i) => hasTypeLooks(i.spec))) {
    return e;
  }
  var looks = [
    ...typeLooks(e.textSpec, MotionDevice.bodyLayer),
    for (var item in e.items) ...typeLooks(item.spec, item.id),
  ];
  var motion = e.base.motion;
  var devices = [...motion.devices];
  for (var look in looks) {
    var i =
        devices.indexWhere((d) => d.layer == look.layer && d.kind == look.kind);
    if (i < 0) {
      devices.add(look);
    } else {
      var was = devices[i];
      devices[i] = MotionDevice(look.kind,
          on: was.on,
          values: {...was.values, ...look.values},
          id: was.id,
          colour: look.colour,
          layer: look.layer,
          mods: was.mods);
    }
  }
  return e.copyWith(
    textSpec: withoutTypeLooks(e.textSpec),
    items: [
      for (var item in e.items)
        hasTypeLooks(item.spec)
            ? item.copyWith(spec: withoutTypeLooks(item.spec))
            : item
    ],
  ).withBase(motion: motion.copyWith(devices: withMotionDeviceIds(devices)))
      as TextElement;
}

/// _blurAsLook is a type's blur radius as a look's blur: a text shadow's
/// radius is a spread of 0.58 of it and half a pixel (Flutter's Shadow),
/// a look's of half of it.
double _blurAsLook(double radius) =>
    radius <= 0 ? 0 : math.min(60, radius * 1.1547 + 1);
