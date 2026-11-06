import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/transport.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/dock_switcher.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/play_bar_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/transport_controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// play_bar.dart is the play bar along the panels under the canvas: the
// transport, where the playhead is and what it is counted in, the marker
// under it, what is lit, the switcher that opens the panels (see
// dock_switcher.dart) and the rest behind its ⋯ menu. On its own, over the
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
  /// _leftKey and _rightKey are the bar's two ends, measured after each
  /// layout to know whether the panels' buttons fit with their names.
  final GlobalKey _leftKey = GlobalKey(), _rightKey = GlobalKey();

  /// _wideNeeds is how wide the bar must be for the buttons' names, as last
  /// measured with them; null until measured. _wideFor is what it was
  /// measured for -- the text's size and which buttons there are -- so a
  /// change measures it afresh.
  double? _wideNeeds;
  String _wideFor = "";

  /// _compact is whether the panels' buttons are their icons alone.
  bool _compact = false;

  /// _measure, after a layout, decides whether the names fit: the ends'
  /// own widths beside each other within [room], the right one within the
  /// part of it it may take.
  void _measure(double room) {
    if (!mounted) return;
    var left = _leftKey.currentContext?.findRenderObject();
    var right = _rightKey.currentContext?.findRenderObject();
    if (left is! RenderBox || right is! RenderBox) return;
    if (!left.hasSize || !right.hasSize) return;
    if (!_compact) {
      _wideNeeds = math.max(
          left.size.width + right.size.width + 16, right.size.width / 0.6);
    }
    var compact = _wideNeeds != null && room < _wideNeeds!;
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
            tooltip: controller.metronomeAvailable
                ? "Metronome: a click on every beat while it plays"
                : "The metronome needs the mix engine: Settings > Plugins > "
                    "Canvas > Play through the mix engine",
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
    Widget markers() {
      // One button for an action here, a stop until "At this frame" says
      // otherwise. A piece of sound adds a locator.
      if (actionHere == null) {
        return sound
            ? TransportButton(
                key: const ValueKey("addLocator"),
                width: null,
                tooltip: "Add a locator here: a named place to jump to",
                onPressed: controller.addLocator,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.flag_outlined),
                  SizedBox(width: 4),
                  Text("Locator",
                      style: TextStyle(fontWeight: FontWeight.w500)),
                ]),
              )
            : CanvasIconButton(
                key: const ValueKey("addAction"),
                icon: Icons.flag_outlined,
                tooltip: "Add Timeline Action",
                onPressed: () => _addAction(TimelineActionKind.stop),
              );
      }
      return Row(mainAxisSize: MainAxisSize.min, children: [
        CanvasDropdown<TimelineActionKind>(
          label: "At this frame",
          value: actionHere.kind,
          width: 116,
          options: [for (var k in TimelineActionKind.values) (k, k.label)],
          onChanged: (v) => _replaceAction(actionHere.copyWith(kind: v)),
        ),
        // A word or two beside the flag, and whether it shows.
        CanvasTextField(
          key: const ValueKey("actionLabel"),
          label: "Label",
          value: actionHere.label,
          width: 110,
          grow: false,
          onChanged: (v) {
            controller.beginInteraction();
            var document = controller.document;
            controller.apply(
                document.copyWith(actions: [
                  for (var a in document.actions)
                    a.frame == actionHere.frame ? a.copyWith(label: v) : a,
                ]),
                transient: true);
          },
          onCommit: controller.endInteraction,
        ),
        if (actionHere.kind != TimelineActionKind.locator)
          CanvasToggle(
            key: const ValueKey("actionShowLabel"),
            label: "Show label",
            value: actionHere.showLabel,
            onChanged: (v) => _replaceAction(actionHere.copyWith(showLabel: v)),
          ),
        // A stop that waits for one of the game's actions as well as Play
        // ("press A to start").
        if (actionHere.kind == TimelineActionKind.stop)
          CanvasDropdown<String>(
            key: const ValueKey("actionWaitsFor"),
            label: "Goes on when",
            value: document.controlsNow.any((a) => a.id == actionHere.waitsFor)
                ? actionHere.waitsFor
                : "",
            width: 150,
            options: [
              ("", "Played again"),
              for (var a in document.controlsNow)
                (a.id, "${a.name} is pressed"),
            ],
            onChanged: (v) => _replaceAction(actionHere.copyWith(waitsFor: v)),
          ),
        if (actionHere.kind == TimelineActionKind.loop ||
            actionHere.kind == TimelineActionKind.jump)
          CanvasNumberField(
            label: "To frame",
            value: actionHere.target.toDouble(),
            min: 0,
            max: (document.frames - 1).toDouble(),
            width: 56,
            onChanged: (v) =>
                _replaceAction(actionHere.copyWith(target: v.round())),
          ),
        if (actionHere.kind == TimelineActionKind.loop)
          CanvasNumberField(
            label: "Times (0 = ∞)",
            value: actionHere.repeats.toDouble(),
            min: 0,
            max: 999,
            width: 56,
            onChanged: (v) =>
                _replaceAction(actionHere.copyWith(repeats: v.round())),
          ),
        CanvasIconButton(
          icon: Icons.close,
          tooltip: "Remove this marker",
          onPressed: () => _removeAction(actionHere.frame),
        ),
      ]);
    }

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
    // A marker under the playhead, and what it does, or one to add.
    var marker = MenuAnchor(
      menuChildren: [
        Padding(padding: const EdgeInsets.all(10), child: markers()),
      ],
      builder: (context, menu, _) => TransportButton(
        key: const ValueKey("markerMenu"),
        width: null,
        icon: actionHere == null ? Icons.outlined_flag : Icons.flag,
        tooltip: actionHere == null
            ? "A marker here"
            : "The marker here: ${actionHere.label.isEmpty ? actionHere.kind.label : actionHere.label}",
        on: actionHere != null,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
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
      onAddMarker: () => sound
          ? controller.addLocator()
          : _addAction(TimelineActionKind.locator),
      onCustomiseSidebars: widget.onCustomiseSidebars,
    );

    return CanvasControlScope(
      maxWidth: 400,
      hoverCaptions: true,
      child: LayoutBuilder(builder: (context, box) {
        // Short of room, the panels' buttons are their icons alone, and
        // past that the right-hand end scrolls too, rather than running off
        // the bar.
        var scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
        // Measured rather than guessed: with their names while they fit
        // beside the transport. A new text size, or other buttons, are
        // measured again with their names.
        var dock = controller.dock;
        var measuredFor = "$scale|${dock.switcher}|${dock.showLayouts}|"
            "${dock.arrangements.length}|${dock.places}";
        if (measuredFor != _wideFor) {
          _wideFor = measuredFor;
          _wideNeeds = null;
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
          // Scrolls sideways rather than overflowing on a narrow window.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child:
                  Row(key: _leftKey, mainAxisSize: MainAxisSize.min, children: [
                transportMin(),
                readout,
                marker,
                if (back)
                  TransportGroup(children: [
                    TransportButton(
                      key: const ValueKey("backToTimeline"),
                      width: null,
                      icon: Icons.keyboard_return,
                      tooltip: "Something left the timeline for its slots, or "
                          "a setting is held by hand: press to follow the "
                          "timeline again",
                      on: true,
                      lit: const Color(0xFFF2A33D),
                      onPressed: () {
                        if (controller.offTimeline) controller.backToTimeline();
                        if (controller.anyOverridden) {
                          controller.backToArrangement();
                        }
                      },
                      child: const Text("Back to timeline",
                          style: TextStyle(fontWeight: FontWeight.w500)),
                    ),
                  ]),
              ]),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                  key: _rightKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    lit,
                    const SizedBox(width: 4),
                    switcher,
                    more,
                  ]),
            ),
          ),
        ]);
      }),
    );
  }

  void _addAction(TimelineActionKind kind) {
    var document = controller.document;
    var actions = [
      ...document.actions.where((a) => a.frame != controller.frame),
      TimelineAction(
        id: motionId("m"),
        frame: controller.frame,
        kind: kind,
        // A loop with nothing to loop back to is useless, so it defaults to
        // the start.
        target: 0,
      ),
    ];
    controller.apply(document.copyWith(actions: actions));
  }

  void _removeAction(int frame) {
    var document = controller.document;
    controller.apply(document.copyWith(
        actions: document.actions.where((a) => a.frame != frame).toList()));
  }

  void _replaceAction(TimelineAction action) {
    var document = controller.document;
    controller.apply(document.copyWith(actions: [
      ...document.actions.where((a) => a.frame != action.frame),
      action,
    ]));
  }
}
