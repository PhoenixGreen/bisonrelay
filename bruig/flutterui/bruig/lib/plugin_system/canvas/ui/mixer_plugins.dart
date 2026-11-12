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
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show KeyDiamond;
import 'package:bruig/plugin_system/canvas/model/text_looks.dart' show textLayerChoices;
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
    show CanvasDropdown, CanvasSwitch;
import 'package:bruig/plugin_system/canvas/ui/device_screens.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;

part 'mixer_sound_devices.dart';
part 'mixer_midi_devices.dart';
part 'mixer_listeners.dart';
part 'mixer_motion.dart';

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

/// ChainPanelStyle draws the cards under it -- the Chain's Motion view --
/// in the settings panel's style, as the approved chain prototype has them
/// (Ken, 2026-11-12: "the design differs between panels"): a plain card
/// with its name in a header, its settings two or three to a row as
/// steppers and selects, and any screen kept small over them. The Sound
/// view keeps the studio's knobs.
class ChainPanelStyle extends InheritedWidget {
  const ChainPanelStyle({required super.child, super.key});

  static bool on(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChainPanelStyle>() != null;

  @override
  bool updateShouldNotify(ChainPanelStyle oldWidget) => false;
}

/// paramStep is how far a setting's arrows move it in ChainPanelStyle: a
/// pixel, a degree, a whole number, a hundredth of a share -- rather than
/// a fiftieth of a travel thousands of pixels long.
double? paramStep(DeviceParam p) {
  if (p.isChoice) return null;
  if (p.id == "weight") return 100;
  return switch (p.unit) {
    "px" || "°" || "#" => 1,
    "" => 0.01,
    "×" || "s" => 0.05,
    "/s" || "Hz" => 0.01,
    _ => null,
  };
}

/// ChainGroupColour marks the cards under it as one clip's -- its style,
/// timing, launch, place and what it plays -- by a line of the clip's
/// colour along their tops (Ken, 2026-11-12: which preset they belong to
/// was not clear).
class ChainGroupColour extends InheritedWidget {
  final Color colour;
  const ChainGroupColour({required this.colour, required super.child, super.key});

  static Color? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChainGroupColour>()
      ?.colour;

  @override
  bool updateShouldNotify(ChainGroupColour oldWidget) =>
      oldWidget.colour != colour;
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
            Flexible(
              child: Text("Add a knob to turn",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: studio.text)),
            ),
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
            // Onto more rows where it is narrower than all of them (Ken's
            // log: 278 pixels past a 170-wide card).
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                children: [
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
                    // Its add button under its name where the card is
                    // narrow.
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text("MACRO ${picked + 1} TURNS",
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w600,
                                  color: studio.muted)),
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

  /// Hidden from the Chain's ⋯, it reads nothing.
  @override
  bool get metering => widget.controller.chainBadges;

  @override
  void didUpdateWidget(_GainBadge old) {
    super.didUpdateWidget(old);
    meterAgain();
  }

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

  /// name tells it from the other joins in its keys: by default how many
  /// effects are before it.
  final String? name;
  const NoteJoin(
      {super.key,
      required this.controller,
      required this.channel,
      required this.upto,
      required this.height,
      this.name});

  @override
  State<NoteJoin> createState() => _NoteJoinState();
}

class _NoteJoinState extends State<NoteJoin>
    with SingleTickerProviderStateMixin, _Metered {
  int _notes = 0;

  @override
  CanvasController get meteredBy => widget.controller;

  /// Hidden from the Chain's ⋯, it reads nothing.
  @override
  bool get metering => widget.controller.chainMeters;

  @override
  void didUpdateWidget(NoteJoin old) {
    super.didUpdateWidget(old);
    meterAgain();
  }

  // Counted again as keys go down and up -- live keys sound nothing a
  // meter would wake for -- and once to begin with.
  @override
  void initState() {
    super.initState();
    tick();
    widget.controller.keysHeld.addListener(_keys);
  }

  void _keys() {
    if (mounted && metering) setState(tick);
  }

  @override
  void dispose() {
    widget.controller.keysHeld.removeListener(_keys);
    super.dispose();
  }

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
    var studio = MixerLook.of(context).studio;
    const dots = 6;
    return Tooltip(
      message: _notes == 0
          ? "No notes passing"
          : "$_notes note${_notes == 1 ? "" : "s"} passing",
      child: SizedBox(
        key: ValueKey("noteJoin-${widget.name ?? widget.upto}"),
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

  /// lead is what comes first on the card, over its screen: what the rest
  /// of it is about (the Motion clips card's own arrival, loop and leaving).
  final List<Widget> lead;

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
    this.lead = const [],
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
    var barHeight = ChainPanelStyle.on(context)
        ? 40.0
        : tier == DeviceTier.small || tier == DeviceTier.strip
            ? 24.0
            : 28.0;
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
    if (ChainPanelStyle.on(context)) {
      // As the settings panel's cards: plain, a line round it, its
      // settings faded while it is switched off.
      var group = ChainGroupColour.of(context);
      return Container(
        decoration: BoxDecoration(
          color: studio.strip,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: studio.edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            if (group != null)
              Container(
                  key: const ValueKey("chainGroupLine"),
                  height: 3,
                  color: group),
            header,
            Expanded(
                child: IgnorePointer(
                    ignoring: frozen,
                    child: Opacity(opacity: off ? 0.5 : 1, child: inside))),
          ]),
        ),
      );
    }
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

  /// _inMenu is whether [w] goes behind the bar's ⋯ rather than on it: the
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
    var panel = ChainPanelStyle.on(context);
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
      padding: panel
          ? const EdgeInsets.fromLTRB(10, 0, 4, 0)
          : const EdgeInsets.fromLTRB(8, 0, 2, 0),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: studio.edge.withValues(alpha: 0.7)))),
      child: Row(children: [
        if (on != null) ...[
          _Power(on: on!, onPower: onPower!, powerKey: powerKey),
          const SizedBox(width: 7),
        ],
        if (icon != null && full && !panel) ...[
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
              child: Text(panel ? _titled(title) : title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: panel ? 13 : 10.5,
                      letterSpacing: panel ? 0 : 0.6,
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

  /// _isCell is whether [w] takes a cell of a ChainPanelStyle card: a knob,
  /// alone or with its key's diamond on its corner.
  static bool _isCell(Widget w) =>
      _isKnob(w) ||
      (w is Stack && w.children.isNotEmpty && _isKnob(w.children.first));

  /// _besideDisplay is how wide a short card's display is, beside its
  /// knobs.
  static const double _besideDisplay = 170;

  /// _titled is a card's name as the settings panel writes one: its first
  /// letter a capital, the rest as given ("MOTION CLIPS" -> "Motion clips").
  static String _titled(String t) {
    if (t.isEmpty || t != t.toUpperCase()) return t;
    var lower = t.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  /// _panelLaid is the device in ChainPanelStyle: its screen, kept small,
  /// over its settings, two or three to a row -- the knobs as steppers,
  /// each a cell; anything else a row of its own.
  Widget _panelLaid(BuildContext context) {
    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var tier = DeviceTier.of(height);
    var items = folded
        ? const <Widget>[]
        : controls!(tier == DeviceTier.strip ? DeviceTier.small : tier);
    var leading = folded ? const <Widget>[] : lead;
    var cells = items.where(_isCell).length;
    var columns = cells > 4 ? 3 : 2;
    var cell = 104.0 * scale;
    // A list (its copies, its parts) keeps a column of its own beside the
    // settings, its full height: it is used, not looked at.
    var list = displayBeside && display != null && !folded;
    var listWidth = list ? (besideDisplay ?? 220.0) : 0.0;
    var w = folded
        ? deviceFoldedWidth
        : math.max(math.max(236.0 * scale, width),
                22 + columns * cell + (columns - 1) * 8) +
            (list ? listWidth + 8 : 0);
    var header = _bar(context, height: 40, short: false, full: true, cardWidth: w);
    Widget inside;
    if (folded) {
      inside = _foldedInside(context);
    } else {
      var studio = MixerLook.of(context).studio;
      var room = w - 22 - (list ? listWidth + 8 : 0);
      var each = ((room - (columns - 1) * 8) / columns).floorToDouble();
      inside = LayoutBuilder(builder: (context, box) {
        var settings = SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var k in items)
              SizedBox(width: _isCell(k) ? each : room, child: k),
          ]),
        );
        if (list) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
              child: SizedBox(
                width: listWidth,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: studio.edge),
                  ),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(6), child: display),
                ),
              ),
            ),
            Expanded(child: settings),
          ]);
        }
        var screen = display == null
            ? null
            : SizedBox(
                height: math.min(96.0, box.maxHeight * 0.35),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: studio.edge),
                  ),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(6), child: display),
                ),
              );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var w in leading) ...[w, const SizedBox(height: 8)],
                if (screen != null) ...[screen, const SizedBox(height: 8)],
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var k in items)
                    SizedBox(width: _isCell(k) ? each : room, child: k),
                ]),
                if (footer.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: footer),
                ],
              ]),
        );
      });
    }
    return SizedBox(
      key: ValueKey("device-$id"),
      width: w,
      height: height,
      child: _card(context, header, inside),
    );
  }

  /// _tiered is the device laid out for [height]: see DeviceTier.
  Widget _tiered(BuildContext context) {
    if (ChainPanelStyle.on(context)) return _panelLaid(context);
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
      var knobs = [...lead, ...controls!(tier)];
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
  Widget build(BuildContext context) => ChainPanelStyle.on(context)
      ? Padding(
          padding: const EdgeInsets.only(right: 1),
          child: CanvasSwitch(key: powerKey, value: on, onChanged: onPower))
      : Tooltip(
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
        // In ChainPanelStyle a knob is a stepper: a cell as the rest are.
        var panel = ChainPanelStyle.on(context);
        return Wrap(spacing: gap, runSpacing: panel ? 8 : 7, children: [
          for (var w in children)
            SizedBox(
                width: w is PackWide
                    ? room
                    : DeviceFrame._isKnob(w) && !panel
                        ? knobWidth * scale
                        : cell,
                child: w),
        ]);
      });
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
      var tp = paintedLabel(text, TextStyle(fontSize: 9, color: colour));
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
