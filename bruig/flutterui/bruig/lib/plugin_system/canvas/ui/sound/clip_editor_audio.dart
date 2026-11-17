part of 'clip_editor.dart';

// An audio clip: its editor, toolbar, inspector and status. Part of
// _ClipEditorState: its fields, lifecycle and build are in clip_editor.dart.

extension _ClipEditorAudio on _ClipEditorState {
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

  /// _tb is a button of the audio clip's bar: a word, an icon or both.
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

  /// _tbReadout is a value on the bar, typed into on a double-click.
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

  Widget _tbMenu(MixerLook look, String key, String label, List<Widget> items,
          {IconData? icon, String? tip, bool enabled = true}) =>
      MenuAnchor(
        menuChildren: items,
        builder: (context, menu, _) => _tb(look, key, label,
            enabled ? () => menu.isOpen ? menu.close() : menu.open() : null,
            icon: icon, tip: tip, menu: true),
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
                      editorMenuItem(
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
                      editorMenuItem("clipSlice-${by.name}", by.label,
                          () => _run(() => c.sliceClip(by))),
                    const Divider(height: 8),
                    editorMenuItem("clipSliceNotes", "Into a note clip",
                        () => _run(() => c.sliceToInstrument(pads: false)),
                        hint: "Each hit a note, on a new channel that plays "
                            "them"),
                    editorMenuItem("clipSlicePads", "Into drum pads",
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
                      editorMenuItem("clipFadeCurve-${f.name}", f.label,
                          () => c.editClip((x) => x.copyWith(fadeCurve: f)),
                          on: f == clip.fadeCurve),
                    const Divider(height: 8),
                    editorMenuItem("clipFade", "A short fade at every cut",
                        () => c.editClip((x) => x.copyWith(fade: !x.fade)),
                        on: clip.fade,
                        hint: "A few milliseconds at its start and its "
                            "loop's: no click where it is cut"),
                  ],
                  icon: Icons.show_chart,
                  tip: "The way its fades go"),
              _tbGap(look),
              _tbLabel(look, "Envelope"),
              toolbarGroup(look, [
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
                          editorMenuItem(
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
              toolbarGroup(look, [
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
              clip.fadeIn == 0 ? "None" : _ClipEditorState._seconds(clip.fadeIn),
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
              clip.fadeOut == 0 ? "None" : _ClipEditorState._seconds(clip.fadeOut),
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
}
