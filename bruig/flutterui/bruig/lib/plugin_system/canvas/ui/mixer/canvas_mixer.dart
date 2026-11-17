import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart'
    show transitionSoundPrefix;

import 'package:bruig/plugin_system/canvas/ui/timeline/row_header.dart'
    show motionColour, sceneColour, soundColour;
import 'package:bruig/plugin_system/canvas/ui/help_note.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show sectionColors;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show CanvasElement, newElementId;
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart'
    show MotionClip, MotionKind, crossFade;
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart'
    show MotionDeviceKind;
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart'
    show MotionPreset, presetsFor;
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/element_sound.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_lanes.dart'
    show MotionSlotDrag, motionLayerName;
import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_rows.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_player.dart'
    show MotionSlotState;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show InstrumentPart, MidiMonitor;
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_channels.dart'
    show ChannelNameEditor, ChannelNameEditorState;
import 'package:bruig/plugin_system/canvas/ui/timeline/scene_strip.dart'
    show sceneTint;
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart'
    show AssetKind, LibraryAsset;
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart'
    show isMidiId;
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart'
    show droppedAsset, droppedKind;
import 'package:bruig/plugin_system/canvas/ui/timeline/automation_lanes.dart'
    show automationColour;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/slot_face.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/slots_window.dart' show SlotKeys;
import 'package:bruig/plugin_system/canvas/ui/mixer/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_cards.dart' show StudioDrop;
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart'
    show limitKey;
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasDropdown;
import 'package:bruig/plugin_system/canvas/ui/sound/instrument_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/pitch_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/clip_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/source_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/speech_device.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter/scheduler.dart';

part 'canvas_mixer_desk.dart';
part 'canvas_mixer_editor.dart';

part 'canvas_mixer_strips.dart';
part 'canvas_mixer_motion.dart';
part 'canvas_mixer_buses.dart';
part 'canvas_slots_panel.dart';
part 'canvas_mixer_fader.dart';
part 'canvas_mixer_meters.dart';
part 'canvas_mixer_pan.dart';
part 'canvas_mixer_chain_view.dart';
part 'canvas_mixer_strip_controls.dart';
part 'canvas_mixer_strip_sound.dart';
part 'canvas_mixer_strip_channel.dart';
part 'canvas_mixer_strip_buses.dart';
part 'canvas_mixer_strip_rail.dart';
part 'canvas_mixer_strip_clips.dart';

// canvas_mixer.dart is the mixer panel: a column for each channel, return
// and the master (see canvas_mixer_strips.dart), resized by its top edge.
// The same widget is the effects panel (CanvasMixer.effects) and a section
// of a sound's settings (CanvasMixer.section). All it sets is saved with the
// canvas, except solo, and is defined in model/mix.dart.

/// mixerMinHeight is the least the panel is ever given, and
/// mixerDefaultHeight what it opens at; how short it goes with its bands as
/// they are is mixerLeastHeight.
const double mixerMinHeight = 56;

/// mixerLeastHeight is how short the mixer goes with its bands as
/// [controller]'s C, D and M say, each at its least, for the screen to stop
/// a drag at. Short of that, the clips and the devices scroll. [bare] is the
/// mixer at its smallest (see mixerSmallest), with no column heads.
double mixerLeastHeight(CanvasController controller, {bool? bare}) {
  bare ??= controller.mixerSmallest;
  var bands = 0.0;
  var showing = 0;
  for (var s in MixerSection.values) {
    var state = controller.bandState(s);
    if (state == BandState.hidden) continue;
    showing++;
    // No returns, no sends band at all.
    var n = controller.document.returns.length;
    var sends = math.max(
        sendsHeight(n),
        controller.narrowStrips.isNotEmpty
            ? sendsHeight(n, narrow: true)
            : 0.0);
    if (s == MixerSection.sends && sends == 0) {
      showing--;
      continue;
    }
    bands += switch (s) {
      MixerSection.clips => _clipsLeast,
      MixerSection.devices => _slotH,
      MixerSection.mixer => state == BandState.shown
          ? _mixerMinH
          : bare
              ? _bareMixerH
              : _miniMixerH,
      MixerSection.sends => sends,
    };
  }
  // The room along the top edge, the strips' bottom margin and a column's
  // edge and border, its head and the gaps over each band.
  return _edgeRoom +
      10 +
      14 +
      2 +
      (bare ? 0 : _headH) +
      _bandGap * showing +
      bands;
}

/// _edgeRoom is the room kept along a panel's top edge, which is dragged to
/// size it: no handle drawn, only the cursor to say so.
const double _edgeRoom = 4;

/// effectsMinHeight and effectsDefaultHeight are the effects panel's: the
/// devices are scaled to it, down to half their size.
const double effectsMinHeight = 200;

class CanvasMixer extends StatefulWidget {
  final CanvasController controller;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;

  /// resizable is whether it has a grip along its top. Not where its top is
  /// pinned: the effects over the mixer with the canvas put away, where the
  /// line between the two is the mixer's grip.
  final bool resizable;

  /// only is the one channel to show beside the master, by key, or null for
  /// every channel. With [embedded], the mixer is a section of a sound's
  /// settings rather than the panel over the canvas: no grip, no close.
  final String? only;
  final bool embedded;

  /// effects makes this the effects panel: the chain of one strip
  /// (controller.effectsOf) in a panel of its own, rather than the strips.
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
  /// _joinScroll scrolls the Scenes strip's joins by themselves: they are
  /// not on the cue rows the other columns scroll along.
  final ScrollController _joinScroll = ScrollController();
  late final Ticker _ticker;

  /// _board is every strip's meter. Only what shows a level listens to it:
  /// the desk is not built again thirty times a second.
  final _MeterBoard _board = _MeterBoard();

  /// _peaks is each strip's held peak, per side, in decibels; they fall back
  /// slowly, as a meter's peak hold does. _now is each one's level.
  Map<String, (double, double)> get _peaks => _board.peaks;
  Map<String, (double, double)> get _now => _board.now;

  /// _editing is the strip whose chain of effects is shown: in the effects
  /// panel the controller's effectsOf, and never among the strips, whose
  /// effects open the effects panel.
  String? get _editing =>
      widget.effects ? controller.effectsOf ?? controller.effectsChannel : null;

  /// _open opens [key]'s chain of effects on [what], unfolded and scrolled
  /// to.
  void _open(String key, _Opened what) {
    // In the effects panel, from here and from a sound's settings alike: the
    // strips stay where they are.
    controller.openEffects(key, device: _deviceOf(what));
  }

  void _scrollTo(String device) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      var at = _devices["${controller.effectsOf}|$device"]?.currentContext;
      if (at != null && at.mounted) {
        // Into view only if it is not: a scroll view takes no presses while it
        // moves, so scrolling to a device already in view would swallow the
        // first press on it. Otherwise its left edge (its switch and name) in
        // view, where a narrow chain cannot show it whole.
        var box = at.findRenderObject() as RenderBox?;
        var view =
            Scrollable.maybeOf(at)?.context.findRenderObject() as RenderBox?;
        if (box != null && view != null && box.hasSize && view.hasSize) {
          var left = box.localToGlobal(Offset.zero).dx -
              view.localToGlobal(Offset.zero).dx;
          if (left >= 0 && left + box.size.width <= view.size.width) return;
        }
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

  /// _devices finds each device in the chain, to scroll to it, by strip and
  /// id: a card kept across strips would keep the first strip's state, and
  /// write to it.
  final Map<String, GlobalKey> _devices = {};
  GlobalKey _deviceKey(String strip, String id) =>
      _devices["$strip|$id"] ??= GlobalKey();

  /// _addAt is where in [chain] a device put on goes: before the EQ and
  /// compressor where they end it, else at the end -- see chainOrder.
  static int _addAt(List<String> chain) {
    var at = chain.length;
    while (at > 0 && (chain[at - 1] == chainEq || chain[at - 1] == chainComp)) {
      at--;
    }
    return at;
  }

  /// _junction is the meter at step [i] of the open chain [key]: clicked,
  /// listened to from there, or an analyser put there.
  Widget _junction(int i, double h, MixerLook theme, String key) =>
      // Hidden from the Chain's ⋯: a gap between devices, no more.
      !controller.chainMeters
          ? const SizedBox(width: 4)
          : _metered(() => _Junction(
              i,
              i < _taps.length ? _taps[i] : (-90.0, -90.0),
              i < _tapPeaks.length ? _tapPeaks[i] : (-90.0, -90.0),
              theme.studio,
              h,
              latched: _clipped.contains((key, i)),
              onClear: () =>
                  setState(() => _clipped.removeWhere((x) => x.$1 == key)),
              listening: controller.listening == (key, i),
              onListen: () => controller.listenAt(
                  key, controller.listening == (key, i) ? null : i),
              onAnalyser: (kind) =>
                  controller.insertDevice(key, MixDevice(kind), i)));

  /// _metered is [make]'s widget built again as the meters move: one that
  /// shows a level as more than a bar (see _MeterPainter), or many of them.
  Widget _metered(Widget Function() make) =>
      ListenableBuilder(listenable: _board, builder: (context, _) => make());

  Loudness? _measured;
  bool _measuring = false;

  /// _clipped are the joins that have clipped, by strip and place: lit until
  /// cleared from a join's menu.
  final Set<(String, int)> _clipped = {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_meter)..start();
    controller.addListener(_wakeIfPlaying);
    controller.addListener(_changed);
    controller.keysHeld.addListener(_wakeIfPlaying);
  }

  /// The meters move only while there is sound: a ticker redraws the whole
  /// window every refresh, so it runs while something plays and rests once
  /// the peaks have fallen. At rest a slow check wakes it for sound that
  /// starts without the timeline: a key played, a preview.
  Timer? _resting;

  void _wake() {
    _resting?.cancel();
    _resting = null;
    if (_ticker.isActive) return;
    // A ticker's time restarts from nought: a _last kept from the run before
    // would hold every frame back until this run had lasted as long.
    _last = Duration.zero;
    _ticker.start();
  }

  void _rest() {
    if (_ticker.isActive) _ticker.stop();
    _resting ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      // Sound anywhere: the master, or any channel -- an instrument played
      // live is heard on its channel first.
      var loudest = [
        controller.levels(),
        for (var c in controller.timelineChannels) controller.levels(c.key),
      ].fold(0.0, (m, lr) => math.max(m, math.max(lr.$1, lr.$2)));
      if (_sounding || gainToDb(loudest) > _floor) _wake();
    });
  }

  bool get _sounding => controller.playing || controller.sessionActive;

  /// _deskChanges builds the desk again on every change the canvas tells of
  /// but the playhead moving, which it follows only where a strip is
  /// automated: the desk is not built at every frame of play. The meters and
  /// the slots have their own beats (_board, _sessionPulse).
  final _MeterBoard _deskChanges = _MeterBoard();
  String _channelsWere = "";
  bool _sessionWas = false;

  void _changed() {
    if (controller.notifyingPlayhead && !controller.mixFollowsPlayhead) {
      // A channel come or gone under the playhead is still shown.
      var now = [for (var l in controller.timelineChannels) l.key].join("|");
      if (now == _channelsWere) return;
    }
    _deskChanges.moved();
  }

  /// _wakeIfPlaying wakes the meters on any change the canvas tells of -- a
  /// key pressed, a clip launched -- rather than waiting for the slow check.
  void _wakeIfPlaying() => _wake();

  /// _floor is as quiet as a meter shows, in decibels.
  static const double _floor = -80;

  /// _clipScrolls keeps the columns' clip slots scrolled together.
  final _ClipScrolls _clipScrolls = _ClipScrolls();

  @override
  void dispose() {
    controller.removeListener(_wakeIfPlaying);
    controller.keysHeld.removeListener(_wakeIfPlaying);
    controller.removeListener(_changed);
    _joinScroll.dispose();
    _deskChanges.dispose();
    _resting?.cancel();
    _clipScrolls.dispose();
    _ticker.dispose();
    _board.dispose();
    _chainScroll.dispose();
    super.dispose();
  }

  /// _taps and _tapPeaks are the open chain's levels between its devices,
  /// in decibels, and their held peaks: see CanvasController.deviceLevels.
  List<(double, double)> _taps = const [];
  List<(double, double)> _tapPeaks = const [];

  /// _tapsOf is the strip [_taps] and [_tapPeaks] were measured on: another
  /// opened starts its joins afresh, not from the last one's held peaks.
  String? _tapsOf;

  /// _last and _meter read every strip's level, about thirty times a second.
  Duration _last = Duration.zero;
  void _meter(Duration now) {
    if (now - _last < const Duration(milliseconds: 33)) return;
    _last = now;
    var channels = {
      for (var channel in controller.timelineChannels) channel.key: channel,
    };
    var returns = {for (var r in controller.document.returns) r.id};
    // The master's chain open: each speaker's level too, for its Output.
    var speakers = _editing == _master
        ? [
            for (var c = 0;
                c < controller.document.audio.speakers.channels;
                c++)
              speakerLevelKey(c)
          ]
        : const <String>[];
    var keys = [
      ...channels.keys,
      ...returns,
      if (_sceneShown) sceneBusKey,
      _master,
      ...speakers,
      // How far the master's limiter is turning down, for its screen.
      if (_editing == _master) limitKey,
    ];
    var moved = false;
    for (var key in keys) {
      // A channel is as loud as its strip: every sound on it is mixed there.
      var (l, r) =
          key == _master ? controller.levels() : controller.levels(key);
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
    // The open chain's meters between devices: a channel's, a return's,
    // the scene bus's and the master's, each measured at every step.
    var open = _editing;
    if (open != null &&
        (channels.containsKey(open) ||
            controller.returnOf(open) != null ||
            open == _master ||
            open == sceneBusKey)) {
      var taps = [
        for (var (l, r) in controller.deviceLevels(open))
          (gainToDb(l), gainToDb(r))
      ];
      if (_tapsOf != open) {
        _tapsOf = open;
        _taps = _tapPeaks = const [];
      }
      if (taps.length != _taps.length) {
        moved = true;
      } else {
        for (var i = 0; i < taps.length && !moved; i++) {
          if ((taps[i].$1 - _taps[i].$1).abs() > 0.3 ||
              (taps[i].$2 - _taps[i].$2).abs() > 0.3) {
            moved = true;
          }
        }
      }
      // A join that has clipped stays lit, until its lights are cleared.
      for (var (i, t) in taps.indexed) {
        if ((t.$1 >= 0 || t.$2 >= 0) && _clipped.add((open, i))) moved = true;
      }
      _tapPeaks = [
        for (var (i, t) in taps.indexed)
          i < _tapPeaks.length
              ? (
                  math.max(t.$1, _tapPeaks[i].$1 - 0.66),
                  math.max(t.$2, _tapPeaks[i].$2 - 0.66)
                )
              : t
      ];
      _taps = taps;
    }
    // Clips waiting for a bar blink and playing ones go round, while the
    // session plays, once more as it stops, and while the canvas plays (a
    // clip on the timeline lights its slot; see motionSlotState).
    var session = controller.sessionActive ||
        controller.playing ||
        controller.motionPlayer.playing;
    if (session || _sessionWas) _sessionPulse.moved();
    _sessionWas = session;
    if (moved && mounted) _board.moved();
    // Nothing playing, no slot waiting and every meter down: rest.
    if (!moved &&
        !session &&
        !_sounding &&
        _peaks.values.every((p) => math.max(p.$1, p.$2) <= _floor)) {
      _rest();
    }
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

  /// build zooms the desk to the reader's text size, as Ableton's zoom does:
  /// the desk is laid out at its own sizes and scaled as a whole, so labels
  /// fit at large text sizes. Faders, curves and dials read the pointer in
  /// their own coordinates, so they stay under it.
  @override
  // No hover tips in the mixer: a "?" explains. The effects keep theirs, as
  // does a sound's own settings.
  Widget build(BuildContext context) {
    var built = _built ??= _build(context);
    if (widget.effects || widget.embedded) return built;
    return TooltipVisibility(visible: false, child: built);
  }

  /// _built is the desk as last built, handed back while nothing it shows
  /// has changed: its holder is built at every frame of play. Dropped on its
  /// own setState or a change in what it is given or inherits; _deskChanges
  /// builds it again from inside.
  Widget? _built;

  @override
  void setState(VoidCallback fn) {
    _built = null;
    super.setState(fn);
  }

  @override
  void didUpdateWidget(CanvasMixer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.height != widget.height ||
        old.only != widget.only ||
        old.embedded != widget.embedded ||
        old.effects != widget.effects ||
        old.resizable != widget.resizable) {
      _built = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  Widget _build(BuildContext context) {
    var zoom = MediaQuery.textScalerOf(context).scale(1);
    // Never so far that the desk is left less than its least height: a
    // mixer folded to one line, zoomed, would be too short for its names.
    if ((zoom - 1).abs() < 0.01 || zoom <= 0) return _desk(context, 1);
    if (zoom > 1) {
      zoom = math.max(
          1.0,
          math.min(
              zoom,
              widget.height /
                  (widget.effects ? effectsMinHeight : mixerMinHeight)));
    }
    // Held to its own size either way: zoomed, or (with no room to zoom)
    // drawn at the size it was laid out for.
    Widget unscaled(double zoom) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: Builder(builder: (context) => _desk(context, zoom)),
        );
    // Zoomed to one (the panel dragged down to its least) it is still laid
    // out the same way: rebuilt unwrapped as it crossed, every device would
    // move to a new desk, and a tooltip showing as it moved asserts.
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

  // ---- canvas_mixer_editor.dart -------------------------------------------

  /// _roomForAll is whether an editor [box] wide has room for all three
  /// columns of its settings (690 together) and what it edits, at the desk's
  /// own size (see build).
  static bool _roomForAll(BoxConstraints box) => box.maxWidth >= 690 + 480;

  final ScrollController _chainScroll = ScrollController();

  /// _chainOffsets are where each chain was scrolled to when it was left,
  /// by its key and view; _chainKey the one shown.
  final Map<String, double> _chainOffsets = {};
  String? _chainKey;
}

typedef _MixWrite<T> = void Function(T next, {bool transient});

/// _PinnedRight lays out the mixer's two parts: [right] (the returns, the
/// scene's bus, the master, the rail) as wide as it is, up to all but
/// [leftLeast] of the room (at most half of it, where the room is narrower
/// still), and [left] (the channels) in what is left.
class _PinnedRight extends MultiChildLayoutDelegate {
  static const left = 0, right = 1;
  final double leftLeast;
  _PinnedRight({required this.leftLeast});

  @override
  void performLayout(Size size) {
    var keep = math.min(leftLeast, size.width / 2);
    var most = math.max(0.0, size.width - keep);
    var pinned = layoutChild(
        right,
        BoxConstraints(
            maxWidth: most, minHeight: size.height, maxHeight: size.height));
    positionChild(right, Offset(size.width - pinned.width, 0));
    layoutChild(
        left,
        BoxConstraints.tightFor(
            width: size.width - pinned.width, height: size.height));
    positionChild(left, Offset.zero);
  }

  @override
  bool shouldRelayout(_PinnedRight old) => old.leftLeast != leftLeast;
}

String _transitionsSaid(int n) =>
    n <= 0 ? "no transitions" : "$n transition${n == 1 ? "" : "s"}";
