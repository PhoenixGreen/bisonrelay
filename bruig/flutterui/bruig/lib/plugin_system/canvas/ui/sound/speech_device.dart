import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/qwen_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_downloads.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/media/speech_finish.dart'
    show lineGap;
import 'package:bruig/plugin_system/canvas/model/instrument.dart' show MidiNote;
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/phrasing_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart'
    show TextDocumentRef;
import 'package:bruig/plugin_system/canvas/ui/picking/document_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/text_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

part 'speech_device_voices.dart';
part 'speech_device_script.dart';
part 'speech_device_takes.dart';
part 'speech_device_feel.dart';
part 'speech_device_layout.dart';

// speech_device.dart is the Speech device in a channel's chain: engine and
// voice; the script line by line, each with its direction and takes; the
// voice's feel; and Speak all, which speaks the lines in the background and
// joins the chosen takes into a clip on the channel. See speech_spec.dart
// for what it keeps and speech_engines.dart for how it speaks.

const _problemInk = Color(0xFFFF8A80);

/// _cueIcons are the cues' icons. Not emoji: Impeller draws emoji into its
/// glyph atlas slowly and redraws them whenever the atlas is rebuilt,
/// costing seconds a frame.
const _cueIcons = {
  SpeechCue.pause: Icons.pause,
  SpeechCue.breath: Icons.air,
  SpeechCue.exhale: Icons.blur_on,
  SpeechCue.laugh: Icons.sentiment_very_satisfied,
  SpeechCue.sigh: Icons.sentiment_dissatisfied,
  SpeechCue.cough: Icons.sick_outlined,
  SpeechCue.whisper: Icons.volume_down,
  SpeechCue.stress: Icons.priority_high,
  SpeechCue.slow: Icons.slow_motion_video,
};

/// SpeechKit is what the Speech device is drawn with: the studio palette's
/// text, boxes, buttons, chips and dropdowns.
class SpeechKit {
  final StudioColors s;
  final ColorScheme scheme;
  const SpeechKit(this.s, this.scheme);

  TextStyle text(double size,
          {FontWeight? weight, Color? colour, double? height}) =>
      TextStyle(
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: colour ?? s.text);

  TextStyle mono(double size, {Color? colour}) => TextStyle(
      fontFamily: "RobotoMono",
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: colour ?? s.text);

  /// cued is [script]'s words with its cues ("[laugh]") shown as tags.
  TextSpan cued(String script) {
    var spans = <InlineSpan>[];
    var at = 0;
    for (var m in RegExp(r"\[([a-z]+)(?:\s+[0-9.]+)?\]").allMatches(script)) {
      if (m.start > at) {
        spans.add(TextSpan(text: script.substring(at, m.start)));
      }
      spans.add(TextSpan(
          text:
              " ${m[1]}${m[0]!.contains(" ") ? " ${m[0]!.split(" ").last.replaceAll("]", "")}s" : ""} ",
          style: text(10.5, colour: s.solo)
              .copyWith(backgroundColor: s.solo.withValues(alpha: 0.16))));
      at = m.end;
    }
    if (at < script.length) spans.add(TextSpan(text: script.substring(at)));
    return TextSpan(children: spans);
  }

  Widget label(String t) => Text(t,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text(11, colour: s.muted));

  Widget section(String t) => Text(t.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text(9.5, weight: FontWeight.w700, colour: s.muted)
          .copyWith(letterSpacing: 0.6));

  BoxDecoration box(Color fill, {Color? border}) => BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: border ?? s.edge));

  InputDecoration field(String hint, {int lines = 4}) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: s.inset,
        hintText: hint,
        hintMaxLines: lines,
        hintStyle: text(11, colour: s.muted.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: s.edge)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: s.solo)),
      );

  Widget button(String label, VoidCallback? onTap,
      {Key? key,
      IconData? icon,
      Color? fill,
      Color? ink,
      bool small = false,
      String? tip}) {
    var colour = onTap == null ? s.muted.withValues(alpha: 0.6) : ink ?? s.text;
    Widget out = Material(
      color: fill ?? s.raised,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: fill == null ? BorderSide(color: s.edge) : BorderSide.none),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: SizedBox(
          height: small ? 22 : 26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 13, color: colour),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text(11,
                            weight: fill == null ? null : FontWeight.w600,
                            colour: colour)),
                  ),
                ]),
          ),
        ),
      ),
    );
    return tip == null ? out : Tooltip(message: tip, child: out);
  }

  /// chip is a rounded choice, lit blue when chosen.
  Widget chip(String label, bool on, VoidCallback? onTap,
      {Key? key, IconData? icon}) {
    var colour = on
        ? s.text
        : onTap == null
            ? s.muted
            : s.text.withValues(alpha: 0.9);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: on ? s.solo.withValues(alpha: 0.25) : s.strip,
        shape: StadiumBorder(side: BorderSide(color: on ? s.solo : s.edge)),
        child: InkWell(
          key: key,
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: colour),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text(10.5, colour: colour)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// take is one of a line's slots, by letter: lit when its take is chosen,
  /// greyed while [empty], ringed blue while [picked] in the line panel,
  /// turning while [working] (being spoken into).
  Widget take(String letter, bool on, VoidCallback? onTap,
          {Key? key,
          bool empty = false,
          bool picked = false,
          bool working = false}) =>
      Material(
        color: on
            ? s.on
            : empty
                ? Colors.transparent
                : s.inset,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
                color: picked
                    ? s.solo
                    : on
                        ? s.on
                        : empty
                            ? s.edge.withValues(alpha: 0.5)
                            : s.edge,
                width: picked ? 2 : 1)),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 22,
            child: Center(
              child: working
                  ? SizedBox.square(
                      dimension: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: s.on))
                  : Text(letter,
                      style: text(11,
                          weight: FontWeight.w700,
                          colour: on
                              ? s.onOn
                              : empty
                                  ? s.muted.withValues(alpha: 0.6)
                                  : s.text)),
            ),
          ),
        ),
      );

  /// dropdown is a choice of [items] (value and words) in a field-like box.
  Widget dropdown<T>(
          {required Key key,
          required T value,
          required List<(T, String)> items,
          required ValueChanged<T> onChanged,
          Map<T, Key> itemKeys = const {}}) =>
      Container(
        height: 26,
        padding: const EdgeInsets.only(left: 8, right: 4),
        decoration: box(s.inset),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: key,
            isExpanded: true,
            isDense: true,
            value: value,
            style: text(11.5),
            iconSize: 18,
            iconEnabledColor: s.muted,
            dropdownColor: s.raised,
            borderRadius: BorderRadius.circular(5),
            items: [
              for (var (v, words) in items)
                DropdownMenuItem(
                    value: v,
                    child: Text(words,
                        key: itemKeys[v],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}

class SpeechDevice extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const SpeechDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    this.editor = false,
    super.key,
  });

  /// editor fills the Chain as the Speech view, rather than being a card.
  final bool editor;

  @override
  State<SpeechDevice> createState() => _SpeechDeviceState();
}

/// _SpeechView is what one build of the Speech device works from: its
/// spec and what follows from it, worked out once (_viewOf) and handed to
/// each section.
class _SpeechView {
  final SpeechSpec spec;
  final SpeechKit k;
  final StudioColors s;
  final DeviceSkin skin;
  final SpeechEngineKind engine;
  final bool expressive, local, unmade, needsVoices;

  /// download is the engine's voices to fetch; picked the voice in use.
  final PinnedDownload download;
  final String picked;

  /// lines are the sections, and line the one picked.
  final List<SpeechLine> lines;
  final SpeechLine? line;
  final bool asText;

  /// queue is the sections still to speak, while Speak all runs.
  final List<String>? queue;
  final bool busy, cantSpeak, allSpoken, reading, phrasingOn;
  final int spoken, pickedSlot;

  const _SpeechView({
    required this.spec,
    required this.k,
    required this.s,
    required this.skin,
    required this.engine,
    required this.expressive,
    required this.local,
    required this.download,
    required this.unmade,
    required this.needsVoices,
    required this.picked,
    required this.lines,
    required this.line,
    required this.asText,
    required this.queue,
    required this.busy,
    required this.spoken,
    required this.cantSpeak,
    required this.allSpoken,
    required this.reading,
    required this.phrasingOn,
    required this.pickedSlot,
  });
}

class _SpeechDeviceState extends State<SpeechDevice> {
  // The parts are extensions, and call setState: overridden so the call
  // is this class's own, not State's protected one.
  @override
  void setState(VoidCallback fn) => super.setState(fn);

  CanvasController get c => widget.controller;
  final TextEditingController _script = TextEditingController();
  final FocusNode _scriptFocus = FocusNode();
  final TextEditingController _own = TextEditingController();
  final FocusNode _ownFocus = FocusNode();

  /// _voices are the engine's voices, asked for once per engine
  /// (_voicesFor).
  Future<List<SpeechVoice>>? _voices;
  String _voicesFor = "";
  String _filter = "";

  /// _accent narrows the voice list to an accent (the start of a voice's
  /// description, "UK", "US"), or "" for all.
  String _accent = "";

  /// _missing is how much of each download's voices is still to fetch.
  final Map<PinnedDownload, Future<int>> _missing = {};
  String? _problem;

  /// _asText is whether the script shows as text to edit rather than lines:
  /// null until chosen, meaning text for a device with nothing written yet.
  bool? _asText;

  /// _line is the line picked in the list, and _slot its slot picked (A to
  /// C), null for the one its take is chosen in.
  int _line = 0;
  int? _slot;

  @override
  void initState() {
    super.initState();
    for (var d in [KokoroDownload.instance, QwenDownload.instance]) {
      d.addListener(_changed);
      d.check();
    }
    _scriptFocus.addListener(() {
      // A stretch of typing, one change to undo.
      if (!_scriptFocus.hasFocus) c.endInteraction();
    });
    _ownFocus.addListener(() {
      if (!_ownFocus.hasFocus) _keepOwn();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    KokoroDownload.instance.removeListener(_changed);
    QwenDownload.instance.removeListener(_changed);
    _script.dispose();
    _scriptFocus.dispose();
    _own.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  void _set(SpeechSpec spec, {bool transient = false}) =>
      c.setSpeech(widget.channel, spec, transient: transient);

  Future<void> _run(Future<String?> Function() job) async {
    setState(() => _problem = null);
    var problem = await job();
    if (mounted) setState(() => _problem = problem);
  }

  void _speakAll() => _run(() => c.speakLines(widget.channel));

  /// _linesOf is the device's lines, set out from its script if it has none.
  List<SpeechLine> _linesOf(SpeechSpec spec) => spec.shownLines;

  /// _changeLine changes line [index] (its direction or own words) and, where
  /// it has been spoken and has a slot free, speaks it again into it, keeping
  /// the other takes to compare. With every slot in use nothing is spoken:
  /// the reader picks a slot to replace.
  void _changeLine(SpeechSpec spec, int index, SpeechLine changed) {
    var lines = [..._linesOf(spec)];
    if (index >= lines.length) return;
    var was = lines[index];
    lines[index] = changed;
    c.setSpeechLines(widget.channel, lines);
    if (was.takes.isNotEmpty &&
        changed.freeSlot >= 0 &&
        (was.direction != changed.direction || was.own != changed.own)) {
      _run(() => c.anotherTake(widget.channel, changed));
    }
  }

  /// _pickLine picks line [i], its slot picked afresh.
  void _pickLine(int i) => setState(() {
        if (_line != i) _slot = null;
        _line = i;
      });

  /// _keepOwn keeps the own words typed for the line picked.
  void _keepOwn() {
    var spec = c.speechOf(widget.channel);
    if (spec == null) return;
    var lines = _linesOf(spec);
    if (_line >= lines.length) return;
    var own = _own.text.trim();
    if (own == lines[_line].own) return;
    _changeLine(spec, _line, lines[_line].copyWith(own: own));
  }

  @override
  Widget build(BuildContext context) {
    var view = _viewOf(context);
    if (view == null) return const SizedBox();
    // Each section made in the order it always was: the voices first,
    // whose list is asked for even while Phrasing hides it.
    var voiceColumn = _voiceColumn(view);
    var scriptColumn = _scriptColumn(view,
        scriptText: _scriptText(view), scriptLines: _scriptLines(view));
    var feelColumn = _feelColumn(view);
    var clipStrip = _clipStrip(view);
    var engines = _engines(view);
    var remove = _removeButton(view);
    var inside = _inside(view,
        voiceColumn: voiceColumn,
        scriptColumn: scriptColumn,
        feelColumn: feelColumn,
        clipStrip: clipStrip);
    if (widget.editor) {
      var toggles = [
        for (var (kind, name, _) in _panels(view)) _toggle(view, kind, name)
      ];
      return _editorView(view, inside, engines, toggles, remove);
    }
    return _cardView(view, inside, engines, remove);
  }

  /// _viewOf brings the text fields and the line picked into step with
  /// the spec, and works out what the sections are drawn from: null where
  /// the channel has no Speech device.
  _SpeechView? _viewOf(BuildContext context) {
    var spec = c.speechOf(widget.channel);
    if (spec == null) return null;
    if (!_scriptFocus.hasFocus && _script.text != spec.script) {
      _script.text = spec.script;
    }
    var look = MixerLook.of(context);
    var skin = DeviceSkin.themed(look.colors);
    var k = SpeechKit(look.studio, look.colors);
    var s = look.studio;
    var engine = spec.engine;
    var expressive = engine == SpeechEngineKind.expressive;
    var local = engine == SpeechEngineKind.local;
    var download = _downloadOf(engine);
    // The expressive voices are built for some computers only.
    var unmade = expressive && !qwenSupported;
    // Our own voices, until downloaded: the download in place of the list,
    // and nothing to speak with.
    var needsVoices = unmade || download.ready != true;
    var picked = spec.voice.isEmpty
        ? switch (engine) {
            SpeechEngineKind.local => kokoroVoices.first.id,
            SpeechEngineKind.expressive => qwenVoices.first.id,
          }
        : spec.voice;
    var lines = _linesOf(spec);
    if (_line >= lines.length) _line = lines.isEmpty ? 0 : lines.length - 1;
    var line = lines.isEmpty ? null : lines[_line];
    if (!_ownFocus.hasFocus && _own.text != (line?.own ?? "")) {
      _own.text = line?.own ?? "";
    }
    var asText = _asText ?? lines.isEmpty;
    var queue = c.speechQueue[widget.channel];
    var joining = c.joining.contains(widget.channel);
    var busy = queue != null || joining;
    var spoken = lines.where((l) => l.take != null).length;
    var cantSpeak = needsVoices || lines.isEmpty;
    var allSpoken = lines.isNotEmpty && lines.every((l) => l.takes.isNotEmpty);
    var reading = spec.document.on;
    // Phrasing, in place of the sections, on the section and slot picked.
    var phrasingOn = c.phrasing?.channel == widget.channel;
    var pickedSlot =
        (_slot ?? (line == null || line.chosen < 0 ? 0 : line.chosen))
            .clamp(0, SpeechLine.speechSlots - 1);
    if (phrasingOn &&
        line != null &&
        (c.phrasing!.line != _line || c.phrasing!.slot != pickedSlot)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.phrasing?.channel == widget.channel) {
          c.openPhrasing(widget.channel, _line, pickedSlot);
        }
      });
    }
    return _SpeechView(
      spec: spec,
      k: k,
      s: s,
      skin: skin,
      engine: engine,
      expressive: expressive,
      local: local,
      download: download,
      unmade: unmade,
      needsVoices: needsVoices,
      picked: picked,
      lines: lines,
      line: line,
      asText: asText,
      queue: queue,
      busy: busy,
      spoken: spoken,
      cantSpeak: cantSpeak,
      allSpoken: allSpoken,
      reading: reading,
      phrasingOn: phrasingOn,
      pickedSlot: pickedSlot,
    );
  }

  void _takeOff() {
    c.beginInteraction();
    c.setSpeech(widget.channel, null);
    c.endInteraction();
  }
}

/// VocaliserDevice is channel [channel]'s Vocaliser: the MIDI channel whose
/// notes it sings, how it sings them, and Sing, which sings the channel's
/// latest Speech take into a new clip.
class VocaliserDevice extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const VocaliserDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  State<VocaliserDevice> createState() => _VocaliserDeviceState();
}

class _VocaliserDeviceState extends State<VocaliserDevice> {
  CanvasController get c => widget.controller;
  String? _problem;

  void _set(VocaliserSpec spec, {bool transient = false}) =>
      c.setVocaliser(widget.channel, spec, transient: transient);

  Future<void> _sing() async {
    setState(() => _problem = null);
    var problem = await c.sing(widget.channel);
    if (mounted) setState(() => _problem = problem);
  }

  @override
  Widget build(BuildContext context) {
    var spec = c.vocaliserOf(widget.channel);
    if (spec == null) return const SizedBox();
    var look = MixerLook.of(context);
    var studio = look.studio;
    var tunes = c.midiChannels;
    var melody = tunes.any((t) => t.$1 == spec.melody)
        ? spec.melody
        : tunes.firstOrNull?.$1;
    var sings = c.singsWhat(widget.channel);
    var busy = c.singing.contains(widget.channel);
    var notes = melody == null
        ? const <MidiNote>[]
        : c.instrumentOf(melody)?.instrument?.notes ?? const <MidiNote>[];
    var muted = TextStyle(fontSize: 10, color: studio.muted);
    Widget knob(
            DeviceTier tier,
            String key,
            String label,
            String text,
            double value,
            double initial,
            double max,
            VocaliserSpec Function(double) change) =>
        DeviceKnob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value,
          initial: initial,
          min: 0,
          max: max,
          size: switch (tier) {
            DeviceTier.large => 46,
            DeviceTier.medium => 38,
            _ => 28,
          },
          accent: voiceColour,
          ink: studio.text,
          onChanged: (v, {transient = false}) {
            c.beginInteraction();
            _set(change(v), transient: true);
            if (!transient) c.endInteraction();
          },
          onCommit: c.endInteraction,
        );
    return DeviceFrame(
      id: "vocaliser",
      title: "Vocaliser",
      help: "Sings this channel's Speech to a MIDI channel's notes: each "
          "word on its note, with a vibrato and a glide between. Sing makes "
          "it a new clip, where the tune starts.",
      skin: DeviceSkin.studio(studio),
      icon: Icons.music_note,
      accent: voiceColour,
      // Its vibrato and glide compared A|B, or reset; the tune kept.
      onAB: () => c.toggleABOf("${widget.channel}|vocaliser", spec, (o) {
        var other = o as VocaliserSpec;
        _set(other.copyWith(melody: spec.melody), transient: true);
      }),
      showingB: c.showingBOf("${widget.channel}|vocaliser"),
      onReset: () {
        c.beginInteraction();
        _set(VocaliserSpec(melody: spec.melody), transient: true);
        c.endInteraction();
      },
      folded: widget.folded,
      onFold: widget.onFold,
      width: 340,
      height: widget.height,
      actions: [
        IconButton(
          key: const ValueKey("vocaliserRemove"),
          tooltip: "Take the Vocaliser off. What it sang stays on the "
              "timeline.",
          icon: const Icon(Icons.close),
          onPressed: () {
            c.beginInteraction();
            c.setVocaliser(widget.channel, null);
            c.endInteraction();
          },
        ),
      ],
      summary: melody == null
          ? "No MIDI channel to sing"
          : "Sings ${tunes.firstWhere((t) => t.$1 == melody).$2}",
      foldedBody: const SizedBox(),
      // The tune it sings: the notes, with vibrato and glide between them.
      display: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey("vocaliserMelodyLine"),
            painter: _MelodyPainter(notes,
                vibrato: spec.vibrato,
                glide: spec.glide,
                accent: voiceColour,
                back: studio.display,
                line: studio.edge),
          ),
        ),
        Positioned(
          left: 6,
          top: 4,
          right: 6,
          child: IgnorePointer(
            child: Text(
                _problem ??
                    sings ??
                    "Sings this channel's Speech: speak a take first",
                key: const ValueKey("vocaliserStatus"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _problem != null
                    ? const TextStyle(fontSize: 10, color: Color(0xFFFF8A80))
                    : muted),
          ),
        ),
        // Sing, on the tune it sings: always in reach, whatever the height.
        Positioned(
          right: 6,
          bottom: 6,
          child: FilledButton.icon(
            key: const ValueKey("vocaliserSing"),
            style: FilledButton.styleFrom(
                backgroundColor: voiceColour,
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: busy || sings == null || melody == null ? null : _sing,
            icon: busy
                ? const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.music_note, size: 16),
            label: Text(busy ? "Singing…" : "Sing"),
          ),
        ),
      ]),
      controls: (tier) => [
        knob(
            tier,
            "vocaliserVibrato",
            "Vibrato",
            "${(spec.vibrato * 100).round()}%",
            spec.vibrato,
            0.3,
            1,
            (v) => spec.copyWith(vibrato: v)),
        knob(
            tier,
            "vocaliserGlide",
            "Glide",
            "${(spec.glide * 1000).round()} ms",
            spec.glide,
            0.06,
            0.5,
            (v) => spec.copyWith(glide: v)),
        SizedBox(
          width: 170,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Sings the notes of", style: muted),
                const SizedBox(height: 3),
                tunes.isEmpty
                    ? Text("No MIDI channel yet",
                        key: const ValueKey("vocaliserMelody"), style: muted)
                    : DeviceChoices(options: [
                        for (var (key, name) in tunes)
                          (
                            ValueKey("vocaliserMelody-$key"),
                            name,
                            key == melody,
                            () => _set(spec.copyWith(melody: key)),
                          ),
                      ]),
              ]),
        ),
      ],
      body: const SizedBox(),
    );
  }
}

/// _MelodyPainter draws the tune a Vocaliser sings: each note a line at its
/// pitch, swinging by the vibrato, sliding in from the last by the glide.
class _MelodyPainter extends CustomPainter {
  final List<MidiNote> notes;
  final double vibrato, glide;
  final Color accent, back, line;
  _MelodyPainter(this.notes,
      {required this.vibrato,
      required this.glide,
      required this.accent,
      required this.back,
      required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
        Paint()..color = back);
    if (notes.isEmpty) return;
    var sorted = [...notes]..sort((a, b) => a.start.compareTo(b.start));
    var end = sorted.map((n) => n.end).reduce(math.max);
    var low = sorted.map((n) => n.key).reduce(math.min) - 2;
    var high = sorted.map((n) => n.key).reduce(math.max) + 2;
    if (end <= 0) return;
    double x(double t) => 6 + (size.width - 12) * t / end;
    double y(double key) =>
        8 + (size.height - 30) * (high - key) / math.max(1, high - low);
    var path = Path();
    double? lastKey;
    for (var n in sorted) {
      var from = lastKey ?? n.key.toDouble();
      // Slides in from the last note over the glide, then holds with vibrato.
      var slide = math.min(glide, n.length / 2);
      path.moveTo(x(n.start), y(from));
      path.lineTo(x(n.start + slide), y(n.key.toDouble()));
      for (var t = n.start + slide; t < n.end; t += end / 400) {
        var swing = vibrato * 0.5 * math.sin((t - n.start) * 2 * math.pi * 5.5);
        path.lineTo(x(t), y(n.key + swing));
      }
      lastKey = n.key.toDouble();
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_MelodyPainter old) =>
      !identical(old.notes, notes) ||
      old.vibrato != vibrato ||
      old.glide != glide ||
      old.accent != accent;
}

/// voiceColour is a voice channel's colour.
const voiceColour = Color(0xFFC45C8A);

/// SpeechCard is a voice channel's generator in its chain, as the
/// Instrument card is a MIDI channel's: Speech is chosen for a channel (the
/// Add menu's Generators), not on every one. It shows a section's take
/// (its sound, words and play position), its feel as knobs, its voice as a
/// list, and Speak all with the take count. Its editor is the Speech tab.
class SpeechCard extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final DeviceSkin skin;

  const SpeechCard({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    required this.skin,
    super.key,
  });

  @override
  State<SpeechCard> createState() => _SpeechCardState();
}

class _SpeechCardState extends State<SpeechCard> {
  /// _line is the section stepped to, shown on the screen; null for the
  /// first spoken.
  int? _line;

  CanvasController get c => widget.controller;

  /// _write changes the Speech: one undo step, or with [transient] part of a
  /// knob's turn.
  void _write(SpeechSpec next, {bool transient = false}) {
    c.beginInteraction();
    c.setSpeech(widget.channel, next, transient: true);
    if (!transient) c.endInteraction();
  }

  Future<void> _speakAll() async {
    var problem = await c.speakLines(widget.channel);
    if (problem == null || !mounted) return;
    try {
      SnackBarModel.of(context).error(problem);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    var spec = c.speechOf(widget.channel);
    var look = MixerLook.of(context);
    var studio = look.studio;
    if (spec == null) return const SizedBox();
    var k = SpeechKit(studio, look.colors);
    var lines = spec.shownLines;
    var written = lines.where((l) => l.text.trim().isNotEmpty).length;
    var takes = lines.fold(0, (n, l) => n + l.takes.length);
    var engine = spec.engine;
    var expressive = engine == SpeechEngineKind.expressive;
    var voices = expressive ? qwenVoices : kokoroVoices;
    var voiceId =
        voices.any((v) => v.id == spec.voice) ? spec.voice : voices.first.id;
    var voiceName = voices.firstWhere((v) => v.id == voiceId).name;
    // The section shown: the one stepped to, or the first spoken.
    var spoken = [
      for (var (i, l) in lines.indexed)
        if (l.take != null) i
    ];
    if ((_line ?? 0) >= lines.length) _line = null;
    var shownLine = lines.isEmpty ? null : _line ?? spoken.firstOrNull ?? 0;
    var take = shownLine == null ? null : lines[shownLine].take;
    var (lowSpeed, highSpeed) = switch (engine) {
      SpeechEngineKind.local => (0.5, 2.0),
      SpeechEngineKind.expressive => (0.7, 1.3),
    };
    var busy = c.speechQueue[widget.channel] != null ||
        c.joining.contains(widget.channel);

    Widget knob(
            String id,
            String label,
            String text,
            double value,
            double initial,
            double min,
            double max,
            SpeechSpec Function(double v) change) =>
        DeviceKnob(
          key: ValueKey("speechCard-$id"),
          label: label,
          text: text,
          value: value.clamp(min, max),
          initial: initial,
          min: min,
          max: max,
          accent: voiceColour,
          ink: widget.skin.ink,
          onChanged: (v, {transient = false}) => _write(
              change(v).copyWith(preset: "custom"),
              transient: transient),
          onCommit: c.endInteraction,
        );

    // Its voice: one list of every voice, by engine.
    var voiceRow = SizedBox(
      width: 300,
      child: Row(children: [
        SizedBox(width: 40, child: k.label("Voice")),
        Expanded(
          child: k.dropdown<String>(
            key: const ValueKey("speechCardVoice"),
            value: "${engine.name}|$voiceId",
            items: [
              for (var (e, list) in [
                (SpeechEngineKind.local, kokoroVoices),
                (SpeechEngineKind.expressive, qwenVoices),
              ])
                for (var v in list)
                  ("${e.name}|${v.id}", "${e.label} · ${v.name}"),
            ],
            onChanged: (v) {
              var (name, id) = (v.split("|").first, v.split("|").last);
              var e = SpeechEngineKind.values.firstWhere((x) => x.name == name);
              var list =
                  e == SpeechEngineKind.expressive ? qwenVoices : kokoroVoices;
              var picked = list.firstWhere((x) => x.id == id);
              _write(spec.copyWith(
                  engine: e, voice: picked.id, voiceName: picked.name));
            },
          ),
        ),
        const SizedBox(width: 6),
        // Speaker boost: on or off, so a switch, not a knob.
        SizedBox(
          width: 74,
          child: DeviceChoices(options: [
            (
              const ValueKey("speechCardBoost"),
              "Boost",
              spec.boost,
              () => _write(spec.copyWith(boost: !spec.boost, preset: "custom")),
            ),
          ]),
        ),
      ]),
    );

    return DeviceFrame(
      id: "speechCard",
      title: "Speech",
      help: "Speaks a script: each section spoken is a take, and the takes "
          "are clips on this channel. Write the script and shape its "
          "words in the Speech tab.",
      skin: widget.skin,
      icon: Icons.record_voice_over,
      accent: voiceColour,
      glows: true,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 340,
      height: widget.height,
      actions: [
        IconButton(
          key: const ValueKey("speechEdit"),
          tooltip: "Open the script",
          icon: const Icon(Icons.open_in_new),
          onPressed: () => c.showSpeech(widget.channel),
        ),
        IconButton(
          key: const ValueKey("speechRemove"),
          tooltip: "Take the speech off: what it spoke stays on the timeline",
          icon: const Icon(Icons.close),
          onPressed: () {
            c.beginInteraction();
            c.setVocaliser(widget.channel, null);
            c.setSpeech(widget.channel, null);
            c.endInteraction();
          },
        ),
      ],
      summary: "$written section${written == 1 ? "" : "s"} · $voiceName",
      foldedBody: const SizedBox(),
      display: _SpeechTakeScreen(
        controller: c,
        onOpen: () => c.showSpeech(widget.channel),
        take: take,
        caption: shownLine == null
            ? null
            : "Section ${shownLine + 1} · $voiceName"
                "${take == null ? "" : ", take ${String.fromCharCode(65 + lines[shownLine].chosen)}"}",
        empty: lines.isEmpty
            ? "No script yet: open it to write one"
            : "Not spoken yet: “${lines[shownLine!].text.trim()}”",
        step: lines.length < 2
            ? null
            : (
                "${(shownLine ?? 0) + 1}/${lines.length}",
                () => setState(() => _line =
                    ((shownLine ?? 0) - 1 + lines.length) % lines.length),
                () => setState(
                    () => _line = ((shownLine ?? 0) + 1) % lines.length),
              ),
      ),
      controls: (tier) => [
        knob("speed", "Speed", "${spec.speed.toStringAsFixed(2)}×", spec.speed,
            1, lowSpeed, highSpeed, (v) => spec.copyWith(speed: v)),
        // Steadiness and expression move the expressive voices only.
        if (expressive) ...[
          knob(
              "steadiness",
              "Steadiness",
              "${(spec.steadiness * 100).round()}%",
              spec.steadiness,
              0.45,
              0,
              1,
              (v) => spec.copyWith(steadiness: v)),
          knob(
              "expression",
              "Expression",
              "${(spec.expression * 100).round()}%",
              spec.expression,
              0.6,
              0,
              1,
              (v) => spec.copyWith(expression: v)),
        ],
        knob(
            "room",
            "Room",
            spec.room < 0.05 ? "dry" : "${(spec.room * 100).round()}%",
            spec.room,
            0,
            0,
            1,
            (v) => spec.copyWith(room: v)),
        if (tier != DeviceTier.small) voiceRow,
      ],
      footer: [
        k.button(busy ? "Speaking…" : "Speak all",
            busy || written == 0 ? null : _speakAll,
            key: const ValueKey("speechCardSpeakAll"),
            icon: Icons.record_voice_over,
            small: true,
            tip: "Speak every section that has no take yet"),
        const Spacer(),
        Text("Takes: $takes",
            key: const ValueKey("speechCardTakes"),
            style: k.text(10.5, colour: studio.muted)),
      ],
      body: const SizedBox(),
    );
  }
}

/// _SpeechTakeScreen is the Speech card's screen: [take]'s sound, its words
/// over it where said, a playhead and play button, and [step], if given,
/// to step through the sections.
class _SpeechTakeScreen extends StatefulWidget {
  final CanvasController controller;
  final SpeechTake? take;
  final String? caption;
  final String empty;
  final (String, VoidCallback, VoidCallback)? step;

  /// onOpen opens the script when the screen is double-clicked.
  final VoidCallback onOpen;
  const _SpeechTakeScreen(
      {required this.controller,
      required this.onOpen,
      required this.take,
      required this.caption,
      required this.empty,
      required this.step});

  @override
  State<_SpeechTakeScreen> createState() => _SpeechTakeScreenState();
}

class _SpeechTakeScreenState extends State<_SpeechTakeScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var c = widget.controller;
    var studio = MixerLook.of(context).studio;
    var take = widget.take;
    var heard = take != null && c.speechHeard == take.assetId;
    // Moving only while it is heard.
    if (heard != _ticker.isActive) heard ? _ticker.start() : _ticker.stop();
    var muted = TextStyle(fontSize: 10, color: studio.muted);
    Widget small(IconData icon, Key key, VoidCallback onTap) => InkWell(
          key: key,
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 14, color: studio.muted),
          ),
        );
    return Container(
      color: studio.display,
      child: LayoutBuilder(builder: (context, box) {
        var w = box.maxWidth, h = box.maxHeight;
        var at = heard ? c.heardSeconds : null;
        var length = take == null || take.length <= 0 ? 1.0 : take.length;
        var wordH = MediaQuery.textScalerOf(context).scale(10) + 4;
        // The words drawn only where there is room under the caption.
        var wordsShown = take != null && h >= 60;
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey("speechCardScript"),
              behavior: HitTestBehavior.opaque,
              onDoubleTap: widget.onOpen,
            ),
          ),
          if (take == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(widget.empty,
                    textAlign: TextAlign.center, style: muted),
              ),
            )
          else
            Positioned.fill(
              child: IgnorePointer(
                  child: CustomPaint(
                painter: _TakeWave(
                    peaks: c.waveformOf(take.assetId),
                    words: take.words,
                    length: length,
                    playhead: at == null ? null : at / length,
                    top: wordsShown ? 18 + wordH : 18,
                    ink: voiceColour,
                    faint: studio.edge),
              )),
            ),
          if (wordsShown)
            for (var word in take.words)
              Positioned(
                left: word.start / length * w + 2,
                top: 18,
                width: math.max(0.0, (word.end - word.start) / length * w),
                child: Text(word.text,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(fontSize: 10, color: studio.text)),
              ),
          if (widget.caption case var caption?)
            Positioned(
              left: 6,
              top: 3,
              right: widget.step == null ? 6 : 70,
              child: Text(caption,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            ),
          if (widget.step case (var where, var back, var on))
            Positioned(
              right: 2,
              top: 1,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                small(
                    Icons.chevron_left, const ValueKey("speechCardPrev"), back),
                Text(where, style: muted),
                small(
                    Icons.chevron_right, const ValueKey("speechCardNext"), on),
              ]),
            ),
          if (take != null)
            Positioned(
              left: 3,
              bottom: 3,
              child: small(heard ? Icons.stop : Icons.play_arrow,
                  const ValueKey("speechCardHear"), () async {
                await c.hearTake(take.assetId);
              }),
            ),
        ]);
      }),
    );
  }
}

/// _TakeWave draws a take's sound under [top], each word's span lit
/// faintly, and the playhead.
class _TakeWave extends CustomPainter {
  final Float32List? peaks;
  final List<TimedWord> words;
  final double length;
  final double? playhead;
  final double top;
  final Color ink, faint;
  _TakeWave(
      {required this.peaks,
      required this.words,
      required this.length,
      required this.playhead,
      required this.top,
      required this.ink,
      required this.faint});

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width;
    var bottom = size.height - 4;
    var mid = (top + bottom) / 2, half = math.max(1.0, (bottom - top) / 2);
    for (var word in words) {
      canvas.drawRect(
          Rect.fromLTRB(
              word.start / length * w, top - 1, word.end / length * w, bottom),
          Paint()..color = ink.withValues(alpha: 0.08));
    }
    var p = peaks;
    var bar = Paint()
      ..color = ink.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    if (p == null || p.isEmpty) {
      canvas.drawLine(Offset(0, mid), Offset(w, mid), Paint()..color = faint);
    } else {
      for (var x = 0.0; x < w; x += 2) {
        var i = (x / w * p.length).floor().clamp(0, p.length - 1);
        var a = math.max(0.5, p[i] * half);
        canvas.drawLine(Offset(x, mid - a), Offset(x, mid + a), bar);
      }
    }
    if (playhead case var at?) {
      var x = at.clamp(0.0, 1.0) * w;
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height),
          Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  @override
  bool shouldRepaint(_TakeWave old) =>
      old.peaks != peaks ||
      old.words != words ||
      old.length != length ||
      old.playhead != playhead ||
      old.top != top ||
      old.ink != ink;
}
