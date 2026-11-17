part of 'speech_device.dart';

// The Feel panel: the preset, and the sliders for how a voice speaks and how it
// sounds after. Part of _SpeechDeviceState: its fields, lifecycle and build are
// in speech_device.dart.

extension _SpeechFeel on _SpeechDeviceState {
  /// _slider is one of the Feel panel's sliders: its label and reading
  /// above, greyed where the engine cannot do it ([can]), the drag one
  /// change to undo.
  Widget _slider(_SpeechView view, String label, String reading, double value,
      double min, double max, ValueChanged<double> onChanged,
      {required Key key, bool can = true, VoidCallback? onEnd}) {
    var k = view.k, s = view.s;
    return Opacity(
      opacity: can ? 1 : 0.45,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
  }

  /// _feelColumn is the Feel panel: the preset, Hear this feel, and the
  /// sliders for how it is spoken and how it sounds after.
  Widget _feelColumn(_SpeechView view) {
    var spec = view.spec,
        k = view.k,
        s = view.s,
        engine = view.engine,
        local = view.local,
        needsVoices = view.needsVoices,
        picked = view.picked;
    var (lowSpeed, highSpeed) = switch (engine) {
      SpeechEngineKind.local => (0.5, 2.0),
      SpeechEngineKind.expressive => (0.7, 1.3),
    };
    return SliderTheme(
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
          // A dropdown, not chips, leaving the sliders room. Custom shows when
          // the sliders have moved to it; it is not picked.
          k.dropdown<String>(
            key: const ValueKey("speechPreset"),
            value: SpeechPreset.values.any((p) => p.name == spec.preset)
                ? spec.preset
                : "custom",
            items: [
              for (var p in SpeechPreset.values) (p.name, p.label),
              ("custom", "Custom"),
            ],
            onChanged: (v) {
              for (var p in SpeechPreset.values) {
                if (p.name == v) _set(spec.withPreset(p));
              }
            },
          ),
          if (!needsVoices) ...[
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
                      : () =>
                          _run(() => c.previewVoice(widget.channel, picked)),
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
          _slider(
              view,
              "Speed",
              "${spec.speed.toStringAsFixed(2)}×",
              spec.speed,
              lowSpeed,
              highSpeed,
              (v) => _set(spec.copyWith(speed: v, preset: "custom"),
                  transient: true),
              key: const ValueKey("speechSpeed")),
          _slider(
              view,
              "Stability",
              "${(spec.steadiness * 100).round()}%",
              spec.steadiness,
              0,
              1,
              (v) => _set(spec.copyWith(steadiness: v, preset: "custom"),
                  transient: true),
              key: const ValueKey("speechSteadiness"),
              can: !local),
          _slider(
              view,
              "Expression",
              // Vivid, the expressive voices breathe between sentences.
              "${(spec.expression * 100).round()}%"
                  "${engine == SpeechEngineKind.expressive && spec.expression > qwenBreathing ? " · breaths" : ""}",
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
          _slider(
            view,
            "Room",
            spec.room < 0.05 ? "dry" : "${(spec.room * 100).round()}%",
            spec.room,
            0,
            1,
            (v) =>
                _set(spec.copyWith(room: v, preset: "custom"), transient: true),
            key: const ValueKey("speechRoom"),
          ),
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
                  },
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
