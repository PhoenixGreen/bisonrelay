import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_icons.dart';
import 'package:bruig/plugin_system/canvas/model/strip_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/device_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart'
    show ScopeReading;
import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart'
    show Wave, correlation;
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show MidiMonitor, noInput, instrumentKnobs, instrumentTarget;
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart'
    show SpeechSpec, VocaliserSpec;
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart'
    show GainPoint, envelopeAt;
import 'package:bruig/plugin_system/canvas/model/audio_tools.dart'
    show duckEnvelope;
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show lookAtCamera, lookAtPointer, motionSpeedAt, retimed;
import 'package:bruig/plugin_system/canvas/render/motion_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/automation_lanes.dart'
    show automationColour;
import 'package:bruig/plugin_system/canvas/ui/autotune_card.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasDropdown;
import 'package:bruig/plugin_system/canvas/ui/device_screens.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

// mixer_plugins.dart is a strip's effects as devices in a chain, as in
// Ableton: the Channel EQ and Compressor as Logic has them, a limiter and
// meters, in the order the sound goes through them. Each folds to its
// switch, its name and a meter. A device keeps its own colours whatever the
// app's theme, as a hardware unit does, and is drawn at deviceHeight and
// scaled to the chain's room, never laid out again.

/// dragPointers are what may drag a value -- a fader, a dial, a knob: the
/// mouse, a finger, a pen; never the trackpad. A drag recognizer takes a
/// trackpad's two-finger swipe as a drag, so swiping past a fader moved it.
/// Clicked and dragged on a trackpad is the mouse's, and still works.
const Set<PointerDeviceKind> dragPointers = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

/// deviceHeight is the height every device is drawn at, before it is scaled
/// to the chain.
const double deviceHeight = 320;

/// deviceFoldedWidth is a folded device's width, before scaling.
const double deviceFoldedWidth = 34;

/// DeviceSkin is a device's colours.
class DeviceSkin {
  final Decoration body;
  final Color header;
  final Color ink;
  final Color dim;
  const DeviceSkin(
      {required this.body,
      required this.header,
      required this.ink,
      required this.dim});

  static const navy = DeviceSkin(
    body: BoxDecoration(color: _eqBack),
    header: Color(0xFF1B2838),
    ink: _eqInk,
    dim: _eqDim,
  );

  static const silver = DeviceSkin(
    body: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE4E6EA), Color(0xFFBFC3CA)])),
    header: Color(0xFF3A3F47),
    ink: _silverInk,
    dim: _silverDim,
  );

  /// studio is the Chain's card, in the studio palette: a raised header, the
  /// body a shade under it, and its text and labels.
  static DeviceSkin studio(StudioColors s) => DeviceSkin(
        body: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.12],
                colors: [Color.lerp(s.raised, s.strip, 0.4)!, s.strip])),
        header: Color.lerp(s.raised, s.strip, 0.2)!,
        ink: s.text,
        dim: s.muted,
      );

  /// themed is the app's own colours, for the devices that are settings
  /// rather than a unit: ducking and loudness.
  static DeviceSkin themed(ColorScheme c) => DeviceSkin(
        body: BoxDecoration(color: c.surfaceContainerHigh),
        header: c.surfaceContainerHighest,
        ink: c.onSurface,
        dim: c.onSurfaceVariant,
      );
}

/// DeviceTier is how much a device shows at the height the chain gives it:
/// everything when tall, less as the panel is made shorter -- the knobs on
/// one row, then only a line saying what it is set to. See DeviceFrame.
enum DeviceTier {
  large,
  medium,
  small,
  strip;

  static DeviceTier of(double height) => height > 300
      ? large
      : height > 205
          ? medium
          : height > 120
              ? small
              : strip;
}

/// midiColour is the colour of what carries notes: a MIDI channel's
/// effects, its In and its instrument, as the prototype has them.
const midiColour = Color(0xFFD08F3E);

/// deviceGroupLook is a family of devices' mark: its icon in a device's bar
/// and the colour of the stripe along its top.
(IconData, Color) deviceGroupLook(DeviceGroup group) => switch (group) {
      DeviceGroup.space => (Icons.blur_circular, const Color(0xFF6FA8E8)),
      DeviceGroup.dynamics => (Icons.compress, const Color(0xFFE0A84F)),
      DeviceGroup.filter => (
          Icons.filter_alt_outlined,
          const Color(0xFF5CC6B8)
        ),
      DeviceGroup.modulation => (Icons.waves, const Color(0xFFB98AE8)),
      DeviceGroup.drive => (Icons.whatshot_outlined, const Color(0xFFE07A5F)),
      DeviceGroup.pitch => (Icons.music_note, const Color(0xFFE57AA8)),
      DeviceGroup.utility => (Icons.tune, const Color(0xFFA7A3B8)),
      DeviceGroup.analysers => (Icons.insights, const Color(0xFF7FC8F8)),
      // Pink, as the rings round the knobs they move.
      DeviceGroup.modulators => (Icons.swap_vert, modulationColour),
    };

/// deviceMoveButtons are the arrows in a device's bar that move it a place
/// along strip [owner]'s chain, keyed deviceLeft-[index] and
/// deviceRight-[index]; an arrow that has nowhere to go is greyed out.
List<Widget> deviceMoveButtons(
    CanvasController c, String owner, int index, Color ink) {
  var devices = c.devicesOf(owner);
  if (index >= devices.length) return const [];
  var id = deviceIdAt(devices, index), name = devices[index].kind.label;
  // Its place in the chain, the EQ and compressor among the devices.
  var chain = c.chainOf(owner);
  var at = chain.indexOf(id);
  if (at < 0 || chain.length < 2) return const [];
  Widget arrow(int by, IconData icon, String side) => IconButton(
        key: ValueKey("device${by < 0 ? "Left" : "Right"}-$index"),
        tooltip: "Move the ${name.toLowerCase()} $side",
        iconSize: 14,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: ink),
        onPressed: at + by < 0 || at + by >= chain.length
            ? null
            : () => c.moveDevice(owner, id, by),
      );
  return [
    arrow(-1, Icons.chevron_left, "left"),
    arrow(1, Icons.chevron_right, "right"),
  ];
}

/// MacroPanel is a chain's Macros (Ken, 2026-11-08: "it's not obvious how
/// to set up the macros -- Macro 1, what is it set to, what can it be set
/// to, and how can it be set?"): eight knobs, each saying what it turns
/// under it; one picked, what it turns listed, each with how far, and any
/// knob of the chain to add to it.
class MacroPanel extends StatefulWidget {
  final int index;
  final MixDevice device;

  /// knobs are every knob of the chain a macro can turn: the device's id,
  /// the setting's, and its name ("Reverb · Size").
  final List<(String, String, String)> knobs;
  final Color accent, ink;
  final void Function(MixDevice next, {bool transient}) onChanged;
  final VoidCallback onCommit;
  const MacroPanel(
      {required this.index,
      required this.device,
      required this.knobs,
      required this.accent,
      required this.ink,
      required this.onChanged,
      required this.onCommit,
      super.key});

  /// width is its card's: eight knobs across.
  static const double width = 14.0 + 58 * macroKnobs;

  @override
  State<MacroPanel> createState() => _MacroPanelState();
}

class _MacroPanelState extends State<MacroPanel> {
  int _picked = 0;

  String _nameOf(ModTarget m) =>
      widget.knobs
          .where((k) => k.$1 == m.device && k.$2 == m.param)
          .firstOrNull
          ?.$3 ??
      "Gone";

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var device = widget.device;
    var index = widget.index;
    var mods = device.mods;
    var picked = _picked.clamp(0, macroKnobs - 1);
    var accent = widget.accent;
    // What each turns, by knob.
    List<(int, ModTarget)> turnedBy(int k) => [
          for (var (j, m) in mods.indexed)
            if (m.from == k) (j, m),
        ];
    Widget column(int k) {
      var p = macroParams[k];
      var turns = turnedBy(k);
      var on = k == picked;
      var first = turns.isEmpty ? null : _nameOf(turns.first.$2);
      var short = first == null
          ? "Not set"
          : first.contains(" · ")
              ? first.substring(first.lastIndexOf(" · ") + 3)
              : first;
      return GestureDetector(
        key: ValueKey("macroPick-$index-$k"),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _picked = k),
        child: Container(
          width: 56,
          padding: const EdgeInsets.only(top: 3, bottom: 3),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? accent : Colors.transparent),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Knob(
              key: ValueKey("device-$index-${p.id}"),
              label: "Macro ${k + 1}",
              text: p.reading(device.value(p.id)),
              value: device.value(p.id),
              initial: p.initial,
              range: _Range(p.min, p.max),
              size: 26,
              accent: accent,
              ink: widget.ink,
              onChanged: (v, {transient = false}) =>
                  widget.onChanged(device.withValue(p.id, v),
                      transient: transient),
              onCommit: widget.onCommit,
            ),
            const SizedBox(height: 2),
            // What it turns, in a word: the first, and how many more.
            Text(
                turns.length > 1 ? "$short +${turns.length - 1}" : short,
                key: ValueKey("macroTurns-$index-$k"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
                    color: first == null
                        ? studio.muted.withValues(alpha: 0.7)
                        : modulationColour)),
          ]),
        ),
      );
    }

    var turns = turnedBy(picked);
    var free = [
      for (var k in widget.knobs)
        if (!turns.any((t) => t.$2.device == k.$1 && t.$2.param == k.$2)) k,
    ];
    // The chain's knobs, by device: what the picked macro can be given.
    var byDevice = <String, List<(String, String, String)>>{};
    for (var k in free) {
      var cut = k.$3.lastIndexOf(" · ");
      var owner = cut < 0 ? k.$3 : k.$3.substring(0, cut);
      (byDevice[owner] ??= []).add(k);
    }
    var add = MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, "Macro ${picked + 1} turns…"),
        for (var MapEntry(key: owner, value: list) in byDevice.entries)
          SubmenuButton(
            key: ValueKey("macroAddDevice-$index-$owner"),
            style: chainMenuItemStyle(look),
            menuStyle: chainMenuStyle(look),
            menuChildren: [
              for (var k in list)
                chainMenuItem(look,
                    key: ValueKey("macroAddKnob-$index-${k.$1}-${k.$2}"),
                    text: k.$3.substring(owner.length).replaceFirst(" · ", ""),
                    onPressed: () => widget.onChanged(device.withMods([
                          ...mods,
                          ModTarget(k.$1, k.$2, 0.5, picked),
                        ]))),
            ],
            child: Text(owner, style: const TextStyle(fontSize: 11.5)),
          ),
        if (byDevice.isEmpty)
          chainMenuHeading(look, "Nothing more in this chain to turn"),
      ],
      builder: (context, menu, _) => InkWell(
        key: ValueKey("macroAdd-$index"),
        borderRadius: BorderRadius.circular(5),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: studio.edge)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, size: 13, color: studio.muted),
            const SizedBox(width: 3),
            Text("Add a knob to turn",
                style: TextStyle(fontSize: 10.5, color: studio.text)),
            Icon(Icons.arrow_drop_down, size: 14, color: studio.muted),
          ]),
        ),
      ),
    );

    return SizedBox(
      width: MacroPanel.width - 16,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var k = 0; k < macroKnobs; k++) column(k),
            ]),
            const SizedBox(height: 6),
            // The picked one: what it turns, and how far each.
            Container(
              key: ValueKey("macroTurnsPanel-$index"),
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              decoration: BoxDecoration(
                color: studio.inset,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: studio.edge),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text("MACRO ${picked + 1} TURNS",
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w600,
                                color: studio.muted)),
                      ),
                      add,
                    ]),
                    const SizedBox(height: 4),
                    if (turns.isEmpty)
                      Text(
                          "Nothing yet. Add a knob for it to turn -- any "
                          "knob of this chain -- or right-click a knob and "
                          "pick Macro ${picked + 1}.",
                          style: TextStyle(
                              fontSize: 10.5,
                              height: 1.35,
                              color: studio.muted))
                    else
                      for (var (j, m) in turns)
                        SizedBox(
                          key: ValueKey("macroTarget-$index-$j"),
                          height: 26,
                          child: Row(children: [
                            Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                    color: modulationColour,
                                    shape: BoxShape.circle)),
                            Expanded(
                              child: Text(_nameOf(m),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: studio.text)),
                            ),
                            // How far it turns it: either way.
                            SizedBox(
                              width: 120,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    activeTrackColor: modulationColour,
                                    thumbColor: modulationColour,
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 5)),
                                child: Slider(
                                  key: ValueKey("macroDepth-$index-$j"),
                                  value: m.depth.clamp(-1.0, 1.0),
                                  min: -1,
                                  max: 1,
                                  onChanged: (v) => widget.onChanged(
                                      device.withMods([...mods]..[j] =
                                          m.withDepth(
                                              (v * 20).roundToDouble() / 20)),
                                      transient: true),
                                  onChangeEnd: (_) => widget.onCommit(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 38,
                              child: Text(
                                  "${m.depth >= 0 ? "+" : "−"}${(m.depth.abs() * 100).round()}%",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                      color: studio.text)),
                            ),
                            GestureDetector(
                              key: ValueKey("macroRemove-$index-$j"),
                              onTap: () => widget.onChanged(
                                  device.withMods([...mods]..removeAt(j))),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.close,
                                    size: 13, color: studio.muted),
                              ),
                            ),
                          ]),
                        ),
                  ]),
            ),
          ]),
    );
  }
}

/// DashedAddButton is a narrow dashed "+" where something can go, added at
/// once on a click: the Macros zone of a chain with none (Ken: narrow, not
/// an "Add macros" card).
class DashedAddButton extends StatelessWidget {
  final String tip;
  final double height;
  final VoidCallback onTap;
  const DashedAddButton(
      {required this.tip,
      required this.height,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: height,
          child: CustomPaint(
            painter: _DashedSlot(look.studio.edge),
            child: Center(
              child: Icon(Icons.add, size: 15, color: look.studio.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// _PresetPicker is a card's preset on its bar, as the prototype's
/// "Default ▾": the saved presets of its kind to put on it, Default to
/// start again from, and Save.
class _PresetPicker extends StatefulWidget {
  final DeviceKind kind;
  final String? name;
  final void Function(String name, MixDevice preset) onPick;
  final VoidCallback onDefault;
  final VoidCallback onSave;
  const _PresetPicker(
      {required this.kind,
      required this.name,
      required this.onPick,
      required this.onDefault,
      required this.onSave,
      super.key});

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var kept = [
      for (var p in devicePresets.presets)
        if (presetDevices(p.data) case [var d] when d.kind == widget.kind)
          (p.name, d),
    ];
    return MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, "${widget.kind.label} presets"),
        chainMenuItem(look,
            key: const ValueKey("presetDefault"),
            text: "Default",
            current: widget.name == null,
            onPressed: widget.onDefault),
        for (var (name, d) in kept)
          chainMenuItem(look,
              key: ValueKey("preset-$name"),
              text: name,
              current: widget.name == name,
              onPressed: () => widget.onPick(name, d)),
        chainMenuDivider(look),
        chainMenuItem(look,
            key: const ValueKey("presetSave"),
            text: "Save these settings as a preset",
            onPressed: widget.onSave),
      ],
      builder: (context, menu, _) => GestureDetector(
        key: widget.key == null
            ? null
            : ValueKey("${(widget.key as ValueKey).value}-open"),
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          if (menu.isOpen) {
            menu.close();
            return;
          }
          await devicePresets.load();
          if (!mounted) return;
          setState(() {});
          menu.open();
        },
        child: _presetLabel(context, widget.name ?? "Default", studio),
      ),
    );
  }
}

/// _FoldedLevel is a folded device's level as the sound leaves it -- the
/// join after it, [at] -- as a slim meter at the foot of its card, as the
/// prototype's folded cards have.
class _FoldedLevel extends StatefulWidget {
  final CanvasController controller;
  final String owner;
  final int at;
  const _FoldedLevel(
      {required this.controller,
      required this.owner,
      required this.at,
      super.key});

  @override
  State<_FoldedLevel> createState() => _FoldedLevelState();
}

class _FoldedLevelState extends State<_FoldedLevel>
    with SingleTickerProviderStateMixin, _Metered {
  double _db = -90;

  @override
  CanvasController get meteredBy => widget.controller;

  @override
  void tick() {
    var taps = widget.controller.deviceLevels(widget.owner);
    var at = widget.at;
    _db = at > 0 && at < taps.length
        ? gainToDb(math.max(taps[at].$1, taps[at].$2))
        : -90;
  }

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var u = ((_db + 60) / 60).clamp(0.0, 1.0);
    return Center(
      child: Container(
        width: 6,
        margin: const EdgeInsets.symmetric(vertical: 4),
        alignment: Alignment.bottomCenter,
        decoration: BoxDecoration(
            color: studio.display, borderRadius: BorderRadius.circular(3)),
        child: FractionallySizedBox(
          heightFactor: u,
          child: Container(
            decoration: BoxDecoration(
                color: _db >= 0
                    ? const Color(0xFFE5484D)
                    : const Color(0xFF3FB08D),
                borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
    );
  }
}

/// _PresetCompact tells a preset picker under it to show its mark alone,
/// its name in its tooltip: a card too narrow for "Default ▾".
class _PresetCompact extends InheritedWidget {
  const _PresetCompact({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PresetCompact>() != null;

  @override
  bool updateShouldNotify(_PresetCompact old) => false;
}

/// _presetLabel is a preset picker's face: "Default ▾", or -- compact --
/// its mark alone, the preset's name in its tooltip.
Widget _presetLabel(BuildContext context, String name, StudioColors studio) {
  if (_PresetCompact.of(context)) {
    return Tooltip(
      message: "Presets: $name",
      child: Container(
        width: 18,
        height: 16,
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: studio.edge)),
        child: Icon(Icons.tune, size: 11, color: studio.muted),
      ),
    );
  }
  return Container(
    constraints: const BoxConstraints(maxWidth: 82),
    height: 16,
    margin: const EdgeInsets.only(right: 3),
    padding: const EdgeInsets.only(left: 5, right: 1),
    decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: studio.edge)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, height: 1.1, color: studio.muted)),
      ),
      Icon(Icons.arrow_drop_down, size: 12, color: studio.muted),
    ]),
  );
}

/// worksOnMenu is a card's ⋯ "Works on": the whole sound, only its
/// middle (what both sides share) or only its sides (where they differ),
/// as [value] says -- for a device, and a strip's EQ and compressor.
Widget worksOnMenu(MixerLook look,
        {required String id,
        required int value,
        required ValueChanged<int> onPick}) =>
    SubmenuButton(
      key: ValueKey(id),
      style: chainMenuItemStyle(look),
      menuStyle: chainMenuStyle(look),
      menuChildren: [
        for (var (k, label) in const [
          (0, "Both sides"),
          (1, "Mid: what both sides share"),
          (2, "Side: where they differ"),
        ])
          chainMenuItem(look,
              key: ValueKey("$id-$k"),
              text: label,
              current: value == k,
              onPressed: () => onPick(k)),
      ],
      child: Text(
          "Works on: ${const ["both sides", "mid", "side"][value.clamp(0, 2)]}"),
    );

/// _stripKept are the saved presets of a strip's [part], by name.
List<(String, Map<String, dynamic>)> _stripKept(StripPart part) => [
      for (var p in devicePresets.presets)
        if (stripPresetOf(p.data) case (var of, var value) when of == part)
          (p.name, value),
    ];

/// _StripPresetPicker is the Presets ▾ of a strip's own card -- its EQ,
/// compressor, limiter or Ducker -- as a device's: Default, the starting
/// points it comes with, the ones saved, and Save.
class _StripPresetPicker extends StatefulWidget {
  /// label is what it is the presets of: "EQ", "Wiggle".
  final String label;

  /// kept are the saved presets it offers, by name, as written: asked for
  /// as it opens, once they are read.
  final List<(String, Map<String, dynamic>)> Function() kept;

  /// name is the preset last put on, or null for its own settings.
  final String? name;

  /// builtIn are its starting points, by name, as written (see toJson).
  final List<(String, Map<String, dynamic>)> builtIn;
  final void Function(String name, Map<String, dynamic> value) onPick;
  final VoidCallback onDefault;
  final VoidCallback onSave;
  const _StripPresetPicker(
      {required this.label,
      required this.kept,
      required this.name,
      required this.builtIn,
      required this.onPick,
      required this.onDefault,
      required this.onSave,
      super.key});

  @override
  State<_StripPresetPicker> createState() => _StripPresetPickerState();
}

class _StripPresetPickerState extends State<_StripPresetPicker> {
  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var kept = widget.kept();
    var id = (widget.key as ValueKey?)?.value ?? "stripPreset";
    return MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, "${widget.label} presets"),
        chainMenuItem(look,
            key: ValueKey("$id-default"),
            text: "Default",
            current: widget.name == null,
            onPressed: widget.onDefault),
        for (var (name, value) in [...widget.builtIn, ...kept])
          chainMenuItem(look,
              key: ValueKey("$id-$name"),
              text: name,
              current: widget.name == name,
              onPressed: () => widget.onPick(name, value)),
        chainMenuDivider(look),
        chainMenuItem(look,
            key: ValueKey("$id-save"),
            text: "Save these settings as a preset",
            onPressed: widget.onSave),
      ],
      builder: (context, menu, _) => GestureDetector(
        key: ValueKey("$id-open"),
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          if (menu.isOpen) {
            menu.close();
            return;
          }
          await devicePresets.load();
          if (!mounted) return;
          setState(() {});
          menu.open();
        },
        child: _presetLabel(context, widget.name ?? "Default", studio),
      ),
    );
  }
}

/// _GainBadge is what a device does to the level, read between it and the
/// one before while sound passes -- "+2.2" warm, "−4.1" cool -- as the
/// prototype's gain-change badge; nothing while it is quiet.
class _GainBadge extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final String id;
  const _GainBadge(
      {required this.controller,
      required this.channel,
      required this.id,
      super.key});

  @override
  State<_GainBadge> createState() => _GainBadgeState();
}

class _GainBadgeState extends State<_GainBadge>
    with SingleTickerProviderStateMixin, _Metered {
  double? _change;

  @override
  CanvasController get meteredBy => widget.controller;

  @override
  void tick() {
    var i = widget.controller.chainOf(widget.channel).indexOf(widget.id);
    var taps = widget.controller.deviceLevels(widget.channel);
    if (i < 0 || i + 1 >= taps.length) {
      _change = null;
      return;
    }
    double db((double, double) p) => gainToDb(math.max(p.$1, p.$2));
    var a = db(taps[i]), b = db(taps[i + 1]);
    var now = a <= -80 || b <= -80 ? null : b - a;
    // Steadied, so it can be read.
    _change = now == null
        ? null
        : _change == null
            ? now
            : _change! + (now - _change!) * 0.15;
  }

  @override
  Widget build(BuildContext context) {
    var c = _change;
    if (!widget.controller.chainBadges) return const SizedBox.shrink();
    if (c == null || c.abs() < 0.05) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
          "${c >= 0 ? "+" : "−"}${c.abs().toStringAsFixed(1)}",
          key: ValueKey("deviceGain-${widget.id}"),
          style: TextStyle(
              fontSize: 9.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: c > 0 ? const Color(0xFFE2B04A) : const Color(0xFF7FC8F8))),
    );
  }
}

/// NoteJoin is a join on a MIDI chain: the notes passing there as dots,
/// one lit for each -- what is sounding now, done to by the first [upto]
/// of its MIDI effects (a chord adds notes, a scale moves them).
class NoteJoin extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final int upto;
  final double height;
  const NoteJoin(
      {super.key,
      required this.controller,
      required this.channel,
      required this.upto,
      required this.height});

  @override
  State<NoteJoin> createState() => _NoteJoinState();
}

class _NoteJoinState extends State<NoteJoin>
    with SingleTickerProviderStateMixin, _Metered {
  int _notes = 0;

  @override
  CanvasController get meteredBy => widget.controller;

  @override
  void tick() {
    var e = widget.controller.instrumentOf(widget.channel);
    var part = e?.instrument;
    if (e == null || part == null) {
      _notes = 0;
      return;
    }
    var keys = widget.controller.audioState(e).keys;
    var effects = part.effects.take(widget.upto).toList();
    _notes = effects.isEmpty
        ? keys.length
        : {
            for (var k in keys)
              for (var (out, _) in liveKeys(effects, k, 96)) out,
          }.length;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.chainMeters) return const SizedBox(width: 4);
    tick();
    var studio = MixerLook.of(context).studio;
    const dots = 6;
    return Tooltip(
      message: _notes == 0
          ? "No notes passing"
          : "$_notes note${_notes == 1 ? "" : "s"} passing",
      child: SizedBox(
        key: ValueKey("noteJoin-${widget.upto}"),
        width: 16,
        height: widget.height,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < dots; i++)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dots - 1 - i < _notes
                      ? midiColour
                      : studio.edge.withValues(alpha: 0.6),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// _ReadingBadge is a card's reading in its bar, as _GainBadge's: a turn
/// down, cool.
class _ReadingBadge extends StatelessWidget {
  final String text;
  const _ReadingBadge({required this.text, super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 9.5,
                fontFeatures: [FontFeature.tabularFigures()],
                color: Color(0xFF7FC8F8))),
      );
}

/// _ABSwitch is a card's A|B: the one heard lit; a press hears the other.
class _ABSwitch extends StatelessWidget {
  final bool b;
  final VoidCallback onTap;
  const _ABSwitch({required this.b, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    Widget half(String letter, bool lit) => Container(
          width: 15,
          alignment: Alignment.center,
          color: lit ? look.colors.primary : null,
          child: Text(letter,
              style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: lit ? look.colors.onPrimary : studio.muted)),
        );
    return Tooltip(
      message: b
          ? "Hearing B: press to hear A again"
          : "Hearing A: press to try a second set of settings, B",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 16,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: studio.edge)),
          clipBehavior: Clip.antiAlias,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            half("A", !b),
            Container(width: 1, color: studio.edge),
            half("B", b),
          ]),
        ),
      ),
    );
  }
}

/// _MacroTools are a macro's Random -- every knob somewhere new -- and its
/// Variation: its knobs' settings kept, by number, and brought back.
class _MacroTools extends StatelessWidget {
  final int index;
  final MixDevice device;
  final MixerLook look;
  final ValueChanged<MixDevice> onChanged;
  const _MacroTools(
      {required this.index,
      required this.device,
      required this.look,
      required this.onChanged,
      super.key});

  /// _now is the knobs' settings as they are.
  Map<String, double> get _now => {
        for (var p in macroParams) p.id: device.value(p.id),
      };

  bool _isNow(Map<String, double> v) =>
      macroParams.every((p) => (v[p.id] ?? 0) == device.value(p.id));

  @override
  Widget build(BuildContext context) {
    var studio = look.studio;
    var variations = device.variations;
    var current = variations.indexWhere(_isNow);
    Widget button(String key, String icon, String label, VoidCallback onTap) =>
        InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: studio.edge)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon.isNotEmpty) ...[
                ChainIcon(icon, size: 12, color: studio.muted),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: studio.text)),
              ),
            ]),
          ),
        );
    return SizedBox(
      width: MacroPanel.width - 16,
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        button("macroRandom-$index", "dice", "Random", () {
          var dice = math.Random();
          var next = device;
          for (var p in macroParams) {
            next = next.withValue(p.id, dice.nextDouble());
          }
          onChanged(next);
        }),
        MenuAnchor(
          style: chainMenuStyle(look),
          builder: (context, menu, _) => button(
              "macroVariation-$index",
              "",
              current >= 0
                  ? "Variation ${current + 1} ▾"
                  : variations.isEmpty
                      ? "Variations ▾"
                      : "Variation · changed ▾",
              () => menu.isOpen ? menu.close() : menu.open()),
          menuChildren: [
            chainMenuHeading(look, "Variations"),
            for (var (i, v) in variations.indexed)
              chainMenuItem(look,
                  key: ValueKey("macroVariation-$index-$i"),
                  text: "Variation ${i + 1}",
                  current: i == current, onPressed: () {
                var next = device;
                for (var p in macroParams) {
                  next = next.withValue(p.id, v[p.id] ?? 0);
                }
                onChanged(next);
              }),
            if (variations.isNotEmpty) chainMenuDivider(look),
            chainMenuItem(look,
                key: ValueKey("macroVariationSave-$index"),
                text: "Keep these as Variation ${variations.length + 1}",
                onPressed: () =>
                    onChanged(device.withVariations([...variations, _now]))),
            if (current >= 0)
              chainMenuItem(look,
                  key: ValueKey("macroVariationForget-$index"),
                  text: "Forget Variation ${current + 1}",
                  onPressed: () => onChanged(device
                      .withVariations([...variations]..removeAt(current)))),
          ],
        ),
      ]),
    );
  }
}

/// freezeFrom freezes [owner]'s chain up to [step], saying so as it goes:
/// it takes a moment, as each sound is rendered.
Future<void> freezeFrom(
    BuildContext context, CanvasController c, String owner, String step) async {
  SnackBarModel? snack;
  try {
    snack = SnackBarModel.of(context);
  } catch (_) {}
  snack?.success("Freezing: each sound on the channel is rendered once");
  var why = await c.freezeChain(owner, step);
  if (why != null) {
    snack?.error(why);
  } else {
    snack?.success("Frozen: it plays a rendered copy until unfrozen");
  }
}

/// freezeHooks are a device card's freezing, at [step] of [owner]'s chain:
/// whether it is frozen, a way to freeze up to it, and to unfreeze.
({bool frozen, VoidCallback? onFreeze, VoidCallback? onUnfreeze}) freezeHooks(
    BuildContext context, CanvasController c, String owner, String step) {
  var steps = c.frozenSteps(owner);
  if (steps.isNotEmpty) {
    return (
      frozen: steps.contains(step),
      onFreeze: null,
      onUnfreeze: () => c.unfreezeChain(owner),
    );
  }
  var can = c.canFreeze(owner) == null && !c.freezing(owner);
  return (
    frozen: false,
    onFreeze: can ? () => freezeFrom(context, c, owner, step) : null,
    onUnfreeze: null,
  );
}

/// duplicateDevice puts a copy of device [index] of [owner]'s chain after
/// it, with an id of its own, as one undo step.
void duplicateDevice(CanvasController c, String owner, int index) {
  var now = withDeviceIds(c.devicesOf(owner));
  if (index >= now.length) return;
  c.beginInteraction();
  c.setDevicesOf(
      owner, withDeviceIds([...now]..insert(index + 1, now[index].withId(""))));
  c.endInteraction();
}

/// resetDevice sets device [index] of [owner]'s chain back to a new one's
/// settings, keeping its place, its switch and what it listens to.
void resetDevice(CanvasController c, String owner, int index) {
  var now = c.devicesOf(owner);
  if (index >= now.length) return;
  var d = now[index];
  c.beginInteraction();
  c.setDevicesOf(
      owner,
      [...now]..[index] = MixDevice(d.kind,
          on: d.on, id: d.id, source: d.source, variations: d.variations));
  c.endInteraction();
}

/// chainMenuStyle is a menu of the Chain's, as the prototype draws them:
/// a dark panel with a fine edge, rounded, close-set.
MenuStyle chainMenuStyle(MixerLook look) => MenuStyle(
      backgroundColor: WidgetStatePropertyAll(Color.alphaBlend(
          look.colors.primary.withValues(alpha: 0.07), look.studio.raised)),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(BorderSide(color: look.studio.edge)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      elevation: const WidgetStatePropertyAll(6),
      shadowColor: const WidgetStatePropertyAll(Color(0xAA000000)),
    );

/// chainMenuItemStyle is one line of such a menu: small text, lit in the
/// accent under the pointer.
ButtonStyle chainMenuItemStyle(MixerLook look) => ButtonStyle(
      textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
      minimumSize: const WidgetStatePropertyAll(Size(170, 26)),
      maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 28)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding:
          const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      visualDensity: VisualDensity.compact,
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: WidgetStateProperty.resolveWith((s) => s
              .contains(WidgetState.disabled)
          ? null
          : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
              ? look.colors.primary
              : null),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s
              .contains(WidgetState.disabled)
          ? look.studio.muted
          : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
              ? look.colors.onPrimary
              : look.studio.text),
    );

/// chainMenuItem is a line of a Chain menu: [text], and [hint] small at
/// its right.
Widget chainMenuItem(MixerLook look,
        {Key? key,
        required String text,
        String? hint,
        bool current = false,
        VoidCallback? onPressed}) =>
    MenuItemButton(
      key: key,
      style: chainMenuItemStyle(look),
      onPressed: onPressed,
      leadingIcon: current
          ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: look.colors.primary, shape: BoxShape.circle))
          : null,
      trailingIcon: hint == null
          ? null
          : Text(hint,
              style: TextStyle(
                  fontSize: 10,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: look.studio.muted)),
      child: Text(text),
    );

/// chainMenuHeading is a small capital heading in a Chain menu.
Widget chainMenuHeading(MixerLook look, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 3),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w500,
              color: look.studio.muted)),
    );

/// chainMenuDivider is a fine line between a Chain menu's groups.
Widget chainMenuDivider(MixerLook look) => Divider(
    height: 9, thickness: 1, indent: 2, endIndent: 2, color: look.studio.edge);

/// DeviceFrame is one device in the chain: a bar along the top with its
/// fold arrow, its power switch and its name, and under it the device -- or,
/// folded, its name down the side and [folded], a meter or a reading.
class DeviceFrame extends StatelessWidget {
  /// id names the device in keys: device-[id], deviceFold-[id].
  final String id;
  final String title;
  final DeviceSkin skin;

  /// on is whether it is switched on, or null for a device with no switch.
  final bool? on;
  final ValueChanged<bool>? onPower;
  final Key? powerKey;
  final bool folded;
  final VoidCallback onFold;

  /// width is the device's width open, before scaling; height the room the
  /// chain gives it; drawnHeight the height it is drawn at and scaled from
  /// (deviceHeight for a unit, whose dials keep their places; the room
  /// itself for a form, which keeps its text's size and scrolls).
  final double width;
  final double height;
  final double drawnHeight;
  final Widget body;
  final Widget foldedBody;
  final List<Widget> actions;

  /// controls, given, lays the device out for its height rather than
  /// scaling it (see DeviceTier): [display] over its knobs -- the knobs
  /// [controls] gives for the tier -- with [footer] under them when tall,
  /// and only [summary] when short. [body] is then not used.
  final List<Widget> Function(DeviceTier tier)? controls;

  /// display is what the device is doing, drawn over its knobs: it takes
  /// the height left over.
  final Widget? display;
  final List<Widget> footer;
  final String summary;

  /// icon and accent are its family's mark: see deviceGroupLook.
  final IconData? icon;
  final Color? accent;

  /// help is what it does, behind a "?" at the right of its bar, read when
  /// clicked: the Chain shows no tips on hover. Empty for none.
  final String help;

  /// glows is whether it is what makes the sound -- an instrument, the
  /// Generator -- drawn as the prototype does: its edge and a glow in its
  /// colour.
  final bool glows;

  /// onDuplicate and onReset, given, are its ⋯ menu's Duplicate and Reset
  /// every setting, as the prototype's: a copy after it, and its settings
  /// as a new one's.
  final VoidCallback? onDuplicate;
  final VoidCallback? onReset;

  /// onSavePreset, given, is its ⋯ menu's Save as a preset: it and its
  /// settings, kept with the canvas's presets.
  final VoidCallback? onSavePreset;

  /// onAB, given, is its bar's A|B: its settings swapped with a second set
  /// to compare by ear, as the prototype's; [showingB] which is heard.
  final VoidCallback? onAB;
  final bool showingB;

  /// extraMenu are more of its ⋯ menu's items, after Reset: its own
  /// settings that are not knobs (Oversample, Works on, Listens to).
  final List<Widget> Function(MixerLook look)? extraMenu;

  /// barExtras sit on its bar before A|B: its preset, and what it does to
  /// the level.
  final List<Widget> barExtras;

  /// frozen is whether it is in the part of its chain frozen into the
  /// channel's sounds (see CanvasController.freezeChain): shown as frozen,
  /// and not to be changed until unfrozen. onFreeze, given, freezes the
  /// chain up to it; onUnfreeze puts the chain back.
  final bool frozen;
  final VoidCallback? onFreeze;
  final VoidCallback? onUnfreeze;

  /// besideDisplay, given, is how wide its display is on a short card --
  /// beside its settings, the full height -- and besideSettings how wide
  /// those settings are, packed rather than in one row that scrolls (Ken,
  /// 2026-11-08: the motion devices' displays wide, as the prototype's).
  final double? besideDisplay;
  final double besideSettings;

  /// displayBeside puts [display] beside the settings at every height but
  /// the strip, not only a short one's: a list, which wants height more
  /// than width (the Instances card's copies).
  final bool displayBeside;

  const DeviceFrame({
    required this.id,
    required this.title,
    required this.skin,
    required this.folded,
    required this.onFold,
    required this.width,
    required this.height,
    required this.body,
    required this.foldedBody,
    this.drawnHeight = deviceHeight,
    this.on,
    this.onPower,
    this.powerKey,
    this.actions = const [],
    this.controls,
    this.display,
    this.footer = const [],
    this.summary = "",
    this.icon,
    this.accent,
    this.glows = false,
    this.help = "",
    this.onDuplicate,
    this.onReset,
    this.onSavePreset,
    this.onAB,
    this.showingB = false,
    this.extraMenu,
    this.barExtras = const [],
    this.frozen = false,
    this.onFreeze,
    this.onUnfreeze,
    this.besideDisplay,
    this.besideSettings = 220,
    this.displayBeside = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (controls != null) return _tiered(context);
    // The bar as every card's, at its own size; only what is under it is
    // drawn at the device's size and scaled to the room.
    var tier = DeviceTier.of(height);
    var barHeight =
        tier == DeviceTier.small || tier == DeviceTier.strip ? 24.0 : 28.0;
    var header = _bar(context,
        height: barHeight, short: false, full: true, cardWidth: width);
    if (folded) {
      return SizedBox(
        key: ValueKey("device-$id"),
        width: deviceFoldedWidth,
        height: height,
        child: _card(context, header, _foldedInside(context)),
      );
    }
    var drawn = drawnHeight - 28;
    var scale = ((height - barHeight) / drawn).clamp(0.5, 1.5);
    // Never narrower than its bar needs; what is under the bar keeps its
    // shape, scaled to fit.
    return SizedBox(
      key: ValueKey("device-$id"),
      width: math.max(width * scale, 120),
      height: height,
      child: _card(
        context,
        header,
        FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, height: drawn, child: body),
        ),
      ),
    );
  }

  /// _card is the Chain's card round [header] and [inside], as the
  /// prototype draws every device: the studio's raised card, a line round
  /// it, its family's colour along its top, faded while it is switched off.
  Widget _card(BuildContext context, Widget header, Widget inside) {
    var studio = MixerLook.of(context).studio;
    var off = on == false;
    // The line round it and the colour along its top are drawn over it, as
    // the prototype's are, taking none of the room its insides had.
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [
              0,
              0.14
            ],
            colors: [
              Color.lerp(studio.raised, Colors.white, 0.03)!,
              studio.raised
            ]),
        borderRadius: BorderRadius.circular(9),
        boxShadow: glows && accent != null
            ? [
                BoxShadow(
                    color: accent!.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: -6)
              ]
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
            color: glows && accent != null
                ? Color.lerp(accent!, studio.edge, 0.3)!
                : studio.edge),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          Column(children: [
            header,
            Expanded(
                child: IgnorePointer(
                    ignoring: frozen,
                    child: Opacity(opacity: off ? 0.55 : 1, child: inside))),
          ]),
          if (frozen && !folded)
            Positioned(
              right: 8,
              bottom: 6,
              child: IgnorePointer(
                child: Container(
                  key: ValueKey("deviceFrozen-$id"),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5AB4E6).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: const Color(0xFF5AB4E6).withValues(alpha: 0.6)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.ac_unit, size: 11, color: Color(0xFF9FD4F2)),
                    SizedBox(width: 3),
                    Text("FROZEN",
                        style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            color: Color(0xFF9FD4F2))),
                  ]),
                ),
              ),
            ),
          if (!folded)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 2,
              child: IgnorePointer(
                child: ColoredBox(
                    color: (accent ?? studio.muted)
                        .withValues(alpha: off ? 0.3 : 0.9)),
              ),
            ),
        ]),
      ),
    );
  }

  /// _menuKey is whether [w] goes behind the bar's ⋯ rather than on it: the
  /// arrows that move a device along the chain, and what takes it out.
  static bool _inMenu(Widget w) {
    if (w is DeviceMove) return true;
    var key = w.key;
    if (key is! ValueKey<String>) return false;
    var k = key.value;
    return k.startsWith("deviceLeft-") ||
        k.startsWith("deviceRight-") ||
        k.startsWith("menu-") ||
        k.contains("Remove");
  }

  /// _menuItems are its ⋯ menu, as the prototype's: its name; moving it,
  /// a copy and its settings reset; what else [actions] keeps there; what
  /// it does; and, last, taking it out. The actions keep their keys.
  List<Widget> _menuItems(MixerLook look) {
    var moves = <Widget>[], others = <Widget>[], removes = <Widget>[];
    String? hintOf(VoidCallback? onPressed, bool left) =>
        onPressed != null ? null : (left ? "first" : "last");
    for (var w in actions.where(_inMenu)) {
      if (w is DeviceMove) {
        for (var (left, can) in [(true, w.canLeft), (false, w.canRight)]) {
          VoidCallback? go = !can ? null : () => w.onMove(left ? -1 : 1);
          moves.add(chainMenuItem(look,
              key: ValueKey("deviceMove${left ? "Left" : "Right"}-${w.id}"),
              text: left ? "Move left" : "Move right",
              hint: hintOf(go, left),
              onPressed: go));
        }
      } else if (w is IconButton) {
        var k =
            w.key is ValueKey<String> ? (w.key as ValueKey<String>).value : "";
        var left = k.startsWith("deviceLeft-");
        if (left || k.startsWith("deviceRight-")) {
          moves.add(chainMenuItem(look,
              key: w.key,
              text: left ? "Move left" : "Move right",
              hint: hintOf(w.onPressed, left),
              onPressed: w.onPressed));
        } else if (k.contains("Remove")) {
          removes.add(chainMenuItem(look,
              key: w.key, text: "Remove", onPressed: w.onPressed));
        } else {
          others.add(chainMenuItem(look,
              key: w.key, text: w.tooltip ?? "", onPressed: w.onPressed));
        }
      }
    }
    var top = [
      ...moves,
      if (onDuplicate != null)
        chainMenuItem(look,
            key: ValueKey("deviceDuplicate-$id"),
            text: "Duplicate",
            onPressed: onDuplicate),
      if (onReset != null)
        chainMenuItem(look,
            key: ValueKey("deviceReset-$id"),
            text: "Reset every setting",
            onPressed: onReset),
      ...others,
      ...?extraMenu?.call(look),
    ];
    if (top.isEmpty &&
        removes.isEmpty &&
        onSavePreset == null &&
        onFreeze == null &&
        onUnfreeze == null) {
      return const [];
    }
    return [
      chainMenuHeading(look, title),
      ...top,
      if (help.isNotEmpty ||
          onSavePreset != null ||
          onFreeze != null ||
          onUnfreeze != null)
        chainMenuDivider(look),
      if (onUnfreeze != null)
        chainMenuItem(look,
            key: ValueKey("deviceUnfreeze-$id"),
            text: "Unfreeze the chain",
            onPressed: onUnfreeze)
      else if (onFreeze != null)
        chainMenuItem(look,
            key: ValueKey("deviceFreeze-$id"),
            text: "Freeze the chain up to here",
            hint: "plays a copy",
            onPressed: onFreeze),
      if (onSavePreset != null)
        chainMenuItem(look,
            key: ValueKey("deviceSavePreset-$id"),
            text: "Save as a preset",
            onPressed: onSavePreset),
      if (help.isNotEmpty) ...[
        SubmenuButton(
          key: ValueKey("deviceAbout-$id"),
          style: chainMenuItemStyle(look),
          menuStyle: chainMenuStyle(look),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 240,
                child: Text(help,
                    style: TextStyle(
                        fontSize: 11.5, height: 1.4, color: look.studio.text)),
              ),
            ),
          ],
          child: const Text("What it does"),
        ),
      ],
      if (removes.isNotEmpty) ...[chainMenuDivider(look), ...removes],
    ];
  }

  /// _barRoom is what the bar has room for beside its switch, its mark, a
  /// short name, its A|B, its [buttons] and its ⋯ ([more]) -- measured,
  /// each button its tap target's 48 -- given out in order: a reading (a
  /// gain badge comes and goes with the sound, so its room is kept), the
  /// presets whole or as their mark, then the help, which the ⋯ also says.
  ({bool badges, bool preset, bool compactPreset, bool help}) _barRoom(
      BuildContext context, int buttons, bool more, double cardWidth) {
    var scale = MediaQuery.textScalerOf(context).scale(1);
    var badges = barExtras.where((w) => w is _GainBadge || w is _ReadingBadge);
    var pickers =
        barExtras.where((w) => w is _PresetPicker || w is _StripPresetPicker);
    // Anything else it has there -- a latency, a mark -- always shown.
    var others = barExtras.length - badges.length - pickers.length;
    var room = cardWidth -
        (72 * scale * others +
            10 +
            (on != null ? 25 : 0) +
            (icon != null ? 20 : 0) +
            52 * scale +
            (onAB != null ? 36 : 0) +
            48 * (buttons + (more ? 1 : 0)));
    bool take(double w) {
      if (room < w) return false;
      room -= w;
      return true;
    }

    var hasBadges = badges.isEmpty || take(badges.length * 44 * scale);
    var whole = pickers.isNotEmpty && take(86 * scale);
    var compact = !whole && pickers.isNotEmpty && take(23);
    var help = take(48);
    return (
      badges: hasBadges && badges.isNotEmpty,
      preset: whole,
      compactPreset: compact,
      help: help,
    );
  }

  Widget _bar(BuildContext context,
      {required double height,
      required bool short,
      required bool full,
      double cardWidth = double.infinity}) {
    var studio = MixerLook.of(context).studio;
    var shown = [
      for (var a in actions)
        if (!_inMenu(a)) a
    ];
    var look = MixerLook.of(context);
    var menu = _menuItems(look);
    var bar = _barRoom(context, shown.length, menu.isNotEmpty, cardWidth);
    Widget small(Widget child) => IconButtonTheme(
          data: IconButtonThemeData(
              style: IconButton.styleFrom(
                  foregroundColor: studio.muted,
                  minimumSize: const Size(21, 21),
                  maximumSize: const Size(28, 28),
                  padding: EdgeInsets.zero,
                  iconSize: 14)),
          child: child,
        );
    if (folded) {
      return Container(
        height: height,
        alignment: Alignment.center,
        child: on == null
            ? null
            : _Power(on: on!, onPower: onPower!, powerKey: powerKey),
      );
    }
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(8, 0, 2, 0),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: studio.edge.withValues(alpha: 0.7)))),
      child: Row(children: [
        if (on != null) ...[
          _Power(on: on!, onPower: onPower!, powerKey: powerKey),
          const SizedBox(width: 7),
        ],
        if (icon != null && full) ...[
          chainIconOr(icon!, size: 14, color: accent ?? studio.muted),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Tooltip(
            message: "Fold $title",
            child: GestureDetector(
              key: ValueKey("deviceFold-$id"),
              behavior: HitTestBehavior.opaque,
              onTap: onFold,
              child: Text(title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: studio.text)),
            ),
          ),
        ),
        // A strip is too narrow for its buttons: they are for a taller
        // panel.
        if (full) ...[
          // Its reading, its presets and A|B; what the bar has no room for
          // left off, in this order: the help (its ⋯ says what it does),
          // then the presets as their mark alone, then the reading.
          ...[
            for (var w in barExtras)
              if (w is _GainBadge || w is _ReadingBadge)
                if (bar.badges) w else const SizedBox.shrink()
              else if (w is _PresetPicker || w is _StripPresetPicker)
                if (bar.preset)
                  w
                else if (bar.compactPreset)
                  _PresetCompact(child: w)
                else
                  const SizedBox.shrink()
              else
                w,
            if (onAB != null)
              _ABSwitch(
                  key: ValueKey("deviceAB-$id"), b: showingB, onTap: onAB!),
          ],
          for (var a in shown) small(a),
          if (help.isNotEmpty && bar.help)
            MenuAnchor(
              style: chainMenuStyle(look),
              builder: (context, controller, _) => small(IconButton(
                key: ValueKey("deviceHelp-$id"),
                icon: const Icon(Icons.help_outline),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              )),
              menuChildren: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 240,
                    child: Text(help,
                        key: ValueKey("deviceHelpText-$id"),
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: look.studio.text)),
                  ),
                ),
              ],
            ),
          if (menu.isNotEmpty)
            MenuAnchor(
              style: chainMenuStyle(look),
              builder: (context, controller, _) => small(IconButton(
                key: ValueKey("deviceMore-$id"),
                tooltip: "Move or remove",
                icon: const Icon(Icons.more_horiz),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              )),
              menuChildren: menu,
            ),
        ],
      ]),
    );
  }

  /// _foldedInside is a folded card, as the prototype's: a slim column of
  /// its family's mark and its name down it, pressed to open it.
  Widget _foldedInside(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    return Tooltip(
      message: "Open $title",
      child: GestureDetector(
        key: ValueKey("deviceFold-$id"),
        behavior: HitTestBehavior.opaque,
        onTap: onFold,
        // What it shows folded -- a meter, a curve -- at its foot, as the
        // prototype's level does: as much of the card as is left over its
        // name, up to 90. Measured from the card itself: a LayoutBuilder in
        // the column is told nothing of its height, and took 80 a short
        // card did not have.
        child: LayoutBuilder(builder: (context, box) {
          var room = box.maxHeight.isFinite ? box.maxHeight : 200.0;
          var fixed = (icon != null ? 18.0 : 0) + 8 + 6;
          var foot = math.min(
              math.min(90.0, room * 0.4), math.max(0.0, room - fixed - 30));
          return Column(children: [
            if (icon != null) ...[
              const SizedBox(height: 4),
              chainIconOr(icon!, size: 14, color: accent ?? studio.muted),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: studio.text)),
              ),
            ),
            SizedBox(
              width: 26,
              height: math.max(0.0, foot),
              child: ClipRect(child: foldedBody),
            ),
            const SizedBox(height: 6),
          ]);
        }),
      ),
    );
  }

  /// _isKnob is whether [w] takes a knob's cell on the card's grid.
  static bool _isKnob(Widget w) => w is _Knob || w is DeviceKnob;

  /// _besideDisplay is how wide a short card's display is, beside its
  /// knobs.
  static const double _besideDisplay = 170;

  /// _tiered is the device laid out for [height]: see DeviceTier.
  Widget _tiered(BuildContext context) {
    var tier = DeviceTier.of(height);
    var short = tier == DeviceTier.small || tier == DeviceTier.strip;
    var barHeight = short ? 24.0 : 28.0;
    // Wider rather than taller: as wide as its knobs need to sit on one row
    // -- the chain scrolls sideways, and has more room across than down.
    var knobCount = folded || tier == DeviceTier.strip
        ? 0
        : controls!(tier).where(_isKnob).length;
    var oneRow = 14.0 + 58 * math.min(knobCount, 9);
    // Short, its display goes beside its knobs rather than over them: the
    // card wider, the display still a picture worth looking at.
    var beside = display != null &&
        (tier == DeviceTier.small ||
            (displayBeside && tier != DeviceTier.strip));
    var packed = beside && besideDisplay != null;
    var textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var w = folded
        ? deviceFoldedWidth
        : tier == DeviceTier.strip
            ? math.min(width, 170.0)
            : packed
                ? besideDisplay! + besideSettings * textScale + 21
                : beside
                    ? math.max(width, _besideDisplay + 50.0 * knobCount + 24)
                    : math.max(width, oneRow);
    var header = _bar(context,
        height: barHeight,
        short: short,
        full: tier != DeviceTier.strip,
        cardWidth: w);
    var studio = MixerLook.of(context).studio;
    Widget inside;
    if (folded) {
      inside = _foldedInside(context);
    } else if (tier == DeviceTier.strip) {
      inside = Padding(
        key: ValueKey("deviceSummary-$id"),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Text(summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: studio.muted)),
      );
    } else {
      var knobs = controls!(tier);
      inside = LayoutBuilder(builder: (context, box) {
        // The knobs on an even grid, a column for every 55 pixels of the
        // card (three to seven), each other setting a row of its own; one
        // row of them on a small card, scrolled where it is too long.
        Widget grid;
        if (packed) {
          // Beside a wide display: a knob a cell, the rest the settings'
          // width, wrapping down rather than scrolling along.
          grid = Wrap(spacing: 4, runSpacing: 6, children: [
            for (var k in knobs)
              SizedBox(
                  width: _isKnob(k)
                      ? 50.0 * textScale
                      : besideSettings * textScale - 14,
                  child: k),
          ]);
        } else if (tier == DeviceTier.small) {
          grid = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var (i, k) in knobs.indexed) ...[
                    if (i > 0) const SizedBox(width: 4),
                    // A knob a cell; any other setting as wide as it
                    // needs, in a row that scrolls.
                    _isKnob(k)
                        ? SizedBox(width: 50, child: k)
                        // A split's branches are the card: all of it.
                        : SizedBox(
                            width: k is SplitBranches
                                ? SplitBranches.width - 16
                                : 170,
                            child: k),
                  ],
                ]),
          );
        } else {
          var count = knobs.where(_isKnob).length;
          var columns = math.max(((box.maxWidth - 14) / 55).floor().clamp(3, 9),
              math.min(count, 9));
          var rows = <Widget>[];
          var run = <Widget>[];
          void flush() {
            if (run.isEmpty) return;
            rows.add(
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var k in run) Expanded(child: k),
              for (var i = run.length; i < columns; i++)
                const Expanded(child: SizedBox()),
            ]));
            run = [];
          }

          for (var k in knobs) {
            if (_isKnob(k)) {
              run.add(k);
              if (run.length == columns) flush();
            } else {
              flush();
              rows.add(Align(alignment: Alignment.centerLeft, child: k));
            }
          }
          flush();
          grid = Column(mainAxisSize: MainAxisSize.min, children: [
            for (var (i, r) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: 7),
              r,
            ],
          ]);
        }
        // The knobs, as much of them as fits under the display's least;
        // they scroll rather than spill where even that is too much.
        var most = math.max(0.0, box.maxHeight - (display == null ? 0 : 40));
        var below = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: most),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(7, short ? 5 : 8, 7, short ? 5 : 5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                grid,
                if (tier == DeviceTier.large && footer.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: footer),
                ],
              ]),
            ),
          ),
        );
        Widget? screen = display == null
            ? null
            : Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: studio.edge.withValues(alpha: 0.8)),
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(5), child: display),
              );
        if (beside) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 5, 0, 6),
              child: SizedBox(
                  width: besideDisplay ?? _besideDisplay, child: screen),
            ),
            Expanded(
              child: Align(
                // Beside a list, from its top; beside a picture, level with
                // its middle.
                alignment:
                    displayBeside ? Alignment.topLeft : Alignment.centerLeft,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                    child: grid,
                  ),
                ),
              ),
            ),
          ]);
        }
        return Column(children: [
          if (screen != null)
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(7, short ? 5 : 7, 7, 0),
                child: screen,
              ),
            ),
          below,
          if (display == null) const Spacer(),
        ]);
      });
    }
    return SizedBox(
      key: ValueKey("device-$id"),
      width: w,
      height: height,
      child: _card(context, header, inside),
    );
  }

  /// headerInk is what reads on the header bar: light, on every skin.
  Color get headerInk => skin.header.computeLuminance() > 0.5
      ? const Color(0xFF1E2227)
      : const Color(0xFFE8EAEE);
}

class _Power extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onPower;
  final Key? powerKey;
  const _Power({required this.on, required this.onPower, this.powerKey});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: on ? "On: click to bypass" : "Bypassed: click to switch on",
        // A lit dot, as the prototype's: green and glowing while on, grey
        // while bypassed.
        child: GestureDetector(
          key: powerKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => onPower(!on),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on
                    ? const RadialGradient(
                        center: Alignment(-0.3, -0.3),
                        colors: [Color(0xFF9BF0A6), Color(0xFF5BC46B)])
                    : null,
                color: on ? null : const Color(0xFF4A4658),
                border: Border.all(color: const Color(0xFF110F22), width: 2),
                boxShadow: on
                    ? const [BoxShadow(color: Color(0x885BC46B), blurRadius: 6)]
                    : null,
              ),
            ),
          ),
        ),
      );
}

/// DeviceMove is the pair of arrows on a device that moves it along its
/// chain (in its ⋯ menu as Move left and Move right).
class DeviceMove extends StatelessWidget {
  final bool canLeft, canRight;
  final Color ink;
  final String id;

  /// onMove moves it a place along the chain, minus one to the left.
  final void Function(int by) onMove;

  const DeviceMove(
      {required this.id,
      required this.canLeft,
      required this.canRight,
      required this.onMove,
      required this.ink,
      super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var (left, can) in [(true, canLeft), (false, canRight)])
          Tooltip(
            message: left ? "Move earlier in the chain" : "Move later",
            child: GestureDetector(
              key: ValueKey("deviceMove${left ? "Left" : "Right"}-$id"),
              onTap: !can ? null : () => onMove(left ? -1 : 1),
              child: Icon(left ? Icons.chevron_left : Icons.chevron_right,
                  size: 18, color: can ? ink : ink.withValues(alpha: 0.25)),
            ),
          ),
      ]);
}

/// _Strip reads and writes the mix of one strip, by its channel's key, or
/// the master's with none.
class _Strip {
  final CanvasController controller;
  final String? channel;
  _Strip(this.controller, this.channel);

  TimelineChannel? get _lane => channel == null
      ? null
      : controller.timelineChannels.where((l) => l.key == channel).firstOrNull;

  /// _return is the return this strip is, where it is one rather than a
  /// channel of sounds.
  ReturnChannel? get _return => controller.returnOf(channel);

  /// _scene is whether it is the scene's bus (see CanvasScene.bus).
  bool get _scene => channel == sceneBusKey;

  ChannelMix? get _mix =>
      _scene ? controller.sceneBus : _lane?.mix ?? _return?.mix;

  bool get gone =>
      channel != null && !_scene && _lane == null && _return == null;

  /// canMove is whether [step] (chainEq, chainComp) can go left, and right.
  (bool, bool) canMove(String step) {
    var chain = controller.chainOf(channel ?? mixerMasterKey);
    var i = chain.indexOf(step);
    return (i > 0, i >= 0 && i < chain.length - 1);
  }

  void move(String step, int by) =>
      controller.moveDevice(channel ?? mixerMasterKey, step, by);

  // A channel can go while its devices are on screen -- its last sound
  // deleted, a speaker emptied -- and the meters ask for its settings thirty
  // times a second. Gone, it reads as a strip at rest rather than throwing.
  Eq get eq => channel == null
      ? controller.document.masterMix.eq
      : _mix?.eq ?? const Eq();
  Dynamics get comp => channel == null
      ? controller.document.masterMix.comp
      : _mix?.comp ?? const Dynamics();

  void write({Eq? eq, Dynamics? comp, bool transient = false}) {
    controller.beginInteraction();
    if (channel == null) {
      var m = controller.document.masterMix;
      controller.setMasterMix(m.copyWith(eq: eq, comp: comp), transient: true);
    } else if (_scene) {
      controller.setSceneBus(controller.sceneBus.copyWith(eq: eq, comp: comp),
          transient: true);
    } else if (_lane case var lane?) {
      // Opened on purpose, so changed wherever the sound is.
      controller.setChannelMix(lane, lane.mix.copyWith(eq: eq, comp: comp),
          transient: true, anywhere: true);
    } else if (_return case var ret?) {
      controller.setReturn(
          ret.copyWith(mix: ret.mix.copyWith(eq: eq, comp: comp)),
          transient: true);
    }
    if (!transient) controller.endInteraction();
  }

  void commit() => controller.endInteraction();

  Ducking get duck => _lane?.mix.duck ?? const Ducking();

  void writeDuck(Ducking next, {bool transient = false}) {
    var lane = _lane;
    if (lane == null) return;
    controller.beginInteraction();
    controller.setChannelMix(lane, lane.mix.copyWith(duck: next),
        transient: true, anywhere: true);
    if (!transient) controller.endInteraction();
  }

  String get name => _scene
      ? controller.document.scene.saysAt(controller.document.at)
      : _lane?.name ?? _return?.name ?? "";

  (double, double) get levels =>
      channel == null ? controller.levels() : controller.levels(channel);

  /// level is how loud the strip is now, in decibels: the louder side.
  double get levelDb {
    var (l, r) =
        channel == null ? controller.levels() : controller.levels(channel);
    return gainToDb(math.max(l, r));
  }

  Float32List? get spectrum => controller.spectrum(channel);
}

/// _Range is a control's travel: straight, or even in ratio for things like
/// frequency and time, where each doubling is the same distance.
class _Range {
  final double min, max;
  final bool log;
  const _Range(this.min, this.max, {this.log = false});

  double toUnit(double v) {
    var c = v.clamp(min, max);
    return log
        ? math.log(c / min) / math.log(max / min)
        : (c - min) / (max - min);
  }

  double fromUnit(double u) {
    var c = u.clamp(0.0, 1.0);
    return log
        ? min * math.pow(max / min, c).toDouble()
        : min + (max - min) * c;
  }
}

/// _Dragged is a value changed by dragging up and down on it -- a knob, a
/// readout -- a hundred and fifty pixels for its whole travel, and put back
/// to [initial] with a double-click.
class _Dragged extends StatelessWidget {
  final double value;
  final double initial;
  final _Range range;
  final void Function(double v, {bool transient}) onChanged;
  final VoidCallback onCommit;
  final Widget child;

  /// menu is its right-click's choices: see _Knob.menu.
  final List<(String, VoidCallback)> menu;

  const _Dragged({
    required this.value,
    required this.initial,
    required this.range,
    required this.onChanged,
    required this.onCommit,
    required this.child,
    this.menu = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (menu.isEmpty) return _knob();
    // Its right-click's menu, anchored on the knob where it was clicked.
    return _KnobMenu(menu: menu, child: _knob());
  }

  Widget _knob() {
    var at = range.toUnit(value);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        supportedDevices: dragPointers,
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => at = range.toUnit(value),
        onVerticalDragUpdate: (d) {
          at = (at - d.delta.dy / 150).clamp(0.0, 1.0);
          onChanged(range.fromUnit(at), transient: true);
        },
        onVerticalDragEnd: (_) => onCommit(),
        onDoubleTap: () => onChanged(initial),
        child: child,
      ),
    );
  }
}

/// _KnobMenu is a knob's right-click menu (see _Knob.menu), anchored on it
/// where it was clicked; keeps its controller across builds.
class _KnobMenu extends StatefulWidget {
  final List<(String, VoidCallback)> menu;
  final Widget child;
  const _KnobMenu({required this.menu, required this.child});

  @override
  State<_KnobMenu> createState() => _KnobMenuState();
}

class _KnobMenuState extends State<_KnobMenu> {
  final MenuController _opened = MenuController();

  @override
  Widget build(BuildContext context) => MenuAnchor(
        controller: _opened,
        menuChildren: [
          for (var (i, (label, then)) in widget.menu.indexed)
            MenuItemButton(
              key: ValueKey("knobMenu-$i"),
              onPressed: then,
              child: Text(label, style: const TextStyle(fontSize: 12.5)),
            ),
        ],
        child: GestureDetector(
          onSecondaryTapDown: (d) => _opened.open(position: d.localPosition),
          child: widget.child,
        ),
      );
}

String _hz(double f) => f >= 1000
    ? "${(f / 1000).toStringAsFixed(f >= 10000 ? 1 : 2)} kHz"
    : "${f.round()} Hz";

String _signed(double db) =>
    "${db > 0.05 ? "+" : db < -0.05 ? "−" : ""}${db.abs().toStringAsFixed(1)}";

/// _Metered is a plugin window's ticker: about thirty times a second it
/// rebuilds, for the meters and the analyzer.
mixin _Metered<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  void tick();

  /// meteredBy is the canvas whose sound the device shows.
  CanvasController get meteredBy;

  /// metering is whether it reads the sound at all: a display switched off
  /// does not, and costs nothing. Changed, call [meterAgain].
  bool get metering => true;

  /// meterAgain starts reading again, where [metering] has come on.
  void meterAgain() {
    if (metering) _wake();
  }

  /// The device's readings move only while there is sound: a ticker asks
  /// for a frame on every screen refresh, so it rests after a second and a
  /// half of quiet (the needles fallen), and a slow check -- no frames --
  /// wakes it.
  int _quietTicks = 0;
  Timer? _resting;

  bool get _loud {
    var c = meteredBy;
    if (c.playing || c.sessionActive) return true;
    var (l, r) = c.levels();
    return gainToDb(math.max(l, r)) > -80;
  }

  void _wake() {
    _resting?.cancel();
    _resting = null;
    _quietTicks = 0;
    if (_ticker.isActive) return;
    // A ticker's time starts again from nought each start: the last read,
    // from the run before, would hold every frame back until this run had
    // lasted as long.
    _last = Duration.zero;
    _ticker.start();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((now) {
      if (!metering) {
        _ticker.stop();
        return;
      }
      if (now - _last < const Duration(milliseconds: 33)) return;
      _last = now;
      if (mounted) setState(tick);
      if (_loud) {
        _quietTicks = 0;
      } else if (++_quietTicks > 45) {
        _ticker.stop();
        _resting ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (_loud && metering) _wake();
        });
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _resting?.cancel();
    _ticker.dispose();
    super.dispose();
  }
}

// ---- Channel EQ

/// eqBandColour is each band's colour: its button, its handle and its own
/// curve. Red at the bottom through to magenta at the top, as Logic has
/// them.
Color eqBandColour(EqSlot slot) => switch (slot) {
      EqSlot.lowCut => const Color(0xFFE5484D),
      EqSlot.low => const Color(0xFFF27D3A),
      EqSlot.lowMid => const Color(0xFFF2C94C),
      EqSlot.mid => const Color(0xFF6FCF5E),
      EqSlot.highMid => const Color(0xFF35C6C2),
      EqSlot.presence => const Color(0xFF3E9BF2),
      EqSlot.high => const Color(0xFF8E6CF2),
      EqSlot.highCut => const Color(0xFFE45BC6),
    };

const _eqBack = Color(0xFF0D1826);
const _eqInk = Color(0xFFC9D6E6);

/// _headerInkLight is what reads on a device's dark header bar -- its
/// remove button, which drawn in the body's ink was there but not seen.
const _headerInkLight = Color(0xFFE8EAEE);
const _eqDim = Color(0xFF6E8199);

/// EqDevice is a strip's Channel EQ in the chain -- the master's, with no
/// [channel].
class EqDevice extends StatefulWidget {
  static const width = 392.0;
  final CanvasController controller;
  final String? channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const EqDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<EqDevice> createState() => _EqDeviceState();
}

class _EqDeviceState extends State<EqDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _analyzer is whether what is playing is drawn behind the curve.
  bool _analyzer = false;
  Float32List? _spectrum;

  /// _picked is the band last touched: its own curve is drawn in its colour.
  EqSlot? _picked;
  EqSlot? _dragging;

  @override
  void tick() =>
      _spectrum = _analyzer && !widget.folded ? strip.spectrum : null;

  static const _fMin = 20.0, _fMax = 20000.0, _gMax = 12.0;
  static const _freq = _Range(_fMin, _fMax, log: true);

  void _write(Eq eq, {bool transient = false}) =>
      strip.write(eq: eq, transient: transient);

  /// _band writes [b] into [slot], switching the EQ and the band on: moving
  /// something is asking to hear it.
  void _band(EqSlot slot, EqBand b, {bool transient = false}) {
    setState(() => _picked = slot);
    _write(strip.eq.withBand(slot, b.copyWith(on: true)).copyWith(on: true),
        transient: transient);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (strip.gone) return const SizedBox.shrink();
          var eq = strip.eq;
          var look = MixerLook.of(context);
          var studio = look.studio;
          var picked = _picked ?? EqSlot.mid;
          var hooks = widget.channel == null
              ? (frozen: false, onFreeze: null, onUnfreeze: null)
              : freezeHooks(
                  context, widget.controller, widget.channel!, chainEq);
          return DeviceFrame(
            id: "eq",
            frozen: hooks.frozen,
            onFreeze: hooks.onFreeze,
            onUnfreeze: hooks.onUnfreeze,
            title: widget.channel == null ? "Master EQ" : "Channel EQ",
            help: "Shapes the sound's tone. Drag a band's point on the curve: "
                "across for where, up and down for how much; its Q knob for "
                "how wide. A chip picks a band and shows its knobs; pressed "
                "again, switches it off.",
            skin: DeviceSkin.studio(studio),
            // The prototype's Tone family: its own colour and mark.
            icon: Icons.equalizer,
            accent: const Color(0xFF9A92EA),
            on: eq.on,
            powerKey: const ValueKey("eqOn"),
            onPower: (v) => _write(eq.copyWith(on: v)),
            // A second set of bands to compare by ear, and back to flat.
            onAB: () => widget.controller.toggleABOf(
                "${widget.channel ?? mixerMasterKey}|eq",
                eq,
                (o) => _write(o as Eq, transient: true)),
            showingB: widget.controller
                .showingBOf("${widget.channel ?? mixerMasterKey}|eq"),
            onReset: () => _write(const Eq().copyWith(on: eq.on)),
            // On the whole sound, its middle or its sides.
            extraMenu: (look) => [
              worksOnMenu(look,
                  id: "eqStereo",
                  value: eq.stereo,
                  onPick: (k) => _write(eq.copyWith(stereo: k))),
            ],
            barExtras: [
              _GainBadge(
                  key: const ValueKey("gainBadge-eq"),
                  controller: widget.controller,
                  channel: widget.channel ?? mixerMasterKey,
                  id: chainEq),
              _StripPresetPicker(
                key: const ValueKey("stripPreset-eq"),
                label: StripPart.eq.label,
                kept: () => _stripKept(StripPart.eq),
                name: widget.controller
                    .presetNameOf(widget.channel ?? mixerMasterKey, "eq"),
                builtIn: [for (var (n, v) in eqPresets) (n, v.toJson())],
                onPick: (name, value) {
                  _write(Eq.fromJson(value));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "eq", name);
                },
                onDefault: () {
                  _write(const Eq().copyWith(on: eq.on));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "eq", null);
                },
                onSave: () =>
                    saveStripPreset(context, StripPart.eq, eq.toJson()),
              ),
            ],
            folded: widget.folded,
            onFold: widget.onFold,
            width: EqDevice.width,
            height: widget.height,
            actions: [
              if (widget.channel case var owner?
                  when widget.controller.canRemovePart(owner, chainEq))
                IconButton(
                  key: const ValueKey("deviceRemove-eq"),
                  tooltip: "Take the EQ out",
                  icon: const Icon(Icons.close),
                  onPressed: () => widget.controller.removePart(owner, chainEq),
                ),
              DeviceMove(
                  id: "eq",
                  canLeft: strip.canMove(chainEq).$1,
                  canRight: strip.canMove(chainEq).$2,
                  onMove: (by) => strip.move(chainEq, by),
                  ink: studio.text),
            ],
            summary: [
              for (var slot in EqSlot.values)
                if (eq.band(slot).on) slot.label,
            ].join(" · "),
            foldedBody: CustomPaint(
                key: const ValueKey("eqFolded"), painter: _MiniCurve(eq)),
            // Its curve, the bands dragged on it, what is playing behind it
            // while Analyzer is on.
            display: Stack(children: [
              Positioned.fill(
                  child: ColoredBox(color: _eqBack, child: _graph(eq))),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  key: const ValueKey("eqAnalyzer"),
                  onTap: () => setState(() {
                    _analyzer = !_analyzer;
                    _spectrum = null;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: studio.panel.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: _analyzer ? look.colors.primary : studio.edge),
                    ),
                    child: Text("Analyse",
                        style: TextStyle(
                            fontSize: 9.5,
                            color: _analyzer ? studio.text : studio.muted)),
                  ),
                ),
              ),
            ]),
            controls: (tier) => [
              _bandButtons(eq),
              ..._bandKnobs(eq, picked, tier),
              if (picked.isCut) _slope(eq, picked, studio),
            ],
            body: const SizedBox(),
          );
        },
      );

  /// _bandKnobs are the picked band's knobs -- where it is, how much (a
  /// bell's or shelf's), how wide -- and the EQ's output.
  List<Widget> _bandKnobs(Eq eq, EqSlot slot, DeviceTier tier) {
    var b = eq.band(slot);
    var size = switch (tier) {
      DeviceTier.large => 46.0,
      DeviceTier.medium => 38.0,
      _ => 28.0,
    };
    var accent = eqBandColour(slot);
    void set(EqBand next, {bool transient = false}) =>
        _band(slot, next, transient: transient);
    return [
      _Knob(
        key: ValueKey("eqFreq-${slot.name}"),
        label: "${slot.label} freq",
        text: _hz(b.freq),
        value: b.freq,
        initial: slot.initial.freq,
        range: _freq,
        size: size,
        reading: tier != DeviceTier.small,
        accent: accent,
        onChanged: (v, {transient = false}) =>
            set(b.copyWith(freq: v), transient: transient),
        onCommit: strip.commit,
      ),
      if (!slot.isCut)
        _Knob(
          key: ValueKey("eqGain-${slot.name}"),
          label: "Gain",
          text: "${_signed(b.gainDb)} dB",
          value: b.gainDb,
          initial: 0,
          range: const _Range(-12, 12),
          size: size,
          reading: tier != DeviceTier.small,
          accent: accent,
          bipolar: true,
          onChanged: (v, {transient = false}) => set(
              b.copyWith(gainDb: (v * 2).roundToDouble() / 2),
              transient: transient),
          onCommit: strip.commit,
        ),
      _Knob(
        key: ValueKey("eqQ-${slot.name}"),
        label: "Q",
        text: b.q.toStringAsFixed(2),
        value: b.q,
        initial: slot.initial.q,
        range: const _Range(0.1, 10, log: true),
        size: size,
        reading: tier != DeviceTier.small,
        accent: accent,
        onChanged: (v, {transient = false}) =>
            set(b.copyWith(q: v), transient: transient),
        onCommit: strip.commit,
      ),
      _Knob(
        key: const ValueKey("eqOutput"),
        label: "Output",
        text: "${_signed(eq.gainDb)} dB",
        value: eq.gainDb,
        initial: 0,
        range: const _Range(-12, 12),
        size: size,
        reading: tier != DeviceTier.small,
        accent: accent,
        bipolar: true,
        onChanged: (v, {transient = false}) => _write(
            eq.copyWith(on: true, gainDb: (v * 2).roundToDouble() / 2),
            transient: transient),
        onCommit: strip.commit,
      ),
    ];
  }

  /// _slope is a cut's steepness, stepped through by a click.
  Widget _slope(Eq eq, EqSlot slot, StudioColors studio) {
    var b = eq.band(slot);
    return Row(children: [
      Text("Slope", style: TextStyle(fontSize: 9.5, color: studio.muted)),
      const SizedBox(width: 8),
      GestureDetector(
        key: ValueKey("eqSlope-${slot.name}"),
        onTap: () {
          var i = eqSlopes.indexOf(b.slope);
          _band(slot, b.copyWith(slope: eqSlopes[(i + 1) % eqSlopes.length]));
        },
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: studio.edge),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text("${b.slope} dB/Oct ▸",
              style: TextStyle(fontSize: 10, color: studio.text)),
        ),
      ),
    ]);
  }

  /// _bandButtons are a chip a band: pressed, the band is picked -- its
  /// knobs shown -- and switched on or off.
  Widget _bandButtons(Eq eq) => SizedBox(
        height: 22,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var slot in EqSlot.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Tooltip(
                  message: "${slot.label}: "
                      "${eq.band(slot).on ? "on" : "off"}",
                  child: GestureDetector(
                    key: ValueKey("eqBand-${slot.name}"),
                    onTap: () {
                      var b = eq.band(slot);
                      // A press on the band picked switches it; on another,
                      // picks it, switching it on.
                      var switching = _picked == slot || !b.on;
                      setState(() => _picked = slot);
                      if (switching) {
                        _write(eq
                            .withBand(slot, b.copyWith(on: !b.on))
                            .copyWith(on: true));
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: eq.band(slot).on
                            ? eqBandColour(slot).withValues(alpha: 0.85)
                            : const Color(0xFF1F2E40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: (_picked ?? EqSlot.mid) == slot
                                ? Colors.white70
                                : Colors.black26),
                      ),
                      child: CustomPaint(
                        painter: _BandIcon(
                            slot,
                            eq.band(slot).on
                                ? const Color(0xFF0D1826)
                                : _eqDim),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );

  double _x(double f, double w) => _freq.toUnit(f) * w;
  double _y(double g, double h) => h / 2 - g / _gMax * (h / 2 - 14);
  double _g(double y, double h) =>
      ((h / 2 - y) / (h / 2 - 14) * _gMax).clamp(-_gMax, _gMax);

  /// _handle is where [slot]'s handle is drawn: a cut's on its own curve at
  /// its corner, the rest at their gain.
  Offset _handle(Eq eq, EqSlot slot, double w, double h) {
    var b = eq.band(slot);
    return Offset(_x(b.freq, w),
        _y(slot.isCut ? (b.on ? eq.bandDb(slot, b.freq) : 0) : b.gainDb, h));
  }

  EqSlot? _nearest(Eq eq, Offset p, double w, double h, double within) {
    EqSlot? best;
    var closest = within;
    for (var slot in EqSlot.values) {
      var d = (_handle(eq, slot, w, h) - p).distance;
      if (d < closest) {
        closest = d;
        best = slot;
      }
    }
    return best;
  }

  /// _moveTo puts the handle being dragged at [at]: sideways its
  /// frequency, up and down its gain.
  void _moveTo(Offset at, double w, double h) {
    var slot = _dragging;
    if (slot == null) return;
    var b = strip.eq.band(slot);
    var next = b.copyWith(
        freq: _freq.fromUnit(at.dx / w),
        gainDb: slot.isCut ? b.gainDb : (_g(at.dy, h) * 2).roundToDouble() / 2);
    _band(slot, next, transient: true);
  }

  Widget _graph(Eq eq) => LayoutBuilder(builder: (context, box) {
        var w = box.maxWidth, h = box.maxHeight;
        // Set by a press and a drag only: a wheel or a trackpad's scroll
        // over it scrolls the chain (Ken). A band's Q is its knob.
        return GestureDetector(
          key: const ValueKey("eqCurve"),
          supportedDevices: dragPointers,
          // The handle is chosen where the press lands, not where the drag
          // is recognised: in the sideways-scrolling chain that is a
          // little way off, past the handle.
          onPanDown: (d) => setState(() {
            _dragging = _nearest(eq, d.localPosition, w, h, 24);
            if (_dragging != null) _picked = _dragging;
          }),
          onPanCancel: () => setState(() => _dragging = null),
          // Moved from the start: what was moved while the drag was being
          // recognised arrives with it, not as an update.
          onPanStart: (d) => _moveTo(d.localPosition, w, h),
          onPanUpdate: (d) => _moveTo(d.localPosition, w, h),
          onPanEnd: (_) {
            if (_dragging != null) strip.commit();
            setState(() => _dragging = null);
          },
          onDoubleTapDown: (d) {
            var slot = _nearest(eq, d.localPosition, w, h, 14);
            if (slot == null || slot.isCut) return;
            _band(slot, eq.band(slot).copyWith(gainDb: 0));
          },
          child: CustomPaint(
            size: Size(w, h),
            painter: _EqGraph(eq, _picked, _spectrum, _x, _y, _handle),
          ),
        );
      });
}

/// _BandIcon is a band's shape, drawn small on its button.
class _BandIcon extends CustomPainter {
  final EqSlot slot;
  final Color ink;
  _BandIcon(this.slot, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    var cx = w / 2, mid = h / 2;
    var l = cx - 16, r = cx + 16, up = mid - 7, down = mid + 7;
    var p = Path();
    switch (slot.kind) {
      case EqKind.lowCut:
        p
          ..moveTo(l, down)
          ..quadraticBezierTo(l + 8, mid - 2, l + 14, mid - 2)
          ..lineTo(r, mid - 2);
      case EqKind.highCut:
        p
          ..moveTo(l, mid - 2)
          ..lineTo(r - 14, mid - 2)
          ..quadraticBezierTo(r - 8, mid - 2, r, down);
      case EqKind.lowShelf:
        p
          ..moveTo(l, up)
          ..lineTo(cx - 5, up)
          ..cubicTo(cx, up, cx, mid + 3, cx + 5, mid + 3)
          ..lineTo(r, mid + 3);
      case EqKind.highShelf:
        p
          ..moveTo(l, mid + 3)
          ..lineTo(cx - 5, mid + 3)
          ..cubicTo(cx, mid + 3, cx, up, cx + 5, up)
          ..lineTo(r, up);
      case EqKind.bell:
        p
          ..moveTo(l, mid + 4)
          ..lineTo(cx - 9, mid + 4)
          ..cubicTo(cx - 4, mid + 4, cx - 3, up - 1, cx, up - 1)
          ..cubicTo(cx + 3, up - 1, cx + 4, mid + 4, cx + 9, mid + 4)
          ..lineTo(r, mid + 4);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = ink);
  }

  @override
  bool shouldRepaint(_BandIcon old) => old.ink != ink || old.slot != slot;
}

/// paintedLabel is [text] in [style], laid out: kept, as the meters and
/// graphs paint the same few labels on every frame they move, and laying
/// them out again each time was much of what those frames cost.
TextPainter paintedLabel(String text, TextStyle style) {
  var key = (text, style);
  var kept = _labels[key];
  if (kept != null) return kept;
  if (_labels.length > 400) _labels.clear();
  return _labels[key] = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr)
    ..layout();
}

final _labels = <(String, TextStyle), TextPainter>{};

class _EqGraph extends CustomPainter {
  final Eq eq;
  final EqSlot? picked;
  final Float32List? spectrum;
  final double Function(double, double) x;
  final double Function(double, double) y;
  final Offset Function(Eq, EqSlot, double, double) handle;
  _EqGraph(this.eq, this.picked, this.spectrum, this.x, this.y, this.handle);

  static const _labels = [
    (20.0, "20"),
    (50.0, "50"),
    (100.0, "100"),
    (200.0, "200"),
    (500.0, "500"),
    (1000.0, "1k"),
    (2000.0, "2k"),
    (5000.0, "5k"),
    (10000.0, "10k"),
    (20000.0, "20k"),
  ];

  void _text(Canvas canvas, String s, Offset at, {bool right = false}) {
    var tp = paintedLabel(s, const TextStyle(fontSize: 9, color: _eqDim));
    tp.paint(canvas, right ? at - Offset(tp.width, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    var frame =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(
        frame,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF16273B), Color(0xFF0A1420)])
              .createShader(Offset.zero & size));
    canvas.save();
    canvas.clipRRect(frame);
    var grid = Paint()..color = const Color(0xFF22354B);
    for (var (f, label) in _labels) {
      var px = x(f, w);
      canvas.drawLine(Offset(px, 0), Offset(px, h), grid);
      if (f > 20 && f < 20000) _text(canvas, label, Offset(px + 3, 3));
    }
    for (var g in const [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      canvas.drawLine(Offset(0, y(g, h)), Offset(w, y(g, h)),
          g == 0 ? (Paint()..color = const Color(0xFF3A5272)) : grid);
      if (g != 12 && g != -12) {
        _text(canvas, g == 0 ? "0" : _signed(g), Offset(w - 4, y(g, h) - 11),
            right: true);
      }
    }
    // The analyzer: what is playing, after the EQ, sixty decibels below its
    // loudest at the floor.
    if (spectrum case var bins? when bins.isNotEmpty) {
      var loudest = bins.fold(0.0, (m, v) => v > m ? v : m);
      if (loudest > 0) {
        const nyquist = 22050.0;
        var fill = Path()..moveTo(0, h);
        for (var i = 1; i < bins.length; i++) {
          var f = i * nyquist / bins.length;
          if (f < 20) continue;
          var db = 20 * math.log(bins[i] / loudest + 1e-6) / math.ln10 +
              eq.responseDb(f);
          fill.lineTo(x(f, w), h - ((db + 60) / 60).clamp(0.0, 1.0) * (h - 16));
        }
        fill
          ..lineTo(w, h)
          ..close();
        canvas.drawPath(fill,
            Paint()..color = const Color(0xFF5F7FA6).withValues(alpha: 0.35));
      }
    }
    var shown = eq.copyWith(on: true);
    var zero = y(0, h);
    Path curve(double Function(double f) db) {
      var p = Path();
      for (var i = 0; i <= 200; i++) {
        var px = i / 200 * w;
        var f = 20 * math.pow(1000, px / w).toDouble();
        var py = y(db(f).clamp(-14.0, 14.0), h);
        i == 0 ? p.moveTo(px, py) : p.lineTo(px, py);
      }
      return p;
    }

    // The band last touched, alone, in its colour.
    if (picked case var slot? when eq.band(slot).on) {
      var own = curve((f) => shown.bandDb(slot, f));
      var area = Path.from(own)
        ..lineTo(w, zero)
        ..lineTo(0, zero)
        ..close();
      canvas.drawPath(
          area, Paint()..color = eqBandColour(slot).withValues(alpha: 0.22));
      canvas.drawPath(
          own,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = eqBandColour(slot).withValues(alpha: 0.8));
    }
    // Everything together, filled to the line.
    var all = curve((f) => shown.responseDb(f));
    var area = Path.from(all)
      ..lineTo(w, zero)
      ..lineTo(0, zero)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..color = (eq.on ? const Color(0xFF6CC4FF) : const Color(0xFF6E8199))
              .withValues(alpha: 0.16));
    canvas.drawPath(
        all,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = eq.on ? const Color(0xFFE6F2FF) : _eqDim);
    for (var slot in EqSlot.values) {
      var b = eq.band(slot);
      var at = handle(eq, slot, w, h);
      var colour = eqBandColour(slot);
      canvas.drawCircle(at, slot == picked ? 8 : 6.5,
          Paint()..color = b.on ? colour : colour.withValues(alpha: 0.3));
      canvas.drawCircle(
          at,
          slot == picked ? 8 : 6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = slot == picked ? Colors.white : Colors.black54);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EqGraph old) =>
      old.spectrum != spectrum ||
      old.picked != picked ||
      !identical(old.eq, eq);
}

// ---- Compressor

/// _silverInk and _silverDim are what reads on a device's card: they were
/// a silver unit's dark ink, and every card is the Chain's dark one now.
const _silverInk = Color(0xFFE8E4EE);
const _silverDim = Color(0xFF8E8A9C);

/// _faceInk and _faceDim read on a cream meter's face: the compressor's VU,
/// the ducking curve.
const _faceInk = Color(0xFF2B2F36);
const _faceDim = Color(0xFF6A707A);
const _cream = Color(0xFFF1E7C9);

/// CompDevice is a strip's compressor in the chain -- the master's glue,
/// with no [channel].
class CompDevice extends StatefulWidget {
  static const width = 440.0;
  final CanvasController controller;
  final String? channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const CompDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<CompDevice> createState() => _CompDeviceState();
}

class _CompDeviceState extends State<CompDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _needleShown is whether the display shows the gain-reduction needle
  /// rather than the transfer curve, which it opens on, as the prototype's.
  bool _needleShown = false;
  double _input = -90;

  /// _needle is the gain reduction shown, eased as a VU needle is.
  double _needle = 0;

  @override
  void tick() {
    _input = strip.levelDb;
    var comp = strip.comp;
    // What the compressor is really taking off, from an engine that can
    // measure inside a strip; worked out from the strip's level otherwise.
    var channel = widget.channel;
    var measured =
        channel != null && widget.controller.deviceLevels(channel).isNotEmpty;
    var reduction = !comp.on
        ? 0.0
        : measured
            ? widget.controller.reduction(channel)
            : _input > -60
                ? _input - comp.reducedDb(_input)
                : 0.0;
    _needle += (reduction - _needle) * 0.35;
  }

  void _write(Dynamics c, {bool transient = false}) =>
      strip.write(comp: c, transient: transient);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (strip.gone) return const SizedBox.shrink();
          var comp = strip.comp;
          var output = comp.on && _input > -90
              ? _input +
                  comp.mix *
                      (comp.reducedDb(_input) + comp.totalMakeupDb - _input)
              : _input;
          var look = MixerLook.of(context);
          var studio = look.studio;
          var hooks = widget.channel == null
              ? (frozen: false, onFreeze: null, onUnfreeze: null)
              : freezeHooks(
                  context, widget.controller, widget.channel!, chainComp);
          return DeviceFrame(
            id: "comp",
            frozen: hooks.frozen,
            onFreeze: hooks.onFreeze,
            onUnfreeze: hooks.onUnfreeze,
            title: widget.channel == null ? "Glue" : "Compressor",
            help: "Turns the sound down when it goes over the Threshold, by "
                "the Ratio, so loud and quiet sit closer. Attack and Release "
                "are how fast; Make up brings it back up. Listens to another "
                "channel to duck under it, as a kick pumps a pad.",
            skin: DeviceSkin.studio(studio),
            icon: deviceGroupLook(DeviceGroup.dynamics).$1,
            accent: deviceGroupLook(DeviceGroup.dynamics).$2,
            on: comp.on,
            powerKey: const ValueKey("compOn"),
            onPower: (v) => _write(comp.copyWith(on: v)),
            onAB: () => widget.controller.toggleABOf(
                "${widget.channel ?? mixerMasterKey}|comp",
                comp,
                (o) => _write(o as Dynamics, transient: true)),
            showingB: widget.controller
                .showingBOf("${widget.channel ?? mixerMasterKey}|comp"),
            // The master's glue starts gentler than a channel's compressor.
            onReset: () => _write((widget.channel == null
                    ? const MasterMix().comp
                    : const Dynamics())
                .copyWith(on: comp.on)),
            extraMenu: (look) => [
              worksOnMenu(look,
                  id: "compStereo",
                  value: comp.stereo,
                  onPick: (k) => _write(comp.copyWith(stereo: k))),
            ],
            barExtras: [
              _GainBadge(
                  key: const ValueKey("gainBadge-comp"),
                  controller: widget.controller,
                  channel: widget.channel ?? mixerMasterKey,
                  id: chainComp),
              _StripPresetPicker(
                key: const ValueKey("stripPreset-comp"),
                label: StripPart.comp.label,
                kept: () => _stripKept(StripPart.comp),
                name: widget.controller
                    .presetNameOf(widget.channel ?? mixerMasterKey, "comp"),
                builtIn: [for (var (n, v) in compPresets) (n, v.toJson())],
                onPick: (name, value) {
                  _write(Dynamics.fromJson(value));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "comp", name);
                },
                onDefault: () {
                  _write((widget.channel == null
                          ? const MasterMix().comp
                          : const Dynamics())
                      .copyWith(on: comp.on));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "comp", null);
                },
                onSave: () =>
                    saveStripPreset(context, StripPart.comp, comp.toJson()),
              ),
            ],
            folded: widget.folded,
            onFold: widget.onFold,
            width: CompDevice.width,
            height: widget.height,
            actions: [
              if (widget.channel case var owner?
                  when widget.controller.canRemovePart(owner, chainComp))
                IconButton(
                  key: const ValueKey("deviceRemove-comp"),
                  tooltip: "Take the compressor out",
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      widget.controller.removePart(owner, chainComp),
                ),
              DeviceMove(
                  id: "comp",
                  canLeft: strip.canMove(chainComp).$1,
                  canRight: strip.canMove(chainComp).$2,
                  onMove: (by) => strip.move(chainComp, by),
                  ink: studio.text),
            ],
            summary: "${comp.threshold.round()} dB · "
                "${comp.ratio.toStringAsFixed(1)}:1 · "
                "−${_needle.toStringAsFixed(1)} dB",
            // Folded, how much it is taking off.
            foldedBody: CustomPaint(
                key: const ValueKey("compFolded"),
                size: const Size(14, double.infinity),
                painter: _ReductionBar(_needle)),
            display: _display(comp, studio, output),
            controls: (tier) => [
              ..._knobList(comp, tier),
              _autoGain(comp, studio),
              if (widget.channel != null) _listensTo(comp),
            ],
            body: const SizedBox(),
          );
        },
      );

  /// _display is the compressor's screen: its curve, or how much it is
  /// taking off as a needle, switched in its corner, with the reduction
  /// read along its foot.
  Widget _display(Dynamics comp, StudioColors studio, double output) =>
      Stack(children: [
        Positioned.fill(
          child: ColoredBox(
            color: studio.display,
            child: _needleShown
                ? Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: _cream, borderRadius: BorderRadius.circular(4)),
                    child: CustomPaint(
                        key: const ValueKey("gainReduction"),
                        painter: _VuNeedle(_needle)),
                  )
                : CustomPaint(
                    key: const ValueKey("compCurve"),
                    painter: _TransferCurve(comp, _input,
                        line: Color.lerp(studio.text, Colors.white, 0.1)!,
                        grid: studio.edge.withValues(alpha: 0.6),
                        dim: studio.muted)),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Row(children: [
            _tab("Curve", !_needleShown, const ValueKey("compViewGraph"),
                () => setState(() => _needleShown = false), studio),
            const SizedBox(width: 3),
            _tab("Meter", _needleShown, const ValueKey("compViewMeter"),
                () => setState(() => _needleShown = true), studio),
          ]),
        ),
        Positioned(
          left: 6,
          bottom: 4,
          child: IgnorePointer(
            child: Text(
                "takes off ${_needle.toStringAsFixed(1)} dB · out "
                "${output > -60 ? output.round() : "−∞"} dB",
                style: TextStyle(
                    fontSize: 9.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: studio.muted)),
          ),
        ),
      ]);

  /// _tab is one of the display's views, in its corner, as the prototype's.
  Widget _tab(String label, bool on, Key key, VoidCallback onTap,
          StudioColors studio) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: studio.panel.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: on ? MixerLook.of(context).colors.primary : studio.edge),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 9.5, color: on ? studio.text : studio.muted)),
        ),
      );

  /// _autoGain is its make-up worked out for it: off, or to a level.
  Widget _autoGain(Dynamics comp, StudioColors studio) => Row(children: [
        Text("Auto gain", style: TextStyle(fontSize: 9.5, color: studio.muted)),
        const SizedBox(width: 8),
        Expanded(
          child: DeviceChoices(
            options: [
              for (var a in AutoGain.values)
                (
                  ValueKey("autoGain-${a.name}"),
                  a.label,
                  comp.autoGain == a,
                  () => _write(comp.copyWith(autoGain: a))
                ),
            ],
          ),
        ),
      ]);

  /// _listensTo is what the compressor hears to turn down by: its own sound,
  /// or another channel's -- a sidechain, as a kick pumps a pad.
  Widget _listensTo(Dynamics comp) {
    var channels = [
      for (var c in widget.controller.timelineChannels)
        if (c.key != widget.channel) c,
    ];
    var chosen = channels.any((c) => c.key == comp.source) ? comp.source : "";
    const ink = TextStyle(fontSize: 11, color: _silverInk);
    return Row(children: [
      const Text("Listens to",
          style: TextStyle(fontSize: 10, color: _silverDim)),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButton<String>(
          key: const ValueKey("compSource"),
          isExpanded: true,
          isDense: true,
          value: chosen,
          style: ink,
          iconEnabledColor: _silverInk,
          dropdownColor: MixerLook.of(context).studio.raised,
          items: [
            const DropdownMenuItem(
                value: "", child: Text("Itself", style: ink)),
            for (var c in channels)
              DropdownMenuItem(
                  value: c.key,
                  child: Text(c.name,
                      overflow: TextOverflow.ellipsis, style: ink)),
          ],
          onChanged: (v) {
            if (v != null) _write(comp.copyWith(source: v));
          },
        ),
      ),
    ]);
  }

  /// _knobList are its knobs, sized for [tier], in the order the
  /// prototype has them.
  List<Widget> _knobList(Dynamics comp, DeviceTier tier) {
    var initial =
        widget.channel == null ? const MasterMix().comp : const Dynamics();
    Widget knob(String label, String key, double value, double initialValue,
            _Range range, String text, Dynamics Function(double) apply,
            {bool big = false}) =>
        _Knob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value,
          initial: initialValue,
          range: range,
          size: switch (tier) {
            DeviceTier.large => 46,
            DeviceTier.medium => 38,
            _ => 28,
          },
          reading: tier != DeviceTier.small,
          accent: deviceGroupLook(DeviceGroup.dynamics).$2,
          onChanged: (v, {transient = false}) =>
              _write(apply(v), transient: transient),
          onCommit: strip.commit,
        );
    return [
      knob(
          "Threshold",
          "compThreshold",
          comp.threshold,
          initial.threshold,
          const _Range(-60, 0),
          "${comp.threshold.toStringAsFixed(1)} dB",
          (v) => comp.copyWith(threshold: v),
          big: true),
      knob(
          "Ratio",
          "compRatio",
          comp.ratio,
          initial.ratio,
          const _Range(1, 10, log: true),
          "${comp.ratio.toStringAsFixed(1)} : 1",
          (v) => comp.copyWith(ratio: v),
          big: true),
      knob(
          "Make up",
          "compMakeup",
          comp.makeupDb,
          initial.makeupDb,
          const _Range(0, 24),
          "${comp.makeupDb.toStringAsFixed(1)} dB",
          (v) => comp.copyWith(makeupDb: v),
          big: true),
      knob(
          "Knee",
          "compKnee",
          comp.kneeDb,
          initial.kneeDb,
          const _Range(0, 18),
          "${comp.kneeDb.toStringAsFixed(1)} dB",
          (v) => comp.copyWith(kneeDb: v)),
      knob(
          "Attack",
          "compAttack",
          comp.attackMs,
          initial.attackMs,
          const _Range(0.1, 100, log: true),
          "${comp.attackMs.toStringAsFixed(comp.attackMs < 10 ? 1 : 0)} ms",
          (v) => comp.copyWith(attackMs: v)),
      knob(
          "Release",
          "compRelease",
          comp.releaseMs,
          initial.releaseMs,
          const _Range(10, 1000, log: true),
          "${comp.releaseMs.round()} ms",
          (v) => comp.copyWith(releaseMs: v)),
      knob("Mix", "compMix", comp.mix, initial.mix, const _Range(0, 1),
          "${(comp.mix * 100).round()}%", (v) => comp.copyWith(mix: v)),
    ];
  }
}

/// _Choices is a setting that is one of a few, as the prototype draws one:
/// joined buttons, the one chosen filled.
class DeviceChoices extends StatelessWidget {
  /// options are each one's key, name, whether it is chosen, and its press.
  final List<(Key, String, bool, VoidCallback)> options;
  const DeviceChoices({required this.options, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return Container(
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(color: look.studio.edge),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        for (var (i, (key, label, on, tap)) in options.indexed) ...[
          if (i > 0) Container(width: 1, color: look.studio.edge),
          Expanded(
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: tap,
              child: Container(
                color: on ? look.colors.primary : null,
                alignment: Alignment.center,
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: on ? look.colors.onPrimary : look.studio.muted)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// _Knob is a rotary control: dragged up to turn it right, double-clicked
/// to put it back.
class _Knob extends StatefulWidget {
  final String label;
  final String text;
  final double value;
  final double initial;
  final _Range range;
  final double size;
  final void Function(double v, {bool transient}) onChanged;
  final VoidCallback onCommit;

  /// automated is whether a lane moves it -- a red dot by its name -- and
  /// held whether a hand is holding it instead: the dot grey.
  final bool automated;
  final bool held;

  /// modulated is whether an LFO moves it: a pink ring round it.
  final bool modulated;

  /// own is whether the copies being edited have a value of their own here
  /// (see instances.dart): its arc amber, with a dot by it.
  final bool own;

  /// menu is what its right-click offers -- a modulator of the chain to
  /// move it with, each -- by name; empty for none.
  final List<(String, VoidCallback)> menu;

  /// reading is whether its value is written under it: not on a short
  /// device, where the room is the knob's.
  final bool reading;

  /// accent, given, draws it as the Chain's cards have it: a dark knob with
  /// its arc in [accent], filled from the middle for a setting that goes
  /// both ways (see [bipolar]); [ink] its label's and reading's colour.
  final Color? accent;
  final Color ink;
  final bool bipolar;

  const _Knob({
    this.automated = false,
    this.held = false,
    this.modulated = false,
    this.own = false,
    this.menu = const [],
    this.reading = true,
    this.accent,
    this.ink = _silverInk,
    this.bipolar = false,
    required this.label,
    required this.text,
    required this.value,
    required this.initial,
    required this.range,
    required this.size,
    required this.onChanged,
    required this.onCommit,
    super.key,
  });

  @override
  State<_Knob> createState() => _KnobState();
}

/// _KnobState is a knob, and -- its value double-clicked -- a field to type
/// a number into.
class _KnobState extends State<_Knob> {
  bool _typing = false;
  final TextEditingController _typed = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Clicked away from, what was typed is kept.
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _commit();
    });
  }

  @override
  void dispose() {
    _typed.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get label => widget.label;
  String get text => widget.text;
  double get value => widget.value;
  double get initial => widget.initial;
  _Range get range => widget.range;
  double get size => widget.size;
  bool get automated => widget.automated;
  bool get held => widget.held;
  bool get modulated => widget.modulated;
  List<(String, VoidCallback)> get menu => widget.menu;
  bool get reading => widget.reading;
  bool get bipolar => widget.bipolar;
  void Function(double v, {bool transient}) get onChanged => widget.onChanged;
  VoidCallback get onCommit => widget.onCommit;

  void _type() {
    _typed.text = text;
    _typed.selection =
        TextSelection(baseOffset: 0, extentOffset: _typed.text.length);
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    var v = typedValue(_typed.text, text, range.min, range.max);
    setState(() => _typing = false);
    if (v != null) onChanged(v);
  }

  /// _face is the knob's size drawn, as the prototype's: 32 on a tall card,
  /// 27 and 22 on shorter ones, whatever size it was asked for.
  double get _face => size >= 44
      ? 32
      : size >= 36
          ? 27
          : size >= 26
              ? 22
              : size;

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var face = _face;
    // The whole of it takes a drag, its name and reading as well as its
    // dial, as the prototype's knobs do.
    return _Dragged(
      value: value,
      initial: initial,
      range: range,
      onChanged: onChanged,
      onCommit: onCommit,
      menu: menu,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CustomPaint(
                    size: Size.square(face),
                    painter: _KnobFace(range.toUnit(value),
                        accent: widget.own ? ownColour : look.colors.primary,
                        from: bipolar ? range.toUnit(0) : 0)),
                if (widget.own)
                  Positioned(
                    top: 0,
                    left: -6,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey("knobOwn"),
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: ownColour, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                if (modulated)
                  IgnorePointer(
                    child: Container(
                      key: const ValueKey("knobModulated"),
                      width: face + 4,
                      height: face + 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: modulationColour, width: 2),
                      ),
                    ),
                  ),
                if (automated)
                  Positioned(
                    top: 0,
                    right: -6,
                    child: Container(
                      key: const ValueKey("knobAutomated"),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: held
                              ? const Color(0xFF7D838D)
                              : automationColour),
                    ),
                  ),
              ]),
          const SizedBox(height: 1),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, color: look.studio.muted)),
          // Its value, double-clicked: typed in.
          if (reading && _typing)
            SizedBox(
              width: 56,
              height: 16,
              child: Focus(
                onKeyEvent: (node, e) {
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.escape) {
                    setState(() => _typing = false);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: ValueKey("knobTyped-$label"),
                  controller: _typed,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: look.studio.text),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                    filled: true,
                    fillColor: look.studio.inset,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: look.colors.primary)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: look.colors.primary)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: look.colors.primary)),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            )
          else if (reading)
            Tooltip(
              message: "Double-click to type a value",
              waitDuration: const Duration(milliseconds: 800),
              child: GestureDetector(
                key: ValueKey("knobValue-$label"),
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _type,
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: look.studio.text)),
              ),
            ),
        ],
      ),
    );
  }
}

/// DeviceKnob is the Chain's knob for an editor outside this file (the
/// Instrument's, say): dragged up to turn it right, double-clicked to put it
/// back to [initial]; [log] spreads its travel as hertz and seconds want.
class DeviceKnob extends StatelessWidget {
  final String label;
  final String text;
  final double value, initial, min, max;
  final bool log;
  final double size;
  final Color accent;
  final Color ink;
  final bool bipolar;
  final void Function(double v, {bool transient}) onChanged;
  final VoidCallback onCommit;

  /// menu is its right-click's choices, and modulated whether something
  /// moves it (a pink ring), as a device's own knobs have; own whether the
  /// copies edited have their own value (see _Knob.own).
  final List<(String, VoidCallback)> menu;
  final bool modulated;
  final bool own;

  const DeviceKnob({
    this.menu = const [],
    this.modulated = false,
    this.own = false,
    required this.label,
    required this.text,
    required this.value,
    required this.initial,
    required this.min,
    required this.max,
    required this.accent,
    required this.ink,
    required this.onChanged,
    required this.onCommit,
    this.log = false,
    this.size = 38,
    this.bipolar = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _Knob(
        menu: menu,
        modulated: modulated,
        own: own,
        label: label,
        text: text,
        value: value,
        initial: initial,
        range: _Range(min, max, log: log),
        size: size,
        accent: accent,
        ink: ink,
        bipolar: bipolar,
        onChanged: onChanged,
        onCommit: onCommit,
      );
}

/// typedValue is what was [typed] for a knob that reads [shown], in its own
/// terms -- "50" a half where it reads in percent, "1.2k" or "1200" hertz
/// -- held to [min] and [max]; null where nothing like a number was typed.
double? typedValue(String typed, String shown, double min, double max) {
  var t = typed.trim().replaceAll("\u2212", "-").replaceAll(",", ".");
  var m = RegExp(r"-?\d*\.?\d+").firstMatch(t);
  if (m == null) return null;
  var v = double.tryParse(m.group(0)!);
  if (v == null) return null;
  var rest = t.substring(m.end).trim().toLowerCase();
  // In thousands: "k", or kilohertz.
  if (rest.startsWith("k")) v *= 1000;
  // A share the knob shows in percent: as a percent unless typed as one.
  var percent = shown.trim().endsWith("%");
  if (percent && max <= 2.0001) v /= 100;
  // Shown in kilohertz, a small number typed is in kilohertz too.
  if (!rest.startsWith("k") && shown.contains("kHz") && v < min) v *= 1000;
  return v.clamp(math.min(min, max), math.max(min, max)).toDouble();
}

/// _sweep is a knob's travel, from seven o'clock round to five.
const _sweepStart = math.pi * 0.75, _sweep = math.pi * 1.5;

class _KnobFace extends CustomPainter {
  final double unit;

  /// accent and from: see _Knob.accent and _Knob.bipolar.
  final Color? accent;
  final double from;
  _KnobFace(this.unit, {this.accent, this.from = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (accent != null) return _dark(canvas, size, accent!);
    var c = size.center(Offset.zero);
    var r = size.width / 2;
    var ring = Rect.fromCircle(center: c, radius: r - 2);
    canvas.drawArc(
        ring,
        _sweepStart,
        _sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF9A9EA5));
    canvas.drawArc(
        ring,
        _sweepStart,
        _sweep * unit,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2E9BF0));
    var body = r - 7;
    canvas.drawCircle(
        c + const Offset(0, 1.5), body, Paint()..color = Colors.black26);
    canvas.drawCircle(
        c,
        body,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [Color(0xFFFAFAFB), Color(0xFFA9AEB6)])
              .createShader(Rect.fromCircle(center: c, radius: body)));
    var a = _sweepStart + _sweep * unit;
    canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * body * 0.25,
        c + Offset(math.cos(a), math.sin(a)) * body * 0.85,
        Paint()
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = _silverInk);
  }

  /// _dark is the Chain's knob: a dark track, the arc in its accent from
  /// [from] to its value, a dark body and a light pointer.
  void _dark(Canvas canvas, Size size, Color accent) {
    var c = size.center(Offset.zero);
    var r = size.width / 2;
    var ring = Rect.fromCircle(center: c, radius: r - 2);
    var stroke = math.max(2.5, size.width * 0.1);
    canvas.drawArc(
        ring,
        _sweepStart,
        _sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2C2843));
    var a0 = _sweepStart + _sweep * from.clamp(0.0, 1.0),
        a1 = _sweepStart + _sweep * unit;
    if ((a1 - a0).abs() > 0.01) {
      canvas.drawArc(
          ring,
          math.min(a0, a1),
          (a1 - a0).abs(),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = accent);
    }
    var body = r - stroke - 2;
    canvas.drawCircle(
        c,
        body,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.2, -0.36),
                  colors: [Color(0xFF46405F), Color(0xFF211D33)])
              .createShader(Rect.fromCircle(center: c, radius: body)));
    canvas.drawCircle(
        c,
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF3E3958));
    canvas.drawLine(
        c + Offset(math.cos(a1), math.sin(a1)) * body * 0.15,
        c + Offset(math.cos(a1), math.sin(a1)) * body * 0.85,
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFF3F0F8));
  }

  @override
  bool shouldRepaint(_KnobFace old) =>
      old.unit != unit || old.accent != accent || old.from != from;
}

/// _VuNeedle is the gain-reduction meter: a needle at rest on the right,
/// swinging left as the compressor takes level off, thirty decibels across.
class _VuNeedle extends CustomPainter {
  final double reduction;
  _VuNeedle(this.reduction);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.clipRect(Offset.zero & size);
    // Across the top: from thirty decibels down on the left to none, the
    // pivot just under the bottom edge, as on a VU meter.
    const swing = 0.8; // radians either side of upright
    var radius = math.min(h * 0.78, (w / 2 - 26) / math.sin(swing));
    var pivot = Offset(w / 2, h - 6 + radius * 0.08);
    double angle(double db) =>
        -math.pi / 2 - swing + (1 - (db / 30).clamp(0.0, 1.0)) * 2 * swing;
    var arc = Rect.fromCircle(center: pivot, radius: radius);
    canvas.drawArc(
        arc,
        angle(30),
        2 * swing,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _faceInk);
    canvas.drawArc(
        arc.deflate(-4),
        angle(30),
        angle(20) - angle(30),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFFC0392B));
    for (var db in const [0, 2, 4, 6, 8, 10, 15, 20, 30]) {
      var a = angle(db.toDouble());
      var dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          pivot + dir * radius,
          pivot + dir * (radius + 7),
          Paint()
            ..strokeWidth = 1.2
            ..color = _faceInk);
      var tp =
          paintedLabel("$db", const TextStyle(fontSize: 10, color: _faceInk));
      tp.paint(canvas,
          pivot + dir * (radius + 16) - Offset(tp.width / 2, tp.height / 2));
    }
    var tp = paintedLabel("GAIN REDUCTION  dB",
        const TextStyle(fontSize: 9, letterSpacing: 1, color: _faceDim));
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, pivot.dy - radius * 0.45));
    var a = angle(reduction);
    canvas.drawLine(
        pivot,
        pivot + Offset(math.cos(a), math.sin(a)) * (radius + 4),
        Paint()
          ..strokeWidth = 1.8
          ..color = const Color(0xFF1A1A1A));
  }

  @override
  bool shouldRepaint(_VuNeedle old) => old.reduction != reduction;
}

/// _TransferCurve is what goes in along the bottom against what comes out up
/// the side: the diagonal is no compressor at all.
class _TransferCurve extends CustomPainter {
  final Dynamics comp;
  final double input;

  /// line, grid and dim are its colours: on a cream face by default, or the
  /// Chain's dark display.
  final Color line, grid, dim;
  _TransferCurve(this.comp, this.input,
      {this.line = _faceInk,
      this.grid = const Color(0xFFD3C7A4),
      this.dim = _faceDim});

  static const _lo = -60.0;

  @override
  void paint(Canvas canvas, Size size) {
    var pad = 14.0;
    var w = size.width - 2 * pad, h = size.height - 2 * pad;
    double px(double db) => pad + (db - _lo) / -_lo * w;
    double py(double db) => pad + h - ((db - _lo) / -_lo).clamp(0.0, 1.0) * h;
    var grid = Paint()..color = this.grid;
    for (var db = -48.0; db <= 0; db += 12) {
      canvas.drawLine(Offset(px(db), pad), Offset(px(db), pad + h), grid);
      canvas.drawLine(Offset(pad, py(db)), Offset(pad + w, py(db)), grid);
    }
    canvas.drawLine(Offset(px(_lo), py(_lo)), Offset(px(0), py(0)),
        Paint()..color = const Color(0xFFB5A77F));
    canvas.drawLine(
        Offset(px(comp.threshold), pad),
        Offset(px(comp.threshold), pad + h),
        Paint()..color = const Color(0xFFC0392B));
    var path = Path();
    for (var i = 0; i <= 120; i++) {
      var db = _lo + i / 120 * -_lo;
      var out = comp.reducedDb(db) + comp.totalMakeupDb;
      var p = Offset(px(db), py(out));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = comp.on ? line : dim);
    if (input > _lo) {
      var out = comp.on ? comp.reducedDb(input) + comp.totalMakeupDb : input;
      canvas.drawCircle(Offset(px(input), py(out)), 5,
          Paint()..color = const Color(0xFFE08A1E));
    }
  }

  @override
  bool shouldRepaint(_TransferCurve old) =>
      old.input != input ||
      !identical(old.comp, comp);
}

/// _LedMeter is a level meter of lit segments: green, then amber, then red
/// in the top six decibels.
class _LedMeter extends CustomPainter {
  final double db;
  _LedMeter(this.db);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
        Paint()..color = const Color(0xFF2B2F36));
    const segments = 30;
    var gap = 1.5;
    var seg = (size.height - 4 - gap * (segments - 1)) / segments;
    var lit = ((db + 60) / 60 * segments).clamp(0, segments).floor();
    for (var i = 0; i < segments; i++) {
      var level = -60 + (i + 1) * 2.0;
      var colour = level > -6
          ? const Color(0xFFE5484D)
          : level > -18
              ? const Color(0xFFF2C94C)
              : const Color(0xFF52C26A);
      var y = size.height - 2 - (i + 1) * seg - i * gap;
      canvas.drawRect(Rect.fromLTWH(3, y, size.width - 6, seg),
          Paint()..color = i < lit ? colour : colour.withValues(alpha: 0.12));
    }
  }

  @override
  bool shouldRepaint(_LedMeter old) => old.db != db;
}

/// _MiniCurve is a folded EQ: its curve, small.
class _MiniCurve extends CustomPainter {
  final Eq eq;
  _MiniCurve(this.eq);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
        Paint()..color = const Color(0xFF16273B));
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2),
        Paint()..color = const Color(0xFF3A5272));
    var shown = eq.copyWith(on: true);
    // Turned on its side, as the folded device is tall: low at the bottom,
    // a lift to the right.
    var p = Path();
    for (var i = 0; i <= 60; i++) {
      var y = h - i / 60 * h;
      var f = 20 * math.pow(1000, i / 60).toDouble();
      var x = w / 2 + shown.responseDb(f).clamp(-12.0, 12.0) / 12 * (w / 2 - 3);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = eq.on ? const Color(0xFFE6F2FF) : _eqDim);
  }

  @override
  bool shouldRepaint(_MiniCurve old) =>
      !identical(old.eq, eq);
}

/// _ReductionBar is gain reduction as a bar falling from the top: twenty
/// decibels fills it.
class _ReductionBar extends CustomPainter {
  final double reduced;
  _ReductionBar(this.reduced);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
        Paint()..color = const Color(0xFF2B2F36));
    var depth = (reduced / 20).clamp(0.0, 1.0) * (size.height - 4);
    canvas.drawRect(Rect.fromLTWH(2, 2, size.width - 4, depth),
        Paint()..color = const Color(0xFFF0A33C));
  }

  @override
  bool shouldRepaint(_ReductionBar old) => old.reduced != reduced;
}

// ---- Meters and the limiter

/// MeterDevice is a strip's level as it leaves -- the channel's after its
/// fader, or the master's, which is what is heard -- each side with its
/// held peak and the loudest it has been.
class MeterDevice extends StatefulWidget {
  static const width = 180.0;
  final CanvasController controller;
  final String? channel;
  final String id;
  final String title;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const MeterDevice(
      {required this.controller,
      required this.channel,
      required this.id,
      required this.title,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<MeterDevice> createState() => _MeterDeviceState();
}

class _MeterDeviceState extends State<MeterDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;
  (double, double) _now = (-90, -90);
  (double, double) _held = (-90, -90);

  /// _loudest is the highest peak since it was last cleared, per side.
  (double, double) _loudest = (-90, -90);

  @override
  void tick() {
    var (l, r) = strip.levels;
    _now = (gainToDb(l), gainToDb(r));
    _held = (
      math.max(_now.$1, _held.$1 - 0.66),
      math.max(_now.$2, _held.$2 - 0.66),
    );
    _loudest = (
      math.max(_now.$1, _loudest.$1),
      math.max(_now.$2, _loudest.$2),
    );
  }

  String _db(double v) => v > -60 ? v.toStringAsFixed(1) : "−∞";

  @override
  Widget build(BuildContext context) {
    Widget pair(double width) =>
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var (i, (side, db))
              in [("L", _now.$1), ("R", _now.$2)].indexed) ...[
            // A gap between the two, not after them: folded, they fill
            // the fold's 26 exactly.
            if (i > 0) const SizedBox(width: 4),
            SizedBox(
              width: width,
              child: CustomPaint(
                  key: ValueKey("meter$side-${widget.id}"),
                  size: Size.infinite,
                  painter: _LedMeter(db)),
            ),
          ],
        ]);
    var clipped = _loudest.$1 > -0.1 || _loudest.$2 > -0.1;
    return DeviceFrame(
      id: widget.id,
      title: widget.title,
      skin: DeviceSkin.navy,
      folded: widget.folded,
      onFold: widget.onFold,
      width: MeterDevice.width,
      height: widget.height,
      foldedBody: pair(11),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(children: [
          // The loudest yet, red where it touched the top; a click clears
          // it.
          GestureDetector(
            key: ValueKey("meterLoudest-${widget.id}"),
            onTap: () => setState(() => _loudest = (-90, -90)),
            child: Tooltip(
              message: "The loudest peak so far: click to clear",
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: clipped
                      ? const Color(0xFFE5484D)
                      : const Color(0xFF132233),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text("${_db(_loudest.$1)}  ${_db(_loudest.$2)}",
                    style: const TextStyle(
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: _eqInk)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: pair(20)),
              // The scale, top to bottom.
              SizedBox(
                width: 26,
                child: CustomPaint(painter: _MeterScale()),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text("${_db(_held.$1)}  ${_db(_held.$2)} dB",
              style: const TextStyle(
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: _eqDim)),
        ]),
      ),
    );
  }
}

/// _MeterScale is the decibel marks beside a _LedMeter, which runs from -60
/// at the bottom to 0 at the top.
class _MeterScale extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var db in const [0, -6, -12, -18, -24, -36, -48, -60]) {
      var y = 2 + (-db / 60) * (size.height - 4);
      var tp = paintedLabel("$db", const TextStyle(fontSize: 9, color: _eqDim));
      tp.paint(canvas, Offset(size.width - tp.width, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_MeterScale old) => false;
}

/// LimiterDevice is the master's limiter, last in its chain, as the chain
/// prototype has it (Ken, 2026-11-08): its screen the turn-down it has made
/// lately against its ceiling, its Ceiling, Release and Look-ahead, and
/// the delay its look-ahead adds on its bar.
class LimiterDevice extends StatefulWidget {
  static const width = 280.0;
  final CanvasController controller;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  /// reductionDb is how far it is turning the sound down now, in dB (zero
  /// or less).
  final double reductionDb;
  const LimiterDevice(
      {required this.controller,
      required this.folded,
      required this.onFold,
      required this.height,
      this.reductionDb = 0,
      super.key});

  @override
  State<LimiterDevice> createState() => _LimiterDeviceState();
}

class _LimiterDeviceState extends State<LimiterDevice> {
  /// _history is the turn-down at each of the last readings, oldest first.
  final List<double> _history = [];

  /// _reduction is the turn-down read now: none where nothing has been
  /// read (silence reads as minus infinity, not as all the way down).
  double get _reduction => widget.reductionDb.isFinite
      ? widget.reductionDb.clamp(-24.0, 0.0)
      : 0.0;

  @override
  void didUpdateWidget(LimiterDevice old) {
    super.didUpdateWidget(old);
    _history.add(_reduction);
    if (_history.length > 160) _history.removeAt(0);
  }

  void _write(MasterMix m, {bool transient = false}) {
    var c = widget.controller;
    c.beginInteraction();
    c.setMasterMix(m, transient: true);
    if (!transient) c.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var c = widget.controller;
    var m = c.document.masterMix;
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var (icon, accent) = deviceGroupLook(DeviceGroup.dynamics);
    var reading = "${m.ceilingDb.toStringAsFixed(1)} dBTP";
    return DeviceFrame(
      id: "limiter",
      title: "Limiter",
      skin: skin,
      icon: icon,
      accent: accent,
      help: "Last in the chain: no peak gets past its ceiling, in playing or "
          "in an export. It looks ahead, so it turns down before a peak "
          "arrives -- which delays everything by that much -- and lets go "
          "over its release.",
      on: m.limiter,
      powerKey: const ValueKey("limitOn"),
      onPower: (v) => _write(m.copyWith(limiter: v)),
      onReset: () => _write(m.copyWith(
          ceilingDb: -1, limiterAheadMs: 5, limiterReleaseMs: 50)),
      onAB: () => widget.controller.toggleABOf(
          "$mixerMasterKey|limiter",
          (m.ceilingDb, m.limiterAheadMs, m.limiterReleaseMs),
          (o) {
        var (ceiling, ahead, release) = o as (double, double, double);
        _write(
            widget.controller.document.masterMix.copyWith(
                ceilingDb: ceiling,
                limiterAheadMs: ahead,
                limiterReleaseMs: release),
            transient: true);
      }),
      showingB: widget.controller.showingBOf("$mixerMasterKey|limiter"),
      folded: widget.folded,
      onFold: widget.onFold,
      width: LimiterDevice.width,
      height: widget.height,
      besideDisplay: 200,
      besideSettings: 180,
      // Its look-ahead delays the whole mix by as much.
      barExtras: [
        // How far it is holding the mix down now.
        if (_reduction > 0.05 && widget.controller.chainBadges)
          _ReadingBadge(
              key: const ValueKey("gainBadge-limiter"),
              text: "−${_reduction.toStringAsFixed(1)}"),
        _StripPresetPicker(
          key: const ValueKey("stripPreset-limiter"),
          label: StripPart.limiter.label,
                kept: () => _stripKept(StripPart.limiter),
          name: c.presetNameOf(mixerMasterKey, "limiter"),
          builtIn: [
            for (var (n, v) in limiterPresets)
              (
                n,
                {
                  "ceiling": v.ceilingDb,
                  "ahead": v.aheadMs,
                  "release": v.releaseMs
                }
              ),
          ],
          onPick: (name, value) {
            _write(m.copyWith(
                ceilingDb: (value["ceiling"] as num?)?.toDouble(),
                limiterAheadMs: (value["ahead"] as num?)?.toDouble(),
                limiterReleaseMs: (value["release"] as num?)?.toDouble()));
            c.setPresetName(mixerMasterKey, "limiter", name);
          },
          onDefault: () {
            _write(m.copyWith(
                ceilingDb: -1, limiterAheadMs: 5, limiterReleaseMs: 50));
            c.setPresetName(mixerMasterKey, "limiter", null);
          },
          onSave: () => saveStripPreset(context, StripPart.limiter, {
            "ceiling": m.ceilingDb,
            "ahead": m.limiterAheadMs,
            "release": m.limiterReleaseMs,
          }),
        ),
        Container(
          key: const ValueKey("limitLatency"),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: look.studio.edge)),
          child: Text("${m.limiterAheadMs.toStringAsFixed(1)} ms",
              style: TextStyle(fontSize: 9.5, color: look.studio.muted)),
        ),
      ],
      summary: "$reading · ${_reduction.toStringAsFixed(1)} dB",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        for (var (key, label, text, value, min, max, initial, log, set) in [
          (
            "limitCeiling",
            "Ceiling",
            reading,
            m.ceilingDb,
            -12.0,
            0.0,
            -1.0,
            false,
            (double v) =>
                m.copyWith(ceilingDb: (v * 10).roundToDouble() / 10)
          ),
          (
            "limitRelease",
            "Release",
            "${m.limiterReleaseMs.round()} ms",
            m.limiterReleaseMs,
            5.0,
            1000.0,
            50.0,
            true,
            (double v) => m.copyWith(limiterReleaseMs: v.roundToDouble())
          ),
          (
            "limitAhead",
            "Look-ahead",
            "${m.limiterAheadMs.toStringAsFixed(1)} ms",
            m.limiterAheadMs,
            0.5,
            20.0,
            5.0,
            true,
            (double v) =>
                m.copyWith(limiterAheadMs: (v * 10).roundToDouble() / 10)
          ),
        ])
          _Knob(
            key: ValueKey(key),
            label: label,
            text: text,
            value: value,
            initial: initial,
            range: _Range(min, max, log: log),
            size: switch (tier) {
              DeviceTier.large => 46,
              DeviceTier.medium => 38,
              _ => 30,
            },
            accent: accent,
            ink: skin.ink,
            onChanged: (v, {transient = false}) =>
                _write(set(v), transient: transient),
            onCommit: c.endInteraction,
          ),
      ],
      display: CustomPaint(
        key: const ValueKey("limitScreen"),
        painter: _LimitHistory(
            List.of(_history), m.ceilingDb, accent, look.studio),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// _LimitHistory is the limiter's turn-down over the last readings, down
/// from the top (none) to twelve decibels, and its ceiling written.
class _LimitHistory extends CustomPainter {
  final List<double> history;
  final double ceiling;
  final Color accent;
  final StudioColors studio;
  _LimitHistory(this.history, this.ceiling, this.accent, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var grid = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var db = 3; db < 12; db += 3) {
      var y = size.height * db / 12;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), grid);
    }
    if (history.isNotEmpty) {
      var step = size.width / math.max(1, 159);
      var x0 = size.width - (history.length - 1) * step;
      var path = Path()..moveTo(x0, 0);
      for (var (i, db) in history.indexed) {
        var y = size.height * (-db).clamp(0.0, 12.0) / 12;
        path.lineTo(x0 + i * step, y);
      }
      path
        ..lineTo(size.width, 0)
        ..close();
      canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.35));
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2),
        Paint()..color = const Color(0xFFE5534B));
    var now = history.isEmpty ? 0.0 : history.last;
    var tp = TextPainter(
        text: TextSpan(
            text: "ceiling ${ceiling.toStringAsFixed(1)} dB · "
                "${now < -0.05 ? "down ${(-now).toStringAsFixed(1)} dB" : "not turning down"}",
            style: TextStyle(fontSize: 10, color: studio.muted)),
        maxLines: 1,
        ellipsis: "…",
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: size.width - 12);
    tp.paint(canvas, Offset(6, size.height - tp.height - 4));
  }

  @override
  bool shouldRepaint(_LimitHistory old) => true;
}

// ---- Ducking

/// DuckDevice is a channel turning the others down while it is heard -- see
/// Ducking -- as a unit beside the compressor: the shape of the dip on its
/// screen, how far the others are down now, knobs for the depth and the
/// times, and which channels it ducks.
class DuckDevice extends StatefulWidget {
  static const width = 600.0;
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const DuckDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<DuckDevice> createState() => _DuckDeviceState();
}

class _DuckDeviceState extends State<DuckDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _now is how far, in decibels, the channels it ducks are down at the
  /// playhead.
  double _now = 0;

  List<TimelineChannel> get _others => [
        for (var c in widget.controller.timelineChannels)
          if (c.key != widget.channel) c,
      ];

  @override
  void tick() {
    var c = widget.controller;
    var duck = strip.gone ? const Ducking() : strip.duck;
    var ducked = _others
        .where((o) => !duck.except.contains(o.key))
        .map((o) => o.key)
        .firstOrNull;
    var env = ducked == null ? null : c.duckEnvelopeOf(ducked);
    var rate = math.max(1, c.document.frameRate);
    _now = env == null || !duck.on
        ? 0
        : -gainToDb(envelopeAt(env, c.runFrame / rate)).clamp(-60.0, 0.0);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (strip.gone) return const SizedBox.shrink();
          var duck = strip.duck;
          void write(Ducking d, {bool transient = false}) =>
              strip.writeDuck(d, transient: transient);
          return DeviceFrame(
            id: "duck",
            title: "Ducker",
            actions: [
              if (widget.controller.canRemovePart(widget.channel, stripDuck))
                IconButton(
                  key: const ValueKey("deviceRemove-duck"),
                  tooltip: "Take the Ducker out",
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      widget.controller.removePart(widget.channel, stripDuck),
                ),
            ],
            skin: DeviceSkin.silver,
            icon: deviceGroupLook(DeviceGroup.dynamics).$1,
            accent: deviceGroupLook(DeviceGroup.dynamics).$2,
            help: "Turns the other channels down while this one plays -- a "
                "voice over music -- by Depth, easing down and back.",
            on: duck.on,
            powerKey: const ValueKey("duckOn"),
            onPower: (v) => write(duck.copyWith(on: v)),
            onAB: () => widget.controller.toggleABOf(
                "${widget.channel}|duck",
                duck,
                (o) => write(o as Ducking, transient: true)),
            showingB: widget.controller.showingBOf("${widget.channel}|duck"),
            onReset: () => write(Ducking(on: duck.on, except: duck.except)),
            barExtras: [
              // How far it is turning the others down now.
              if (_now > 0.05 && widget.controller.chainBadges)
                _ReadingBadge(
                    key: const ValueKey("gainBadge-duck"),
                    text: "−${_now.toStringAsFixed(1)}"),
              _StripPresetPicker(
                key: const ValueKey("stripPreset-duck"),
                label: StripPart.duck.label,
                kept: () => _stripKept(StripPart.duck),
                name: widget.controller
                    .presetNameOf(widget.channel, "duck"),
                builtIn: [for (var (n, v) in duckPresets) (n, v.toJson())],
                onPick: (name, value) {
                  // Its own list of who is not turned down is kept.
                  write(Ducking.fromJson(value).copyWith(except: duck.except));
                  widget.controller
                      .setPresetName(widget.channel, "duck", name);
                },
                onDefault: () {
                  write(Ducking(on: duck.on, except: duck.except));
                  widget.controller
                      .setPresetName(widget.channel, "duck", null);
                },
                onSave: () =>
                    saveStripPreset(context, StripPart.duck, duck.toJson()),
              ),
            ],
            folded: widget.folded,
            onFold: widget.onFold,
            width: DuckDevice.width,
            height: widget.height,
            foldedBody: Column(children: [
              const Text("Duck",
                  style: TextStyle(fontSize: 10, color: _silverDim)),
              const SizedBox(height: 4),
              Expanded(
                child: CustomPaint(
                    key: const ValueKey("duckFolded"),
                    size: const Size(14, double.infinity),
                    painter: _ReductionBar(_now)),
              ),
              const SizedBox(height: 4),
              Text(duck.on ? "${duck.depthDb.round()}" : "off",
                  style: const TextStyle(fontSize: 10, color: _silverInk)),
            ]),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 280, child: _screen(duck, write)),
                    const SizedBox(width: 10),
                    // How far the others are down now.
                    _NowMeter(barKey: const ValueKey("duckNow"), now: _now),
                    const SizedBox(width: 12),
                    Expanded(child: _controls(duck, write)),
                  ]),
            ),
          );
        },
      );

  /// _segment is one of the card's choices, as the Chain's chips: the one
  /// picked filled in the accent, the rest outlined on the dark card.
  Widget _segment(String label, bool on, Key key, VoidCallback onTap) {
    var look = MixerLook.of(context);
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: on ? look.colors.primary : look.studio.inset,
          borderRadius: BorderRadius.circular(5),
          border:
              Border.all(color: on ? look.colors.primary : look.studio.edge),
        ),
        child: Text(label,
            maxLines: 1,
            style: TextStyle(
                fontSize: 11,
                color: on ? look.colors.onPrimary : look.studio.text)),
      ),
    );
  }

  /// _screen is the dip drawn on the cream screen, and under it its shape.
  Widget _screen(
          Ducking duck, void Function(Ducking, {bool transient}) write) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _cream,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF8D8F93), width: 2),
            ),
            child: CustomPaint(
                key: const ValueKey("duckShape"),
                painter: _DuckShape(duck, strip.name)),
          ),
        ),
        const SizedBox(height: 8),
        const Text("Shape",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: _silverDim)),
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.center, runSpacing: 4, children: [
          for (var c in DuckCurve.values)
            _segment(c.label, duck.curve == c, ValueKey("duckCurve-${c.name}"),
                () => write(duck.copyWith(curve: c))),
        ]),
      ]);

  Widget _controls(
      Ducking duck, void Function(Ducking, {bool transient}) write) {
    Widget knob(String label, String key, double value, double initial,
            _Range range, String text, Ducking Function(double) apply) =>
        _Knob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value,
          initial: initial,
          range: range,
          size: 56,
          onChanged: (v, {transient = false}) =>
              write(apply(v), transient: transient),
          onCommit: strip.commit,
        );
    var others = _others;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        knob(
            "Depth",
            "duckDepth",
            duck.depthDb,
            -10,
            const _Range(-40, -1),
            "${duck.depthDb.toStringAsFixed(1)} dB",
            (v) => duck.copyWith(depthDb: (v * 2).roundToDouble() / 2)),
        knob(
            "Down",
            "duckAttack",
            duck.attack,
            0.3,
            const _Range(0, 2),
            "${duck.attack.toStringAsFixed(2)} s",
            (v) => duck.copyWith(attack: (v * 100).roundToDouble() / 100)),
        knob(
            "Back",
            "duckRelease",
            duck.release,
            0.8,
            const _Range(0, 4),
            "${duck.release.toStringAsFixed(2)} s",
            (v) => duck.copyWith(release: (v * 100).roundToDouble() / 100)),
      ]),
      const SizedBox(height: 10),
      Text(
          others.isEmpty
              ? "No other channels to duck"
              : "Ducks, while ${strip.name} is heard:",
          style: const TextStyle(fontSize: 10, color: _silverDim)),
      const SizedBox(height: 4),
      Expanded(
        child: SingleChildScrollView(
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            // Lit is ducked; a click leaves it alone.
            for (var o in others)
              _segment(
                  o.name,
                  !duck.except.contains(o.key),
                  ValueKey("duckExcept-${o.key}"),
                  () => write(duck.copyWith(except: [
                        for (var k in duck.except)
                          if (k != o.key) k,
                        if (!duck.except.contains(o.key)) o.key,
                      ]))),
          ]),
        ),
      ),
    ]);
  }
}

/// _NowMeter is how far the ducked channels are down now: a bar, under a
/// label that never wraps, over the reading -- in dB while it is ducking,
/// and nothing when it is not.
class _NowMeter extends StatelessWidget {
  final Key barKey;
  final double now;
  const _NowMeter({required this.barKey, required this.now});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        child: Column(children: [
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text("Now",
                maxLines: 1, style: TextStyle(fontSize: 10, color: _silverDim)),
          ),
          const SizedBox(height: 4),
          Expanded(
              child: CustomPaint(
                  key: barKey,
                  size: Size.infinite,
                  painter: _ReductionBar(now))),
          const SizedBox(height: 4),
          SizedBox(
            height: 13,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(now > 0.05 ? "−${now.toStringAsFixed(1)} dB" : "",
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 9,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: _silverInk)),
            ),
          ),
        ]),
      );
}

/// DuckedDevice is the Ducker as the channel it turns down sees it: first in
/// its chain, as the dip is made to its sounds as they come in. Which voices
/// duck it, the dips drawn across the run with the playhead, how far down it
/// is now, and its switch -- off leaves this channel alone. The dip's
/// settings belong to the voice, for every channel it ducks (see Ducking),
/// so the knobs here turn the voice's, and say so.
///
/// The dips are worked out ahead from the voice's recordings, so they lead
/// each line rather than chase it.
class DuckedDevice extends StatefulWidget {
  static const width = 460.0;
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const DuckedDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<DuckedDevice> createState() => _DuckedDeviceState();
}

class _DuckedDeviceState extends State<DuckedDevice>
    with SingleTickerProviderStateMixin, _Metered {
  @override
  CanvasController get meteredBy => widget.controller;

  /// _now is how far, in decibels, the channel is down at the playhead.
  double _now = 0;

  @override
  void tick() {
    var c = widget.controller;
    var env = c.duckEnvelopeOf(widget.channel);
    var rate = math.max(1, c.document.frameRate);
    _now = env == null
        ? 0
        : -gainToDb(envelopeAt(env, c.runFrame / rate)).clamp(-60.0, 0.0);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          var c = widget.controller;
          var by = c.duckersOf(widget.channel);
          if (by.isEmpty) return const SizedBox.shrink();
          var on = by.any((v) => !v.mix.duck.except.contains(widget.channel));
          var names = by.map((v) => v.name).join(", ");
          var rate = math.max(1, c.document.frameRate);
          return DeviceFrame(
            id: "ducked",
            title: "Ducker",
            actions: [
              IconButton(
                key: const ValueKey("deviceRemove-ducked"),
                tooltip: "Take it out: this channel is not ducked",
                icon: const Icon(Icons.close),
                onPressed: () => c.removePart(widget.channel, stripDucked),
              ),
            ],
            skin: DeviceSkin.silver,
            icon: deviceGroupLook(DeviceGroup.dynamics).$1,
            accent: deviceGroupLook(DeviceGroup.dynamics).$2,
            help: "This channel is turned down while the ones that duck it "
                "play: worked out ahead, as the sounds come in.",
            on: on,
            powerKey: const ValueKey("duckedOn"),
            onPower: (v) => c.setDuckedBy(widget.channel, v),
            folded: widget.folded,
            onFold: widget.onFold,
            width: DuckedDevice.width,
            height: widget.height,
            foldedBody: Column(children: [
              const Text("Duck",
                  style: TextStyle(fontSize: 10, color: _silverDim)),
              const SizedBox(height: 4),
              Expanded(
                child: CustomPaint(
                    key: const ValueKey("duckedFolded"),
                    size: const Size(14, double.infinity),
                    painter: _ReductionBar(_now)),
              ),
            ]),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("By $names, ahead of each line",
                        key: const ValueKey("duckedBy"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11, color: _silverInk)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _cream,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFF8D8F93), width: 2),
                                ),
                                child: CustomPaint(
                                    key: const ValueKey("duckedDips"),
                                    painter: _RunDips(
                                        on
                                            ? c.duckEnvelopeOf(
                                                    widget.channel) ??
                                                const []
                                            : const [],
                                        c.document.playFrames / rate,
                                        c.runFrame / rate)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _NowMeter(
                                barKey: const ValueKey("duckedNow"), now: _now),
                          ]),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      for (var v in by)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextButton(
                            key: ValueKey("duckedOpen-${v.key}"),
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: _silverInk),
                            onPressed: () =>
                                c.openEffects(v.key, device: "duck"),
                            child: Text(
                                "${v.name}: ${v.mix.duck.depthDb.toStringAsFixed(1)} dB",
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ]),
                  ]),
            ),
          );
        },
      );
}

/// _RunDips is a channel's ducking over the whole run: how far down it is,
/// forty decibels down the screen, with the playhead.
class _RunDips extends CustomPainter {
  final List<GainPoint> env;
  final double total, now;
  _RunDips(this.env, this.total, this.now);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    var w = size.width - 2 * pad, h = size.height - 2 * pad;
    if (w <= 0 || h <= 0 || total <= 0) return;
    double x(double t) => pad + (t / total).clamp(0.0, 1.0) * w;
    double y(double gain) => pad + (-gainToDb(gain).clamp(-40.0, 0.0) / 40) * h;
    var grid = Paint()..color = const Color(0xFFD3C7A4);
    for (var db = 0.0; db >= -40; db -= 10) {
      var gy = pad + -db / 40 * h;
      canvas.drawLine(Offset(pad, gy), Offset(pad + w, gy), grid);
    }
    var path = Path()..moveTo(x(0), y(env.isEmpty ? 1 : env.first.gain));
    for (var p in env) {
      path.lineTo(x(p.time), y(p.gain));
    }
    path.lineTo(x(total), y(env.isEmpty ? 1 : env.last.gain));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = _faceInk);
    canvas.drawLine(Offset(x(now), pad), Offset(x(now), pad + h),
        Paint()..color = const Color(0xFFE08A1E));
  }

  @override
  bool shouldRepaint(_RunDips old) =>
      old.now != now || old.total != total || !identical(old.env, env);
}

/// _DuckShape is one dip: the others at full level, down by the depth over
/// the attack in the chosen shape, held while the channel is heard, and back
/// over the release.
class _DuckShape extends CustomPainter {
  final Ducking duck;
  final String name;
  _DuckShape(this.duck, this.name);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 14.0;
    var w = size.width - 2 * pad, h = size.height - 2 * pad;
    // Forty decibels down the screen; time along it, the held part a fixed
    // second and a half so the ramps read at their own lengths.
    double y(double gain) => pad + (-gainToDb(gain).clamp(-40.0, 0.0) / 40) * h;
    const hold = 1.5;
    var lead = 0.4;
    var total = lead + duck.attack + hold + duck.release + lead;
    double x(double t) => pad + t / total * w;
    var grid = Paint()..color = const Color(0xFFD3C7A4);
    for (var db = 0.0; db >= -40; db -= 10) {
      var gy = pad + -db / 40 * h;
      canvas.drawLine(Offset(pad, gy), Offset(pad + w, gy), grid);
    }
    // When the channel listened for is heard.
    var from = lead + duck.attack, to = from + hold;
    canvas.drawRect(Rect.fromLTRB(x(from), pad, x(to), pad + h),
        Paint()..color = const Color(0xFFE08A1E).withValues(alpha: 0.18));
    var tp = TextPainter(
        text: TextSpan(
            text: name, style: const TextStyle(fontSize: 9, color: _faceDim)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…")
      ..layout(maxWidth: math.max(0, x(to) - x(from) - 4));
    tp.paint(canvas, Offset(x(from) + 2, pad + h - tp.height - 2));
    var env = duckEnvelope([(from, to)],
        gain: dbToGain(duck.depthDb),
        attack: duck.attack,
        release: duck.release,
        curve: duck.curve);
    var path = Path()..moveTo(x(0), y(1));
    for (var p in env) {
      path.lineTo(x(p.time), y(p.gain));
    }
    path.lineTo(x(total), y(1));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = duck.on ? _faceInk : _faceDim);
  }

  @override
  bool shouldRepaint(_DuckShape old) =>
      old.name != name ||
      !identical(old.duck, duck);
}

/// ParamDevice is a device in a return's chain, drawn from its kind's table
/// of settings: a knob for each, its switch, and a way to take it out. A
/// reverb or a delay -- and whatever device is added to the table next.
class ParamDevice extends StatelessWidget {
  final CanvasController controller;

  /// owner is the strip the device is on: a return's id, or a channel's
  /// key -- see CanvasController.devicesOf.
  final String owner;
  final int index;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const ParamDevice({
    required this.controller,
    required this.owner,
    required this.index,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  /// _autoTuneWidth is the Auto-tune's card: room for its twelve keys.
  static const double _autoTuneWidth = 330;

  /// _range is how a knob turns for [p]: times and frequencies on a log
  /// scale, everything else in a straight line.
  static _Range _range(DeviceParam p) {
    var log = p.unit == "Hz" || p.unit == "ms";
    return _Range(log && p.min <= 0 ? 1 : p.min, p.max, log: log);
  }

  @override
  Widget build(BuildContext context) {
    var devices = controller.devicesOf(owner);
    if (index >= devices.length) return const SizedBox();
    var device = devices[index];
    void write(MixDevice next, {bool transient = false}) {
      var now = controller.devicesOf(owner);
      if (index >= now.length) return;
      controller.beginInteraction();
      controller.setDevicesOf(owner, [...now]..[index] = next, transient: true);
      if (!transient) controller.endInteraction();
    }

    var params = device.kind.params;
    var columns = (params.length + 1) ~/ 2;
    // Which of its knobs a lane moves, and which a hand is holding.
    var lane =
        controller.timelineChannels.where((c) => c.key == owner).firstOrNull;
    var automated = {
      for (var l in lane?.mix.automation ?? const <AutomationLane>[])
        if (l.points.isNotEmpty) l.target
    };
    var held = controller.overridden[owner] ?? const <String>{};
    // Which of its knobs an LFO in the chain moves.
    var moved = {
      for (var d in devices)
        if (d.on && d.kind.modulates)
          for (var m in d.mods)
            if (m.device == deviceIdAt(devices, index)) m.param,
    };
    // Right-click: move it with a modulator of the chain.
    void moveWith(int j, ModTarget t) {
      var now = controller.devicesOf(owner);
      if (j >= now.length) return;
      var m = now[j];
      if (m.mods.any((x) =>
          x.device == t.device && x.param == t.param && x.from == t.from)) {
        return;
      }
      controller.beginInteraction();
      controller.setDevicesOf(
          owner, [...now]..[j] = m.withMods([...m.mods, t]));
      controller.endInteraction();
    }

    List<(String, VoidCallback)> modMenu(DeviceParam p) {
      var me = deviceIdAt(devices, index);
      return [
        for (var (j, m) in devices.indexed)
          if (j != index && m.kind.modulates)
            if (m.kind == DeviceKind.macro)
              for (var k = 0; k < macroKnobs; k++)
                (
                  "Turn with ${m.kind.label} ${j + 1}'s M${k + 1}",
                  () => moveWith(j, ModTarget(me, p.id, 0.5, k))
                )
            else
              (
                "Move with ${m.kind.label} ${j + 1}",
                () => moveWith(j, ModTarget(me, p.id))
              ),
      ];
    }

    String target(DeviceParam p) => AutomationTarget.deviceSetting(
            deviceIdAt(devices, index), device.kind, p.id)
        .id;
    // A knob's lane, and a controller's knob learnt for it, as the
    // prototype's right-click.
    List<(String, VoidCallback)> knobMenu(DeviceParam p) {
      var me = deviceIdAt(devices, index);
      // What the prototype's knob menu has on every strip: an LFO of its
      // own, a macro's knob, and back where it began.
      var anyStrip = <(String, VoidCallback)>[
        if (!device.kind.modulates && !p.isChoice) ...[
          (
            "Move it with a new LFO",
            () {
              controller.beginInteraction();
              controller.setDevicesOf(
                  owner,
                  withDeviceIds([
                    ...controller.devicesOf(owner),
                    const MixDevice(DeviceKind.lfo)
                        .withMods([ModTarget(me, p.id)]),
                  ]));
              controller.endInteraction();
            }
          ),
          (
            "Add it to a macro",
            () {
              var now = controller.devicesOf(owner);
              var at = now.indexWhere((d) => d.kind == DeviceKind.macro);
              var macro = at >= 0 ? now[at] : const MixDevice(DeviceKind.macro);
              // Its first knob turning nothing yet -- or the first.
              var used = {for (var m in macro.mods) m.from};
              var k = [for (var k = 0; k < macroKnobs; k++) k]
                      .where((k) => !used.contains(k))
                      .firstOrNull ??
                  0;
              var next =
                  macro.withMods([...macro.mods, ModTarget(me, p.id, 0.5, k)]);
              controller.beginInteraction();
              controller.setDevicesOf(
                  owner,
                  withDeviceIds(
                      at >= 0 ? ([...now]..[at] = next) : [...now, next]));
              controller.endInteraction();
            }
          ),
        ],
        ("Reset", () => write(device.withValue(p.id, p.initial))),
      ];
      if (lane == null) return anyStrip;
      var t = target(p);
      var cc = controller.controlOf(owner, t);
      var laned =
          controller.automationLaneOf(lane, t)?.points.isNotEmpty ?? false;
      return [
        ("Show its automation lane", () => controller.showLaneFor(owner, t)),
        if (!laned)
          (
            "Automate it",
            () {
              // A lane begun where it is now, and shown to be drawn on.
              controller.beginInteraction();
              controller.setAutomationPoints(
                  lane, t, [(0.0, device.value(p.id))],
                  transient: true);
              controller.endInteraction();
              controller.showLaneFor(owner, t);
            }
          ),
        if (controller.overridden[owner]?.contains(t) ?? false)
          (
            "Back to its automation",
            () => controller.backToAutomationFor(owner, t)
          ),
        ...anyStrip,
        if (cc != null)
          (
            "Forget the controller (CC $cc)",
            () => controller.forgetControl(owner, t)
          )
        else
          (
            "Learn a controller: turn one of its knobs next",
            () => controller.learnControl(owner, t)
          ),
      ];
    }

    var (icon, accent) = deviceGroupLook(device.kind.group);
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var autoTune = device.kind == DeviceKind.autoTune;
    // Tall, with its text at size, Notes to MIDI is a button at its foot,
    // as the prototype's; shorter, or its text larger, an icon on its bar,
    // leaving its screen the room.
    var roomy = DeviceTier.of(height) == DeviceTier.large &&
        MediaQuery.textScalerOf(context).scale(10) <= 12;
    // Auto-tune's notes made a MIDI channel, as the prototype's foot.
    void notesToMidi() {
      var why = controller.notesToMidi(owner,
          root: device.value("key").round(), steps: autoTuneSteps(device));
      try {
        var snack = SnackBarModel.of(context);
        why == null
            ? snack.success("Its notes are on a new MIDI channel")
            : snack.error(why);
      } catch (_) {}
    }

    // A setting that is one of a few -- a filter's type, an LFO's shape --
    // is a list, not a knob: the prototype's dropdowns.
    bool listed(DeviceParam p) =>
        paramShown(device, p) &&
        device.kind != DeviceKind.split &&
        device.kind != DeviceKind.macro &&
        !(autoTune && (p.id == "key" || p.id == "scale"));
    // Its own knobs, then the Out trim at its foot if it has one.
    var turned = [
      ...params,
      if (device.kind.hasOut) deviceExtras.firstWhere((p) => p.id == "out"),
    ];
    List<Widget> knobs(DeviceTier tier) => [
          for (var p in turned)
            if (listed(p) && !p.isChoice)
              _Knob(
                key: ValueKey("device-$index-${p.id}"),
                automated: automated.contains(target(p)),
                held: held.contains(target(p)),
                modulated: moved.contains(p.id),
                menu: [
                  if (!device.kind.modulates) ...modMenu(p),
                  ...knobMenu(p),
                ],
                label: p.label,
                text: p.reading(device.value(p.id)),
                value: device.value(p.id),
                initial: p.initial,
                range: _range(p),
                size: switch (tier) {
                  DeviceTier.large => 46,
                  DeviceTier.medium => 38,
                  _ => 28,
                },
                reading: tier != DeviceTier.small,
                accent: accent,
                ink: skin.ink,
                bipolar: p.min < 0 && p.max > 0,
                onChanged: (v, {transient = false}) =>
                    write(device.withValue(p.id, v), transient: transient),
                onCommit: controller.endInteraction,
              ),
          if (params.any((p) => listed(p) && p.isChoice))
            DevicePack(key: ValueKey("deviceChoices-$index"), children: [
              for (var p in params)
                if (listed(p) && p.isChoice)
                  StudioDrop<int>(
                    key: ValueKey("device-$index-${p.id}"),
                    label: p.label,
                    value: device
                        .value(p.id)
                        .round()
                        .clamp(0, p.choices.length - 1),
                    options: [for (var (i, ch) in p.choices.indexed) (i, ch)],
                    onChanged: (i) =>
                        write(device.withValue(p.id, i.toDouble())),
                  ),
            ]),
          // Short, its knobs only, as the prototype's.
          // Medium, or its text large, its key and scale as lists on one
          // row; tall, as the prototype's rows of buttons.
          if (autoTune && tier != DeviceTier.small) ...[
            if (tier == DeviceTier.medium ||
                MediaQuery.textScalerOf(context).scale(10) > 12)
              AutoTuneKeyScaleRow(
                  key: ValueKey("autoTuneKeyScaleRow-$index"),
                  device: device,
                  index: index,
                  width: _autoTuneWidth - 16,
                  onPick: (param, v) =>
                      write(device.withValue(param, v.toDouble())))
            else ...[
              AutoTuneKey(
                  key: ValueKey("autoTuneKeyRow-$index"),
                  device: device,
                  index: index,
                  width: _autoTuneWidth - 16,
                  onPick: (k) => write(device.withValue("key", k.toDouble()))),
              AutoTuneScale(
                  key: ValueKey("autoTuneScaleRow-$index"),
                  device: device,
                  index: index,
                  width: _autoTuneWidth - 16,
                  onPick: (k) =>
                      write(device.withValue("scale", k.toDouble()))),
            ],
            if (roomy && controller.pitchElementOf(owner) != null)
              SizedBox(
                width: _autoTuneWidth - 16,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    key: ValueKey("menu-autoTuneToMidi-$index"),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 11)),
                    onPressed: notesToMidi,
                    child: const Text("Notes to MIDI"),
                  ),
                ),
              ),
          ],
          if (device.kind == DeviceKind.vocoder &&
              device.value("carrier").round() == carrierFromChannel)
            _sourceChannel(context, device, write),
          // A split's branches, each its own chain.
          if (device.kind == DeviceKind.split)
            SplitBranches(
              key: ValueKey("splitBranches-$index"),
              device: device,
              // Its branches' knobs a modulator of the chain moves.
              moved: {
                for (var d in devices)
                  if (d.on && d.kind.modulates)
                    for (var m in d.mods)
                      if (branchDevicePath(m.device)
                          case (var split, var b, var id)
                          when split == deviceIdAt(devices, index))
                        "$b/$id/${m.param}",
              },
              ink: skin.ink,
              accent: accent,
              onChanged: (branches, {transient = false}) =>
                  write(device.withBranches(branches), transient: transient),
              onSet: (param, v, {transient = false}) =>
                  write(device.withValue(param, v), transient: transient),
              onCommit: controller.endInteraction,
            ),
          // A macro's knobs set at random, and its settings kept as
          // variations to come back to, as the prototype's Macros.
          if (device.kind == DeviceKind.macro)
            MacroPanel(
              key: ValueKey("macroPanel-$index"),
              index: index,
              device: device,
              knobs: [
                // The instrument's own: its envelope, cutoff and glide.
                if (controller.instrumentChannel(owner))
                  for (var k in instrumentKnobs)
                    (instrumentTarget, k.id, "Instrument · ${k.label}"),
                for (var (i, d) in devices.indexed)
                  if (i != index && !d.kind.modulates)
                    for (var p in d.kind.params)
                      if (!p.isChoice)
                        (
                          deviceIdAt(devices, i),
                          p.id,
                          "${d.kind.label} · ${p.label}"
                        ),
              ],
              accent: accent,
              ink: skin.ink,
              onChanged: (next, {transient = false}) =>
                  write(next, transient: transient),
              onCommit: controller.endInteraction,
            ),
          if (device.kind == DeviceKind.macro)
            _MacroTools(
              key: ValueKey("macroTools-$index"),
              index: index,
              device: device,
              look: MixerLook.of(context),
              onChanged: (next) {
                write(next, transient: true);
                controller.endInteraction();
              },
            ),
          // What a modulator moves: any knob of the chain's other devices.
          // A macro's are its panel's.
          if (device.kind.modulates && device.kind != DeviceKind.macro)
            ModTargets(
              key: ValueKey("modTargets-$index"),
              mods: device.mods,
              sources: device.kind == DeviceKind.macro
                  ? [for (var i = 1; i <= macroKnobs; i++) "M$i"]
                  : const [],
              knobs: [
                for (var (i, d) in devices.indexed)
                  if (i != index && !d.kind.modulates) ...[
                    for (var p in d.kind.params)
                      if (!p.isChoice)
                        (
                          deviceIdAt(devices, i),
                          p.id,
                          "${d.kind.label} · ${p.label}"
                        ),
                    // And the knobs of a split's branches' devices.
                    for (var (b, branch) in d.branches.indexed)
                      for (var (j, x) in branch.devices.indexed)
                        for (var p in x.kind.params)
                          if (!p.isChoice)
                            (
                              branchDeviceId(deviceIdAt(devices, i), b,
                                  deviceIdAt(branch.devices, j)),
                              p.id,
                              "${splitBranchNames(d.value("mode").round(), d.branches.length).elementAtOrNull(b) ?? "Branch"}"
                                  " · ${x.kind.label} · ${p.label}"
                            ),
                  ],
              ],
              ink: skin.ink,
              onChanged: (mods, {transient = false}) =>
                  write(device.withMods(mods), transient: transient),
              onCommit: controller.endInteraction,
            ),
          // A gate opens to its own sound, or to another channel's; a
          // follower follows one or the other.
          if (device.kind == DeviceKind.gate ||
              device.kind == DeviceKind.follower)
            _sourceChannel(context, device, write, itself: true),
        ];
    var hooks =
        freezeHooks(context, controller, owner, deviceIdAt(devices, index));
    return DeviceFrame(
      id: deviceKey(deviceIdAt(devices, index)),
      title: device.kind.label,
      help: deviceAbout(device.kind),
      frozen: hooks.frozen,
      onFreeze: hooks.onFreeze,
      onUnfreeze: hooks.onUnfreeze,
      onDuplicate: () => duplicateDevice(controller, owner, index),
      onReset: () => resetDevice(controller, owner, index),
      onSavePreset: () =>
          saveDevicePreset(context, device.kind.label, devices: [device]),
      onAB: device.kind.params.isEmpty ||
              device.kind == DeviceKind.macro ||
              device.kind == DeviceKind.split
          ? null
          : () => controller.toggleAB(owner, deviceIdAt(devices, index)),
      barExtras: [
        // What it does to the level, on any strip: a channel's, the
        // master's, a scene's bus or a return.
        _GainBadge(
              key: ValueKey("gainBadge-$index"),
              controller: controller,
              channel: owner,
              id: deviceIdAt(devices, index)),
        if (device.kind != DeviceKind.macro && device.kind != DeviceKind.split)
          _PresetPicker(
            key: ValueKey("devicePreset-$index"),
            kind: device.kind,
            name: controller.presetNameOf(owner, deviceIdAt(devices, index)),
            onPick: (name, preset) {
              var next = device;
              for (var p in [...device.kind.params, ...deviceExtras]) {
                next = next.withValue(p.id, preset.value(p.id));
              }
              write(next);
              controller.setPresetName(
                  owner, deviceIdAt(devices, index), name);
            },
            onDefault: () {
              resetDevice(controller, owner, index);
              controller.setPresetName(owner, deviceIdAt(devices, index), null);
            },
            onSave: () =>
                saveDevicePreset(context, device.kind.label, devices: [device]),
          ),
      ],
      extraMenu: (look) => [
        // A drive's harmonics kept from folding back down.
        if (device.kind.oversamples)
          SubmenuButton(
            key: ValueKey("deviceOversample-$index"),
            style: chainMenuItemStyle(look),
            menuStyle: chainMenuStyle(look),
            menuChildren: [
              for (var (k, label) in const [
                (1, "Off"),
                (2, "×2"),
                (4, "×4"),
              ])
                chainMenuItem(look,
                    key: ValueKey("deviceOversample-$index-$k"),
                    text: label,
                    hint: k == 1 ? null : "cleaner, a little more work",
                    current: (device.value("oversample").round() >= 3
                            ? 4
                            : device.value("oversample").round()) ==
                        k,
                    onPressed: () =>
                        write(device.withValue("oversample", k.toDouble()))),
            ],
            child: Text(
                "Oversample: ${device.value("oversample").round() <= 1 ? "off" : "×${device.value("oversample").round() >= 3 ? 4 : 2}"}"),
          ),
        // Only the middle of the sound, or only its sides.
        if (device.kind.worksOnSides)
          worksOnMenu(look,
              id: "deviceStereo-$index",
              value: device.value("stereo").round(),
              onPick: (k) => write(device.withValue("stereo", k.toDouble()))),
        // What it listens to beside its own sound.
        if (device.kind == DeviceKind.gate ||
            device.kind == DeviceKind.follower ||
            (device.kind == DeviceKind.vocoder &&
                device.value("carrier").round() == carrierFromChannel))
          SubmenuButton(
            key: ValueKey("deviceListens-$index"),
            style: chainMenuItemStyle(look),
            menuStyle: chainMenuStyle(look),
            menuChildren: [
              if (device.kind != DeviceKind.vocoder)
                chainMenuItem(look,
                    key: ValueKey("deviceListens-$index-itself"),
                    text: "Itself",
                    current: device.source.isEmpty,
                    onPressed: () => write(device.withSource(""))),
              for (var ch in controller.timelineChannels)
                if (ch.key != owner)
                  chainMenuItem(look,
                      key: ValueKey("deviceListens-$index-${ch.key}"),
                      text: ch.name,
                      current: device.source == ch.key,
                      onPressed: () => write(device.withSource(ch.key))),
            ],
            child: const Text("Listens to (sidechain)"),
          ),
      ],
      showingB: controller.showingB(owner, deviceIdAt(devices, index)),
      skin: skin,
      on: device.on,
      onPower: (v) => write(device.switched(v)),
      powerKey: ValueKey("devicePower-$index"),
      folded: folded,
      onFold: onFold,
      // A split's branches side by side, a column each.
      width: device.kind == DeviceKind.split
          ? SplitBranches.width
          : device.kind == DeviceKind.macro
              ? MacroPanel.width
              : autoTune
              ? _autoTuneWidth
              : math.max(240.0, 24.0 + 72 * columns),
      height: height,
      actions: [
        // Auto-tune's notes: in the Pitch editor, or made a MIDI channel.
        if (autoTune)
          Tooltip(
            message: "How far behind it puts what it hears",
            child: Text("${autoTuneLatencyMs.round()} ms",
                key: ValueKey("autoTuneLatency-$index"),
                style: TextStyle(
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: skin.ink.withValues(alpha: 0.7))),
          ),
        if (autoTune && !roomy && controller.pitchElementOf(owner) != null)
          IconButton(
            key: ValueKey("menu-autoTuneToMidi-$index"),
            tooltip: "Notes to MIDI",
            icon: const Icon(Icons.piano),
            onPressed: notesToMidi,
          ),
        if (autoTune && controller.pitchElementOf(owner) != null)
          IconButton(
            key: ValueKey("autoTunePitch-$index"),
            tooltip: "Open its notes in the Pitch editor",
            icon: const Icon(Icons.open_in_new),
            onPressed: () => controller.showPitch(owner),
          ),
        ...deviceMoveButtons(controller, owner, index, _headerInkLight),
        IconButton(
          key: ValueKey("deviceRemove-$index"),
          tooltip: "Take the ${device.kind.label.toLowerCase()} out",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: _headerInkLight),
          onPressed: () {
            var now = controller.devicesOf(owner);
            if (index >= now.length) return;
            controller.beginInteraction();
            controller.setDevicesOf(owner, [...now]..removeAt(index));
            controller.endInteraction();
          },
        ),
      ],
      // Folded, its level as it leaves it, at its foot.
      foldedBody: _FoldedLevel(
          key: ValueKey("foldedLevel-$index"),
          controller: controller,
          owner: owner,
          at: controller.chainOf(owner).indexOf(deviceIdAt(devices, index)) +
              1),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: knobs(DeviceTier.large),
        ),
      ),
      // Laid out for its height: its levels over its knobs.
      controls: knobs,
      // A split's branches are its picture: they have the room.
      display: device.kind == DeviceKind.split ||
              device.kind == DeviceKind.macro
          ? null
          : autoTune
              ? AutoTuneScreen(
                  key: ValueKey("autoTuneScreen-$index"),
                  controller: controller,
                  owner: owner,
                  device: device,
                  index: index)
              : DeviceLevels(
                  key: ValueKey("deviceLevels-$index"),
                  controller: controller,
                  deviceId: deviceIdAt(devices, index),
                  // Measured on any strip: a channel's, a return's, the
                  // master's or a scene's bus.
                  channel: owner,
                  // Its place in the chain, where its levels are read: the EQ and
                  // compressor can be before it.
                  index: controller
                      .chainOf(owner)
                      .indexOf(deviceIdAt(devices, index)),
                  device: device,
                  accent: accent,
                  back: look.studio.display),
      summary: [
        for (var p in params.where((p) => paramShown(device, p)).take(2))
          "${p.label} ${p.reading(device.value(p.id))}"
      ].join(" · "),
      icon: icon,
      accent: accent,
    );
  }

  /// _sourceChannel is which channel a device listens to beside its own:
  /// a vocoder's carrier -- an instrument playing the chords, muted so only
  /// the vocoder is heard -- or, with [itself], a gate's key, where "" is
  /// its own sound.
  Widget _sourceChannel(
      BuildContext context, MixDevice device, void Function(MixDevice) write,
      {bool itself = false}) {
    var look = MixerLook.of(context);
    var channels = [
      for (var c in controller.timelineChannels)
        if (c.key != owner) c,
    ];
    var chosen = channels.any((c) => c.key == device.source)
        ? device.source
        : itself
            ? ""
            : null;
    var ink = TextStyle(fontSize: 11, color: look.studio.text);
    return SizedBox(
      width: 104,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("From", style: ink.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButton<String>(
          key: ValueKey("deviceSource-$index"),
          isExpanded: true,
          isDense: true,
          value: chosen,
          style: ink,
          iconEnabledColor: look.studio.text,
          dropdownColor: look.colors.surfaceContainerHigh,
          hint: Text(channels.isEmpty ? "No other channel" : "A channel",
              style: ink, overflow: TextOverflow.ellipsis),
          items: [
            if (itself)
              DropdownMenuItem(
                  value: "",
                  child: Text("Itself",
                      style: TextStyle(
                          fontSize: 11, color: look.colors.onSurface))),
            for (var c in channels)
              DropdownMenuItem(
                  value: c.key,
                  child: Text(c.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: look.colors.onSurface))),
          ],
          selectedItemBuilder: (_) => [
            if (itself) Text("Itself", style: ink),
            for (var c in channels)
              Text(c.name, overflow: TextOverflow.ellipsis, style: ink),
          ],
          onChanged: channels.isEmpty && !itself
              ? null
              : (v) {
                  if (v != null) write(device.withSource(v));
                },
        ),
      ]),
    );
  }
}

/// AddDeviceSlot puts a device on strip [owner], after its others: the
/// prototype's "+" at the chain's end, opening every kind of device by its
/// family.
class AddDeviceSlot extends StatelessWidget {
  final CanvasController controller;

  /// owner is the strip it adds to: see CanvasController.devicesOf.
  final String owner;
  final double height;

  const AddDeviceSlot(
      {required this.controller,
      required this.owner,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    // A sound's channel can be given a generator: Speech, which makes its
    // clips. A MIDI channel has its instrument; a bus, a video's sound or
    // one with speech already, none.
    var lane =
        controller.timelineChannels.where((l) => l.key == owner).firstOrNull;
    var canSpeak = lane != null &&
        !lane.video &&
        !controller.instrumentChannel(owner) &&
        controller.speechOf(owner) == null;
    devicePresets.load();
    return ListenableBuilder(
      listenable: devicePresets,
      builder: (context, _) => AddSlot(
        id: "addDeviceOpen",
        title: "Add a device",
        height: height,
        groups: [
          // Kept with Save as a preset: a device, or a whole chain.
          if (devicePresets.presets.where((p) => presetHolds(p)) case var kept
              when kept.isNotEmpty)
            (
              "Presets",
              [
                for (var p in kept)
                  (
                    "addPreset-${p.id}",
                    p.name,
                    () => useDevicePreset(controller, owner, p.data),
                  ),
              ]
            ),
          // The strip's own parts taken out, to put back.
          if ([
            for (var part in removableParts)
              if (controller.partRemoved(owner, part)) part
          ]
              case var gone when gone.isNotEmpty)
            (
              "Channel strip",
              [
                for (var part in gone)
                  (
                    "addPart-$part",
                    switch (part) {
                      chainEq => "EQ",
                      chainComp => "Compressor",
                      stripDucked => "Ducked by others",
                      _ => "Ducker",
                    },
                    () => controller.restorePart(owner, part),
                  ),
              ]
            ),
          // A voice can be sung: the Vocaliser, among its effects.
          if (lane != null &&
              controller.speechOf(owner) != null &&
              controller.vocaliserOf(owner) == null)
            (
              "Voice",
              [
                (
                  "addDevice-vocaliser",
                  "Vocaliser",
                  () {
                    controller.beginInteraction();
                    controller.setVocaliser(owner, const VocaliserSpec());
                    controller.endInteraction();
                    controller.openEffects(owner, device: "vocaliser");
                  }
                ),
              ]
            ),
          if (canSpeak)
            (
              "Generators",
              [
                (
                  "addDevice-speech",
                  "Speech",
                  () {
                    controller.beginInteraction();
                    controller.setSpeech(owner, const SpeechSpec());
                    controller.endInteraction();
                    controller.showSpeech(owner);
                  }
                ),
              ]
            ),
          for (var group in DeviceGroup.values)
            (
              group.label,
              [
                for (var kind in DeviceKind.values)
                  if (kind.group == group)
                    (
                      "addDevice-${kind.name}",
                      kind.label,
                      () {
                        var now = controller.devicesOf(owner);
                        controller.beginInteraction();
                        controller
                            .setDevicesOf(owner, [...now, MixDevice(kind)]);
                        controller.endInteraction();
                        controller.openEffects(owner,
                            device: deviceKey(deviceIdAt(
                                controller.devicesOf(owner), now.length)));
                      }
                    ),
              ]
            ),
        ],
      ),
    );
  }
}

/// AddSlot is the chain's "+", as the prototype draws it: a slim dashed slot
/// that, pressed, opens what can be added -- a search, and each family's
/// kinds in columns.
class AddSlot extends StatelessWidget {
  /// id keys the slot itself; each item is keyed by its own key.
  final String id;
  final String title;
  final double height;

  /// groups are each family's name and its items: a key, a name, and what
  /// picking it does.
  final List<(String, List<(String, String, VoidCallback)>)> groups;

  const AddSlot(
      {required this.id,
      required this.title,
      required this.height,
      required this.groups,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return MenuAnchor(
      builder: (context, menu, _) => Tooltip(
        message: title,
        child: InkWell(
          key: ValueKey(id),
          borderRadius: BorderRadius.circular(8),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: SizedBox(
            width: 30,
            height: height,
            child: CustomPaint(
              painter: _DashedSlot(look.studio.edge),
              child: Center(
                child: Icon(Icons.add, size: 16, color: look.studio.muted),
              ),
            ),
          ),
        ),
      ),
      menuChildren: [
        Builder(
          builder: (context) => _AddPanel(
            title: title,
            groups: groups,
            onPicked: () => MenuController.maybeOf(context)?.close(),
          ),
        ),
      ],
    );
  }
}

/// _DashedSlot draws the "+" slot's dashed outline.
class _DashedSlot extends CustomPainter {
  final Color colour;
  _DashedSlot(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    var r = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(3), const Radius.circular(8));
    var paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var metric in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedSlot old) => old.colour != colour;
}

/// _AddPanel is what the "+" opens: a search over every kind, and the kinds
/// by family, four families to a row.
class _AddPanel extends StatefulWidget {
  final String title;
  final List<(String, List<(String, String, VoidCallback)>)> groups;
  final VoidCallback onPicked;
  const _AddPanel(
      {required this.title, required this.groups, required this.onPicked});

  @override
  State<_AddPanel> createState() => _AddPanelState();
}

class _AddPanelState extends State<_AddPanel> {
  String _q = "";

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var q = _q.toLowerCase();
    var shown = [
      for (var (family, items) in widget.groups)
        (
          family,
          [
            for (var item in items)
              if (q.isEmpty ||
                  item.$2.toLowerCase().contains(q) ||
                  family.toLowerCase().contains(q))
                item
          ]
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    var columns = math.min(4, math.max(1, shown.length));
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 150.0 * columns + 8 * (columns - 1),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 30,
                child: TextField(
                  key: const ValueKey("addSlotSearch"),
                  autofocus: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText:
                        "Find ${widget.title.toLowerCase().replaceFirst("add ", "")}",
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5)),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (var (family, items) in shown)
                  SizedBox(
                    width: 150,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                            child: Text(family.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 9.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w500,
                                    color: look.studio.muted)),
                          ),
                          for (var (key, label, pick) in items)
                            InkWell(
                              key: ValueKey(key),
                              borderRadius: BorderRadius.circular(5),
                              onTap: () {
                                widget.onPicked();
                                pick();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                child: Text(label,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                        ]),
                  ),
              ]),
            ]),
      ),
    );
  }
}

// ---- A MIDI channel's devices: where its notes come from, and its MIDI effects

/// MidiInDevice is a MIDI channel's In: which keyboard it takes notes from,
/// and when it plays them -- see MidiMonitor. First in its chain.
class MidiInDevice extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const MidiInDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var part = controller.instrumentOf(channel)?.instrument;
    if (part == null) return const SizedBox();
    var look = MixerLook.of(context);
    var skin = DeviceSkin.themed(look.colors);
    var keyboards = [
      for (var d in MidiInput.shared.devices) d.name,
      if (part.input.isNotEmpty &&
          part.input != noInput &&
          !MidiInput.shared.devices.any((d) => d.name == part.input))
        part.input,
    ];
    var armed = controller.armed.contains(channel);
    TextStyle small([Color? c]) =>
        TextStyle(fontSize: 11, color: c ?? skin.ink);
    return DeviceFrame(
      id: "midiIn",
      title: "MIDI In",
      help: "Where the channel's notes come in from: a keyboard, or all of "
          "them. Monitor is when what comes in is heard: always, while the "
          "channel is armed, or never.",
      skin: skin,
      icon: Icons.grid_view,
      accent: midiColour,
      folded: folded,
      onFold: onFold,
      width: 190,
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text("In: ${part.monitor.label}", style: small(skin.dim)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("From", style: small(skin.dim)),
          const SizedBox(height: 2),
          DropdownButton<String>(
            key: const ValueKey("midiFrom"),
            isExpanded: true,
            isDense: true,
            value: part.input,
            style: small(),
            dropdownColor: look.colors.surfaceContainerHigh,
            items: [
              const DropdownMenuItem(value: "", child: Text("All MIDI inputs")),
              for (var k in keyboards)
                DropdownMenuItem(
                    value: k, child: Text(k, overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: noInput, child: Text("No input")),
            ],
            onChanged: (v) {
              if (v == null) return;
              controller.setChannelPart(channel, (p) => p.copyWith(input: v));
            },
          ),
          const SizedBox(height: 12),
          Text("Monitor", style: small(skin.dim)),
          const SizedBox(height: 4),
          Row(children: [
            for (var m in MidiMonitor.values) ...[
              Expanded(
                child: Tooltip(
                  message: m.hint,
                  child: Material(
                    color: part.monitor == m
                        ? look.studio.on
                        : look.colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      key: ValueKey("midiMonitor-${m.name}"),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => controller.setChannelPart(
                          channel, (p) => p.copyWith(monitor: m)),
                      child: SizedBox(
                        height: 24,
                        child: Center(
                          child: Text(m.label,
                              style: small(part.monitor == m
                                  ? look.studio.onOn
                                  : skin.ink)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (m != MidiMonitor.values.last) const SizedBox(width: 4),
            ],
          ]),
          const SizedBox(height: 12),
          Text(
            switch (part.monitor) {
              MidiMonitor.input => "Plays what comes in, armed or not.",
              MidiMonitor.auto => armed
                  ? "Armed: plays what comes in."
                  : "Plays what comes in once it is armed.",
              MidiMonitor.off => "Plays only its clips and its part.",
            },
            style: small(skin.dim),
          ),
          if (MidiInput.shared.device == null) ...[
            const SizedBox(height: 8),
            Text("No keyboard chosen: see the instrument's settings.",
                style: small(skin.dim)),
          ],
          const Spacer(),
          OutlinedButton.icon(
            key: const ValueKey("openPianoRoll"),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: skin.ink,
                textStyle: const TextStyle(fontSize: 11)),
            onPressed: () => controller.openPianoRoll(channel),
            icon: const Icon(Icons.piano, size: 14),
            label: const Text("Piano roll: its part"),
          ),
        ]),
      ),
    );
  }
}

/// MidiEffectDevice is one of a MIDI channel's MIDI effects -- see
/// midi_effects.dart -- as knobs: a choice turned through its choices.
class MidiEffectDevice extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final int index;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const MidiEffectDevice({
    required this.controller,
    required this.channel,
    required this.index,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var part = controller.instrumentOf(channel)?.instrument;
    if (part == null || index >= part.effects.length) return const SizedBox();
    var effect = part.effects[index];
    void write(MidiEffect next, {bool transient = false}) {
      controller.beginInteraction();
      controller.setChannelPart(
          channel,
          (p) => index >= p.effects.length
              ? p
              : p.copyWith(effects: [...p.effects]..[index] = next),
          transient: true);
      if (!transient) controller.endInteraction();
    }

    var params = effect.kind.params;
    void edit(List<MidiEffect> Function(List<MidiEffect>) change) {
      controller.beginInteraction();
      controller.setChannelPart(
          channel,
          (p) => index >= p.effects.length
              ? p
              : p.copyWith(effects: change([...p.effects])));
      controller.endInteraction();
    }

    var abKey = "$channel|midi$index|${effect.kind.name}";
    return DeviceFrame(
      id: "midi$index",
      title: effect.kind.label,
      onDuplicate: () => edit((e) => e..insert(index + 1, e[index])),
      onSavePreset: () =>
          saveDevicePreset(context, effect.kind.label, midi: [effect]),
      onReset: () =>
          edit((e) => e..[index] = MidiEffect(e[index].kind, on: e[index].on)),
      // Kept by its place and kind: another effect moved into its place
      // starts its own A and B.
      onAB: () => controller.toggleABOf(abKey, effect,
          (o) => write((o as MidiEffect).switched(effect.on), transient: true)),
      showingB: controller.showingBOf(abKey),
      help: "Done to the notes before the instrument plays them.",
      skin: DeviceSkin.silver,
      icon: Icons.grid_view,
      accent: midiColour,
      on: effect.on,
      onPower: (v) => write(effect.switched(v)),
      powerKey: ValueKey("midiPower-$index"),
      folded: folded,
      onFold: onFold,
      width: 236,
      height: height,
      actions: [
        IconButton(
          key: ValueKey("midiRemove-$index"),
          tooltip: "Take the ${effect.kind.label.toLowerCase()} out",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: _headerInkLight),
          onPressed: () {
            controller.beginInteraction();
            controller.setChannelPart(
                channel,
                (p) => index >= p.effects.length
                    ? p
                    : p.copyWith(effects: [...p.effects]..removeAt(index)));
            controller.endInteraction();
          },
        ),
      ],
      foldedBody: const SizedBox(),
      summary: [
        for (var p in params) "${p.label} ${p.reading(effect.value(p.id))}"
      ].join(" · "),
      controls: (tier) => [
        for (var p in params)
          if (!p.isChoice)
            _Knob(
              key: ValueKey("midi-$index-${p.id}"),
              label: p.label,
              text: p.reading(effect.value(p.id)),
              value: effect.value(p.id),
              initial: p.initial,
              range: _Range(p.min, p.max),
              size: switch (tier) {
                DeviceTier.large => 46,
                DeviceTier.medium => 38,
                _ => 28,
              },
              reading: tier != DeviceTier.small,
              accent: midiColour,
              onChanged: (v, {transient = false}) =>
                  write(effect.withValue(p.id, v), transient: transient),
              onCommit: controller.endInteraction,
            ),
        // A rate, a mode, a scale: chosen from a list, as a sound device's.
        if (params.any((p) => p.isChoice))
          DevicePack(key: ValueKey("midiChoices-$index"), children: [
            for (var p in params)
              if (p.isChoice)
                StudioDrop<int>(
                  key: ValueKey("midi-$index-${p.id}"),
                  label: p.label,
                  value: effect.choice(p.id).clamp(0, p.choices.length - 1),
                  options: [for (var (i, ch) in p.choices.indexed) (i, ch)],
                  onChanged: (i) => write(effect.withValue(p.id, i.toDouble())),
                ),
          ]),
      ],
      body: const SizedBox(),
    );
  }
}

/// AddMidiEffectSlot puts a MIDI effect on a MIDI channel, after the
/// others, before its instrument: the chain's "+".
class AddMidiEffectSlot extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final double height;

  const AddMidiEffectSlot(
      {required this.controller,
      required this.channel,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    devicePresets.load();
    return ListenableBuilder(
      listenable: devicePresets,
      builder: (context, _) => AddSlot(
        id: "addMidiOpen",
        title: "Add a MIDI effect",
        height: height,
        groups: [
          // Kept with Save as a preset: its MIDI effects, after the rest.
          if (devicePresets.presets.where((p) => presetHolds(p, midi: true))
              case var kept when kept.isNotEmpty)
            (
              "Presets",
              [
                for (var p in kept)
                  (
                    "addPreset-${p.id}",
                    p.name,
                    () => useDevicePreset(controller, channel, p.data),
                  ),
              ]
            ),
          (
            "MIDI effects",
            [
              for (var kind in MidiEffectKind.values)
                (
                  "addMidi-${kind.name}",
                  kind.label,
                  () {
                    controller.beginInteraction();
                    controller.setChannelPart(
                        channel,
                        (p) => p.copyWith(
                            effects: [...p.effects, MidiEffect(kind)]));
                    controller.endInteraction();
                    controller.openEffects(channel,
                        device:
                            "midi${controller.instrumentOf(channel)!.instrument!.effects.length - 1}");
                  }
                ),
            ]
          ),
        ],
      ),
    );
  }
}

// ---- The devices that only listen: a tuner, a spectrum

/// ListenerDevice is a Tuner or a Spectrum on strip [owner]: what it hears,
/// drawn a few times a second, changing nothing.
class ListenerDevice extends StatefulWidget {
  final CanvasController controller;
  final String owner;
  final int index;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const ListenerDevice({
    required this.controller,
    required this.owner,
    required this.index,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  State<ListenerDevice> createState() => _ListenerDeviceState();
}

class _ListenerDeviceState extends State<ListenerDevice>
    with SingleTickerProviderStateMixin, _Metered {
  /// _history is a Spectrum's spectrogram: its spectra, oldest first, one
  /// taken each tick while it is shown.
  final List<Float32List> _history = [];
  static const int _historyLength = 240;

  // What it shows is read in build: a tick only asks for it again -- and a
  // spectrogram keeps what it heard.
  @override
  void tick() {
    var c = widget.controller;
    var devices = c.devicesOf(widget.owner);
    if (widget.index >= devices.length) return;
    var device = devices[widget.index];
    if (device.kind != DeviceKind.spectrum || device.value("view") < 0.5) {
      return;
    }
    var bins = c.spectrum(widget.owner == mixerMasterKey ? null : widget.owner);
    // Kept while there is sound: played, a clip launched, or keys pressed.
    if (bins == null || !_loud) return;
    _history.add(Float32List.fromList(bins));
    if (_history.length > _historyLength) _history.removeAt(0);
  }

  @override
  CanvasController get meteredBy => widget.controller;

  @override
  Widget build(BuildContext context) {
    var c = widget.controller;
    var devices = c.devicesOf(widget.owner);
    if (widget.index >= devices.length) return const SizedBox();
    var device = devices[widget.index];
    var tuner = device.kind == DeviceKind.tuner;
    var look = MixerLook.of(context);
    var studio = look.studio;
    Widget body;
    String summary = "Listening";
    if (tuner) {
      var heard = c.pitch(widget.owner);
      String note = "–", reading = "Listening…";
      double cents = 0;
      if (heard != null && heard.clarity > 0.5) {
        var midi = 69 + 12 * math.log(heard.hz / 440) / math.ln2;
        var nearest = midi.round();
        cents = (midi - nearest) * 100;
        note = "${const [
          "C",
          "C♯",
          "D",
          "E♭",
          "E",
          "F",
          "F♯",
          "G",
          "A♭",
          "A",
          "B♭",
          "B"
        ][nearest % 12]}"
            "${nearest ~/ 12 - 1}";
        reading = "${heard.hz.toStringAsFixed(1)} Hz · "
            "${cents >= 0 ? "+" : ""}${cents.round()} cents";
      }
      summary = note == "–"
          ? "Listening"
          : "$note ${cents >= 0 ? "+" : "−"}${cents.abs().round()} cents";
      // The note as big as the screen has room for, its needle and its
      // reading under it while there is room for them.
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: LayoutBuilder(builder: (context, box) {
          var roomy = box.maxHeight > 110;
          return Column(children: [
            Expanded(
              child: FittedBox(
                // Smaller where the screen is short; never bigger.
                fit: BoxFit.scaleDown,
                child: Text(note,
                    key: const ValueKey("tunerNote"),
                    style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: cents.abs() < 5 && note != "–"
                            ? studio.meterLow
                            : studio.text)),
              ),
            ),
            SizedBox(
              height: roomy ? 34 : 18,
              width: double.infinity,
              child: CustomPaint(painter: _TunerPainter(cents, studio)),
            ),
            if (roomy) ...[
              const SizedBox(height: 6),
              Text(reading,
                  key: const ValueKey("tunerReading"),
                  style: TextStyle(fontSize: 12, color: studio.muted)),
            ],
          ]);
        }),
      );
    } else if (device.kind == DeviceKind.scope) {
      var wave = c.wave(DeviceKind.scope, widget.owner);
      summary = "${device.value("time").round()} ms";
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: CustomPaint(
          key: const ValueKey("scopeView"),
          size: Size.infinite,
          painter: _ScopePainter(wave, device.value("zoom"), studio),
        ),
      );
    } else if (device.kind == DeviceKind.stereoImage) {
      var wave = c.wave(DeviceKind.stereoImage, widget.owner);
      var r = wave == null ? 0.0 : correlation(wave);
      summary =
          "correlation ${r >= 0 ? "+" : "−"}${r.abs().toStringAsFixed(2)}";
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          Expanded(
            child: CustomPaint(
              key: const ValueKey("stereoImageView"),
              size: Size.infinite,
              painter: _GoniometerPainter(wave, studio),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            width: double.infinity,
            child: CustomPaint(
                key: const ValueKey("correlationBar"),
                painter: _CorrelationPainter(r, studio)),
          ),
          Text(summary,
              key: const ValueKey("correlationReading"),
              style: TextStyle(fontSize: 11, color: studio.muted)),
        ]),
      );
    } else if (device.kind == DeviceKind.loudness) {
      var heard = c.loudness(widget.owner);
      var target = device.value("target");
      String lufs(double v) =>
          v.isFinite ? "${v < 0 ? "−" : ""}${v.abs().toStringAsFixed(1)}" : "–";
      summary = heard == null || !heard.shortTerm.isFinite
          ? "Listening"
          : "${lufs(heard.shortTerm)} LUFS";
      Widget row(String key, String label, String value) => Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: studio.muted)),
            ),
            Text(value,
                key: ValueKey(key),
                style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: studio.text)),
          ]);
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: LayoutBuilder(builder: (context, box) {
          return SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(heard == null ? "–" : lufs(heard.shortTerm),
                        key: const ValueKey("loudnessShortTerm"),
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: studio.text)),
                  ),
                  Text("LUFS short-term · aim ${target.round()}",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: studio.muted)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 10,
                    child: CustomPaint(
                        painter: _LoudnessBarPainter(
                            heard?.shortTerm ?? -double.infinity,
                            target,
                            studio)),
                  ),
                  const SizedBox(height: 6),
                  row("loudnessMomentary", "Momentary",
                      heard == null ? "–" : lufs(heard.momentary)),
                  row("loudnessIntegrated", "Whole, since reset",
                      heard == null ? "–" : lufs(heard.integrated)),
                  row(
                      "loudnessTruePeak",
                      "True peak",
                      heard == null || !heard.truePeak.isFinite
                          ? "–"
                          : "${lufs(heard.truePeak)} dBTP"),
                ]),
          );
        }),
      );
    } else if (device.value("view") >= 0.5) {
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: CustomPaint(
          key: const ValueKey("spectrogramView"),
          size: Size.infinite,
          painter: _SpectrogramPainter(_history, _history.length),
        ),
      );
    } else {
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: CustomPaint(
          key: const ValueKey("spectrumView"),
          size: Size.infinite,
          painter: _SpectrumPainter(
              c.spectrum(widget.owner == mixerMasterKey ? null : widget.owner),
              studio),
        ),
      );
    }
    void write(MixDevice next) {
      var now = c.devicesOf(widget.owner);
      if (widget.index >= now.length) return;
      c.beginInteraction();
      c.setDevicesOf(widget.owner, [...now]..[widget.index] = next);
      c.endInteraction();
    }

    var (icon, accent) = deviceGroupLook(device.kind.group);
    var skin = DeviceSkin.studio(studio);
    var hooks = freezeHooks(
        context, c, widget.owner, deviceIdAt(devices, widget.index));
    return DeviceFrame(
      id: deviceKey(deviceIdAt(devices, widget.index)),
      title: device.kind.label,
      help: deviceAbout(device.kind),
      frozen: hooks.frozen,
      onFreeze: hooks.onFreeze,
      onUnfreeze: hooks.onUnfreeze,
      onDuplicate: () => duplicateDevice(c, widget.owner, widget.index),
      onReset: () => resetDevice(c, widget.owner, widget.index),
      onSavePreset: () =>
          saveDevicePreset(context, device.kind.label, devices: [device]),
      skin: skin,
      // Its screen is all of it, and its few settings: it only listens.
      display: body,
      controls: (tier) => [
        for (var p in device.kind.params)
          if (!p.isChoice)
            _Knob(
              key: ValueKey("device-${widget.index}-${p.id}"),
              label: p.label,
              text: p.reading(device.value(p.id)),
              value: device.value(p.id),
              initial: p.initial,
              range: _Range(p.min, p.max),
              size: tier == DeviceTier.large ? 38 : 28,
              reading: tier != DeviceTier.small,
              accent: accent,
              ink: skin.ink,
              onChanged: (v, {transient = false}) {
                var now = c.devicesOf(widget.owner);
                if (widget.index >= now.length) return;
                c.beginInteraction();
                c.setDevicesOf(widget.owner,
                    [...now]..[widget.index] = device.withValue(p.id, v),
                    transient: true);
                if (!transient) c.endInteraction();
              },
              onCommit: c.endInteraction,
            ),
      ],
      summary: summary,
      icon: icon,
      accent: accent,
      on: device.on,
      onPower: (v) => write(device.switched(v)),
      powerKey: ValueKey("devicePower-${widget.index}"),
      folded: widget.folded,
      onFold: widget.onFold,
      width: switch (device.kind) {
        DeviceKind.tuner => 220,
        DeviceKind.stereoImage || DeviceKind.loudness => 290,
        _ => 360,
      },
      height: widget.height,
      actions: [
        // A Spectrum shown as it is now, or over time; a Loudness started
        // again.
        if (device.kind == DeviceKind.spectrum)
          IconButton(
            key: ValueKey("spectrumView-${widget.index}"),
            tooltip: device.value("view") >= 0.5
                ? "Show the spectrum as it is now"
                : "Show it over time: a spectrogram",
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            icon: Icon(
                device.value("view") >= 0.5
                    ? Icons.show_chart
                    : Icons.view_week_outlined,
                color: skin.ink),
            onPressed: () {
              _history.clear();
              write(device.withValue(
                  "view", device.value("view") >= 0.5 ? 0 : 1));
            },
          ),
        if (device.kind == DeviceKind.loudness)
          IconButton(
            key: ValueKey("loudnessReset-${widget.index}"),
            tooltip: "Start measuring again",
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.restart_alt, color: skin.ink),
            onPressed: () => c.resetLoudness(widget.owner),
          ),
        ...deviceMoveButtons(c, widget.owner, widget.index, skin.ink),
        IconButton(
          key: ValueKey("deviceRemove-${widget.index}"),
          tooltip: "Take the ${device.kind.label.toLowerCase()} out",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, color: skin.ink),
          onPressed: () {
            var now = c.devicesOf(widget.owner);
            if (widget.index >= now.length) return;
            c.beginInteraction();
            c.setDevicesOf(widget.owner, [...now]..removeAt(widget.index));
            c.endInteraction();
          },
        ),
      ],
      foldedBody: const SizedBox(),
      body: body,
    );
  }
}

/// _TunerPainter is the tuner's needle: fifty cents flat to fifty sharp,
/// in tune in the middle.
class _TunerPainter extends CustomPainter {
  final double cents;
  final StudioColors studio;
  _TunerPainter(this.cents, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var mid = size.width / 2;
    var line = Paint()
      ..color = _eqDim
      ..strokeWidth = 1;
    for (var c = -50; c <= 50; c += 10) {
      var x = mid + c / 50 * (size.width / 2 - 6);
      canvas.drawLine(Offset(x, size.height * (c == 0 ? 0.1 : 0.35)),
          Offset(x, size.height * 0.65), line);
    }
    var x = mid + cents.clamp(-50, 50) / 50 * (size.width / 2 - 6);
    canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = cents.abs() < 5 ? studio.meterLow : studio.meterMid);
  }

  @override
  bool shouldRepaint(_TunerPainter old) => old.cents != cents;
}

/// _ScopePainter is a sound's wave over the Scope's time: left and right
/// over each other, [zoom] times as tall.
class _ScopePainter extends CustomPainter {
  final Wave? wave;
  final double zoom;
  final StudioColors studio;
  _ScopePainter(this.wave, this.zoom, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid),
        Paint()..color = studio.muted.withValues(alpha: 0.3));
    var w = wave;
    if (w == null || w.$1.isEmpty) return;
    for (var (side, colour) in [
      (w.$2, studio.meterMid.withValues(alpha: 0.7)),
      (w.$1, studio.meterLow),
    ]) {
      var path = Path();
      for (var i = 0; i < side.length; i++) {
        var x = i / math.max(1, side.length - 1) * size.width;
        var y = mid - (side[i] * zoom).clamp(-1.0, 1.0) * (mid - 2);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
    }
  }

  @override
  bool shouldRepaint(_ScopePainter old) => true;
}

/// _GoniometerPainter draws left against right as a goniometer does: the
/// middle (both alike) straight up, the sides (left less right) across, so
/// mono is a vertical line and a wide sound a cloud.
class _GoniometerPainter extends CustomPainter {
  final Wave? wave;
  final StudioColors studio;
  _GoniometerPainter(this.wave, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = math.min(size.width, size.height) / 2 - 4;
    var guide = Paint()
      ..color = studio.muted.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), guide);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), guide);
    var d = r * math.sqrt1_2;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), guide);
    canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), guide);
    var w = wave;
    if (w == null) return;
    var (l, rr) = w;
    // Its loudest, so a quiet sound still fills it.
    var most = 1e-6;
    for (var i = 0; i < l.length; i++) {
      most = math.max(most, math.max(l[i].abs(), rr[i].abs()));
    }
    var scale = r / math.max(most, 0.05) * math.sqrt1_2;
    var points = <Offset>[
      for (var i = 0; i < l.length; i++)
        c + Offset((l[i] - rr[i]) * scale, -(l[i] + rr[i]) * scale),
    ];
    canvas.drawPoints(
        ui.PointMode.points,
        points,
        Paint()
          ..color = studio.meterLow.withValues(alpha: 0.75)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_GoniometerPainter old) => true;
}

/// _CorrelationPainter is the correlation's bar: minus one (opposite, left
/// of the middle, in the warning colour) to plus one (alike).
class _CorrelationPainter extends CustomPainter {
  final double value;
  final StudioColors studio;
  _CorrelationPainter(this.value, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height / 2 - 3, size.width, 6),
        const Radius.circular(3));
    canvas.drawRRect(track, Paint()..color = studio.inset);
    var mid = size.width / 2;
    canvas.drawLine(Offset(mid, 0), Offset(mid, size.height),
        Paint()..color = studio.muted.withValues(alpha: 0.5));
    var x = mid + value.clamp(-1.0, 1.0) * (mid - 4);
    canvas.drawCircle(Offset(x, size.height / 2), 5,
        Paint()..color = value < 0 ? studio.meterHigh : studio.meterLow);
  }

  @override
  bool shouldRepaint(_CorrelationPainter old) => old.value != value;
}

/// _LoudnessBarPainter is short-term loudness from -40 to nought LUFS, the
/// target marked: green under it, amber to a couple over, red past.
class _LoudnessBarPainter extends CustomPainter {
  final double lufs, target;
  final StudioColors studio;
  _LoudnessBarPainter(this.lufs, this.target, this.studio);

  double _x(double v, double w) => ((v + 40) / 40).clamp(0.0, 1.0) * w;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
        Paint()..color = studio.inset);
    if (lufs.isFinite) {
      var colour = lufs > target + 2
          ? studio.meterHigh
          : lufs > target - 1
              ? studio.meterMid
              : studio.meterLow;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, _x(lufs, size.width), size.height),
              const Radius.circular(3)),
          Paint()..color = colour);
    }
    var t = _x(target, size.width);
    canvas.drawLine(
        Offset(t, -2),
        Offset(t, size.height + 2),
        Paint()
          ..color = studio.text
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_LoudnessBarPainter old) =>
      old.lufs != lufs || old.target != target;
}

/// _SpectrogramPainter is a Spectrum over time: a column a tick, the
/// oldest on the left, low pitches at the bottom, each as bright as loud.
class _SpectrogramPainter extends CustomPainter {
  final List<Float32List> history;
  final int count;
  _SpectrogramPainter(this.history, this.count);

  static const int _rows = 64;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0E1622));
    if (history.isEmpty) return;
    var colW = size.width / _ListenerDeviceState._historyLength;
    var rowH = size.height / _rows;
    var left = size.width - history.length * colW;
    const lowHz = 30.0, highHz = 20000.0;
    var paint = Paint();
    for (var (c, bins) in history.indexed) {
      for (var r = 0; r < _rows; r++) {
        var hz = lowHz * math.pow(highHz / lowHz, r / _rows);
        var i = (hz / 24000 * bins.length).floor().clamp(0, bins.length - 1);
        var db = 20 * math.log(math.max(1e-6, bins[i])) / math.ln10;
        var v = ((db + 80) / 80).clamp(0.0, 1.0);
        if (v < 0.05) continue;
        paint.color = Color.lerp(
            const Color(0xFF3C2470),
            v < 0.6 ? const Color(0xFFD0506A) : const Color(0xFFFFE9A8),
            v < 0.6 ? v / 0.6 : (v - 0.6) / 0.4)!;
        canvas.drawRect(
            Rect.fromLTWH(left + c * colW, size.height - (r + 1) * rowH,
                colW + 0.5, rowH + 0.5),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrogramPainter old) => true;
}

/// _SpectrumPainter is a sound's spectrum, low on the left to high on the
/// right, the frequencies spread as an octave a step.
class _SpectrumPainter extends CustomPainter {
  final Float32List? bins;
  final StudioColors studio;
  _SpectrumPainter(this.bins, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0E1622));
    var b = bins;
    if (b == null || b.isEmpty) return;
    var path = Path()..moveTo(0, size.height);
    const lowHz = 30.0, highHz = 20000.0;
    for (var x = 0.0; x <= size.width; x += 2) {
      var hz = lowHz * math.pow(highHz / lowHz, x / size.width);
      var i = (hz / 24000 * b.length).floor().clamp(0, b.length - 1);
      var db = 20 * math.log(math.max(1e-6, b[i])) / math.ln10;
      var y = size.height * (1 - ((db + 80) / 80).clamp(0.0, 1.0));
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = studio.on.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => true;
}

/// DeviceLevels is a device's screen: its own picture (see
/// device_screens.dart), moving with the sound, or where it has none how
/// loud the sound is going into it and coming out of it over the last few
/// seconds. What it changes the level by is read between the devices of
/// [channel]'s strip -- see CanvasController.deviceLevels -- and is not
/// shown for a strip that is not a channel's (null).
class DeviceLevels extends StatefulWidget {
  final CanvasController controller;
  final String? channel;
  final int index;

  /// device is what it draws: see hasScreen. [deviceId] is its id on the
  /// strip, by which its display is switched on (see
  /// CanvasController.analysing); none, it is a picture only.
  final MixDevice? device;
  final String? deviceId;
  final Color accent;

  /// back is the display's background: the studio palette's Display.
  final Color back;
  const DeviceLevels(
      {required this.controller,
      required this.channel,
      required this.index,
      required this.accent,
      this.device,
      this.deviceId,
      this.back = const Color(0xFF110F22),
      super.key});

  @override
  State<DeviceLevels> createState() => _DeviceLevelsState();
}

class _DeviceLevelsState extends State<DeviceLevels>
    with SingleTickerProviderStateMixin, _Metered {
  /// _history is the last few seconds of (in, out), in decibels, oldest
  /// first: for a device with no picture of its own.
  final List<(double, double)> _history = [];
  static const int _length = 120;

  /// _scope is what the engine last kept of the sound through it, and
  /// _stamp counts the readings, for the painter.
  ScopeReading? _scope;
  int _stamp = 0;

  @override
  CanvasController get meteredBy => widget.controller;

  /// _moving is a modulator's screen: what it moves knobs by, drawn as it
  /// goes -- there is no sound through it to show.
  bool get _moving => widget.device?.kind.modulates ?? false;

  /// _t is how long it has been moving, for a modulator's screen.
  double _t = 0;

  /// _on is whether its display shows the real sound (Ken: off until
  /// switched on, as it costs).
  bool get _on {
    if (_moving) return false;
    var channel = widget.channel, id = widget.deviceId;
    if (channel == null || id == null) return widget.device == null;
    return widget.controller.analysing(channel, id);
  }

  @override
  bool get metering => _on || _moving || widget.device == null;

  @override
  void didUpdateWidget(DeviceLevels old) {
    super.didUpdateWidget(old);
    meterAgain();
    if (!_on) _scope = null;
  }

  @override
  void dispose() {
    var channel = widget.channel, id = widget.deviceId;
    if (channel != null && id != null) {
      widget.controller.stopScope(channel, id);
    }
    super.dispose();
  }

  @override
  void tick() {
    _t += 0.033;
    var channel = widget.channel;
    if (channel == null) return;
    var id = widget.deviceId;
    var device = widget.device;
    if (device != null && hasScreen(device.kind)) {
      if (id != null && _on) {
        _scope = widget.controller.deviceScope(channel, id);
        _stamp++;
      }
      return;
    }
    var taps = widget.controller.deviceLevels(channel);
    var i = widget.index;
    if (i + 1 >= taps.length) return;
    double db((double, double) p) => gainToDb(math.max(p.$1, p.$2));
    _history.add((db(taps[i]), db(taps[i + 1])));
    if (_history.length > _length) _history.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    var device = widget.device;
    if (device != null && hasScreen(device.kind)) {
      var channel = widget.channel, id = widget.deviceId;
      var on = _on;
      return Stack(fit: StackFit.expand, children: [
        CustomPaint(
          painter: _moving
              ? DeviceScreenPainter(
                  device,
                  ScreenMoment(t: _t, live: widget.controller.playing),
                  widget.accent,
                  widget.back)
              : on
              ? DeviceAnalysisPainter(
                  device, _scope, widget.accent, widget.back, stamp: _stamp)
              // Off: a still picture of what its settings do.
              : DeviceScreenPainter(
                  device, const ScreenMoment(), widget.accent, widget.back),
        ),
        if (channel != null && id != null && !_moving)
          Positioned(
            top: 3,
            right: 3,
            child: _AnalyseSwitch(
              key: ValueKey("deviceAnalyse-$id"),
              on: on,
              accent: widget.accent,
              onTap: () => widget.controller.setAnalysing(channel, id, !on),
            ),
          ),
      ]);
    }
    return CustomPaint(
      painter: _LevelsPainter(
          List.of(_history), _length, widget.accent, widget.back),
      child: const SizedBox.expand(),
    );
  }
}

/// _AnalyseSwitch puts a device's display on or off: "Analyse", lit while
/// it shows the real sound.
class _AnalyseSwitch extends StatelessWidget {
  final bool on;
  final Color accent;
  final VoidCallback onTap;
  const _AnalyseSwitch(
      {required this.on, required this.accent, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return Tooltip(
      message: on
          ? "Stop showing the sound through it"
          : "Show the real sound going in and coming out",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
              color: on
                  ? accent.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: on ? accent : look.studio.edge)),
          child: Text("Analyse",
              style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: on ? look.studio.text : look.studio.muted)),
        ),
      ),
    );
  }
}

class _LevelsPainter extends CustomPainter {
  final List<(double, double)> history;
  final int length;
  final Color accent;
  final Color back;
  _LevelsPainter(this.history, this.length, this.accent, this.back);

  /// _y is where [db] sits, nought at the top to minus sixty at the bottom.
  static double _y(double db, double h) =>
      ((-db) / 60).clamp(0.0, 1.0) * (h - 6) + 3;

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    var grid = Paint()..color = Color.lerp(back, Colors.white, 0.07)!;
    for (var db in [-12.0, -24.0, -36.0, -48.0]) {
      canvas.drawRect(Rect.fromLTWH(0, _y(db, h), w, 1), grid);
    }
    if (history.length < 2) {
      _label(canvas, "Its levels in and out, while it plays", 6, h - 15,
          const Color(0xFF8E8A9C));
      return;
    }
    Path line(double Function((double, double)) of) {
      var p = Path();
      for (var (i, v) in history.indexed) {
        var x = w - (history.length - 1 - i) * w / (length - 1);
        var y = _y(of(v), h);
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    canvas.drawPath(
        line((v) => v.$1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x667FC8F8));
    canvas.drawPath(
        line((v) => v.$2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent);
    var (inDb, outDb) = history.last;
    var change = inDb <= -80 || outDb <= -80 ? null : outDb - inDb;
    _label(
        canvas,
        change == null
            ? "—"
            : "${change >= 0 ? "+" : "−"}${change.abs().toStringAsFixed(1)} dB",
        6,
        h - 15,
        change == null
            ? const Color(0xFF8E8A9C)
            : change > 0.05
                ? const Color(0xFFE2B04A)
                : change < -0.05
                    ? const Color(0xFF7FC8F8)
                    : const Color(0xFFE8E4EE));
  }

  void _label(Canvas canvas, String text, double x, double y, Color colour) {
    var tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: 10,
                color: colour,
                fontFeatures: const [FontFeature.tabularFigures()])),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(_LevelsPainter old) =>
      old.history.length != history.length ||
      (history.isNotEmpty && old.history.last != history.last) ||
      old.accent != accent;
}

/// VoiceStartCard is the way into a channel's Speech where it has none --
/// "Speak a script" -- or, with [sing], to its Vocaliser: "Sing it", a sung
/// copy of the speech made as a new clip.
class VoiceStartCard extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final double height;
  final bool sing;
  const VoiceStartCard(
      {required this.controller,
      required this.channel,
      required this.height,
      this.sing = false,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    return Container(
      width: 200,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: look.studio.strip,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: look.studio.edge)),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(sing ? Icons.music_note : Icons.record_voice_over,
              size: 20, color: skin.ink),
          const SizedBox(height: 8),
          Text(
              sing
                  ? "Sing it: the speech sung to notes, made as a new clip."
                  : "Speak a script: each line spoken is a clip on this "
                      "channel, beside recordings.",
              style: TextStyle(fontSize: 11.5, height: 1.4, color: skin.dim)),
          const SizedBox(height: 10),
          FilledButton.tonal(
            key: ValueKey(sing ? "speechSingButton" : "speechStartButton"),
            onPressed: () {
              controller.beginInteraction();
              if (sing) {
                controller.setVocaliser(channel, const VocaliserSpec());
              } else {
                controller.setSpeech(channel, const SpeechSpec());
              }
              controller.endInteraction();
              controller.openEffects(channel,
                  device: sing ? "vocaliser" : "speech");
            },
            child: Text(sing ? "Sing it" : "Speak a script"),
          ),
        ]),
      ),
    );
  }
}

// ---- Packed settings

/// PackWide marks a setting of a DevicePack that takes the whole row: a
/// list of chips, a line of text.
class PackWide extends StatelessWidget {
  final Widget child;
  const PackWide(this.child, {super.key});

  @override
  Widget build(BuildContext context) => child;
}

/// DevicePack lays a card's settings out as the chain prototype does (Ken,
/// 2026-11-08: the motion devices as the audio ones, their displays big):
/// knobs a cell each and the rest in columns -- two on a narrow card,
/// three on a wide one -- side by side and wrapping, rather than one to a
/// row. The settings then take a few short rows, and the display above
/// them keeps the card's height.
class DevicePack extends StatelessWidget {
  final List<Widget> children;
  const DevicePack({required this.children, super.key});

  static const double knobWidth = 54, gap = 8;

  /// columns is how many settings sit across [room].
  static int columns(double room, double scale) => room >= 370 * scale ? 3 : 2;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
        var room = box.maxWidth.isFinite ? box.maxWidth : 300.0;
        var n = columns(room, scale);
        var cell = ((room - gap * (n - 1)) / n).floorToDouble();
        return Wrap(spacing: gap, runSpacing: 7, children: [
          for (var w in children)
            SizedBox(
                width: w is PackWide
                    ? room
                    : DeviceFrame._isKnob(w)
                        ? knobWidth * scale
                        : cell,
                child: w),
        ]);
      });
}

// ---- The motion chain

/// MotionDeviceCard is one device of an element's motion chain (see
/// motion_devices.dart) in the Chain's Motion view, as a sound's devices
/// are in its Sound view: its switch, its knobs, a screen of what it does,
/// arrows to move it along its side of the drawing, and a way to take it
/// out.
class MotionDeviceCard extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final String device;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const MotionDeviceCard({
    required this.controller,
    required this.element,
    required this.device,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var all = controller.motionDevicesOf(element);
    var d = all.where((x) => x.id == device).firstOrNull;
    if (d == null) return const SizedBox.shrink();
    var side = [
      for (var x in all)
        if (x.side == d.side) x.id
    ];
    var at = side.indexOf(d.id);
    void write(MotionDevice next, {bool transient = false}) {
      var now = controller.motionDevicesOf(element);
      controller.beginInteraction();
      controller.setMotionDevices(
          element, [for (var x in now) x.id == next.id ? next : x],
          transient: true);
      if (!transient) controller.endInteraction();
    }

    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var pose = d.side == MotionDeviceSide.pose;
    // Which of its knobs an LFO in the chain moves.
    var moved = {
      for (var l in all)
        if (l.on && l.modulates)
          for (var m in l.mods)
            if (m.device == d.id) m.param,
    };
    var accent = pose ? const Color(0xFF6FA8FF) : const Color(0xFFE59BFF);
    // Right-click: move it with a modulator of the element's chain.
    List<(String, VoidCallback)> modMenu(DeviceParam p) {
      if (d.modulates) return const [];
      void moveWith(MotionDevice m, ModTarget t) {
        if (m.mods.any((x) =>
            x.device == t.device && x.param == t.param && x.from == t.from)) {
          return;
        }
        var now = controller.motionDevicesOf(element);
        controller.beginInteraction();
        controller.setMotionDevices(element, [
          for (var x in now) x.id == m.id ? x.withMods([...x.mods, t]) : x
        ]);
        controller.endInteraction();
      }

      // A modulator of its own, made for it, as a sound knob's menu has.
      void added(MotionDeviceKind kind, ModTarget t) {
        var now = controller.motionDevicesOf(element);
        controller.beginInteraction();
        controller.setMotionDevices(
            element,
            motionDevicesInOrder(withMotionDeviceIds(
                [...now, MotionDevice(kind).withMods([t])])));
        controller.endInteraction();
      }

      var macro =
          all.where((m) => m.kind == MotionDeviceKind.macro).firstOrNull;
      return [
        for (var m in all)
          if (m.id != d.id && m.modulates)
            if (m.kind == MotionDeviceKind.macro)
              for (var k = 0; k < macroKnobs; k++)
                (
                  "Turn with ${m.kind.label}'s M${k + 1}",
                  () => moveWith(m, ModTarget(d.id, p.id, 0.5, k))
                )
            else
              (
                "Move with ${m.kind.label}",
                () => moveWith(m, ModTarget(d.id, p.id))
              ),
        if (!p.isChoice) ...[
          (
            "Move it with a new LFO",
            () => added(MotionDeviceKind.lfo, ModTarget(d.id, p.id))
          ),
          (
            "Add it to a macro",
            () {
              if (macro == null) {
                return added(
                    MotionDeviceKind.macro, ModTarget(d.id, p.id, 0.5, 0));
              }
              var used = {for (var t in macro.mods) t.from};
              var k = [for (var k = 0; k < macroKnobs; k++) k]
                      .where((k) => !used.contains(k))
                      .firstOrNull ??
                  0;
              moveWith(macro, ModTarget(d.id, p.id, 0.5, k));
            }
          ),
        ],
        ("Reset", () => write(d.withValue(p.id, p.initial))),
      ];
    }

    var reused = controller.motionOf(element).instances != null;
    // With copies picked, a knob is theirs: their own value, or the shared
    // one, and turned it becomes their own (Ken, 2026-11-08).
    var copies = controller.copiesPicked(element);
    (double, bool) knobAt(DeviceParam p) =>
        controller.deviceKnob(element, d.id, p.id, d.value(p.id));
    void set(DeviceParam p, double v, {bool transient = false}) {
      if (!copies) return write(d.withValue(p.id, v), transient: transient);
      controller.beginInteraction();
      controller.setCopyOwn(element, deviceOwnKey(d.id, p.id), v,
          transient: true);
      if (!transient) controller.endInteraction();
    }

    List<(String, VoidCallback)> ownMenu(DeviceParam p) => [
          if (copies && knobAt(p).$2)
            (
              "Back to the shared value",
              () {
                controller.beginInteraction();
                controller.setCopyOwn(element, deviceOwnKey(d.id, p.id), null);
                controller.endInteraction();
              }
            ),
        ];
    List<Widget> knobs(DeviceTier tier) => [
          for (var p in d.kind.params)
            if (!p.isChoice && motionParamShown(d, p, reused: reused))
              _Knob(
                key: ValueKey("mdev-${d.id}-${p.id}"),
                modulated: moved.contains(p.id),
                own: knobAt(p).$2,
                menu: [...ownMenu(p), ...modMenu(p)],
                label: p.label,
                text: p.reading(knobAt(p).$1),
                value: knobAt(p).$1,
                initial: p.initial,
                range: _Range(p.min, p.max),
                size: switch (tier) {
                  DeviceTier.large => 46,
                  DeviceTier.medium => 38,
                  _ => 30,
                },
                reading: true,
                accent: accent,
                ink: skin.ink,
                bipolar: p.min < 0 && p.max > 0,
                onChanged: (v, {transient = false}) =>
                    set(p, v, transient: transient),
                onCommit: controller.endInteraction,
              ),
          // What an LFO moves: any knob of the element's other devices.
          if (d.modulates)
            ModTargets(
              key: ValueKey("mdevMods-${d.id}"),
              mods: d.mods,
              sources: d.kind == MotionDeviceKind.macro
                  ? [for (var i = 1; i <= macroKnobs; i++) "M$i"]
                  : const [],
              knobs: [
                for (var x in all)
                  if (x.id != d.id && !x.modulates)
                    for (var p in x.kind.params)
                      if (!p.isChoice)
                        (x.id, p.id, "${x.kind.label} · ${p.label}"),
              ],
              ink: skin.ink,
              onChanged: (mods, {transient = false}) =>
                  write(d.withMods(mods), transient: transient),
              onCommit: controller.endInteraction,
            ),
          // Its choices, and what it follows or looks at: dropdowns side by
          // side under its knobs, as the prototype's Seed and Follows.
          if (d.takesTarget ||
              d.kind.params.any(
                  (p) => p.isChoice && motionParamShown(d, p, reused: reused)))
            DevicePack(key: ValueKey("mdevPack-${d.id}"), children: [
              for (var p in d.kind.params)
                if (p.isChoice && motionParamShown(d, p, reused: reused))
                  StudioDrop<int>(
                    key: ValueKey("mdev-${d.id}-${p.id}"),
                    label: knobAt(p).$2 ? "${p.label} · its own" : p.label,
                    value: knobAt(p).$1.round(),
                    options: [for (var (i, ch) in p.choices.indexed) (i, ch)],
                    onChanged: (i) => set(p, i.toDouble()),
                  ),
              if (d.takesTarget)
                StudioDrop<String>(
                  key: ValueKey("mdevTarget-${d.id}"),
                  label: switch (d.kind) {
                    MotionDeviceKind.followPath => "Path",
                    MotionDeviceKind.followSound ||
                    MotionDeviceKind.follower =>
                      "Channel",
                    MotionDeviceKind.spring => "Chases",
                    _ => "Looks at",
                  },
                  value: d.target,
                  options: [
                    ("", "Nothing"),
                    // Facing the camera, wherever it is pointed.
                    if (d.kind == MotionDeviceKind.lookAt) ...[
                      (lookAtCamera, "The camera"),
                      (lookAtPointer, "The pointer"),
                    ],
                    // A sound follows a channel's loudness.
                    if (d.kind == MotionDeviceKind.followSound ||
                        d.kind == MotionDeviceKind.follower)
                      for (var ch in controller.timelineChannels)
                        (ch.key, ch.name)
                    else
                      for (var x in controller.document.elements)
                        if (x.id != element &&
                            (d.kind != MotionDeviceKind.followPath ||
                                x is PathElement ||
                                x is LineElement))
                          (x.id, x.name.isEmpty ? x.id : x.name),
                  ],
                  onChanged: (v) => write(d.withTarget(v)),
                ),
            ]),
          if (d.side == MotionDeviceSide.look &&
              d.kind != MotionDeviceKind.colour &&
              d.kind != MotionDeviceKind.blur)
            _LookColour(
                key: ValueKey("mdevColour-${d.id}"),
                colour: d.colour,
                ink: skin.ink,
                onPick: (c) => write(d.withColour(c))),
        ];
    return DeviceFrame(
      id: "mdev:${d.id}",
      title: d.kind.label,
      help: motionAbout(d.kind),
      // Its presets, as a sound device's: Default, those saved of its
      // kind, and Save -- a preset's knobs put on, its target kept.
      barExtras: [
        _StripPresetPicker(
          key: ValueKey("mdevPreset-${d.id}"),
          label: d.kind.label,
          kept: () => [
            for (var p in devicePresets.presets)
              if (motionPresetOf(p.data) case var m? when m.kind == d.kind)
                (p.name, p.data["motion"] as Map<String, dynamic>),
          ],
          name: controller.presetNameOf(element, "mdev:${d.id}"),
          builtIn: const [],
          onPick: (name, value) {
            var m = MotionDevice.fromJson(value);
            if (m == null) return;
            var next = d;
            for (var p in d.kind.params) {
              next = next.withValue(p.id, m.value(p.id));
            }
            write(next);
            controller.setPresetName(element, "mdev:${d.id}", name);
          },
          onDefault: () {
            write(MotionDevice(d.kind, on: d.on)
                .withId(d.id)
                .withTarget(d.target)
                .withMods(d.mods));
            controller.setPresetName(element, "mdev:${d.id}", null);
          },
          onSave: () => saveMotionPreset(context, d),
        ),
      ],
      onSavePreset: () => saveMotionPreset(context, d),
      // A copy beside it, and its settings back as they began.
      onDuplicate: () {
        var now = controller.motionDevicesOf(element);
        var i = now.indexWhere((x) => x.id == d.id);
        if (i < 0) return;
        controller.beginInteraction();
        controller.setMotionDevices(
            element, withMotionDeviceIds([...now]..insert(i + 1, d.withId(""))));
        controller.endInteraction();
      },
      onReset: () {
        var fresh = MotionDevice(d.kind, on: d.on).withId(d.id);
        controller.beginInteraction();
        controller.setMotionDevices(element, [
          for (var x in controller.motionDevicesOf(element))
            x.id == d.id ? fresh.withTarget(d.target).withMods(d.mods) : x
        ]);
        controller.endInteraction();
      },
      // A second set of its knobs to compare, as a sound device's A|B.
      onAB: () => controller.toggleABOf("$element|mdev:${d.id}", d,
          (o) => write((o as MotionDevice).switched(d.on).withTarget(d.target),
              transient: true)),
      showingB: controller.showingBOf("$element|mdev:${d.id}"),
      // What it does made keys, for an EPUB, and it switched off.
      extraMenu: pose &&
              d.on &&
              !d.modulates &&
              d.kind != MotionDeviceKind.instances &&
              d.kind != MotionDeviceKind.follower
          ? (look) => [
                chainMenuItem(look,
                    key: ValueKey("mdevBake-${d.id}"),
                    text: "Bake into keys",
                    hint: "for EPUB", onPressed: () {
                  var why = controller.bakeMotionDevice(element, d.id);
                  try {
                    var snack = SnackBarModel.of(context);
                    why == null
                        ? snack.success("Baked: the ${d.kind.label} is keys "
                            "in a clip now, and switched off")
                        : snack.error(why);
                  } catch (_) {}
                }),
              ]
          : null,
      skin: skin,
      on: d.on,
      onPower: (v) => write(d.switched(v)),
      powerKey: ValueKey("mdevPower-${d.id}"),
      folded: folded,
      onFold: onFold,
      // As wide as its knobs on one row, and room for two dropdowns.
      // Wide enough for its presets' mark beside its name and its A|B.
      width: math.max(
          280.0,
          16.0 +
              58 *
                  d.kind.params.where((p) => !p.isChoice).length *
                  MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5)),
      height: height,
      icon: pose ? Icons.timer_outlined : Icons.auto_awesome,
      accent: accent,
      besideDisplay: 250,
      besideSettings: 200,
      actions: [
        DeviceMove(
            id: "mdev-${d.id}",
            canLeft: at > 0,
            canRight: at < side.length - 1,
            onMove: (by) => controller.moveMotionDevice(element, d.id, by),
            ink: _headerInkLight),
        IconButton(
          key: ValueKey("mdevRemove-${d.id}"),
          tooltip: "Take the ${d.kind.label.toLowerCase()} off",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: _headerInkLight),
          onPressed: () => controller.removeMotionDevice(element, d.id),
        ),
      ],
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: knobs,
      // A screen where there is something to show without the element:
      // a look on a square, Time's curve, a wave's shape.
      // Every kind has one now (Ken, 2026-11-08: the motion chain as
      // usable as the sound's): its settings drawn.
      display: d.kind != MotionDeviceKind.instances
          ? SizedBox.expand(
              child: CustomPaint(
                  key: ValueKey("mdevScreen-${d.id}"),
                  painter: _MotionScreen(d, look.studio.display, accent)),
            )
          : null,
      summary: [
        for (var p in d.kind.params.take(2))
          "${p.label} ${p.reading(d.value(p.id))}"
      ].join(" · "),
    );
  }
}

/// _LookColour is the colour a look draws in: its own (none chosen), or
/// one of a few.
class _LookColour extends StatelessWidget {
  final int? colour;
  final Color ink;
  final ValueChanged<int?> onPick;
  const _LookColour(
      {required this.colour,
      required this.ink,
      required this.onPick,
      super.key});

  static const _choices = <int?>[
    null,
    0xFF000000,
    0xFFFFFFFF,
    0xFFFFD54F,
    0xFFFF5252,
    0xFF40C4FF,
    0xFF69F0AE,
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 92,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Colour", style: TextStyle(fontSize: 11, color: ink)),
          const SizedBox(height: 4),
          Wrap(spacing: 3, runSpacing: 3, children: [
            for (var c in _choices)
              Tooltip(
                message: c == null ? "Its own" : "",
                child: InkWell(
                  key: ValueKey("lookColour-${c ?? "own"}"),
                  onTap: () => onPick(c),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: c == null ? null : Color(c),
                      gradient: c == null
                          ? const SweepGradient(colors: [
                              Color(0xFFFF5252),
                              Color(0xFFFFD54F),
                              Color(0xFF69F0AE),
                              Color(0xFF40C4FF),
                              Color(0xFFFF5252),
                            ])
                          : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: colour == c ? ink : ink.withValues(alpha: 0.3),
                          width: colour == c ? 2 : 1),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      );
}

/// _MotionScreen is a motion device's screen: a look drawn on a square, as
/// it would be on the element; Time, the moment it asks for against the
/// moment it is.
class _MotionScreen extends CustomPainter {
  final MotionDevice device;
  final Color back, accent;
  _MotionScreen(this.device, this.back, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    if (size.width < 8 || size.height < 8) return;
    if (device.kind == MotionDeviceKind.wiggle ||
        device.kind == MotionDeviceKind.oscillate) {
      // Four seconds of what it adds, across.
      var path = Path();
      var amount = device.value("amount");
      double at(double t) => device.kind == MotionDeviceKind.oscillate
          ? math.sin(
              2 * math.pi * (device.value("rate") * t + device.value("phase")))
          : (math.sin(t * device.value("speed") * 2.1) * 0.5 +
              math.sin(t * device.value("speed") * 4.7 + 1.3) * 0.3 +
              math.sin(t * device.value("speed") * 9.3 + 2.1) * 0.2);
      var reach = amount <= 0 ? 0.0 : 0.42;
      for (var i = 0; i <= 160; i++) {
        var x = size.width * i / 160;
        var y = size.height * (0.5 - at(4.0 * i / 160) * reach);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = device.on ? accent : accent.withValues(alpha: 0.4));
      return;
    }
    var ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = device.on ? accent : accent.withValues(alpha: 0.4);
    var faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.2);
    var w = size.width, h = size.height;
    Path curve(double Function(double u) y, {int steps = 120}) {
      var path = Path();
      for (var i = 0; i <= steps; i++) {
        var u = i / steps;
        i == 0 ? path.moveTo(u * w, y(u)) : path.lineTo(u * w, y(u));
      }
      return path;
    }

    switch (device.kind) {
      case MotionDeviceKind.spring:
        // A step: where its keys go (the dashed line), and it overshooting
        // and settling there.
        var k = device.value("stiffness"), damp = device.value("damping");
        var top = h * 0.25, bottom = h * 0.82;
        canvas.drawLine(Offset(0, top), Offset(w, top), faint);
        canvas.drawPath(
            curve((u) {
              var t = u * 2.5;
              var settle = 1 -
                  math.exp(-t * damp * k * 0.5) * math.cos(t * k * 0.9);
              return bottom - (bottom - top) * settle;
            }),
            ink);
        return;
      case MotionDeviceKind.squash:
        // A ball as it lands: squashed by Amount, more the faster.
        var a = device.value("amount") * (0.4 + 0.6 * device.value("bySpeed"));
        var r = math.min(w, h) * 0.22;
        var floor = h * 0.85;
        canvas.drawLine(Offset(8, floor), Offset(w - 8, floor), faint);
        for (var (i, sq) in [0.0, a * 0.5, a].indexed) {
          var cx = w * (0.22 + 0.28 * i);
          var rw = r * (1 + sq * 0.6), rh = r * (1 - sq * 0.5);
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(cx, floor - rh), width: rw * 2, height: rh * 2),
              ink..style = i == 2 ? PaintingStyle.fill : PaintingStyle.stroke);
        }
        return;
      case MotionDeviceKind.followPath:
        // A path, and where along it it starts.
        Offset at(double u) => Offset(
            w * (0.1 + 0.8 * u), h * (0.5 - math.sin(u * 2 * math.pi) * 0.3));
        var path = Path()..moveTo(at(0).dx, at(0).dy);
        for (var i = 1; i <= 60; i++) {
          path.lineTo(at(i / 60).dx, at(i / 60).dy);
        }
        canvas.drawPath(path, faint..strokeWidth = 2);
        var start = at(device.value("start"));
        canvas.drawCircle(start, 6,
            Paint()..color = device.on ? accent : accent.withValues(alpha: 0.4));
        if (device.target.isEmpty) _say(canvas, size, "Pick a path below");
        return;
      case MotionDeviceKind.lookAt:
        // It, turned to face what it looks at, with its offset.
        var me = Offset(w * 0.3, h * 0.6), them = Offset(w * 0.78, h * 0.3);
        canvas.drawCircle(them, 5, Paint()..color = accent.withValues(alpha: 0.5));
        var a = math.atan2(them.dy - me.dy, them.dx - me.dx) +
            device.value("offset") * math.pi / 180;
        var tip = me + Offset(math.cos(a), math.sin(a)) * math.min(w, h) * 0.3;
        canvas.drawLine(me, tip, ink);
        canvas.drawCircle(me, 7, ink..style = PaintingStyle.fill);
        if (device.target.isEmpty) _say(canvas, size, "Pick what it looks at");
        return;
      case MotionDeviceKind.followSound || MotionDeviceKind.follower:
        // A sound coming and going (faint) and it rising after it,
        // smoothed as set.
        var smooth = device.value("smooth");
        double loud(double u) =>
            (math.sin(u * 19) * 0.5 + 0.5) * (u % 0.33 < 0.2 ? 1 : 0.15);
        canvas.drawPath(curve((u) => h * 0.9 - loud(u) * h * 0.7), faint);
        var env = 0.0, k = 1 - smooth * 0.95;
        canvas.drawPath(
            curve((u) {
              env += (loud(u) - env) * k * 0.25;
              return h * 0.9 - env * h * 0.7;
            }),
            ink);
        if (device.target.isEmpty) _say(canvas, size, "Pick a channel below");
        return;
      case MotionDeviceKind.lfo:
        // Two of its cycles in its shape.
        var shape = device.value("shape").round(),
            phase = device.value("phase");
        canvas.drawPath(
            curve((u) => h / 2 - lfoValue(shape, 2 * u + phase) * (h / 2 - 6)),
            ink);
        return;
      case MotionDeviceKind.macro:
        // Its knobs as bars, as far as each is turned.
        var bar = (w - 10) / macroKnobs;
        for (var i = 0; i < macroKnobs; i++) {
          var full = Rect.fromLTWH(5 + i * bar + 3, 8, bar - 6, h - 16);
          canvas.drawRect(full, Paint()..color = accent.withValues(alpha: 0.15));
          var up = device.value("m${i + 1}");
          canvas.drawRect(
              Rect.fromLTRB(full.left, full.bottom - full.height * up,
                  full.right, full.bottom),
              Paint()..color = accent);
        }
        return;
      default:
        break;
    }
    if (device.kind == MotionDeviceKind.time) {
      // Eight seconds along; the moment asked for, up the side.
      const span = 8.0;
      var grid = Paint()..color = accent.withValues(alpha: 0.15);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), grid);
      var path = Path();
      for (var i = 0; i <= 120; i++) {
        var t = span * i / 120;
        var y = size.height -
            (retimed(device, t) / span).clamp(0.0, 1.0) * size.height;
        var x = size.width * i / 120;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = device.on ? accent : accent.withValues(alpha: 0.4));
      return;
    }
    // A look is shown on a page, as it would mostly be seen: a shadow in its
    // own black would vanish on the dark screen.
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFE9E6DF));
    var side = math.min(size.width, size.height) * 0.42;
    var box = Rect.fromCenter(
        center: size.center(Offset.zero), width: side, height: side);
    void square() => canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(side * 0.12)),
        Paint()..color = accent);
    if (!device.on) return square();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintWithLooks(canvas, box, [device], square);
    canvas.restore();
  }

  /// _say writes [text] small at the foot: what it is waiting for.
  void _say(Canvas canvas, Size size, String text) {
    var tp = TextPainter(
        text: TextSpan(
            text: text,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8E8A9C))),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: size.width - 12);
    tp.paint(canvas, Offset(6, size.height - tp.height - 4));
  }

  @override
  bool shouldRepaint(_MotionScreen old) =>
      old.device != device || old.back != back || old.accent != accent;
}

/// AddMotionDeviceSlot puts a move (or a look, by [side]) on [element]'s
/// motion chain: the chain's "+".
class AddMotionDeviceSlot extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final MotionDeviceSide side;
  final double height;
  const AddMotionDeviceSlot(
      {required this.controller,
      required this.element,
      required this.side,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var pose = side == MotionDeviceSide.pose;
    return AddSlot(
      id: pose ? "addMoveOpen" : "addLookOpen",
      title: pose ? "Add a move" : "Add a look",
      height: height,
      // By family, as the sound chain's "+" lists them.
      groups: [
        for (var family in {
          for (var k in MotionDeviceKind.on(side)) motionFamily(k),
        })
          (
            family,
            [
              for (var k in MotionDeviceKind.on(side))
                if (motionFamily(k) == family)
                  (
                    "addMotion-${k.name}",
                    k.label,
                    () {
                      controller.beginInteraction();
                      controller.addMotionDevice(element, k);
                      controller.endInteraction();
                    }
                  ),
            ]
          ),
      ],
    );
  }
}

/// MotionJoin is the join after the first [upto] pose devices of
/// [element]'s motion chain -- after its clips, for nought: how fast it is
/// going there, as a bar and in its tooltip with its pose; clicked, the
/// stage shows the element as the chain leaves it there ("Preview from
/// here"), and clicked again, whole.
class MotionJoin extends StatefulWidget {
  final CanvasController controller;
  final String element;
  final int upto;
  final double height;
  const MotionJoin(
      {required this.controller,
      required this.element,
      required this.upto,
      required this.height,
      super.key});

  @override
  State<MotionJoin> createState() => _MotionJoinState();
}

class _MotionJoinState extends State<MotionJoin>
    with SingleTickerProviderStateMixin, _Metered {
  @override
  CanvasController get meteredBy => widget.controller;

  double _speed = 0;
  Keyframe _pose = Keyframe.rest;

  @override
  void tick() {
    var c = widget.controller;
    var e = c.document.elementById(widget.element);
    if (e == null) return;
    var (speed, pose) = motionSpeedAt(e, c.frame, c.document,
        upto: widget.upto, live: c.liveMotion);
    _speed = speed;
    _pose = pose;
  }

  @override
  Widget build(BuildContext context) {
    // Read again on every build too -- a frame scrubbed to, the chain
    // changed -- as the ticker rests while nothing plays.
    tick();
    var c = widget.controller;
    var look = MixerLook.of(context);
    var on = c.motionPreview == (widget.element, widget.upto);
    // A thousand pixels a second fills it; slower is more than its share,
    // so a drift still shows.
    var fill = (math.log(1 + _speed) / math.log(1001)).clamp(0.0, 1.0);
    return Tooltip(
      message: "x ${_pose.dx.round()} · y ${_pose.dy.round()} · "
          "size ${_pose.scale.toStringAsFixed(2)} · turn ${_pose.rotate.round()}° · "
          "${_speed.round()} px/s\n"
          "${on ? "Showing it as it is here. Click to show it whole." : "Click to show it on the stage as it is here."}",
      // A right click: preview from here, or with its trail on the stage
      // as well, as the prototype's join menu.
      child: MenuAnchor(
        style: chainMenuStyle(look),
        menuChildren: [
          chainMenuItem(look,
              key: ValueKey("motionJoinPreview-${widget.upto}"),
              text: on ? "Show the whole chain again" : "Preview from here",
              hint: "on the canvas",
              onPressed: () =>
                  c.previewMotionFrom(widget.element, on ? null : widget.upto)),
          chainMenuItem(look,
              key: ValueKey("motionJoinTrail-${widget.upto}"),
              text: "Preview from here, with its trail", onPressed: () {
            c.motionTrail = true;
            c.previewMotionFrom(widget.element, widget.upto);
          }),
        ],
        builder: (context, menu, _) => GestureDetector(
          onSecondaryTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: InkWell(
            key: ValueKey("motionJoin-${widget.upto}"),
            onTap: () =>
                c.previewMotionFrom(widget.element, on ? null : widget.upto),
            child: Container(
              width: 22,
              height: widget.height,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: on ? look.colors.primary.withValues(alpha: 0.25) : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(children: [
                Icon(on ? Icons.visibility : Icons.visibility_outlined,
                    size: 11,
                    color: on ? look.colors.primary : look.studio.muted),
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    width: 6,
                    alignment: Alignment.bottomCenter,
                    decoration: BoxDecoration(
                      color: look.studio.display,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      key: ValueKey("motionJoinBar-${widget.upto}"),
                      heightFactor: fill,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF6FA8FF),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// modulationColour marks what a modulator moves: a knob's ring.
const Color modulationColour = Color(0xFFFF6FB5);

/// ownColour marks a copy's own value: a knob's arc and its dot.
const Color ownColour = Color(0xFFE2B04A);

/// ModTargets is what a modulator moves: each knob, by its device and its
/// name, with how far it moves it and a way to take it off, and a way to
/// add another of [knobs] -- (device id, setting, name) each.
class ModTargets extends StatelessWidget {
  final List<ModTarget> mods;
  final List<(String, String, String)> knobs;

  /// sources are a macro's knobs, by name, each target turned by one;
  /// empty for a modulator of one.
  final List<String> sources;
  final Color ink;
  final void Function(List<ModTarget> mods, {bool transient}) onChanged;
  final VoidCallback onCommit;
  const ModTargets(
      {required this.mods,
      required this.knobs,
      required this.ink,
      required this.onChanged,
      required this.onCommit,
      this.sources = const [],
      super.key});

  @override
  Widget build(BuildContext context) {
    var style = TextStyle(fontSize: 11, color: ink);
    String nameOf(ModTarget m) =>
        knobs
            .where((k) => k.$1 == m.device && k.$2 == m.param)
            .firstOrNull
            ?.$3 ??
        "Gone";
    var free = [
      for (var k in knobs)
        if (!mods.any((m) => m.device == k.$1 && m.param == k.$2)) k,
    ];
    return SizedBox(
      width: 230,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Moves", style: style.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (var (i, m) in mods.indexed)
              Row(key: ValueKey("modTarget-$i"), children: [
                Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: const BoxDecoration(
                        color: modulationColour, shape: BoxShape.circle)),
                // Which of a macro's knobs turns it.
                if (sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: CanvasDropdown<int>(
                      key: ValueKey("modFrom-$i"),
                      label: "",
                      value: m.from.clamp(0, sources.length - 1),
                      width: 64,
                      grow: false,
                      tight: true,
                      options: [
                        for (var (k, name) in sources.indexed) (k, name)
                      ],
                      onChanged: (k) =>
                          onChanged([...mods]..[i] = m.withFrom(k)),
                    ),
                  ),
                Expanded(
                  child: Text(nameOf(m),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style),
                ),
                _Knob(
                  key: ValueKey("modDepth-$i"),
                  label: "",
                  text: "${(m.depth * 100).round()}%",
                  value: m.depth,
                  initial: 0.5,
                  range: const _Range(-1, 1),
                  size: 22,
                  reading: false,
                  accent: modulationColour,
                  ink: ink,
                  bipolar: true,
                  onChanged: (v, {transient = false}) => onChanged(
                      [...mods]..[i] = m.withDepth(v),
                      transient: transient),
                  onCommit: onCommit,
                ),
                IconButton(
                  key: ValueKey("modRemove-$i"),
                  tooltip: "Stop moving it",
                  iconSize: 13,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, color: ink),
                  onPressed: () => onChanged([...mods]..removeAt(i)),
                ),
              ]),
            if (free.isNotEmpty)
              CanvasDropdown<String>(
                key: const ValueKey("modAdd"),
                label: "Add",
                value: "",
                width: 200,
                grow: false,
                options: [
                  ("", "Move a knob…"),
                  for (var k in free) ("${k.$1}|${k.$2}", k.$3),
                ],
                onChanged: (v) {
                  if (v.isEmpty) return;
                  var cut = v.indexOf("|");
                  onChanged([
                    ...mods,
                    ModTarget(v.substring(0, cut), v.substring(cut + 1)),
                  ]);
                },
              )
            else if (knobs.isEmpty)
              Text("Nothing in the chain to move yet", style: style),
          ]),
    );
  }
}

/// SplitBranches is a split's branches, a column each: its name, how loud
/// it comes back and whether it is heard, its devices -- each with its
/// switch, its knobs and a way to take it out -- and a way to add one; in
/// parallel, a way to add a branch and take one away.
class SplitBranches extends StatefulWidget {
  final MixDevice device;

  /// moved are its branches' knobs a modulator moves, each as
  /// "branch/device id/setting": a pink ring round them.
  final Set<String> moved;
  final Color ink, accent;
  final void Function(List<SplitBranch> branches, {bool transient}) onChanged;

  /// onSet changes one of the split's own settings: how it splits, and
  /// where lows give way to highs.
  final void Function(String param, double value, {bool transient}) onSet;
  final VoidCallback onCommit;
  const SplitBranches(
      {required this.device,
      required this.ink,
      required this.accent,
      required this.onChanged,
      required this.onSet,
      required this.onCommit,
      this.moved = const {},
      super.key});

  /// width is the card's: its branches listed, and the one open beside.
  static const double width = 520;

  /// _addable are the kinds a branch takes: what changes sound, not a
  /// split, a modulator or a listener.
  static List<DeviceKind> get _addable => [
        for (var k in DeviceKind.values)
          if (k != DeviceKind.split &&
              !k.modulates &&
              !listensOnly(k) &&
              k != DeviceKind.vocoder)
            k
      ];

  @override
  State<SplitBranches> createState() => _SplitBranchesState();
}

/// _SplitBranchesState is the prototype's Split (Ken, 2026-11-08: "the split
/// device visuals need improving"): the sound drawn dividing into its
/// branches, how it divides, a row for each branch -- its level, its name,
/// what is on it -- and the branch picked open beside them, to change.
class _SplitBranchesState extends State<SplitBranches> {
  int _open = 0;

  @override
  Widget build(BuildContext context) {
    var device = widget.device;
    var look = MixerLook.of(context);
    var studio = look.studio;
    var ink = widget.ink, accent = widget.accent;
    var mode = device.value("mode").round();
    var parallel = mode == 0;
    var names = splitBranchNames(mode, device.branches.length);
    var branches = [
      for (var i = 0; i < names.length; i++)
        i < device.branches.length ? device.branches[i] : const SplitBranch(),
    ];
    var open = branches.isEmpty ? null : _open.clamp(0, branches.length - 1);
    var small = TextStyle(fontSize: 10.5, color: studio.text);
    void set(int i, SplitBranch b, {bool transient = false}) {
      var next = [...branches];
      next[i] = b;
      widget.onChanged(next, transient: transient);
    }

    Widget row(int i, SplitBranch b) {
      var on = i == open;
      var level = ((b.gainDb + 60) / 72).clamp(0.0, 1.0);
      return GestureDetector(
        key: ValueKey("splitBranch-$i"),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _open = i),
        child: Container(
          height: 26,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.12) : studio.inset,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? accent : studio.edge),
          ),
          child: Row(children: [
            // Its level: how loud it is put back.
            Container(
              width: 5,
              height: 18,
              decoration: BoxDecoration(
                  color: studio.display,
                  borderRadius: BorderRadius.circular(2)),
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: b.mute ? 0 : level,
                child: Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFF5BC46B),
                        borderRadius: BorderRadius.circular(2))),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 54,
              child: Text(names[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small.copyWith(
                      color: b.mute ? studio.muted : studio.text,
                      fontWeight: on ? FontWeight.w600 : null)),
            ),
            Expanded(
              // As many of its devices as fit; the rest cut off at its end.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  for (var d in b.devices)
                    Container(
                      margin: const EdgeInsets.only(right: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: studio.raised,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(d.kind.label,
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 9.5,
                              color: d.on ? studio.muted : studio.edge)),
                    ),
                  if (b.devices.isEmpty)
                    Text("straight through",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: studio.muted)),
                ]),
              ),
            ),
            _RowButton(
              key: ValueKey("splitMute-$i"),
              label: "M",
              on: b.mute,
              tip: b.mute ? "Hear this branch again" : "Silence this branch",
              onTap: () => set(i, b.copyWith(mute: !b.mute)),
            ),
            if (parallel && branches.length > 1)
              _RowButton(
                key: ValueKey("splitRemove-$i"),
                icon: Icons.close,
                tip: "Take this branch away",
                onTap: () {
                  if (_open >= i && _open > 0) _open--;
                  widget.onChanged([...branches]..removeAt(i));
                },
              ),
          ]),
        ),
      );
    }

    Widget editor(int i, SplitBranch b) => Container(
          key: ValueKey("splitEditor-$i"),
          decoration: BoxDecoration(
            color: studio.inset,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: studio.edge),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(names[i].toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                              color: studio.muted)),
                    ),
                    SizedBox(
                      width: 52,
                      child: _Knob(
                        key: ValueKey("splitGain-$i"),
                        label: "Level",
                        text: "${b.gainDb.toStringAsFixed(1)} dB",
                        value: b.gainDb,
                        initial: 0,
                        range: const _Range(-60, 12),
                        size: 24,
                        accent: accent,
                        ink: ink,
                        onChanged: (v, {transient = false}) => set(
                            i, b.copyWith(gainDb: (v * 2).roundToDouble() / 2),
                            transient: transient),
                        onCommit: widget.onCommit,
                      ),
                    ),
                  ]),
                  for (var (j, d) in b.devices.indexed)
                    Container(
                      key: ValueKey("splitDevice-$i-$j"),
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: studio.panel,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          GestureDetector(
                            key: ValueKey("splitDevicePower-$i-$j"),
                            onTap: () => set(
                                i,
                                b.copyWith(
                                    devices: [...b.devices]..[j] =
                                        d.switched(!d.on))),
                            child: Icon(
                                d.on ? Icons.circle : Icons.circle_outlined,
                                size: 9,
                                color: d.on
                                    ? const Color(0xFF5BC46B)
                                    : studio.muted),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                              child: Text(d.kind.label.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      letterSpacing: 0.6,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          d.on ? studio.text : studio.muted))),
                          GestureDetector(
                            key: ValueKey("splitDeviceRemove-$i-$j"),
                            onTap: () => set(
                                i,
                                b.copyWith(
                                    devices: [...b.devices]..removeAt(j))),
                            child: Icon(Icons.close,
                                size: 12, color: studio.muted),
                          ),
                        ]),
                        const SizedBox(height: 3),
                        Wrap(spacing: 2, runSpacing: 2, children: [
                          for (var p in d.kind.params)
                            if (!p.isChoice)
                              SizedBox(
                                width: 46,
                                child: _Knob(
                                  key: ValueKey("splitKnob-$i-$j-${p.id}"),
                                  modulated: widget.moved.contains(
                                      "$i/${deviceIdAt(b.devices, j)}/${p.id}"),
                                  label: p.label,
                                  text: p.reading(d.value(p.id)),
                                  value: d.value(p.id),
                                  initial: p.initial,
                                  range: ParamDevice._range(p),
                                  size: 22,
                                  reading: false,
                                  accent: accent,
                                  ink: ink,
                                  bipolar: p.min < 0 && p.max > 0,
                                  onChanged: (v, {transient = false}) => set(
                                      i,
                                      b.copyWith(
                                          devices: [...b.devices]..[j] =
                                              d.withValue(p.id, v)),
                                      transient: transient),
                                  onCommit: widget.onCommit,
                                ),
                              ),
                        ]),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  CanvasDropdown<DeviceKind?>(
                    key: ValueKey("splitAdd-$i"),
                    label: "",
                    value: null,
                    width: 210,
                    grow: false,
                    options: [
                      (null, "Add a device…"),
                      for (var k in SplitBranches._addable) (k, k.label),
                    ],
                    onChanged: (k) {
                      if (k == null) return;
                      set(i, b.copyWith(devices: [...b.devices, MixDevice(k)]));
                    },
                  ),
                ]),
          ),
        );

    var crossover = device.kind.param("crossover");
    var left = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The sound dividing into its branches, and meeting again.
          Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: studio.edge.withValues(alpha: 0.8)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                key: const ValueKey("splitPicture"),
                painter: _SplitPicture(
                    mode: mode,
                    names: names,
                    muted: [for (var b in branches) b.mute],
                    picked: open,
                    crossover: device.value("crossover"),
                    accent: accent,
                    back: studio.display),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // How it divides.
          DeviceChoices(
            key: const ValueKey("splitMode"),
            options: [
              for (var (k, label)
                  in const ["Parallel", "Mid/Side", "L/R", "Low/High"].indexed)
                (
                  ValueKey("splitMode-$k"),
                  label,
                  mode == k,
                  () {
                    widget.onSet("mode", k.toDouble());
                    widget.onCommit();
                  }
                ),
            ],
          ),
          if (mode == 3) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text("Lows give way at",
                    style: TextStyle(fontSize: 10.5, color: studio.muted)),
              ),
              SizedBox(
                width: 56,
                child: _Knob(
                  key: const ValueKey("splitCrossover"),
                  label: "Crossover",
                  text: crossover.reading(device.value("crossover")),
                  value: device.value("crossover"),
                  initial: crossover.initial,
                  range: ParamDevice._range(crossover),
                  size: 22,
                  accent: accent,
                  ink: ink,
                  onChanged: (v, {transient = false}) =>
                      widget.onSet("crossover", v, transient: transient),
                  onCommit: widget.onCommit,
                ),
              ),
            ]),
          ],
          const SizedBox(height: 6),
          for (var (i, b) in branches.indexed) row(i, b),
          if (parallel && branches.length < maxBranches)
            Align(
              alignment: Alignment.centerLeft,
              child: _RowButton(
                key: const ValueKey("splitAddBranch"),
                label: "+ Branch",
                tip: "Another branch, with its own devices",
                onTap: () {
                  setState(() => _open = branches.length);
                  widget.onChanged([...branches, const SplitBranch()]);
                },
              ),
            ),
        ]);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: SplitBranches.width - 16),
      child: LayoutBuilder(
        builder: (context, box) =>
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Half each, its rows at most 240 across.
          SizedBox(width: math.min(240.0, (box.maxWidth - 8) / 2), child: left),
          const SizedBox(width: 8),
          Expanded(
            child: open == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text("Add a branch to give it devices of its own.",
                        style: TextStyle(fontSize: 10.5, color: studio.muted)),
                  )
                : editor(open, branches[open]),
          ),
        ]),
      ),
    );
  }
}

/// _RowButton is a small boxed button of a split's rows: a letter, a word,
/// or an icon; lit where [on].
class _RowButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool on;
  final String tip;
  final VoidCallback onTap;
  const _RowButton(
      {this.label,
      this.icon,
      this.on = false,
      required this.tip,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 18,
          margin: const EdgeInsets.only(left: 3),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 2 : 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0xFFE0A84F) : studio.raised,
            borderRadius: BorderRadius.circular(4),
            border:
                Border.all(color: on ? const Color(0xFFE0A84F) : studio.edge),
          ),
          child: label == null
              ? Icon(icon, size: 12, color: studio.muted)
              : Text(label!,
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: on ? Colors.black : studio.text)),
        ),
      ),
    );
  }
}

/// _SplitPicture is a split's sound dividing into [names] and joining
/// again, the [picked] branch bright and a muted one faint; split by
/// frequency, the lows' and highs' curves crossing at [crossover].
class _SplitPicture extends CustomPainter {
  final int mode;
  final List<String> names;
  final List<bool> muted;
  final int? picked;
  final double crossover;
  final Color accent, back;
  _SplitPicture(
      {required this.mode,
      required this.names,
      required this.muted,
      required this.picked,
      required this.crossover,
      required this.accent,
      required this.back});

  static const _colours = [
    Color(0xFFE0A84F),
    Color(0xFF9A92EA),
    Color(0xFF5CC6B8),
    Color(0xFFE57AA8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    void label(String text, double x, double y, Color colour) {
      var tp = TextPainter(
          text: TextSpan(
              text: text, style: TextStyle(fontSize: 9, color: colour)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    }

    if (mode == 3) {
      // The lows' and highs' curves, over 20 Hz to 20 kHz, crossing.
      var xc = math.log(crossover.clamp(20, 20000) / 20) / math.log(1000);
      for (var (k, low) in [true, false].indexed) {
        var p = Path();
        for (var i = 0; i <= 80; i++) {
          var x = i / 80;
          var d = (x - xc) * 9;
          var g = low ? 1 / (1 + math.exp(d)) : 1 / (1 + math.exp(-d));
          var y = h - 6 - g * (h - 16);
          i == 0 ? p.moveTo(x * w, y) : p.lineTo(x * w, y);
        }
        var colour = _colours[k]
            .withValues(alpha: k < muted.length && muted[k] ? 0.3 : 1);
        canvas.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = picked == k ? 2.2 : 1.6
              ..color = colour);
        if (k < names.length) {
          label(names[k], low ? 6 : w - 30, 10, colour);
        }
      }
      canvas.drawLine(Offset(xc * w, 4), Offset(xc * w, h - 4),
          Paint()..color = Colors.white.withValues(alpha: 0.25));
      return;
    }
    var n = math.max(1, names.length);
    for (var i = 0; i < n; i++) {
      var y = names.isEmpty ? h / 2 : (i + 0.5) * h / n;
      var colour = _colours[i % _colours.length]
          .withValues(alpha: i < muted.length && muted[i] ? 0.28 : 1);
      var path = Path()
        ..moveTo(0, h / 2)
        ..cubicTo(w * 0.22, h / 2, w * 0.14, y, w * 0.32, y)
        ..lineTo(w * 0.68, y)
        ..cubicTo(w * 0.86, y, w * 0.78, h / 2, w, h / 2);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = picked == i ? 2.4 : 1.5
            ..color = colour);
      if (i < names.length) label(names[i], w * 0.36, y - 6, colour);
    }
  }

  @override
  bool shouldRepaint(_SplitPicture old) =>
      old.mode != mode ||
      old.picked != picked ||
      old.crossover != crossover ||
      old.names.length != names.length ||
      old.muted.toString() != muted.toString();
}
