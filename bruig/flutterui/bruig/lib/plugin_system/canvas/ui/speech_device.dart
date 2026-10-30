import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
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
// and the voice, the script with its cues, how it is delivered, and Speak
// -- which speaks it into a clip on the channel. See speech_spec.dart for
// what it keeps, and speech_engines.dart for how it speaks.

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

  /// _voices are the engine's voices, asked for once for each engine (and
  /// key), and _voicesFor what they were asked for.
  Future<List<SpeechVoice>>? _voices;
  String _voicesFor = "";
  String _filter = "";

  /// _accent is the accent the voice list is narrowed to -- the start of a
  /// voice's description, "UK", "US" -- or "" for all.
  String _accent = "";

  /// _missing is how much of our own voices is still to download.
  Future<int>? _missing;
  String? _problem;

  @override
  void initState() {
    super.initState();
    KokoroDownload.instance.addListener(_changed);
    KokoroDownload.instance.check();
    _scriptFocus.addListener(() {
      // A stretch of typing, one change to undo.
      if (!_scriptFocus.hasFocus) c.endInteraction();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    KokoroDownload.instance.removeListener(_changed);
    _script.dispose();
    _scriptFocus.dispose();
    _key.dispose();
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
    _set(spec.copyWith(script: next));
  }

  Future<void> _speak() async {
    setState(() => _problem = null);
    var problem = await c.speak(widget.channel, cloudKey: _cloudKey);
    if (mounted) setState(() => _problem = problem);
  }

  /// _download is in place of the voice list until our own voices are
  /// here: how big they are, and the button to fetch them -- or how far
  /// they have got.
  Widget _download(KokoroDownload voices, TextStyle Function([Color?]) small,
          DeviceSkin skin) =>
      SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FutureBuilder<int>(
            future: _missing ??=
                voices.missingBytes().catchError((_) => kokoroBytes),
            builder: (context, snap) {
              var missing = snap.data ?? kokoroBytes;
              var some = missing < kokoroBytes;
              return Text(
                  "${kokoroVoices.length} voices -- British, American and "
                  "Chinese; and Spanish, French, Hindi, Italian, Japanese "
                  "and Portuguese where espeak-ng is installed -- spoken on "
                  "this computer. "
                  "${some ? "The new ones are" : "They are"} a one-off "
                  "download of ${(missing / 1e6).round()} MB.",
                  style: small(skin.dim));
            },
          ),
          const SizedBox(height: 6),
          if (voices.downloading) ...[
            LinearProgressIndicator(
                key: const ValueKey("speechDownloadProgress"),
                value: voices.share),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: Text("${((voices.share ?? 0) * 100).round()}%",
                      style: small(skin.dim))),
              TextButton(
                  key: const ValueKey("speechDownloadStop"),
                  onPressed: voices.stop,
                  child: const Text("Stop")),
            ]),
          ] else
            FilledButton.icon(
              key: const ValueKey("speechDownload"),
              onPressed: voices.ready == null ? null : voices.start,
              icon: const Icon(Icons.download, size: 16),
              label: const Text("Download"),
            ),
          if (voices.problem case var problem?) ...[
            const SizedBox(height: 4),
            Text(problem, style: small(const Color(0xFFFF8A80))),
          ],
        ]),
      );

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
    var studio = look.studio;
    TextStyle small([Color? colour]) =>
        TextStyle(fontSize: 11, color: colour ?? skin.ink);
    var speaking = c.speaking.contains(widget.channel);
    var cloud = spec.engine == SpeechEngineKind.cloud;
    var needsKey = cloud && _cloudKey.isEmpty;
    var voices = KokoroDownload.instance;
    // Our own voices, until they are downloaded: the download in place of
    // the list, and nothing to speak with.
    var needsVoices = !cloud && voices.ready != true;
    var picked =
        spec.voice.isEmpty && !cloud ? kokoroVoices.first.id : spec.voice;

    Widget pill(String label, bool on, VoidCallback onTap, {Key? key}) =>
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Material(
            color: on ? studio.on : look.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(4),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: on ? studio.onOn : skin.ink)),
              ),
            ),
          ),
        );

    Widget slider(String label, String reading, double value, double min,
            double max, ValueChanged<double> onChanged,
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
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                c.beginInteraction();
                onChanged(v);
              },
              onChangeEnd: (_) => c.endInteraction(),
            ),
          ),
        ]);

    var latest = spec.takes.lastOrNull;
    return DeviceFrame(
      id: "speech",
      title: "Speech",
      skin: skin,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 660,
      height: widget.height,
      actions: [
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
              style: small(skin.dim)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text("Engine  ", style: small(skin.dim)),
            for (var e in SpeechEngineKind.values)
              pill(
                  e.label,
                  spec.engine == e,
                  () =>
                      _set(spec.copyWith(engine: e, voice: "", voiceName: "")),
                  key: ValueKey("speechEngine-${e.name}")),
          ]),
          if (cloud) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: const Color(0xFF3A2A14),
                  borderRadius: BorderRadius.circular(4)),
              child: Row(children: [
                Expanded(
                  child: Text(
                      "ElevenLabs, in the cloud: the script is sent there to "
                      "be spoken, on your own account, when you press Speak.",
                      style: small(const Color(0xFFF2D6A0))),
                ),
                if (needsKey) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 170,
                    height: 26,
                    child: TextField(
                      key: const ValueKey("speechKey"),
                      controller: _key,
                      obscureText: true,
                      style: small(),
                      decoration: const InputDecoration(
                          isDense: true,
                          hintText: "Your API key",
                          border: OutlineInputBorder()),
                      onSubmitted: (v) {
                        try {
                          context.read<CanvasPreferences>().elevenLabsKey = v;
                        } catch (_) {}
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 6),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // The voices.
              SizedBox(
                width: 160,
                child: FutureBuilder<List<SpeechVoice>>(
                  future: _voicesOf(spec),
                  builder: (context, snap) {
                    var all = snap.data ?? const <SpeechVoice>[];
                    var gendered = all.any((v) => v.gender.isNotEmpty);
                    // Accents, where the voices have more than one.
                    var accents = <String>{
                      for (var v in all)
                        if (v.about.contains(" ")) v.about.split(" ").first
                    }.toList();
                    var shown = [
                      for (var v in all)
                        if ((_filter.isEmpty || v.gender == _filter) &&
                            (_accent.isEmpty ||
                                v.about.startsWith("$_accent ")))
                          v
                    ];
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Voice", style: small(skin.dim)),
                          // One line, scrolled sideways where the text is
                          // too large for it: wrapped, it took the list's room.
                          if (gendered && all.length > 2)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                for (var (g, label) in const [
                                  ("", "All"),
                                  ("f", "Women"),
                                  ("m", "Men")
                                ])
                                  pill(label, _filter == g,
                                      () => setState(() => _filter = g),
                                      key: ValueKey("speechFilter-$g")),
                              ]),
                            ),
                          if (accents.length > 1) ...[
                            const SizedBox(height: 3),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                for (var a in ["", ...accents])
                                  pill(a.isEmpty ? "Any" : a, _accent == a,
                                      () => setState(() => _accent = a),
                                      key: ValueKey("speechAccent-$a")),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Expanded(
                            child: needsVoices
                                ? _download(voices, small, skin)
                                : snap.connectionState != ConnectionState.done
                                    ? Center(
                                        child: Text("Finding voices…",
                                            style: small(skin.dim)))
                                    : shown.isEmpty
                                        ? Text(
                                            needsKey
                                                ? "Your key, to list its voices."
                                                : "No voices found.",
                                            style: small(skin.dim))
                                        : ListView(
                                            key: const ValueKey("speechVoices"),
                                            padding: EdgeInsets.zero,
                                            children: [
                                              for (var v in shown)
                                                Material(
                                                  color: v.id == picked
                                                      ? studio.on.withValues(
                                                          alpha: 0.25)
                                                      : Colors.transparent,
                                                  child: InkWell(
                                                    key: ValueKey(
                                                        "speechVoice-${v.id}"),
                                                    onTap: () => _set(
                                                        spec.copyWith(
                                                            voice: v.id,
                                                            voiceName: v.name)),
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 4,
                                                          vertical: 3),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(v.name,
                                                                style: small()),
                                                            if (v.about
                                                                .isNotEmpty)
                                                              Text(v.about,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: small(
                                                                      skin.dim)),
                                                          ]),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                          ),
                        ]);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // The script, and its cues -- at most half the room, scrolled
              // past that, so the script always has the rest.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, room) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The script typed here, or read from a Writing
                      // Tools document -- kept up to date as it is edited.
                      Row(children: [
                        Text("Script", style: small(skin.dim)),
                        const SizedBox(width: 6),
                        // The document's name, in what room is left; the
                        // switch made smaller, rather than overflowing,
                        // where the column is narrow.
                        Expanded(
                          child: spec.document.on
                              ? Row(children: [
                                  Flexible(
                                    child: Text(spec.document.says,
                                        key: const ValueKey("speechDocument"),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: small(skin.dim)),
                                  ),
                                  InkWell(
                                    key: const ValueKey("speechDocumentPick"),
                                    onTap: () =>
                                        _pickDocument(spec, again: true),
                                    child: Tooltip(
                                      message: "Read another document",
                                      child: Icon(Icons.description_outlined,
                                          size: 14, color: skin.dim),
                                    ),
                                  ),
                                ])
                              : const SizedBox(),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: pill("From document", spec.document.on, () {
                              if (spec.document.on) {
                                // What was typed before, given back.
                                _set(spec.copyWith(
                                    script: spec.document.wasText,
                                    document: const TextDocumentRef()));
                              } else {
                                _pickDocument(spec);
                              }
                            }, key: const ValueKey("speechFromDocument")),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Expanded(
                        child: TextField(
                          key: const ValueKey("speechScript"),
                          controller: _script,
                          focusNode: _scriptFocus,
                          // Read from a document: changed there.
                          readOnly: spec.document.on,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: "What is to be said. Cues go in "
                                  "[brackets]: [pause 0.5], [laugh]…"),
                          onChanged: (v) {
                            c.beginInteraction();
                            _set(spec.copyWith(script: v), transient: true);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: room.maxHeight / 2),
                        child: SingleChildScrollView(
                          child: Wrap(spacing: 3, runSpacing: 3, children: [
                            for (var cue in spec.engine.cues)
                              Tooltip(
                                message: "Put in ${cue.token}",
                                child: InkWell(
                                  key: ValueKey("speechCue-${cue.name}"),
                                  onTap: () => _cue(spec, cue),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        border: Border.all(color: studio.edge),
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: Text("${cue.icon} ${cue.label}",
                                        style: const TextStyle(fontSize: 10)),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // How it is said, and Speak.
              SizedBox(
                width: 140,
                // The sliders scroll in what room the button leaves: four of
                // them for ElevenLabs, or a larger text size, are more than
                // the device's height.
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                slider(
                                    "Speed",
                                    "${spec.speed.toStringAsFixed(2)}×",
                                    spec.speed,
                                    0.5,
                                    2,
                                    (v) => _set(spec.copyWith(speed: v),
                                        transient: true),
                                    key: const ValueKey("speechSpeed")),
                                if (cloud) ...[
                                  slider(
                                      "Expression",
                                      "${(spec.expression * 100).round()}%",
                                      spec.expression,
                                      0,
                                      1,
                                      (v) => _set(spec.copyWith(expression: v),
                                          transient: true),
                                      key: const ValueKey("speechExpression")),
                                  slider(
                                      "Steadiness",
                                      "${(spec.steadiness * 100).round()}%",
                                      spec.steadiness,
                                      0,
                                      1,
                                      (v) => _set(spec.copyWith(steadiness: v),
                                          transient: true),
                                      key: const ValueKey("speechSteadiness")),
                                ],
                              ]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FilledButton.icon(
                        key: const ValueKey("speechSpeak"),
                        onPressed:
                            speaking || needsKey || needsVoices ? null : _speak,
                        icon: speaking
                            ? const SizedBox.square(
                                dimension: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.record_voice_over, size: 16),
                        label: Text(speaking ? "Speaking…" : "Speak"),
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(
            key: const ValueKey("speechStatus"),
            _problem ??
                (latest == null
                    ? "Spoken into a clip on this channel, from the playhead."
                    : "Take ${spec.takes.length}: "
                        "${latest.length.toStringAsFixed(1)} s, "
                        "${latest.words.length} words "
                        "${latest.exact ? "timed exactly" : "timed by length"}"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small(_problem != null ? const Color(0xFFFF8A80) : skin.dim),
          ),
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
