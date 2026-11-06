import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show MidiMonitor, noInput;
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
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show motionSpeedAt, retimed;
import 'package:bruig/plugin_system/canvas/render/motion_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/automation_lanes.dart'
    show automationColour;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasDropdown;
import 'package:bruig/plugin_system/canvas/ui/device_screens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
const double deviceFoldedWidth = 92;

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
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (controls != null) return _tiered(context);
    var scale = (height / drawnHeight).clamp(0.5, 1.5);
    var w = folded ? deviceFoldedWidth : width;
    var header = Container(
      height: 28,
      color: skin.header,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Tooltip(
          message: folded ? "Open $title" : "Fold $title",
          child: GestureDetector(
            key: ValueKey("deviceFold-$id"),
            behavior: HitTestBehavior.opaque,
            onTap: onFold,
            child: SizedBox(
              width: 20,
              height: 28,
              child: Icon(folded ? Icons.arrow_right : Icons.arrow_drop_down,
                  size: 18, color: headerInk),
            ),
          ),
        ),
        if (on != null) ...[
          _Power(on: on!, onPower: onPower!, powerKey: powerKey),
          const SizedBox(width: 6),
        ],
        if (!folded)
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: headerInk)),
          ),
        if (!folded) ...actions,
      ]),
    );
    var inside = folded
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RotatedBox(
              quarterTurns: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: skin.ink)),
              ),
            ),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                    child: foldedBody)),
          ])
        : body;
    return SizedBox(
      key: ValueKey("device-$id"),
      width: w * scale,
      height: height,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: w,
          height: drawnHeight,
          child: Container(
            decoration: skin.body,
            foregroundDecoration: BoxDecoration(
                border: Border.all(color: Colors.black38),
                borderRadius: BorderRadius.circular(6)),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [header, Expanded(child: inside)]),
            ),
          ),
        ),
      ),
    );
  }

  /// _tiered is the device laid out for [height]: see DeviceTier.
  Widget _tiered(BuildContext context) {
    var tier = DeviceTier.of(height);
    var short = tier == DeviceTier.small || tier == DeviceTier.strip;
    var barHeight = short ? 24.0 : 28.0;
    var w = folded
        ? deviceFoldedWidth
        : tier == DeviceTier.strip
            ? math.min(width, 170.0)
            : width;
    var header = Container(
      height: barHeight,
      color: skin.header,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Tooltip(
          message: folded ? "Open $title" : "Fold $title",
          child: GestureDetector(
            key: ValueKey("deviceFold-$id"),
            behavior: HitTestBehavior.opaque,
            onTap: onFold,
            child: SizedBox(
              width: 20,
              height: barHeight,
              child: Icon(folded ? Icons.arrow_right : Icons.arrow_drop_down,
                  size: 18, color: headerInk),
            ),
          ),
        ),
        if (on != null) ...[
          _Power(on: on!, onPower: onPower!, powerKey: powerKey),
          const SizedBox(width: 6),
        ],
        if (!folded && icon != null && tier != DeviceTier.strip) ...[
          Icon(icon, size: 14, color: accent ?? headerInk),
          const SizedBox(width: 5),
        ],
        if (!folded)
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: short ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: headerInk)),
          ),
        // A strip is too narrow for its buttons: its ⋯ and the chain's
        // arrows are for a taller panel.
        if (!folded && tier != DeviceTier.strip) ...actions,
      ]),
    );
    Widget inside;
    if (folded) {
      inside = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RotatedBox(
          quarterTurns: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: skin.ink)),
          ),
        ),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                child: foldedBody)),
      ]);
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
                color: skin.ink)),
      );
    } else {
      var knobs = controls!(tier);
      var row = tier == DeviceTier.small
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var (i, k) in knobs.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  k,
                ],
              ]),
            )
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: knobs);
      inside = LayoutBuilder(builder: (context, box) {
        // The knobs, as much of them as fits under the display's least;
        // they scroll rather than spill where even that is too much.
        var most = math.max(0.0, box.maxHeight - (display == null ? 0 : 40));
        var below = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: most),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(6, short ? 4 : 8, 6, short ? 4 : 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                row,
                if (tier == DeviceTier.large && footer.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: footer),
                ],
              ]),
            ),
          ),
        );
        return Column(children: [
          if (display != null)
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(7, short ? 5 : 7, 7, 0),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(6), child: display),
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
      child: Container(
        decoration: skin.body,
        foregroundDecoration: BoxDecoration(
            border: Border.all(color: Colors.black38),
            borderRadius: BorderRadius.circular(6)),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            if (accent != null && !folded) Container(height: 2, color: accent),
            header,
            Expanded(child: inside),
          ]),
        ),
      ),
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
        child: GestureDetector(
          key: powerKey,
          onTap: () => onPower(!on),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? const Color(0xFFF0A33C) : const Color(0xFF555B66),
              border: Border.all(color: Colors.black38),
            ),
            child: const Icon(Icons.power_settings_new,
                size: 12, color: Colors.white),
          ),
        ),
      );
}

/// DeviceMove is the pair of arrows on a device that can change places with
/// its neighbour: the EQ and the compressor.
class DeviceMove extends StatelessWidget {
  final bool canLeft, canRight;
  final VoidCallback onSwap;
  final Color ink;
  final String id;

  /// onMove, given, moves it a place along the chain -- minus one to the
  /// left -- rather than swapping it with its neighbour.
  final void Function(int by)? onMove;

  const DeviceMove(
      {required this.id,
      required this.canLeft,
      required this.canRight,
      required this.onSwap,
      required this.ink,
      this.onMove,
      super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var (left, can) in [(true, canLeft), (false, canRight)])
          Tooltip(
            message: left ? "Move earlier in the chain" : "Move later",
            child: GestureDetector(
              key: ValueKey("deviceMove${left ? "Left" : "Right"}-$id"),
              onTap: !can
                  ? null
                  : onMove == null
                      ? onSwap
                      : () => onMove!(left ? -1 : 1),
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

  /// inChain is whether its EQ and compressor have places in a chain with
  /// its devices: a channel's and the master's do; a return's are its
  /// strip's, after its devices, and only change places with each other.
  bool get inChain => _return == null;

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

  bool get compFirst => channel == null
      ? controller.document.masterMix.compFirst
      : _mix?.compFirst ?? false;

  /// swap puts the compressor before the EQ, or back after it.
  void swap() {
    controller.beginInteraction();
    if (channel == null) {
      var m = controller.document.masterMix;
      controller.setMasterMix(m.copyWith(compFirst: !m.compFirst),
          transient: true);
    } else if (_scene) {
      var b = controller.sceneBus;
      controller.setSceneBus(b.copyWith(compFirst: !b.compFirst),
          transient: true);
    } else if (_lane case var lane?) {
      controller.setChannelMix(
          lane, lane.mix.copyWith(compFirst: !lane.mix.compFirst),
          transient: true, anywhere: true);
    } else if (_return case var ret?) {
      controller.setReturn(
          ret.copyWith(mix: ret.mix.copyWith(compFirst: !ret.mix.compFirst)),
          transient: true);
    }
    controller.endInteraction();
  }

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

  const _Dragged({
    required this.value,
    required this.initial,
    required this.range,
    required this.onChanged,
    required this.onCommit,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
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
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((now) {
      if (now - _last < const Duration(milliseconds: 33)) return;
      _last = now;
      if (mounted) setState(tick);
      if (_loud) {
        _quietTicks = 0;
      } else if (++_quietTicks > 45) {
        _ticker.stop();
        _resting ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (_loud) _wake();
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
const _eqPanel = Color(0xFF132233);
const _eqInk = Color(0xFFC9D6E6);

/// _headerInkLight is what reads on a device's dark header bar -- its
/// remove button, which drawn in the body's ink was there but not seen.
const _headerInkLight = Color(0xFFE8EAEE);
const _eqDim = Color(0xFF6E8199);

/// EqDevice is a strip's Channel EQ in the chain -- the master's, with no
/// [channel].
class EqDevice extends StatefulWidget {
  static const width = 780.0;
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
  late final _Strip strip = _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _analyzer is whether what is playing is drawn behind the curve.
  bool _analyzer = true;
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
          var first = !strip.compFirst;
          return DeviceFrame(
            id: "eq",
            title: widget.channel == null ? "Master EQ" : "Channel EQ",
            skin: DeviceSkin.navy,
            on: eq.on,
            powerKey: const ValueKey("eqOn"),
            onPower: (v) => _write(eq.copyWith(on: v)),
            folded: widget.folded,
            onFold: widget.onFold,
            width: EqDevice.width,
            height: widget.height,
            actions: [
              _pill("Analyzer", _analyzer,
                  key: const ValueKey("eqAnalyzer"),
                  onTap: () => setState(() {
                        _analyzer = !_analyzer;
                        _spectrum = null;
                      })),
              const SizedBox(width: 6),
              DeviceMove(
                  id: "eq",
                  canLeft: strip.inChain ? strip.canMove(chainEq).$1 : !first,
                  canRight: strip.inChain ? strip.canMove(chainEq).$2 : first,
                  onSwap: strip.swap,
                  onMove:
                      strip.inChain ? (by) => strip.move(chainEq, by) : null,
                  ink: _eqInk),
            ],
            foldedBody: CustomPaint(
                key: const ValueKey("eqFolded"), painter: _MiniCurve(eq)),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _bandButtons(eq),
                            const SizedBox(height: 6),
                            Expanded(child: _graph(eq)),
                            const SizedBox(height: 6),
                            _readouts(eq),
                          ]),
                    ),
                    const SizedBox(width: 10),
                    _gain(eq),
                  ]),
            ),
          );
        },
      );

  Widget _pill(String label, bool on,
          {required Key key, required VoidCallback onTap}) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF2E6FB0) : const Color(0xFF26364A),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style:
                  TextStyle(fontSize: 11, color: on ? Colors.white : _eqDim)),
        ),
      );

  Widget _bandButtons(Eq eq) => SizedBox(
        height: 34,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var slot in EqSlot.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Tooltip(
                  message: "${slot.label}: "
                      "${eq.band(slot).on ? "on" : "off"}",
                  child: GestureDetector(
                    key: ValueKey("eqBand-${slot.name}"),
                    onTap: () {
                      var b = eq.band(slot);
                      setState(() => _picked = slot);
                      _write(eq
                          .withBand(slot, b.copyWith(on: !b.on))
                          .copyWith(on: true));
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: eq.band(slot).on
                            ? eqBandColour(slot).withValues(alpha: 0.85)
                            : const Color(0xFF1F2E40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: _picked == slot
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
        return Listener(
          // The wheel over a handle is its Q: how wide a bell is, how sharp
          // a cut's corner.
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            var slot = _nearest(eq, e.localPosition, w, h, 18);
            if (slot == null ||
                slot.kind == EqKind.lowShelf ||
                slot.kind == EqKind.highShelf) {
              return;
            }
            var b = eq.band(slot);
            var q =
                (b.q * (e.scrollDelta.dy > 0 ? 0.9 : 1 / 0.9)).clamp(0.1, 10.0);
            _band(slot, b.copyWith(q: q));
          },
          child: GestureDetector(
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
          ),
        );
      });

  Widget _readouts(Eq eq) {
    Widget value(String text, {required Key key, required Color colour}) =>
        Container(
          key: key,
          height: 17,
          alignment: Alignment.center,
          child: Text(text,
              style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: colour)),
        );
    return SizedBox(
      height: 58,
      child: Row(children: [
        for (var slot in EqSlot.values)
          Expanded(
            child: Builder(builder: (context) {
              var b = eq.band(slot);
              var ink = b.on ? _eqInk : _eqDim;
              void set(EqBand next, {bool transient = false}) =>
                  _band(slot, next, transient: transient);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                    color: _eqPanel, borderRadius: BorderRadius.circular(4)),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Dragged(
                        value: b.freq,
                        initial: slot.initial.freq,
                        range: _freq,
                        onChanged: (v, {transient = false}) =>
                            set(b.copyWith(freq: v), transient: transient),
                        onCommit: strip.commit,
                        child: value(_hz(b.freq),
                            key: ValueKey("eqFreq-${slot.name}"), colour: ink),
                      ),
                      if (slot.isCut)
                        // A click steps through the slopes.
                        GestureDetector(
                          onTap: () {
                            var i = eqSlopes.indexOf(b.slope);
                            set(b.copyWith(
                                slope: eqSlopes[(i + 1) % eqSlopes.length]));
                          },
                          child: value("${b.slope} dB/Oct",
                              key: ValueKey("eqSlope-${slot.name}"),
                              colour: ink),
                        )
                      else
                        _Dragged(
                          value: b.gainDb,
                          initial: 0,
                          range: const _Range(-12, 12),
                          onChanged: (v, {transient = false}) => set(
                              b.copyWith(gainDb: (v * 2).roundToDouble() / 2),
                              transient: transient),
                          onCommit: strip.commit,
                          child: value("${_signed(b.gainDb)} dB",
                              key: ValueKey("eqGain-${slot.name}"),
                              colour: ink),
                        ),
                      _Dragged(
                        value: b.q,
                        initial: slot.initial.q,
                        range: const _Range(0.1, 10, log: true),
                        onChanged: (v, {transient = false}) =>
                            set(b.copyWith(q: v), transient: transient),
                        onCommit: strip.commit,
                        child: value("Q ${b.q.toStringAsFixed(2)}",
                            key: ValueKey("eqQ-${slot.name}"), colour: _eqDim),
                      ),
                    ]),
              );
            }),
          ),
      ]),
    );
  }

  /// _gain is the output gain: a slider down the right, as Logic has.
  Widget _gain(Eq eq) => SizedBox(
        width: 56,
        child: Column(children: [
          const Text("Gain", style: TextStyle(fontSize: 11, color: _eqDim)),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              var h = box.maxHeight;
              double at(double dy) => ((0.5 - dy / h) * 24).clamp(-12.0, 12.0);
              return GestureDetector(
                supportedDevices: dragPointers,
                key: const ValueKey("eqOutput"),
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) => _write(
                    eq.copyWith(
                        on: true,
                        gainDb:
                            (at(d.localPosition.dy) * 2).roundToDouble() / 2),
                    transient: true),
                onVerticalDragEnd: (_) => strip.commit(),
                onDoubleTap: () => _write(eq.copyWith(gainDb: 0)),
                child: CustomPaint(
                    size: Size(56, h), painter: _GainSlider(eq.gainDb)),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text("${_signed(eq.gainDb)} dB",
              style: const TextStyle(
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: _eqInk)),
        ]),
      );
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
      old.eq.toJson().toString() != eq.toJson().toString();
}

class _GainSlider extends CustomPainter {
  final double db;
  _GainSlider(this.db);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    var cx = w / 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 3, 0, 6, h), const Radius.circular(3)),
        Paint()..color = const Color(0xFF22354B));
    var y = (0.5 - db / 24) * h;
    canvas.drawLine(Offset(cx - 10, h / 2), Offset(cx + 10, h / 2),
        Paint()..color = _eqDim);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, y), width: 34, height: 14),
            const Radius.circular(3)),
        Paint()..color = const Color(0xFFB8C6D8));
    canvas.drawLine(
        Offset(cx - 12, y),
        Offset(cx + 12, y),
        Paint()
          ..color = const Color(0xFF0D1826)
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_GainSlider old) => old.db != db;
}

// ---- Compressor

const _silverInk = Color(0xFF2B2F36);
const _silverDim = Color(0xFF6A707A);
const _cream = Color(0xFFF1E7C9);

/// CompDevice is a strip's compressor in the chain -- the master's glue,
/// with no [channel].
class CompDevice extends StatefulWidget {
  static const width = 660.0;
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
  late final _Strip strip = _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _graph is whether the display shows the transfer curve rather than the
  /// gain-reduction meter.
  bool _graph = false;
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
          var first = strip.compFirst;
          return DeviceFrame(
            id: "comp",
            title: widget.channel == null ? "Glue" : "Compressor",
            skin: DeviceSkin.silver,
            on: comp.on,
            powerKey: const ValueKey("compOn"),
            onPower: (v) => _write(comp.copyWith(on: v)),
            folded: widget.folded,
            onFold: widget.onFold,
            width: CompDevice.width,
            height: widget.height,
            actions: [
              DeviceMove(
                  id: "comp",
                  canLeft: strip.inChain ? strip.canMove(chainComp).$1 : !first,
                  canRight: strip.inChain ? strip.canMove(chainComp).$2 : first,
                  onSwap: strip.swap,
                  onMove:
                      strip.inChain ? (by) => strip.move(chainComp, by) : null,
                  ink: const Color(0xFFE8EAEE)),
            ],
            // Folded, how much it is taking off.
            foldedBody: Column(children: [
              const Text("GR",
                  style: TextStyle(fontSize: 10, color: _silverDim)),
              const SizedBox(height: 4),
              Expanded(
                child: CustomPaint(
                    key: const ValueKey("compFolded"),
                    size: const Size(14, double.infinity),
                    painter: _ReductionBar(_needle)),
              ),
              const SizedBox(height: 4),
              Text(_needle > 0.05 ? "−${_needle.toStringAsFixed(1)}" : "0",
                  style: const TextStyle(
                      fontSize: 10,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: _silverInk)),
            ]),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _meter("In", _input, const ValueKey("compIn")),
                    const SizedBox(width: 10),
                    SizedBox(width: 290, child: _display(comp)),
                    const SizedBox(width: 12),
                    Expanded(child: _knobs(comp)),
                    const SizedBox(width: 10),
                    _meter("Out", output, const ValueKey("compOut")),
                  ]),
            ),
          );
        },
      );

  Widget _meter(String label, double db, Key key) => SizedBox(
        width: 22,
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _silverDim)),
          const SizedBox(height: 4),
          Expanded(
              child: CustomPaint(
                  key: key, size: Size.infinite, painter: _LedMeter(db))),
          const SizedBox(height: 4),
          Text(db > -60 ? db.round().toString() : "−∞",
              style: const TextStyle(
                  fontSize: 9,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: _silverInk)),
        ]),
      );

  Widget _display(Dynamics comp) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _segment("Meter", !_graph, const ValueKey("compViewMeter"),
              () => setState(() => _graph = false)),
          _segment("Graph", _graph, const ValueKey("compViewGraph"),
              () => setState(() => _graph = true)),
        ]),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _cream,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF8D8F93), width: 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
            child: _graph
                ? CustomPaint(
                    key: const ValueKey("compCurve"),
                    painter: _TransferCurve(comp, _input))
                : CustomPaint(
                    key: const ValueKey("gainReduction"),
                    painter: _VuNeedle(_needle)),
          ),
        ),
        const SizedBox(height: 10),
        const Text("Auto gain",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: _silverDim)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var a in AutoGain.values)
            _segment(
                a.label,
                comp.autoGain == a,
                ValueKey("autoGain-${a.name}"),
                () => _write(comp.copyWith(autoGain: a))),
        ]),
        if (widget.channel != null) ...[
          const SizedBox(height: 6),
          _listensTo(comp),
        ],
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
          dropdownColor: const Color(0xFFE4E6EA),
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

  Widget _segment(String label, bool on, Key key, VoidCallback onTap) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF4A5059) : const Color(0xFFD4D7DC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF9A9EA5)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, color: on ? Colors.white : _silverInk)),
        ),
      );

  Widget _knobs(Dynamics comp) {
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
          size: big ? 66 : 48,
          onChanged: (v, {transient = false}) =>
              _write(apply(v), transient: transient),
          onCommit: strip.commit,
        );
    return Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
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
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
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
      ]),
    ]);
  }
}

/// _Knob is a rotary control: dragged up to turn it right, double-clicked
/// to put it back.
class _Knob extends StatelessWidget {
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
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (automated)
              Container(
                key: const ValueKey("knobAutomated"),
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: held ? const Color(0xFF7D838D) : automationColour),
              ),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent == null ? ink : ink.withValues(alpha: 0.7))),
          ]),
          const SizedBox(height: 4),
          _Dragged(
            value: value,
            initial: initial,
            range: range,
            onChanged: onChanged,
            onCommit: onCommit,
            child: CustomPaint(
                size: Size.square(size),
                painter: _KnobFace(range.toUnit(value),
                    accent: accent, from: bipolar ? range.toUnit(0) : 0)),
          ),
          if (reading) ...[
            const SizedBox(height: 4),
            Text(text,
                style: TextStyle(
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: ink)),
          ],
        ],
      );
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
          ..color = _silverInk);
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
            ..color = _silverInk);
      var tp =
          paintedLabel("$db", const TextStyle(fontSize: 10, color: _silverInk));
      tp.paint(canvas,
          pivot + dir * (radius + 16) - Offset(tp.width / 2, tp.height / 2));
    }
    var tp = paintedLabel("GAIN REDUCTION  dB",
        const TextStyle(fontSize: 9, letterSpacing: 1, color: _silverDim));
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
  _TransferCurve(this.comp, this.input);

  static const _lo = -60.0;

  @override
  void paint(Canvas canvas, Size size) {
    var pad = 14.0;
    var w = size.width - 2 * pad, h = size.height - 2 * pad;
    double px(double db) => pad + (db - _lo) / -_lo * w;
    double py(double db) => pad + h - ((db - _lo) / -_lo).clamp(0.0, 1.0) * h;
    var grid = Paint()..color = const Color(0xFFD3C7A4);
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
          ..color = comp.on ? _silverInk : _silverDim);
    if (input > _lo) {
      var out = comp.on ? comp.reducedDb(input) + comp.totalMakeupDb : input;
      canvas.drawCircle(Offset(px(input), py(out)), 5,
          Paint()..color = const Color(0xFFE08A1E));
    }
  }

  @override
  bool shouldRepaint(_TransferCurve old) =>
      old.input != input ||
      old.comp.toJson().toString() != comp.toJson().toString();
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
      old.eq.toJson().toString() != eq.toJson().toString();
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
  late final _Strip strip = _Strip(widget.controller, widget.channel);

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
          for (var (side, db) in [("L", _now.$1), ("R", _now.$2)]) ...[
            SizedBox(
              width: width,
              child: CustomPaint(
                  key: ValueKey("meter$side-${widget.id}"),
                  size: Size.infinite,
                  painter: _LedMeter(db)),
            ),
            const SizedBox(width: 4),
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
      foldedBody: pair(12),
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

/// LimiterDevice is the master's limiter: on or off, and its ceiling.
class LimiterDevice extends StatelessWidget {
  static const width = 220.0;
  final CanvasController controller;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const LimiterDevice(
      {required this.controller,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  void _write(MasterMix m, {bool transient = false}) {
    controller.beginInteraction();
    controller.setMasterMix(m, transient: true);
    if (!transient) controller.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var m = controller.document.masterMix;
    var reading = "${m.ceilingDb.toStringAsFixed(1)} dBTP";
    return DeviceFrame(
      id: "limiter",
      title: "Limiter",
      skin: DeviceSkin.silver,
      on: m.limiter,
      powerKey: const ValueKey("limitOn"),
      onPower: (v) => _write(m.copyWith(limiter: v)),
      folded: folded,
      onFold: onFold,
      width: width,
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(reading,
              style: const TextStyle(fontSize: 11, color: _silverInk)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          const Spacer(),
          _Knob(
            key: const ValueKey("limitCeiling"),
            label: "Ceiling",
            text: reading,
            value: m.ceilingDb,
            initial: -1,
            range: const _Range(-12, 0),
            size: 76,
            onChanged: (v, {transient = false}) => _write(
                m.copyWith(ceilingDb: (v * 10).roundToDouble() / 10),
                transient: transient),
            onCommit: controller.endInteraction,
          ),
          const Spacer(),
          const Text(
              "Last in the chain: no peak gets past the ceiling, in "
              "playing or in an export.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: _silverDim)),
        ]),
      ),
    );
  }
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
  late final _Strip strip = _Strip(widget.controller, widget.channel);

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
            skin: DeviceSkin.silver,
            on: duck.on,
            powerKey: const ValueKey("duckOn"),
            onPower: (v) => write(duck.copyWith(on: v)),
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
                    SizedBox(
                      width: 22,
                      child: Column(children: [
                        const Text("Now",
                            style: TextStyle(fontSize: 10, color: _silverDim)),
                        const SizedBox(height: 4),
                        Expanded(
                            child: CustomPaint(
                                key: const ValueKey("duckNow"),
                                size: Size.infinite,
                                painter: _ReductionBar(_now))),
                        const SizedBox(height: 4),
                        Text(_now > 0.05 ? "−${_now.toStringAsFixed(1)}" : "0",
                            style: const TextStyle(
                                fontSize: 9,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: _silverInk)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _controls(duck, write)),
                  ]),
            ),
          );
        },
      );

  Widget _segment(String label, bool on, Key key, VoidCallback onTap) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF4A5059) : const Color(0xFFD4D7DC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF9A9EA5)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, color: on ? Colors.white : _silverInk)),
        ),
      );

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
            skin: DeviceSkin.silver,
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
                            SizedBox(
                              width: 22,
                              child: Column(children: [
                                const Text("Now",
                                    style: TextStyle(
                                        fontSize: 10, color: _silverDim)),
                                const SizedBox(height: 4),
                                Expanded(
                                    child: CustomPaint(
                                        key: const ValueKey("duckedNow"),
                                        size: Size.infinite,
                                        painter: _ReductionBar(_now))),
                                const SizedBox(height: 4),
                                Text(
                                    _now > 0.05
                                        ? "−${_now.toStringAsFixed(1)}"
                                        : "0",
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontFeatures: [
                                          FontFeature.tabularFigures()
                                        ],
                                        color: _silverInk)),
                              ]),
                            ),
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
          ..color = _silverInk);
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
            text: name, style: const TextStyle(fontSize: 9, color: _silverDim)),
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
          ..color = duck.on ? _silverInk : _silverDim);
  }

  @override
  bool shouldRepaint(_DuckShape old) =>
      old.name != name ||
      old.duck.toJson().toString() != duck.toJson().toString();
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
    String target(DeviceParam p) => AutomationTarget.deviceSetting(
            deviceIdAt(devices, index), device.kind, p.id)
        .id;
    var (icon, accent) = deviceGroupLook(device.kind.group);
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    // Only a channel's strip measures between its devices: see
    // CanvasController.deviceLevels.
    var isChannel = controller.timelineChannels.any((c) => c.key == owner);
    List<Widget> knobs(DeviceTier tier) => [
          for (var p in params)
            if (paramShown(device, p))
              _Knob(
                key: ValueKey("device-$index-${p.id}"),
                automated: automated.contains(target(p)),
                held: held.contains(target(p)),
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
          if (device.kind == DeviceKind.vocoder &&
              device.value("carrier").round() == carrierFromChannel)
            _sourceChannel(context, device, write),
          // A gate opens to its own sound, or to another channel's.
          if (device.kind == DeviceKind.gate)
            _sourceChannel(context, device, write, itself: true),
        ];
    return DeviceFrame(
      id: deviceKey(deviceIdAt(devices, index)),
      title: device.kind.label,
      skin: skin,
      on: device.on,
      onPower: (v) => write(device.switched(v)),
      powerKey: ValueKey("devicePower-$index"),
      folded: folded,
      onFold: onFold,
      width: math.max(220.0, 24.0 + 72 * columns),
      height: height,
      actions: [
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
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(device.kind.label,
              style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
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
      display: DeviceLevels(
          key: ValueKey("deviceLevels-$index"),
          controller: controller,
          channel: isChannel ? owner : null,
          // Its place in the chain, where its levels are read: the EQ and
          // compressor can be before it.
          index: controller.chainOf(owner).indexOf(deviceIdAt(devices, index)),
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

/// AddDeviceSlot is the end of a strip's chain -- a return's, or a
/// channel's -- listing every kind of device that can be put on it, by
/// group, to add one.
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
    var look = MixerLook.of(context);
    // Shut nearly flat, as the effects are opened or shut: too short for
    // its title, it is only its place.
    if (height < 48) return SizedBox(width: 124, height: height);
    return Container(
      width: 124,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: look.studio.edge),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text("Add a device",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: look.studio.muted)),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            for (var group in DeviceGroup.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
                child: Text(group.label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: look.studio.muted)),
              ),
              for (var kind in DeviceKind.values)
                if (kind.group == group)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: OutlinedButton(
                      key: ValueKey("addDevice-${kind.name}"),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: look.studio.text,
                          side: BorderSide(color: look.studio.edge),
                          textStyle: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        var now = controller.devicesOf(owner);
                        controller.beginInteraction();
                        controller
                            .setDevicesOf(owner, [...now, MixDevice(kind)]);
                        controller.endInteraction();
                        controller.openEffects(owner,
                            device: deviceKey(deviceIdAt(
                                controller.devicesOf(owner), now.length)));
                      },
                      child: Text(kind.label),
                    ),
                  ),
            ],
          ]),
        ),
      ]),
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
      title: "In",
      skin: skin,
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
    var columns = (params.length + 1) ~/ 2;
    return DeviceFrame(
      id: "midi$index",
      title: effect.kind.label,
      skin: DeviceSkin.silver,
      on: effect.on,
      onPower: (v) => write(effect.switched(v)),
      powerKey: ValueKey("midiPower-$index"),
      folded: folded,
      onFold: onFold,
      width: 24.0 + 80 * columns,
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
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(effect.kind.label,
              style: const TextStyle(fontSize: 11, color: _silverInk)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var p in params)
              _Knob(
                key: ValueKey("midi-$index-${p.id}"),
                label: p.label,
                text: p.reading(effect.value(p.id)),
                value: effect.value(p.id),
                initial: p.initial,
                range: _Range(p.min, p.max),
                size: 46,
                onChanged: (v, {transient = false}) =>
                    write(effect.withValue(p.id, v), transient: transient),
                onCommit: controller.endInteraction,
              ),
          ],
        ),
      ),
    );
  }
}

/// AddMidiEffectSlot puts a MIDI effect on a MIDI channel, after the
/// others, before its instrument.
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
    var look = MixerLook.of(context);
    return Container(
      width: 112,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: look.studio.edge),
      ),
      padding: const EdgeInsets.all(8),
      // Shrunk to a short panel, as the devices beside it are: a button
      // for each MIDI effect is taller than the panel at its shortest.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("MIDI effects",
              style: TextStyle(fontSize: 11, color: look.studio.muted)),
          const SizedBox(height: 6),
          for (var kind in MidiEffectKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: OutlinedButton(
                key: ValueKey("addMidi-${kind.name}"),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: look.studio.text,
                    side: BorderSide(color: look.studio.edge),
                    textStyle: const TextStyle(fontSize: 11)),
                onPressed: () {
                  controller.beginInteraction();
                  controller.setChannelPart(
                      channel,
                      (p) => p
                          .copyWith(effects: [...p.effects, MidiEffect(kind)]));
                  controller.endInteraction();
                  controller.openEffects(channel,
                      device:
                          "midi${controller.instrumentOf(channel)!.instrument!.effects.length - 1}");
                },
                child: Text(kind.label),
              ),
            ),
        ]),
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
  // What it shows is read in build: a tick only asks for it again.
  @override
  void tick() {}

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
    return DeviceFrame(
      id: deviceKey(deviceIdAt(devices, widget.index)),
      title: device.kind.label,
      skin: skin,
      // Its screen is all of it: it only listens.
      display: body,
      controls: (_) => const [],
      summary: summary,
      icon: icon,
      accent: accent,
      on: device.on,
      onPower: (v) => write(device.switched(v)),
      powerKey: ValueKey("devicePower-${widget.index}"),
      folded: widget.folded,
      onFold: widget.onFold,
      width: tuner ? 220 : 360,
      height: widget.height,
      actions: [
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
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(device.kind.label,
              style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
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

  /// device is what it draws: see hasScreen.
  final MixDevice? device;
  final Color accent;

  /// back is the display's background: the studio palette's Display.
  final Color back;
  const DeviceLevels(
      {required this.controller,
      required this.channel,
      required this.index,
      required this.accent,
      this.device,
      this.back = const Color(0xFF110F22),
      super.key});

  @override
  State<DeviceLevels> createState() => _DeviceLevelsState();
}

class _DeviceLevelsState extends State<DeviceLevels>
    with SingleTickerProviderStateMixin, _Metered {
  /// _history is the last few seconds of (in, out), in decibels, oldest
  /// first.
  final List<(double, double)> _history = [];
  static const int _length = 120;

  @override
  CanvasController get meteredBy => widget.controller;

  /// _t is how long it has been moving, for a screen's LFO.
  double _t = 0;

  @override
  void tick() {
    _t += 0.033;
    var channel = widget.channel;
    if (channel == null) return;
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
      var last = _history.lastOrNull;
      var sounding = last != null && last.$1 > -80 && last.$2 > -80;
      return CustomPaint(
        painter: DeviceScreenPainter(
            device,
            ScreenMoment(
                t: _t,
                live: widget.controller.playing,
                level: last == null
                    ? 0
                    : ((last.$1 + 60) / 60).clamp(0.0, 1.0).toDouble(),
                change: sounding ? last.$2 - last.$1 : null),
            widget.accent,
            widget.back),
        child: const SizedBox.expand(),
      );
    }
    return CustomPaint(
      painter: _LevelsPainter(
          List.of(_history), _length, widget.accent, widget.back),
      child: const SizedBox.expand(),
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
    var accent = pose ? const Color(0xFF6FA8FF) : const Color(0xFFE59BFF);
    List<Widget> knobs(DeviceTier tier) => [
          for (var p in d.kind.params)
            _Knob(
              key: ValueKey("mdev-${d.id}-${p.id}"),
              label: p.label,
              text: p.reading(d.value(p.id)),
              value: d.value(p.id),
              initial: p.initial,
              range: _Range(p.min, p.max),
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
                  write(d.withValue(p.id, v), transient: transient),
              onCommit: controller.endInteraction,
            ),
          // What it follows, or looks at.
          if (d.takesTarget)
            CanvasDropdown<String>(
              key: ValueKey("mdevTarget-${d.id}"),
              label: switch (d.kind) {
                MotionDeviceKind.followPath => "Path",
                MotionDeviceKind.followSound => "Channel",
                _ => "Looks at",
              },
              value: d.target,
              width: 140,
              grow: false,
              options: [
                ("", "Nothing"),
                // A sound follows a channel's loudness.
                if (d.kind == MotionDeviceKind.followSound)
                  for (var ch in controller.timelineChannels) (ch.key, ch.name)
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
      skin: skin,
      on: d.on,
      onPower: (v) => write(d.switched(v)),
      powerKey: ValueKey("mdevPower-${d.id}"),
      folded: folded,
      onFold: onFold,
      width: math.max(220.0, 30.0 + 72 * ((d.kind.params.length + 2) ~/ 2)),
      height: height,
      icon: pose ? Icons.timer_outlined : Icons.auto_awesome,
      accent: accent,
      actions: [
        DeviceMove(
            id: "mdev-${d.id}",
            canLeft: at > 0,
            canRight: at < side.length - 1,
            onSwap: () {},
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
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(d.kind.label,
              style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
      body: const SizedBox.shrink(),
      controls: knobs,
      // A screen where there is something to show without the element:
      // a look on a square, Time's curve, a wave's shape.
      display: d.side == MotionDeviceSide.look ||
              d.kind == MotionDeviceKind.time ||
              d.kind == MotionDeviceKind.wiggle ||
              d.kind == MotionDeviceKind.oscillate
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

  @override
  bool shouldRepaint(_MotionScreen old) =>
      old.device != device || old.back != back || old.accent != accent;
}

/// DrawingCard is the element itself in its motion chain: what its pose
/// devices move, and its looks are laid on. It has no settings of its own
/// here; it marks the drawing between the two sides.
class DrawingCard extends StatelessWidget {
  final String name;
  final double height;
  const DrawingCard({required this.name, required this.height, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return Container(
      key: const ValueKey("drawingCard"),
      width: 92,
      height: height,
      decoration: BoxDecoration(
        color: look.studio.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: look.studio.edge),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.draw_outlined, size: 22, color: look.studio.text),
        const SizedBox(height: 6),
        Text("Drawing",
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: look.studio.text)),
        const SizedBox(height: 2),
        Text(name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: look.studio.muted)),
      ]),
    );
  }
}

/// AddMotionDeviceSlot is the end of one side of an element's motion
/// chain: the kinds that side takes (rule 1), to put one on.
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
    var look = MixerLook.of(context);
    var pose = side == MotionDeviceSide.pose;
    return Container(
      width: 132,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: look.studio.edge),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(pose ? "Add a move" : "Add a look",
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: look.studio.text)),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(children: [
            for (var k in MotionDeviceKind.on(side))
              InkWell(
                key: ValueKey("addMotion-${k.name}"),
                onTap: () {
                  controller.beginInteraction();
                  controller.addMotionDevice(element, k);
                  controller.endInteraction();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                  child: Row(children: [
                    Icon(Icons.add, size: 13, color: look.studio.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(k.label,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 11, color: look.studio.text)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
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
                size: 11, color: on ? look.colors.primary : look.studio.muted),
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
    );
  }
}

/// InstancesCard is an element's Instances, first of its moves unless moved:
/// "1 · this one" and a way to reuse it, or its instances -- how many, how
/// they are laid out, and what differs between them, each by order, at
/// random or from the middle (rule 3: from here on, each has its own).
class InstancesCard extends StatelessWidget {
  final CanvasController controller;
  final String element;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  /// canLeft and canRight are whether it can move among the moves.
  final bool canLeft, canRight;

  const InstancesCard({
    required this.controller,
    required this.element,
    required this.folded,
    required this.onFold,
    required this.height,
    this.canLeft = false,
    this.canRight = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var set = controller.motionOf(element).instances;
    const accent = Color(0xFF6FA8FF);
    var ink = TextStyle(fontSize: 11, color: skin.ink);
    Widget button(String key, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.all(2),
          child: OutlinedButton(
            key: ValueKey(key),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: skin.ink,
                side: BorderSide(color: look.studio.edge)),
            onPressed: onTap,
            child: Text(label, style: ink),
          ),
        );
    void write(InstanceSet next, {bool transient = false}) {
      controller.beginInteraction();
      controller.setInstances(element, next, transient: true);
      if (!transient) controller.endInteraction();
    }

    List<Widget> controls(DeviceTier tier) {
      if (set == null) {
        return [
          Text("1 · this one", style: ink),
          button("instancesReuse", "Reuse…", () {
            controller.beginInteraction();
            controller.reuseElement(element, 5);
            controller.endInteraction();
          }),
        ];
      }
      return [
        // How many.
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              key: const ValueKey("instancesLess"),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.remove, color: skin.ink),
              onPressed: set.count <= 1
                  ? null
                  : () {
                      controller.beginInteraction();
                      controller.reuseElement(element, set.count - 1);
                      controller.endInteraction();
                    }),
          Text("×${set.count}",
              key: const ValueKey("instancesCount"),
              style: ink.copyWith(fontWeight: FontWeight.w700)),
          IconButton(
              key: const ValueKey("instancesMore"),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.add, color: skin.ink),
              onPressed: set.count >= maxInstances
                  ? null
                  : () {
                      controller.beginInteraction();
                      controller.reuseElement(element, set.count + 1);
                      controller.endInteraction();
                    }),
        ]),
        // Laid out afresh: a choice that does something, so it shows none.
        CanvasDropdown<InstanceLayout?>(
          key: const ValueKey("instancesLayout"),
          label: "Lay out",
          value: null,
          width: 120,
          grow: false,
          options: [
            (null, "Lay out…"),
            for (var l in InstanceLayout.values) (l, l.label),
          ],
          onChanged: (l) {
            if (l == null) return;
            controller.beginInteraction();
            controller.layOutInstances(element, l);
            controller.endInteraction();
          },
        ),
        // What differs between them.
        for (var w in VaryWhat.values)
          _VaryRow(
            what: w,
            vary: set.varyOf(w),
            ink: skin.ink,
            accent: accent,
            tier: tier,
            onChanged: (v, {transient = false}) =>
                write(set.withVary(w, v), transient: transient),
            onCommit: controller.endInteraction,
          ),
        if (set.vary.values.any((v) => v.how == VaryHow.random))
          button("instancesReroll", "Re-roll",
              () => write(set.copyWith(seed: set.seed + 1))),
        button("instancesOnce", "Place once", () {
          controller.beginInteraction();
          controller.setInstances(element, null);
          controller.endInteraction();
        }),
      ];
    }

    var varied = set == null
        ? 0
        : VaryWhat.values
            .where((w) => set.varyOf(w).how != VaryHow.same)
            .length;
    return DeviceFrame(
      id: "instances",
      title: set == null ? "Instances" : "Instances ×${set.count}",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: set == null ? 220 : 420,
      height: height,
      icon: Icons.copy_all_outlined,
      accent: accent,
      actions: [
        if (set != null)
          DeviceMove(
              id: "instances",
              canLeft: canLeft,
              canRight: canRight,
              onSwap: () {},
              onMove: (by) => controller.moveInstances(element, by),
              ink: _headerInkLight),
      ],
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(set == null ? "Placed once" : "×${set.count}",
              style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
      body: const SizedBox.shrink(),
      controls: controls,
      summary: set == null
          ? "placed once"
          : "×${set.count}${varied == 0 ? " · alike" : " · $varied vary"}",
    );
  }
}

/// _VaryRow is one setting that can differ between instances: how, and by
/// at most how much.
class _VaryRow extends StatelessWidget {
  final VaryWhat what;
  final Vary vary;
  final Color ink, accent;
  final DeviceTier tier;
  final void Function(Vary v, {bool transient}) onChanged;
  final VoidCallback onCommit;
  const _VaryRow(
      {required this.what,
      required this.vary,
      required this.ink,
      required this.accent,
      required this.tier,
      required this.onChanged,
      required this.onCommit});

  String _reading(double v) => switch (what.unit) {
        "s" => "${v.toStringAsFixed(2)} s",
        "°" => "${v.round()}°",
        _ => "${v >= 0 ? "+" : "−"}${(v.abs() * 100).round()}%",
      };

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      CanvasDropdown<VaryHow>(
        key: ValueKey("vary-${what.name}"),
        label: what.label,
        value: vary.how,
        width: 120,
        grow: false,
        options: [for (var h in VaryHow.values) (h, h.label)],
        onChanged: (h) => onChanged(Vary(h, vary.amount)),
      ),
      if (vary.how != VaryHow.same)
        _Knob(
          key: ValueKey("vary-${what.name}-amount"),
          label: "",
          text: _reading(vary.amount),
          value: vary.amount,
          initial: what.initial,
          range: _Range(what.min, what.max),
          size: tier == DeviceTier.large ? 34 : 26,
          reading: tier != DeviceTier.small,
          accent: accent,
          ink: ink,
          bipolar: what.min < 0,
          onChanged: (v, {transient = false}) =>
              onChanged(Vary(vary.how, v), transient: transient),
          onCommit: onCommit,
        ),
    ]);
  }
}
