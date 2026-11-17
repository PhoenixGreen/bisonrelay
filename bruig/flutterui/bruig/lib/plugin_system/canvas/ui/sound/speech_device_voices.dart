part of 'speech_device.dart';

// The Voice panel: the engine's voices, narrowed by gender and accent, each
// heard before it is picked, and the download that brings them. Part of
// _SpeechDeviceState: its fields, lifecycle and build are in
// speech_device.dart.

extension _SpeechVoices on _SpeechDeviceState {
  Future<List<SpeechVoice>> _voicesOf(SpeechSpec spec) {
    var asked = spec.engine.name;
    if (_voices == null || asked != _voicesFor) {
      _voicesFor = asked;
      _voices = CanvasController.speechEngineFor(spec)
          .voices()
          .catchError((Object e) => <SpeechVoice>[]);
    }
    return _voices!;
  }

  PinnedDownload _downloadOf(SpeechEngineKind engine) => switch (engine) {
        SpeechEngineKind.local => KokoroDownload.instance,
        SpeechEngineKind.expressive => QwenDownload.instance,
      };

  /// _downloadPanel replaces the voice list until the engine's voices are
  /// here: their size and a fetch button, or the progress.
  Widget _downloadPanel(
      PinnedDownload voices, SpeechEngineKind engine, SpeechKit k) {
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

  /// A voice heard saying a line; pressed while playing, it stops.
  Widget _previewButton(_SpeechView view, String voice) {
    var s = view.s, needsVoices = view.needsVoices;
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
            : () => _run(() => c.previewVoice(widget.channel, voice)),
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

  /// _voiceColumn is the Voice panel: the language (expressive voices), the
  /// gender and accent chips, and the list -- or the download in its place.
  Widget _voiceColumn(_SpeechView view) {
    var spec = view.spec,
        k = view.k,
        s = view.s,
        engine = view.engine,
        expressive = view.expressive,
        download = view.download,
        unmade = view.unmade,
        needsVoices = view.needsVoices,
        picked = view.picked;
    return FutureBuilder<List<SpeechVoice>>(
      future: _voicesOf(spec),
      builder: (context, snap) {
        var all = snap.data ?? const <SpeechVoice>[];
        var gendered = all.any((v) => v.gender.isNotEmpty);
        // Accents, where the voices have more than one: the expressive ones
        // keep theirs in every language, so are not narrowed.
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
        Widget list() {
          if (unmade) {
            return Text(
                "The expressive voices are made for Apple Silicon Macs and "
                "for Linux: not for this computer yet.",
                key: const ValueKey("speechUnmade"),
                style: k.text(10.5, colour: s.muted));
          }
          if (needsVoices) return _downloadPanel(download, engine, k);
          var waiting = snap.connectionState != ConnectionState.done
              ? "Finding voices…"
              : shown.isEmpty
                  ? "No voices found."
                  : null;
          return ListView(
            key: const ValueKey("speechVoices"),
            padding: EdgeInsets.zero,
            children: [
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
                          // Previews for our own voices only: ElevenLabs
                          // charges for one.
                          _previewButton(view, v.id),
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
              // One line, scrolled sideways if too long.
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
  }
}
