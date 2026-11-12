import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/design_device.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart'
    show textLayerChoices;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/keys_strip.dart' show PhaseChip;
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show KeyDiamond, lookParamView, lookTakesColour;
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show chainMenuStyle;
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// chain_cards.dart is the Chain's cards in the settings panel's style (Ken,
// 2026-11-12, the approved chain prototype): a look's -- Glow, Shadow and
// the rest -- and the element's own Design. Each has a header with its
// switch, its name and what it is on; its A, L, Loop and I, which say where
// its keys play; and its settings in columns, each with a diamond that keys
// it at the playhead.

/// ChainCard is the frame every restyled Chain card is drawn in: a header,
/// its A, L, Loop and I where it has keys to play, and its settings,
/// scrolling where they are taller than the room.
class ChainCard extends StatelessWidget {
  final String id;
  final double width;
  final double height;
  final List<Widget> header;
  final Widget? phases;
  final Widget body;
  final bool off;
  final bool folded;
  final VoidCallback onFold;

  const ChainCard(
      {required this.id,
      required this.width,
      required this.height,
      required this.header,
      required this.body,
      required this.folded,
      required this.onFold,
      this.phases,
      this.off = false,
      super.key});

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    // As tall as the Chain's other cards (see DeviceFrame), its settings
    // scrolling where they need more.
    return SizedBox(
      height: height,
      child: Container(
        key: ValueKey("chainCard-$id"),
        width: folded ? 120 : width * scale,
        decoration: BoxDecoration(
          color: studio.strip,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: studio.edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: CanvasDense(
          height: 30,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: studio.edge))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                        height: 28,
                        child: Row(children: [
                          ...header,
                        ])),
                    if (phases != null && !folded) ...[
                      const SizedBox(height: 4),
                      phases!,
                    ],
                  ]),
            ),
            if (!folded)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: Opacity(opacity: off ? 0.5 : 1, child: body),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// chainCardName is a card's name in its header: pressed, it folds.
Widget chainCardName(BuildContext context, String name, VoidCallback onFold,
    {String? key}) {
  var studio = MixerLook.of(context).studio;
  return Expanded(
    child: GestureDetector(
      key: key == null ? null : ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onFold,
      child: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: studio.text)),
    ),
  );
}

/// chainCardKind is the small capitals after a card's name: what it is.
Widget chainCardKind(BuildContext context, String kind) {
  var studio = MixerLook.of(context).studio;
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Text(kind.toUpperCase(),
        style: TextStyle(
            fontSize: 10.5, letterSpacing: 0.84, color: studio.muted)),
  );
}

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

/// _labelled is [child] under [label], as a SettingCell's caption reads.
Widget _labelled(BuildContext context, String label, Widget child) {
  var studio = MixerLook.of(context).studio;
  return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
            height: 18,
            child: Text(label,
                style: TextStyle(fontSize: 11.5, color: studio.muted))),
        const SizedBox(height: 4),
        child,
      ]);
}

/// _cellWidth is each setting's width in a card [width] wide of [columns].
double _cellWidth(double width, int columns) =>
    ((width - 22 - (columns - 1) * 8) / columns).floorToDouble();

/// SettingCell is one setting of a card: its name, the diamond that keys
/// it at the playhead (gold where it is keyed, filled where a key is
/// here), and its stepper -- or, for a colour, its swatch.
class SettingCell extends StatelessWidget {
  final String device;
  final DeviceParam param;
  final String label;
  final double value;
  final bool keyed;
  final bool keyHere;
  final double width;
  final ValueChanged<double> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onKey;
  final VoidCallback? onRemove;
  final MotionDeviceKind kind;

  const SettingCell(
      {required this.device,
      required this.kind,
      required this.param,
      required this.label,
      required this.value,
      required this.keyed,
      required this.keyHere,
      required this.width,
      required this.onChanged,
      required this.onCommit,
      required this.onKey,
      this.onRemove,
      super.key});

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    const gold = Color(0xFFF2C14E);
    var accent = Theme.of(context).colorScheme.primary;
    var caption = Row(children: [
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: studio.muted)),
      ),
      const SizedBox(width: 2),
      Semantics(
        button: true,
        label:
            keyHere ? "Take the key here away: $label" : "Key it here: $label",
        child: InkWell(
          key: ValueKey("mdevKey-$device-${param.id}"),
          onTap: onKey,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: IconTheme(
              data: IconThemeData(color: keyed ? gold : studio.edge),
              child: KeyDiamond(filled: keyHere, size: 11),
            ),
          ),
        ),
      ),
      if (onRemove != null) ...[
        const Spacer(),
        InkWell(
          key: ValueKey("designRemove-${param.id}"),
          onTap: onRemove,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.close, size: 12, color: studio.muted),
          ),
        ),
      ],
    ]);
    Widget control;
    if (param.unit == "argb") {
      control = CanvasColorButton(
        key: ValueKey("mdev-$device-${param.id}"),
        label: "",
        color: Color(value.toInt()),
        onChanged: (c) {
          onChanged(c.toARGB32().toDouble());
          onCommit();
        },
      );
    } else if (param.isChoice) {
      control = CanvasDropdown<int>(
        key: ValueKey("mdev-$device-${param.id}"),
        label: "",
        value: value.round(),
        options: [for (var (i, ch) in param.choices.indexed) (i, ch)],
        onChanged: (v) {
          onChanged(v.toDouble());
          onCommit();
        },
      );
    } else {
      var view = lookParamView(kind, param);
      control = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border:
              keyed ? Border.all(color: accent.withValues(alpha: 0.6)) : null,
        ),
        child: CanvasStepper(
          key: ValueKey("mdev-$device-${param.id}"),
          name: "mdev-$device-${param.id}",
          label: "",
          fill: true,
          value: view.shown(value),
          min: view.shown(param.min),
          max: view.shown(param.max),
          decimals: view.decimals,
          suffix: view.suffix,
          onChanged: (v) => onChanged(view.stored(v)),
          onCommit: onCommit,
        ),
      );
    }
    return SizedBox(
      width: width,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 18, child: caption),
            const SizedBox(height: 4),
            CanvasCellFill(child: control),
          ]),
    );
  }
}

/// LookCard is a look of [element]'s Chain -- Glow, Shadow and the rest --
/// in the settings panel's style: its settings two to a row, each keyed
/// where it is.
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
    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var cell = _cellWidth(width * scale, 2);
    var wide = width * scale - 22;
    var layers = e is TextElement ? textLayerChoices(e) : null;
    var on = layers?.where((l) => l.$1 == d.layer).firstOrNull?.$2;
    Widget setting(DeviceParam p) => SettingCell(
          device: d.id,
          kind: d.kind,
          param: p,
          label: lookParamView(d.kind, p).label,
          value: c.deviceValueNow(e.id, d, p.id),
          keyed: d.keyed(p.id),
          keyHere: d.keyAt(p.id, t, spans: spans),
          width: p.isChoice ? wide : cell,
          onChanged: (v) =>
              c.setDeviceSetting(e.id, d.id, p.id, v, transient: true),
          onCommit: c.endInteraction,
          onKey: () => c.toggleDeviceKey(e.id, d.id, p.id),
        );
    return ChainCard(
      key: ValueKey("mdevCard-${d.id}"),
      id: d.id,
      width: width,
      height: height,
      folded: folded,
      onFold: onFold,
      off: !d.on,
      header: [
        CanvasSwitch(
          key: ValueKey("mdevPower-${d.id}"),
          value: d.on,
          onChanged: (v) {
            c.beginInteraction();
            c.setMotionDevices(e.id, [
              for (var x in c.motionDevicesOf(e.id))
                x.id == d.id ? x.switched(v) : x
            ]);
            c.endInteraction();
          },
        ),
        const SizedBox(width: 8),
        chainCardName(context, d.kind.label, onFold, key: "mdevName-${d.id}"),
        if (on != null && !folded)
          Container(
            constraints: const BoxConstraints(maxWidth: 84),
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
        _more(context),
      ],
      phases: PhaseButtons(controller: c, element: e.id, device: d),
      body: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var p in d.kind.params) setting(p),
        if (lookTakesColour(d.kind))
          SizedBox(
            width: wide,
            child: _labelled(
                context,
                "Colour",
                CanvasCellFill(
                  child: CanvasColorButton(
                    key: ValueKey("mdevColour-${d.id}"),
                    label: "",
                    color: Color(d.colour ?? 0xFF000000),
                    onChanged: (col) {
                      c.beginInteraction();
                      c.setMotionDevices(e.id, [
                        for (var x in c.motionDevicesOf(e.id))
                          x.id == d.id ? x.withColour(col.toARGB32()) : x
                      ]);
                      c.endInteraction();
                    },
                  ),
                )),
          ),
        if (layers != null)
          SizedBox(
            width: wide,
            child: _labelled(
                context,
                "On",
                CanvasCellFill(
                  child: CanvasDropdown<String>(
                    key: ValueKey("mdevLayer-${d.id}"),
                    label: "",
                    value: layers.any((l) => l.$1 == d.layer) ? d.layer : "",
                    options: layers,
                    onChanged: (v) {
                      c.beginInteraction();
                      c.setMotionDevices(e.id, [
                        for (var x in c.motionDevicesOf(e.id))
                          x.id == d.id ? x.withLayer(v) : x
                      ]);
                      c.endInteraction();
                    },
                  ),
                )),
          ),
      ]),
    );
  }

  Widget _more(BuildContext context) {
    var c = controller;
    var studio = MixerLook.of(context).studio;
    void remove() {
      c.beginInteraction();
      c.setMotionDevices(element.id, [
        for (var x in c.motionDevicesOf(element.id))
          if (x.id != device.id) x
      ]);
      c.endInteraction();
    }

    return MenuAnchor(
      style: chainMenuStyle(MixerLook.of(context)),
      builder: (context, menu, _) => SizedBox(
        width: 26,
        height: 26,
        child: IconButton(
          key: ValueKey("deviceMore-${device.id}"),
          padding: EdgeInsets.zero,
          iconSize: 16,
          icon: Icon(Icons.more_horiz, color: studio.muted),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      ),
      menuChildren: [
        MenuItemButton(
            key: ValueKey("mdevRemove-${device.id}"),
            onPressed: remove,
            child: const Text("Remove")),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: SizedBox(
            width: 220,
            child: Text(motionAbout(device.kind),
                style: TextStyle(fontSize: 11.5, color: studio.muted)),
          ),
        ),
      ],
    );
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
    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var cell = _cellWidth(width * scale, 3);
    var choices = designChoices(e);
    var free = [
      for (var (group, ids) in choices)
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
    Widget setting(String id) {
      var p = kind.param(id);
      return SettingCell(
        key: ValueKey("designSetting-$id"),
        device: d?.id ?? "design",
        kind: kind,
        param: p,
        label: p.label,
        value:
            d == null ? designRest(e, rest, id) : c.deviceValueNow(e.id, d, id),
        keyed: d?.keyed(id) ?? false,
        keyHere: d?.keyAt(id, t, spans: spans) ?? false,
        width: cell,
        onChanged: (v) => c.setDesignSetting(e.id, id, v, transient: true),
        onCommit: c.endInteraction,
        onKey: () => c.toggleDesignKey(e.id, id),
        onRemove: () => c.showDesignSetting(e.id, id, false),
      );
    }

    return ChainCard(
      key: const ValueKey("designCard"),
      id: "design",
      width: width,
      height: height,
      folded: folded,
      onFold: onFold,
      header: [
        chainCardName(context, "Design", onFold, key: "designName"),
        if (!folded) chainCardKind(context, "itself"),
      ],
      phases: Row(children: [
        PhaseButtons(
            controller: c,
            element: e.id,
            device: d,
            onNeed: () => c.ensureDesign(e.id)),
        const Spacer(),
        if (free.isNotEmpty)
          SizedBox(
            width: 128,
            child: CanvasDropdown<String>(
              key: const ValueKey("designAdd"),
              label: "",
              value: "",
              options: [
                ("", "+ Setting"),
                for (var (_, ids) in free)
                  for (var id in ids) (id, kind.param(id).label),
              ],
              // Grouped as the settings panel groups them.
              groupOf: (id) => id.isEmpty
                  ? ""
                  : free.firstWhere((g) => g.$2.contains(id)).$1,
              onChanged: (id) {
                if (id.isNotEmpty) c.showDesignSetting(e.id, id, true);
              },
            ),
          ),
      ]),
      body: shown.isEmpty
          ? Text("No settings yet: add one from + Setting.",
              style: TextStyle(fontSize: 11.5, color: studio.muted))
          : Wrap(spacing: 8, runSpacing: 8, children: [
              for (var id in shown) setting(id),
            ]),
    );
  }
}
