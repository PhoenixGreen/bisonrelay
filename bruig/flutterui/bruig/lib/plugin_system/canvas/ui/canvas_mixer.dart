import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart'
    show ChannelNameEditor;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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
    super.key,
  }) : effects = false;

  /// CanvasMixer.effects is the effects panel: one strip's chain, over the
  /// mixer, opened from the timeline or from a strip's slot.
  const CanvasMixer.effects({
    required this.controller,
    required this.height,
    required this.onResize,
    required this.onClose,
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
    var keys = [...channels.keys, _master];
    var moved = false;
    for (var key in keys) {
      // A channel is as loud as its strip: every sound on it is mixed there.
      var (l, r) = key == _master
          ? controller.levels()
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

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
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
            widget.height < mixerCompactBelow;
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
          // panel, which always shows a chain.
          if (lane == null) editing = widget.effects ? _master : null;
        }
        // No scroll bars, on the strips or the chain: they scroll with the
        // wheel or the trackpad, and a bar was a stripe across the meters.
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: theme.colors.surfaceContainerLow.withValues(alpha: 0.97),
              border: Border(
                  top:
                      BorderSide(color: theme.colors.outlineVariant, width: 1)),
            ),
            child: Column(children: [
              // The grip: dragged up, the mixer is taller. Over the canvas, so
              // it never moves the design, whatever its height.
              if (!widget.embedded)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) =>
                      widget.onResize(widget.height - d.delta.dy),
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
        );
      },
    );
  }

  /// _compact is the mixer at its shortest: a line of channels, each its
  /// name -- picked with a press, renamed with a double-click -- over its
  /// meter on its side, and the master's at the end.
  Widget _compact(ThemeNotifier theme, List<TimelineChannel> lanes) {
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
                painter: _MeterPainter(
                    _now[key] ?? (-90, -90), _peaks[key] ?? (-90, -90), colors,
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
                      theme: theme,
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

  Widget _strips(ThemeNotifier theme, List<TimelineChannel> lanes) {
    var master = controller.document.masterMix;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: lanes.isEmpty
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
                          name: lane.name,
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
                        ),
                      ),
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
  Widget _editor(ThemeNotifier theme, String key, TimelineChannel? lane) {
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
      var compFirst = isMaster ? master.compFirst : lane!.mix.compFirst;
      var skin = DeviceSkin.themed(theme.colors);
      var chain = <Widget>[
        ...(compFirst ? [comp, eq] : [eq, comp]),
        if (!isMaster)
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
        if (!isMaster)
          device("meter",
              // The channel's own strip, as on the mixer -- its panning,
              // mute and solo, fader and meter -- under its name.
              (f, fold) {
            var level = _now[key] ?? (-90.0, -90.0);
            var peak = _peaks[key] ?? (-90.0, -90.0);
            var mix = lane!.mix;
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
                  painter: _MeterPainter(level, peak, theme.colors)),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(children: [
                  _Balance(
                    value: mix.balance,
                    theme: theme,
                    onChanged: (v, {transient = false}) =>
                        write(mix.copyWith(balance: v), transient: transient),
                    onCommit: controller.endInteraction,
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: _Toggle(
                          key: const ValueKey("meterMute"),
                          label: "M",
                          on: mix.mute,
                          onColor: const Color(0xFFB23B3B),
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
                          onColor: const Color(0xFFB28A1F),
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
  final ThemeNotifier theme;
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
                  size: Size(26, h),
                  painter: _FaderPainter(db, theme.colors),
                ),
              ),
            ),
            const SizedBox(width: 4),
            CustomPaint(
              size: Size(wide ? 22 : 14, h),
              painter: _MeterPainter(level, peak, theme.colors),
            ),
          ]);
        },
      );
}

class _FaderPainter extends CustomPainter {
  final double db;
  final ColorScheme colors;
  _FaderPainter(this.db, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var cx = size.width / 2;
    canvas.drawRRect(
        RRect.fromLTRBR(
            cx - 1.5, 6, cx + 1.5, size.height - 6, const Radius.circular(2)),
        Paint()..color = colors.surfaceContainerHighest);
    // Unity, marked: the one place on a fader everybody wants to find.
    var unity = 6 + faderPosition(0) * (size.height - 12);
    canvas.drawLine(Offset(cx - 9, unity), Offset(cx - 4, unity),
        Paint()..color = colors.outline);
    var y = 6 + faderPosition(db) * (size.height - 12);
    var cap = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, y), width: 24, height: 14),
        const Radius.circular(3));
    canvas.drawRRect(cap, Paint()..color = colors.onSurfaceVariant);
    canvas.drawLine(
        Offset(cx - 9, y), Offset(cx + 9, y), Paint()..color = colors.surface);
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.db != db;
}

class _MeterPainter extends CustomPainter {
  final (double, double) level;
  final (double, double) peak;
  final ColorScheme colors;

  /// horizontal lays it on its side: nought on the right, the left side's
  /// bar above the right's.
  final bool horizontal;
  _MeterPainter(this.level, this.peak, this.colors, {this.horizontal = false});

  /// A meter reads from minus sixty to nought, with the last six decibels in
  /// amber and the top in red -- the colours of every meter anybody has seen.
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
      canvas.drawRect(well, Paint()..color = colors.surfaceContainerHighest);
      var top = well.bottom - _fill(db) * well.height;
      canvas.drawRect(
          Rect.fromLTRB(x, top, x + w, well.bottom),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xFF3FCF73),
                Color(0xFF3FCF73),
                Color(0xFFF0B43C),
                Color(0xFFEF4D4D)
              ],
              stops: [0, 0.8, 0.9, 1],
            ).createShader(well));
      var peakY = well.bottom - _fill(held) * well.height;
      canvas.drawRect(Rect.fromLTWH(x, peakY - 1, w, 2),
          Paint()..color = colors.onSurface.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.level != level || old.peak != peak;
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

Widget _slot(ThemeNotifier theme, String label, bool on, Widget trailing,
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
  final ChannelMix mix;
  final bool editable;
  final bool soloed;
  final (double, double) level;
  final (double, double) peak;
  final ThemeNotifier theme;
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

  const _ChannelStrip({
    required this.name,
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
      width: 104,
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
            theme: theme,
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
                size: 7,
                color: mix.comp.on ? const Color(0xFFF0B43C) : colors.outline),
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
        const SizedBox(height: 6),
        _Balance(
          value: mix.balance,
          theme: theme,
          onChanged: (v, {transient = false}) =>
              onChanged(mix.copyWith(balance: v), transient: transient),
          onCommit: onCommit,
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: _Toggle(
                key: const ValueKey("mute"),
                label: "M",
                on: mix.mute,
                onColor: const Color(0xFFB23B3B),
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
                onColor: const Color(0xFFB28A1F),
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
  final ThemeNotifier theme;
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
  final ThemeNotifier theme;
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
  final ThemeNotifier theme;
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
                  color:
                      mix.comp.on ? const Color(0xFFF0B43C) : colors.outline),
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
  final ThemeNotifier theme;
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
                    for (var (v, label) in loudnessTargets)
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
                      ? const Color(0xFFF0B43C)
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
