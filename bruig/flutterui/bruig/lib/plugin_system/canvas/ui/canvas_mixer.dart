import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart'
    show transitionSoundPrefix;

import 'package:bruig/plugin_system/canvas/ui/row_header.dart'
    show motionColour;
import 'package:bruig/plugin_system/canvas/ui/help_note.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show sectionColors;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show CanvasElement, newElementId;
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart'
    show ElementMotion, MotionClip, MotionKind;
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart'
    show MotionPreset, presetsFor;
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart'
    show MotionSlotDrag, motionKindColours;
import 'package:bruig/plugin_system/canvas/ui/canvas_rows.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart'
    show MotionSlotState;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show InstrumentPart, MidiMonitor;
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart'
    show ChannelNameEditor;
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart'
    show AssetKind, LibraryAsset;
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart'
    show isMidiId;
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart'
    show droppedAsset, droppedKind;
import 'package:bruig/plugin_system/canvas/ui/automation_lanes.dart'
    show automationColour;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/slots_window.dart' show SlotKeys;
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart' show StudioDrop;
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart'
    show limitKey;
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasDropdown;
import 'package:bruig/plugin_system/canvas/ui/instrument_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/pitch_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/clip_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/source_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/speech_device.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter/scheduler.dart';

part 'canvas_mixer_strips.dart';
part 'canvas_mixer_motion.dart';
part 'canvas_mixer_buses.dart';

// canvas_mixer.dart is the mixer panel: a column for each channel, each
// return and the master (the columns are canvas_mixer_strips.dart), resized
// by dragging its top edge. The same widget is the effects panel, one
// column's chain of devices (CanvasMixer.effects), and a section of a
// sound's settings (CanvasMixer.section).
//
// Everything it sets is saved with the canvas except solo, which is for
// listening (see CanvasController.solo). What it sets is defined in
// model/mix.dart, in terms the editor and an export both follow.

/// mixerMinHeight is the least the panel is ever given, and
/// mixerDefaultHeight what it opens at; how short it goes with its bands as
/// they are is mixerLeastHeight.
const double mixerMinHeight = 56;
const double mixerDefaultHeight = 320;

/// mixerLeastHeight is how short the mixer goes with its bands as
/// [controller]'s C, D and M say, each at its least (a slot of clips and its
/// stop, a device slot, the fader at its least or the mixer minimised as a
/// row), for the screen to stop a drag at. Short of that, the clips and the
/// devices scroll.
///
/// [bare] is the mixer at its smallest (see mixerSmallest), which drops the
/// columns' heads; by default, whether it is.
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
const double effectsDefaultHeight = 340;

class CanvasMixer extends StatefulWidget {
  final CanvasController controller;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;

  /// resizable is whether it has a grip along its top to be dragged taller
  /// by. Not where its top is pinned (the effects over the mixer with the
  /// canvas put away, where the line between the two is the mixer's grip).
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

  /// _board is every strip's meter. It notifies as they move, and only what
  /// shows a level listens: the desk is not built again thirty times a
  /// second for them (Ken's systems review, 2026-11-08).
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
  /// id: "eq" on one strip is not the same card as on another, and a card
  /// kept across strips would keep the first one's state (Ken's systems
  /// review, 2026-11-08: the EQ went on writing to the master).
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

  /// _clipped are the joins that have clipped, by strip and place: their
  /// lights kept lit, as the prototype's, until cleared from a join's menu.
  final Set<(String, int)> _clipped = {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_meter)..start();
    controller.addListener(_wakeIfPlaying);
    controller.addListener(_changed);
    controller.keysHeld.addListener(_wakeIfPlaying);
  }

  /// The meters move only while there is sound to show: a ticker asks for a
  /// frame on every screen refresh, the whole window drawn each time, so it
  /// runs while something plays and rests once the peaks have fallen. At
  /// rest a slow check (no frames) wakes it for sound that starts without
  /// the timeline: a key played, a preview.
  Timer? _resting;

  void _wake() {
    _resting?.cancel();
    _resting = null;
    if (_ticker.isActive) return;
    // A ticker's time starts again from nought each start: _last, from the
    // run before, held every frame back until this run had lasted as long
    // -- Ken's strip, master and panner meters standing dead while the
    // devices' own (fresh) meters moved.
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

  /// _deskChanges tells the desk to be built again: on every change the
  /// canvas tells of but the playhead moving on, which it follows only where
  /// a strip is automated (Ken's systems review, 2026-11-08: the whole mixer
  /// was built at every frame of play). The meters and the slots have their
  /// own beats (_board, _sessionPulse).
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

  /// _wakeIfPlaying wakes the meters on any change the canvas tells of --
  /// a key pressed, a clip launched, playing -- rather than waiting for the
  /// slow check: Ken's channel meters stood still while he played keys. At
  /// rest again at the next tick if nothing is heard.
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
    // Clips waiting for a bar blink, and playing ones go round: the slots
    // listen for it, not the desk.
    // And once more as the session stops: its last slots shown stopped.
    var session = controller.sessionActive;
    if (session || _sessionWas) _sessionPulse.moved();
    _sessionWas = session;
    if (moved && mounted) _board.moved();
    // Nothing playing -- no slot waiting either -- and every meter down:
    // rest.
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

  /// build zooms the desk to the reader's text size, as Ableton's zoom does.
  ///
  /// The strips, devices and their screens are drawn at a desk's own sizes,
  /// and at the larger text sizes their labels ran out of them, so the desk is
  /// laid out at the ordinary size and scaled as a whole. The faders, curves
  /// and dials read the pointer in their own coordinates, so they stay under
  /// it.
  @override
  // No hover tips in the mixer (the approved design): a "?" explains. The
  // effects keep theirs, as does a sound's own settings.
  Widget build(BuildContext context) {
    var built = _built ??= _build(context);
    if (widget.effects || widget.embedded) return built;
    return TooltipVisibility(visible: false, child: built);
  }

  /// _built is the desk as last built, handed back while nothing it shows
  /// has changed: whatever holds the mixer is built again at every frame of
  /// play, and the desk need not be with it. Let go of on a change of its
  /// own (setState), of what it is given, or of what it inherits -- and the
  /// desk's own beat (_deskChanges) builds it again from inside.
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

  /// _desk is the mixer, or the effects, laid out at [zoom]'s share of its
  /// height (see build).
  Widget _desk(BuildContext context, double zoom) {
    var theme = MixerLook.of(context);
    return ListenableBuilder(
      listenable: _deskChanges,
      builder: (context, _) {
        mixerDeskBuilds++;
        _channelsWere =
            [for (var l in controller.timelineChannels) l.key].join("|");
        var lanes = [
          for (var l in controller.timelineChannels)
            if (widget.only == null || l.key == widget.only) l,
        ];
        var editing = _editing;
        var focused = false;
        if (widget.effects &&
            controller.effectsFocusCount != _focusSeen &&
            controller.effectsFocus != null) {
          _focusSeen = controller.effectsFocusCount;
          _scrollTo(controller.effectsFocus!);
          focused = true;
        }
        // Each chain where it was left (Ken): switching channels and back,
        // the meters he was watching are still in view -- unless a device
        // was asked for, which is scrolled to.
        var chainKey =
            editing == null ? null : "$editing|${controller.speechShown}";
        if (widget.effects && chainKey != _chainKey) {
          if (_chainKey case var was? when _chainScroll.hasClients) {
            _chainOffsets[was] = _chainScroll.offset;
          }
          _chainKey = chainKey;
          var back = chainKey == null ? null : _chainOffsets[chainKey];
          if (!focused) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_chainScroll.hasClients) return;
              _chainScroll.jumpTo((back ?? 0)
                  .clamp(0.0, _chainScroll.position.maxScrollExtent));
            });
          }
        }
        TimelineChannel? lane;
        if (editing != null && editing != _master) {
          lane = lanes.where((l) => l.key == editing).firstOrNull;
          // A channel gone from the timeline: the master's, in the effects panel,
          // which always shows a chain. A return is not on the timeline and keeps
          // its own.
          if (lane == null &&
              controller.returnOf(editing) == null &&
              editing != sceneBusKey) {
            editing = widget.effects ? _master : null;
          }
        }
        // No scroll bars, on the strips or the chain: they scroll with the wheel
        // or the trackpad, and a bar would be a stripe across the meters.
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
                child: Stack(children: [
                  Positioned.fill(
                    child: Column(children: [
                      if (!widget.embedded && widget.resizable)
                        const SizedBox(height: _edgeRoom),
                      if (widget.embedded) const SizedBox(height: 8),
                      Expanded(
                        child: editing == null
                            ? _leastOrScrolled(_strips(theme, lanes))
                            : _editor(theme, editing, lane),
                      ),
                    ]),
                  ),
                  // Its top edge, dragged: taller or shorter. The drag is in the
                  // desk's own, zoomed, coordinates, put back into the screen's so
                  // the edge stays with the pointer.
                  if (!widget.embedded && widget.resizable)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          supportedDevices: dragPointers,
                          key: ValueKey(
                              widget.effects ? "effectsGrip" : "mixerGrip"),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (d) => widget
                              .onResize(widget.height - d.delta.dy * zoom),
                        ),
                      ),
                    ),
                ]),
              ),
            ));
      },
    );
  }

  /// _leastOrScrolled is [strips] given at least their least height (see
  /// mixerLeastHeight) and scrolled where the panel is shorter, as a window
  /// can be.
  Widget _leastOrScrolled(Widget strips) => LayoutBuilder(builder: (c, box) {
        var least = mixerLeastHeight(controller) - _edgeRoom;
        if (widget.embedded || box.maxHeight >= least) return strips;
        return SingleChildScrollView(
            child: SizedBox(height: least, child: strips));
      });

  Widget _strips(MixerLook theme, List<TimelineChannel> lanes) {
    var master = controller.document.masterMix;
    var returns = controller.document.returns;
    var narrow = controller.narrowStrips;
    // In a sound's own settings: its devices and its fader, not clips.
    var states = widget.embedded
        ? const {
            MixerSection.clips: BandState.hidden,
            MixerSection.devices: BandState.shown,
            MixerSection.mixer: BandState.shown,
            MixerSection.sends: BandState.shown,
          }
        : {for (var s in MixerSection.values) s: controller.bandState(s)};
    var showReturns = !widget.embedded && controller.returnsShown;
    // Every band is one height in every column: the tallest column's devices
    // set it, so the faders all start on one line.
    var devicesWanted = [
      for (var l in lanes)
        _ChannelStrip.devicesWanted(
            part: controller.instrumentOf(l.key)?.instrument,
            devices: l.mix.devices.length +
                (l.mix.speech == null ? 0 : 1) +
                (l.mix.vocaliser == null ? 0 : 1)),
      _MasterStrip.devicesWanted(master.devices.length),
      if (showReturns)
        for (var r in returns) _ReturnStrip.devicesWanted(r),
    ].reduce(math.max);
    // Three slots, while the clips and the mixer show whole: a longer chain
    // scrolls rather than squeezing them.
    var devicesCap = _slotsHeight(3);
    // The sends: as tall as the most dials take (a narrow column's, two to a
    // row, where there is one).
    var sendsH = widget.embedded && lanes.isEmpty
        ? 0.0
        : math.max(
            sendsHeight(returns.length),
            lanes.any((l) => narrow.contains(l.key))
                ? sendsHeight(returns.length, narrow: true)
                : 0.0);
    // The elements, outside a sound's own settings and the effects; and
    // which of the channels are theirs.
    // The rows every panel shows (see canvas_rows.dart): each element's strip
    // with its own sound's beside it, then the sounds that are nobody's --
    // in the timeline's order, so a row is in the same place in both.
    var canvasRows = widget.embedded || widget.effects
        ? const <CanvasRow>[]
        : canvasRowsOf(controller);
    var rows = [
      for (var r in canvasRows)
        if (r.element case var e?) e
    ];
    var ownedKeys = {
      for (var r in canvasRows)
        if (r.element != null)
          for (var c in r.channels) c.key
    };
    // The sounds that are nobody's, each with its place among the strips'
    // lanes: in the rows' order, or -- with no rows, in a sound's own
    // settings or the effects -- every lane as it comes.
    var loose = canvasRows.isEmpty
        ? [
            for (var (i, l) in lanes.indexed)
              if (!ownedKeys.contains(l.key)) (i, l)
          ]
        : [
            for (var r in canvasRows)
              if (r.element == null)
                for (var c in r.channels)
                  if (lanes.indexWhere((l) => l.key == c.key) case var i
                      when i >= 0)
                    (i, lanes[i])
          ];
    var show = controller.timelineShow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: LayoutBuilder(builder: (context, box) {
        // At its smallest: no heads, and no rail of bands.
        var bare =
            !widget.embedded && !widget.effects && controller.mixerSmallest;
        // The column's height inside its padding and its edge.
        // Elements with strips: every column a motion half over its sound
        // half, every slot row a motion part over its sound part.
        var withMotion = rows.isNotEmpty && show != TimelineShow.sound;
        // Each element's own sound's place among the lanes, -1 for none.
        var ownLane = {
          for (var e in rows)
            e.id: lanes.indexWhere((l) => l.key == elementSoundKey(e.id))
        };
        var bands = _Bands.fit(
            box.maxHeight - 14, states, devicesWanted, devicesCap,
            sendsH: sendsH,
            bare: bare,
            clipRows: controller.slotsShown,
            motion: withMotion);
        // The channels on the left, scrolled; the returns, the scene's bus,
        // the master and the rail pinned on the right as wide as they are --
        // or, where that leaves no room for a channel, scrolled themselves.
        return CustomMultiChildLayout(
            delegate: _PinnedRight(leftLeast: 124),
            children: [
              LayoutId(
                id: _PinnedRight.left,
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
                                fontSize: 12,
                                color: theme.colors.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // The elements' strips first, as the timeline has
                          // their rows: their animation slots on the same cue
                          // rows, and each one's own sound beside it.
                          // One strip each (the approved design): its
                          // motion half over its own sound's half, its motion
                          // slots over its sound slots; with no sound of its
                          // own, or the motion alone shown, its motion strip.
                          for (var e in rows)
                            if (show != TimelineShow.animation &&
                                (ownLane[e.id] ?? -1) >= 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                // The element's strip, with its motion;
                                // only the sound shown, the sound's alone.
                                child: KeyedSubtree(
                                  key: show == TimelineShow.sound
                                      ? null
                                      : ValueKey("motionStrip-${e.id}"),
                                  child: _channelStrip(theme,
                                      lanes[ownLane[e.id]!], ownLane[e.id]!,
                                      bands,
                                      element: show == TimelineShow.sound
                                          ? null
                                          : e),
                                ),
                              )
                            else if (show != TimelineShow.sound)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _elementStrip(controller, theme, e,
                                    bands, _clipScrolls.of("motion:${e.id}")),
                              ),
                          // Then the sounds that are nobody's, the All
                          // group's last; none shows only the animation.
                          if (show != TimelineShow.animation)
                            for (var (i, lane) in loose)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _channelStrip(theme, lane, i, bands),
                              ),
                        ],
                      ),
              ),
              LayoutId(
                id: _PinnedRight.right,
                child: SingleChildScrollView(
                  key: const ValueKey("mixerPinned"),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The returns, pinned beside the master as Ableton's are, in view
                        // however far the channels are scrolled. Never more than half the
                        // width; past that they scroll among themselves.
                        if (showReturns) ...[
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: box.maxWidth / 2),
                            child: SingleChildScrollView(
                              key: const ValueKey("returnsPinned"),
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var (i, ret) in returns.indexed)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child:
                                            _returnStrip(theme, ret, i, bands),
                                      ),
                                    if (returns.length < maxReturns)
                                      _AddReturn(
                                          theme: theme,
                                          onAdd: () {
                                            controller.beginInteraction();
                                            controller.addReturn();
                                            controller.endInteraction();
                                          }),
                                  ]),
                            ),
                          ),
                        ],
                        // The scene's bus, between what is in the scene and the master:
                        // where there is a master's or another scene's to tell it from.
                        if (_sceneShown) ...[
                          const SizedBox(width: 8),
                          _SceneStrip(
                            key: const ValueKey("strip-scene"),
                            name: controller.document.scene.saysAt(
                                controller.document.at,
                                controller.document.kind),
                            mix: controller.sceneBus,
                            chain: controller.chainOf(sceneBusKey),
                            meter: _Meter(_board, sceneBusKey),
                            theme: theme,
                            bands: bands,
                            narrow: narrow.contains(sceneBusKey),
                            onNarrow: () =>
                                controller.toggleNarrow(sceneBusKey),
                            onChanged: (mix, {transient = false}) {
                              controller.beginInteraction();
                              controller.setSceneBus(mix, transient: true);
                              if (!transient) controller.endInteraction();
                            },
                            onCommit: controller.endInteraction,
                            onOpen: (device) => controller
                                .openEffects(sceneBusKey, device: device),
                            onRemoveDevice: (id) =>
                                _removeDevice(sceneBusKey, id),
                            selected: controller.selectedChannel == sceneBusKey,
                            onSelect: () => controller.pickStrip(sceneBusKey),
                          ),
                        ],
                        const SizedBox(width: 8),
                        _MasterStrip(
                          key: const ValueKey("strip-master"),
                          mix: master,
                          speakers: controller.document.audio.speakers,
                          meter: _Meter(_board, _master),
                          theme: theme,
                          bands: bands,
                          narrow: narrow.contains(_master),
                          onNarrow: () => controller.toggleNarrow(_master),
                          onChanged: (mix, {transient = false}) {
                            controller.beginInteraction();
                            controller.setMasterMix(mix, transient: true);
                            if (!transient) controller.endInteraction();
                          },
                          onCommit: controller.endInteraction,
                          onOpenEq: () => _open(_master, _Opened.eq),
                          onOpenComp: () => _open(_master, _Opened.comp),
                          onOpenLoudness: () =>
                              _open(_master, _Opened.loudness),
                          onOpenDevice: (id) =>
                              controller.openEffects(_master, device: id),
                          onRemoveDevice: (id) => _removeDevice(_master, id),
                          scenes: () => _SceneBand(
                              controller: controller,
                              theme: theme,
                              motion: bands.motionClip,
                              scroll: _clipScrolls.of(_master)),
                          selected: controller.selectedChannel == _master,
                          onSelect: () => controller.pickStrip(_master),
                        ),
                        if (!widget.embedded && !bare) ...[
                          const SizedBox(width: 6),
                          _SectionRail(
                            states: states,
                            theme: theme,
                            onToggle: controller.toggleMixerSection,
                            returnsShown: controller.returnsShown,
                            onReturns: () => controller.returnsShown =
                                !controller.returnsShown,
                            allNarrow:
                                _allKeys(lanes, rows).every(narrow.contains),
                            onNarrowAll: () {
                              var keys = _allKeys(lanes, rows);
                              controller.setAllNarrow(
                                  keys, !keys.every(narrow.contains));
                            },
                          ),
                        ],
                      ]),
                ),
              ),
            ]);
      }),
    );
  }

  /// _removeDevice takes device [id] ("dev:d2", "midi0", "speech") out of strip
  /// [key]'s chain, as one change to undo.
  void _removeDevice(String key, String id) {
    controller.beginInteraction();
    if (id == "speech") {
      controller.setSpeech(key, null);
    } else if (id == "vocaliser") {
      controller.setVocaliser(key, null);
    } else if (id.startsWith("midi")) {
      var i = int.tryParse(id.substring(4)) ?? -1;
      controller.setChannelPart(
          key,
          (p) => i < 0 || i >= p.effects.length
              ? p
              : p.copyWith(effects: [...p.effects]..removeAt(i)));
    } else if (deviceKeyId(id) case var dev?) {
      var now = controller.devicesOf(key);
      var i = deviceIndexOf(now, dev);
      if (i >= 0) controller.setDevicesOf(key, [...now]..removeAt(i));
    }
    controller.endInteraction();
  }

  /// _allKeys is every column's key: channels, returns, the scene's bus,
  /// master.
  List<String> _allKeys(
          List<TimelineChannel> lanes, List<CanvasElement> rows) =>
      [
        for (var l in lanes) l.key,
        for (var e in rows) motionStripKey(e.id),
        for (var r in controller.document.returns) r.id,
        if (_sceneShown) sceneBusKey,
        _master,
      ];

  /// _sceneShown is whether the scene's bus has a strip: in a document of
  /// scenes, or with a master's sounds to go past it. Not in a sound's own
  /// settings, which show its channel and the master's.
  bool get _sceneShown =>
      widget.only == null &&
      (controller.document.hasScenes || controller.document.masterOn);

  Widget _channelStrip(
      MixerLook theme, TimelineChannel lane, int index, _Bands bands,
      {CanvasElement? element}) {
    var e = lane.first.element;
    var narrowNow = controller.narrowStrips.contains(lane.key);
    // As it plays now: a setting a lane moves, where the lane has it, and a
    // hand on one holds it there. See changeChannelMix.
    var shown = controller.mixNow(lane);
    return _ChannelStrip(
      key: ValueKey("strip-${lane.key}"),
      name: lane.name,
      number: index + 1,
      channelKey: lane.key,
      mix: shown,
      automated: {
        for (var l in lane.mix.automation)
          if (l.points.isNotEmpty) l.target
      },
      held: controller.overridden[lane.key] ?? const {},
      // In a sound's own settings it was picked on purpose, and is changed
      // there wherever it is.
      editable: lane.editable || widget.embedded,
      soloed: controller.solo.contains(lane.key),
      midi: e is AudioElement && e.instrument != null,
      part: controller.instrumentOf(lane.key)?.instrument,
      onOpenDevice: (id) => controller.openEffects(lane.key, device: id),
      onRemoveDevice: (id) => _removeDevice(lane.key, id),
      armed: controller.armed.contains(lane.key),
      meter: _Meter(_board, lane.key),
      theme: theme,
      bands: bands,
      narrow: controller.narrowStrips.contains(lane.key),
      onNarrow: () => controller.toggleNarrow(lane.key),
      onChanged: (mix, {transient = false}) {
        controller.beginInteraction();
        controller.changeChannelMix(lane, shown, mix,
            transient: true, anywhere: widget.embedded);
        if (!transient) controller.endInteraction();
      },
      onCommit: controller.endInteraction,
      onSolo: () => controller.toggleSolo(lane.key),
      onArm: () => controller.toggleArm(lane.key),
      onOpenEq: () => _open(lane.key, _Opened.eq),
      onOpenComp: () => _open(lane.key, _Opened.comp),
      onOpenDuck: () => _open(lane.key, _Opened.duck),
      onOpenPanner: () => controller.openEffects(lane.key, device: "panner"),
      // Its element's motion, where it is an element's own sound.
      motion: element == null
          ? null
          : () => _MotionHalf(
              controller: controller,
              element: element,
              narrow: narrowNow,
              theme: theme),
      leadSlot: element == null
          ? null
          : _ElementSoundBand(
              controller: controller, element: element, theme: theme),
      motionLine: element == null
          ? null
          : () => _MotionLine(
              controller: controller,
              element: element,
              narrow: narrowNow,
              theme: theme),
      clips: () => _ClipBand(
          controller: controller,
          channel: lane.key,
          theme: theme,
          scroll: _clipScrolls.of(lane.key),
          motion: bands.motionClip,
          motionRow: element == null
              ? null
              : (row) => _MotionSlot(
                  key: ValueKey("motionSlot-${element.id}-$row"),
                  controller: controller,
                  element: element.id,
                  row: row,
                  theme: theme)),
      selected: controller.selectedChannel == lane.key,
      onSelect: () => controller.pickStrip(lane.key),
      onRename: (name) => controller.renameChannel(lane, name),
      returns: controller.document.returns,
    );
  }

  Widget _returnStrip(
          MixerLook theme, ReturnChannel ret, int index, _Bands bands) =>
      _ReturnStrip(
        key: ValueKey("strip-${ret.id}"),
        letter: returnLetter(index),
        ret: ret,
        meter: _Meter(_board, ret.id),
        theme: theme,
        bands: bands,
        narrow: controller.narrowStrips.contains(ret.id),
        onNarrow: () => controller.toggleNarrow(ret.id),
        onChanged: (next, {transient = false}) {
          controller.beginInteraction();
          controller.setReturn(next, transient: true);
          if (!transient) controller.endInteraction();
        },
        onCommit: controller.endInteraction,
        onOpen: (device) => controller.openEffects(ret.id, device: device),
        onRemoveDevice: (id) => _removeDevice(ret.id, id),
        onRemove: () {
          controller.beginInteraction();
          controller.removeReturn(ret.id);
          controller.endInteraction();
        },
        selected: controller.selectedChannel == ret.id,
        onSelect: () => controller.pickStrip(ret.id),
      );

  /// _editor is [key]'s effects as a chain, left to right in the order the
  /// sound goes through them, scrolling sideways: for a channel its EQ and
  /// compressor in the order set, what it ducks, its level, and the
  /// master's; for the master its EQ and glue, the limiter, the loudness
  /// and its level.
  Widget _editor(MixerLook theme, String key, TimelineChannel? lane) {
    var master = controller.document.masterMix;
    var isMaster = key == _master;
    // The scene's bus: a chain as a channel's is, of the scene's strip.
    var isScene = key == sceneBusKey;
    var channel = isMaster ? null : key;
    var folded = controller.foldedDevices;
    return LayoutBuilder(builder: (context, room) {
      var h = math.max(120.0, room.maxHeight - 14);
      Widget device(String id,
              Widget Function(bool folded, VoidCallback onFold) make) =>
          KeyedSubtree(
            key: _deviceKey(key, id),
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
      // deviceAt is device [i] of the strip's own, a listener's screen or
      // a device of knobs.
      Widget deviceAt(int i) => device(
          deviceKey(deviceIdAt(controller.devicesOf(key), i)),
          (f, fold) => listensOnly(controller.devicesOf(key)[i].kind)
              ? ListenerDevice(
                  controller: controller,
                  owner: key,
                  index: i,
                  folded: f,
                  onFold: fold,
                  height: h)
              : ParamDevice(
                  controller: controller,
                  owner: key,
                  index: i,
                  folded: f,
                  onFold: fold,
                  height: h));
      var ret = isMaster ? null : controller.returnOf(key);
      var skin = DeviceSkin.themed(theme.colors);
      // The editor (a clip's, opened from its slot, or a part's piano roll)
      // first in its channel's strip.
      var clipHere =
          controller.clipEditorShown && controller.clipEditing?.channel == key;
      var rollHere = controller.pianoRollShown &&
          controller.pianoRoll?.row == null &&
          controller.pianoRoll?.channel == key;
      // The Pitch editor: the channel's recording as notes, first in it.
      var pitchHere = controller.pitchShown && lane != null;
      // The Instrument editor: how a MIDI channel's instrument plays.
      var instrumentHere = controller.instrumentShown &&
          lane != null &&
          controller.instrumentChannel(key);
      // The channel's Speech: its script, takes and voice -- what makes its
      // clips, not a step of its chain -- as wide as the panel, as the clip
      // editor is (Ken), not a card among the chain's others.
      var speechHere = controller.speechShown && lane != null;
      // An editor, opened from the Chain's tabs, fills the panel as the
      // prototype's do: the chain is then the rail under it.
      var editorId = instrumentHere
          ? "instrument"
          : pitchHere
              ? "pitch"
              : speechHere
                  ? "speech"
                  : clipHere
                      ? "clip"
                      : rollHere
                          ? "roll"
                          : null;
      Widget? editor = switch (editorId) {
        "instrument" => InstrumentEditor(controller: controller, channel: key),
        "pitch" => PitchEditor(controller: controller, channel: key),
        // No Speech yet: the way to start one, in the middle of the room.
        "speech" => controller.speechOf(key) == null
            ? LayoutBuilder(
                builder: (context, box) => Center(
                      child: VoiceStartCard(
                          key: const ValueKey("speechStart"),
                          controller: controller,
                          channel: key,
                          height: math.min(300.0, box.maxHeight - 16)),
                    ))
            : SpeechDevice(
                controller: controller,
                channel: key,
                folded: false,
                onFold: () {},
                height: h,
                editor: true),
        // Every column of its settings where there is room for them; one
        // at a time where not.
        "clip" => LayoutBuilder(
            builder: (context, box) => ClipEditor(
                controller: controller,
                wide: controller.editorWide && _roomForAll(box),
                canWiden: _roomForAll(box))),
        "roll" => LayoutBuilder(
            builder: (context, box) => ClipEditor(
                controller: controller,
                wide: controller.editorWide && _roomForAll(box),
                canWiden: _roomForAll(box),
                part: true)),
        _ => null,
      };
      if (editor != null) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  key: ValueKey("device-$editorId"),
                  color: theme.studio.panel,
                  child: editor,
                ),
              ),
              _ChainRail(controller: controller, channel: key, theme: theme),
            ]);
      }
      // The chain's Macro, kept in its own zone at the start, as the
      // prototype's Macros: knobs that turn other knobs.
      var macroAt = controller
          .devicesOf(key)
          .indexWhere((d) => d.kind == DeviceKind.macro);
      var chain = <Widget>[
        if (controller.chainMacros &&
            (lane != null || isMaster || isScene || ret != null)) ...[
          chainZone("Macros", const Color(0xFFA7A3B8), h),
          if (macroAt >= 0)
            deviceAt(macroAt)
          else
            _MacrosStart(controller: controller, owner: key, height: h),
        ],
        // A return's and the master's Source: what comes into them, as the
        // prototype's From sends and Every channel.
        if (isMaster || (ret != null && lane == null)) ...[
          chainZone("Source", const Color(0xFF3FB08D), h),
          device(
              "busSource",
              (f, fold) => _metered(() => _BusSourceDevice(
                  controller: controller,
                  ret: isMaster ? null : ret,
                  levels: _now,
                  theme: theme,
                  folded: f,
                  onFold: fold,
                  height: h))),
        ],
        // A scene's bus: everything heard in it, summed -- its Source, as
        // the prototype has it.
        if (isScene) ...[
          chainZone("Source", _sceneColour, h),
          device(
              "sceneSound",
              (f, fold) => _metered(() => _SceneSoundDevice(
                  controller: controller,
                  levels: _now,
                  theme: theme,
                  folded: f,
                  onFold: fold,
                  height: h))),
        ],
        // An audio channel's sounds -- on the timeline and in its slots --
        // before anything is done to them.
        if (lane != null &&
            !lane.video &&
            !controller.instrumentChannel(key)) ...[
          chainZone("Source", audioColour, h),
          device(
              "audioClips",
              (f, fold) => AudioClipsDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
        ],
        // A MIDI channel's notes -- its part and its note clips -- then its
        // In and its MIDI effects, before its instrument plays: what comes
        // in, and what is done to the notes.
        if (lane != null && controller.instrumentChannel(key)) ...[
          chainZone("Source", midiColour, h),
          device(
              "noteClips",
              (f, fold) => NoteClipsDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
          // Between each two of its note devices, the notes passing as dots,
          // as the prototype's joins on a MIDI chain: the effects before
          // each done to them.
          // The notes as they come, before MIDI In picks what it hears.
          NoteJoin(
              controller: controller,
              channel: key,
              upto: 0,
              height: h,
              name: "in"),
          chainZone("Before", midiColour, h),
          device(
              "midiIn",
              (f, fold) => MidiInDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h)),
          NoteJoin(controller: controller, channel: key, upto: 0, height: h),
          for (var i = 0;
              i < controller.instrumentOf(key)!.instrument!.effects.length;
              i++) ...[
            device(
                "midi$i",
                (f, fold) => MidiEffectDevice(
                    controller: controller,
                    channel: key,
                    index: i,
                    folded: f,
                    onFold: fold,
                    height: h)),
            NoteJoin(
                controller: controller, channel: key, upto: i + 1, height: h),
          ],
          AddMidiEffectSlot(
              key: const ValueKey("addMidiEffectSlot"),
              controller: controller,
              channel: key,
              height: h),
          // Then the instrument, playing them.
          chainZone("Generator", midiColour, h),
          device(
              "instrumentCard",
              (f, fold) => InstrumentDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
        ],
        // A voice channel's generator: Speech, chosen for it from the Add
        // menu's Generators, as a MIDI channel's Instrument is its own. Its
        // script and takes are the Speech tab's.
        if (lane != null && controller.speechOf(key) != null) ...[
          chainZone("Generator", voiceColour, h),
          device(
              "speechCard",
              (f, fold) => SpeechCard(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
        ],
        // A channel's, a return's, the scene bus's and the master's chain in
        // the order it runs, its EQ and compressor among its devices
        // wherever they were put, a join between each two; then a way to add
        // another.
        // Turned down by a voice: the Ducker first, as the dips are made to
        // the channel's sounds as they come in.
        if (lane != null &&
            controller.duckersOf(key).isNotEmpty &&
            !controller.partRemoved(key, stripDucked))
          device(
              "ducked",
              (f, fold) => DuckedDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h)),
        if (lane != null || isMaster || isScene || ret != null) ...[
          chainZone(
              lane != null && controller.instrumentChannel(key)
                  ? "After"
                  : "Effects",
              const Color(0xFF4F8FD6),
              h),
          // A voice's Vocaliser, first of its effects: added from the "+"
          // when it is wanted, not opened with the Speech.
          if (lane != null && controller.vocaliserOf(key) != null)
            device(
                "vocaliser",
                (f, fold) => VocaliserDevice(
                    controller: controller,
                    channel: key,
                    folded: f,
                    onFold: fold,
                    height: h)),
          for (var (i, step) in controller.chainOf(key).indexed) ...[
            // The way to add one where it will go: before the EQ and
            // compressor when they are last (see chainOrder).
            if (i == _addAt(controller.chainOf(key)))
              AddDeviceSlot(
                  key: const ValueKey("addDeviceSlot"),
                  controller: controller,
                  owner: key,
                  height: h),
            // A part of the strip taken out is not shown, nor its meter.
            // The master and the scene bus are measured between their
            // devices as a channel is.
            if (!controller.partRemoved(key, step)) _junction(i, h, theme, key),
            if (controller.partRemoved(key, step))
              const SizedBox.shrink()
            else if (step == chainEq)
              eq
            else if (step == chainComp)
              comp
            else if (deviceIndexOf(controller.devicesOf(key), step) case var at
                when at >= 0 && at != macroAt)
              deviceAt(at),
          ],
          _junction(controller.chainOf(key).length, h, theme, key),
          if (_addAt(controller.chainOf(key)) == controller.chainOf(key).length)
            AddDeviceSlot(
                key: const ValueKey("addDeviceSlot"),
                controller: controller,
                owner: key,
                height: h),
        ],
        if (lane != null && !controller.partRemoved(key, stripDuck))
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
              (f, fold) => _metered(() => LimiterDevice(
                  controller: controller,
                  folded: f,
                  onFold: fold,
                  height: h,
                  reductionDb: (_now[limitKey] ?? (0.0, 0.0)).$1))),
          device(
              "loudness",
              (f, fold) => _LoudnessDevice(
                    controller: controller,
                    mix: master,
                    measured: _measured,
                    measuring: _measuring,
                    onMeasure: _measure,
                    theme: theme,
                    folded: f,
                    onFold: fold,
                    height: h,
                  )),
          // Where it is heard: the speakers, each one's level.
          device(
              "output",
              (f, fold) => _metered(() => _MasterOutputDevice(
                    controller: controller,
                    levels: [
                      for (var c = 0;
                          c < controller.document.audio.speakers.channels;
                          c++)
                        (_now[speakerLevelKey(c)] ?? (-90.0, -90.0)).$1
                    ],
                    theme: theme,
                    skin: skin,
                    folded: f,
                    onFold: fold,
                    height: h,
                  ))),
        ],
        // Where it is heard from, big enough to place it by: the room, its
        // speakers and the channel among them, stereo or surround.
        if (lane != null || ret != null)
          chainZone("Output", const Color(0xFFCFCBDF), h),
        if (lane != null || ret != null)
          device("panner", (f, fold) {
            // A channel's pan as it plays now: see mixNow.
            var mix = lane != null ? controller.mixNow(lane) : ret!.mix;
            void write(ChannelMix next, {bool transient = false}) {
              controller.beginInteraction();
              if (lane != null) {
                controller.changeChannelMix(lane, mix, next,
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
              // The channel's own strip, as on the mixer (panning, mute and solo,
              // fader and meter), under its name.
              (f, fold) {
            var meter = _Meter(_board, key);
            var mix = lane.mix;
            void write(ChannelMix next, {bool transient = false}) {
              controller.beginInteraction();
              controller.setChannelMix(lane, next,
                  transient: true, anywhere: true);
              if (!transient) controller.endInteraction();
            }

            void set(double db, {bool transient = false}) =>
                write(mix.copyWith(gainDb: db), transient: transient);

            // Where it goes: the master, or the bus it is routed into.
            var to = mix.output.isEmpty
                ? "Master"
                : controller.document.returns
                        .where((r) => r.id == mix.output)
                        .firstOrNull
                        ?.name ??
                    "Master";
            var returns = controller.document.returns;
            var small = TextStyle(fontSize: 10.5, color: theme.studio.muted);
            var value = TextStyle(
                fontSize: 10.5,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.studio.text);
            return DeviceFrame(
              id: "meter",
              // The prototype's Output: where the chain leaves the channel.
              title: "Output",
              skin: skin,
              icon: Icons.speaker,
              accent: const Color(0xFFCFCBDF),
              help: "Where ${lane.name}'s chain ends: its pan, its sends to "
                  "the returns, its fader, mute and solo -- as on the mixer "
                  "-- and where it goes.",
              folded: f,
              onFold: fold,
              width:
                  returns.isEmpty ? 150 : 150 + 52.0 * returns.take(2).length,
              height: h,
              foldedBody: CustomPaint(
                  key: const ValueKey("meterFolded"),
                  painter: _MeterPainter(meter, theme.studio)),
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
                      meter: meter,
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
                  // Its sends, a knob each, as the prototype's Send A.
                  if (returns.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var r in returns.take(2))
                            SizedBox(
                              width: 50,
                              child: DeviceKnob(
                                key: ValueKey("outputSend-${r.id}"),
                                label: "Send ${r.name}",
                                text: (mix.sends[r.id] ?? -60) <= -60
                                    ? "off"
                                    : "${mix.sends[r.id]!.toStringAsFixed(1)} dB",
                                value: mix.sends[r.id] ?? -60,
                                initial: -60,
                                min: -60,
                                max: 6,
                                size: 24,
                                accent: const Color(0xFF9A92EA),
                                ink: theme.studio.text,
                                onChanged: (v, {transient = false}) => write(
                                    mix.copyWith(
                                        sends: {
                                      ...mix.sends,
                                      r.id: (v * 2).roundToDouble() / 2,
                                    }..removeWhere((_, db) => db <= -60)),
                                    transient: transient),
                                onCommit: controller.endInteraction,
                              ),
                            ),
                        ]),
                  ],
                  const SizedBox(height: 4),
                  Row(children: [
                    Text("Peak", style: small),
                    const Spacer(),
                    // Read again as the meters move, not the card.
                    ListenableBuilder(
                        listenable: _board,
                        builder: (context, _) {
                          var peak = meter.peak;
                          return Text(
                              peak.$1 <= -80 && peak.$2 <= -80
                                  ? "−∞"
                                  : "${math.max(peak.$1, peak.$2).toStringAsFixed(1)} dB",
                              key: const ValueKey("outputPeak"),
                              style: value);
                        }),
                  ]),
                  Row(children: [
                    Text("To", style: small),
                    const Spacer(),
                    Flexible(
                      child: Text(to,
                          key: const ValueKey("outputTo"),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: value),
                    ),
                  ]),
                ]),
              ),
            );
          }),
        // A bus's chain ends at its Output too: a scene's, a return's.
        if (isScene || (ret != null && lane == null)) ...[
          if (isScene) chainZone("Output", const Color(0xFFCFCBDF), h),
          device("busOutput", (f, fold) {
            var mix = isScene ? controller.sceneBus : ret!.mix;
            return _metered(() => _BusOutputDevice(
              id: "busOutput",
              mix: mix,
              level: _now[key] ?? (-90.0, -90.0),
              to: "Master",
              theme: theme,
              folded: f,
              onFold: fold,
              height: h,
              onChanged: (next, {transient = false}) {
                controller.beginInteraction();
                if (isScene) {
                  controller.setSceneBus(next, transient: true);
                } else {
                  controller.setReturn(ret!.copyWith(mix: next),
                      transient: true);
                }
                if (!transient) controller.endInteraction();
              },
              onCommit: controller.endInteraction,
            ));
          }),
        ],
        // The master's own meter, on the master's chain only: a channel's
        // or a bus's chain ends at its Output (Ken, 2026-11-08).
        if (isMaster)
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
      // The devices' own lists still scroll; only the chain itself is not
      // dragged.
      var inside = ScrollConfiguration.of(context);
      // Held to the left, not centred, when narrower than the panel.
      return Align(
        alignment: Alignment.topLeft,
        // By the wheel and the trackpad, not by a drag: a drag in a device (a
        // note drawn, a point moved) is the device's.
        child: ScrollConfiguration(
          behavior: inside.copyWith(
              scrollbars: false, dragDevices: {PointerDeviceKind.trackpad}),
          child: SingleChildScrollView(
            key: const ValueKey("effectsChain"),
            controller: _chainScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Each wrapper keyed as its device is: matched by place, a device put in
              // ahead (the clip editor opened) would move every one after it to
              // another wrapper, and a showing tooltip moved that way asserts.
              for (var (i, d) in chain.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                ScrollConfiguration(
                    key: d.key == null ? null : ValueKey(d.key),
                    behavior: inside,
                    child: d),
              ],
            ]),
          ),
        ),
      );
    });
  }

  /// _roomForAll is whether an editor [box] wide has room for every column
  /// of its settings -- three, 690 together -- and what it edits beside
  /// them. At the desk's own size: the desk is zoomed as a whole for the
  /// text's (see build).
  static bool _roomForAll(BoxConstraints box) => box.maxWidth >= 690 + 480;

  final ScrollController _chainScroll = ScrollController();

  /// _chainOffsets are where each chain was scrolled to when it was left,
  /// by its key and view; _chainKey the one shown.
  final Map<String, double> _chainOffsets = {};
  String? _chainKey;
}

typedef _MixWrite<T> = void Function(T next, {bool transient});

// ---------------------------------------------------------------------------
// Pieces of a strip
// ---------------------------------------------------------------------------

/// _faderTop and _faderBottom are the fader's travel, in decibels. The
/// bottom is silence.
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
/// "-inf" for silence, clamped to what the fader reaches. Null for anything
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
        // One line, shrunk rather than wrapped: a reading on two lines would
        // make a column's fader shorter than its neighbours'.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text("${dbText(widget.db)}${widget.unit}",
              key: widget.textKey,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: widget.style),
        ),
      ),
    );
  }
}

class _Fader extends StatelessWidget {
  final double db;
  final _Meter meter;
  final MixerLook theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;
  final bool wide;

  /// small is a mixer strip's: half the size of the effects' own. [labels] is
  /// whether its scale is numbered (not in a narrow strip, which has room for
  /// the marks alone).
  final bool small;
  final bool labels;

  const _Fader({
    required this.db,
    required this.meter,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    this.wide = false,
    this.small = false,
    this.labels = true,
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
              supportedDevices: dragPointers,
              key: const ValueKey("fader"),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) => at(d.localPosition.dy),
              onVerticalDragUpdate: (d) => at(d.localPosition.dy),
              onVerticalDragEnd: (_) => onCommit(),
              onDoubleTap: () => onChanged(0),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: CustomPaint(
                  size: Size(
                      small
                          ? (labels ? 26 : 14)
                          : wide
                              ? 44
                              : 40,
                      h),
                  painter: _FaderPainter(db, theme.studio,
                      small: small, labels: labels),
                ),
              ),
            ),
            SizedBox(width: small ? 2 : 4),
            CustomPaint(
              size: Size(
                  small
                      ? (labels ? (wide ? 12 : 9) : 6)
                      : wide
                          ? 22
                          : 14,
                  h),
              painter: _MeterPainter(meter, theme.studio),
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
  final bool small;
  final bool labels;
  _FaderPainter(this.db, this.colors, {this.small = false, this.labels = true});

  static const _marks = [6.0, 0.0, -6.0, -12.0, -24.0, -48.0];

  @override
  void paint(Canvas canvas, Size size) {
    // Half size: the cap, the marks and the numbers all halved.
    var k = small ? 0.5 : 1.0;
    var slotX = size.width - (small ? 7 : 13);
    double yOf(double d) => 6 + faderPosition(d) * (size.height - 12);
    // The scale, left of the slot.
    for (var m in _marks) {
      var y = yOf(m);
      var unity = m == 0;
      canvas.drawLine(
          Offset(slotX - (unity ? 12 : 8) * k - (small ? 2 : 0), y),
          Offset(slotX - 3 * k - (small ? 1.5 : 0), y),
          Paint()
            ..strokeWidth = 1
            ..color = unity ? colors.muted : colors.edge);
      if (!labels) continue;
      var label = paintedLabel(
          m > 0 ? "+${m.round()}" : "${m.round()}".replaceAll("-", "−"),
          TextStyle(
              fontSize: small ? 6 : 7,
              height: 1,
              color: unity ? colors.text : colors.muted));
      if (size.height > (small ? 70 : 90)) {
        label.paint(
            canvas,
            Offset(
                slotX - (small ? 9 : 14) - label.width, y - label.height / 2));
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
    var cap = Rect.fromCenter(
        center: Offset(slotX, y),
        width: 22 * k + (small ? 1 : 0),
        height: 30 * k);
    var rrect = RRect.fromRectAndRadius(cap, Radius.circular(4 * k + 0.5));
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
    for (var dy in small ? [-4.5, 4.5] : [-9.0, -5.0, 5.0, 9.0]) {
      canvas.drawLine(
          Offset(slotX - 7 * k, y + dy), Offset(slotX + 7 * k, y + dy), grip);
    }
    canvas.drawLine(
        Offset(slotX - 8 * k, y),
        Offset(slotX + 8 * k, y),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.on);
  }

  @override
  bool shouldRepaint(_FaderPainter old) =>
      old.db != db ||
      old.colors != colors ||
      old.small != small ||
      old.labels != labels;
}

/// _Junction is the meter between two devices of a chain: how loud the
/// sound is after the one on its left, its peak held -- step [index] of
/// the strip (see StripProcessor.taps).
class _Junction extends StatelessWidget {
  final int index;
  final (double, double) level;
  final (double, double) peak;
  final StudioColors colors;
  final double height;

  /// listening is whether the chain is heard from here; onListen hears it
  /// from here, or all of it again, and onAnalyser puts one here.
  final bool listening;
  final VoidCallback onListen;
  final ValueChanged<DeviceKind> onAnalyser;

  /// latched is whether it has clipped since its lights were last cleared,
  /// and onClear clears every join's of the chain.
  final bool latched;
  final VoidCallback onClear;
  const _Junction(this.index, this.level, this.peak, this.colors, this.height,
      {required this.listening,
      required this.onListen,
      required this.onAnalyser,
      this.latched = false,
      required this.onClear});

  /// clipped is whether it has reached nought decibels: held, or since its
  /// lights were cleared.
  bool get clipped => latched || peak.$1 >= 0 || peak.$2 >= 0;

  /// reading is its level and the peak held, in decibels.
  String get reading =>
      "${level.$1 <= -80 ? "−∞" : level.$1.toStringAsFixed(1)} dB · hold "
      "${peak.$1 <= -80 ? "−∞" : peak.$1.toStringAsFixed(1)}";

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, reading),
        chainMenuItem(look,
            key: ValueKey("junctionListen-$index"),
            text: listening
                ? "Stop listening here"
                : "Listen from here (what comes after unheard)",
            onPressed: onListen),
        if (latched)
          chainMenuItem(look,
              key: ValueKey("junctionClear-$index"),
              text: "Clear the clip lights",
              onPressed: onClear),
        chainMenuDivider(look),
        chainMenuHeading(look, "Add an analyser here"),
        for (var kind in const [
          DeviceKind.spectrum,
          DeviceKind.scope,
          DeviceKind.tuner,
          DeviceKind.loudness,
        ])
          chainMenuItem(look,
              key: ValueKey("junctionAnalyser-$index-${kind.name}"),
              text: kind.label,
              onPressed: () => onAnalyser(kind)),
      ],
      builder: (context, menu, _) => GestureDetector(
        key: ValueKey("junction-$index"),
        behavior: HitTestBehavior.opaque,
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Tooltip(
            message: reading,
            child: SizedBox(
              width: 16,
              height: height,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: listening
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: const Color(0xFFE2B04A), width: 1.5))
                      : null,
                  // Its clip light over it and the peak held under it, as
                  // the prototype's joins: lit red once it reaches 0 dB.
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      key: ValueKey("junctionClip-$index"),
                      width: 7,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 3),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1),
                          color: clipped
                              ? const Color(0xFFE5484D)
                              : colors.edge),
                    ),
                    SizedBox(
                      width: 9,
                      height: math.min(150.0, math.max(30.0, height - 80)),
                      child: CustomPaint(
                          painter: _MeterPainter(
                              _Meter.fixed(level, peak), colors)),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 16,
                      height: 10,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                            peak.$1 <= -80
                                ? "—"
                                : peak.$1.round().toString().replaceFirst(
                                    "-", "−"),
                            key: ValueKey("junctionDb-$index"),
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                fontSize: 8,
                                color: clipped
                                    ? const Color(0xFFE5484D)
                                    : colors.muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final _Meter meter;
  final StudioColors colors;

  /// horizontal lays it on its side: nought on the right, the left side's
  /// bar above the right's.
  final bool horizontal;

  /// Painted again as [meter]'s board moves, without the widget it is in
  /// being built again.
  _MeterPainter(this.meter, this.colors, {this.horizontal = false})
      : super(repaint: meter.board);

  (double, double) get level => meter.level;
  (double, double) get peak => meter.peak;

  /// _fill is how far a meter is lit: it reads from minus sixty to nought, in
  /// segments, green, then amber for the last nine decibels, then red at the
  /// top.
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
      !identical(old.meter.board, meter.board) ||
      old.meter.key != meter.key ||
      old.level != level ||
      old.peak != peak ||
      old.colors != colors ||
      old.horizontal != horizontal;
}

/// mixerDeskBuilds counts the desk built, for a test that the meters move
/// without it.
@visibleForTesting
int mixerDeskBuilds = 0;

/// _MeterBoard is a desk's meters: each strip's level and held peak, in
/// decibels, by its key. It notifies as they move -- about thirty times a
/// second while there is sound -- and only the meters and readings listen.
class _MeterBoard extends ChangeNotifier {
  final Map<String, (double, double)> now = {};
  final Map<String, (double, double)> peaks = {};
  void moved() => notifyListeners();
}

/// _sessionPulse beats while the session plays: a slot waiting for its bar
/// blinks on it, and a playing one's ring goes round.
final _MeterBoard _sessionPulse = _MeterBoard();

/// _Meter is one meter: strip [key]'s on [board], read as it is painted --
/// or, fixed, the level and peak it was made with (a join's, built again
/// as its board moves).
class _Meter {
  final _MeterBoard? board;
  final String key;
  final (double, double) _level, _peak;
  const _Meter(_MeterBoard this.board, this.key)
      : _level = (-90.0, -90.0),
        _peak = (-90.0, -90.0);
  const _Meter.fixed(this._level, this._peak)
      : board = null,
        key = "";

  (double, double) get level =>
      board == null ? _level : board!.now[key] ?? (-90.0, -90.0);
  (double, double) get peak =>
      board == null ? _peak : board!.peaks[key] ?? (-90.0, -90.0);
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
      !identical(old.eq, eq);
}

Widget _slot(MixerLook theme, String label, bool on, Widget trailing,
        VoidCallback onTap,
        {Key? key, VoidCallback? onRemove}) =>
    Material(
      color: theme.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        // Right-clicked, a device's slot takes the device out.
        onSecondaryTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: LayoutBuilder(
            builder: (context, box) => Row(children: [
              // A long label ("Add a device", a device's own name) fades at the
              // slot's edge rather than running out of it.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.7),
                child: Text(label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on
                            ? theme.colors.onSurface
                            : theme.colors.onSurfaceVariant)),
              ),
              const SizedBox(width: 4),
              // Scaled down rather than overflowing: "−12.0 dBTP" beside its label
              // is wider than a strip in some fonts.
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
                ),
              ),
            ]),
          ),
        ),
      ),
    );

class _Toggle extends StatelessWidget {
  final String label;

  /// icon, given, is drawn rather than [label]: the scene's on/off switch.
  final IconData? icon;
  final bool on;
  final Color onColor;

  /// onInk is what the label is drawn in while it is on: white if not said.
  final Color? onInk;
  final double height;
  final double fontSize;
  final MixerLook theme;
  final String tooltip;
  final VoidCallback onTap;

  const _Toggle({
    this.onInk,
    this.height = 20,
    this.fontSize = 10,
    this.icon,
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
              height: height,
              child: Center(
                child: icon != null
                    ? Icon(icon,
                        size: height * 0.62,
                        color: on
                            ? onInk ?? const Color(0xFFFFFFFF)
                            : theme.colors.onSurfaceVariant)
                    : Text(label,
                        style: TextStyle(
                            fontSize: fontSize,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: on
                                ? onInk ?? const Color(0xFFFFFFFF)
                                : theme.colors.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      );
}

/// _Balance is a knob: dragged up to turn right, down to turn left,
/// double-clicked to centre.
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
        supportedDevices: dragPointers,
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
/// drag (with how wide its two sides are spread, and how much goes to the
/// LFE). Placed by the picture: the same pad, showing where the picture
/// puts it, not to be dragged.
class _PanControl extends StatelessWidget {
  final String channel;
  final ChannelMix mix;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  const _PanControl({
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
    // fixed height with the fader taking what is left.
    var pad = Tooltip(
      message: placed != null
          ? "Heard from where the picture puts it: see the sound's "
              "Placement. Its own pan is kept for when it is not placed."
          : "Drag the dot round to where it is heard from. Double-click "
              "for the front pair, as it was mixed.",
      child: _SurroundPad(
        key: const ValueKey("surroundPad"),
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
                // Each shrinks rather than runs out of a narrow strip. Placed says
                // so; otherwise the reading (Front, or an angle) says what it is.
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

/// _ChainRail is the chain under an open editor, as the prototype has it:
/// "Chain" back to it, then each step as a chip -- its colour and its name
/// -- pressed, the chain again, on that step.
class _ChainRail extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final MixerLook theme;
  const _ChainRail(
      {required this.controller, required this.channel, required this.theme});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var studio = theme.studio;
    var steps = <(String, String, Color, bool)>[];
    if (c.instrumentOf(channel)?.instrument case var part?) {
      steps.add(("midiIn", "MIDI In", midiColour, true));
      for (var (i, e) in part.effects.indexed) {
        steps.add(("midi$i", e.kind.label, midiColour, e.on));
      }
      steps.add(("instrumentCard", "Instrument", midiColour, true));
    }
    var devices = c.devicesOf(channel);
    for (var step in c.chainOf(channel)) {
      if (step == chainEq) {
        steps.add(("eq", "EQ", const Color(0xFF9A92EA), true));
      } else if (step == chainComp) {
        steps.add((
          "comp",
          "Compressor",
          deviceGroupLook(DeviceGroup.dynamics).$2,
          true
        ));
      } else if (deviceIndexOf(devices, step) case var at when at >= 0) {
        var d = devices[at];
        steps.add((
          deviceKey(step),
          d.kind.label,
          deviceGroupLook(d.kind.group).$2,
          d.on
        ));
      }
    }
    steps.add(("panner", "Output", const Color(0xFFCFCBDF), true));
    Widget chip(String id, String name, Color colour, bool on) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: InkWell(
            key: ValueKey("railChip-$id"),
            borderRadius: BorderRadius.circular(5),
            onTap: () {
              c.closeEditor();
              c.openEffects(channel, device: id);
            },
            child: Opacity(
              opacity: on ? 1 : 0.45,
              child: Container(
                height: 22,
                padding: const EdgeInsets.fromLTRB(4, 0, 7, 0),
                decoration: BoxDecoration(
                  color: studio.raised,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: studio.edge),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                          color: colour,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text(name,
                      style: TextStyle(fontSize: 10.5, color: studio.muted)),
                ]),
              ),
            ),
          ),
        );
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: studio.panel,
        border: Border(top: BorderSide(color: studio.edge)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          InkWell(
            key: const ValueKey("editorClose"),
            borderRadius: BorderRadius.circular(5),
            onTap: c.closeEditor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text("Chain",
                  style: TextStyle(fontSize: 11, color: studio.text)),
            ),
          ),
          const SizedBox(width: 4),
          for (var (id, name, colour, on) in steps) chip(id, name, colour, on),
        ]),
      ),
    );
  }
}

/// chainZone marks where a part of a chain begins, as the prototype does:
/// its name up the side, a line of [colour] beside it.
/// _MacrosStart is the Macros zone of a chain with no Macro yet: a narrow
/// dashed "+" (Ken: narrow while unused), adding one at once.
class _MacrosStart extends StatelessWidget {
  final CanvasController controller;
  final String owner;
  final double height;
  const _MacrosStart(
      {required this.controller, required this.owner, required this.height});

  @override
  Widget build(BuildContext context) => DashedAddButton(
        key: const ValueKey("macrosAdd"),
        tip: "Add macros: eight knobs, each turning any knobs of this "
            "chain you give it",
        height: height,
        onTap: () {
          controller.beginInteraction();
          controller.setDevicesOf(owner, [
            ...controller.devicesOf(owner),
            const MixDevice(DeviceKind.macro),
          ]);
          controller.endInteraction();
        },
      );
}

Widget chainZone(String label, Color colour, double height) => Builder(
      builder: (context) {
        var look = MixerLook.of(context);
        return Container(
          key: ValueKey("chainZone-$label"),
          width: 16,
          height: height,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colour, width: 2))),
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(label.toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                    fontSize: 9, letterSpacing: 1.1, color: look.studio.muted)),
          ),
        );
      },
    );

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

/// _MasterOutputDevice is the master's Output, last in its chain: the
/// speakers the piece is mixed for (stereo, 5.1 or 7.1), a meter for each,
/// and -- in surround, which the editor plays folded down to two -- which
/// of them are heard here, everything or one group alone.
class _MasterOutputDevice extends StatelessWidget {
  final CanvasController controller;

  /// levels are each speaker's level now, in decibels.
  final List<double> levels;
  final MixerLook theme;
  final DeviceSkin skin;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const _MasterOutputDevice({
    required this.controller,
    required this.levels,
    required this.theme,
    required this.skin,
    required this.folded,
    required this.onFold,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    var audio = controller.document.audio;
    var master = controller.document.masterMix;
    var layout = audio.speakers;
    var hear = controller.hear;
    var small = TextStyle(fontSize: 11, color: skin.ink.withValues(alpha: 0.7));
    return DeviceFrame(
      id: "output",
      accent: const Color(0xFFCFCBDF),
      help: "What the piece is mixed for: two speakers, 5.1 or 7.1, with a "
          "meter for each. Surround is heard here folded down to two; Hear "
          "plays one group of speakers alone, to check what goes where. "
          "Exports carry the whole mix.",
      title: "Output",
      skin: skin,
      icon: Icons.speaker,
      folded: folded,
      onFold: onFold,
      width: math.max(
          190.0, 70.0 + 26 * layout.channels + (layout.isSurround ? 90 : 60)),
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(layout.label,
              style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: CustomPaint(
              key: const ValueKey("outputMeters"),
              painter: _SpeakerMetersPainter(
                layout: layout,
                levels: levels,
                hear: hear,
                studio: theme.studio,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // The master's Out, and how loud it is now, as the prototype's
          // Output: the fader at the end of everything.
          Row(children: [
            DeviceKnob(
              key: const ValueKey("outputOut"),
              label: "Out",
              text: "${dbText(master.gainDb)} dB",
              value: master.gainDb.clamp(-24.0, 12.0),
              initial: 0,
              min: -24,
              max: 12,
              size: 30,
              accent: const Color(0xFFCFCBDF),
              ink: skin.ink,
              bipolar: true,
              onChanged: (v, {transient = false}) {
                controller.beginInteraction();
                controller.setMasterMix(
                    controller.document.masterMix
                        .copyWith(gainDb: (v * 10).roundToDouble() / 10),
                    transient: true);
                if (!transient) controller.endInteraction();
              },
              onCommit: controller.endInteraction,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  key: const ValueKey("outputLufs"),
                  switch (controller.loudness(mixerMasterKey)?.shortTerm) {
                    var l? when l.isFinite => "${l.toStringAsFixed(1)} LUFS",
                    _ => "— LUFS",
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
          const SizedBox(height: 6),
          CanvasDropdown<SpeakerLayout>(
            key: const ValueKey("outputSpeakers"),
            label: "Speakers",
            value: layout,
            tight: true,
            width: 150,
            options: [for (var l in SpeakerLayout.values) (l, l.label)],
            onChanged: (l) => controller.setAudio(audio.copyWith(speakers: l)),
          ),
          if (layout.isSurround) ...[
            const SizedBox(height: 6),
            Tooltip(
              message: "Heard here on two speakers: everything folded "
                  "down, as most listeners will hear it, or one group "
                  "alone to check what goes where. What is written is "
                  "the whole mix.",
              child: CanvasDropdown<SpeakerGroup>(
                key: const ValueKey("outputHear"),
                label: "Hear",
                value: hear,
                tight: true,
                width: 150,
                options: [
                  for (var g in SpeakerGroup.values)
                    if (g == SpeakerGroup.all ||
                        layout.speakers.any((s) => g.has(s.$2)))
                      (g, g.label)
                ],
                onChanged: controller.hearSpeakers,
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text("Two speakers, as heard here",
                maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
          ],
        ]),
      ),
    );
  }
}

/// _SpeakerMetersPainter draws a meter a speaker, named beneath, those not
/// heard here dimmed.
class _SpeakerMetersPainter extends CustomPainter {
  final SpeakerLayout layout;
  final List<double> levels;
  final SpeakerGroup hear;
  final StudioColors studio;

  _SpeakerMetersPainter({
    required this.layout,
    required this.levels,
    required this.hear,
    required this.studio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var n = layout.channels;
    const foot = 14.0;
    var w = size.width / n;
    var h = size.height - foot;
    if (h <= 4) return;
    for (var (c, (name, deg)) in layout.speakers.indexed) {
      var x = c * w + 3;
      var bar = Rect.fromLTWH(x, 0, w - 6, h);
      canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)),
          Paint()..color = studio.inset);
      var db = c < levels.length ? levels[c] : -90.0;
      var u = ((db + 60) / 60).clamp(0.0, 1.0);
      var heard = hear.has(deg);
      var colour = db > -1
          ? studio.meterHigh
          : db > -12
              ? studio.meterMid
              : studio.meterLow;
      if (u > 0) {
        canvas.drawRect(Rect.fromLTWH(x, h * (1 - u), w - 6, h * u),
            Paint()..color = colour.withValues(alpha: heard ? 1 : 0.3));
      }
      // Kept, as it is painted at the meters' rate.
      var label = paintedLabel(
          name,
          TextStyle(
              fontSize: 9.5,
              color: studio.muted.withValues(alpha: heard ? 1 : 0.5)),
          maxWidth: w);
      label.paint(canvas, Offset(c * w + (w - label.width) / 2, h + 2));
    }
  }

  @override
  bool shouldRepaint(_SpeakerMetersPainter old) =>
      old.layout != layout ||
      old.hear != hear ||
      old.studio != studio ||
      !_same(old.levels, levels);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.2) return false;
    }
    return true;
  }
}

/// speakerLights is how much of a channel each of [layout]'s speakers
/// carries, nought to one (the same sums MixGraph lands it with), for
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
    var gl = panGains(layout, pan.angle - pan.width / 2, centre: pan.centre);
    var gr = panGains(layout, pan.angle + pan.width / 2, centre: pan.centre);
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
/// lit by how much of the channel each carries. See _PanControl for the
/// stereo, surround and placed cases.
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
    // The room fills the device: as wide as it is, as tall as the device less
    // the bar of readings along its foot, with the speakers on an ellipse to
    // match. A press is read against the room as it was drawn.
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
        // Set by a press and a drag only: a wheel or a trackpad's scroll
        // over it scrolls the chain (Ken). Its width is the Width number's.
        view = GestureDetector(
          supportedDevices: dragPointers,
          onPanStart: (d) => point(d.localPosition, room),
          onPanUpdate: (d) => point(d.localPosition, room),
          onPanEnd: (_) => onCommit(),
          onDoubleTap: () => onChanged(
              surround ? mix.withSurround(null) : mix.copyWith(balance: 0)),
          child: MouseRegion(cursor: SystemMouseCursors.precise, child: view),
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
          if (layout.speakers.any((s) => s.$2 == 0))
            number(
                "pannerCentre",
                "Centre",
                "${(pan.centre * 100).round()}%",
                "How much of what is heard from in front goes to the centre "
                    "speaker: all of it, or none -- between the front pair, "
                    "the centre kept for voices.",
                (dy) => onChanged(
                    mix.withSurround(
                        pan.copyWith(centre: pan.centre - dy / 100)),
                    transient: true),
                () => onChanged(mix.withSurround(pan.copyWith(centre: 1)))),
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
      icon: Icons.speaker,
      accent: const Color(0xFFCFCBDF),
      help: "Where it is heard from. Drag in the room to place it; in "
          "surround the wheel sets its width. Centre is how much of what is "
          "in front goes to the centre speaker. Double-click for the front.",
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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
      var p = paintedLabel(
          text,
          TextStyle(
              fontSize: fontSize, fontWeight: FontWeight.w600, color: colour));
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
    var front = paintedLabel(
        "▲ FRONT",
        TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: studio.displayLine.withValues(alpha: 0.7)));
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
      !identical(old.mix, mix) ||
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
          supportedDevices: dragPointers,
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
  final SpeakerLayout speakers;
  final SurroundPan? pan;
  final Heard? placed;
  final MixerLook theme;
  final ValueChanged<double>? onAngle;
  final VoidCallback onCommit;
  final VoidCallback? onReset;

  const _SurroundPad({
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
  double get side => size;

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
      supportedDevices: dragPointers,
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

// ---------------------------------------------------------------------------
// The ducking and loudness editors
// ---------------------------------------------------------------------------

/// _Sends is a channel's sends: a dial for each return, by its letter,
/// dragged up for more, double-clicked for none.
class _Sends extends StatelessWidget {
  final ChannelMix mix;
  final List<ReturnChannel> returns;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  /// narrow is a narrow column's: smaller dials, two to a row.
  final bool narrow;

  const _Sends({
    this.narrow = false,
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
              size: narrow ? 18 : 24,
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
  final double size;

  const _SendDial({
    this.size = 24,
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
  /// _from is where the drag started, and _was where the dial was then: the
  /// turn is measured from the press, not summed from each move, which loses
  /// moves that arrive between two frames.
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
        supportedDevices: dragPointers,
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
              size: Size.square(widget.size),
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
            // Shrunk to fit, in a mixer at its least.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 18, color: theme.studio.muted),
                const SizedBox(height: 6),
                RotatedBox(
                  quarterTurns: 3,
                  child: Text("Return",
                      style:
                          TextStyle(fontSize: 11, color: theme.studio.muted)),
                ),
              ]),
            ),
          ),
        ),
      );
}
