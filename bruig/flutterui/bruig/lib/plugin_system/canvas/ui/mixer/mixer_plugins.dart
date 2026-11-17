import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/chain_icons.dart';
import 'package:bruig/plugin_system/canvas/model/strip_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/device_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/pitch_editing.dart';
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
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/automation_lanes.dart'
    show automationColour;
import 'package:bruig/plugin_system/canvas/ui/mixer/autotune_card.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasDropdown, CanvasSwitch;
import 'package:bruig/plugin_system/canvas/ui/mixer/device_screens.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_cards.dart'
    show StudioDrop;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;

part 'mixer_sound_devices.dart';
part 'mixer_midi_devices.dart';
part 'mixer_listeners.dart';
part 'mixer_motion.dart';
part 'mixer_plugins_frame.dart';
part 'mixer_plugins_card_parts.dart';
part 'mixer_plugins_macros.dart';
part 'mixer_plugins_split.dart';
part 'mixer_devices_eq.dart';
part 'mixer_devices_dynamics.dart';
part 'mixer_devices_duck.dart';
part 'mixer_devices_param.dart';
part 'mixer_devices_add.dart';

// mixer_plugins.dart is a strip's effects as devices in a chain, as in
// Ableton, in the order the sound goes through them; each folds to its
// switch, name and a meter. A device keeps its own colours whatever the
// app's theme, as a hardware unit does, and is drawn at deviceHeight and
// scaled to the chain's room, never laid out again.

/// dragPointers may drag a value (fader, dial, knob): mouse, finger, pen;
/// never the trackpad, whose two-finger swipe a recognizer takes as a
/// drag. A trackpad click-and-drag is the mouse's, and still works.
const Set<PointerDeviceKind> dragPointers = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

/// deviceHeight is the height every device is drawn at before scaling.
const double deviceHeight = 320;

const double deviceFoldedWidth = 34;

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

/// DeviceTier is how much a device shows at the chain's height: everything
/// tall, then knobs on one row, then one line of what it is set to.
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

/// ChainPanelStyle draws the cards under it (the Chain's Motion view) in
/// the settings panel's style, so every panel matches: name in a header,
/// settings two or three to a row as steppers and selects, any screen kept
/// small. The Sound view keeps the studio's knobs.
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

/// ChainGroupColour marks the cards under it as one clip's by a line of
/// its colour along their tops, so which preset they belong to is clear.
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

/// midiColour marks what carries notes: MIDI effects, In and instrument.
const midiColour = Color(0xFFD08F3E);

/// deviceGroupLook is a device family's mark: bar icon and top stripe colour.
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

/// deviceMoveButtons are a device bar's arrows moving it along [owner]'s
/// chain, keyed deviceLeft-[index] and deviceRight-[index]; greyed at ends.
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

/// DashedAddButton is a narrow dashed "+" that adds at once on a click.
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

/// chainMenuStyle is a Chain menu: dark, rounded, close-set, fine-edged.
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

/// chainMenuItemStyle is a menu line: small text, lit in the accent on hover.
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

/// chainMenuItem is a Chain menu line: [text], and [hint] small at right.
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

Widget chainMenuHeading(MixerLook look, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 3),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w500,
              color: look.studio.muted)),
    );

Widget chainMenuDivider(MixerLook look) => Divider(
    height: 9, thickness: 1, indent: 2, endIndent: 2, color: look.studio.edge);

/// _Strip reads and writes the mix of one strip, by its channel's key, or
/// the master's with none.
class _Strip {
  final CanvasController controller;
  final String? channel;
  _Strip(this.controller, this.channel);

  TimelineChannel? get _lane => channel == null
      ? null
      : controller.timelineChannels.where((l) => l.key == channel).firstOrNull;

  /// _return is the return this strip is, if it is one.
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

/// _Dragged is a value (a knob, a readout) dragged up and down, 150 px
/// for its whole travel, back to [initial] on a double-click.
class _Dragged extends StatelessWidget {
  final double value;
  final double initial;
  final _Range range;
  final void Function(double v, {bool transient}) onChanged;
  final VoidCallback onCommit;
  final Widget child;

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

/// _Metered is a device window's ticker, rebuilding ~30 times a second.
mixin _Metered<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  void tick();

  CanvasController get meteredBy;

  /// metering is whether it reads the sound at all: a display switched off
  /// does not, and costs nothing. Changed, call [meterAgain].
  bool get metering => true;

  /// meterAgain starts reading again, where [metering] has come on.
  void meterAgain() {
    if (metering) _wake();
  }

  /// Readings move only while there is sound, and a ticker asks for a
  /// frame every refresh, so it rests after 1.5 s of quiet (needles fallen)
  /// and a slow check, with no frames, wakes it.
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
    // A ticker's time restarts from nought each start: the last read, from
    // the run before, would hold every frame back until this run caught up.
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

/// PackWide marks a DevicePack setting that takes the whole row (chips, text).
class PackWide extends StatelessWidget {
  final Widget child;
  const PackWide(this.child, {super.key});

  @override
  Widget build(BuildContext context) => child;
}

/// DevicePack lays a card's settings out as the audio devices do: knobs a
/// cell each, the rest two or three columns across, wrapping, so they take
/// a few short rows and the display above keeps its height.
class DevicePack extends StatelessWidget {
  final List<Widget> children;
  const DevicePack({required this.children, super.key});

  static const double knobWidth = 54, gap = 8;

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
