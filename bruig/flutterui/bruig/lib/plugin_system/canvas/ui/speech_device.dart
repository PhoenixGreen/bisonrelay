import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/qwen_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_downloads.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/media/speech_finish.dart'
    show lineGap;
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart'
    show TextDocumentRef;
import 'package:bruig/plugin_system/canvas/ui/document_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/text_documents.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// speech_device.dart is the Speech device in a channel's chain: the engine
// and the voice; the script, line by line, each with how it is said and its
// takes; the voice's feel; and Speak all -- which speaks the lines, one at
// a time in the background, and joins the takes chosen into a clip on the
// channel. See speech_spec.dart for what it keeps, and speech_engines.dart
// for how it speaks.

const _problemInk = Color(0xFFFF8A80);

/// _cueIcons are the cues' icons. Not emoji: Impeller draws an emoji into
/// its glyph atlas slowly, and redraws them all whenever the atlas is made
/// again -- seconds a frame, with the device open.
const _cueIcons = {
  SpeechCue.pause: Icons.pause,
  SpeechCue.breath: Icons.air,
  SpeechCue.laugh: Icons.sentiment_very_satisfied,
  SpeechCue.sigh: Icons.sentiment_dissatisfied,
  SpeechCue.cough: Icons.sick_outlined,
  SpeechCue.whisper: Icons.volume_down,
  SpeechCue.stress: Icons.priority_high,
  SpeechCue.slow: Icons.slow_motion_video,
};

/// _Kit is what the Speech device is drawn with: the studio palette's
/// text, boxes, buttons, chips and dropdowns, each the same everywhere in
/// it.
class _Kit {
  final StudioColors s;
  final ColorScheme scheme;
  const _Kit(this.s, this.scheme);

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

  /// label names a part of the device.
  Widget label(String t) => Text(t,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text(11, colour: s.muted));

  /// section heads a group of settings.
  Widget section(String t) => Text(t.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text(9.5, weight: FontWeight.w700, colour: s.muted)
          .copyWith(letterSpacing: 0.6));

  BoxDecoration box(Color fill, {Color? border}) => BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: border ?? s.edge));

  InputDecoration field(String hint) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: s.inset,
        hintText: hint,
        hintMaxLines: 4,
        hintStyle: text(11, colour: s.muted.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: s.edge)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: s.solo)),
      );

  /// button is a plain button: a raised box, its icon and words.
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

  /// chip is a rounded choice: lit blue when it is the one chosen.
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

  /// take is one of a line's takes, by its letter: lit when it is the one
  /// in the clip.
  Widget take(String letter, bool on, VoidCallback? onTap, {Key? key}) =>
      Material(
        color: on ? s.on : s.inset,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: on ? s.on : s.edge)),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 22,
            child: Center(
              child: Text(letter,
                  style: text(11,
                      weight: FontWeight.w700, colour: on ? s.onOn : s.text)),
            ),
          ),
        ),
      );

  /// dropdown is a choice of [items] -- each its value and words -- in a
  /// box like the device's fields.
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

/// SpeechDevice is channel [channel]'s Speech device.
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
    super.key,
  });

  @override
  State<SpeechDevice> createState() => _SpeechDeviceState();
}

class _SpeechDeviceState extends State<SpeechDevice> {
  CanvasController get c => widget.controller;
  final TextEditingController _script = TextEditingController();
  final FocusNode _scriptFocus = FocusNode();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _own = TextEditingController();
  final FocusNode _ownFocus = FocusNode();

  /// _voices are the engine's voices, asked for once for each engine (and
  /// key), and _voicesFor what they were asked for.
  Future<List<SpeechVoice>>? _voices;
  String _voicesFor = "";
  String _filter = "";

  /// _accent is the accent the voice list is narrowed to -- the start of a
  /// voice's description, "UK", "US" -- or "" for all.
  String _accent = "";

  /// _missing is how much of the voices is still to download, for each
  /// download.
  final Map<PinnedDownload, Future<int>> _missing = {};
  String? _problem;

  /// _asText is whether the script is shown as text to edit rather than as
  /// lines: null until chosen, when it is text for a device with nothing
  /// written yet.
  bool? _asText;

  /// _line is the line picked in the list.
  int _line = 0;

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
    _key.dispose();
    _own.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  /// _cloudKey is the reader's ElevenLabs key, where the preferences are
  /// to hand: a test may put the device up without them.
  String get _cloudKey {
    try {
      return context.read<CanvasPreferences>().elevenLabsKey;
    } catch (_) {
      return "";
    }
  }

  void _set(SpeechSpec spec, {bool transient = false}) =>
      c.setSpeech(widget.channel, spec, transient: transient);

  Future<List<SpeechVoice>> _voicesOf(SpeechSpec spec) {
    var asked = "${spec.engine.name}:${_cloudKey.isNotEmpty}";
    if (_voices == null || asked != _voicesFor) {
      _voicesFor = asked;
      _voices = CanvasController.speechEngineFor(spec, _cloudKey)
          .voices()
          .catchError((Object e) => <SpeechVoice>[]);
    }
    return _voices!;
  }

  /// _download is the engine's download: our two sets of voices each have
  /// one; ElevenLabs none.
  PinnedDownload? _downloadOf(SpeechEngineKind engine) => switch (engine) {
        SpeechEngineKind.local => KokoroDownload.instance,
        SpeechEngineKind.expressive => QwenDownload.instance,
        SpeechEngineKind.cloud => null,
      };

  /// _cue puts [cue] into the script where the text cursor is.
  void _cue(SpeechSpec spec, SpeechCue cue) {
    var text = _script.text;
    var sel = _script.selection;
    var at = sel.isValid ? sel.start : text.length;
    var before = text.substring(0, at);
    var token =
        "${before.isEmpty || before.endsWith(" ") ? "" : " "}${cue.token} ";
    var next = before + token + text.substring(sel.isValid ? sel.end : at);
    _script.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: at + token.length));
    _set(spec.withScript(next));
  }

  Future<void> _run(Future<String?> Function() job) async {
    setState(() => _problem = null);
    var problem = await job();
    if (mounted) setState(() => _problem = problem);
  }

  void _speakAll() =>
      _run(() => c.speakLines(widget.channel, cloudKey: _cloudKey));

  /// _lines are the device's lines, set out from its script where it has
  /// none of its own yet.
  List<SpeechLine> _linesOf(SpeechSpec spec) => spec.shownLines;

  /// _changeLine changes line [index] -- its direction, or its own words --
  /// and, where it has been spoken, speaks it again that way: a new take,
  /// the others kept to compare -- see CanvasController.withTake.
  void _changeLine(SpeechSpec spec, int index, SpeechLine changed) {
    var lines = [..._linesOf(spec)];
    if (index >= lines.length) return;
    var was = lines[index];
    lines[index] = changed;
    c.setSpeechLines(widget.channel, lines);
    if (was.takes.isNotEmpty &&
        (was.direction != changed.direction || was.own != changed.own)) {
      _run(() => c.anotherTake(widget.channel, changed, cloudKey: _cloudKey));
    }
  }

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

  /// _downloadPanel is in place of the voice list until the engine's
  /// voices are here: how big they are, and the button to fetch them -- or
  /// how far they have got.
  Widget _downloadPanel(
      PinnedDownload voices, SpeechEngineKind engine, _Kit k) {
    var expressive = engine == SpeechEngineKind.expressive;
    var whole = expressive ? qwenBytes : kokoroBytes;
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: k.box(k.s.solo.withValues(alpha: 0.10),
            border: k.s.solo.withValues(alpha: 0.45)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FutureBuilder<int>(
            future: _missing[voices] ??=
                voices.missingBytes().catchError((_) => whole),
            builder: (context, snap) {
              var missing = snap.data ?? whole;
              var some = missing < whole;
              var size = missing >= 1e9
                  ? "${(missing / 1e9).toStringAsFixed(1)} GB"
                  : "${(missing / 1e6).round()} MB";
              return Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: expressive
                            ? "Expressive voices run on this computer. "
                            : "Built-in voices run on this computer. ",
                        style: k.text(11, weight: FontWeight.w600)),
                    TextSpan(
                        text: expressive
                            ? "${qwenVoices.length} voices, each keeping its "
                                "accent in ten languages, each line said as "
                                "you direct it. Slower than the built-in "
                                "voices, so lines are spoken in the "
                                "background. "
                                "${some ? "The rest is" : "They are"} a "
                                "one-off download of $size."
                            : "${kokoroVoices.length} voices -- British, "
                                "American and Chinese; and six more "
                                "languages where espeak-ng is installed. "
                                "${some ? "The new ones are" : "They are"} a "
                                "one-off download of $size.",
                        style: k.text(10.5, colour: k.s.muted)),
                  ]),
                  style: const TextStyle(height: 1.4));
            },
          ),
          const SizedBox(height: 8),
          if (voices.downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                  key: const ValueKey("speechDownloadProgress"),
                  minHeight: 5,
                  color: k.s.solo,
                  backgroundColor: k.s.raised,
                  value: voices.share),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: Text("${((voices.share ?? 0) * 100).round()}%",
                      style: k.text(10.5, colour: k.s.muted))),
              k.button("Stop", voices.stop,
                  key: const ValueKey("speechDownloadStop")),
            ]),
          ] else
            k.button(
                "Download",
                voices.ready == null
                    ? null
                    : () {
                        _missing.remove(voices);
                        voices.start();
                      },
                key: const ValueKey("speechDownload"),
                icon: Icons.download,
                fill: k.s.solo,
                ink: k.s.onSolo),
          if (voices.problem case var problem?) ...[
            const SizedBox(height: 4),
            Text(problem, style: k.text(10.5, colour: _problemInk)),
          ],
        ]),
      ),
    );
  }

  /// _pickDocument reads the script from a document picked in the Writing
  /// library: again, another one, the typed script still kept.
  Future<void> _pickDocument(SpeechSpec spec, {bool again = false}) async {
    var picked = await pickLibraryDocument(context);
    if (picked == null || !mounted) return;
    _set(spec.copyWith(
        document: again
            ? spec.document.copyWith(folder: picked.folder, name: picked.name)
            : picked.copyWith(wasText: spec.script)));
    await refreshTextDocuments(c);
  }

  @override
  Widget build(BuildContext context) {
    var spec = c.speechOf(widget.channel);
    if (spec == null) return const SizedBox();
    if (!_scriptFocus.hasFocus && _script.text != spec.script) {
      _script.text = spec.script;
    }
    var look = MixerLook.of(context);
    var skin = DeviceSkin.themed(look.colors);
    var k = _Kit(look.studio, look.colors);
    var s = look.studio;
    var engine = spec.engine;
    var cloud = engine == SpeechEngineKind.cloud;
    var expressive = engine == SpeechEngineKind.expressive;
    var local = engine == SpeechEngineKind.local;
    var needsKey = cloud && _cloudKey.isEmpty;
    var download = _downloadOf(engine);
    // The expressive voices are built for some computers only.
    var unmade = expressive && !qwenSupported;
    // Our own voices, until they are downloaded: the download in place of
    // the list, and nothing to speak with.
    var needsVoices = unmade || (download != null && download.ready != true);
    var picked = spec.voice.isEmpty
        ? switch (engine) {
            SpeechEngineKind.local => kokoroVoices.first.id,
            SpeechEngineKind.expressive => qwenVoices.first.id,
            SpeechEngineKind.cloud => "",
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
    var cantSpeak = needsKey || needsVoices || lines.isEmpty;
    var allSpoken = lines.isNotEmpty && spoken == lines.length;
    var reading = spec.document.on;

    // The finish changed: the clip joined again, nothing spoken again.
    void refinish() {
      if (spoken > 0 && !busy) _run(() => c.joinSpeech(widget.channel));
    }

    // A voice heard saying a line, in the device's feel: playing, it
    // stops; being spoken for it, it says so.
    Widget previewButton(String voice) {
      var heard = c.speechHeard == "voice:$voice";
      var speaking = c.speechPreviewing == voice;
      return Tooltip(
        message:
            heard ? "Stop" : "Hear it say a line, as this device's feel has it",
        child: InkWell(
          key: ValueKey("speechPreview-$voice"),
          borderRadius: BorderRadius.circular(12),
          onTap: needsVoices || (c.speechPreviewing != null && !speaking)
              ? null
              : () => _run(() =>
                  c.previewVoice(widget.channel, voice, cloudKey: _cloudKey)),
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: speaking
                  ? SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: s.muted))
                  : Icon(heard ? Icons.stop : Icons.play_arrow,
                      size: 16, color: heard ? s.on : s.muted),
            ),
          ),
        ),
      );
    }

    // ---- The voices
    var voiceColumn = FutureBuilder<List<SpeechVoice>>(
      future: _voicesOf(spec),
      builder: (context, snap) {
        var all = snap.data ?? const <SpeechVoice>[];
        var gendered = all.any((v) => v.gender.isNotEmpty);
        // Accents, where the voices have more than one: the expressive
        // ones keep theirs in every language, so are not narrowed by it.
        var accents = expressive
            ? const <String>[]
            : <String>{
                for (var v in all)
                  if (v.about.contains(" ")) v.about.split(" ").first
              }.toList();
        var shown = [
          for (var v in all)
            if ((_filter.isEmpty || v.gender == _filter) &&
                (_accent.isEmpty || v.about.startsWith("$_accent ")))
              v
        ];
        // ElevenLabs, said first, scrolled with the voices: what leaves
        // the computer, and the key.
        var notice = <Widget>[
          if (cloud) ...[
            Container(
              padding: const EdgeInsets.all(7),
              decoration: k.box(s.on.withValues(alpha: 0.10),
                  border: s.on.withValues(alpha: 0.4)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        "In the cloud: each line is sent to ElevenLabs to be "
                        "spoken, on your own account.",
                        style: k.text(10, colour: s.text)),
                    if (needsKey) ...[
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 26,
                        child: TextField(
                          key: const ValueKey("speechKey"),
                          controller: _key,
                          obscureText: true,
                          style: k.text(11),
                          decoration: k.field("Your API key"),
                          onSubmitted: (v) {
                            try {
                              context.read<CanvasPreferences>().elevenLabsKey =
                                  v;
                            } catch (_) {}
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ]),
            ),
            const SizedBox(height: 6),
          ],
        ];

        Widget list() {
          if (unmade) {
            return Text(
                "The expressive voices are made for Apple Silicon Macs and "
                "for Linux: not for this computer yet.",
                key: const ValueKey("speechUnmade"),
                style: k.text(10.5, colour: s.muted));
          }
          if (needsVoices) return _downloadPanel(download!, engine, k);
          var waiting = snap.connectionState != ConnectionState.done
              ? "Finding voices…"
              : shown.isEmpty
                  ? needsKey
                      ? "Your key, to list its voices."
                      : "No voices found."
                  : null;
          return ListView(
            key: const ValueKey("speechVoices"),
            padding: EdgeInsets.zero,
            children: [
              ...notice,
              if (waiting != null)
                Text(waiting, style: k.text(11, colour: s.muted)),
              for (var v in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: v.id == picked
                        ? s.solo.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      key: ValueKey("speechVoice-${v.id}"),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () =>
                          _set(spec.copyWith(voice: v.id, voiceName: v.name)),
                      child: Padding(
                        padding: const EdgeInsets.only(
                            left: 7, right: 2, top: 4, bottom: 4),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: k.text(12,
                                          weight: FontWeight.w600,
                                          colour: v.id == picked
                                              ? s.text
                                              : s.text.withValues(alpha: 0.9))),
                                  if (v.about.isNotEmpty)
                                    Text(v.about,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: k.text(10, colour: s.muted)),
                                ]),
                          ),
                          // Heard before it is picked: our own voices only,
                          // as a preview from ElevenLabs costs the reader.
                          if (!cloud) previewButton(v.id),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              k.label("Voice"),
              const SizedBox(height: 4),
              if (expressive && !needsVoices) ...[
                k.dropdown<String>(
                  key: const ValueKey("speechLanguage"),
                  value: qwenLanguages.contains(spec.language)
                      ? spec.language
                      : qwenLanguages.first,
                  items: [for (var l in qwenLanguages) (l, l)],
                  onChanged: (v) =>
                      _set(spec.copyWith(language: v == "English" ? "" : v)),
                ),
                const SizedBox(height: 5),
              ],
              // One line, scrolled sideways where the text is too large for
              // it: wrapped, it took the list's room.
              if (gendered && all.length > 2 && !needsVoices)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var (g, label) in const [
                      ("", "All"),
                      ("f", "Women"),
                      ("m", "Men")
                    ])
                      k.chip(label, _filter == g,
                          () => setState(() => _filter = g),
                          key: ValueKey("speechFilter-$g")),
                  ]),
                ),
              if (accents.length > 1 && !needsVoices) ...[
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var a in ["", ...accents])
                      k.chip(a.isEmpty ? "Any" : a, _accent == a,
                          () => setState(() => _accent = a),
                          key: ValueKey("speechAccent-$a")),
                  ]),
                ),
              ],
              const SizedBox(height: 5),
              Expanded(child: list()),
            ]);
      },
    );

    // ---- The script, as text
    var scriptText =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: TextField(
          key: const ValueKey("speechScript"),
          controller: _script,
          focusNode: _scriptFocus,
          // Read from a document: changed there.
          readOnly: reading,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: k.text(12.5, height: 1.5),
          decoration: k.field(
              "What is to be said, a line to each sentence. A direction "
              "goes first, in [brackets]: [warm], [sad]… and cues anywhere: "
              "[pause 0.5], [laugh]."),
          onChanged: (v) {
            _asText ??= true;
            c.beginInteraction();
            _set(spec.withScript(v), transient: true);
          },
        ),
      ),
      const SizedBox(height: 5),
      // One row, scrolled sideways where it is too long for the column.
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var cue in engine.cues)
            Tooltip(
              message: "Put in ${cue.token}",
              child: k.chip(cue.label, false, () => _cue(spec, cue),
                  key: ValueKey("speechCue-${cue.name}"), icon: _cueIcons[cue]),
            ),
        ]),
      ),
    ]);

    // ---- The script, line by line
    String lineState(SpeechLine l) {
      switch (c.speechLineState(widget.channel, l)) {
        case "speaking":
          return "Speaking…";
        case "waiting":
          return "Waiting";
      }
      var t = l.take;
      if (t == null) return needsVoices ? "" : "Not spoken yet";
      return "${t.length.toStringAsFixed(1)} s";
    }

    Widget lineCard(int i, SpeechLine l) {
      var on = i == _line;
      var state = c.speechLineState(widget.channel, l);
      var direction = l.own.isNotEmpty
          ? "“${l.own}”"
          : l.direction == SpeechDirection.plain
              ? ""
              : l.direction.label;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? s.solo.withValues(alpha: 0.14) : s.strip,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: BorderSide(
                  color: on ? s.solo : s.edge.withValues(alpha: 0.6))),
          child: InkWell(
            key: ValueKey("speechLine-$i"),
            borderRadius: BorderRadius.circular(5),
            onTap: () => setState(() => _line = i),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
              child: Row(children: [
                SizedBox(
                  width: 18,
                  child: Text("${i + 1}", style: k.mono(10, colour: s.muted)),
                ),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: k.text(12.5)),
                        const SizedBox(height: 3),
                        Row(children: [
                          if (direction.isNotEmpty) ...[
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(
                                    color: s.on.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(9)),
                                child: Text(direction,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: k.text(10, colour: s.on)),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(lineState(l),
                              style: k.text(10,
                                  colour:
                                      state == "speaking" ? s.on : s.muted)),
                        ]),
                      ]),
                ),
                // The takes, A to C: the one chosen is in the clip.
                for (var (t, _) in l.takes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: k.take(
                        String.fromCharCode(65 + t),
                        t == l.chosen,
                        busy
                            ? null
                            : () =>
                                _run(() => c.chooseTake(widget.channel, i, t)),
                        key: ValueKey("speechTake-$i-$t")),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    var scriptLines = lines.isEmpty
        ? Center(
            child: Text("No lines yet: Edit as text, and write the script.",
                style: k.text(11, colour: s.muted)))
        : ListView(
            key: const ValueKey("speechLines"),
            padding: EdgeInsets.zero,
            children: [for (var (i, l) in lines.indexed) lineCard(i, l)],
          );

    // Where the script comes from: typed here, or a Writing document.
    var fromItems = <(String, String)>[
      ("typed", "Typed here"),
      if (reading) ("document", spec.document.says),
      ("pick", reading ? "Another document…" : "A Writing document…"),
    ];
    var scriptColumn =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: k.label(asText ? "Script" : "Lines")),
        // Narrowed, rather than overflowing, where the column is narrow.
        Flexible(
          flex: 2,
          child: k.button(asText ? "Show as lines" : "Edit as text", () {
            _scriptFocus.unfocus();
            setState(() => _asText = !asText);
          }, key: const ValueKey("speechAsText"), small: true),
        ),
        const SizedBox(width: 8),
        Flexible(child: k.label("From")),
        const SizedBox(width: 5),
        Flexible(
          flex: 3,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: k.dropdown<String>(
              key: const ValueKey("speechFromDocument"),
              value: reading ? "document" : "typed",
              items: fromItems,
              itemKeys: {
                if (reading) "document": const ValueKey("speechDocument")
              },
              onChanged: (v) {
                if (v == "typed" && reading) {
                  // What was typed before, given back.
                  _set(spec
                      .withScript(spec.document.wasText)
                      .copyWith(document: const TextDocumentRef()));
                } else if (v == "pick") {
                  _pickDocument(spec, again: reading);
                }
              },
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Expanded(child: asText ? scriptText : scriptLines),
    ]);

    // ---- The line picked, and Speak all
    Widget linePanel() {
      var l = line;
      var full =
          l != null && l.takes.length >= CanvasController.speechTakesMost;
      var ready = !cantSpeak && !busy;
      var editable = l != null && !reading;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: l == null
              ? Text("Pick a line to direct it.",
                  style: k.text(11, colour: s.muted))
              : SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: k
                                  .label("Line ${_line + 1} · how it is said")),
                          // Each take heard on its own, to choose between.
                          for (var (t, take) in l.takes.indexed)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: k.chip(
                                  String.fromCharCode(65 + t),
                                  c.speechHeard == take.assetId,
                                  () => _run(() => c.hearTake(take.assetId)),
                                  key: ValueKey("speechHear-$t"),
                                  icon: c.speechHeard == take.assetId
                                      ? Icons.stop
                                      : Icons.play_arrow),
                            ),
                        ]),
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          // Those the engine cannot say greyed, and why.
                          for (var d in SpeechDirection.values)
                            Tooltip(
                              message: engine.directs(d)
                                  ? ""
                                  : "Not on Built in: pick Expressive",
                              child: k.chip(
                                  d.label,
                                  l.own.isEmpty && l.direction == d,
                                  editable && engine.directs(d)
                                      ? () => _changeLine(spec, _line,
                                          l.copyWith(direction: d, own: ""))
                                      : null,
                                  key: ValueKey("speechDirection-${d.name}")),
                            ),
                        ]),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 28,
                          child: TextField(
                            key: const ValueKey("speechOwn"),
                            controller: _own,
                            focusNode: _ownFocus,
                            readOnly: reading,
                            style: k.text(11.5),
                            decoration: k.field(local
                                ? "Or your own words, for the other engines"
                                : "Or your own words: “tired, end of a "
                                    "long day”"),
                            onSubmitted: (_) => _keepOwn(),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                            child: k.button(
                                "Join",
                                _line + 1 < lines.length && !busy && !reading
                                    ? () =>
                                        c.joinSpeechLine(widget.channel, _line)
                                    : null,
                                key: const ValueKey("speechJoin"),
                                icon: Icons.call_merge,
                                tip: "Join with the next line: said as one"),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: k.button(
                                "Split",
                                CanvasController.speechSplitAt(l.text) !=
                                            null &&
                                        !busy &&
                                        !reading
                                    ? () =>
                                        c.splitSpeechLine(widget.channel, _line)
                                    : null,
                                key: const ValueKey("speechSplit"),
                                icon: Icons.content_cut,
                                tip: "Split at the comma or stop nearest "
                                    "its middle"),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            flex: 2,
                            child: k.button(
                                "Another take",
                                ready
                                    ? () => _run(() => c.anotherTake(
                                        widget.channel, l,
                                        cloudKey: _cloudKey))
                                    : null,
                                key: const ValueKey("speechAnother"),
                                icon: Icons.refresh,
                                tip: full
                                    ? "Speak it again: three takes are kept, "
                                        "so the oldest not chosen makes room"
                                    : "Speak it again, the takes it has "
                                        "kept to compare"),
                          ),
                        ]),
                      ]),
                ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 32,
          child: FilledButton.icon(
            key: const ValueKey("speechSpeak"),
            style: FilledButton.styleFrom(
              backgroundColor: s.meterLow,
              foregroundColor: const Color(0xFF0D2416),
              disabledBackgroundColor: s.raised,
              disabledForegroundColor: s.muted,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5)),
            ),
            // Every line spoken, there is nothing for it to do: Another
            // take, or a new direction, speaks a line again.
            onPressed: busy || cantSpeak || allSpoken ? null : _speakAll,
            icon: busy
                ? SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: s.muted))
                : const Icon(Icons.record_voice_over, size: 16),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                  busy
                      ? "Speaking…"
                      : allSpoken
                          ? "All spoken"
                          : "Speak all",
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        // Only while it works: how far, and that it is in the background.
        if (busy) ...[
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                key: const ValueKey("speechProgress"),
                minHeight: 4,
                color: s.meterLow,
                backgroundColor: s.raised),
          ),
          const SizedBox(height: 3),
          Text(
              queue != null
                  ? "${queue.length} ${queue.length == 1 ? "line" : "lines"} "
                      "to speak · keep working meanwhile"
                  : "Joining the lines into the clip…",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: k.text(10, colour: s.muted)),
        ],
      ]);
    }

    // ---- The feel
    Widget slider(String label, String reading, double value, double min,
            double max, ValueChanged<double> onChanged,
            {required Key key, bool can = true, VoidCallback? onEnd}) =>
        Opacity(
          opacity: can ? 1 : 0.45,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text(11.5))),
              Text(can ? reading : "not here",
                  style: can
                      ? k.mono(10.5, colour: s.text.withValues(alpha: 0.8))
                      : k.text(10, colour: s.muted)),
            ]),
            SizedBox(
              height: 20,
              child: Slider(
                key: key,
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: can
                    ? (v) {
                        c.beginInteraction();
                        onChanged(v);
                      }
                    : null,
                onChangeEnd: can
                    ? (_) {
                        c.endInteraction();
                        onEnd?.call();
                      }
                    : null,
              ),
            ),
          ]),
        );

    var (lowSpeed, highSpeed) = switch (engine) {
      SpeechEngineKind.local => (0.5, 2.0),
      SpeechEngineKind.expressive => (0.7, 1.3),
      SpeechEngineKind.cloud => (0.7, 1.2),
    };
    var feelColumn = SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: s.on,
        inactiveTrackColor: s.raised,
        thumbColor: s.on,
        overlayColor: s.on.withValues(alpha: 0.15),
        disabledActiveTrackColor: s.edge,
        disabledInactiveTrackColor: s.raised,
        disabledThumbColor: s.edge,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          k.label("Feel"),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var p in SpeechPreset.values)
              k.chip(p.label, spec.preset == p.name, () {
                _set(spec.withPreset(p));
                refinish();
              }, key: ValueKey("speechPreset-${p.name}")),
            k.chip("Custom", spec.preset == "custom", null,
                key: const ValueKey("speechPreset-custom")),
          ]),
          if (!cloud && !needsVoices) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: k.button(
                  c.speechHeard == "voice:$picked"
                      ? "Stop"
                      : c.speechPreviewing == picked
                          ? "Speaking…"
                          : "Hear this feel",
                  c.speechPreviewing != null
                      ? null
                      : () => _run(() => c.previewVoice(widget.channel, picked,
                          cloudKey: _cloudKey)),
                  key: const ValueKey("speechHearFeel"),
                  icon: c.speechHeard == "voice:$picked"
                      ? Icons.stop
                      : Icons.play_arrow,
                  small: true,
                  tip: "The voice picked saying a line, as the sliders have "
                      "it: move one, and hear it again"),
            ),
          ],
          const SizedBox(height: 8),
          k.section("Performance · how it is spoken"),
          const SizedBox(height: 4),
          slider(
              "Speed",
              "${spec.speed.toStringAsFixed(2)}×",
              spec.speed,
              lowSpeed,
              highSpeed,
              (v) => _set(spec.copyWith(speed: v, preset: "custom"),
                  transient: true),
              key: const ValueKey("speechSpeed"),
              // The pauses between the lines follow it at once; the lines
              // themselves, spoken again.
              onEnd: refinish),
          slider(
              "Stability",
              "${(spec.steadiness * 100).round()}%",
              spec.steadiness,
              0,
              1,
              (v) => _set(spec.copyWith(steadiness: v, preset: "custom"),
                  transient: true),
              key: const ValueKey("speechSteadiness"),
              can: !local),
          slider(
              "Expression",
              "${(spec.expression * 100).round()}%",
              spec.expression,
              0,
              1,
              (v) => _set(spec.copyWith(expression: v, preset: "custom"),
                  transient: true),
              key: const ValueKey("speechExpression"),
              can: !local),
          const SizedBox(height: 6),
          k.section("Finish · the sound, after"),
          const SizedBox(height: 4),
          slider(
              "Room",
              spec.room < 0.05 ? "dry" : "${(spec.room * 100).round()}%",
              spec.room,
              0,
              1,
              (v) => _set(spec.copyWith(room: v, preset: "custom"),
                  transient: true),
              key: const ValueKey("speechRoom"),
              onEnd: refinish),
          Row(children: [
            Expanded(child: Text("Speaker boost", style: k.text(11.5))),
            SizedBox(
              height: 22,
              child: FittedBox(
                child: Switch(
                  key: const ValueKey("speechBoost"),
                  value: spec.boost,
                  activeTrackColor: s.on,
                  inactiveTrackColor: s.raised,
                  thumbColor:
                      WidgetStatePropertyAll(spec.boost ? s.onOn : s.muted),
                  trackOutlineColor:
                      WidgetStatePropertyAll(spec.boost ? s.on : s.edge),
                  onChanged: (v) {
                    _set(spec.copyWith(boost: v, preset: "custom"));
                    refinish();
                  },
                ),
              ),
            ),
          ]),
        ]),
      ),
    );

    // ---- The clip: the takes chosen, joined
    var clipTake = spec.clip.isEmpty ? null : spec.takes.lastOrNull;
    var clipStrip = Row(children: [
      SizedBox(
        width: 190,
        child: Text(
          key: const ValueKey("speechStatus"),
          _problem ??
              (clipTake != null
                  ? "Clip: $spoken of ${lines.length} lines joined, "
                      "${clipTake.length.toStringAsFixed(1)} s"
                  : "The clip: the takes chosen, joined"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: k.text(10.5, colour: _problem != null ? _problemInk : s.muted),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          // As tall as its words, at the reader's text size.
          height: MediaQuery.textScalerOf(context).scale(12) + 10,
          padding: const EdgeInsets.all(3),
          decoration: k.box(s.inset),
          child: LayoutBuilder(builder: (context, room) {
            // Each line as long as its take, or as its words would be.
            double long(SpeechLine l) =>
                l.take?.length ?? math.max(0.6, l.text.split(" ").length * 0.4);
            var total = lines.fold(0.0, (n, l) => n + long(l)) +
                math.max(0, lines.length - 1) * lineGap(spec.speed);
            if (total <= 0) return const SizedBox();
            var per = room.maxWidth / total;
            return Row(children: [
              for (var (i, l) in lines.indexed) ...[
                if (i > 0) SizedBox(width: lineGap(spec.speed) * per),
                SizedBox(
                  width: math.max(0, long(l) * per),
                  child: GestureDetector(
                    onTap: () => setState(() => _line = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: l.take != null
                            ? (i == _line
                                ? s.solo.withValues(alpha: 0.35)
                                : s.raised)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                            color: i == _line
                                ? s.solo
                                : l.take != null
                                    ? s.on.withValues(alpha: 0.5)
                                    : s.edge),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text("${i + 1}  ${l.text}",
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: k.text(9,
                              colour: l.take != null ? s.text : s.muted)),
                    ),
                  ),
                ),
              ],
            ]);
          }),
        ),
      ),
    ]);

    Widget divider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: s.edge.withValues(alpha: 0.7));

    return DeviceFrame(
      id: "speech",
      title: "Speech",
      skin: skin,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 1140,
      height: widget.height,
      actions: [
        Text("Engine", style: k.text(11, colour: s.muted)),
        const SizedBox(width: 6),
        for (var e in SpeechEngineKind.values)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Material(
              color: engine == e ? s.on : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                key: ValueKey("speechEngine-${e.name}"),
                borderRadius: BorderRadius.circular(4),
                onTap: () =>
                    _set(spec.copyWith(engine: e, voice: "", voiceName: "")),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  child: Text(e.label,
                      style: k.text(11,
                          weight: FontWeight.w600,
                          colour: engine == e ? s.onOn : s.text)),
                ),
              ),
            ),
          ),
        const SizedBox(width: 6),
        IconButton(
          key: const ValueKey("speechRemove"),
          tooltip: "Take the Speech device off. Its takes stay on the "
              "timeline.",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, color: skin.ink),
          onPressed: _takeOff,
        ),
      ],
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
              "Speech · ${spec.voiceName.isEmpty ? "voice" : spec.voiceName}",
              style: k.text(11, colour: s.muted)),
        ),
      ),
      body: Container(
        color: s.panel,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 190, child: voiceColumn),
              divider(),
              Expanded(child: scriptColumn),
              divider(),
              SizedBox(width: 300, child: linePanel()),
              divider(),
              SizedBox(width: 200, child: feelColumn),
            ]),
          ),
          const SizedBox(height: 7),
          clipStrip,
        ]),
      ),
    );
  }

  void _takeOff() {
    c.beginInteraction();
    c.setSpeech(widget.channel, null);
    c.endInteraction();
  }
}

/// VocaliserDevice is channel [channel]'s Vocaliser: the MIDI channel
/// whose notes it sings, how it sings them, and Sing -- which sings the
/// channel's latest Speech take into a new clip.
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
    var skin = DeviceSkin.themed(look.colors);
    TextStyle small([Color? colour]) =>
        TextStyle(fontSize: 11, color: colour ?? skin.ink);
    var tunes = c.midiChannels;
    var melody = tunes.any((t) => t.$1 == spec.melody)
        ? spec.melody
        : tunes.firstOrNull?.$1;
    var take = c.speechOf(widget.channel)?.takes.lastOrNull;
    var busy = c.singing.contains(widget.channel);

    Widget slider(String label, String reading, double value, double max,
            ValueChanged<double> onChanged,
            {required Key key}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(label, style: small())),
            Text(reading, style: small(skin.dim)),
          ]),
          SizedBox(
            height: 22,
            child: Slider(
              key: key,
              value: value.clamp(0, max),
              max: max,
              onChanged: (v) {
                c.beginInteraction();
                onChanged(v);
              },
              onChangeEnd: (_) => c.endInteraction(),
            ),
          ),
        ]);

    return DeviceFrame(
      id: "vocaliser",
      title: "Vocaliser",
      skin: skin,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 260,
      height: widget.height,
      actions: [
        IconButton(
          key: const ValueKey("vocaliserRemove"),
          tooltip: "Take the Vocaliser off. What it sang stays on the "
              "timeline.",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, color: skin.ink),
          onPressed: () {
            c.beginInteraction();
            c.setVocaliser(widget.channel, null);
            c.endInteraction();
          },
        ),
      ],
      foldedBody: Center(
        child: RotatedBox(
            quarterTurns: 3, child: Text("Vocaliser", style: small(skin.dim))),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // All but Sing scroll in what room it leaves.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        take == null
                            ? "Sings this channel's latest Speech take: speak one "
                                "first."
                            : "Sings Take ${c.speechOf(widget.channel)!.takes.length}: "
                                "${take.words.length} words.",
                        style: small(skin.dim)),
                    const SizedBox(height: 10),
                    Text("To the notes of", style: small(skin.dim)),
                    DropdownButton<String>(
                      key: const ValueKey("vocaliserMelody"),
                      isExpanded: true,
                      isDense: true,
                      value: melody,
                      hint: Text("No MIDI channel yet", style: small(skin.dim)),
                      style: small(),
                      dropdownColor: look.colors.surfaceContainerHigh,
                      items: [
                        for (var (key, name) in tunes)
                          DropdownMenuItem(value: key, child: Text(name)),
                      ],
                      onChanged: (v) {
                        if (v != null) _set(spec.copyWith(melody: v));
                      },
                    ),
                    const SizedBox(height: 10),
                    slider(
                        "Vibrato",
                        "${(spec.vibrato * 100).round()}%",
                        spec.vibrato,
                        1,
                        (v) => _set(spec.copyWith(vibrato: v), transient: true),
                        key: const ValueKey("vocaliserVibrato")),
                    slider(
                        "Glide",
                        "${(spec.glide * 1000).round()} ms",
                        spec.glide,
                        0.5,
                        (v) => _set(spec.copyWith(glide: v), transient: true),
                        key: const ValueKey("vocaliserGlide")),
                  ]),
            ),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            key: const ValueKey("vocaliserSing"),
            onPressed: busy || take == null || melody == null ? null : _sing,
            icon: busy
                ? const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.music_note, size: 16),
            label: Text(busy ? "Singing…" : "Sing"),
          ),
          const SizedBox(height: 4),
          Text(_problem ?? "Into a new clip, where the tune starts.",
              key: const ValueKey("vocaliserStatus"),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  small(_problem != null ? const Color(0xFFFF8A80) : skin.dim)),
        ]),
      ),
    );
  }
}
