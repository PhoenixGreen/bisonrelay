import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/warp.dart' show onsets;
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show ControlPoint;
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/automation_lanes.dart'
    show envelopeLengths, settingLabel;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show dragPointers;
import 'package:bruig/plugin_system/canvas/ui/piano_roll.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

// clip_editor.dart is the clip editor -- Ableton's clip view: a clip in a
// slot, double-clicked, opens here in the effects panel. Down the left, its
// settings in columns: Clip (where it starts, its loop, its colour), Launch
// (how a press plays it, what its launch waits for, what it does when it
// has played), and Audio (gain, reverse, crop) or Notes (the pitch and time
// tools). On the right, what it plays: an audio clip's sound, with its
// start and loop on a ruler over it to drag; a MIDI clip's notes in the
// piano roll.
//
// Everything is in beats, as the clip is (see SessionClip). An audio clip
// warped keeps the song's tempo -- its sound rendered stretched, see
// warp.dart -- and its warp markers pin moments of the sound to beats.
// Its envelopes -- gain and pan -- are drawn over its sound and rendered
// with it; a MIDI clip's are its controllers' curves, in the piano roll.
//
// It is a device in the effects strip, first in the channel's chain:
// narrow, one column of settings at a time beside what it plays; widened
// with its button, all of them, and what it plays as wide as the strip.

const double _columnW = 220;

/// editorNarrowWidth is the clip editor's width in the strip, unwidened.
const double editorNarrowWidth = 760;

/// EditorFrame is the clip editor's -- or a part's piano roll's -- place in
/// the effects strip: a bar along the top, as every device has, with its
/// name and its buttons, and the editor under it, at the strip's height --
/// given the room, not scaled to it as a device is.
class EditorFrame extends StatelessWidget {
  final String id;
  final String title;
  final double width;
  final double height;
  final bool wide;
  final VoidCallback onWide;
  final VoidCallback onClose;
  final Widget child;

  /// onResize is its right edge dragged, to the width it would be: wider
  /// or narrower, the notes or the sound with it.
  final ValueChanged<double>? onResize;

  const EditorFrame({
    this.onResize,
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.wide,
    required this.onWide,
    required this.onClose,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var ink = look.colors.onSurface;
    Widget frame = Container(
      key: ValueKey("device-$id"),
      width: width,
      height: height,
      decoration: BoxDecoration(
          color: look.studio.panel,
          border: Border.all(color: Colors.black38),
          borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 28,
          color: look.colors.surfaceContainerHighest,
          padding: const EdgeInsets.only(left: 8),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
            ),
            IconButton(
              key: const ValueKey("editorWide"),
              tooltip: wide
                  ? "Narrower"
                  : "Wider: every setting, and more "
                      "room for what it plays",
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: Icon(wide ? Icons.close_fullscreen : Icons.open_in_full,
                  color: ink),
              onPressed: onWide,
            ),
            IconButton(
              key: const ValueKey("editorClose"),
              tooltip: "Close the editor",
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, color: ink),
              onPressed: onClose,
            ),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
    if (onResize case var resize?) {
      frame = Stack(children: [
        frame,
        // Its right edge, dragged: no handle, only the cursor to say so.
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 6,
          child: _EdgeDrag(
              key: ValueKey("editorEdge-$id"), width: width, onResize: resize),
        ),
      ]);
    }
    return frame;
  }
}

/// _EdgeDrag is an editor's right edge, dragged: the width it had when the
/// drag began, and how far the pointer has gone since -- not each move
/// added to the last, which lost moves that came between two frames.
class _EdgeDrag extends StatefulWidget {
  final double width;
  final ValueChanged<double> onResize;
  const _EdgeDrag({required this.width, required this.onResize, super.key});

  @override
  State<_EdgeDrag> createState() => _EdgeDragState();
}

class _EdgeDragState extends State<_EdgeDrag> {
  double _from = 0, _was = 0;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          supportedDevices: dragPointers,
          behavior: HitTestBehavior.opaque,
          // From the press: the edge stays under the pointer.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (d) {
            _from = d.globalPosition.dx;
            _was = widget.width;
          },
          onHorizontalDragUpdate: (d) =>
              widget.onResize(_was + d.globalPosition.dx - _from),
        ),
      );
}

class ClipEditor extends StatefulWidget {
  final CanvasController controller;

  /// wide is whether every column of settings shows, or one at a time.
  final bool wide;

  /// part is whether it edits a MIDI channel's part -- the piano roll's,
  /// opened from its In -- rather than a clip in a slot: its place on the
  /// timeline and its notes' tools, and Play for the timeline.
  final bool part;
  const ClipEditor(
      {required this.controller,
      this.wide = true,
      this.part = false,
      super.key});

  @override
  State<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<ClipEditor> {
  CanvasController get c => widget.controller;

  /// _said is what the last Reverse, Crop or Warp had to say, and _busy
  /// whether one is still working.
  String? _said;
  bool _busy = false;

  /// _shown is the column of settings shown, narrow: 0 Clip, 1 Launch, 2
  /// Audio or Notes.
  int _shown = 0;

  /// _envelope is the envelope drawn over an audio clip's sound, by its key
  /// -- its gain or pan, or a setting of its channel: see
  /// SessionClip.curveOf -- or null for its gain.
  String? _envelope;
  bool _envelopes = false;

  Future<void> _run(Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    String? said;
    try {
      said = await job();
    } catch (exception, stack) {
      // Said, not lost: a failure here was a press that did nothing.
      debugPrint("The clip editor could not do that: $exception\n$stack");
      said = "That did not work: $exception";
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _said = said;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          var look = MixerLook.of(context);
          if (widget.part) {
            var t = c.pianoRoll;
            var content = c.rollContent;
            var e = t == null ? null : c.instrumentOf(t.channel);
            if (t == null || t.row != null || content == null || e == null) {
              return const SizedBox();
            }
            return _layout(
                look,
                _partHeader(look, e),
                // The columns a slot's clip has, in the same places: a part's
                // place on the timeline, how it is launched -- it is not, but
                // a copy of it in a slot is -- and its notes' tools.
                [
                  ("Clip", _partColumn(look, e, content), "partColumn"),
                  (
                    "Launch",
                    _partLaunchColumn(look, t.channel),
                    "launchColumn"
                  ),
                  ("Notes", _notesColumn(look), "notesColumn"),
                ],
                PianoRoll(controller: c, inClipEditor: true));
          }
          var t = c.clipEditing;
          var clip = c.editedClip;
          if (t == null || clip == null) return const SizedBox();
          return _layout(
              look,
              _header(look, t, clip),
              [
                ("Clip", _clipColumn(look, clip), "clipColumn"),
                ("Launch", _launchColumn(look, clip), "launchColumn"),
                clip.midi
                    ? ("Notes", _notesColumn(look), "notesColumn")
                    : ("Audio", _audioColumn(look, clip), "audioColumn"),
              ],
              clip.midi
                  ? PianoRoll(controller: c, inClipEditor: true)
                  : _SampleView(
                      controller: c,
                      clip: clip,
                      envelope: _envelopes ? _envelopeKey(clip, t) : null,
                      envelopeRest: _envelopeRest(_envelopeKey(clip, t), t),
                      envelopeLength: clip.lengthOf(_envelopeKey(clip, t))));
        },
      );

  /// _layout is the editor: its header over its columns of settings --
  /// every one, wide; narrow, one at a time, picked above it -- and what it
  /// plays beside them.
  Widget _layout(MixerLook look, Widget header,
      List<(String, List<Widget>, String)> settings, Widget editor) {
    var columns = [
      for (var (title, children, key) in settings)
        _column(look, title, children, key: ValueKey(key)),
    ];
    var shown = _shown.clamp(0, columns.length - 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.wide)
            ...columns
          else
            SizedBox(
              width: _columnW,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Wrap(spacing: 3, runSpacing: 3, children: [
                        for (var (i, (label, _, _)) in settings.indexed)
                          _pill(look, label, i == shown,
                              () => setState(() => _shown = i),
                              key: ValueKey("clipShow-$i")),
                      ]),
                    ),
                    Expanded(child: columns[shown]),
                  ]),
            ),
          Expanded(child: editor),
        ]),
      ),
    ]);
  }

  /// _partHeader is a part's name and its channel's, and Play: the
  /// timeline, from the playhead -- dragged along the ruler over the notes.
  Widget _partHeader(MixerLook look, AudioElement e) {
    var lane = c.timelineChannels
        .where((l) => l.key == c.pianoRoll?.channel)
        .firstOrNull;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: look.studio.edge))),
      child: Row(children: [
        Icon(Icons.piano, size: 14, color: look.studio.muted),
        const SizedBox(width: 8),
        Flexible(
          child: Text("${e.name.isEmpty ? "Part" : e.name} · part",
              key: const ValueKey("partEditorName"),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: look.studio.text)),
        ),
        const SizedBox(width: 8),
        if (lane != null)
          Flexible(
            child: Text(lane.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _small(look, look.studio.muted)),
          ),
        const Spacer(),
        _pill(look, c.playing ? "■ Stop" : "▶ Play", c.playing, c.togglePlay,
            key: const ValueKey("partPlay"),
            tip: c.playing
                ? "Stop playing"
                : "Play the timeline from the playhead -- drag it along "
                    "the ruler over the notes"),
      ]),
    );
  }

  /// _partLaunchColumn is a part's Launch: it plays with the timeline, not
  /// from a slot -- but copied into one, it is launched as any clip is.
  List<Widget> _partLaunchColumn(MixerLook look, String channel) {
    var row = c.emptySlotOf(channel);
    return [
      Text(
          "A part plays with the timeline, from where it starts. To launch "
          "it, copy it into a slot: its launch settings are there.",
          style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: _pill(
            look, "Copy into a slot", false, row == null ? null : c.partToSlot,
            key: const ValueKey("partToSlot"),
            tip: row == null
                ? "Every slot of the channel is full"
                : "Into slot ${row + 1}, and open it there"),
      ),
      if (row == null) ...[
        const SizedBox(height: 4),
        Text("Every slot of the channel is full.",
            style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
      ],
    ];
  }

  /// _partColumn is where a part is: where it starts on the timeline, how
  /// long the roll shows it, and the playhead's place in it -- where a
  /// paste goes and Play starts.
  List<Widget> _partColumn(
      MixerLook look, AudioElement e, RollContent content) {
    var a = c.document.audio;
    var startBeats = e.clip.at /
        math.max(1, c.document.frameRate) /
        math.max(0.001, a.secondsPerBeat);
    var bars = content.beats / a.beatsPerBar;
    var cursor = c.rollCursor;
    return [
      _row(
          look,
          "Starts",
          _stepper(
              look,
              "partStart",
              _place(startBeats),
              e.clip.at <= 0 ? null : () => c.movePart(-1),
              () => c.movePart(1))),
      _row(
          look,
          "Length",
          Text(bars == 1 ? "1 bar" : "${bars.round()} bars",
              key: const ValueKey("partLength"), style: _small(look))),
      _row(
          look,
          "Playhead",
          _stepper(
              look,
              "partCursor",
              _place(cursor),
              cursor <= 0
                  ? null
                  : () => c.rollCursor = (cursor - 1).ceilToDouble(),
              () => c.rollCursor = (cursor + 1).floorToDouble())),
      Text(
          "Where a paste goes, and Play starts. Drag it along the ruler "
          "over the notes.",
          style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
    ];
  }

  // ---- The parts

  TextStyle _small(MixerLook look, [Color? colour]) =>
      TextStyle(fontSize: 11, color: colour ?? look.studio.text);

  Widget _pill(MixerLook look, String label, bool on, VoidCallback? onTap,
          {Key? key, String? tip}) =>
      Tooltip(
        message: tip ?? label,
        child: Material(
          color: on ? look.studio.on : look.studio.raised,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: onTap == null
                          ? look.studio.muted
                          : on
                              ? look.studio.onOn
                              : look.studio.text)),
            ),
          ),
        ),
      );

  Widget _drop<T>(MixerLook look, Key key, T value, List<(String, T)> items,
          ValueChanged<T> onChanged) =>
      DropdownButton<T>(
        key: key,
        value: value,
        isDense: true,
        isExpanded: true,
        underline: const SizedBox(),
        style: _small(look),
        dropdownColor: look.colors.surfaceContainerHigh,
        items: [
          for (var (label, v) in items)
            DropdownMenuItem(
                value: v,
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  /// _row is a setting: its name, and what sets it.
  Widget _row(MixerLook look, String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
              width: 56,
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _small(look, look.studio.muted))),
          Expanded(child: child),
        ]),
      );

  /// _stepper is a value with a step down and a step up either side.
  Widget _stepper(MixerLook look, String key, String value, VoidCallback? down,
      VoidCallback? up,
      {ValueChanged<String>? typed}) {
    var style = _small(look).copyWith(fontFeatures: const [
      FontFeature.tabularFigures(),
    ]);
    return Row(children: [
      _step(look, "$key-down", Icons.remove, down),
      Expanded(
        child: typed == null
            ? Text(value,
                key: ValueKey(key),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style)
            : _TypedPlace(
                key: ValueKey(key), value: value, style: style, onTyped: typed),
      ),
      _step(look, "$key-up", Icons.add, up),
    ]);
  }

  Widget _step(
          MixerLook look, String key, IconData icon, VoidCallback? onTap) =>
      InkWell(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
              color: look.studio.raised,
              borderRadius: BorderRadius.circular(3)),
          child: Icon(icon,
              size: 12,
              color: onTap == null ? look.studio.muted : look.studio.text),
        ),
      );

  Widget _column(MixerLook look, String title, List<Widget> children,
          {Key? key}) =>
      Container(
        key: key,
        width: _columnW,
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: look.studio.edge))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: look.studio.text)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _header(MixerLook look, PianoRollTarget t, SessionClip clip) {
    var lane = c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var sound = clip.sound;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: look.studio.edge))),
      child: Row(children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: Color(sectionColors[clip.color % sectionColors.length]),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Flexible(
          child: Text(clip.name.isEmpty ? "Clip" : clip.name,
              key: const ValueKey("clipEditorName"),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: look.studio.text)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
              [
                lane?.name ?? "",
                "slot ${t.row! + 1}",
                if (!clip.midi && sound != null)
                  "${sound.name.isEmpty ? "sound" : sound.name}"
                      "${sound.length > 0 ? " · ${sound.length.toStringAsFixed(1)} s" : ""}",
              ].where((p) => p.isNotEmpty).join(" · "),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _small(look, look.studio.muted)),
        ),
        const Spacer(),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (_said case var said?)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(said,
                  key: const ValueKey("clipEditorSaid"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _small(look, const Color(0xFFFF8A80))),
            ),
          ),
        // Heard on its own, at once: with the transport stopped, the
        // timeline stays silent -- see CanvasController.sessionOnly.
        _pill(look, c.clipPreviewing ? "■ Stop" : "▶ Play", c.clipPreviewing,
            c.previewClip,
            key: const ValueKey("clipPreview"),
            tip: c.clipPreviewing
                ? "Stop it"
                : "Play it now, round its loop -- the timeline stays quiet"),
        const SizedBox(width: 4),
        // An audio clip's envelopes, over its sound: its own gain or pan,
        // or one of its channel's settings. A MIDI clip's are in the lanes
        // under its notes, chosen there.
        if (!clip.midi) ...[
          _pill(look, "Envelopes", _envelopes,
              () => setState(() => _envelopes = !_envelopes),
              key: const ValueKey("clipEnvelopes"),
              tip: "Its gain or its pan, or a setting of its channel, "
                  "changed as it plays: drawn over its sound"),
          if (_envelopes) ...[
            const SizedBox(width: 4),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: _drop(
                    look,
                    const ValueKey("clipEnvelopeTarget"),
                    _envelopeKey(clip, t),
                    _envelopeChoices(clip, t),
                    (v) => setState(() => _envelope = v)),
              ),
            ),
            // A setting's envelope: the clip's length, or its own.
            if (ClipEnvelope.values
                .every((e) => e.name != _envelopeKey(clip, t))) ...[
              const SizedBox(width: 4),
              SizedBox(
                width: 84,
                child: _drop(
                    look,
                    const ValueKey("clipEnvelopeLength"),
                    clip.lengthOf(_envelopeKey(clip, t)) ?? 0.0,
                    [
                      for (var (beats, label)
                          in envelopeLengths(c.document.audio.beatsPerBar))
                        (label, beats ?? 0.0)
                    ],
                    (v) => c.editClip((x) => x.withLength(
                        _envelopeKey(clip, t), v == 0 ? null : v))),
              ),
            ],
          ],
        ],
      ]),
    );
  }

  /// _envelopeChoices are what an audio clip's envelope can change: its own
  /// gain and pan, drawn into its sound, then its channel's settings, moved
  /// on the channel while it plays.
  List<(String, String)> _envelopeChoices(SessionClip clip, PianoRollTarget t) {
    var lane = c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var returns = c.document.returns;
    return [
      for (var e in ClipEnvelope.values) ("Clip › ${e.label}", e.name),
      if (lane != null)
        for (var a in automationTargets(lane.mix, returns))
          (settingLabel(a, lane.mix, returns), a.id),
    ];
  }

  /// _envelopeKey is the envelope shown: the one chosen, while its channel
  /// still has it, else the clip's gain.
  String _envelopeKey(SessionClip clip, PianoRollTarget t) {
    var key = _envelope;
    if (key != null && _envelopeChoices(clip, t).any((c) => c.$2 == key)) {
      return key;
    }
    return ClipEnvelope.gain.name;
  }

  /// _envelopeRest is envelope [key]'s height with no points: the clip as it
  /// is, or the setting where its channel has it.
  double _envelopeRest(String key, PianoRollTarget t) {
    for (var e in ClipEnvelope.values) {
      if (e.name == key) return e.rest;
    }
    var what = AutomationTarget.parse(key);
    var lane = c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    if (what == null || lane == null) return 0.5;
    return what.height(what.own(lane.mix));
  }

  /// _place is a place in a clip, as Ableton shows it: bar, beat, and
  /// sixteenth, from one.
  String _place(double beats) {
    var bpb = c.document.audio.beatsPerBar;
    var bar = (beats / bpb).floor() + 1;
    var beat = (beats % bpb).floor() + 1;
    var sixteenth = ((beats % 1) * 4).floor() + 1;
    return "$bar.$beat.$sixteenth";
  }

  List<Widget> _clipColumn(MixerLook look, SessionClip clip) {
    var bpb = c.document.audio.beatsPerBar;
    // A place typed, as Ableton's are: "3", "3.2" or "3.2.3" -- bar, beat,
    // sixteenth. One that is not a place is left as it was.
    ValueChanged<String> typed(
            SessionClip Function(SessionClip x, double beats) change) =>
        (text) {
          if (beatsOfPlace(text, bpb) case var b?)
            c.editClip((x) => change(x, b));
        };
    var playhead = c.clipPlayhead;
    var bars = clip.bars;
    var lengths = {
      0.25, 0.5, //
      ...clipBarChoices.map((b) => b.toDouble()),
      bars,
    }.toList()
      ..sort();
    String barsText(double b) =>
        b == 1 ? "1 bar" : "${b == b.roundToDouble() ? b.round() : b} bars";
    // Set: from where it is playing, to the beat.
    VoidCallback? set(SessionClip Function(double beat) change) =>
        playhead == null
            ? null
            : () => c.editClip((_) => change(playhead.floorToDouble()));
    return [
      _row(
          look,
          "Start",
          Row(children: [
            Expanded(
              child: _stepper(
                  look,
                  "clipStart",
                  _place(clip.start),
                  clip.start <= 0
                      ? null
                      : () => c.editClip((x) => x.copyWith(start: x.start - 1)),
                  () => c.editClip((x) => x.copyWith(start: x.start + 1)),
                  typed: typed((x, b) => x.copyWith(start: b))),
            ),
            const SizedBox(width: 4),
            _pill(look, "Set", false, set((b) => clip.copyWith(start: b)),
                key: const ValueKey("clipSetStart"),
                tip: "Start where it is playing now"),
          ])),
      _row(
          look,
          "Loop",
          Align(
            alignment: Alignment.centerLeft,
            child: _pill(look, clip.loop ? "On" : "Off", clip.loop,
                () => c.editClip((x) => x.copyWith(loop: !x.loop)),
                key: const ValueKey("clipLoop"),
                tip: "Round its loop until it is stopped, or once through"),
          )),
      _row(
          look,
          "Position",
          Row(children: [
            Expanded(
              child: _stepper(
                  look,
                  "clipLoopStart",
                  _place(clip.loopStart),
                  clip.loopStart <= 0
                      ? null
                      : () => c.editClip(
                          (x) => x.copyWith(loopStart: x.loopStart - 1)),
                  () =>
                      c.editClip((x) => x.copyWith(loopStart: x.loopStart + 1)),
                  typed: typed((x, b) => x.copyWith(loopStart: b))),
            ),
            const SizedBox(width: 4),
            _pill(look, "Set", false, set((b) => clip.copyWith(loopStart: b)),
                key: const ValueKey("clipSetLoop"),
                tip: "Its loop from where it is playing now"),
          ])),
      _row(
          look,
          "Length",
          _drop(
              look,
              const ValueKey("clipLength"),
              bars,
              [for (var b in lengths) (barsText(b), b)],
              (v) => c.editClip((x) => x.copyWith(bars: v)))),
      // Its end typed: the loop as long as that makes it.
      _row(
          look,
          "Ends",
          _TypedPlace(
              key: const ValueKey("clipEnds"),
              value: _place(clip.loopEnd(bpb)),
              style: _small(look),
              align: TextAlign.left,
              onTyped: typed((x, b) => b > x.loopStart
                  ? x.copyWith(bars: (b - x.loopStart) / bpb)
                  : x))),
      _row(
          look,
          "Colour",
          Wrap(spacing: 3, runSpacing: 3, children: [
            for (var (i, colour) in sectionColors.indexed)
              GestureDetector(
                key: ValueKey("clipColour-$i"),
                onTap: () => c.editClip((x) => x.copyWith(color: i)),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                      color: Color(colour),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                          color: i == clip.color
                              ? look.studio.text
                              : Colors.transparent,
                          width: 2)),
                ),
              ),
          ])),
    ];
  }

  List<Widget> _launchColumn(MixerLook look, SessionClip clip) => [
        _row(
            look,
            "Mode",
            _drop(
                look,
                const ValueKey("clipLaunchMode"),
                clip.launch,
                [for (var m in LaunchMode.values) (m.label, m)],
                (v) => c.editClip((x) => x.copyWith(launch: v)))),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(clip.launch.hint,
              style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
        ),
        _row(
            look,
            "Legato",
            Align(
              alignment: Alignment.centerLeft,
              child: _pill(look, clip.legato ? "On" : "Off", clip.legato,
                  () => c.editClip((x) => x.copyWith(legato: !x.legato)),
                  key: const ValueKey("clipLegato"),
                  tip: "Take over from where the clip playing on the "
                      "channel had got to, rather than from the start"),
            )),
        // How much a pad's velocity -- a Push's, launching it -- sets how
        // loud it plays. A click is a full velocity.
        _row(
            look,
            "Velocity",
            _stepper(
                look,
                "clipVelocity",
                "${(clip.velocity * 100).round()}%",
                clip.velocity <= 0
                    ? null
                    : () => c.editClip((x) => x.copyWith(
                        velocity: ((x.velocity * 10).round() - 1) / 10)),
                clip.velocity >= 1
                    ? null
                    : () => c.editClip((x) => x.copyWith(
                        velocity: ((x.velocity * 10).round() + 1) / 10)))),
        _row(
            look,
            "Waits for",
            _drop<Quantise?>(
                look,
                const ValueKey("clipQuantise"),
                clip.quantise,
                [
                  ("The song's", null),
                  for (var q in Quantise.values)
                    (q == Quantise.off ? "Nothing" : q.label, q),
                ],
                (v) => c.editClip((x) => v == null
                    ? x.copyWith(clearQuantise: true)
                    : x.copyWith(quantise: v)))),
        const SizedBox(height: 4),
        _row(
            look,
            "Then",
            _drop(
                look,
                const ValueKey("clipFollow"),
                clip.follow,
                [for (var f in FollowAction.values) (f.label, f)],
                (v) => c.editClip((x) => x.copyWith(follow: v)))),
        if (clip.follow != FollowAction.none)
          _row(
              look,
              "After",
              _drop<double?>(
                  look,
                  const ValueKey("clipFollowAfter"),
                  clip.followBars,
                  [
                    ("Its loop", null),
                    for (var b in const [1.0, 2.0, 4.0, 8.0, 16.0])
                      (b == 1 ? "1 bar" : "${b.round()} bars", b),
                    if (clip.followBars case var f?
                        when !const [1.0, 2.0, 4.0, 8.0, 16.0].contains(f))
                      ("$f bars", f),
                  ],
                  (v) => c.editClip((x) => v == null
                      ? x.copyWith(clearFollowBars: true)
                      : x.copyWith(followBars: v)))),
      ];

  List<Widget> _audioColumn(MixerLook look, SessionClip clip) {
    // In Re-pitch, as unwarped, its pitch is its speed.
    var repitch = clip.warp && clip.warpMode == WarpMode.repitch;
    return [
      _row(
          look,
          "Warp",
          Row(children: [
            _pill(look, clip.warp ? "On" : "Off", clip.warp,
                _busy ? null : () => _run(() => c.setWarp(!clip.warp)),
                key: const ValueKey("clipWarp"),
                tip: "Keep the song's tempo: its sound stretched to its "
                    "beats. Off, it plays at its own speed."),
            if (c.warping.contains(clip.id)) ...[
              const SizedBox(width: 6),
              const SizedBox.square(
                  dimension: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5)),
            ],
          ])),
      if (clip.warp) ...[
        _row(
            look,
            "Mode",
            _drop(
                look,
                const ValueKey("clipWarpMode"),
                clip.warpMode,
                [for (var m in WarpMode.values) (m.label, m)],
                (v) => c.editClip((x) => x.copyWith(warpMode: v)))),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(clip.warpMode.hint,
              style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
        ),
        _row(
            look,
            "BPM",
            _stepper(
                look,
                "clipBpm",
                clip.bpm.toStringAsFixed(2),
                () => c.editClip((x) => x.copyWith(bpm: x.bpm - 1)),
                () => c.editClip((x) => x.copyWith(bpm: x.bpm + 1)))),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            _pill(look, "÷2", false,
                () => c.editClip((x) => x.copyWith(bpm: x.bpm / 2)),
                key: const ValueKey("clipBpmHalve"),
                tip: "Its tempo heard as twice what it is: half it"),
            _pill(look, "×2", false,
                () => c.editClip((x) => x.copyWith(bpm: x.bpm * 2)),
                key: const ValueKey("clipBpmDouble"),
                tip: "Its tempo heard as half what it is: double it"),
          ]),
        ),
      ],
      if (!repitch) ...[
        _row(
            look,
            "Pitch",
            _stepper(
                look,
                "clipPitch",
                "${clip.pitch > 0 ? "+" : ""}${clip.pitch} st",
                () => c.editClip((x) => x.copyWith(pitch: x.pitch - 1)),
                () => c.editClip((x) => x.copyWith(pitch: x.pitch + 1)))),
        _row(
            look,
            "Fine",
            _stepper(
                look,
                "clipCents",
                "${clip.cents > 0 ? "+" : ""}${clip.cents} ct",
                () => c.editClip((x) => x.copyWith(cents: x.cents - 5)),
                () => c.editClip((x) => x.copyWith(cents: x.cents + 5)))),
        if (!clip.warp && (clip.pitch != 0 || clip.cents != 0))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text("Unwarped, a higher pitch is faster too.",
                style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
          ),
      ] else
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text("Re-pitch: its pitch follows its speed.",
              style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
        ),
      _row(
          look,
          "Gain",
          _stepper(
              look,
              "clipGain",
              "${clip.gain > 0 ? "+" : ""}${clip.gain.toStringAsFixed(1)} dB",
              () => c.editClip((x) => x.copyWith(gain: x.gain - 1)),
              () => c.editClip((x) => x.copyWith(gain: x.gain + 1)))),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _pill(look, "Reverse", clip.reversedOf != null,
            _busy ? null : () => _run(c.reverseClip),
            key: const ValueKey("clipReverse"),
            tip: "Backwards: a reversed copy of its sound is kept in the "
                "library, beside the original"),
        _pill(look, "Fade", clip.fade,
            () => c.editClip((x) => x.copyWith(fade: !x.fade)),
            key: const ValueKey("clipFade"),
            tip: "A few milliseconds' fade in at its start and its loop's, "
                "and out at its loop's end: no click where it is cut"),
        _pill(look, "Crop", false, _busy ? null : () => _run(c.cropClip),
            key: const ValueKey("clipCrop"),
            tip: "Keep only what it plays, as a new sound, so the rest "
                "stops taking room"),
      ]),
      const SizedBox(height: 10),
      Text(
          "Drag the white flag on the ruler for its start, the bar over "
          "it for its loop, and the bar's end for its length."
          "${clip.warp ? " Click under the ruler for a warp marker, drag "
              "it to pull the sound onto a beat, right-click it to take it "
              "out." : ""}",
          style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
    ];
  }

  List<Widget> _notesColumn(MixerLook look) {
    Widget tool(NoteTool t, String tip) =>
        _pill(look, t.label, false, () => c.useNoteTool(t),
            key: ValueKey("noteTool-${t.name}"), tip: tip);
    var picked = c.rollSelected.length;
    return [
      Text(
          picked == 0
              ? "On every note -- or pick some in the notes."
              : "On the $picked note${picked == 1 ? "" : "s"} picked.",
          key: const ValueKey("notesToolsOn"),
          style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
      const SizedBox(height: 6),
      _row(
          look,
          "Transpose",
          Wrap(spacing: 3, runSpacing: 3, children: [
            tool(NoteTool.down, "Down a semitone"),
            tool(NoteTool.up, "Up a semitone"),
            tool(NoteTool.octaveDown, "Down an octave"),
            tool(NoteTool.octaveUp, "Up an octave"),
          ])),
      Wrap(spacing: 4, runSpacing: 4, children: [
        tool(NoteTool.fitToScale,
            "Each to the nearest note of the channel's scale"),
        tool(NoteTool.invert, "Upside down: the highest the lowest"),
        tool(NoteTool.reverse, "Played backwards"),
        tool(NoteTool.legato, "Each held until the next"),
        tool(NoteTool.faster, "Twice as fast"),
        tool(NoteTool.slower, "Half as fast"),
        tool(NoteTool.third, "A third added over each: a chord"),
        tool(NoteTool.fifth, "A fifth added over each"),
        tool(
            NoteTool.humanise,
            "A little off the grid, a little louder "
            "or softer"),
      ]),
    ];
  }
}

// ---------------------------------------------------------------------------
// An audio clip's sound
// ---------------------------------------------------------------------------

/// _Sound is a stored sound as the editor draws it: the loudest of each of
/// its slices, how long it is, and where it is struck.
typedef _Sound = ({Float32List peaks, double seconds, List<double> hits});

/// _soundsOf are each stored sound, worked out once.
final Map<String, Future<_Sound?>> _soundsOf = {};

const int _peakSlices = 4000;

Future<_Sound?> _soundOf(String assetId) => _soundsOf[assetId] ??= () async {
      var audio = await CanvasController.clipAudio(assetId);
      // Not kept, unread: it is read again next time.
      if (audio == null) {
        _soundsOf.remove(assetId);
        return null;
      }
      var (l, r) = audio;
      // Worked out away from the app's own isolate: a whole song's peaks
      // and hits there held up the mixer's sound.
      return Isolate.run(() => _drawingOf(l, r));
    }();

_Sound _drawingOf(Float32List l, Float32List r) {
  var n = l.length;
  var peaks = Float32List(_peakSlices);
  for (var i = 0; i < n; i++) {
    var v = math.max(l[i].abs(), r[i].abs());
    var k = i * _peakSlices ~/ n;
    if (v > peaks[k]) peaks[k] = v;
  }
  return (
    peaks: peaks,
    seconds: n / 48000,
    hits: n == 0 ? const <double>[] : onsets(l, r),
  );
}

enum _Handle { start, loop, length, marker, point }

/// _SampleView is an audio clip's sound against the song's beats: its
/// start's flag and its loop's bar on a ruler over it, to drag -- and,
/// warped, its warp markers under the ruler, pinning moments of the sound
/// to beats.
class _SampleView extends StatefulWidget {
  final CanvasController controller;
  final SessionClip clip;

  /// envelope is the envelope drawn over its sound, to change, by its key
  /// -- see SessionClip.curveOf -- or null; envelopeRest its height with no
  /// points, and envelopeLength its own length in beats, or null for one
  /// that goes with the clip.
  final String? envelope;
  final double envelopeRest;
  final double? envelopeLength;
  const _SampleView(
      {required this.controller,
      required this.clip,
      this.envelope,
      this.envelopeRest = 1,
      this.envelopeLength});

  @override
  State<_SampleView> createState() => _SampleViewState();
}

class _SampleViewState extends State<_SampleView>
    with SingleTickerProviderStateMixin {
  CanvasController get c => widget.controller;
  late final Ticker _ticker;
  double? _playhead;
  _Handle? _dragging;
  int _marker = 0;
  double _dragFrom = 0, _valueFrom = 0;

  @override
  void initState() {
    super.initState();
    // The playhead, while it plays.
    _ticker = createTicker((_) {
      var at = c.clipPlayhead;
      if (at != _playhead) setState(() => _playhead = at);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  static const double _rulerH = 26;
  static const double _markersH = 14;

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var clip = widget.clip;
    var sound = clip.sound;
    var audio = c.document.audio;
    var bpb = audio.beatsPerBar;
    var spb = math.max(0.001, audio.secondsPerBeat);
    return FutureBuilder<_Sound?>(
      future: sound == null ? null : _soundOf(sound.assetId),
      builder: (context, snap) => LayoutBuilder(builder: (context, size) {
        var heard = snap.data;
        var fileSeconds = heard?.seconds ?? 0.0;
        var playStart = sound?.start ?? 0;
        var playEnd = sound == null
            ? 0.0
            : sound.end > 0
                ? sound.end
                : (fileSeconds > 0 ? fileSeconds : sound.length);
        var length = math.max(0.0, playEnd - playStart);
        // Where a moment of the sound falls, in beats, and back: by its
        // warp map, warped; at the song's tempo -- and faster with its
        // pitch -- not.
        var map = clip.warpMap;
        var speed =
            math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
        double beatOf(double seconds) =>
            clip.warp ? map.beatAt(seconds) : seconds / speed / spb;
        double secondOf(double beat) =>
            clip.warp ? map.sourceAt(beat) : beat * spb * speed;
        var soundBeats = beatOf(length);
        // In view: the sound, its loop, and a bar more.
        var beats = [
              soundBeats,
              clip.loopEnd(bpb),
              clip.start + 1,
            ].reduce(math.max) +
            bpb;
        var beatW = size.maxWidth / beats;
        double beatAt(double x) => x / beatW;
        var markers = clip.warp ? clip.markers : const <WarpMarker>[];
        var top = _rulerH + (clip.warp ? _markersH : 0);
        return GestureDetector(
          key: const ValueKey("clipRuler"),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          // A warp marker added, at a hit near where it was clicked; one
          // right-clicked taken out.
          onTapUp: (d) {
            var p = d.localPosition;
            // An envelope's point, where the sound is.
            if (widget.envelope case var env? when p.dy > top) {
              if (_pointNear(clip, env, beatW, top, size.maxHeight, p) !=
                  null) {
                return;
              }
              var beat = _onEnvelope((beatAt(p.dx) * 4).roundToDouble() / 4);
              var value = _valueAt(p.dy, top, size.maxHeight);
              c.editClip(
                  (x) => x.withCurve(env, [...x.curveOf(env), (beat, value)]));
              return;
            }
            if (!clip.warp || p.dy < _rulerH || p.dy > top) return;
            var beat = beatAt(p.dx);
            if (_markerNear(markers, beatW, p.dx) != null) return;
            var seconds = secondOf(beat).clamp(0.0, length);
            for (var h in heard?.hits ?? const <double>[]) {
              if ((beatOf(h) - beat).abs() * beatW <= 6) seconds = h;
            }
            if (seconds <= 0) return;
            c.editClip((x) => x.copyWith(markers: [
                  ...x.markers,
                  (seconds: seconds, beat: beatOf(seconds)),
                ]));
          },
          onSecondaryTapUp: (d) {
            if (widget.envelope case var env? when d.localPosition.dy > top) {
              var i = _pointNear(
                  clip, env, beatW, top, size.maxHeight, d.localPosition);
              if (i == null) return;
              c.editClip(
                  (x) => x.withCurve(env, [...x.curveOf(env)]..removeAt(i)));
              return;
            }
            var i = _markerNear(markers, beatW, d.localPosition.dx);
            if (i == null || d.localPosition.dy > top) return;
            c.editClip((x) => x.copyWith(markers: [...x.markers]..removeAt(i)));
          },
          onPanStart: (d) {
            var p = d.localPosition;
            if (widget.envelope case var env? when p.dy > top) {
              var i = _pointNear(clip, env, beatW, top, size.maxHeight, p);
              if (i == null) return;
              _dragging = _Handle.point;
              _marker = i;
              c.beginInteraction();
              return;
            }
            if (p.dy > top + 12) return;
            var x = p.dx;
            if (clip.warp && p.dy >= _rulerH && p.dy <= top) {
              var i = _markerNear(markers, beatW, x);
              if (i == null) return;
              _dragging = _Handle.marker;
              _marker = i;
              _valueFrom = markers[i].beat;
            } else {
              var startX = clip.start * beatW;
              var endX = clip.loopEnd(bpb) * beatW;
              var loopX = clip.loopStart * beatW;
              if ((x - startX).abs() <= 10) {
                _dragging = _Handle.start;
                _valueFrom = clip.start;
              } else if ((x - endX).abs() <= 10) {
                _dragging = _Handle.length;
                _valueFrom = clip.bars;
              } else if (x >= loopX && x <= endX) {
                _dragging = _Handle.loop;
                _valueFrom = clip.loopStart;
              } else {
                return;
              }
            }
            _dragFrom = x;
            c.beginInteraction();
          },
          onPanUpdate: (d) {
            var handle = _dragging;
            if (handle == null) return;
            // To the beat -- a marker to the sixteenth.
            var moved = beatAt(d.localPosition.dx - _dragFrom);
            switch (handle) {
              case _Handle.start:
                var v = (_valueFrom + moved).roundToDouble();
                c.editClip((x) => x.copyWith(start: v), transient: true);
              case _Handle.loop:
                var v = (_valueFrom + moved).roundToDouble();
                c.editClip((x) => x.copyWith(loopStart: v), transient: true);
              case _Handle.length:
                var b =
                    math.max(1.0, (_valueFrom * bpb + moved).roundToDouble());
                c.editClip((x) => x.copyWith(bars: b / bpb), transient: true);
              case _Handle.point:
                var env = widget.envelope;
                if (env == null) return;
                var beat = _onEnvelope(
                    (beatAt(d.localPosition.dx) * 4).roundToDouble() / 4);
                var value = _valueAt(d.localPosition.dy, top, size.maxHeight);
                c.editClip((x) {
                  var points = [...x.curveOf(env)];
                  if (_marker >= points.length) return x;
                  points[_marker] = (math.max(0.0, beat), value);
                  // Kept in order -- and the one dragged followed.
                  var moved = points[_marker];
                  points.sort((a, b) => a.$1.compareTo(b.$1));
                  _marker = points.indexOf(moved);
                  return x.withCurve(env, points);
                }, transient: true);
              case _Handle.marker:
                var v = ((_valueFrom + moved) * 4).roundToDouble() / 4;
                c.editClip((x) {
                  var next = [...x.markers];
                  if (_marker >= next.length) return x;
                  next[_marker] = (seconds: next[_marker].seconds, beat: v);
                  return x.copyWith(markers: next);
                }, transient: true);
            }
          },
          onPanEnd: (_) {
            if (_dragging == null) return;
            _dragging = null;
            c.endInteraction();
          },
          child: CustomPaint(
            key: const ValueKey("clipSample"),
            size: Size(size.maxWidth, size.maxHeight),
            painter: _SamplePainter(
              peaks: heard?.peaks,
              fileSeconds: fileSeconds,
              playStart: playStart,
              playLength: length,
              secondOf: secondOf,
              hits: [
                for (var h in heard?.hits ?? const <double>[])
                  if (h >= playStart && h < playEnd) beatOf(h - playStart)
              ],
              markers: [for (var m in markers) m.beat],
              beatsPerBar: bpb,
              beatW: beatW,
              beats: beats,
              soundBeats: soundBeats,
              start: clip.start,
              loopStart: clip.loopStart,
              loopEnd: clip.loopEnd(bpb),
              loop: clip.loop,
              gain: math.pow(10, clip.gain / 20).toDouble(),
              playhead: _playhead,
              studio: look.studio,
              rulerH: _rulerH,
              top: top,
              envelope: widget.envelope == null
                  ? null
                  : clip.curveOf(widget.envelope!),
              envelopeRest: widget.envelopeRest,
              envelopeLength: widget.envelopeLength,
              key: clip.warpSignature(spb),
            ),
          ),
        );
      }),
    );
  }

  /// _valueAt is an envelope's value at height [y] in the sound, between
  /// [top] and [bottom]: one at the top, nought at the bottom.
  double _valueAt(double y, double top, double bottom) =>
      (1 - (y - top - 6) / math.max(1, bottom - top - 12)).clamp(0.0, 1.0);

  /// _onEnvelope is [beat] kept inside an envelope of its own length: its
  /// points are its first time round, which the rest repeat.
  double _onEnvelope(double beat) {
    var length = widget.envelopeLength;
    beat = math.max(0.0, beat);
    return length == null ? beat : beat.clamp(0.0, length - 0.25);
  }

  /// _pointNear is the envelope point within reach of [p], or null.
  int? _pointNear(SessionClip clip, String env, double beatW, double top,
      double bottom, Offset p) {
    for (var (i, (b, v)) in clip.curveOf(env).indexed) {
      var y = top + 6 + (1 - v) * math.max(1, bottom - top - 12);
      if ((Offset(b * beatW, y) - p).distance <= 8) return i;
    }
    return null;
  }

  /// _markerNear is the marker within reach of [x], or null.
  int? _markerNear(List<WarpMarker> markers, double beatW, double x) {
    for (var (i, m) in markers.indexed) {
      if ((m.beat * beatW - x).abs() <= 7) return i;
    }
    return null;
  }
}

class _SamplePainter extends CustomPainter {
  final Float32List? peaks;
  final double fileSeconds, playStart, playLength;
  final double Function(double beat) secondOf;
  final List<double> hits, markers;
  final int beatsPerBar;
  final double beatW, beats, soundBeats, start, loopStart, loopEnd, gain;
  final double rulerH, top;
  final bool loop;
  final double? playhead;
  final StudioColors studio;

  /// envelope is the envelope drawn over the sound -- its points, a beat
  /// and a value -- or null for none, and envelopeRest its value with none.
  final List<ControlPoint>? envelope;
  final double envelopeRest;

  /// envelopeLength is the envelope's own length, in beats -- drawn once,
  /// then again and again, fainter, along the clip -- or null.
  final double? envelopeLength;

  /// key is what the sound's drawing depends on beyond the rest: when it
  /// changes, it is drawn again.
  final String key;

  _SamplePainter({
    required this.peaks,
    required this.fileSeconds,
    required this.playStart,
    required this.playLength,
    required this.secondOf,
    required this.hits,
    required this.markers,
    required this.beatsPerBar,
    required this.beatW,
    required this.beats,
    required this.soundBeats,
    required this.start,
    required this.loopStart,
    required this.loopEnd,
    required this.loop,
    required this.gain,
    required this.playhead,
    required this.studio,
    required this.rulerH,
    required this.top,
    required this.key,
    this.envelope,
    this.envelopeRest = 1,
    this.envelopeLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.inset);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, top), Paint()..color = studio.panel);
    // What it does not play, darker: before its start, past its end.
    var dim = Paint()..color = Colors.black.withValues(alpha: 0.28);
    var first = (loop ? math.min(start, loopStart) : start) * beatW;
    canvas.drawRect(Rect.fromLTRB(0, top, first, h), dim);
    canvas.drawRect(Rect.fromLTRB(loopEnd * beatW, top, size.width, h), dim);
    // The beats and bars, numbered.
    var label = TextPainter(textDirection: TextDirection.ltr);
    var every = beatW * beatsPerBar < 28 ? 4 : 1;
    for (var b = 0; b <= beats; b++) {
      var x = b * beatW;
      var bar = b % beatsPerBar == 0;
      canvas.drawLine(
          Offset(x, bar ? rulerH - 8 : rulerH - 4),
          Offset(x, h),
          Paint()
            ..color = bar ? studio.edge : studio.edge.withValues(alpha: 0.35));
      if (bar && (b ~/ beatsPerBar) % every == 0) {
        label.text = TextSpan(
            text: "${b ~/ beatsPerBar + 1}",
            style: TextStyle(fontSize: 10, color: studio.muted));
        label.layout();
        label.paint(canvas, Offset(x + 3, rulerH - 14));
      }
    }
    // Its hits, grey, and its warp markers, yellow, under the ruler.
    if (top > rulerH) {
      var tick = Paint()..color = studio.muted;
      for (var b in hits) {
        canvas.drawLine(
            Offset(b * beatW, top - 5), Offset(b * beatW, top), tick);
      }
      var pin = Paint()..color = const Color(0xFFF2D14B);
      for (var b in markers) {
        var x = b * beatW;
        canvas.drawPath(
            Path()
              ..moveTo(x - 5, rulerH + 2)
              ..lineTo(x + 5, rulerH + 2)
              ..lineTo(x, rulerH + 11)
              ..close(),
            pin);
        canvas.drawLine(Offset(x, rulerH + 11), Offset(x, h),
            Paint()..color = pin.color.withValues(alpha: 0.35));
      }
    }
    // The sound: both sides together, where each moment of it falls.
    var peaks = this.peaks;
    if (peaks != null && fileSeconds > 0) {
      var mid = top + (h - top) / 2;
      var half = (h - top) / 2 - 6;
      var wave = Paint()
        ..color = studio.text.withValues(alpha: 0.75)
        ..strokeWidth = 1;
      for (var x = 0.0; x < math.min(size.width, soundBeats * beatW); x += 1) {
        var from = playStart + secondOf(x / beatW);
        var to = playStart + secondOf((x + 1) / beatW);
        if (from >= playStart + playLength) break;
        var a = (from / fileSeconds * _peakSlices)
            .floor()
            .clamp(0, _peakSlices - 1);
        var b =
            (to / fileSeconds * _peakSlices).ceil().clamp(a + 1, _peakSlices);
        var v = 0.0;
        for (var k = a; k < b; k++) {
          v = math.max(v, peaks[k]);
        }
        var y = math.min(1.0, v * gain) * half;
        canvas.drawLine(Offset(x, mid - y), Offset(x, mid + y), wave);
      }
    }
    // The loop's bar over the ruler, and its end's grip.
    var brace = Paint()
      ..color = loop ? studio.on : studio.muted.withValues(alpha: 0.6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(loopStart * beatW, 2, loopEnd * beatW, 9),
            const Radius.circular(2)),
        brace);
    canvas.drawRect(Rect.fromLTWH(loopEnd * beatW - 3, 0, 3, rulerH), brace);
    // The start's flag.
    var sx = start * beatW;
    canvas.drawPath(
        Path()
          ..moveTo(sx, 10)
          ..lineTo(sx + 9, 15)
          ..lineTo(sx, 20)
          ..close(),
        Paint()..color = studio.text);
    canvas.drawLine(Offset(sx, 10), Offset(sx, h),
        Paint()..color = studio.text.withValues(alpha: 0.5));
    // The envelope: a line through its points, held flat before the first
    // and after the last, over the sound dimmed.
    if (envelope case var points?) {
      canvas.drawRect(Rect.fromLTRB(0, top, size.width, h),
          Paint()..color = Colors.black.withValues(alpha: 0.35));
      double y(double v) => top + 6 + (1 - v) * math.max(1, h - top - 12);
      const colour = Color(0xFFFF6F61);
      var line = Paint()
        ..color = colour
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      var length = envelopeLength;
      Path once(double from, double to) {
        var path = Path();
        if (points.isEmpty) {
          return path
            ..moveTo(from, y(envelopeRest))
            ..lineTo(to, y(envelopeRest));
        }
        path.moveTo(from, y(points.first.$2));
        for (var (b, v) in points) {
          path.lineTo(from + b * beatW, y(v));
        }
        return path..lineTo(to, y(points.last.$2));
      }

      if (length == null || length <= 0) {
        canvas.drawPath(once(0, size.width), line);
      } else {
        // Its own length: round and round along the clip, the first time
        // the one changed.
        var span = length * beatW;
        canvas.drawPath(once(0, span), line);
        var faint = Paint()
          ..color = colour.withValues(alpha: 0.35)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        for (var x = span; x < size.width && span > 1; x += span) {
          canvas.drawPath(once(x, x + span), faint);
        }
        canvas.drawLine(Offset(span, top), Offset(span, h),
            Paint()..color = colour.withValues(alpha: 0.5));
      }
      for (var (b, v) in points) {
        canvas.drawCircle(Offset(b * beatW, y(v)), 4, Paint()..color = colour);
      }
    }
    if (playhead case var p?) {
      canvas.drawLine(
          Offset(p * beatW, top),
          Offset(p * beatW, h),
          Paint()
            ..color = studio.text
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_SamplePainter old) =>
      old.peaks != peaks ||
      old.key != key ||
      old.playhead != playhead ||
      old.start != start ||
      old.loopStart != loopStart ||
      old.loopEnd != loopEnd ||
      old.loop != loop ||
      old.gain != gain ||
      old.beatW != beatW ||
      old.playStart != playStart ||
      old.playLength != playLength ||
      old.hits.length != hits.length ||
      old.envelope != envelope ||
      old.envelopeLength != envelopeLength ||
      old.envelopeRest != envelopeRest ||
      old.studio != studio;
}

/// beatsOfPlace is a place typed as Ableton's are -- "bar.beat.sixteenth",
/// "bar.beat" or "bar", each counted from one -- in beats from the start, at
/// [beatsPerBar]; null for what is not one.
double? beatsOfPlace(String text, int beatsPerBar) {
  var parts = text.trim().split(RegExp(r"[.:\s]+"));
  if (parts.isEmpty || parts.length > 3 || parts.first.isEmpty) return null;
  var n = [for (var p in parts) int.tryParse(p)];
  if (n.contains(null)) return null;
  var (bar, beat, sixteenth) =
      (n[0]!, n.length > 1 ? n[1]! : 1, n.length > 2 ? n[2]! : 1);
  if (bar < 1 ||
      beat < 1 ||
      beat > beatsPerBar ||
      sixteenth < 1 ||
      sixteenth > 4) {
    return null;
  }
  return (bar - 1) * beatsPerBar + (beat - 1) + (sixteenth - 1) / 4;
}

/// _TypedPlace is a place shown as bar.beat.sixteenth, typed into once
/// clicked: Return sets it, Escape or clicking away leaves it.
class _TypedPlace extends StatefulWidget {
  final String value;
  final TextStyle style;
  final TextAlign align;
  final ValueChanged<String> onTyped;
  const _TypedPlace(
      {required this.value,
      required this.style,
      required this.onTyped,
      this.align = TextAlign.center,
      super.key});

  @override
  State<_TypedPlace> createState() => _TypedPlaceState();
}

class _TypedPlaceState extends State<_TypedPlace> {
  bool _typing = false;
  late final _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Clicked away: left as it was.
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) setState(() => _typing = false);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_typing) {
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _text.text = widget.value;
            _text.selection =
                TextSelection(baseOffset: 0, extentOffset: widget.value.length);
            setState(() => _typing = true);
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _focus.requestFocus());
          },
          child: Text(widget.value,
              textAlign: widget.align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _typing = false),
      },
      child: TextField(
        key: const ValueKey("typedPlace"),
        controller: _text,
        focusNode: _focus,
        textAlign: widget.align,
        style: widget.style,
        decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero),
        onSubmitted: (v) {
          widget.onTyped(v);
          setState(() => _typing = false);
        },
      ),
    );
  }
}
