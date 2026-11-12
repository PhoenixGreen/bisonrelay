import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/design_device.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart'
    show textLayerChoices;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasColorButton;
import 'package:bruig/plugin_system/canvas/ui/keys_strip.dart' show PhaseChip;
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show KeyDiamond, lookTakesColour;
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// chain_cards.dart is the Chain's look cards -- Glow, Shadow and the rest --
// and the element's own Design (Ken, 2026-11-12, the approved chain
// prototype). They are DeviceFrames, drawn in ChainPanelStyle as every card
// of the Motion view is, with its knob-steppers and selects: one card, one
// stepper, one select across the Chain. Each has its A, L, Loop and I,
// which say where its keys play, over its settings; each setting a diamond
// on its corner that keys it at the playhead.

/// PhaseButtons are a card's A, L, Loop and I: where its keys play (Ken,
/// 2026-11-12). Each keeps its keys while it is off.
class PhaseButtons extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final MotionDevice? device;

  /// onNeed makes the device where there is none yet (Design): its id.
  final String Function()? onNeed;

  const PhaseButtons(
      {required this.controller,
      required this.element,
      required this.device,
      this.onNeed,
      super.key});

  @override
  Widget build(BuildContext context) {
    var d = device;
    return Wrap(spacing: 3, runSpacing: 3, children: [
      for (var ph in MotionPhase.values)
        PhaseChip(
            key: ValueKey("phase-${d?.id ?? "design"}-${ph.name}"),
            phase: ph,
            on: d == null ? ph == MotionPhase.free : d.playing(ph),
            onTap: () {
              var id = d?.id ?? onNeed?.call();
              if (id == null) return;
              var now = controller
                  .motionDevicesOf(element)
                  .where((x) => x.id == id)
                  .firstOrNull;
              if (now == null) return;
              controller.setDevicePlays(element, id, ph, !now.playing(ph));
            }),
    ]);
  }
}

/// keyedSetting is one setting of a card: the Chain's knob-stepper (see
/// DeviceKnob), and on its corner the diamond that keys it at the playhead
/// -- gold where it is keyed, filled where a key is here -- and, given
/// [onRemove], the cross that takes it off its card. A colour is its
/// swatch, a choice its select.
Widget keyedSetting(
  BuildContext context, {
  required String device,
  required DeviceParam param,
  required double value,
  required bool keyed,
  required bool keyHere,
  required void Function(double v, {bool transient}) onChanged,
  required VoidCallback onCommit,
  required VoidCallback onKey,
  VoidCallback? onRemove,
  Key? key,
}) {
  var studio = MixerLook.of(context).studio;
  const gold = Color(0xFFF2C14E);
  var corner = Row(mainAxisSize: MainAxisSize.min, children: [
    GestureDetector(
      key: ValueKey("mdevKey-$device-${param.id}"),
      behavior: HitTestBehavior.opaque,
      onTap: onKey,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: IconTheme(
          data: IconThemeData(
              color: keyed ? gold : studio.muted.withValues(alpha: 0.6)),
          child: KeyDiamond(filled: keyHere, size: 10),
        ),
      ),
    ),
    if (onRemove != null)
      GestureDetector(
        key: ValueKey("designRemove-${param.id}"),
        behavior: HitTestBehavior.opaque,
        onTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.close, size: 12, color: studio.muted),
        ),
      ),
  ]);
  Widget control;
  if (param.unit == "argb") {
    control = Column(
        key: ValueKey("mdev-$device-${param.id}"),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              height: 18,
              child: Text(param.label,
                  style: TextStyle(fontSize: 11.5, color: studio.muted))),
          const SizedBox(height: 4),
          CanvasColorButton(
            label: "",
            color: Color(value.toInt()),
            onChanged: (c) {
              onChanged(c.toARGB32().toDouble());
              onCommit();
            },
          ),
        ]);
  } else if (param.isChoice) {
    control = StudioDrop<int>(
      key: ValueKey("mdev-$device-${param.id}"),
      label: param.label,
      value: value.round(),
      width: double.infinity,
      options: [for (var (i, ch) in param.choices.indexed) (i, ch)],
      onChanged: (v) {
        onChanged(v.toDouble());
        onCommit();
      },
    );
  } else {
    control = DeviceKnob(
      key: ValueKey("mdev-$device-${param.id}"),
      label: param.label,
      text: param.reading(value),
      value: value.clamp(param.min, param.max).toDouble(),
      initial: param.initial,
      min: param.min,
      max: param.max,
      step: paramStep(param),
      automated: keyed,
      bipolar: param.min < 0 && param.max > 0,
      accent: Theme.of(context).colorScheme.primary,
      ink: studio.text,
      onChanged: onChanged,
      onCommit: onCommit,
    );
  }
  // The knob first: it takes a cell of the card (see DeviceFrame._isCell).
  return Stack(key: key, clipBehavior: Clip.none, children: [
    control,
    Positioned(top: -2, right: -2, child: corner),
  ]);
}

/// LookCard is a look of [element]'s Chain -- Glow, Shadow and the rest:
/// its switch and what it is on in its header, its A, L, Loop and I, and
/// its settings two to a row, each keyed where it is.
class LookCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionDevice device;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  static const width = 236.0;

  const LookCard(
      {required this.controller,
      required this.element,
      required this.device,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var d = device;
    var e = element;
    var studio = MixerLook.of(context).studio;
    var t = c.playheadSeconds;
    var spans = c.phaseSpansFor(e.id);
    var layers = e is TextElement ? textLayerChoices(e) : null;
    var on = layers?.where((l) => l.$1 == d.layer).firstOrNull?.$2;
    void write(MotionDevice next) {
      c.beginInteraction();
      c.setMotionDevices(e.id,
          [for (var x in c.motionDevicesOf(e.id)) x.id == d.id ? next : x]);
      c.endInteraction();
    }

    List<Widget> controls(DeviceTier tier) => [
          for (var p in d.kind.params)
            if (!p.isChoice)
              keyedSetting(context,
                  device: d.id,
                  param: p,
                  value: c.deviceValueNow(e.id, d, p.id),
                  keyed: d.keyed(p.id),
                  keyHere: d.keyAt(p.id, t, spans: spans),
                  onChanged: (v, {transient = false}) => c.setDeviceSetting(
                      e.id, d.id, p.id, v,
                      transient: transient),
                  onCommit: c.endInteraction,
                  onKey: () => c.toggleDeviceKey(e.id, d.id, p.id)),
          for (var p in d.kind.params)
            if (p.isChoice)
              StudioDrop<int>(
                key: ValueKey("mdev-${d.id}-${p.id}"),
                label: p.label,
                value: d.value(p.id).round(),
                width: double.infinity,
                options: [for (var (i, ch) in p.choices.indexed) (i, ch)],
                onChanged: (v) => write(d.withValue(p.id, v.toDouble())),
              ),
          if (lookTakesColour(d.kind))
            Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      height: 18,
                      child: Text("Colour",
                          style:
                              TextStyle(fontSize: 11.5, color: studio.muted))),
                  const SizedBox(height: 4),
                  CanvasColorButton(
                    key: ValueKey("mdevColour-${d.id}"),
                    label: "",
                    color: Color(d.colour ?? 0xFF000000),
                    onChanged: (col) => write(d.withColour(col.toARGB32())),
                  ),
                ]),
          if (layers != null)
            StudioDrop<String>(
              key: ValueKey("mdevLayer-${d.id}"),
              label: "On",
              value: layers.any((l) => l.$1 == d.layer) ? d.layer : "",
              width: double.infinity,
              options: layers,
              onChanged: (v) => write(d.withLayer(v)),
            ),
        ];

    return KeyedSubtree(
        key: ValueKey("mdevCard-${d.id}"),
        child: DeviceFrame(
          id: d.id,
          title: d.kind.label,
          skin: DeviceSkin.studio(studio),
          on: d.on,
          onPower: (v) => write(d.switched(v)),
          powerKey: ValueKey("mdevPower-${d.id}"),
          folded: folded,
          onFold: onFold,
          width: width,
          height: height,
          help: motionAbout(d.kind),
          summary: d.kind.label,
          foldedBody: const SizedBox(),
          body: const SizedBox.shrink(),
          barExtras: [
            if (on != null)
              Container(
                constraints: const BoxConstraints(maxWidth: 84),
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: studio.edge),
                ),
                child: Text(on,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: studio.text)),
              ),
          ],
          actions: [
            // Behind its ⋯, as every card's way out.
            IconButton(
              key: ValueKey("mdevRemove-${d.id}"),
              tooltip: "Remove",
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                c.beginInteraction();
                c.setMotionDevices(e.id, [
                  for (var x in c.motionDevicesOf(e.id))
                    if (x.id != d.id) x
                ]);
                c.endInteraction();
              },
            ),
          ],
          lead: [PhaseButtons(controller: c, element: e.id, device: d)],
          controls: controls,
        ));
  }
}

/// DesignCard is the element itself in its Chain (Ken, 2026-11-12): its
/// Design device's settings -- where it is, its turn, size and fade, and
/// any of its settings panel's added from + Setting -- three to a row, each
/// keyed where it is. It stands where the element is drawn, moves before
/// it and looks after it. With no Design device yet, the first change or
/// key makes one.
class DesignCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  static const width = 404.0;

  const DesignCard(
      {required this.controller,
      required this.element,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var e = element;
    var studio = MixerLook.of(context).studio;
    var d = c.designOf(e.id);
    var shown = d?.shown.isNotEmpty == true ? d!.shown : designShownDefault;
    var t = c.playheadSeconds;
    var spans = c.phaseSpansFor(e.id);
    var free = [
      for (var (group, ids) in designChoices(e))
        (
          group,
          [
            for (var id in ids)
              if (!shown.contains(id)) id
          ]
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    const kind = MotionDeviceKind.design;
    var rest = d ?? const MotionDevice(kind);

    List<Widget> controls(DeviceTier tier) => [
          if (shown.isEmpty)
            Text("No settings yet: add one from + Setting.",
                style: TextStyle(fontSize: 11.5, color: studio.muted)),
          for (var id in shown)
            keyedSetting(context,
                key: ValueKey("designSetting-$id"),
                device: d?.id ?? "design",
                param: kind.param(id),
                value: d == null
                    ? designRest(e, rest, id)
                    : c.deviceValueNow(e.id, d, id),
                keyed: d?.keyed(id) ?? false,
                keyHere: d?.keyAt(id, t, spans: spans) ?? false,
                onChanged: (v, {transient = false}) =>
                    c.setDesignSetting(e.id, id, v, transient: transient),
                onCommit: c.endInteraction,
                onKey: () => c.toggleDesignKey(e.id, id),
                onRemove: () => c.showDesignSetting(e.id, id, false)),
        ];

    return KeyedSubtree(
      key: const ValueKey("designCard"),
      child: DeviceFrame(
        id: "design",
        title: "Design",
        skin: DeviceSkin.studio(studio),
        folded: folded,
        onFold: onFold,
        width: width,
        height: height,
        help: motionAbout(kind),
        summary: "Design",
        foldedBody: const SizedBox(),
        body: const SizedBox.shrink(),
        lead: [
          Row(children: [
            PhaseButtons(
                controller: c,
                element: e.id,
                device: d,
                onNeed: () => c.ensureDesign(e.id)),
            const Spacer(),
            if (free.isNotEmpty)
              StudioDrop<String>(
                key: const ValueKey("designAdd"),
                label: "",
                value: "",
                width: 132,
                options: [
                  ("", "+ Setting"),
                  for (var (group, ids) in free)
                    for (var id in ids)
                      (id, "$group · ${kind.param(id).label}"),
                ],
                onChanged: (id) {
                  if (id.isNotEmpty) c.showDesignSetting(e.id, id, true);
                },
              ),
          ]),
        ],
        controls: controls,
      ),
    );
  }
}
