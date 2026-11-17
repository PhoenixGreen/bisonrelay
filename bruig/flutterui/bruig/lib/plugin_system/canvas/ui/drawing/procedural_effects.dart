part of 'procedural_settings.dart';

// Symbols, metal, a look's own groups, each setting's control, and the effects
// over the look. Part of ProceduralSettings: its fields, lifecycle and build
// are in procedural_settings.dart.

extension ProceduralEffects on ProceduralSettings {
  /// _symbols is the character set the glyph styles draw from.
  Widget _symbols() => CanvasControlGroup(label: "Symbols", children: [
        // A set to start from, and the set itself as one string, so a
        // character is added by typing it.
        CanvasDropdown<String>(
          key: const ValueKey("glyphSet"),
          label: "Set",
          value:
              glyphSets.where((g) => g.$2 == spec.glyphs).firstOrNull?.$1 ?? "",
          width: 110,
          options: [
            if (!glyphSets.any((g) => g.$2 == spec.glyphs)) ("", "Your own"),
            for (var (name, _) in glyphSets) (name, name),
          ],
          onChanged: (name) {
            for (var (n, glyphs) in glyphSets) {
              if (n == name) _setNow(spec.copyWith(glyphs: glyphs));
            }
          },
        ),
        CanvasTextField(
          label: "Characters used",
          value: spec.glyphs,
          width: 240,
          onChanged: (v) => _set(spec.copyWith(glyphs: v)),
          onCommit: onCommit,
        ),
        CanvasIconButton(
          icon: Icons.restart_alt,
          tooltip: "Back to the default characters",
          onPressed: () => _setNow(spec.copyWith(glyphs: defaultGlyphs)),
        ),
      ]);

  /// _metalGroup is the Metal texture's own settings.
  Widget _metalGroup() => CanvasControlGroup(label: "Metal", children: [
        CanvasNumberField(
          key: const ValueKey("metalRoughness"),
          label: "Roughness",
          value: metal.roughness,
          min: 0,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            onBegin();
            _metalSet(metal.copyWith(roughness: v));
          },
          onCommit: onCommit,
        ),
        CanvasNumberField(
          key: const ValueKey("metalShine"),
          label: "Shine",
          value: metal.shine,
          min: 0,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            onBegin();
            _metalSet(metal.copyWith(shine: v));
          },
          onCommit: onCommit,
        ),
        CanvasNumberField(
          key: const ValueKey("metalRust"),
          label: "Rust",
          value: metal.rust,
          min: 0,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            onBegin();
            _metalSet(metal.copyWith(rust: v));
          },
          onCommit: onCommit,
        ),
        CanvasNumberField(
          key: const ValueKey("metalDamage"),
          label: "Damage",
          value: metal.damage,
          min: 0,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            onBegin();
            _metalSet(metal.copyWith(damage: v));
          },
          onCommit: onCommit,
        ),
        const CanvasHint("The colours above are the sheet: Base is the "
            "metal, Main is the sheen along the brushing, and Accent is "
            "the rust. Shine is matt at nought and mirrored at one."),
      ]);

  /// _ownGroups is the style's own settings, under their headings. See
  /// StyleParam.
  List<Widget> _ownGroups() {
    var params = spec.style.params;
    if (params.isEmpty) return const [];
    bool shows(StyleParam p) =>
        p.onlyWhen.entries.every((w) => w.value.contains(spec.choice(w.key)));

    var groups = <String, List<Widget>>{};
    var fineTune = <Widget>[];
    var pitch = spec.style == ProceduralStyle.pitch;
    for (var p in params) {
      if (!shows(p)) continue;
      // A pitch's camera is moved with the orbit pad; its numbers are there
      // for getting one exactly right, behind it.
      if (pitch && ProceduralSettings._fineTune.contains(p.id)) {
        fineTune.add(_paramControl(p));
        continue;
      }
      (groups[p.group ?? spec.style.label] ??= []).add(_paramControl(p));
      // A pitch's Size is how far in the camera is, so it is with the
      // camera, as a zoom: one fits the frame.
      if (spec.style == ProceduralStyle.pitch && p.id == "view") {
        groups["Camera"]!.add(CanvasNumberField(
          key: const ValueKey("pitchZoom"),
          label: "Zoom",
          value: spec.scale / 0.05,
          min: 0.1,
          max: 5,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            onBegin();
            _set(spec.copyWith(scale: v * 0.05));
          },
          onCommit: onCommit,
        ));
        groups["Camera"]!.add(pitchShotDropdown(spec, _setNow));
        groups["Camera"]!.add(_orbitPad());
        groups["Camera"]!.add(PitchSavedViews(spec: spec, onChanged: _setNow));
      }
    }
    if (fineTune.isNotEmpty) {
      groups["Camera"]!.add(CanvasExpander(
        label: "Fine tune",
        remember: "pitch.fineTune",
        children: [CanvasWrap(children: fineTune)],
      ));
    }
    return [
      for (var MapEntry(key: label, value: children) in groups.entries)
        CanvasControlGroup(label: label, children: children),
    ];
  }

  /// _orbitPad is the pitch's camera as one control. See PitchOrbitPad.
  Widget _orbitPad() {
    var cam = pitchCamera(spec);
    return PitchOrbitPad(
      value: (
        tilt: cam.tilt,
        side: cam.side,
        turn: cam.turn,
        perspective: cam.perspective,
        zoom: spec.scale / 0.05,
      ),
      onBegin: onBegin,
      onCommit: onCommit,
      onChanged: (v) => _set(spec
          .withParam("tiltV", v.tilt)
          .withParam("tiltH", v.side)
          .withParam("turn", v.turn)
          .withParam("perspective", v.perspective)
          .copyWith(scale: v.zoom * 0.05)),
    );
  }

  Widget _paramControl(StyleParam p) {
    var key = ValueKey("param-${p.id}");
    if (p.isChoice) {
      return CanvasDropdown<int>(
        key: key,
        label: p.label,
        value: spec.choice(p.id),
        width: 110,
        options: [for (var (i, c) in p.choices.indexed) (i, c)],
        onChanged: (v) {
          // And whatever this answer puts in place with it.
          var next = spec.withParam(p.id, v.toDouble());
          for (var MapEntry(:key, :value) in (p.sets[v] ?? const {}).entries) {
            next = next.withParam(key, value);
          }
          // A pitch's View starts on its first shot, framing and all.
          if (spec.style == ProceduralStyle.pitch && p.id == "view") {
            var first = pitchShots[v]?.firstOrNull;
            if (first != null) next = withPitchCamera(next, first.$2);
          }
          _setNow(next);
        },
      );
    }
    if (p.toggle) {
      return CanvasToggle(
        key: key,
        label: p.label,
        value: spec.on(p.id),
        onChanged: (v) => _setNow(spec.withParam(p.id, v ? 1 : 0)),
      );
    }
    return CanvasNumberField(
      key: key,
      label: p.label,
      value: spec.p(p.id),
      min: p.min,
      max: p.max,
      decimals: p.decimals,
      width: 62,
      onChanged: (v) {
        onBegin();
        _set(spec.withParam(p.id, v));
      },
      onCommit: onCommit,
    );
  }

  EffectsSpec get fx => spec.effects;

  Widget _fxField(String id, String label, double value, double min, double max,
          EffectsSpec Function(double) put,
          {int decimals = 2, String suffix = ""}) =>
      CanvasNumberField(
        key: ValueKey("fx-$id"),
        label: label,
        value: value,
        min: min,
        max: max,
        decimals: decimals,
        suffix: suffix,
        width: 62,
        onChanged: (v) {
          onBegin();
          _set(spec.copyWith(effects: put(v)));
        },
        onCommit: onCommit,
      );

  /// _effects is what is done to the pattern once drawn: behind a heading like
  /// the light, each off until wanted.
  Widget _effects() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: CanvasExpander(
          label: "Effects",
          remember: "background.effects",
          trailing: fx.any ? "On" : "None",
          children: [
            CanvasControlGroup(label: "Finish", children: [
              _fxField("opacity", "Pattern", fx.opacity, 0, 1,
                  (v) => fx.copyWith(opacity: v)),
              _fxField(
                  "glow", "Glow", fx.glow, 0, 2, (v) => fx.copyWith(glow: v)),
              if (fx.glow > 0)
                _fxField("glowSize", "Spread", fx.glowSize, 0, 1,
                    (v) => fx.copyWith(glowSize: v)),
              _fxField(
                  "blur", "Blur", fx.blur, 0, 1, (v) => fx.copyWith(blur: v)),
              if (!layer)
                CanvasNumberField(
                  key: const ValueKey("fx-vignette"),
                  label: "Vignette",
                  min: 0,
                  max: 1,
                  decimals: 2,
                  width: 62,
                  value: spec.vignette,
                  onChanged: (v) {
                    onBegin();
                    _set(spec.copyWith(vignette: v));
                  },
                  onCommit: onCommit,
                ),
              if (!layer) ...[
                const CanvasLineBreak(),
                _fxField("grain", "Grain", fx.grain, 0, 1,
                    (v) => fx.copyWith(grain: v)),
              ],
              if (fx.grain > 0 && !layer)
                _fxField("grainSize", "Grain size", fx.grainSize, 0.3, 12,
                    (v) => fx.copyWith(grainSize: v),
                    decimals: 1),
              if (fx.grain > 0 && spec.animated && !layer)
                CanvasToggle(
                  key: const ValueKey("fx-grainMoves"),
                  label: "Moves",
                  value: fx.grainMoves,
                  onChanged: (v) => _setNow(
                      spec.copyWith(effects: fx.copyWith(grainMoves: v))),
                ),
              if (!layer)
                _fxField("scanlines", "Scanlines", fx.scanlines, 0, 1,
                    (v) => fx.copyWith(scanlines: v)),
              if (fx.scanlines > 0 && !layer)
                _fxField("scanlineSize", "Line gap", fx.scanlineSize, 1, 40,
                    (v) => fx.copyWith(scanlineSize: v),
                    decimals: 1),
            ]),
            // Where the eye goes, and where the pattern keeps clear of what is
            // on top.
            CanvasControlGroup(label: "Focus", children: [
              _fxField("focus", "Fade out", fx.focus, 0, 1,
                  (v) => fx.copyWith(focus: v)),
              if (fx.focus > 0) ...[
                _fxField("focusSize", "Size", fx.focusSize, 0, 2,
                    (v) => fx.copyWith(focusSize: v)),
                _fxField("focusX", "X", fx.focusX, -0.5, 1.5,
                    (v) => fx.copyWith(focusX: v)),
                _fxField("focusY", "Y", fx.focusY, -0.5, 1.5,
                    (v) => fx.copyWith(focusY: v)),
              ],
            ]),
            CanvasControlGroup(label: "Keep clear", children: [
              CanvasDropdown<ClearArea>(
                key: const ValueKey("fx-clear"),
                label: "Area",
                value: fx.clear,
                width: 90,
                options: [for (var a in ClearArea.values) (a, a.label)],
                onChanged: (v) =>
                    _setNow(spec.copyWith(effects: fx.copyWith(clear: v))),
              ),
              if (fx.clear != ClearArea.none) ...[
                _fxField("clearSize", "Size", fx.clearSize, 0, 1,
                    (v) => fx.copyWith(clearSize: v)),
                _fxField("clearSoftness", "Softness", fx.clearSoftness, 0, 1,
                    (v) => fx.copyWith(clearSoftness: v)),
                _fxField("clearAmount", "Amount", fx.clearAmount, 0, 1,
                    (v) => fx.copyWith(clearAmount: v)),
              ],
            ]),
            if (!layer)
              CanvasControlGroup(label: "Colour grade", children: [
                _fxField(
                    "hue", "Hue", fx.hue, -180, 180, (v) => fx.copyWith(hue: v),
                    decimals: 0, suffix: "°"),
                _fxField("saturation", "Saturation", fx.saturation, -1, 1,
                    (v) => fx.copyWith(saturation: v)),
                _fxField("contrast", "Contrast", fx.contrast, -1, 1,
                    (v) => fx.copyWith(contrast: v)),
                _fxField("brightness", "Brightness", fx.brightness, -1, 1,
                    (v) => fx.copyWith(brightness: v)),
              ]),
          ],
        ),
      );
}
