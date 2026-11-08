import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/media/spectrogram.dart';
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
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

// clip_editor.dart is the clip editor (Ableton's clip view): a clip in a
// slot, double-clicked, opens here in the effects panel. Down the left, its
// settings in columns: Clip (start, loop, colour), Launch (how a press plays
// it, what its launch waits for, what it does when it has played), and Audio
// (gain, reverse, crop) or Notes (pitch and time tools). On the right, what
// it plays: an audio clip's sound with its start and loop on a ruler to
// drag, or a MIDI clip's notes in the piano roll.
//
// Everything is in beats, as the clip is (see SessionClip). A warped audio
// clip keeps the song's tempo (its sound rendered stretched, see warp.dart)
// and its warp markers pin moments of the sound to beats. Its gain and pan
// envelopes are drawn over its sound and rendered with it; a MIDI clip's
// are its controllers' curves, in the piano roll.
//
// It is a device in the effects strip, first in the channel's chain: narrow,
// one column of settings at a time; widened, all of them, and what it plays
// as wide as the strip.

const double _columnW = 220;

/// _fadeInk is the fades and their grips, and the warp markers, amber as
/// the prototype's.
const _fadeInk = Color(0xFFE2B04A);

/// _envelopeInk is an envelope drawn over the sound: the prototype's pink.
const _envelopeInk = Color(0xFFF08BD0);

/// editorNarrowWidth is the clip editor's width in the strip, unwidened.
const double editorNarrowWidth = 760;

/// EditorFrame is the clip editor's (or a part's piano roll's) place in the
/// effects strip: a bar along the top with its name and buttons, as every
/// device has, and the editor under it at the strip's height, given the
/// room rather than scaled to it as a device is.
class EditorFrame extends StatelessWidget {
  final String id;
  final String title;
  final double width;
  final double height;
  final bool wide;
  final VoidCallback onWide;
  final VoidCallback onClose;
  final Widget child;

  /// onResize is its right edge dragged, to the width it would be.
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
/// drag began plus how far the pointer has gone since, not each move added
/// to the last, which loses moves that come between two frames.
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

  /// part is whether it edits a MIDI channel's part (the piano roll's, opened
  /// from its In) rather than a clip in a slot: its place on the timeline and
  /// its notes' tools, and Play for the timeline.
  final bool part;

  /// canWiden is whether there is room for every column: without it, one
  /// at a time and no button to show them all.
  final bool canWiden;
  const ClipEditor(
      {required this.controller,
      this.wide = true,
      this.part = false,
      this.canWiden = true,
      super.key});

  @override
  State<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<ClipEditor> {
  CanvasController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _changes.dispose();
    super.dispose();
  }

  /// _changes tells the editor to be built again: on every change the
  /// canvas tells of but the playhead moving on -- its waveform's playhead
  /// moves by itself -- unless that took its clip from waiting to playing,
  /// or from playing to stopped (Ken's systems review, 2026-11-08).
  final ValueNotifier<int> _changes = ValueNotifier(0);
  Object? _stateWas;

  Object? get _clipStateNow => switch (c.clipEditing) {
        PianoRollTarget(:var channel, row: var row?) =>
          c.clipState(channel, row),
        _ => null,
      };

  void _changed() {
    var now = _clipStateNow;
    if (c.notifyingPlayhead && now == _stateWas) return;
    _stateWas = now;
    _changes.value++;
  }

  /// _built is the editor as last built, handed back while nothing it
  /// shows has changed: see CanvasMixer's.
  Widget? _built;

  @override
  void setState(VoidCallback fn) {
    _built = null;
    super.setState(fn);
  }

  @override
  void didUpdateWidget(ClipEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.wide != widget.wide ||
        old.part != widget.part ||
        old.canWiden != widget.canWiden) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _built = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  /// _said is what the last Reverse, Crop or Warp had to say, and _busy
  /// whether one is still working.
  String? _said;
  bool _busy = false;

  /// _spectral is whether its sound is drawn as a spectrogram.
  bool _spectral = false;

  /// _shown is the column of settings shown, narrow: 0 Clip, 1 Launch, 2
  /// Audio or Notes.
  int _shown = 0;

  /// _envelope is the key of the envelope drawn over an audio clip's sound
  /// (its gain or pan, or a setting of its channel: see SessionClip.curveOf),
  /// or null for its gain.
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
      // Said, not lost, so a failure is not a press that does nothing.
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
  Widget build(BuildContext context) => _built ??= ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          var look = MixerLook.of(context);
          if (widget.part) {
            var t = c.pianoRoll;
            var content = c.rollContent;
            var e = t == null ? null : c.instrumentOf(t.channel);
            if (t == null || t.row != null || content == null || e == null) {
              return const SizedBox();
            }
            // Straight to its toolbar, as the prototype's Notes: what it is
            // is in the Chain's header, and Play is on the roll's bar.
            return _layout(
                look,
                null,
                // The columns a slot's clip has, in the same places: a part's place on
                // the timeline, how it is launched (it is not, but a copy of it in a
                // slot is) and its notes' tools.
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
          // An audio clip as the prototype's: a bar of tools over its sound,
          // its settings in one column at the side, a line of help under.
          if (!clip.midi) return _audioEditor(look, t, clip);
          // Its notes under one bar, as an audio clip's sound is: its Play
          // first on the roll's own, next to the tools; no title row above
          // (Ken, 2026-11-08: "an extra header row ... looks strange").
          return _layout(
              look,
              null,
              [
                ("Clip", _clipColumn(look, clip), "clipColumn"),
                ("Launch", _launchColumn(look, clip), "launchColumn"),
                ("Notes", _notesColumn(look), "notesColumn"),
              ],
              PianoRoll(controller: c, inClipEditor: true));
        },
      );

  // ---- An audio clip, as the prototype's.

  Widget _audioEditor(MixerLook look, PianoRollTarget t, SessionClip clip) {
    var shut = c.settingsShut("clip");
    var envKey = _envelopeKey(clip, t);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _audioToolbar(look, t, clip),
      Container(height: 1, color: look.studio.edge),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _SampleView(
                controller: c,
                clip: clip,
                envelope: _envelopes ? envKey : null,
                envelopeRest: _envelopeRest(envKey, t),
                envelopeLength: clip.lengthOf(envKey),
                spectral: _spectral,
                envelopeName:
                    "${_envelopeChoices(clip, t).where((ch) => ch.$2 == envKey).firstOrNull?.$1 ?? ""} envelope",
                onSay: (said) => setState(() => _said = said)),
          ),
          if (!shut) ...[
            Container(width: 1, color: look.studio.edge),
            SizedBox(
                key: const ValueKey("clipInspector"),
                width: 252,
                child: _audioInspector(look, clip)),
          ],
        ]),
      ),
      Container(height: 1, color: look.studio.edge),
      _audioStatus(look, t, clip),
    ]);
  }

  /// _tb is a button of the audio clip's bar: a word, an icon, or both; lit
  /// where [on].
  Widget _tb(MixerLook look, String key, String label, VoidCallback? tap,
      {bool on = false, IconData? icon, String? tip, bool menu = false}) {
    var s = look.studio;
    var ink = tap == null
        ? s.muted.withValues(alpha: 0.5)
        : on
            ? look.colors.onPrimary
            : s.text;
    return Tooltip(
      message: tip ?? label,
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(5),
        onTap: tap,
        child: Container(
          height: 24,
          padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 5 : 8),
          decoration: BoxDecoration(
              color: on ? look.colors.primary : null,
              borderRadius: BorderRadius.circular(5)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) Icon(icon, size: 14, color: ink),
            if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
            if (label.isNotEmpty)
              Text(label, style: TextStyle(fontSize: 11.5, color: ink)),
            if (menu) Icon(Icons.arrow_drop_down, size: 16, color: ink),
          ]),
        ),
      ),
    );
  }

  Widget _tbGroup(MixerLook look, List<Widget> children) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            border: Border.all(color: look.studio.edge),
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _tbGap(MixerLook look) => Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: look.studio.edge);

  Widget _tbLabel(MixerLook look, String text) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: look.studio.muted)),
      );

  /// _tbReadout is a value on the bar, typed into on a double-click where
  /// [onTyped] takes the number typed.
  Widget _tbReadout(MixerLook look, String key, String text,
      {ValueChanged<double>? onTyped}) {
    var style = TextStyle(
        fontSize: 11.5,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: look.studio.text);
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: look.studio.inset,
          border: Border.all(color: look.studio.edge),
          borderRadius: BorderRadius.circular(4)),
      child: onTyped == null
          ? Text(text, style: style)
          : IntrinsicWidth(
              child: _TypedPlace(
                  key: ValueKey("$key-typed"),
                  value: text,
                  style: style,
                  doubleClick: true,
                  onTyped: (t) {
                    if (typedNumber(t) case (var v, _)) onTyped(v);
                  }),
            ),
    );
  }

  /// _tbMenu is a button of the bar opening [items] under it.
  Widget _tbMenu(MixerLook look, String key, String label, List<Widget> items,
          {IconData? icon, String? tip, bool enabled = true}) =>
      MenuAnchor(
        menuChildren: items,
        builder: (context, menu, _) => _tb(look, key, label,
            enabled ? () => menu.isOpen ? menu.close() : menu.open() : null,
            icon: icon, tip: tip, menu: true),
      );

  MenuItemButton _menuItem(String key, String label, VoidCallback? tap,
          {bool on = false, String? hint}) =>
      MenuItemButton(
        key: ValueKey(key),
        leadingIcon: Icon(on ? Icons.check : null, size: 14),
        onPressed: tap,
        child: hint == null
            ? Text(label)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                    Text(label),
                    Text(hint,
                        style: const TextStyle(
                            fontSize: 10.5, color: Color(0xFF9A98A6))),
                  ]),
      );

  Widget _audioToolbar(MixerLook look, PianoRollTarget t, SessionClip clip) {
    var repitch = clip.warp && clip.warpMode == WarpMode.repitch;
    var envKey = _envelopeKey(clip, t);
    var setting =
        _envelopes && ClipEnvelope.values.every((e) => e.name != envKey);
    var choices = _envelopeChoices(clip, t);
    var settings = choices
        .where((ch) => ClipEnvelope.values.every((e) => e.name != ch.$2))
        .toList();
    return SizedBox(
      height: 34,
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(children: [
              // Heard on its own, at once: with the transport stopped the
              // timeline stays silent (see CanvasController.sessionOnly).
              _tb(look, "clipPreview", c.clipPreviewing ? "Stop" : "Play",
                  c.previewClip,
                  on: c.clipPreviewing,
                  icon: c.clipPreviewing ? Icons.stop : Icons.play_arrow,
                  tip: c.clipPreviewing
                      ? "Stop it"
                      : "Play it now, round its loop -- the timeline stays "
                          "quiet"),
              _tbGap(look),
              _tb(look, "clipWarp", "Warp",
                  _busy ? null : () => _run(() => c.setWarp(!clip.warp)),
                  on: clip.warp,
                  icon: Icons.timeline,
                  tip: "Keep the song's tempo: its sound stretched to its "
                      "beats. Off, it plays at its own speed."),
              _tbMenu(
                  look,
                  "clipWarpMode",
                  clip.warpMode.label,
                  [
                    for (var m in WarpMode.values)
                      _menuItem(
                          "clipWarpMode-${m.name}",
                          m.label,
                          () => c.editClip(
                              (x) => x.copyWith(warp: true, warpMode: m)),
                          on: m == clip.warpMode,
                          hint: m.hint),
                  ],
                  tip: "How it is stretched"),
              if (c.warping.contains(clip.id))
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: SizedBox.square(
                      dimension: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5)),
                ),
              _tbGap(look),
              _tbLabel(look, "BPM"),
              _tb(look, "clipBpm-down", "",
                  () => c.editClip((x) => x.copyWith(bpm: x.bpm - 1)),
                  icon: Icons.remove, tip: "Slower: a beat a minute less"),
              _tbReadout(look, "clipBpm", clip.bpm.toStringAsFixed(1),
                  onTyped: (v) {
                if (v >= 20 && v <= 999) {
                  c.editClip((x) => x.copyWith(bpm: v));
                }
              }),
              _tb(look, "clipBpm-up", "",
                  () => c.editClip((x) => x.copyWith(bpm: x.bpm + 1)),
                  icon: Icons.add, tip: "Faster: a beat a minute more"),
              _tb(look, "clipBpmHalve", "÷2",
                  () => c.editClip((x) => x.copyWith(bpm: x.bpm / 2)),
                  tip: "Its tempo heard as twice what it is: half it"),
              _tb(look, "clipBpmDouble", "×2",
                  () => c.editClip((x) => x.copyWith(bpm: x.bpm * 2)),
                  tip: "Its tempo heard as half what it is: double it"),
              _tbGap(look),
              _tbLabel(look, "Pitch"),
              _tb(
                  look,
                  "clipPitch-down",
                  "",
                  repitch
                      ? null
                      : () => c.editClip((x) => x.copyWith(pitch: x.pitch - 1)),
                  icon: Icons.remove,
                  tip: repitch
                      ? "In Re-pitch its pitch follows its speed"
                      : "Down a semitone"),
              _tbReadout(look, "clipPitch",
                  "${clip.pitch > 0 ? "+" : ""}${clip.pitch} st",
                  onTyped: repitch
                      ? null
                      : (v) => c.editClip(
                          (x) => x.copyWith(pitch: v.round().clamp(-48, 48)))),
              _tb(
                  look,
                  "clipPitch-up",
                  "",
                  repitch
                      ? null
                      : () => c.editClip((x) => x.copyWith(pitch: x.pitch + 1)),
                  icon: Icons.add,
                  tip: repitch
                      ? "In Re-pitch its pitch follows its speed"
                      : "Up a semitone"),
              _tbGap(look),
              _tb(look, "clipReverse", "Reverse",
                  _busy ? null : () => _run(c.reverseClip),
                  on: clip.reversedOf != null,
                  icon: Icons.west,
                  tip: "Backwards: a reversed copy of its sound is kept in "
                      "the library, beside the original"),
              _tb(look, "clipNormalise", "Normalise",
                  _busy ? null : () => _run(c.normaliseClip),
                  tip: "Its gain set so its loudest moment reaches 0 dB"),
              _tb(look, "clipCrop", "Crop",
                  _busy ? null : () => _run(c.cropClip),
                  icon: Icons.crop,
                  tip: "Keep only what it plays, as a new sound, so the rest "
                      "stops taking room"),
              _tbMenu(
                  look,
                  "clipSlice",
                  "Slice",
                  [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 6, 12, 2),
                      child: Text("Into the slots under it, at",
                          style: TextStyle(
                              fontSize: 10.5, color: Color(0xFF9A98A6))),
                    ),
                    for (var by in SliceBy.values)
                      _menuItem("clipSlice-${by.name}", by.label,
                          () => _run(() => c.sliceClip(by))),
                    const Divider(height: 8),
                    _menuItem("clipSliceNotes", "Into a note clip",
                        () => _run(() => c.sliceToInstrument(pads: false)),
                        hint: "Each hit a note, on a new channel that plays "
                            "them"),
                    _menuItem("clipSlicePads", "Into drum pads",
                        () => _run(() => c.sliceToInstrument(pads: true)),
                        hint: "Each hit on a pad of a new drum channel"),
                  ],
                  icon: Icons.content_cut,
                  enabled: !_busy,
                  tip: "Cut it at its hits or on the beat"),
              _tbMenu(
                  look,
                  "clipFadeCurve",
                  "${clip.fadeCurve.label} fades",
                  [
                    for (var f in FadeCurve.values)
                      _menuItem("clipFadeCurve-${f.name}", f.label,
                          () => c.editClip((x) => x.copyWith(fadeCurve: f)),
                          on: f == clip.fadeCurve),
                    const Divider(height: 8),
                    _menuItem("clipFade", "A short fade at every cut",
                        () => c.editClip((x) => x.copyWith(fade: !x.fade)),
                        on: clip.fade,
                        hint: "A few milliseconds at its start and its "
                            "loop's: no click where it is cut"),
                  ],
                  icon: Icons.show_chart,
                  tip: "The way its fades go"),
              _tbGap(look),
              _tbLabel(look, "Envelope"),
              _tbGroup(look, [
                _tb(look, "clipEnvelope-off", "Off",
                    () => setState(() => _envelopes = false),
                    on: !_envelopes),
                for (var e in ClipEnvelope.values)
                  _tb(
                      look,
                      "clipEnvelope-${e.name}",
                      e.label,
                      () => setState(() {
                            _envelopes = true;
                            _envelope = e.name;
                          }),
                      on: _envelopes && envKey == e.name,
                      tip: "Its ${e.label.toLowerCase()} changed as it "
                          "plays: drawn over its sound"),
                if (settings.isNotEmpty)
                  _tbMenu(
                      look,
                      "clipEnvelopeTarget",
                      setting
                          ? choices
                              .firstWhere((ch) => ch.$2 == envKey,
                                  orElse: () => ("Setting", envKey))
                              .$1
                          : "Setting",
                      [
                        for (var (label, k) in settings)
                          _menuItem(
                              "clipEnvelopeTarget-$k",
                              label,
                              () => setState(() {
                                    _envelopes = true;
                                    _envelope = k;
                                  }),
                              on: setting && envKey == k),
                      ],
                      tip: "A setting of its channel, moved as it plays"),
              ]),
              // A setting's envelope: the clip's length, or its own.
              if (setting) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 84,
                  child: _drop(
                      look,
                      const ValueKey("clipEnvelopeLength"),
                      clip.lengthOf(envKey) ?? 0.0,
                      [
                        for (var (beats, label)
                            in envelopeLengths(c.document.audio.beatsPerBar))
                          (label, beats ?? 0.0)
                      ],
                      (v) => c.editClip(
                          (x) => x.withLength(envKey, v == 0 ? null : v))),
                ),
              ],
              _tbGap(look),
              _tbGroup(look, [
                _tb(look, "clipWave", "",
                    () => setState(() => _spectral = false),
                    on: !_spectral, icon: Icons.graphic_eq, tip: "Its wave"),
                _tb(look, "clipSpectrum", "",
                    () => setState(() => _spectral = true),
                    on: _spectral,
                    icon: Icons.bar_chart,
                    tip: "Its sound as a spectrogram: low pitches at the "
                        "bottom, each as bright as it is loud"),
              ]),
            ]),
          ),
        ),
        _tb(look, "clipInspectorToggle", "", () => c.toggleSettingsShut("clip"),
            on: !c.settingsShut("clip"),
            icon: Icons.view_sidebar_outlined,
            tip: c.settingsShut("clip")
                ? "Show the clip's settings"
                : "Hide the clip's settings"),
        const SizedBox(width: 6),
      ]),
    );
  }

  /// _slider is a setting of the clip's sound as the prototype draws it: a
  /// name, a slider and its reading.
  Widget _slider(
      MixerLook look,
      String key,
      String label,
      double value,
      double min,
      double max,
      String reading,
      SessionClip Function(SessionClip x, double v) set,
      {double? Function(double v, String unit)? typed}) {
    var s = look.studio;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(children: [
        SizedBox(
            width: 56,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _small(look, s.muted))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
            child: SizedBox(
              height: 18,
              child: Slider(
              key: ValueKey(key),
              value: value.clamp(min, max),
              min: min,
              max: max,
                onChangeStart: (_) => c.beginInteraction(),
                onChanged: (v) =>
                    c.editClip((x) => set(x, v), transient: true),
                onChangeEnd: (_) => c.endInteraction(),
              ),
            ),
          ),
        ),
        // Its number, typed into on a double-click.
        SizedBox(
          width: 54,
          child: _TypedPlace(
              key: ValueKey("$key-reading"),
              value: reading,
              align: TextAlign.right,
              doubleClick: true,
              style: _small(look).copyWith(
                  fontSize: 10.5,
                  fontFeatures: const [FontFeature.tabularFigures()]),
              onTyped: (text) {
                if (typedNumber(text) case (var v, var unit)) {
                  var value = typed == null ? v : typed(v, unit);
                  if (value != null) {
                    c.editClip((x) => set(x, value.clamp(min, max)));
                  }
                }
              }),
        ),
      ]),
    );
  }

  Widget _audioInspector(MixerLook look, SessionClip clip) {
    var s = look.studio;
    var help = _small(look, s.muted).copyWith(fontSize: 10.5, height: 1.4);
    Widget gap() => const SizedBox(height: 6);
    return Container(
      color: s.panel,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _head(look, "Clip", key: const ValueKey("clipColumn")),
          ..._clipColumn(look, clip),
          // Launched from a slot; one on the timeline plays where it is.
          if (c.clipEditing?.row != timelineRow) ...[
            gap(),
            _head(look, "Launch", key: const ValueKey("launchColumn")),
            ..._launchColumn(look, clip),
          ],
          gap(),
          _head(look, "Sound", key: const ValueKey("audioColumn")),
          _slider(
              look,
              "clipGain",
              "Gain",
              clip.gain,
              -24,
              12,
              "${clip.gain > 0 ? "+" : ""}${clip.gain.toStringAsFixed(1)} dB",
              (x, v) => x.copyWith(gain: (v * 2).roundToDouble() / 2)),
          _slider(
              look,
              "clipCents",
              "Detune",
              clip.cents.toDouble(),
              -50,
              50,
              "${clip.cents > 0 ? "+" : ""}${clip.cents} ct",
              (x, v) => x.copyWith(cents: v.round())),
          _slider(
              look,
              "clipFadeIn",
              "Fade in",
              clip.fadeIn,
              0,
              4,
              clip.fadeIn == 0 ? "None" : _seconds(clip.fadeIn),
              (x, v) => x.copyWith(fadeIn: (v * 100).roundToDouble() / 100),
              typed: (v, unit) => unit == "ms" || (unit.isEmpty && v > 8)
                  ? v / 1000
                  : v),
          _slider(
              look,
              "clipFadeOut",
              "Fade out",
              clip.fadeOut,
              0,
              8,
              clip.fadeOut == 0 ? "None" : _seconds(clip.fadeOut),
              (x, v) => x.copyWith(fadeOut: (v * 100).roundToDouble() / 100),
              typed: (v, unit) => unit == "ms" || (unit.isEmpty && v > 8)
                  ? v / 1000
                  : v),
          if (!clip.warp && (clip.pitch != 0 || clip.cents != 0))
            Text("Unwarped, a higher pitch is faster too.", style: help),
          gap(),
          _head(look, "Warp markers",
              end: "${clip.markers.length}",
              key: const ValueKey("clipMarkersHead")),
          Text(
              clip.warp
                  ? "Click the strip under the ruler to add one; it snaps to "
                      "the grey hits. Drag it to move the sound, and "
                      "right-click or double-click it to take it out."
                  : "Switch Warp on to pin its hits to the beats.",
              style: help),
          if (clip.markers.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: _pill(look, "Take them all out", false,
                  () => c.editClip((x) => x.copyWith(markers: const [])),
                  key: const ValueKey("clipMarkersClear")),
            ),
          ],
          gap(),
          _head(look, "Slice"),
          Wrap(spacing: 4, runSpacing: 4, children: [
            _pill(
                look,
                "To a note clip",
                false,
                _busy
                    ? null
                    : () => _run(() => c.sliceToInstrument(pads: false)),
                key: const ValueKey("clipSliceNotesButton")),
            _pill(
                look,
                "To drum pads",
                false,
                _busy
                    ? null
                    : () => _run(() => c.sliceToInstrument(pads: true)),
                key: const ValueKey("clipSlicePadsButton")),
          ]),
          const SizedBox(height: 6),
          Text(
              "Each hit becomes a note, or a pad that plays that slice, on a "
              "new channel.",
              style: help),
        ]),
      ),
    );
  }

  Widget _audioStatus(MixerLook look, PianoRollTarget t, SessionClip clip) {
    var lane = c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var muted = _small(look, look.studio.muted).copyWith(fontSize: 10.5);
    var said = _said;
    return SizedBox(
      height: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Text(
              "${lane?.name ?? ""} · “${clip.name.isEmpty ? "Clip" : clip.name}”",
              key: const ValueKey("clipEditorName"),
              style: _small(look).copyWith(fontSize: 10.5)),
          const SizedBox(width: 12),
          if (_busy) ...[
            const SizedBox.square(
                dimension: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
                said ??
                    "Click the strip under the ruler to add a warp marker; "
                        "drag the amber squares for the fades; pick Gain or "
                        "Pan to draw an envelope",
                key: said == null ? null : const ValueKey("clipEditorSaid"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: said == null
                    ? muted
                    : muted.copyWith(color: look.studio.text)),
          ),
        ]),
      ),
    );
  }

  /// _layout is the editor: its header over its columns of settings (every
  /// one, wide; narrow, one at a time, picked above it) and what it plays
  /// beside them.
  Widget _layout(MixerLook look, Widget? header,
      List<(String, List<Widget>, String)> settings, Widget editor) {
    var columns = [
      for (var (title, children, key) in settings)
        _column(look, title, children, key: ValueKey(key)),
    ];
    var shown = _shown.clamp(0, columns.length - 1);
    var kind = widget.part ? "roll" : "clip";
    var shut = c.settingsShut(kind);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (header != null) header,
      Expanded(
        // What it plays first, its settings at the right, as the
        // prototype's inspector is.
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: editor),
          Container(width: 1, color: look.studio.edge),
          if (shut)
            // Folded away: a strip naming them, to open them again.
            _shutStrip(look, settings.map((s) => s.$1).join(" · "), kind)
          else if (widget.wide) ...[
            // Hidden, or folded to one column, for more of what it plays.
            Column(children: [
              const SizedBox(height: 4),
              _foldButton(look, kind),
              Expanded(child: _columnsButton(look, wide: true)),
            ]),
            ...columns,
          ] else
            SizedBox(
              width: _columnW,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Row(children: [
                        Expanded(
                          child: Wrap(spacing: 3, runSpacing: 3, children: [
                            for (var (i, (label, _, _)) in settings.indexed)
                              _pill(look, label, i == shown,
                                  () => setState(() => _shown = i),
                                  key: ValueKey("clipShow-$i")),
                          ]),
                        ),
                        if (widget.canWiden) _columnsButton(look, wide: false),
                        _foldButton(look, kind),
                      ]),
                    ),
                    Expanded(child: columns[shown]),
                  ]),
            ),
        ]),
      ),
    ]);
  }

  /// _shutStrip is the settings folded away: a narrow strip, their names
  /// written down it, that opens them again.
  Widget _shutStrip(MixerLook look, String names, String kind) => Tooltip(
        message: "Show $names",
        child: InkWell(
          key: const ValueKey("editorSettingsOpen"),
          onTap: () => c.toggleSettingsShut(kind),
          child: SizedBox(
            width: 24,
            child: Column(children: [
              const SizedBox(height: 6),
              Icon(Icons.chevron_left, size: 16, color: look.studio.muted),
              const SizedBox(height: 6),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: Text(names,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style:
                          TextStyle(fontSize: 10.5, color: look.studio.muted)),
                ),
              ),
            ]),
          ),
        ),
      );

  /// _foldButton folds the settings away, for the most room for what it
  /// plays.
  Widget _foldButton(MixerLook look, String kind) => Tooltip(
        message: "Hide the settings",
        child: InkWell(
          key: const ValueKey("editorSettingsShut"),
          borderRadius: BorderRadius.circular(5),
          onTap: () => c.toggleSettingsShut(kind),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(Icons.last_page, size: 16, color: look.studio.muted),
          ),
        ),
      );

  /// _columnsButton shows every column of settings, or folds them to one --
  /// the one picked above it -- for more room for what it plays.
  Widget _columnsButton(MixerLook look, {required bool wide}) => Tooltip(
        message: wide ? "Show one column" : "Show every column",
        child: InkWell(
          key: const ValueKey("editorWide"),
          borderRadius: BorderRadius.circular(5),
          onTap: c.toggleEditorWide,
          child: SizedBox(
            width: 22,
            height: wide ? null : 22,
            child: Align(
              alignment: wide ? Alignment.topCenter : Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(top: wide ? 8 : 0),
                child: Icon(wide ? Icons.chevron_right : Icons.chevron_left,
                    size: 16, color: look.studio.muted),
              ),
            ),
          ),
        ),
      );

  /// _partLaunchColumn is a part's Launch: it plays with the timeline, not
  /// from a slot, but copied into one it is launched as any clip is.
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
  /// long the roll shows it, and the playhead's place in it (where a paste
  /// goes and Play starts).
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: BorderSide(color: on ? look.studio.on : look.studio.edge)),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(5),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: onTap == null
                          ? look.studio.muted
                          : on
                              ? look.studio.onOn
                              : look.studio.text)),
            ),
          ),
        ),
      );

  /// _drop is a list to pick from, boxed as the prototype's selects are.
  Widget _drop<T>(MixerLook look, Key key, T value, List<(String, T)> items,
          ValueChanged<T> onChanged) =>
      Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: look.studio.inset,
          border: Border.all(color: look.studio.edge),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButton<T>(
          key: key,
          value: value,
          isDense: true,
          isExpanded: true,
          underline: const SizedBox(),
          iconSize: 14,
          iconEnabledColor: look.studio.muted,
          style: _small(look).copyWith(fontSize: 10.5),
          dropdownColor: look.colors.surfaceContainerHigh,
          items: [
            for (var (label, v) in items)
              DropdownMenuItem(
                  value: v,
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );

  /// _row is a setting: its name, and what sets it.
  static String _seconds(double s) => s < 1
      ? "${(s * 1000).round()} ms"
      : "${s.toStringAsFixed(s < 10 ? 1 : 0)} s";

  Widget _row(MixerLook look, String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
              width: 64,
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

  /// _head is a heading of a column's, as the prototype's inspector has
  /// them: small, uppercase, quiet -- and [end] at its right.
  Widget _head(MixerLook look, String title, {String? end, Key? key}) {
    var style = TextStyle(
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: look.studio.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(
            child: Text(title.toUpperCase(),
                key: key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style)),
        if (end != null) Text(end.toUpperCase(), style: style),
      ]),
    );
  }

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
            _head(look, title),
            ...children,
          ]),
        ),
      );

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

  /// _secondsAt and _beatsAt turn a place in [clip], in beats, into how far
  /// into its sound that is, in seconds, and back: by its warp map when
  /// warped, else at the song's tempo (faster with its pitch).
  double _secondsAt(SessionClip clip, double beats) {
    var spb = math.max(0.001, c.document.audio.secondsPerBeat);
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    return clip.warp ? clip.warpMap.sourceAt(beats) : beats * spb * speed;
  }

  double _beatsAt(SessionClip clip, double seconds) {
    var spb = math.max(0.001, c.document.audio.secondsPerBeat);
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    return clip.warp ? clip.warpMap.beatAt(seconds) : seconds / speed / spb;
  }

  List<Widget> _clipColumn(MixerLook look, SessionClip clip) {
    var bpb = c.document.audio.beatsPerBar;
    // A place typed as Ableton's are: "3", "3.2" or "3.2.3" (bar, beat,
    // sixteenth). One that is not a place is left as it was.
    ValueChanged<String> typed(
            SessionClip Function(SessionClip x, double beats) change) =>
        (text) {
          if (beatsOfPlace(text, bpb) case var b?) {
            c.editClip((x) => change(x, b));
          }
        };
    var bars = clip.bars;
    var lengths = {
      0.25, 0.5, //
      ...clipBarChoices.map((b) => b.toDouble()),
      bars,
    }.toList()
      ..sort();
    String barsText(double b) =>
        b == 1 ? "1 bar" : "${b == b.roundToDouble() ? b.round() : b} bars";
    // Readouts, as the prototype's: each typed into once clicked.
    var readout = _small(look).copyWith(
        fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]);
    Widget place(String key, String value, ValueChanged<String> onTyped) =>
        _TypedPlace(
            key: ValueKey(key),
            value: value,
            style: readout,
            align: TextAlign.left,
            onTyped: onTyped);
    return [
      _row(
          look,
          "Starts",
          // Typed as a place, or a time ("0.18s", "180ms"): a sound's start
          // is set by ear.
          place(
              "clipStart",
              "${_place(clip.start)} · "
                  "${_secondsAt(clip, clip.start).toStringAsFixed(2)}s",
              (text) {
            var t = text.trim().toLowerCase();
            var ms = RegExp(r"^([0-9.]+)\s*ms$").firstMatch(t);
            var sec = RegExp(r"^([0-9.]+)\s*s$").firstMatch(t);
            var seconds = ms != null
                ? (double.tryParse(ms.group(1)!) ?? -1) / 1000
                : sec != null
                    ? double.tryParse(sec.group(1)!) ?? -1
                    : null;
            if (seconds != null) {
              if (seconds >= 0) {
                c.editClip((x) => x.copyWith(start: _beatsAt(x, seconds)));
              }
              return;
            }
            typed((x, b) => x.copyWith(start: b))(text);
          })),
      _row(
          look,
          "Loop",
          Row(children: [
            Flexible(
              child: place("clipLoopStart", _place(clip.loopStart),
                  typed((x, b) => x.copyWith(loopStart: b))),
            ),
            Text(" – ", style: readout),
            // Its end typed: the loop as long as that makes it.
            Flexible(
              child: place(
                  "clipEnds",
                  _place(clip.loopEnd(bpb)),
                  typed((x, b) => b > x.loopStart
                      ? x.copyWith(bars: (b - x.loopStart) / bpb)
                      : x)),
            ),
            const SizedBox(width: 4),
            // Round its loop until stopped, or once through.
            Tooltip(
              message: clip.loop
                  ? "Loops: round until it is stopped"
                  : "Plays once through",
              child: InkWell(
                key: const ValueKey("clipLoop"),
                borderRadius: BorderRadius.circular(4),
                onTap: () => c.editClip((x) => x.copyWith(loop: !x.loop)),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.repeat,
                      size: 15,
                      color: clip.loop ? look.studio.on : look.studio.muted),
                ),
              ),
            ),
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
      _row(
          look,
          "Colour",
          Align(
            alignment: Alignment.centerLeft,
            child: MenuAnchor(
              menuChildren: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                    for (var (i, colour) in sectionColors.indexed)
                      GestureDetector(
                        key: ValueKey("clipColour-$i"),
                        onTap: () => c.editClip((x) => x.copyWith(color: i)),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                              color: Color(colour),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                  color: i == clip.color
                                      ? look.studio.text
                                      : Colors.transparent,
                                  width: 2)),
                        ),
                      ),
                  ]),
                ),
              ],
              builder: (context, menu, _) => InkWell(
                key: const ValueKey("clipColour"),
                onTap: () => menu.isOpen ? menu.close() : menu.open(),
                child: Container(
                  width: 28,
                  height: 16,
                  decoration: BoxDecoration(
                      color: Color(
                          sectionColors[clip.color % sectionColors.length]),
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          )),
    ];
  }

  List<Widget> _launchColumn(MixerLook look, SessionClip clip) => [
        _row(
            look,
            "Pressed",
            Tooltip(
              message: clip.launch.hint,
              child: _drop(
                  look,
                  const ValueKey("clipLaunchMode"),
                  clip.launch,
                  [for (var m in LaunchMode.values) (m.label, m)],
                  (v) => c.editClip((x) => x.copyWith(launch: v))),
            )),
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
        // Take over from where the clip playing on the channel had got to.
        _row(
            look,
            "Legato",
            Tooltip(
              message: "Take over from where the clip playing on the "
                  "channel had got to, rather than from the start",
              child: _drop(
                  look,
                  const ValueKey("clipLegato"),
                  clip.legato,
                  const [("From its start", false), ("Takes over", true)],
                  (v) => c.editClip((x) => x.copyWith(legato: v))),
            )),
        // How much a pad's velocity (a Push's, launching it) sets how loud
        // it plays. A click is full velocity.
        _row(
            look,
            "Velocity",
            Tooltip(
              message: "How much a pad's velocity sets how loud it plays",
              child: _drop(
                  look,
                  const ValueKey("clipVelocity"),
                  (clip.velocity * 4).round() / 4,
                  [
                    for (var v in const [0.0, 0.25, 0.5, 0.75, 1.0])
                      ("${(v * 100).round()}%", v)
                  ],
                  (v) => c.editClip((x) => x.copyWith(velocity: v))),
            )),
      ];

  List<Widget> _notesColumn(MixerLook look) {
    Widget tool(NoteTool t, String tip) =>
        _pill(look, t.label, false, () => c.useNoteTool(t),
            key: ValueKey("noteTool-${t.name}"), tip: tip);
    var picked = c.rollSelected.length;
    var all = c.rollContent?.notes.length ?? 0;
    Widget group(List<Widget> tools) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 4, runSpacing: 4, children: tools),
        );
    return [
      Text(
          picked == 0
              ? "On every note -- or pick some in the notes: drag across "
                  "empty space, Shift-click to add one."
              : "On the $picked note${picked == 1 ? "" : "s"} picked.",
          key: const ValueKey("notesToolsOn"),
          style: _small(look, look.studio.muted).copyWith(fontSize: 10.5)),
      Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 2),
        child: Text("$all in all",
            style: _small(look, look.studio.muted).copyWith(fontSize: 10)),
      ),
      _head(look, "Transpose"),
      group([
        tool(NoteTool.down, "Down a semitone"),
        tool(NoteTool.up, "Up a semitone"),
        tool(NoteTool.octaveDown, "Down an octave"),
        tool(NoteTool.octaveUp, "Up an octave"),
        tool(NoteTool.fitToScale,
            "Each to the nearest note of the channel's scale"),
      ]),
      _head(look, "Transform", end: picked == 0 ? "Every note" : "Picked"),
      group([
        tool(
            NoteTool.humanise,
            "A little off the grid, a little louder "
            "or softer"),
        tool(NoteTool.legato, "Each held until the next"),
        tool(NoteTool.strum, "A chord's notes one after another, upwards"),
        tool(NoteTool.reverse, "Played backwards"),
        tool(NoteTool.invert, "Upside down: the highest the lowest"),
        tool(NoteTool.faster, "Twice as fast"),
        tool(NoteTool.slower, "Half as fast"),
        tool(NoteTool.crescendo, "Softer to louder, first to last"),
        tool(NoteTool.chop, "Each cut in two"),
        tool(NoteTool.join, "Notes of one key that touch made one"),
        tool(NoteTool.swing, "Every second sixteenth a little late"),
        tool(NoteTool.duplicate, "A copy after them"),
      ]),
      _head(look, "Generate"),
      group([
        tool(NoteTool.arpeggiate, "Each chord's notes one after another"),
        tool(NoteTool.rhythm, "Five notes in every eight sixteenths"),
        tool(NoteTool.fillChords, "The scale's chord on each note"),
        tool(NoteTool.third, "A third added over each: a chord"),
        tool(NoteTool.fifth, "A fifth added over each"),
        tool(NoteTool.chance, "Played half the time round"),
        tool(NoteTool.always, "Played every time"),
        tool(NoteTool.mute, "Kept but not played, or played again"),
      ]),
    ];
  }
}

// ---------------------------------------------------------------------------
// An audio clip's sound
// ---------------------------------------------------------------------------

/// _Sound is a stored sound as the editor draws it: the loudest of each of
/// its slices, how long it is, and where it is struck.
typedef _Sound = ({
  Float32List peaks,
  Float32List left,
  Float32List right,
  double seconds,
  List<double> hits
});

/// _soundsOf are each stored sound, worked out once.
final Map<String, Future<_Sound?>> _soundsOf = {};

const int _peakSlices = 4000;

/// _spectraOf are each stored sound's spectrogram, made once.
final Map<String, Future<ui.Image?>> _spectraOf = {};

Future<ui.Image?> _spectrumOf(String assetId) =>
    _spectraOf[assetId] ??= () async {
      var audio = await CanvasController.clipAudio(assetId);
      if (audio == null) {
        _spectraOf.remove(assetId);
        return null;
      }
      var (l, r) = audio;
      var made = await Isolate.run(() {
        var mono = Float32List(l.length);
        for (var i = 0; i < l.length; i++) {
          mono[i] = (l[i] + r[i]) / 2;
        }
        return spectrogramOf(mono);
      });
      var done = Completer<ui.Image>();
      ui.decodeImageFromPixels(made.rgba, made.columns, made.rows,
          ui.PixelFormat.rgba8888, done.complete);
      return _spectraMade[assetId] = await done.future;
    }();

/// _spectraMade are the spectrograms made, to draw at once.
final Map<String, ui.Image> _spectraMade = {};

Future<_Sound?> _soundOf(String assetId) => _soundsOf[assetId] ??= () async {
      var audio = await CanvasController.clipAudio(assetId);
      // Not kept, unread: it is read again next time.
      if (audio == null) {
        _soundsOf.remove(assetId);
        return null;
      }
      var (l, r) = audio;
      // Off the app's own isolate: a whole song's peaks and hits there hold up
      // the mixer's sound.
      return Isolate.run(() => _drawingOf(l, r));
    }();

_Sound _drawingOf(Float32List l, Float32List r) {
  var n = l.length;
  var peaks = Float32List(_peakSlices);
  var left = Float32List(_peakSlices), right = Float32List(_peakSlices);
  for (var i = 0; i < n; i++) {
    var a = l[i].abs(), b = r[i].abs();
    var k = i * _peakSlices ~/ n;
    if (a > left[k]) left[k] = a;
    if (b > right[k]) right[k] = b;
    var v = math.max(a, b);
    if (v > peaks[k]) peaks[k] = v;
  }
  return (
    peaks: peaks,
    left: left,
    right: right,
    seconds: n / 48000,
    hits: n == 0 ? const <double>[] : onsets(l, r),
  );
}

enum _Handle { start, loop, length, marker, point, fadeIn, fadeOut }

/// _SampleView is an audio clip's sound against the song's beats: its
/// start's flag and its loop's bar on a ruler over it, to drag, and, when
/// warped, its warp markers under the ruler.
class _SampleView extends StatefulWidget {
  final CanvasController controller;
  final SessionClip clip;

  /// envelope is the key of the envelope drawn over its sound (see
  /// SessionClip.curveOf), or null; envelopeRest is its height with no
  /// points, and envelopeLength its own length in beats, or null for one that
  /// goes with the clip.
  final String? envelope;
  final double envelopeRest;
  final double? envelopeLength;

  /// spectral draws its sound as a spectrogram, under its wave.
  final bool spectral;

  /// onSay tells the editor something to show on its line of help.
  final ValueChanged<String?>? onSay;

  /// envelopeName is a channel setting's envelope's name, written over the
  /// sound.
  final String? envelopeName;
  const _SampleView(
      {required this.controller,
      required this.clip,
      this.envelope,
      this.envelopeRest = 1,
      this.envelopeLength,
      this.spectral = false,
      this.onSay,
      this.envelopeName});

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

  /// The last marker tapped and when, for a double-click taking it out.
  int? _tappedMarker;

  /// The last envelope point tapped, for a double-click taking it out.
  int? _tappedPoint;
  DateTime _tappedAt = DateTime(0);
  double _dragFrom = 0, _valueFrom = 0;

  /// _zoom is how far in the sound is drawn (one: all of it in view), and
  /// _scroll the beat at the view's left edge. Setting a start finer than a
  /// beat needs the sound seen closer than a bar.
  double _zoom = 1;
  double _scroll = 0;
  static const double _maxZoom = 256;

  /// _step is what a drag snaps to, at [beatW] pixels a beat: the finest grid
  /// (a beat, a half, down to 1/256) still eight pixels wide. With Alt held,
  /// nothing.
  static double _step(double beatW) {
    if (HardwareKeyboard.instance.isAltPressed) return 0;
    var step = 1.0;
    while (step > 1 / 256 && step / 2 * beatW >= 8) {
      step /= 2;
    }
    return step;
  }

  static double _snap(double v, double step) =>
      step <= 0 ? v : (v / step).roundToDouble() * step;

  /// _zoomAbout zooms by [factor], keeping the beat under [x] where it is.
  void _zoomAbout(double factor, double x, double fit) {
    var was = fit * _zoom;
    var under = x / was + _scroll;
    var next = (_zoom * factor).clamp(1.0, _maxZoom);
    setState(() {
      _zoom = next;
      _scroll = under - x / (fit * next);
    });
  }

  @override
  void initState() {
    super.initState();
    // The playhead, while it plays: the ticker runs only then, as it asks
    // for a frame on every screen refresh.
    _ticker = createTicker((_) {
      var at = c.clipPlayhead;
      if (at != _playhead) setState(() => _playhead = at);
      if (at == null) _ticker.stop();
    });
    c.addListener(_followPlayhead);
    _followPlayhead();
  }

  void _followPlayhead() {
    if (c.clipPlayhead != null && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    c.removeListener(_followPlayhead);
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
    // Its spectrogram, once made, when the Spectrum view is on.
    ui.Image? spectrum;
    if (widget.spectral && sound != null) {
      spectrum = _spectraMade[sound.assetId];
      if (spectrum == null) {
        _spectrumOf(sound.assetId).then((_) {
          if (mounted) setState(() {});
        });
      }
    }
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
        // Where a moment of the sound falls, in beats, and back: see _secondsAt.
        var map = clip.warpMap;
        var speed =
            math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
        double beatOf(double seconds) =>
            clip.warp ? map.beatAt(seconds) : seconds / speed / spb;
        double secondOf(double beat) =>
            clip.warp ? map.sourceAt(beat) : beat * spb * speed;
        var soundBeats = beatOf(length);
        // In view: the sound, its loop, and a bar more.
        // In view: the sound and its loop, edge to edge, as the
        // prototype's.
        var beats = [
          soundBeats,
          clip.loopEnd(bpb),
          clip.start + 1,
        ].reduce(math.max);
        var fit = size.maxWidth / beats;
        var beatW = fit * _zoom;
        // Kept in reach: never past the end, never before the start.
        var shown = size.maxWidth / beatW;
        var scroll =
            _scroll.clamp(0.0, math.max(0.0, beats - shown)).toDouble();
        double beatAt(double x) => x / beatW + scroll;
        double xOf(double beat) => (beat - scroll) * beatW;
        var step = _step(beatW);
        var markers = clip.warp ? clip.markers : const <WarpMarker>[];
        var top = _rulerH + _markersH;
        var spbNow = math.max(0.001, c.document.audio.secondsPerBeat);
        // The fades' grips, at the top of the sound: where the fade in
        // ends and the fade out begins.
        var fadeInX = xOf(clip.start + clip.fadeIn / spbNow);
        var fadeOutX = xOf(clip.loopEnd(bpb) - clip.fadeOut / spbNow);
        return GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("clipRuler"),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          // A warp marker added, at a hit near where it was clicked; one
          // right-clicked taken out.
          onTapUp: (d) {
            var p = d.localPosition;
            // An envelope's point, where the sound is.
            if (widget.envelope case var env? when p.dy > top) {
              if (_pointNear(clip, env, beatW, top, size.maxHeight,
                      p + Offset(scroll * beatW, 0))
                  case var i?) {
                // Twice on it: taken out, as a right-click does.
                var now = DateTime.now();
                if (i == _tappedPoint &&
                    now.difference(_tappedAt) <
                        const Duration(milliseconds: 400)) {
                  _tappedPoint = null;
                  c.editClip((x) =>
                      x.withCurve(env, [...x.curveOf(env)]..removeAt(i)));
                } else {
                  _tappedPoint = i;
                  _tappedAt = now;
                }
                return;
              }
              _tappedPoint = null;
              var beat = _onEnvelope(_snap(beatAt(p.dx), math.min(step, 0.25)));
              var value = _valueAt(p.dy, top, size.maxHeight);
              c.editClip(
                  (x) => x.withCurve(env, [...x.curveOf(env), (beat, value)]));
              return;
            }
            if (p.dy < _rulerH || p.dy > top) return;
            if (!clip.warp) {
              widget.onSay?.call("Switch Warp on to place warp markers");
              return;
            }
            var beat = beatAt(p.dx);
            if (_markerNear(markers, beatW, p.dx + scroll * beatW)
                case var i?) {
              // Twice on it: taken out, as a right-click does.
              var now = DateTime.now();
              if (i == _tappedMarker &&
                  now.difference(_tappedAt) <
                      const Duration(milliseconds: 400)) {
                _tappedMarker = null;
                c.editClip(
                    (x) => x.copyWith(markers: [...x.markers]..removeAt(i)));
              } else {
                _tappedMarker = i;
                _tappedAt = now;
              }
              return;
            }
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
              var i = _pointNear(clip, env, beatW, top, size.maxHeight,
                  d.localPosition + Offset(scroll * beatW, 0));
              if (i == null) return;
              c.editClip(
                  (x) => x.withCurve(env, [...x.curveOf(env)]..removeAt(i)));
              return;
            }
            var i = _markerNear(
                markers, beatW, d.localPosition.dx + scroll * beatW);
            if (i == null || d.localPosition.dy > top) return;
            c.editClip((x) => x.copyWith(markers: [...x.markers]..removeAt(i)));
          },
          onPanStart: (d) {
            var p = d.localPosition;
            if (widget.envelope case var env? when p.dy > top) {
              var i = _pointNear(clip, env, beatW, top, size.maxHeight,
                  p + Offset(scroll * beatW, 0));
              if (i == null) return;
              _dragging = _Handle.point;
              _marker = i;
              c.beginInteraction();
              return;
            }
            // The fades' grips.
            if (p.dy >= top && p.dy <= top + 14) {
              if ((p.dx - fadeInX).abs() <= 8) {
                _dragging = _Handle.fadeIn;
                c.beginInteraction();
                return;
              }
              if ((p.dx - fadeOutX).abs() <= 8) {
                _dragging = _Handle.fadeOut;
                c.beginInteraction();
                return;
              }
            }
            if (p.dy > top + 12) return;
            var x = p.dx;
            if (clip.warp && p.dy >= _rulerH && p.dy <= top) {
              var i = _markerNear(markers, beatW, x + scroll * beatW);
              if (i == null) return;
              _dragging = _Handle.marker;
              _marker = i;
              _valueFrom = markers[i].beat;
            } else {
              var startX = xOf(clip.start);
              var endX = xOf(clip.loopEnd(bpb));
              var loopX = xOf(clip.loopStart);
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
            // To the finest grid still a few pixels wide (see _step), or, Alt held,
            // to nothing.
            var moved = (d.localPosition.dx - _dragFrom) / beatW;
            switch (handle) {
              case _Handle.fadeIn:
                var b = beatAt(d.localPosition.dx);
                var most = (clip.loopEnd(bpb) - clip.start) / 2;
                var beats = (b - clip.start).clamp(0.0, math.max(0.0, most));
                c.editClip(
                    (x) => x.copyWith(
                        fadeIn: (beats * spbNow * 100).roundToDouble() / 100),
                    transient: true);
              case _Handle.fadeOut:
                var b = beatAt(d.localPosition.dx);
                var most = (clip.loopEnd(bpb) - clip.start) / 2;
                var beats =
                    (clip.loopEnd(bpb) - b).clamp(0.0, math.max(0.0, most));
                c.editClip(
                    (x) => x.copyWith(
                        fadeOut: (beats * spbNow * 100).roundToDouble() / 100),
                    transient: true);
              case _Handle.start:
                var v = math.max(0.0, _snap(_valueFrom + moved, step));
                c.editClip((x) => x.copyWith(start: v), transient: true);
              case _Handle.loop:
                var v = math.max(0.0, _snap(_valueFrom + moved, step));
                c.editClip((x) => x.copyWith(loopStart: v), transient: true);
              case _Handle.length:
                var least = step > 0 ? step : 1 / 64;
                var b = math.max(least, _snap(_valueFrom * bpb + moved, step));
                c.editClip((x) => x.copyWith(bars: b / bpb), transient: true);
              case _Handle.point:
                var env = widget.envelope;
                if (env == null) return;
                var beat = _onEnvelope(
                    _snap(beatAt(d.localPosition.dx), math.min(step, 0.25)));
                var value = _valueAt(d.localPosition.dy, top, size.maxHeight);
                c.editClip((x) {
                  var points = [...x.curveOf(env)];
                  if (_marker >= points.length) return x;
                  points[_marker] = (math.max(0.0, beat), value);
                  // Kept in order, and the one dragged followed.
                  var moved = points[_marker];
                  points.sort((a, b) => a.$1.compareTo(b.$1));
                  _marker = points.indexOf(moved);
                  return x.withCurve(env, points);
                }, transient: true);
              case _Handle.marker:
                var v = _snap(_valueFrom + moved, math.min(step, 0.25));
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
          child: Listener(
            // Two fingers along, or a wheel: across the sound. Pinched, or with Cmd
            // or Ctrl held: in or out, about the pointer.
            onPointerSignal: (e) {
              if (e is! PointerScrollEvent) return;
              var keys = HardwareKeyboard.instance;
              if (keys.isMetaPressed || keys.isControlPressed) {
                _zoomAbout(e.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15,
                    e.localPosition.dx, fit);
                return;
              }
              var by =
                  e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
              setState(() => _scroll = scroll + by / beatW);
            },
            onPointerPanZoomUpdate: (e) {
              if ((e.scale - 1).abs() > 0.001) {
                var to = (_pinchFrom * e.scale).clamp(1.0, _maxZoom);
                _zoomAbout(to / _zoom, e.localPosition.dx, fit);
              } else {
                setState(() => _scroll = scroll - e.panDelta.dx / beatW);
              }
            },
            onPointerPanZoomStart: (_) => _pinchFrom = _zoom,
            child: Stack(children: [
              CustomPaint(
                key: const ValueKey("clipSample"),
                size: Size(size.maxWidth, size.maxHeight),
                painter: _SamplePainter(
                  scroll: scroll,
                  step: step,
                  peaks: heard?.peaks,
                  left: heard?.left,
                  right: heard?.right,
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
                  fadeIn: clip.fadeIn / c.document.audio.secondsPerBeat,
                  fadeOut: clip.fadeOut / c.document.audio.secondsPerBeat,
                  fadeCurve: clip.fadeCurve,
                  spectrum: spectrum,
                  playhead: _playhead,
                  studio: look.studio,
                  rulerH: _rulerH,
                  top: top,
                  envelope: widget.envelope == null
                      ? null
                      : clip.curveOf(widget.envelope!),
                  envelopeRest: widget.envelopeRest,
                  envelopeLength: widget.envelopeLength,
                  envelopeLabel: switch (widget.envelope) {
                    null => "",
                    "gain" => "gain envelope · 0 dB down to silence",
                    "pan" => "pan envelope · left to right",
                    _ => widget.envelopeName ?? "",
                  },
                  gainCurve: clip.envelopes[ClipEnvelope.gain] ?? const [],
                  panCurve: clip.envelopes[ClipEnvelope.pan] ?? const [],
                  key: clip.warpSignature(spb),
                ),
              ),
              // Closer in, further out, and all of it: in the sound's lower
              // corner, off the ruler.
              Positioned(
                right: 6,
                bottom: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _zoomButton(
                      look,
                      "clipZoomOut",
                      Icons.remove,
                      _zoom <= 1
                          ? null
                          : () => _zoomAbout(1 / 2, size.maxWidth / 2, fit)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text("${_zoom.round()}×",
                        key: const ValueKey("clipZoom"),
                        style:
                            TextStyle(fontSize: 10, color: look.studio.muted)),
                  ),
                  _zoomButton(
                      look,
                      "clipZoomIn",
                      Icons.add,
                      _zoom >= _maxZoom
                          ? null
                          : () => _zoomAbout(2, size.maxWidth / 2, fit)),
                  const SizedBox(width: 2),
                  _zoomButton(
                      look,
                      "clipZoomFit",
                      Icons.fit_screen_outlined,
                      _zoom <= 1
                          ? null
                          : () => setState(() {
                                _zoom = 1;
                                _scroll = 0;
                              })),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  /// _pinchFrom is the zoom a pinch started from.
  double _pinchFrom = 1;

  Widget _zoomButton(
          MixerLook look, String key, IconData icon, VoidCallback? onTap) =>
      InkWell(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              color: look.studio.panel,
              border: Border.all(color: look.studio.edge),
              borderRadius: BorderRadius.circular(3)),
          child: Icon(icon,
              size: 12,
              color: onTap == null
                  ? look.studio.muted.withValues(alpha: 0.4)
                  : look.studio.text),
        ),
      );

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
  /// scroll is the beat at the left edge, zoomed in; step the grid a drag
  /// snaps to, drawn where it is finer than a beat (nought for none).
  final double scroll, step;
  final Float32List? peaks;

  /// left and right are each side's peaks: drawn as two halves, as the
  /// prototype's L and R.
  final Float32List? left, right;
  final double fileSeconds, playStart, playLength;
  final double Function(double beat) secondOf;
  final List<double> hits, markers;
  final int beatsPerBar;
  final double beatW, beats, soundBeats, start, loopStart, loopEnd, gain;
  final double rulerH, top;
  final bool loop;
  final double? playhead;
  final StudioColors studio;

  /// envelope is the envelope's points (a beat and a value each) drawn over
  /// the sound, or null for none; envelopeRest is its value with none.
  final List<ControlPoint>? envelope;
  final double envelopeRest;

  /// envelopeLength is the envelope's own length in beats (drawn once, then
  /// repeated fainter along the clip), or null.
  final double? envelopeLength;

  /// key is what the sound's drawing depends on beyond the rest: when it
  /// changes, it is drawn again.
  final String key;

  /// envelopeLabel names the envelope shown, written over the sound.
  final String envelopeLabel;

  /// gainCurve and panCurve are the clip's own envelopes: the sound drawn
  /// as they make it, shown or not, as the prototype's is (Ken: the
  /// envelope did not change the look of the sound).
  final List<ControlPoint> gainCurve, panCurve;

  _SamplePainter({
    this.scroll = 0,
    this.step = 1,
    required this.peaks,
    this.left,
    this.right,
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
    this.envelopeLabel = "",
    this.gainCurve = const [],
    this.panCurve = const [],
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.fadeCurve = FadeCurve.smooth,
    this.spectrum,
  });

  /// spectrum is its sound as a spectrogram (see spectrogram.dart), drawn
  /// under its wave when the Spectrum view is on.
  final ui.Image? spectrum;

  /// fadeIn and fadeOut are its fades, in beats, and [fadeCurve] their
  /// way: drawn as ramps over the sound.
  final double fadeIn, fadeOut;
  final FadeCurve fadeCurve;

  @override
  void paint(Canvas canvas, Size size) {
    var h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.inset);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, top), Paint()..color = studio.panel);
    // Zoomed in: the whole of it drawn along, and the view moved over it.
    var left = scroll * beatW;
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-left, 0);
    size = Size(math.max(size.width, beats * beatW), size.height);
    // The grid a drag snaps to, finer than a beat, faint.
    if (step > 0 && step < 1) {
      var fine = Paint()..color = studio.edge.withValues(alpha: 0.18);
      var from = (scroll / step).floor();
      var to = ((left + size.width) / beatW / step).ceil();
      for (var k = from; k <= to; k++) {
        var x = k * step * beatW;
        if (x < left - 1 || x > left + size.width) continue;
        canvas.drawLine(Offset(x, rulerH - 2), Offset(x, h), fine);
      }
    }
    // What it does not play, darker: before its start, past its end.
    var dim = Paint()..color = Colors.black.withValues(alpha: 0.28);
    var first = (loop ? math.min(start, loopStart) : start) * beatW;
    canvas.drawRect(Rect.fromLTRB(0, top, first, h), dim);
    canvas.drawRect(Rect.fromLTRB(loopEnd * beatW, top, size.width, h), dim);
    // The quarters of each beat, faint, where there is room.
    if (beatW >= 24) {
      var quarter = Paint()..color = studio.edge.withValues(alpha: 0.16);
      for (var q = 0; q <= beats * 4; q++) {
        if (q % 4 == 0) continue;
        var x = q * beatW / 4;
        canvas.drawLine(Offset(x, top), Offset(x, h), quarter);
      }
    }
    // The beats and bars, the bars numbered.
    var label = TextPainter(textDirection: TextDirection.ltr);
    var every = beatW * beatsPerBar < 28 ? 4 : 1;
    for (var b = 0; b <= beats; b++) {
      var x = b * beatW;
      var bar = b % beatsPerBar == 0;
      canvas.drawLine(Offset(x, bar ? 9 : rulerH - 7), Offset(x, rulerH),
          Paint()..color = studio.edge.withValues(alpha: bar ? 1 : 0.7));
      canvas.drawLine(Offset(x, top), Offset(x, h),
          Paint()..color = studio.edge.withValues(alpha: bar ? 0.75 : 0.35));
      if (bar && (b ~/ beatsPerBar) % every == 0) {
        label.text = TextSpan(
            text: "${b ~/ beatsPerBar + 1}",
            style: TextStyle(fontSize: 10.5, color: studio.text));
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
      var pin = Paint()..color = _fadeInk;
      for (var b in markers) {
        var x = b * beatW;
        // A flag on its staff, as the prototype's.
        canvas.drawPath(
            Path()
              ..moveTo(x, rulerH + 1)
              ..lineTo(x + 7, rulerH + 1)
              ..lineTo(x + 7, rulerH + 8)
              ..lineTo(x, rulerH + 13)
              ..close(),
            pin);
        canvas.drawLine(Offset(x, rulerH + 1), Offset(x, h),
            Paint()..color = _fadeInk.withValues(alpha: 0.4));
      }
    }
    // Its spectrum, where each moment of it falls: a column of the picture
    // every two pixels.
    if ((spectrum, fileSeconds) case (var image?, var seconds)
        when seconds > 0) {
      var shownTo = left + size.width;
      var paint = Paint()..filterQuality = FilterQuality.low;
      for (var x = left.floorToDouble();
          x < math.min(shownTo, soundBeats * beatW);
          x += 2) {
        var at = playStart + secondOf(x / beatW);
        if (at >= playStart + playLength) break;
        var col = (at / seconds * image.width).floorToDouble();
        if (col < 0 || col >= image.width) continue;
        canvas.drawImageRect(
            image,
            Rect.fromLTWH(col, 0, 1, image.height.toDouble()),
            Rect.fromLTWH(x, top, 2, h - top),
            paint);
      }
    }
    // The sound, where each moment of it falls: each side a half, as the
    // prototype's L and R -- or, over its spectrum, both together.
    var peaks = this.peaks;
    if (peaks != null && fileSeconds > 0) {
      var stereo = spectrum == null && this.left != null && right != null;
      var sides = stereo ? [this.left!, right!] : [peaks];
      var band = (h - top) / sides.length;
      var wave = Paint()
        ..color = spectrum == null
            ? const Color(0xFF4F8FD6)
            : studio.text.withValues(alpha: 0.12)
        ..strokeWidth = 1;
      var outside = Paint()
        ..color = const Color(0xFF4F8FD6).withValues(alpha: 0.35)
        ..strokeWidth = 1;
      var first = loop ? math.min(start, loopStart) : start;
      // Only what is in view, a pixel at a time: zoomed in far, the whole of
      // it is many windows wide.
      var shownTo = left + size.width;
      for (var (k0, side) in sides.indexed) {
        var mid = top + band * k0 + band / 2;
        var half = band / 2 - 4;
        for (var x = left.floorToDouble();
            x < math.min(shownTo, soundBeats * beatW);
            x += 1) {
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
            v = math.max(v, side[k]);
          }
          var beat = x / beatW;
          // As warp.dart's _envelop makes it: its gain squared, its pan a
          // balance.
          var shaped = 1.0;
          if (gainCurve.isNotEmpty) {
            var g = curveAt(gainCurve, beat, 1);
            shaped = g * g;
          }
          if (panCurve.isNotEmpty) {
            var pan = curveAt(panCurve, beat, 0.5);
            if (stereo) {
              shaped *= k0 == 0
                  ? (pan > 0.5 ? 2 * (1 - pan) : 1)
                  : (pan < 0.5 ? 2 * pan : 1);
            }
          }
          var y = math.min(1.0, v * gain * shaped) * half;
          canvas.drawLine(Offset(x, mid - y), Offset(x, mid + y),
              beat < first || beat > loopEnd ? outside : wave);
        }
        if (stereo) {
          var tp = TextPainter(
              text: TextSpan(
                  text: k0 == 0 ? "L" : "R",
                  style: TextStyle(fontSize: 10, color: studio.muted)),
              textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(canvas, Offset(left + 3, mid - tp.height / 2));
        }
      }
      if (stereo) {
        canvas.drawLine(
            Offset(left, top + band),
            Offset(left + size.width, top + band),
            Paint()..color = studio.edge);
      }
    }
    // The loop's bar over the ruler, and its end's grip.
    var brace = Paint()
      ..color = (loop ? studio.on : studio.muted).withValues(alpha: 0.45);
    var loopGrip = Paint()..color = loop ? studio.on : studio.muted;
    canvas.drawRect(
        Rect.fromLTRB(loopStart * beatW, 2, loopEnd * beatW, 8), brace);
    canvas.drawRect(Rect.fromLTWH(loopStart * beatW - 2, 1, 4, 9), loopGrip);
    canvas.drawRect(Rect.fromLTWH(loopEnd * beatW - 2, 1, 4, 9), loopGrip);
    // The start's flag.
    var sx = start * beatW;
    canvas.drawPath(
        Path()
          ..moveTo(sx, 11)
          ..lineTo(sx + 7, 15)
          ..lineTo(sx, 19)
          ..close(),
        Paint()..color = studio.text);
    canvas.drawLine(Offset(sx, 11), Offset(sx, h),
        Paint()..color = studio.text.withValues(alpha: 0.35));
    // The envelope: a line through its points, held flat before the first
    // and after the last, over the sound dimmed.
    if (envelope case var points?) {
      double y(double v) => top + 6 + (1 - v) * math.max(1, h - top - 12);
      const colour = _envelopeInk;
      if (envelopeLabel.isNotEmpty) {
        var tp = TextPainter(
            text: TextSpan(
                text: envelopeLabel,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: colour)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(left + 8, top + 4));
      }
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
        // Its own length, repeated along the clip, the first pass the one
        // edited.
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
    // Its fades: the level rising from its start (and its loop's) and
    // falling to its loop's end, the faded part shaded.
    void ramp(double from, double to, bool rising) {
      if (to <= from) return;
      var path = Path();
      var shade = Path()..moveTo(from * beatW, top);
      for (var k = 0; k <= 32; k++) {
        var u = k / 32;
        var level = fadeCurve.level(rising ? u : 1 - u);
        var x = (from + (to - from) * u) * beatW;
        var y = top + (h - top) * (1 - level);
        k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        shade.lineTo(x, y);
      }
      shade
        ..lineTo(to * beatW, top)
        ..close();
      canvas.drawPath(shade, Paint()..color = const Color(0x44000000));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _fadeInk);
    }

    // The fades' grips, amber squares at the top of the sound: dragged,
    // the fades are longer or shorter.
    var grip = Paint()..color = _fadeInk;
    canvas.drawRect(
        Rect.fromLTWH((start + fadeIn) * beatW - 4, top + 1, 8, 8), grip);
    canvas.drawRect(
        Rect.fromLTWH((loopEnd - fadeOut) * beatW - 4, top + 1, 8, 8), grip);

    if (fadeIn > 0) {
      ramp(start, start + fadeIn, true);
      if (loop && (loopStart - start).abs() > 1e-6) {
        ramp(loopStart, loopStart + fadeIn, true);
      }
    }
    if (fadeOut > 0) ramp(loopEnd - fadeOut, loopEnd, false);
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
      old.spectrum != spectrum ||
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
      old.gainCurve != gainCurve ||
      old.panCurve != panCurve ||
      old.envelopeLabel != envelopeLabel ||
      old.envelopeLength != envelopeLength ||
      old.envelopeRest != envelopeRest ||
      old.studio != studio;
}

/// beatsOfPlace is a place typed as Ableton's are ("bar.beat.sixteenth",
/// "bar.beat" or "bar", each counted from one) in beats from the start, at
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

/// typedNumber is the number typed at the front of [text] -- "-3", "+2.5
/// dB", "−1" -- and the unit after it, lower case ("" for none); null
/// where it starts with no number.
(double, String)? typedNumber(String text) {
  var m = RegExp(r"^\s*([+\-−]?\d*\.?\d+)\s*([a-zA-Z%]*)")
      .firstMatch(text.trim());
  if (m == null) return null;
  var v = double.tryParse(m.group(1)!.replaceAll("−", "-").replaceAll("+", ""));
  if (v == null) return null;
  return (v, m.group(2)!.toLowerCase());
}

/// _TypedPlace is a place shown as bar.beat.sixteenth, typed into once
/// clicked: Return sets it, Escape or clicking away leaves it.
class _TypedPlace extends StatefulWidget {
  final String value;
  final TextStyle style;
  final TextAlign align;
  final ValueChanged<String> onTyped;

  /// doubleClick is whether it is typed into on a double-click, as a
  /// setting's number is (a click on it is the slider's, or nothing),
  /// rather than on one.
  final bool doubleClick;
  const _TypedPlace(
      {required this.value,
      required this.style,
      required this.onTyped,
      this.align = TextAlign.center,
      this.doubleClick = false,
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
      void type() {
        _text.text = widget.value;
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: widget.value.length);
        setState(() => _typing = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _focus.requestFocus());
      }

      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.doubleClick ? null : type,
          onDoubleTap: widget.doubleClick ? type : null,
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
