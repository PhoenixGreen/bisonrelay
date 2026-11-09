import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/transport.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/dock_switcher.dart';
import 'package:bruig/plugin_system/canvas/ui/help_note.dart';
import 'package:bruig/plugin_system/canvas/ui/marker_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/play_bar_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/transport_controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// play_bar.dart is the play bar along the panels under the canvas (Ken,
// 2026-11-08, "play and timer sections in the middle of the bar"): the
// switcher that opens the panels on the left (see dock_switcher.dart); in the
// middle the transport, where the playhead is and what it is counted in, and
// the Marker menu (marker_panel.dart); on the right Back to the timeline
// when something has left it, what is lit, a "?" and the settings. No hover
// tips: the "?" explains. On its own, over the
// panels or under them (see CanvasController.barBelow), so it stays where it
// is whichever panels are open; the timeline draws one of its own only when
// it is used without the page (see CanvasTimeline.showBar).

/// playBarHeight is the bar: its controls, with no captions over them --
/// the captions are their hover text. See CanvasControlScope.
const double playBarHeight = controlHeight + 6;

/// transportKey is the keyboard of the play bar and the timeline: the space
/// bar plays and stops, and the arrows walk the frames. Returns null for a
/// key that is not one of these, so a caller can go on with its own.
KeyEventResult? transportKey(CanvasController controller, KeyEvent event) {
  // A game playing has the keys: Space jumps and the arrows run, rather
  // than playing the timeline or walking its frames. See gameKey.
  if (controller.gaming) return KeyEventResult.handled;
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  // Never while somebody is typing (see isTypingInAField): this runs before
  // the app's text-editing shortcuts, so the arrows and space would
  // otherwise scrub and play.
  if (isTypingInAField()) return KeyEventResult.ignored;
  switch (event.logicalKey) {
    case LogicalKeyboardKey.space:
      controller.togglePlay();
    case LogicalKeyboardKey.arrowLeft:
      controller.stepFrame(-1);
    case LogicalKeyboardKey.arrowRight:
      controller.stepFrame(1);
    case LogicalKeyboardKey.arrowUp:
      controller.stepFrame(-10);
    case LogicalKeyboardKey.arrowDown:
      controller.stepFrame(10);
    default:
      return null;
  }
  return KeyEventResult.handled;
}

/// CanvasPlayBar is the play bar: see the top of the file.
class CanvasPlayBar extends StatefulWidget {
  final CanvasController controller;

  /// switcher is what opens the panels, at the bar's right end: the dock's
  /// (see DockSwitcherBar) unless another is given.
  final Widget? switcher;

  /// onCustomiseSidebars opens the sidebars' settings, from the bar's
  /// settings; with none, they have no such line.
  final VoidCallback? onCustomiseSidebars;

  const CanvasPlayBar(
      {required this.controller,
      this.switcher,
      this.onCustomiseSidebars,
      super.key});

  @override
  State<CanvasPlayBar> createState() => _CanvasPlayBarState();
}

class _CanvasPlayBarState extends State<CanvasPlayBar> {
  /// _leftKey is the switcher and _centreKey the middle, measured after
  /// each layout to know whether the panels' buttons fit with their names.
  final GlobalKey _leftKey = GlobalKey(), _centreKey = GlobalKey();

  /// _wideNeeds is how wide the bar must be for the buttons' names, as last
  /// measured with them; null until measured. _wideFor is what it was
  /// measured for -- the text's size and which buttons there are -- so a
  /// change measures it afresh.
  double? _wideNeeds;
  String _wideFor = "";

  /// _centreWide is the middle's width, measured with the names too.
  double? _centreWide;

  /// _compact is whether the panels' buttons are their icons alone.
  bool _compact = false;

  /// _measure, after a layout, decides whether the names fit: the
  /// switcher, as wide as it is with them, within the half of [room] the
  /// middle leaves it.
  void _measure(double room) {
    if (!mounted) return;
    var left = _leftKey.currentContext?.findRenderObject();
    var centre = _centreKey.currentContext?.findRenderObject();
    if (left is! RenderBox || centre is! RenderBox) return;
    if (!left.hasSize || !centre.hasSize) return;
    // Both measured as they are with their names: compact makes the middle
    // narrower too, and deciding on that would undo itself the next frame.
    if (!_compact) {
      _wideNeeds = left.size.width;
      _centreWide = centre.size.width;
    }
    var side = (room - (_centreWide ?? centre.size.width) - 24) / 2;
    var compact = _wideNeeds != null && side < _wideNeeds!;
    if (compact != _compact) setState(() => _compact = compact);
  }

  CanvasController get controller => widget.controller;

  /// _focus takes the keyboard once one of the bar's controls is pressed,
  /// so the space bar and the arrows go on working: see transportKey.
  final FocusNode _focus = FocusNode();

  static const _trackpadKey = "canvasTimelineTrackpad";
  static const _snapKey = "canvasTimelineSnap";
  static const _barBelowKey = "canvasTimelineBarBelow";

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    _readSettings();
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// _readSettings puts back the reader's choices kept on the device:
  /// scrubbing, snapping and where the bar sits.
  Future<void> _readSettings() async {
    var scrolls = await StorageManager.readBool(_trackpadKey);
    var snaps = await StorageManager.readBool(_snapKey);
    var below = await StorageManager.readBool(_barBelowKey);
    if (!mounted) return;
    controller.trackpadScrolls = scrolls;
    controller.snapping = snaps;
    controller.barBelow = below;
  }

  void _setSnapping(bool value) {
    controller.snapping = value;
    StorageManager.saveBool(_snapKey, value);
  }

  void _setTrackpadScrolls(bool value) {
    controller.trackpadScrolls = value;
    StorageManager.saveBool(_trackpadKey, value);
  }

  void _setBarBelow(bool value) {
    controller.barBelow = value;
    StorageManager.saveBool(_barBelowKey, value);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var document = controller.document;
    var actionHere =
        document.actions.where((a) => a.frame == controller.frame).firstOrNull;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) =>
          transportKey(controller, event) ?? KeyEventResult.ignored,
      child: SizedBox(
        height: playBarHeight,
        child: _bar(theme, document, actionHere),
      ),
    );
  }

  /// _bar is the play bar: the transport, where the playhead is, what is
  /// lit, and the panels' switcher, with the rest behind the ⋯ menu. See transport_controls.dart. A piece of sound has its tempo, metre
  /// and quantise here, and counts in bars; a document of scenes has its
  /// frames.
  Widget _bar(ThemeNotifier theme, CanvasDocument document,
      TimelineAction? actionHere) {
    var sound = document.kind.isAudio;
    var audio = document.audio;
    var rate = math.max(1, document.frameRate);
    var playable = (controller.playAll && document.hasScenes
            ? document.playFrames
            : document.frames) >
        1;
    void writeAudio(AudioSettings next) =>
        controller.apply(document.copyWith(audio: next));
    var (loopFrom, loopLength) = controller.loopRange;
    var looping = controller.looping;

    Widget timing() {
      if (sound) {
        return TransportGroup(children: [
          // Taps of the beat the time signature counts; the tempo is in quarter
          // notes, as it is everywhere else.
          TapTempoButton(
              onTempo: (bpm) =>
                  writeAudio(audio.copyWith(tempo: bpm * audio.beatUnit / 4))),
          CanvasNumberField(
            key: const ValueKey("audioTempo"),
            label: "Tempo (BPM)",
            value: audio.tempo,
            min: 20,
            max: 400,
            decimals: 2,
            width: 64,
            grow: false,
            onChanged: (v) {
              controller.beginInteraction();
              controller.apply(
                  document.copyWith(audio: audio.copyWith(tempo: v)),
                  transient: true);
            },
            onCommit: controller.endInteraction,
          ),
          CanvasDropdown<String>(
            key: const ValueKey("audioSignature"),
            label: "Time signature",
            value: audio.signature,
            width: 64,
            options: [
              for (var (b, u) in timeSignatures) ("$b/$u", "$b/$u"),
              if (!timeSignatures
                  .any((t) => "${t.$1}/${t.$2}" == audio.signature))
                (audio.signature, audio.signature),
            ],
            onChanged: (v) {
              var parts = v.split("/");
              writeAudio(audio.copyWith(
                  beatsPerBar: int.parse(parts[0]),
                  beatUnit: int.parse(parts[1])));
            },
          ),
          TransportButton(
            key: const ValueKey("metronome"),
            tooltip: "Metronome: a click on every beat while it plays",
            on: controller.metronome,
            onPressed: () => controller.metronome = !controller.metronome,
            child: const MetronomeIcon(),
          ),
          CanvasDropdown<Quantise>(
            key: const ValueKey("audioQuantise"),
            label: "Quantise",
            value: audio.quantise,
            width: 74,
            options: [for (var q in Quantise.values) (q, q.label)],
            onChanged: (q) => writeAudio(audio.copyWith(quantise: q)),
          ),
        ]);
      }
      return TransportGroup(children: [
        // The master canvas is as long as the scenes it covers, so it has no
        // length of its own to set.
        if (document.editingMaster)
          TransportReadout(
            key: const ValueKey("canvasFramesMaster"),
            caption: "LENGTH",
            value: "${document.frames}",
            tooltip: "How long the whole sequence runs: every scene end to "
                "end. The master canvas is as long as what it covers, so "
                "this follows the scenes rather than being set here.",
          )
        else
          CanvasNumberField(
            key: const ValueKey("canvasFrames"),
            label: "Length",
            value: document.frames.toDouble(),
            min: 1,
            max: maxFrameCount.toDouble(),
            width: 68,
            grow: false,
            onChanged: (v) {
              controller.beginInteraction();
              controller.setSceneLength(v.round(), transient: true);
            },
            onCommit: controller.endInteraction,
          ),
        CanvasNumberField(
          key: const ValueKey("canvasFrameRate"),
          label: "Per second",
          value: document.frameRate.toDouble(),
          min: 1,
          max: 60,
          width: 48,
          grow: false,
          onChanged: (v) {
            controller.beginInteraction();
            controller.apply(document.copyWith(frameRate: v.round()),
                transient: true);
          },
          onCommit: controller.endInteraction,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
              document.isAnimated
                  ? "${document.durationSeconds.toStringAsFixed(1)}s"
                  : "Still",
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                  fontSize: 11, color: theme.colors.onSurfaceVariant)),
        ),
      ]);
    }

    var timelinePlays = controller.playing && !controller.sessionOnly;
    // The bar holds what is pressed while working: the transport, where the
    // playhead is, and the panels' switcher. The timing is behind the
    // readout and the rest behind the settings button; an option turned on
    // there shows on the bar, lit, to be turned off here.
    var back = controller.offTimeline || controller.anyOverridden;
    Widget transportMin() => TransportGroup(children: [
          TransportButton(
            key: const ValueKey("play"),
            icon: timelinePlays ? Icons.pause : Icons.play_arrow,
            tooltip: timelinePlays ? "Pause" : "Play (Space)",
            on: timelinePlays,
            lit: const Color(0xFF3CCF7A),
            onPressed: !playable
                ? null
                : controller.sessionOnly
                    ? controller.play
                    : controller.togglePlay,
          ),
          TransportButton(
            key: const ValueKey("stopPlaying"),
            icon: Icons.stop,
            tooltip: "Stop: back to where Play started; again, to the start",
            onPressed: controller.stopPlaying,
          ),
          TransportButton(
            key: const ValueKey("record"),
            tooltip: controller.recording
                ? "Stop recording: what was played is kept"
                : "Record: what is played -- on an instrument, or launched "
                    "from slots -- is written onto the timeline",
            on: controller.recording,
            lit: const Color(0xFF4A1F1F),
            onPressed: () => controller.recording = !controller.recording,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: controller.recording
                      ? const Color(0xFFFF5A5A)
                      : const Color(0xFF9A5A5A)),
            ),
          ),
          TransportButton(
            key: const ValueKey("loop"),
            icon: Icons.repeat,
            tooltip: "Loop: play goes round between the brace's ends on the "
                "ruler",
            on: looping,
            onPressed: () => controller.looping = !looping,
          ),
          // Which of the two Play means, where there is more than one scene:
          // lit, the timeline runs along them all, the scenes over the
          // channels.
          if (document.hasScenes)
            TransportButton(
              key: const ValueKey("playAll"),
              icon: Icons.playlist_play,
              tooltip: controller.playAll
                  ? "Plays every scene: press for the scene in front of you"
                  : "Play every scene, one after another",
              on: controller.playAll,
              onPressed: () => controller.playAll = !controller.playAll,
            ),
        ]);
    // Where the playhead is; pressed, the timing it is counted in.
    var readout = MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                timing(),
                const SizedBox(height: 8),
                TransportGroup(children: [
                  TransportReadout(
                    key: const ValueKey("loopFrom"),
                    fieldKey: const ValueKey("loopFromField"),
                    caption: "LOOP FROM",
                    dim: !looping,
                    value: sound
                        ? barsText(audio, loopFrom, rate)
                        : "${loopFrom + 1}",
                    widest: sound
                        ? barsText(
                            audio, math.max(0, document.frames - 1), rate)
                        : "${document.frames}",
                    tooltip: "Where the loop starts. Press to type it.",
                    onSubmit: (typed) {
                      var at = parsePosition(typed, audio, rate, bars: sound);
                      if (at == null) return false;
                      controller.setLoop(at, loopLength);
                      return true;
                    },
                  ),
                  TransportReadout(
                    key: const ValueKey("loopLength"),
                    fieldKey: const ValueKey("loopLengthField"),
                    caption: "FOR",
                    dim: !looping,
                    value: sound
                        ? lengthText(audio, loopLength, rate)
                        : "$loopLength",
                    widest: sound
                        ? lengthText(audio, document.frames, rate)
                        : "${document.frames}",
                    tooltip: "How long the loop is. Press to type it.",
                    onSubmit: (typed) {
                      var length = parseLength(typed, audio, rate, bars: sound);
                      if (length == null) return false;
                      controller.setLoop(loopFrom, length);
                      return true;
                    },
                  ),
                ]),
              ]),
        ),
      ],
      builder: (context, menu, _) =>
          Row(mainAxisSize: MainAxisSize.min, children: [
        TransportPosition(
          audio: audio,
          bars: sound,
          frame: controller.frame,
          frames: document.frames,
          rate: rate,
          onGo: (f) => controller.stepFrame(f - controller.frame),
        ),
        TransportButton(
          key: const ValueKey("timingMenu"),
          icon: Icons.expand_more,
          tooltip: "The length, frame rate, tempo and loop",
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      ]),
    );
    // The marker under the playhead, named, or Markers: its panel lists
    // every marker and adds one (see marker_panel.dart).
    var marker = MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: MarkerPanel(controller: controller)),
      ],
      builder: (context, menu, _) => TransportButton(
        key: const ValueKey("markerMenu"),
        width: null,
        tooltip: "",
        on: actionHere != null || menu.isOpen,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(actionHere == null ? Icons.outlined_flag : Icons.flag,
              size: 16,
              color: actionHere == null ? null : markerColour(actionHere.kind)),
          if (!_compact) ...[
            const SizedBox(width: 5),
            Text(
                actionHere == null
                    ? "Markers"
                    : actionHere.label.isEmpty
                        ? actionHere.kind.label
                        : actionHere.label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
          const Icon(Icons.expand_more, size: 15),
        ]),
      ),
    );
    // What is turned on in the ⋯ menu, lit on the bar.
    var options = <(String, IconData, String, bool, VoidCallback)>[
      (
        "toolKnife",
        Icons.content_cut,
        "Knife: cut clips (K)",
        controller.timelineTool == TimelineTool.knife,
        () => controller.timelineTool =
            controller.timelineTool == TimelineTool.knife
                ? TimelineTool.select
                : TimelineTool.knife
      ),
      (
        "follow",
        Icons.keyboard_tab,
        "Follow the playhead",
        controller.followPlayhead,
        () => controller.followPlayhead = !controller.followPlayhead
      ),
      (
        "snap",
        Icons.grid_4x4,
        "Snapping",
        controller.snapping,
        () => _setSnapping(!controller.snapping)
      ),
      (
        "metronome",
        Icons.av_timer,
        "Metronome",
        controller.metronome,
        () => controller.metronome = !controller.metronome
      ),
      (
        "automationArm",
        Icons.timeline,
        "Record moves settings (automation)",
        controller.automationArmed,
        () => controller.automationArmed = !controller.automationArmed
      ),
      (
        "trackpadScrolls",
        Icons.swipe_outlined,
        "Scrubbing",
        controller.trackpadScrolls,
        () => _setTrackpadScrolls(!controller.trackpadScrolls)
      ),
    ];
    var show = controller.timelineShow;
    var lit = Row(mainAxisSize: MainAxisSize.min, children: [
      // Showing only some: lit, and pressed, everything again.
      if (show != TimelineShow.everything)
        TransportButton(
          key: const ValueKey("lit-show"),
          icon: show == TimelineShow.animation
              ? Icons.animation
              : Icons.graphic_eq,
          tooltip: "${show.label}: press to show everything",
          on: true,
          lit: const Color(0xFF3A2F12),
          onPressed: () => controller.timelineShow = TimelineShow.everything,
        ),
      for (var (key, icon, tip, on, press) in options)
        if (on)
          TransportButton(
            key: ValueKey("lit-$key"),
            icon: icon,
            tooltip: "$tip: on. Press to turn it off",
            on: true,
            lit: const Color(0xFF3A2F12),
            onPressed: press,
          ),
    ]);
    // One button for every setting the bar has: see play_bar_settings.dart.
    var more = PlayBarSettingsButton(
      controller: controller,
      knife: (
        key: options[0].$1,
        icon: options[0].$2,
        label: options[0].$3,
        on: options[0].$4,
        toggle: options[0].$5,
      ),
      toggles: [
        for (var (key, icon, label, on, toggle) in options.skip(1))
          (key: key, icon: icon, label: label, on: on, toggle: toggle),
      ],
      onBarBelow: () => _setBarBelow(!controller.barBelow),
      onAddMarker: () => addMarker(controller, TimelineActionKind.locator),
      onCustomiseSidebars: widget.onCustomiseSidebars,
    );

    return TooltipVisibility(
      visible: false,
      child: CanvasControlScope(
        maxWidth: 400,
        hoverCaptions: true,
        child: LayoutBuilder(builder: (context, box) {
          var scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
          // Measured rather than guessed: with their names while they fit
          // beside the middle. A new text size, or other buttons, are
          // measured again with their names.
          var dock = controller.dock;
          var measuredFor = "$scale|${dock.switcher}|${dock.showLayouts}|"
              "${dock.arrangements.length}|${dock.places}";
          if (measuredFor != _wideFor) {
            _wideFor = measuredFor;
            _wideNeeds = null;
            _centreWide = null;
            _compact = false;
          }
          var compact = _compact;
          var room = box.maxWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) => _measure(room));
          var switcher =
              widget.switcher ?? DockSwitcherBar(controller: controller);
          if (switcher is DockSwitcherBar && switcher.compact != compact) {
            switcher = switcher.copyWith(compact: compact);
          }
          return Row(children: [
            // The panels, on the left; scrolled rather than overflowing.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: KeyedSubtree(key: _leftKey, child: switcher),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // In the middle: the transport, where the playhead is, and the
            // markers -- always in the same place, whatever is either side.
            Row(key: _centreKey, mainAxisSize: MainAxisSize.min, children: [
              transportMin(),
              readout,
              if (!compact) _tempo(theme, document),
              const SizedBox(width: 4),
              marker,
            ]),
            const SizedBox(width: 12),
            // On the right: Back to the timeline beside the middle, when
            // something has left it; then what is lit, the "?" and the
            // settings at the end.
            Expanded(
              child: Row(children: [
                // Back to the timeline has all the room the rest leaves, so
                // it keeps its words; it gives way to them only short of it.
                Expanded(
                  child: back
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: _BackToTimeline(controller: controller))
                      : const SizedBox.shrink(),
                ),
                // Against the panel's right edge (Ken), whatever is beside.
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        lit,
                        const SizedBox(width: 6),
                        HelpNote(
                          id: "playBar",
                          title: "The play bar",
                          paragraphs: playBarHelp,
                        ),
                        const SizedBox(width: 4),
                        more,
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }

  /// _tempo is what the playhead is counted in, small beside where it is:
  /// the tempo and metre of a piece of sound, a scene's frames a second.
  Widget _tempo(ThemeNotifier theme, CanvasDocument document) {
    var colors = theme.colors;
    // One line, so it fits the bar at any text size.
    var (first, second) = document.kind.isAudio
        ? (
            _trim(document.audio.tempo.toStringAsFixed(2)),
            document.audio.signature
          )
        : ("${document.frameRate}", "fps");
    return Padding(
      key: const ValueKey("playBarTempo"),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text.rich(
          TextSpan(children: [
            TextSpan(text: first, style: TextStyle(color: colors.onSurface)),
            TextSpan(text: " $second"),
          ]),
          maxLines: 1,
          style: TextStyle(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontSize: 11,
              color: colors.onSurfaceVariant)),
    );
  }

  static String _trim(String n) =>
      n.contains(".") ? n.replaceFirst(RegExp(r"\.?0+$"), "") : n;
}

/// playBarHelp is the play bar's "?".
const playBarHelp = [
  "The panels are on the left: press one to open or close it. Its small "
      "picture shows where it opens; drag it onto the map that appears to "
      "move it, or right-click it.",
  "Play, stop, record and loop are in the middle, with where the playhead "
      "is. Press the position to type where to go; the arrow beside it opens "
      "the length, the frame rate, the tempo and the loop.",
  "The flag is the Marker menu: the marker under the playhead, every marker "
      "in the canvas, and a way to add one.",
  "Back to the timeline appears only when something has left the timeline. "
      "The gear holds the panels' places and layouts and the timeline's "
      "settings.",
];

/// _BackToTimeline is Back to the timeline (Ken, 2026-11-08: "what does it
/// do and is it needed? if it is needed it needs a redesign"): shown only
/// while something has left the timeline, amber, with how many; pressed,
/// everything goes back. Its arrow lists them -- the rows playing from their
/// slots, and the channels with settings held by hand off their lanes -- each
/// to send back alone. It is Ableton's Back to Arrangement.
class _BackToTimeline extends StatelessWidget {
  final CanvasController controller;
  const _BackToTimeline({required this.controller});

  static const _ink = Color(0xFFF6C46A);
  static const _edge = Color(0xFF7A5A1E);
  static const _fill = Color(0xFF3A2A10);

  void _all() {
    if (controller.offTimeline) controller.backToTimeline();
    if (controller.anyOverridden) controller.backToArrangement();
  }

  @override
  Widget build(BuildContext context) {
    var items = controller.offTimelineItems;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: InkWell(
            key: const ValueKey("backToTimeline"),
            onTap: _all,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.keyboard_return, size: 15, color: _ink),
                const SizedBox(width: 6),
                const Flexible(
                  child: Text("Back to timeline",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _ink)),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    key: const ValueKey("backToTimelineCount"),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF2A33D),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text("${items.length}",
                        style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                            fontSize: 10.5,
                            color: Color(0xFF2A1A04))),
                  ),
                ],
              ]),
            ),
          ),
        ),
        Container(width: 1, color: _edge),
        MenuAnchor(
          alignmentOffset: const Offset(0, 6),
          menuChildren: [_OffList(controller: controller, onAll: _all)],
          builder: (context, menu, _) => InkWell(
            key: const ValueKey("backToTimelineList"),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: const SizedBox(
                width: 24,
                height: 28,
                child: Icon(Icons.expand_more, size: 15, color: _ink)),
          ),
        ),
      ]),
    );
  }
}

/// _OffList is what is off the timeline, in its two groups, each to send
/// back alone; and all of it at once.
class _OffList extends StatelessWidget {
  final CanvasController controller;
  final VoidCallback onAll;
  const _OffList({required this.controller, required this.onAll});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var colors = ThemeNotifier.of(context).colors;
          var items = controller.offTimelineItems;
          Widget heading(String text) => Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
                child: Text(text.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant)),
              );
          Widget row(OffTimelineItem item) => Container(
                key: ValueKey(
                    "offTimeline-${item.isHeld ? "held" : "slots"}-${item.key}"),
                height: 30,
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Expanded(
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                  ),
                  if (item.isHeld)
                    Text("${item.held} setting${item.held == 1 ? "" : "s"}",
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)),
                  IconButton(
                    key: ValueKey("backToTimeline-${item.key}"),
                    iconSize: 15,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.backToTimelineFor(item),
                    icon: const Icon(Icons.keyboard_return),
                  ),
                ]),
              );
          var slots = [
            for (var i in items)
              if (!i.isHeld) i
          ];
          var held = [
            for (var i in items)
              if (i.isHeld) i
          ];
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              width: 300,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(child: heading("Off the timeline")),
                      const HelpNote(
                        id: "backToTimeline",
                        title: "Back to the timeline",
                        size: 16,
                        paragraphs: [
                          "A row playing from its slots stops its timeline "
                              "clips; a setting moved by hand while its lane "
                              "plays stops following the lane. Both stay that "
                              "way until they are sent back.",
                          "Back to the timeline sends everything back. Send "
                              "one back here, or with the return arrow on its "
                              "row.",
                        ],
                      ),
                    ]),
                    if (slots.isNotEmpty) ...[
                      heading("Playing from slots"),
                      for (var i in slots) row(i),
                    ],
                    if (held.isNotEmpty) ...[
                      heading("Held by hand"),
                      for (var i in held) row(i),
                    ],
                    const SizedBox(height: 6),
                    FilledButton.tonalIcon(
                      key: const ValueKey("backToTimelineAll"),
                      onPressed: onAll,
                      icon: const Icon(Icons.keyboard_return, size: 15),
                      label: const Text("All back to the timeline",
                          style: TextStyle(fontSize: 12)),
                    ),
                  ]),
            ),
          );
        },
      );
}
