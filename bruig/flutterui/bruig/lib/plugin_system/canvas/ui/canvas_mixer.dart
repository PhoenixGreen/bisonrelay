import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart'
    show ChannelNameEditor;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// canvas_mixer.dart is the mixer: a strip for each sound on the timeline and
// a master strip, floated over the canvas from a button at the end of the
// timeline -- see CanvasTimeline -- and resized by the grip along its top.
//
// A strip, top to bottom: its name; its EQ, drawn as the curve in miniature;
// its compressor; its balance; mute and solo; a fader beside a meter; and the
// fader's reading. Clicking the EQ or the compressor opens that strip's
// editor in the panel, and back returns to the strips.
//
// Everything a strip sets is saved with the clip it belongs to, except solo,
// which is for listening -- see CanvasController.solo. What it sets is
// defined in mix.dart, in terms the editor and an export both follow.

/// mixerMinHeight and mixerMaxFraction bound the panel's height, which the
/// screen keeps.
///
/// Under mixerCompactBelow the strips give way to one line of meters, which
/// is as short as it goes.
const double mixerMinHeight = 56;
const double mixerCompactBelow = 260;
const double mixerDefaultHeight = 320;

/// effectsMinHeight and effectsDefaultHeight are the effects panel's: the
/// devices are scaled to it, down to half their size.
const double effectsMinHeight = 200;
const double effectsDefaultHeight = 340;

class CanvasMixer extends StatefulWidget {
  final CanvasController controller;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;

  /// resizable is whether it has a grip along its top to be dragged taller
  /// by. Not where its top is pinned -- the effects over the mixer with the
  /// canvas put away, where the line between the two is the mixer's grip.
  final bool resizable;

  /// only is the one channel to show beside the master, by key, or null for
  /// every channel. With [embedded], the mixer is a section of a sound's
  /// settings rather than the panel over the canvas: no grip, no close.
  final String? only;
  final bool embedded;

  /// effects makes this the effects panel: the chain of one strip --
  /// controller.effectsOf -- in a panel of its own, rather than the strips.
  final bool effects;

  const CanvasMixer({
    required this.controller,
    required this.height,
    required this.onResize,
    required this.onClose,
    this.only,
    this.embedded = false,
    this.resizable = true,
    super.key,
  }) : effects = false;

  /// CanvasMixer.effects is the effects panel: one strip's chain, over the
  /// mixer, opened from the timeline or from a strip's slot.
  const CanvasMixer.effects({
    required this.controller,
    required this.height,
    required this.onResize,
    required this.onClose,
    this.resizable = true,
    super.key,
  })  : only = null,
        embedded = false,
        effects = true;

  /// CanvasMixer.section is the mixer as a section of a sound's settings:
  /// that sound's channel and the master, the effects opening in place.
  const CanvasMixer.section({
    required this.controller,
    required String channel,
    this.height = 330,
    super.key,
  })  : only = channel,
        embedded = true,
        effects = false,
        resizable = false,
        onResize = _ignore,
        onClose = _nothing;

  static void _ignore(double _) {}
  static void _nothing() {}

  @override
  State<CanvasMixer> createState() => _CanvasMixerState();
}

/// _master is the master strip's key where a strip's key is wanted.
const _master = mixerMasterKey;

/// _Opened is which of a strip's effects is open in place of the strips.
enum _Opened {
  eq("EQ"),
  comp("Compressor"),
  duck("Ducking"),
  loudness("Loudness");

  final String label;
  const _Opened(this.label);
}

class _CanvasMixerState extends State<CanvasMixer>
    with SingleTickerProviderStateMixin {
  CanvasController get controller => widget.controller;
  late final Ticker _ticker;

  /// _peaks is each strip's held peak, per side, in decibels; they fall back
  /// slowly, as a meter's peak hold does.
  final Map<String, (double, double)> _peaks = {};
  final Map<String, (double, double)> _now = {};

  /// _editing is the strip whose chain of effects is shown: in the effects
  /// panel the controller's effectsOf, and never among the strips, whose
  /// effects open the effects panel.
  String? get _editing =>
      widget.effects ? controller.effectsOf ?? controller.effectsChannel : null;

  /// _open opens [key]'s chain of effects on [what], unfolded and scrolled
  /// to.
  void _open(String key, _Opened what) {
    // In the effects panel, from here and from a sound's settings alike:
    // the strips stay where they are.
    controller.openEffects(key, device: _deviceOf(what));
  }

  void _scrollTo(String device) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      var at = _devices[device]?.currentContext;
      if (at != null && at.mounted) {
        // Its left edge in view: its switch and its name, where a narrow
        // chain cannot show it whole.
        Scrollable.ensureVisible(at,
            alignment: 0, duration: const Duration(milliseconds: 200));
      }
    });
  }

  /// _focusSeen is the last of the controller's requests for a device this
  /// effects panel has scrolled to.
  int _focusSeen = 0;

  static String _deviceOf(_Opened what) => switch (what) {
        _Opened.eq => "eq",
        _Opened.comp => "comp",
        _Opened.duck => "duck",
        _Opened.loudness => "loudness",
      };

  /// _devices finds each device in the chain, to scroll to it.
  final Map<String, GlobalKey> _devices = {};
  GlobalKey _deviceKey(String id) => _devices[id] ??= GlobalKey();

  Loudness? _measured;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_meter)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _chainScroll.dispose();
    super.dispose();
  }

  /// _meter reads every strip's level, about thirty times a second.
  Duration _last = Duration.zero;
  void _meter(Duration now) {
    if (now - _last < const Duration(milliseconds: 33)) return;
    _last = now;
    var channels = {
      for (var channel in controller.timelineChannels) channel.key: channel,
    };
    var returns = {for (var r in controller.document.returns) r.id};
    var keys = [...channels.keys, ...returns, _master];
    var moved = false;
    for (var key in keys) {
      // A channel is as loud as its strip: every sound on it is mixed there.
      var (l, r) = key == _master
          ? controller.levels()
          : returns.contains(key)
              ? controller.levels(key)
              : controller.channelLevels(channels[key]!);
      var db = (gainToDb(l), gainToDb(r));
      var was = _now[key];
      if (was == null ||
          (was.$1 - db.$1).abs() > 0.3 ||
          (was.$2 - db.$2).abs() > 0.3) {
        moved = true;
      }
      _now[key] = db;
      var held = _peaks[key] ?? (-90.0, -90.0);
      // Held for a moment, then falling at twenty decibels a second.
      _peaks[key] = (
        math.max(db.$1, held.$1 - 0.66),
        math.max(db.$2, held.$2 - 0.66),
      );
    }
    if (moved && mounted) setState(() {});
  }

  Future<void> _measure() async {
    setState(() {
      _measuring = true;
      _measured = null;
    });
    var result = await measureMix(controller.document);
    if (!mounted) return;
    setState(() {
      _measuring = false;
      _measured = result;
    });
  }

  /// build zooms the desk to the reader's text size, as Ableton's zoom does.
  ///
  /// The strips, the devices and their screens are drawn at sizes of their
  /// own, a desk's, and at the larger text sizes in Settings > Appearance
  /// their labels ran out of them -- four pixels over at Medium, a hundred
  /// at Extra Large. So the desk is laid out at the ordinary size and
  /// scaled as a whole: everything bigger by the same amount, in the same
  /// proportions. The faders, curves and dials read the pointer in their
  /// own coordinates, so they stay under it.
  @override
  Widget build(BuildContext context) {
    var zoom = MediaQuery.textScalerOf(context).scale(1);
    // Never so far that the desk is left less than its least height: a
    // mixer folded down to one line, zoomed, was a line too short for its
    // own names.
    if ((zoom - 1).abs() < 0.01 || zoom <= 0) return _desk(context, 1);
    if (zoom > 1) {
      zoom = math.max(
          1.0,
          math.min(
              zoom,
              widget.height /
                  (widget.effects ? effectsMinHeight : mixerMinHeight)));
    }
    // Held to its own size either way: zoomed, or -- with no room to zoom --
    // drawn at the size it was laid out for.
    Widget unscaled(double zoom) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: Builder(builder: (context) => _desk(context, zoom)),
        );
    if ((zoom - 1).abs() < 0.01) return unscaled(1);
    return LayoutBuilder(builder: (context, box) {
      var width = box.maxWidth.isFinite
          ? box.maxWidth
          : MediaQuery.sizeOf(context).width;
      return SizedBox(
        width: width,
        height: widget.height,
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width / zoom,
            height: widget.height / zoom,
            child: unscaled(zoom),
          ),
        ),
      );
    });
  }

  /// _desk is the mixer, or the effects, laid out at [zoom]'s share of its
  /// height -- see build.
  /// _deskHeight is the desk's height as it is laid out, before any zoom.
  double _deskHeight = mixerDefaultHeight;

  Widget _desk(BuildContext context, double zoom) {
    _deskHeight = widget.height / zoom;
    var theme = MixerLook.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var lanes = [
          for (var l in controller.timelineChannels)
            if (widget.only == null || l.key == widget.only) l,
        ];
        var editing = _editing;
        var compact = !widget.embedded &&
            !widget.effects &&
            widget.height / zoom < mixerCompactBelow;
        if (widget.effects &&
            controller.effectsFocusCount != _focusSeen &&
            controller.effectsFocus != null) {
          _focusSeen = controller.effectsFocusCount;
          _scrollTo(controller.effectsFocus!);
        }
        TimelineChannel? lane;
        if (editing != null && editing != _master) {
          lane = lanes.where((l) => l.key == editing).firstOrNull;
          // A channel gone from the timeline: the master's, in the effects
          // panel, which always shows a chain. A return is not on the
          // timeline, and keeps its own.
          if (lane == null && controller.returnOf(editing) == null) {
            editing = widget.effects ? _master : null;
          }
        }
        // No scroll bars, on the strips or the chain: they scroll with the
        // wheel or the trackpad, and a bar was a stripe across the meters.
        return _SoundScene(
            speakers: controller.document.audio.speakers,
            placed: controller.placementsNow,
            child: ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: Container(
                height: widget.height / zoom,
                decoration: BoxDecoration(
                  color:
                      theme.colors.surfaceContainerLow.withValues(alpha: 0.97),
                  border: Border(
                      top: BorderSide(
                          color: theme.colors.outlineVariant, width: 1)),
                ),
                child: Column(children: [
                  // The grip: dragged up, the mixer is taller. Over the canvas, so
                  // it never moves the design, whatever its height.
                  if (!widget.embedded && widget.resizable)
                    GestureDetector(
                      key: ValueKey(
                          widget.effects ? "effectsGrip" : "mixerGrip"),
                      behavior: HitTestBehavior.opaque,
                      // The drag is in the desk's own, zoomed, coordinates: put
                      // back into the screen's, so the edge stays with the
                      // pointer.
                      onVerticalDragUpdate: (d) =>
                          widget.onResize(widget.height - d.delta.dy * zoom),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: SizedBox(
                          height: 12,
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 3,
                              decoration: BoxDecoration(
                                  color: theme.colors.outline,
                                  borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Dragged down past the strips, one line of channels: each its
                  // name over its meter, on its side.
                  if (compact)
                    Expanded(child: _compact(theme, lanes))
                  else ...[
                    if (widget.embedded) const SizedBox(height: 8),
                    Expanded(
                      child: editing == null
                          ? _strips(theme, lanes)
                          : _editor(theme, editing, lane),
                    ),
                  ],
                ]),
              ),
            ));
      },
    );
  }

  /// _compact is the mixer at its shortest: a line of channels, each its
  /// name -- picked with a press, renamed with a double-click -- over its
  /// meter on its side, and the master's at the end.
  Widget _compact(MixerLook theme, List<TimelineChannel> lanes) {
    var colors = theme.colors;
    Widget cell(String key, Widget name) {
      var selected = controller.selectedChannel == key;
      return Listener(
        onPointerDown: (_) => controller.pickStrip(key),
        child: Container(
          key: ValueKey("compact-$key"),
          width: 150,
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 2 : 1),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            name,
            const SizedBox(height: 2),
            Expanded(
              child: CustomPaint(
                key: ValueKey("compactMeter-$key"),
                painter: _MeterPainter(_now[key] ?? (-90, -90),
                    _peaks[key] ?? (-90, -90), theme.studio,
                    horizontal: true),
              ),
            ),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var lane in lanes)
              cell(
                  lane.key,
                  ChannelNameEditor(
                      name: lane.name,
                      theme: ThemeNotifier.of(context),
                      color: theme.colors.onSurface,
                      onRename: (name) => controller.renameChannel(lane, name),
                      weight: FontWeight.w600,
                      textKey: ValueKey("compactName-${lane.key}"),
                      fieldKey: const ValueKey("mixerNameField"))),
          ]),
        ),
        cell(
            _master,
            Text("Master",
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface))),
      ]),
    );
  }

  Widget _strips(MixerLook theme, List<TimelineChannel> lanes) {
    var master = controller.document.masterMix;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: lanes.isEmpty && widget.embedded
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "A strip appears here for each video and background "
                      "sound on the timeline. The master strip is always "
                      "here, and sets how the whole canvas sounds.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: theme.colors.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var lane in lanes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _ChannelStrip(
                          key: ValueKey("strip-${lane.key}"),
                          // A short desk: the small pan, so the fader keeps
                          // its room.
                          compactPan: _deskHeight < 380,
                          name: lane.name,
                          channelKey: lane.key,
                          mix: lane.mix,
                          // In a sound's own settings it was picked on
                          // purpose, and is changed there wherever it is.
                          editable: lane.editable || widget.embedded,
                          soloed: controller.solo.contains(lane.key),
                          level: _now[lane.key] ?? (-90, -90),
                          peak: _peaks[lane.key] ?? (-90, -90),
                          theme: theme,
                          onChanged: (mix, {transient = false}) {
                            controller.beginInteraction();
                            controller.setChannelMix(lane, mix,
                                transient: true, anywhere: widget.embedded);
                            if (!transient) controller.endInteraction();
                          },
                          onCommit: controller.endInteraction,
                          onSolo: () => controller.toggleSolo(lane.key),
                          onOpenEq: () => _open(lane.key, _Opened.eq),
                          onOpenComp: () => _open(lane.key, _Opened.comp),
                          onOpenDuck: () => _open(lane.key, _Opened.duck),
                          selected: controller.selectedChannel == lane.key,
                          onSelect: () => controller.pickStrip(lane.key),
                          onRename: (name) =>
                              controller.renameChannel(lane, name),
                          returns: controller.document.returns,
                        ),
                      ),
                    // The returns, together after the channels, a little
                    // apart: what the channels' sends feed.
                    if (!widget.embedded) ...[
                      const SizedBox(width: 8),
                      for (var (i, ret) in controller.document.returns.indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ReturnStrip(
                            key: ValueKey("strip-${ret.id}"),
                            compactPan: _deskHeight < 380,
                            letter: returnLetter(i),
                            ret: ret,
                            level: _now[ret.id] ?? (-90, -90),
                            peak: _peaks[ret.id] ?? (-90, -90),
                            theme: theme,
                            onChanged: (next, {transient = false}) {
                              controller.beginInteraction();
                              controller.setReturn(next, transient: true);
                              if (!transient) controller.endInteraction();
                            },
                            onCommit: controller.endInteraction,
                            onOpen: (device) =>
                                controller.openEffects(ret.id, device: device),
                            onRemove: () {
                              controller.beginInteraction();
                              controller.removeReturn(ret.id);
                              controller.endInteraction();
                            },
                            selected: controller.selectedChannel == ret.id,
                            onSelect: () => controller.pickStrip(ret.id),
                          ),
                        ),
                      if (controller.document.returns.length < maxReturns)
                        _AddReturn(
                            theme: theme,
                            onAdd: () {
                              controller.beginInteraction();
                              controller.addReturn();
                              controller.endInteraction();
                            }),
                    ],
                  ],
                ),
        ),
        const SizedBox(width: 8),
        _MasterStrip(
          key: const ValueKey("strip-master"),
          mix: master,
          level: _now[_master] ?? (-90, -90),
          peak: _peaks[_master] ?? (-90, -90),
          theme: theme,
          onChanged: (mix, {transient = false}) {
            controller.beginInteraction();
            controller.setMasterMix(mix, transient: true);
            if (!transient) controller.endInteraction();
          },
          onCommit: controller.endInteraction,
          onOpenEq: () => _open(_master, _Opened.eq),
          onOpenComp: () => _open(_master, _Opened.comp),
          onOpenLoudness: () => _open(_master, _Opened.loudness),
          selected: controller.selectedChannel == _master,
          onSelect: () => controller.pickStrip(_master),
        ),
      ]),
    );
  }

  /// _editor is [key]'s effects as a chain, left to right in the order the
  /// sound goes through them, scrolling sideways: for a channel its EQ and
  /// compressor in the order set, what it ducks, its level, and the
  /// master's; for the master its EQ and glue, the limiter, the loudness
  /// and its level.
  Widget _editor(MixerLook theme, String key, TimelineChannel? lane) {
    var master = controller.document.masterMix;
    var isMaster = key == _master;
    var channel = isMaster ? null : key;
    var folded = controller.foldedDevices;
    return LayoutBuilder(builder: (context, room) {
      var h = math.max(120.0, room.maxHeight - 14);
      Widget device(String id,
              Widget Function(bool folded, VoidCallback onFold) make) =>
          KeyedSubtree(
            key: _deviceKey(id),
            child: make(folded.contains(id),
                () => controller.foldDevice(id, !folded.contains(id))),
          );
      var eq = device(
          "eq",
          (f, fold) => EqDevice(
              controller: controller,
              channel: channel,
              folded: f,
              onFold: fold,
              height: h));
      var comp = device(
          "comp",
          (f, fold) => CompDevice(
              controller: controller,
              channel: channel,
              folded: f,
              onFold: fold,
              height: h));
      var ret = isMaster ? null : controller.returnOf(key);
      var compFirst = isMaster
          ? master.compFirst
          : ret?.mix.compFirst ?? lane!.mix.compFirst;
      var skin = DeviceSkin.themed(theme.colors);
      var chain = <Widget>[
        // A return's own devices first -- its reverb, its delay -- then a
        // way to add another, then its EQ and compressor.
        if (ret != null) ...[
          for (var i = 0; i < ret.devices.length; i++)
            device(
                "dev$i",
                (f, fold) => ParamDevice(
                    controller: controller,
                    returnId: ret.id,
                    index: i,
                    folded: f,
                    onFold: fold,
                    height: h)),
          AddDeviceSlot(
              key: const ValueKey("addDeviceSlot"),
              controller: controller,
              returnId: ret.id,
              height: h),
        ],
        ...(compFirst ? [comp, eq] : [eq, comp]),
        if (lane != null)
          device(
              "duck",
              (f, fold) => DuckDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h)),
        if (isMaster) ...[
          device(
              "limiter",
              (f, fold) => LimiterDevice(
                  controller: controller, folded: f, onFold: fold, height: h)),
          device(
            "loudness",
            (f, fold) => DeviceFrame(
              id: "loudness",
              title: "Loudness",
              skin: skin,
              folded: f,
              onFold: fold,
              width: 340,
              height: h,
              foldedBody: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text("${master.target.round()} LUFS",
                      style: TextStyle(fontSize: 11, color: skin.ink)),
                ),
              ),
              body: Padding(
                padding: const EdgeInsets.all(10),
                child: _LoudnessEditor(
                  mix: master,
                  measured: _measured,
                  measuring: _measuring,
                  onMeasure: _measure,
                  theme: theme,
                  onChanged: (next) {
                    controller.beginInteraction();
                    controller.setMasterMix(next, transient: true);
                    controller.endInteraction();
                  },
                ),
              ),
            ),
          ),
        ],
        // Where it is heard from, big enough to place it by: the room, its
        // speakers and the channel among them -- stereo or surround.
        if (lane != null || ret != null)
          device("panner", (f, fold) {
            var mix = lane?.mix ?? ret!.mix;
            void write(ChannelMix next, {bool transient = false}) {
              controller.beginInteraction();
              if (lane != null) {
                controller.setChannelMix(lane, next,
                    transient: true, anywhere: true);
              } else {
                controller.setReturn(ret!.copyWith(mix: next), transient: true);
              }
              if (!transient) controller.endInteraction();
            }

            return _PannerDevice(
              channel: key,
              mix: mix,
              theme: theme,
              skin: skin,
              folded: f,
              onFold: fold,
              height: h,
              onChanged: write,
              onCommit: controller.endInteraction,
            );
          }),
        if (lane != null)
          device("meter",
              // The channel's own strip, as on the mixer -- its panning,
              // mute and solo, fader and meter -- under its name.
              (f, fold) {
            var level = _now[key] ?? (-90.0, -90.0);
            var peak = _peaks[key] ?? (-90.0, -90.0);
            var mix = lane.mix;
            void write(ChannelMix next, {bool transient = false}) {
              controller.beginInteraction();
              controller.setChannelMix(lane, next,
                  transient: true, anywhere: true);
              if (!transient) controller.endInteraction();
            }

            void set(double db, {bool transient = false}) =>
                write(mix.copyWith(gainDb: db), transient: transient);

            return DeviceFrame(
              id: "meter",
              title: lane.name,
              skin: skin,
              folded: f,
              onFold: fold,
              width: 150,
              height: h,
              foldedBody: CustomPaint(
                  key: const ValueKey("meterFolded"),
                  painter: _MeterPainter(level, peak, theme.studio)),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(children: [
                  _PanControl(
                    channel: lane.key,
                    mix: mix,
                    theme: theme,
                    onChanged: (m, {transient = false}) =>
                        write(m, transient: transient),
                    onCommit: controller.endInteraction,
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: _Toggle(
                          key: const ValueKey("meterMute"),
                          label: "M",
                          on: mix.mute,
                          onColor: theme.studio.arm,
                          theme: theme,
                          tooltip: "Mute: silent here and in exports",
                          onTap: () => write(mix.copyWith(mute: !mix.mute))),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _Toggle(
                          key: const ValueKey("meterSolo"),
                          label: "S",
                          on: controller.solo.contains(key),
                          onColor: theme.studio.solo,
                          theme: theme,
                          tooltip: "Solo: hear only this, while you listen",
                          onTap: () => controller.toggleSolo(key)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _Fader(
                      db: mix.gainDb,
                      level: level,
                      peak: peak,
                      theme: theme,
                      wide: true,
                      onChanged: set,
                      onCommit: controller.endInteraction,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DbReading(
                      db: mix.gainDb,
                      textKey: const ValueKey("meterReading"),
                      onSet: (db) => set(db),
                      style: TextStyle(
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: theme.colors.onSurface)),
                ]),
              ),
            );
          }),
        device(
            "masterMeter",
            (f, fold) => MeterDevice(
                controller: controller,
                channel: null,
                id: "masterMeter",
                title: "Master meter",
                folded: f,
                onFold: fold,
                height: h)),
      ];
      // Held to the left: a chain narrower than the panel was centred.
      return Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          key: const ValueKey("effectsChain"),
          controller: _chainScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var (i, d) in chain.indexed) ...[
              if (i > 0) const SizedBox(width: 4),
              d,
            ],
          ]),
        ),
      );
    });
  }

  final ScrollController _chainScroll = ScrollController();
}

typedef _MixWrite<T> = void Function(T next, {bool transient});

// ---------------------------------------------------------------------------
// Pieces of a strip
// ---------------------------------------------------------------------------

/// faderTop and faderBottom are the fader's travel, in decibels. The bottom is
/// silence.
const double _faderTop = 6;
const double _faderBottom = -60;

/// faderPosition is where [db] sits on the fader, nought at the top to one at
/// the bottom. Not a straight line in decibels: most of the travel is spent
/// where mixing happens, between minus thirty and the top.
double faderPosition(double db) => db <= _faderBottom
    ? 1
    : math
        .pow((_faderTop - db) / (_faderTop - _faderBottom), 0.6)
        .toDouble()
        .clamp(0.0, 1.0);

double faderDb(double position) => position >= 0.995
    ? -90
    : _faderTop -
        math.pow(position.clamp(0.0, 1.0), 1 / 0.6) *
            (_faderTop - _faderBottom);

String dbText(double db) => db <= -89
    ? "−∞"
    : "${db > 0 ? "+" : db < 0 ? "−" : ""}${db.abs().toStringAsFixed(1)}";

/// parseDb reads a level somebody typed: "-6", "−6.5 dB", "+3", "0", or
/// "-inf" for silence -- clamped to what the fader reaches. Null for anything
/// that is not a level, which leaves the fader where it was.
double? parseDb(String text) {
  var t = text
      .trim()
      .toLowerCase()
      .replaceAll("−", "-")
      .replaceAll("db", "")
      .replaceAll(" ", "");
  if (t == "-inf" || t == "-∞" || t == "inf" || t == "∞") return -90;
  var v = double.tryParse(t);
  if (v == null || !v.isFinite) return null;
  if (v <= _faderBottom - 30) return -90;
  return v.clamp(-90.0, _faderTop).toDouble();
}

/// DbReading is the level under a fader: clicked, it takes a typed value.
class DbReading extends StatefulWidget {
  final double db;
  final ValueChanged<double> onSet;
  final TextStyle style;

  /// textKey is on the reading itself, so a test can find it by its old name.
  final Key? textKey;

  /// fieldHeight is how tall the box for typing is, to fit where it is.
  final double fieldHeight;

  /// unit follows the number: " dB" under a fader, nothing where there is
  /// no room for it.
  final String unit;

  const DbReading(
      {required this.db,
      required this.onSet,
      required this.style,
      this.textKey,
      this.fieldHeight = 16,
      this.unit = " dB",
      super.key});

  @override
  State<DbReading> createState() => _DbReadingState();
}

class _DbReadingState extends State<DbReading> {
  bool _typing = false;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    setState(() {
      _typing = true;
      _text.text = widget.db <= -89 ? "-inf" : widget.db.toStringAsFixed(1);
      _text.selection =
          TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    if (!_typing) return;
    var v = parseDb(_text.text);
    setState(() => _typing = false);
    if (v != null && v != widget.db) widget.onSet(v);
  }

  @override
  Widget build(BuildContext context) {
    if (_typing) {
      return SizedBox(
        height: widget.fieldHeight,
        child: TextField(
          key: const ValueKey("dbEntry"),
          controller: _text,
          focusNode: _focus,
          textAlign: TextAlign.center,
          style: widget.style,
          decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Text("${dbText(widget.db)}${widget.unit}",
            key: widget.textKey,
            textAlign: TextAlign.center,
            style: widget.style),
      ),
    );
  }
}

class _Fader extends StatelessWidget {
  final double db;
  final (double, double) level;
  final (double, double) peak;
  final MixerLook theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;
  final bool wide;

  const _Fader({
    required this.db,
    required this.level,
    required this.peak,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          var h = box.maxHeight;
          void at(double y) =>
              onChanged(faderDb(((y - 6) / (h - 12)).clamp(0.0, 1.0)),
                  transient: true);
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GestureDetector(
              key: const ValueKey("fader"),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) => at(d.localPosition.dy),
              onVerticalDragUpdate: (d) => at(d.localPosition.dy),
              onVerticalDragEnd: (_) => onCommit(),
              onDoubleTap: () => onChanged(0),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: CustomPaint(
                  size: Size(wide ? 44 : 40, h),
                  painter: _FaderPainter(db, theme.studio),
                ),
              ),
            ),
            const SizedBox(width: 4),
            CustomPaint(
              size: Size(wide ? 22 : 14, h),
              painter: _MeterPainter(level, peak, theme.studio),
            ),
          ]);
        },
      );
}

/// _FaderPainter is the fader: a slot with the decibels marked down its
/// left, nought picked out, and a ridged cap with a line in the strip's
/// "on" colour where the level is.
class _FaderPainter extends CustomPainter {
  final double db;
  final StudioColors colors;
  _FaderPainter(this.db, this.colors);

  static const _marks = [6.0, 0.0, -6.0, -12.0, -24.0, -48.0];

  @override
  void paint(Canvas canvas, Size size) {
    var slotX = size.width - 13;
    double yOf(double d) => 6 + faderPosition(d) * (size.height - 12);
    // The scale, left of the slot.
    for (var m in _marks) {
      var y = yOf(m);
      var unity = m == 0;
      canvas.drawLine(
          Offset(slotX - (unity ? 12 : 8), y),
          Offset(slotX - 3, y),
          Paint()
            ..strokeWidth = 1
            ..color = unity ? colors.muted : colors.edge);
      var label = TextPainter(
        text: TextSpan(
            text: m > 0 ? "+${m.round()}" : "${m.round()}".replaceAll("-", "−"),
            style: TextStyle(
                fontSize: 7,
                height: 1,
                color: unity ? colors.text : colors.muted)),
        textDirection: TextDirection.ltr,
      )..layout();
      if (size.height > 90) {
        label.paint(
            canvas, Offset(slotX - 14 - label.width, y - label.height / 2));
      }
    }
    // The slot, and the part of it under the cap lit.
    var slot = RRect.fromLTRBR(
        slotX - 2, 6, slotX + 2, size.height - 6, const Radius.circular(2));
    canvas.drawRRect(slot, Paint()..color = colors.inset);
    var y = yOf(db);
    canvas.drawRRect(
        RRect.fromLTRBR(slotX - 1.5, y, slotX + 1.5, size.height - 6,
            const Radius.circular(1.5)),
        Paint()..color = colors.on.withValues(alpha: 0.55));
    // The cap: metal, ridged, with its line.
    var cap = Rect.fromCenter(center: Offset(slotX, y), width: 22, height: 30);
    var rrect = RRect.fromRectAndRadius(cap, const Radius.circular(4));
    canvas.drawRRect(
        rrect.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawRRect(
        rrect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFECEEF2),
              Color(0xFFC3C7CE),
              Color(0xFF9AA0A9),
              Color(0xFFC9CDD3),
            ],
            stops: [0, 0.46, 0.54, 1],
          ).createShader(cap));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF0E0F12));
    var grip = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFF7D838D);
    for (var dy in [-9.0, -5.0, 5.0, 9.0]) {
      canvas.drawLine(
          Offset(slotX - 7, y + dy), Offset(slotX + 7, y + dy), grip);
    }
    canvas.drawLine(
        Offset(slotX - 8, y),
        Offset(slotX + 8, y),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.on);
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.db != db || old.colors != colors;
}

class _MeterPainter extends CustomPainter {
  final (double, double) level;
  final (double, double) peak;
  final StudioColors colors;

  /// horizontal lays it on its side: nought on the right, the left side's
  /// bar above the right's.
  final bool horizontal;
  _MeterPainter(this.level, this.peak, this.colors, {this.horizontal = false});

  /// A meter reads from minus sixty to nought, in lit segments: green, then
  /// amber for the last nine decibels, then red at the top -- the colours
  /// of every meter anybody has seen, from the studio palette.
  double _fill(double db) => ((db + 60) / 60).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (horizontal) {
      // Turned a quarter: its bottom to the left, the left side on top.
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.rotate(math.pi / 2);
      _paint(canvas, Size(size.height, size.width), inset: 0);
      canvas.restore();
      return;
    }
    _paint(canvas, size);
  }

  void _paint(Canvas canvas, Size size, {double inset = 6}) {
    var w = (size.width - 2) / 2;
    for (var (i, (db, held))
        in [(level.$1, peak.$1), (level.$2, peak.$2)].indexed) {
      var x = i * (w + 2);
      var well = Rect.fromLTWH(x, inset, w, size.height - 2 * inset);
      canvas.drawRect(well, Paint()..color = colors.inset);
      var segments = math.max(8, (well.height / 4).floor());
      var step = well.height / segments;
      var lit = _fill(db);
      for (var k = 0; k < segments; k++) {
        var f = (k + 0.5) / segments;
        var lamp = f > 0.95
            ? colors.meterHigh
            : f > 0.85
                ? colors.meterMid
                : colors.meterLow;
        var top = well.bottom - (k + 1) * step + 0.5;
        canvas.drawRect(Rect.fromLTWH(x, top, w, math.max(0.5, step - 1)),
            Paint()..color = f <= lit ? lamp : colors.unlit(lamp));
      }
      var peakY = well.bottom - _fill(held) * well.height;
      canvas.drawRect(Rect.fromLTWH(x, peakY - 1, w, 2),
          Paint()..color = colors.text.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.level != level || old.peak != peak || old.colors != colors;
}

/// _MiniCurve is an EQ drawn small, on a strip's EQ slot.
class _MiniCurve extends CustomPainter {
  final Eq eq;
  final ColorScheme colors;
  _MiniCurve(this.eq, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    for (var i = 0; i <= 40; i++) {
      var f = 20 * math.pow(1000, i / 40).toDouble();
      var db = eq.responseDb(f).clamp(-12.0, 12.0);
      var x = i / 40 * size.width;
      var y = size.height / 2 - db / 12 * (size.height / 2 - 1);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = eq.on ? colors.primary : colors.outline);
  }

  @override
  bool shouldRepaint(_MiniCurve old) =>
      old.eq.toJson().toString() != eq.toJson().toString();
}

Widget _slot(MixerLook theme, String label, bool on, Widget trailing,
        VoidCallback onTap,
        {Key? key}) =>
    Material(
      color: theme.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on
                        ? theme.colors.onSurface
                        : theme.colors.onSurfaceVariant)),
            const SizedBox(width: 4),
            // Scaled down rather than overflowing: a reading like
            // "−12.0 dBTP" beside its label is wider than a strip in some
            // fonts, and a strip that overflows is a striped warning where
            // the control should be.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
              ),
            ),
          ]),
        ),
      ),
    );

class _ChannelStrip extends StatelessWidget {
  final String name;

  /// compactPan is a short desk's: see _PanControl.compact.
  final bool compactPan;

  /// channelKey is the channel's key: where its placement is looked up.
  final String channelKey;
  final ChannelMix mix;
  final bool editable;
  final bool soloed;
  final (double, double) level;
  final (double, double) peak;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onSolo;
  final VoidCallback onOpenEq;
  final VoidCallback onOpenComp;
  final VoidCallback onOpenDuck;

  /// selected is whether this is the channel picked -- here or on the
  /// timeline; a press anywhere on the strip picks it.
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<String> onRename;

  /// returns are what its sends can feed: a dial for each.
  final List<ReturnChannel> returns;

  const _ChannelStrip({
    this.compactPan = false,
    this.returns = const [],
    required this.name,
    required this.channelKey,
    required this.mix,
    required this.editable,
    required this.soloed,
    required this.level,
    required this.peak,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    required this.onSolo,
    required this.onOpenEq,
    required this.onOpenComp,
    required this.onOpenDuck,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var body = Container(
      width: 116,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Double-clicked, renamed: the channel's name on the timeline too.
        ChannelNameEditor(
            name: name,
            theme: ThemeNotifier.of(context),
            color: theme.colors.onSurface,
            onRename: onRename,
            weight: FontWeight.w600,
            textKey: const ValueKey("mixerName"),
            fieldKey: const ValueKey("mixerNameField")),
        const SizedBox(height: 6),
        _slot(
            theme,
            "EQ",
            mix.eq.on,
            CustomPaint(
                size: const Size(40, 14), painter: _MiniCurve(mix.eq, colors)),
            onOpenEq,
            key: const ValueKey("eqSlot")),
        const SizedBox(height: 4),
        _slot(
            theme,
            "Comp",
            mix.comp.on,
            Icon(Icons.circle,
                size: 7, color: mix.comp.on ? theme.studio.on : colors.outline),
            onOpenComp,
            key: const ValueKey("compSlot")),
        const SizedBox(height: 4),
        // Whether this channel turns the others down while it is heard --
        // see Ducking. On the channel that is listened for: the voice.
        _slot(
            theme,
            "Duck",
            mix.duck.on,
            Text(mix.duck.on ? "${dbText(mix.duck.depthDb)} dB" : "off",
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
            onOpenDuck,
            key: const ValueKey("duckSlot")),
        if (returns.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Sends(
            mix: mix,
            returns: returns,
            theme: theme,
            onChanged: onChanged,
            onCommit: onCommit,
          ),
        ],
        const SizedBox(height: 6),
        _PanControl(
          compact: compactPan,
          channel: channelKey,
          mix: mix,
          theme: theme,
          onChanged: onChanged,
          onCommit: onCommit,
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: _Toggle(
                key: const ValueKey("mute"),
                label: "M",
                on: mix.mute,
                onColor: theme.studio.arm,
                theme: theme,
                tooltip: "Mute: silent here and in exports",
                onTap: () => onChanged(mix.copyWith(mute: !mix.mute))),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _Toggle(
                key: const ValueKey("solo"),
                label: "S",
                on: soloed,
                onColor: theme.studio.solo,
                theme: theme,
                tooltip: "Solo: hear only this, while you listen",
                onTap: onSolo),
          ),
        ]),
        const SizedBox(height: 6),
        Expanded(
          child: _Fader(
            db: mix.gainDb,
            level: level,
            peak: peak,
            theme: theme,
            onChanged: (db, {transient = false}) =>
                onChanged(mix.copyWith(gainDb: db), transient: transient),
            onCommit: onCommit,
          ),
        ),
        const SizedBox(height: 4),
        DbReading(
            db: mix.gainDb,
            textKey: const ValueKey("faderReading"),
            onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
            style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.onSurface)),
      ]),
    );
    if (editable) {
      // A Listener, not a tap: it picks the channel whatever the press
      // goes on to do -- open an effect, move the fader -- without taking
      // the press from it.
      return Listener(onPointerDown: (_) => onSelect(), child: body);
    }
    return Tooltip(
      message: "On the master: changed there",
      child: IgnorePointer(child: Opacity(opacity: 0.55, child: body)),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool on;
  final Color onColor;
  final MixerLook theme;
  final String tooltip;
  final VoidCallback onTap;

  const _Toggle({
    required this.label,
    required this.on,
    required this.onColor,
    required this.theme,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: on ? onColor : theme.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: SizedBox(
              height: 20,
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: on
                            ? const Color(0xFFFFFFFF)
                            : theme.colors.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      );
}

/// _Balance is a knob: dragged up to turn right, down to turn left, double-
/// clicked to centre.
class _Balance extends StatelessWidget {
  final double value;
  final MixerLook theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;

  const _Balance({
    required this.value,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    var reading = value.abs() < 0.02
        ? "C"
        : "${value < 0 ? "L" : "R"}${(value.abs() * 100).round()}";
    return Row(children: [
      Text("Pan",
          style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant)),
      const Spacer(),
      GestureDetector(
        key: const ValueKey("balance"),
        onVerticalDragUpdate: (d) => onChanged(
            (value - d.delta.dy / 80).clamp(-1.0, 1.0),
            transient: true),
        onVerticalDragEnd: (_) => onCommit(),
        onDoubleTap: () => onChanged(0),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: CustomPaint(
            size: const Size(24, 24),
            painter: _KnobPainter(value, theme.colors),
          ),
        ),
      ),
      const Spacer(),
      SizedBox(
        width: 26,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(reading,
              style: TextStyle(fontSize: 10, color: theme.colors.onSurface)),
        ),
      ),
    ]);
  }
}

/// _SoundScene is what the strips need to know of the room: the speakers
/// the piece is mixed for, and where each placed channel is heard from on
/// this frame.
class _SoundScene extends InheritedWidget {
  final SpeakerLayout speakers;
  final Map<String, Heard> placed;
  const _SoundScene(
      {required this.speakers, required this.placed, required super.child});

  static _SoundScene? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SoundScene>();

  @override
  bool updateShouldNotify(_SoundScene old) =>
      old.speakers != speakers || !mapEquals(old.placed, placed);
}

/// angleText is an angle as a strip says it: C, or L or R and how far.
String angleText(double angle) {
  var a = wrapAngle(angle);
  if (a.abs() < 1) return "C";
  return "${a < 0 ? "L" : "R"}${a.abs().round()}°";
}

/// _PanControl is where a channel is heard from. Stereo: the balance knob.
/// Surround: a pad of the room, its speakers round it, the channel a dot to
/// drag round them -- with how wide its two sides are spread, and how much
/// goes to the LFE. Placed by the picture: the same pad, showing where the
/// picture puts it, and not to be dragged.
class _PanControl extends StatelessWidget {
  final String channel;
  final ChannelMix mix;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  /// compact is a short strip's: a small pad and its reading, the width and
  /// the LFE left to the Panner device in the effects.
  final bool compact;

  const _PanControl({
    this.compact = false,
    required this.channel,
    required this.mix,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    var scene = _SoundScene.of(context);
    var speakers = scene?.speakers ?? SpeakerLayout.stereo;
    var placed = scene?.placed[channel];
    if (placed == null && !speakers.isSurround) {
      return _Balance(
        value: mix.balance,
        theme: theme,
        onChanged: (v, {transient = false}) =>
            onChanged(mix.copyWith(balance: v), transient: transient),
        onCommit: onCommit,
      );
    }
    var colors = theme.colors;
    var pan = mix.surround ?? const SurroundPan();
    var small = TextStyle(fontSize: 9, color: colors.onSurfaceVariant);
    var value = TextStyle(fontSize: 10, color: colors.onSurface);
    // The pad beside its readings, not over them: a strip is a column of
    // fixed height with the fader taking what is left, and the pad stacked
    // over its numbers took eighty pixels from the fader.
    var pad = Tooltip(
      message: placed != null
          ? "Heard from where the picture puts it: see the sound's "
              "Placement. Its own pan is kept for when it is not placed."
          : "Drag the dot round to where it is heard from. Double-click "
              "for the front pair, as it was mixed.",
      child: _SurroundPad(
        key: const ValueKey("surroundPad"),
        side: compact ? 28 : _SurroundPad.size,
        speakers: speakers,
        pan: placed == null ? mix.surround : null,
        placed: placed,
        theme: theme,
        onAngle: placed != null
            ? null
            : (a) => onChanged(mix.withSurround(pan.copyWith(angle: a)),
                transient: true),
        onCommit: onCommit,
        onReset:
            placed != null ? null : () => onChanged(mix.withSurround(null)),
      ),
    );
    Widget fit(Widget child, Alignment to) =>
        FittedBox(fit: BoxFit.scaleDown, alignment: to, child: child);
    if (compact) {
      return SizedBox(
        height: 28,
        child: Row(children: [
          pad,
          const SizedBox(width: 5),
          Expanded(
            child: fit(
                Text(
                    key: const ValueKey("panReading"),
                    placed != null
                        ? "Placed ${angleText(placed.angle)}"
                        : mix.surround == null
                            ? "Front"
                            : angleText(pan.angle),
                    style: value),
                Alignment.centerLeft),
          ),
        ]),
      );
    }
    return SizedBox(
      height: _SurroundPad.size,
      child: Row(children: [
        pad,
        const SizedBox(width: 5),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Each shrinks rather than runs out of a narrow strip.
                // Placed says so; otherwise the reading -- Front, or an
                // angle -- says what it is by itself.
                if (placed != null)
                  fit(Text("Placed", style: small), Alignment.centerLeft),
                fit(
                    Text(
                        key: const ValueKey("panReading"),
                        placed != null
                            ? angleText(placed.angle)
                            : mix.surround == null
                                ? "Front"
                                : angleText(pan.angle),
                        style: value),
                    Alignment.centerLeft),
                if (placed == null && speakers.isSurround) ...[
                  _DragNumber(
                    key: const ValueKey("surroundWidth"),
                    label: "W",
                    text: "${pan.width.round()}°",
                    theme: theme,
                    tooltip: "Width: how far apart its left and right are "
                        "heard. 60 is the front pair, nought one point. Drag "
                        "up or down.",
                    onDrag: (dy) => onChanged(
                        mix.withSurround(pan.copyWith(width: pan.width - dy)),
                        transient: true),
                    onCommit: onCommit,
                    onReset: () =>
                        onChanged(mix.withSurround(pan.copyWith(width: 60))),
                  ),
                  _DragNumber(
                    key: const ValueKey("surroundLfe"),
                    label: "LFE",
                    text: mix.lfeDb == null ? "off" : dbText(mix.lfeDb!),
                    theme: theme,
                    tooltip: "How much also goes to the LFE, the "
                        "low-frequency speaker, below 120Hz. Drag up or "
                        "down; double-click for none.",
                    onDrag: (dy) => onChanged(
                        mix.withLfe((mix.lfeDb ?? -61) - dy / 2),
                        transient: true),
                    onCommit: onCommit,
                    onReset: () => onChanged(mix.withLfe(null)),
                  ),
                ] else
                  const Spacer(),
              ]),
        ),
      ]),
    );
  }
}

/// speakerLights is how much of a channel each of [layout]'s speakers
/// carries, nought to one -- the same sums MixGraph lands it with -- for
/// lighting them.
List<double> speakerLights(
    SpeakerLayout layout, ChannelMix mix, Heard? placed) {
  var n = layout.channels;
  var out = List.filled(n, 0.0);
  if (placed != null) {
    var g = panGains(layout, placed.angle);
    for (var c = 0; c < n; c++) {
      out[c] = g[c] * placed.gain;
    }
    return out;
  }
  if (!layout.isSurround) {
    var b = mix.balance.clamp(-1.0, 1.0);
    return [b > 0 ? 1 - b : 1, b < 0 ? 1 + b : 1];
  }
  var pan = mix.surround;
  if (pan == null) {
    out[0] = 1;
    out[1] = 1;
  } else {
    var gl = panGains(layout, pan.angle - pan.width / 2);
    var gr = panGains(layout, pan.angle + pan.width / 2);
    for (var c = 0; c < n; c++) {
      out[c] = math.max(gl[c], gr[c]);
    }
  }
  if ((layout.lfe, mix.lfeDb) case (var lfe?, var db?)) {
    out[lfe] = dbToGain(db).clamp(0.0, 1.0);
  }
  return out;
}

/// _PannerDevice is the effects panel's view of where a channel is heard
/// from: the room from above, big enough to place a sound by, its speakers
/// lit by how much of the channel each carries. Stereo: the dot is the
/// balance, between the front pair. Surround: anywhere round the room,
/// with its width and its LFE beside. Placed by the picture: where the
/// picture puts it, and not to be dragged.
class _PannerDevice extends StatelessWidget {
  final String channel;
  final ChannelMix mix;
  final MixerLook theme;
  final DeviceSkin skin;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  const _PannerDevice({
    required this.channel,
    required this.mix,
    required this.theme,
    required this.skin,
    required this.folded,
    required this.onFold,
    required this.height,
    required this.onChanged,
    required this.onCommit,
  });

  /// _stereoFrom is the balance a point at [angle] gives: the front pair
  /// across, a point behind heard on its own side.
  static double _stereoFrom(double angle) {
    var a = wrapAngle(angle);
    if (a > 90) a = 180 - a;
    if (a < -90) a = -180 - a;
    return (a / 30).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    var scene = _SoundScene.of(context);
    var layout = scene?.speakers ?? SpeakerLayout.stereo;
    var placed = scene?.placed[channel];
    var surround = layout.isSurround;
    var pan = mix.surround ?? const SurroundPan();
    var colors = theme.colors;
    var reading = placed != null
        ? angleText(placed.angle)
        : surround
            ? (mix.surround == null ? "Front" : angleText(pan.angle))
            : (mix.balance.abs() < 0.02
                ? "C"
                : "${mix.balance < 0 ? "L" : "R"}"
                    "${(mix.balance.abs() * 100).round()}");
    // The room fills the device: as wide as it is, as tall as the device
    // less the bar of readings along its foot -- a room is wider than it is
    // deep, and the speakers stand round it on an ellipse to match. A press
    // is read against the room as it was drawn.
    void point(Offset local, Size room) {
      var rx = room.width / 2 - 22, ry = room.height / 2 - 18;
      var d = local - room.center(Offset.zero);
      var angle = math.atan2(d.dx / rx, -d.dy / ry) * 180 / math.pi;
      onChanged(
          surround
              ? mix.withSurround(pan.copyWith(angle: angle))
              : mix.copyWith(balance: _stereoFrom(angle)),
          transient: true);
    }

    Widget viewOf(Size room) {
      Widget view = CustomPaint(
        size: room,
        painter: _BigRoomPainter(
          layout: layout,
          mix: mix,
          placed: placed,
          lights: speakerLights(layout, mix, placed),
          studio: theme.studio,
        ),
      );
      if (placed == null) {
        view = Listener(
          // The wheel over the room: its width, in surround.
          onPointerSignal: (e) {
            if (!surround || e is! PointerScrollEvent) return;
            onChanged(mix.withSurround(
                pan.copyWith(width: pan.width - e.scrollDelta.dy / 4)));
          },
          child: GestureDetector(
            onPanStart: (d) => point(d.localPosition, room),
            onPanUpdate: (d) => point(d.localPosition, room),
            onPanEnd: (_) => onCommit(),
            onDoubleTap: () => onChanged(
                surround ? mix.withSurround(null) : mix.copyWith(balance: 0)),
            child: MouseRegion(cursor: SystemMouseCursors.precise, child: view),
          ),
        );
      }
      return view;
    }

    var small = TextStyle(fontSize: 10, color: colors.onSurfaceVariant);
    Widget number(String key, String label, String text, String tip,
            ValueChanged<double> drag, VoidCallback reset) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _DragNumber(
              key: ValueKey(key),
              label: label,
              text: text,
              theme: theme,
              height: 20,
              tooltip: tip,
              onDrag: drag,
              onCommit: onCommit,
              onReset: reset,
            ),
          ),
        );

    // The readings, along the foot of the room.
    var bar = SizedBox(
      height: 24,
      child: Row(children: [
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(reading,
                  key: const ValueKey("pannerReading"),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.onSurface)),
              const SizedBox(width: 6),
              Text(
                  placed != null
                      ? (placed.gain >= 0.999
                          ? "Placed by the picture"
                          : "Placed · ${dbText(gainToDb(placed.gain))} dB")
                      : layout.label,
                  style: small),
            ]),
          ),
        ),
        if (placed == null && surround) ...[
          number(
              "pannerAngle",
              "Angle",
              "${wrapAngle(pan.angle).round()}°",
              "Where it is heard from, round from straight ahead. Drag up or "
                  "down; double-click for the front.",
              (dy) => onChanged(
                  mix.withSurround(pan.copyWith(angle: pan.angle - dy)),
                  transient: true),
              () => onChanged(mix.withSurround(pan.copyWith(angle: 0)))),
          number(
              "pannerWidth",
              "Width",
              "${pan.width.round()}°",
              "How far apart its left and right are heard: 60 is the front "
                  "pair, nought one point.",
              (dy) => onChanged(
                  mix.withSurround(pan.copyWith(width: pan.width - dy)),
                  transient: true),
              () => onChanged(mix.withSurround(pan.copyWith(width: 60)))),
          number(
              "pannerLfe",
              "LFE",
              mix.lfeDb == null ? "off" : "${dbText(mix.lfeDb!)} dB",
              "How much also goes to the LFE, below 120Hz. Double-click for "
                  "none.",
              (dy) => onChanged(mix.withLfe((mix.lfeDb ?? -61) - dy / 2),
                  transient: true),
              () => onChanged(mix.withLfe(null))),
        ] else if (placed == null)
          number(
              "pannerBalance",
              "Pan",
              reading,
              "Left to right. Drag up or down; double-click for the middle.",
              (dy) => onChanged(
                  mix.copyWith(
                      balance: (mix.balance - dy / 80).clamp(-1.0, 1.0)),
                  transient: true),
              () => onChanged(mix.copyWith(balance: 0))),
        if (placed == null)
          TextButton(
            key: const ValueKey("pannerFront"),
            onPressed: () => onChanged(
                surround ? mix.withSurround(null) : mix.copyWith(balance: 0)),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: colors.onSurfaceVariant),
            child: FittedBox(
                child: Text(surround ? "Front pair" : "Centre",
                    style: const TextStyle(fontSize: 11))),
          ),
      ]),
    );

    return DeviceFrame(
      id: "panner",
      title: "Panner",
      skin: skin,
      folded: folded,
      onFold: onFold,
      // Wider than tall, as a room is.
      width: (height * 1.6).clamp(340.0, 560.0),
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(reading, style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Tooltip(
              message: placed != null
                  ? "Heard from where the picture puts it -- see the sound's "
                      "Placement."
                  : surround
                      ? "Drag to where it is heard from; the wheel sets its "
                          "width. Double-click for the front pair."
                      : "Drag between the speakers to set its balance. "
                          "Double-click for the middle.",
              child: LayoutBuilder(
                builder: (context, box) => KeyedSubtree(
                    key: const ValueKey("pannerRoom"),
                    child: viewOf(box.biggest)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          bar,
        ]),
      ),
    );
  }
}

class _BigRoomPainter extends CustomPainter {
  final SpeakerLayout layout;
  final ChannelMix mix;
  final Heard? placed;
  final List<double> lights;
  final StudioColors studio;

  _BigRoomPainter({
    required this.layout,
    required this.mix,
    required this.placed,
    required this.lights,
    required this.studio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    // The room's width and depth: speakers round an ellipse, not a circle,
    // so the room fills the device. [k] is how far out, nought to one.
    var rx = size.width / 2 - 22, ry = size.height / 2 - 18;
    Offset at(double deg, double k) {
      var a = deg * math.pi / 180;
      return c + Offset(math.sin(a) * rx * k, -math.cos(a) * ry * k);
    }

    Rect oval(double k) =>
        Rect.fromCenter(center: c, width: 2 * rx * k, height: 2 * ry * k);

    void label(String text, Offset centre, Color colour, double fontSize) {
      var p = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: colour)),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, centre - Offset(p.width / 2, p.height / 2));
    }

    // The room.
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()..color = studio.display);
    var guide = Paint()
      ..style = PaintingStyle.stroke
      ..color = studio.displayLine.withValues(alpha: 0.18);
    for (var k in [0.33, 0.66, 1.0]) {
      canvas.drawOval(oval(k), guide);
    }
    for (var deg = 0; deg < 360; deg += 30) {
      canvas.drawLine(c, at(deg.toDouble(), 1), guide);
    }
    // In the corner, clear of the centre speaker under it.
    var front = TextPainter(
      text: TextSpan(
          text: "▲ FRONT",
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: studio.displayLine.withValues(alpha: 0.7))),
      textDirection: TextDirection.ltr,
    )..layout();
    front.paint(canvas, const Offset(8, 6));

    // The speakers, each lit by how much of the channel it carries.
    for (var (i, (name, deg)) in layout.speakers.indexed) {
      var lit = i < lights.length ? lights[i] : 0.0;
      if (deg == null) {
        // The LFE has no direction: a box at the foot of the room.
        var box = Rect.fromCenter(
            center: Offset(c.dx, size.height - 10), width: 30, height: 12);
        canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)),
            Paint()..color = Color.lerp(studio.inset, studio.on, lit)!);
        label("LFE", box.center, lit > 0.5 ? studio.onOn : studio.muted, 8);
        continue;
      }
      var p = at(deg.toDouble(), 1);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(deg * math.pi / 180);
      var cabinet = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 22, height: 14),
          const Radius.circular(3));
      canvas.drawRRect(
          cabinet, Paint()..color = Color.lerp(studio.inset, studio.on, lit)!);
      canvas.drawRRect(
          cabinet,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = studio.edge);
      canvas.restore();
      label(name, p, lit > 0.5 ? studio.onOn : studio.text, 9);
    }

    // The listener, facing the front.
    canvas.drawCircle(c, 9, Paint()..color = studio.raised);
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - 4, c.dy - 7)
          ..lineTo(c.dx + 4, c.dy - 7)
          ..lineTo(c.dx, c.dy - 13)
          ..close(),
        Paint()..color = studio.muted);

    var dot = Paint()..color = studio.on;
    var ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = studio.on;
    if (placed case var h?) {
      // Nearer the middle the louder it is.
      var p = at(h.angle, 1.05 - h.gain.clamp(0.25, 1.0) * 0.45);
      canvas.drawCircle(p, 9, ring);
      canvas.drawCircle(p, 5, dot);
      return;
    }
    if (!layout.isSurround) {
      var deg = mix.balance.clamp(-1.0, 1.0) * 30;
      canvas.drawArc(
          oval(0.7),
          (-30 - 90) * math.pi / 180,
          60 * math.pi / 180,
          false,
          guide
            ..strokeWidth = 3
            ..color = studio.displayLine.withValues(alpha: 0.35));
      canvas.drawCircle(at(deg, 0.7), 7, dot);
      return;
    }
    var pan = mix.surround;
    if (pan == null) {
      // The front pair, as it was mixed.
      canvas.drawCircle(at(-30, 0.7), 6, dot);
      canvas.drawCircle(at(30, 0.7), 6, dot);
      return;
    }
    if (pan.width > 0) {
      canvas.drawArc(
          oval(0.7),
          (pan.angle - pan.width / 2 - 90) * math.pi / 180,
          pan.width * math.pi / 180,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..color = studio.on.withValues(alpha: 0.5));
      // Its two sides, at the ends.
      for (var side in [-1, 1]) {
        canvas.drawCircle(at(pan.angle + side * pan.width / 2, 0.7), 4,
            Paint()..color = studio.text);
      }
    }
    canvas.drawCircle(at(pan.angle, 0.7), 7, dot);
  }

  @override
  bool shouldRepaint(_BigRoomPainter old) =>
      old.layout != layout ||
      old.mix.toJson().toString() != mix.toJson().toString() ||
      old.placed != placed ||
      !listEquals(old.lights, lights) ||
      old.studio != studio;
}

/// _DragNumber is a small label and value, changed by dragging up or down
/// and put back by a double-click.
class _DragNumber extends StatelessWidget {
  final String label;
  final String text;
  final String tooltip;
  final MixerLook theme;
  final ValueChanged<double> onDrag;
  final VoidCallback onCommit;
  final VoidCallback onReset;

  /// height is the box's; the strips' are small.
  final double height;

  const _DragNumber({
    this.height = 14,
    required this.label,
    required this.text,
    required this.tooltip,
    required this.theme,
    required this.onDrag,
    required this.onCommit,
    required this.onReset,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
          onVerticalDragEnd: (_) => onCommit(),
          onDoubleTap: onReset,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: theme.colors.surfaceContainerLowest,
                border: Border.all(color: theme.colors.outlineVariant),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text("$label $text",
                    style: TextStyle(
                        fontSize: height > 16 ? 11 : 9,
                        color: theme.colors.onSurface)),
              ),
            ),
          ),
        ),
      );
}

/// _SurroundPad is the room from above, the listener in the middle facing
/// up: each speaker a mark round the edge, the channel a dot where it is
/// heard from, its two sides' spread an arc either side.
class _SurroundPad extends StatelessWidget {
  /// side is how big it is drawn.
  final double side;
  final SpeakerLayout speakers;
  final SurroundPan? pan;
  final Heard? placed;
  final MixerLook theme;
  final ValueChanged<double>? onAngle;
  final VoidCallback onCommit;
  final VoidCallback? onReset;

  const _SurroundPad({
    this.side = _SurroundPad.size,
    required this.speakers,
    required this.pan,
    required this.placed,
    required this.theme,
    required this.onAngle,
    required this.onCommit,
    required this.onReset,
    super.key,
  });

  static const double size = 48;

  double _angleAt(Offset local) {
    var d = local - Offset(side / 2, side / 2);
    return math.atan2(d.dx, -d.dy) * 180 / math.pi;
  }

  @override
  Widget build(BuildContext context) {
    var painter = CustomPaint(
      size: Size.square(side),
      painter: _RoomPainter(speakers, pan, placed, theme.studio),
    );
    var angle = onAngle;
    if (angle == null) return painter;
    return GestureDetector(
      onPanStart: (d) => angle(_angleAt(d.localPosition)),
      onPanUpdate: (d) => angle(_angleAt(d.localPosition)),
      onPanEnd: (_) => onCommit(),
      onDoubleTap: onReset,
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: painter),
    );
  }
}

class _RoomPainter extends CustomPainter {
  final SpeakerLayout speakers;
  final SurroundPan? pan;
  final Heard? placed;
  final StudioColors studio;
  _RoomPainter(this.speakers, this.pan, this.placed, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 4;
    Offset at(double deg, double radius) {
      var a = deg * math.pi / 180;
      return c + Offset(math.sin(a), -math.cos(a)) * radius;
    }

    canvas.drawCircle(c, r + 3, Paint()..color = studio.inset);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = studio.edge);
    // The listener, facing the front.
    canvas.drawCircle(c, 2.5, Paint()..color = studio.muted);
    for (var (_, deg) in speakers.speakers) {
      if (deg == null) continue;
      canvas.drawCircle(at(deg.toDouble(), r), 3, Paint()..color = studio.text);
    }
    var lit = Paint()..color = studio.on;
    if (placed case var h?) {
      // Nearer the middle the louder it is.
      canvas.drawCircle(
          at(h.angle, r * (1.15 - h.gain.clamp(0.3, 1.0) * 0.4)), 4.5, lit);
      return;
    }
    var p = pan;
    if (p == null) {
      // The front pair, as it was mixed.
      canvas.drawCircle(at(-30, r * 0.75), 3, lit);
      canvas.drawCircle(at(30, r * 0.75), 3, lit);
      return;
    }
    if (p.width > 0) {
      var rect = Rect.fromCircle(center: c, radius: r * 0.75);
      canvas.drawArc(
          rect,
          (p.angle - p.width / 2 - 90) * math.pi / 180,
          p.width * math.pi / 180,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = studio.on.withValues(alpha: 0.55));
    }
    canvas.drawCircle(at(p.angle, r * 0.75), 4.5, lit);
  }

  @override
  bool shouldRepaint(_RoomPainter old) =>
      old.speakers != speakers ||
      old.pan != pan ||
      old.placed != placed ||
      old.studio != studio;
}

class _KnobPainter extends CustomPainter {
  final double value;
  final ColorScheme colors;
  _KnobPainter(this.value, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 1;
    canvas.drawCircle(c, r, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = colors.outlineVariant);
    var angle = -math.pi / 2 + value * math.pi * 0.75;
    canvas.drawLine(
        c,
        c + Offset(math.cos(angle), math.sin(angle)) * (r - 2),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.onSurface);
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.value != value;
}

class _MasterStrip extends StatelessWidget {
  final MasterMix mix;
  final (double, double) level;
  final (double, double) peak;
  final MixerLook theme;
  final _MixWrite<MasterMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onOpenEq;
  final VoidCallback onOpenComp;
  final VoidCallback onOpenLoudness;
  final bool selected;
  final VoidCallback onSelect;

  const _MasterStrip({
    required this.mix,
    required this.level,
    required this.peak,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    required this.onOpenEq,
    required this.onOpenComp,
    required this.onOpenLoudness,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    TextStyle small([Color? c]) =>
        TextStyle(fontSize: 10, color: c ?? colors.onSurfaceVariant);
    return Listener(
      onPointerDown: (_) => onSelect(),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? colors.primary : colors.outline,
              width: selected ? 2 : 1),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("Master",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface)),
          const SizedBox(height: 6),
          _slot(
              theme,
              "EQ",
              mix.eq.on,
              CustomPaint(
                  size: const Size(40, 14),
                  painter: _MiniCurve(mix.eq, colors)),
              onOpenEq,
              key: const ValueKey("masterEqSlot")),
          const SizedBox(height: 4),
          _slot(
              theme,
              "Glue",
              mix.comp.on,
              Icon(Icons.circle,
                  size: 7,
                  color: mix.comp.on ? theme.studio.on : colors.outline),
              onOpenComp,
              key: const ValueKey("masterCompSlot")),
          const SizedBox(height: 4),
          _slot(
              theme,
              "Limit",
              mix.limiter,
              Text("${dbText(mix.ceilingDb)} dBTP", style: small()),
              () => onChanged(mix.copyWith(limiter: !mix.limiter)),
              key: const ValueKey("limiterSlot")),
          const SizedBox(height: 4),
          // The loudness the whole mix is aimed at, measured from its
          // own editor -- see _LoudnessEditor. Reaching it in an export is
          // a publish setting.
          _slot(
              theme,
              "Loudness",
              true,
              Text("${mix.target.round()} LUFS", style: small()),
              onOpenLoudness,
              key: const ValueKey("loudnessSlot")),
          const SizedBox(height: 6),
          Expanded(
            child: _Fader(
              db: mix.gainDb,
              level: level,
              peak: peak,
              theme: theme,
              wide: true,
              onChanged: (db, {transient = false}) =>
                  onChanged(mix.copyWith(gainDb: db), transient: transient),
              onCommit: onCommit,
            ),
          ),
          const SizedBox(height: 4),
          DbReading(
              db: mix.gainDb,
              textKey: const ValueKey("masterReading"),
              onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
              style: TextStyle(fontSize: 11, color: colors.onSurface)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The ducking and loudness editors
// ---------------------------------------------------------------------------

class _LoudnessEditor extends StatelessWidget {
  final MasterMix mix;
  final Loudness? measured;
  final bool measuring;
  final VoidCallback onMeasure;
  final MixerLook theme;
  final ValueChanged<MasterMix> onChanged;

  const _LoudnessEditor({
    required this.mix,
    required this.measured,
    required this.measuring,
    required this.onMeasure,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    String lufs(double v) => v.isFinite ? v.toStringAsFixed(1) : "−∞";
    Widget reading(String label, String value, Color? colour) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            SizedBox(
                width: 90,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11, color: colors.onSurfaceVariant))),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colour ?? colors.onSurface)),
          ]),
        );
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // A Wrap, not a Row: in the sidebar this is under 300 wide, and the
        // Measure button goes to the next line rather than off the edge.
        Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("Target",
                  style: TextStyle(fontSize: 11, color: colors.onSurface)),
              // Held to a width, the label shortened rather than run off.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: DropdownButton<double>(
                  key: const ValueKey("loudnessTarget"),
                  value: mix.target,
                  isDense: true,
                  isExpanded: true,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  items: [
                    for (var (v, label) in loudnessOptions(mix.target))
                      DropdownMenuItem(
                          value: v,
                          child: Text(label, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) onChanged(mix.copyWith(target: v));
                  },
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey("measure"),
                onPressed: measuring ? null : onMeasure,
                icon: const Icon(Icons.graphic_eq, size: 14),
                label: Text(measuring ? "Measuring…" : "Measure",
                    style: const TextStyle(fontSize: 11)),
              ),
            ]),
        const SizedBox(height: 8),
        if (measured case var m?) ...[
          reading(
              "Integrated",
              "${lufs(m.integrated)} LUFS",
              m.integrated > mix.target + 1
                  ? const Color(0xFFEF4D4D)
                  : m.integrated < mix.target - 2
                      ? theme.studio.on
                      : const Color(0xFF3FCF73)),
          reading("Range", "${m.range.toStringAsFixed(1)} LU", null),
          reading("True peak", "${lufs(m.truePeak)} dBTP",
              m.truePeak > mix.ceilingDb ? const Color(0xFFEF4D4D) : null),
        ] else
          Text(
              "Measure plays the timeline's sound through this mix into a "
              "broadcast loudness meter, as an export would.",
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text("Bringing an export to the target is set where it is published.",
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
      ]),
    );
  }
}

/// _Sends is a channel's sends: a dial for each return, by its letter --
/// dragged up for more, double-clicked for none.
class _Sends extends StatelessWidget {
  final ChannelMix mix;
  final List<ReturnChannel> returns;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  const _Sends({
    required this.mix,
    required this.returns,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 4,
        runSpacing: 2,
        children: [
          for (var (i, r) in returns.indexed)
            _SendDial(
              key: ValueKey("send-${r.id}"),
              letter: returnLetter(i),
              name: r.name,
              db: mix.sendDb(r.id),
              theme: theme,
              onChanged: (db, {transient = false}) =>
                  onChanged(mix.withSend(r.id, db), transient: transient),
              onCommit: onCommit,
            ),
        ],
      );
}

/// sendPosition and sendDb map a send onto its dial: nothing at the bottom,
/// then minus sixty to plus six round the rest of the travel.
double sendPosition(double? db) =>
    db == null ? 0 : ((db + 60) / 66).clamp(0.02, 1.0);
double? sendDbAt(double position) =>
    position <= 0.02 ? null : -60 + position.clamp(0.0, 1.0) * 66;

class _SendDial extends StatefulWidget {
  final String letter;
  final String name;
  final double? db;
  final MixerLook theme;
  final void Function(double? db, {bool transient}) onChanged;
  final VoidCallback onCommit;

  const _SendDial({
    required this.letter,
    required this.name,
    required this.db,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    super.key,
  });

  @override
  State<_SendDial> createState() => _SendDialState();
}

class _SendDialState extends State<_SendDial> {
  /// _from is where the drag started, and _was where the dial was then:
  /// the turn is measured from the press, not added up from each move --
  /// several moves can arrive between two frames, and summed against a dial
  /// not yet redrawn all but the last were lost.
  double _from = 0, _was = 0;

  @override
  Widget build(BuildContext context) {
    var db = widget.db;
    return Tooltip(
      message: "Send to ${widget.letter}"
          "${widget.name.isEmpty ? "" : " · ${widget.name}"}: "
          "${db == null ? "nothing" : "${dbText(db)} dB"}. Drag up for "
          "more; double-click for none.",
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: (d) {
          _from = d.globalPosition.dy;
          _was = sendPosition(widget.db);
        },
        onVerticalDragUpdate: (d) => widget.onChanged(
            sendDbAt(_was + (_from - d.globalPosition.dy) / 120),
            transient: true),
        onVerticalDragEnd: (_) => widget.onCommit(),
        onDoubleTap: () => widget.onChanged(null),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
              size: const Size(24, 24),
              painter: _ArcKnob(sendPosition(db), widget.theme.studio),
            ),
            Text(widget.letter,
                style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: widget.theme.studio.text)),
          ]),
        ),
      ),
    );
  }
}

/// _ArcKnob is a dial drawn as the studio draws them: a track round seven
/// o'clock to five, lit in the "on" colour as far as it is turned.
class _ArcKnob extends CustomPainter {
  final double value;
  final StudioColors colors;
  _ArcKnob(this.value, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 2;
    var rect = Rect.fromCircle(center: c, radius: r);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    var track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = colors.raised;
    canvas.drawArc(rect, start, sweep, false, track);
    if (value > 0.02) {
      canvas.drawArc(
          rect, start, sweep * value, false, track..color = colors.on);
    }
    var a = start + sweep * value;
    canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * 3,
        c + Offset(math.cos(a), math.sin(a)) * r,
        Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = colors.text);
  }

  @override
  bool shouldRepaint(_ArcKnob old) => old.value != value;
}

/// _ReturnStrip is a return: its letter and name, its devices -- each a
/// slot that opens it -- its EQ and compressor, pan, mute, fader and level.
class _ReturnStrip extends StatelessWidget {
  final String letter;

  /// compactPan is a short desk's: see _PanControl.compact.
  final bool compactPan;
  final ReturnChannel ret;
  final (double, double) level;
  final (double, double) peak;
  final MixerLook theme;
  final _MixWrite<ReturnChannel> onChanged;
  final VoidCallback onCommit;
  final ValueChanged<String?> onOpen;
  final VoidCallback onRemove;
  final bool selected;
  final VoidCallback onSelect;

  const _ReturnStrip({
    this.compactPan = false,
    required this.letter,
    required this.ret,
    required this.level,
    required this.peak,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    required this.onOpen,
    required this.onRemove,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var mix = ret.mix;
    void set(ChannelMix next, {bool transient = false}) =>
        onChanged(ret.copyWith(mix: next), transient: transient);
    var body = Container(
      width: 116,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text("$letter ",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.studio.on)),
          Expanded(
            child: ChannelNameEditor(
                name: ret.name.isEmpty ? "Return" : ret.name,
                theme: ThemeNotifier.of(context),
                color: colors.onSurface,
                onRename: (name) => onChanged(ret.copyWith(name: name)),
                weight: FontWeight.w600,
                textKey: const ValueKey("returnName"),
                fieldKey: const ValueKey("returnNameField")),
          ),
          InkWell(
            key: const ValueKey("removeReturn"),
            onTap: onRemove,
            child: Tooltip(
              message: "Take this return away. What is sent to it is kept "
                  "on the channels, for undo to find.",
              child:
                  Icon(Icons.close, size: 13, color: colors.onSurfaceVariant),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        for (var (i, d) in ret.devices.indexed) ...[
          _slot(
              theme,
              d.kind.label,
              d.on,
              Icon(Icons.circle,
                  size: 7, color: d.on ? theme.studio.on : colors.outline),
              () => onOpen("dev$i"),
              key: ValueKey("returnDevice-$i")),
          const SizedBox(height: 4),
        ],
        if (ret.devices.isEmpty) ...[
          _slot(
              theme,
              "Add a device",
              false,
              Icon(Icons.add, size: 12, color: colors.onSurfaceVariant),
              () => onOpen(null),
              key: const ValueKey("returnAddDevice")),
          const SizedBox(height: 4),
        ],
        _slot(
            theme,
            "EQ",
            mix.eq.on,
            CustomPaint(
                size: const Size(40, 14), painter: _MiniCurve(mix.eq, colors)),
            () => onOpen("eq"),
            key: const ValueKey("returnEq")),
        const SizedBox(height: 4),
        _slot(
            theme,
            "Comp",
            mix.comp.on,
            Icon(Icons.circle,
                size: 7, color: mix.comp.on ? theme.studio.on : colors.outline),
            () => onOpen("comp"),
            key: const ValueKey("returnComp")),
        const SizedBox(height: 6),
        _PanControl(
          compact: compactPan,
          channel: ret.id,
          mix: mix,
          theme: theme,
          onChanged: (m, {transient = false}) => set(m, transient: transient),
          onCommit: onCommit,
        ),
        const SizedBox(height: 6),
        _Toggle(
            key: const ValueKey("returnMute"),
            label: "M",
            on: mix.mute,
            onColor: theme.studio.arm,
            theme: theme,
            tooltip: "Mute this return: nothing sent to it is heard",
            onTap: () => set(mix.copyWith(mute: !mix.mute))),
        const SizedBox(height: 6),
        Expanded(
          child: _Fader(
            db: mix.gainDb,
            level: level,
            peak: peak,
            theme: theme,
            onChanged: (db, {transient = false}) =>
                set(mix.copyWith(gainDb: db), transient: transient),
            onCommit: onCommit,
          ),
        ),
        const SizedBox(height: 4),
        DbReading(
            db: mix.gainDb,
            textKey: const ValueKey("returnReading"),
            onSet: (db) => set(mix.copyWith(gainDb: db)),
            style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.onSurface)),
      ]),
    );
    return Listener(onPointerDown: (_) => onSelect(), child: body);
  }
}

/// _AddReturn is the button after the returns that adds another.
class _AddReturn extends StatelessWidget {
  final MixerLook theme;
  final VoidCallback onAdd;
  const _AddReturn({required this.theme, required this.onAdd});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: "Add a return: a reverb every channel can send to",
        child: InkWell(
          key: const ValueKey("addReturn"),
          onTap: onAdd,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.studio.edge),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, size: 18, color: theme.studio.muted),
              const SizedBox(height: 6),
              RotatedBox(
                quarterTurns: 3,
                child: Text("Return",
                    style: TextStyle(fontSize: 11, color: theme.studio.muted)),
              ),
            ]),
          ),
        ),
      );
}
