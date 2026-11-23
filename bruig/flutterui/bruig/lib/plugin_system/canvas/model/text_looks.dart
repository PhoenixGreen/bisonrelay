import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// text_looks.dart moves a text's own shadow, glow and outline (on its type,
// its words' and each piece's) into looks on those layers (see
// MotionDevice.layer), so each lives in one place: the Chain, which the
// panel shows too and can animate. Read as a text is read, so an old
// canvas, a pasted text and a saved design all come in with looks.

/// textLayerChoices is what of [e] a look can be laid on, each a layer
/// (MotionDevice.layer) and its name: all of it, its own words, and each
/// piece.
List<({String layer, String name})> textLayerChoices(TextElement e) => [
      (layer: "", name: "The whole text"),
      (layer: MotionDevice.bodyLayer, name: "Its words"),
      for (var item in e.items) (layer: item.id, name: item.says),
    ];

/// _typeLooks is [spec]'s shadow, glow and outline as looks on [layer], drawn
/// as the type drew them: the outline under the letters, then the glow, then
/// the shadow behind both (softShadows).
List<MotionDevice> _typeLooks(TextSpec spec, String layer) => [
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
              // The way it falls, from where the type kept the light; and
              // turning with the text, as type shadows do.
              "angle": (spec.shadowAngle + 180) % 360,
              "strength": 1,
              "turns": 1,
            },
            colour: spec.shadowColor.toARGB32(),
            layer: layer),
    ];

/// _withoutTypeLooks is [spec] with no shadow, glow or outline of its own.
TextSpec _withoutTypeLooks(TextSpec spec) => spec.copyWith(
    outlineWidth: 0, shadowBlur: 0, shadowDistance: 0, glowBlur: 0);

/// hasTypeLooks is whether [spec] has a shadow, a glow or an outline.
bool hasTypeLooks(TextSpec spec) =>
    spec.outlineWidth > 0 ||
    spec.glowBlur > 0 ||
    spec.shadowBlur > 0 ||
    spec.shadowDistance > 0;

/// typeFollowsStyle is whether type [own] is still [style]'s: the same but
/// for a shadow, glow or outline, which a text holds as looks once read
/// (see textLooksLifted) while the style keeps them in its type. Its fill
/// is compared by its saved form, as a pattern has no equality of its own.
bool typeFollowsStyle(TextSpec own, TextSpec style) =>
    _withoutTypeLooks(own) == _withoutTypeLooks(style) &&
    jsonEncode(own.fill.toJson()) == jsonEncode(style.fill.toJson());

/// textLooksLifted is [e] with its words' and pieces' type looks moved to
/// looks on those layers; [e] itself where there are none. A layer that has
/// a look of that kind already has it set instead, so restyling a text
/// again and again (CanvasController.updateTextStyle) leaves one glow.
TextElement textLooksLifted(TextElement e) {
  if (!hasTypeLooks(e.textSpec) && !e.items.any((i) => hasTypeLooks(i.spec))) {
    return e;
  }
  var looks = [
    ..._typeLooks(e.textSpec, MotionDevice.bodyLayer),
    for (var item in e.items) ..._typeLooks(item.spec, item.id),
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
          keys: was.keys,
          mods: was.mods);
    }
  }
  return e.copyWith(
    textSpec: _withoutTypeLooks(e.textSpec),
    items: [
      for (var item in e.items)
        hasTypeLooks(item.spec)
            ? item.copyWith(spec: _withoutTypeLooks(item.spec))
            : item
    ],
  ).withBase(motion: motion.copyWith(devices: withMotionDeviceIds(devices)))
      as TextElement;
}

/// withPieceLooks is [e] after piece [id] was removed or copied: its looks
/// taken off with it, or, given [copiedTo], laid on the copy too, each look
/// after the one it copies and with an id of its own. A piece's looks are
/// keyed by its id, so they do not follow it unasked.
TextElement withPieceLooks(TextElement e, String id, {String? copiedTo}) {
  var devices = e.base.motion.devices;
  if (!devices.any((d) => d.layer == id)) return e;
  var next = [
    for (var d in devices)
      if (d.layer != id)
        d
      else if (copiedTo != null) ...[
        d,
        d.withId("").withLayer(copiedTo),
      ],
  ];
  return e.withBase(
          motion: e.base.motion.copyWith(devices: withMotionDeviceIds(next)))
      as TextElement;
}

/// _blurAsLook is a type's blur radius as a look's blur: a text shadow's
/// radius is a spread of 0.58 of it and half a pixel (Flutter's Shadow),
/// a look's of half of it.
double _blurAsLook(double radius) =>
    radius <= 0 ? 0 : math.min(60, radius * 1.1547 + 1);
