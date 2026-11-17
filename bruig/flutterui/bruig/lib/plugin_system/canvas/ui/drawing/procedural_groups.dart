part of 'procedural_settings.dart';

// The look's settings, group by group. Part of ProceduralSettings: its fields,
// lifecycle and build are in procedural_settings.dart.

extension ProceduralGroups on ProceduralSettings {
  List<Widget> _groups(BuildContext context) => [
        CanvasControlGroup(label: label, hideCaption: label.isEmpty, children: [
          // See patternStyleDropdown.
          patternStyleDropdown(
            key: const ValueKey("backgroundStyle"),
            spec: spec,
            onChanged: _setNow,
          ),
          // The seed and its shuffle together: the number is seldom typed, but
          // pressed until something good appears, then written down.
          CanvasNumberField(
            label: "Seed",
            value: spec.seed.toDouble(),
            min: 0,
            max: 1000000,
            width: 62,
            onChanged: (v) => _set(spec.copyWith(seed: v.round())),
            onCommit: onCommit,
          ),
          CanvasIconButton(
            icon: Icons.casino_outlined,
            tooltip: "Try the next variation",
            onPressed: () => _setNow(spec.shuffled()),
          ),
          // Back to the beginning, beside the shuffle: the two ways out of a
          // pattern fiddled with past remembering.
          if (onReset != null && !layer)
            CanvasIconButton(
              key: const ValueKey("resetBackground"),
              icon: Icons.restart_alt,
              tooltip: "Put every setting here back to its default",
              onPressed: onReset,
            ),
          if (spec.style == ProceduralStyle.pitch)
            CanvasDropdown<PitchSport>(
              label: "Sport",
              value: spec.sport,
              width: 148,
              options: [for (var s in PitchSport.values) (s, s.label)],
              onChanged: (v) => _setNow(spec.copyWith(sport: v)),
            ),
        ]),
        if (looksFor(spec.style).isNotEmpty)
          CanvasExpander(
            label: "Looks",
            remember: "background.looks",
            initiallyOpen: true,
            trailing: lookMatching(spec)?.name ?? "Custom",
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: canvasGroupGap - 10),
                child: LooksGrid(
                  spec: spec,
                  onPick: (look) => _setNow(withLook(spec, look)),
                ),
              ),
            ],
          ),
        CanvasControlGroup(label: "Colours", children: [
          // All three colours at once, chosen to go together, or the app's own.
          patternPaletteDropdown(
            context,
            key: const ValueKey("backgroundPalette"),
            spec: spec,
            onChanged: _setNow,
          ),
          const CanvasLineBreak(),
          // The base colour and the one it fades to, both in the picker. A
          // layer's base is the background's, unless it is plain: a wash.
          if (!layer || spec.style == ProceduralStyle.plain)
            CanvasColorButton(
              label: "Base",
              color: spec.background,
              gradient: spec.gradient,
              onChanged: (c) => _setNow(spec.copyWith(background: c)),
              onGradientChanged: (g) => _setNow(g == null
                  ? spec.copyWith(flatBackground: true)
                  : spec.copyWith(gradient: g)),
            ),
          CanvasColorButton(
            label: "Main",
            color: spec.foreground,
            gradient: spec.foregroundFade,
            onChanged: (c) => _setNow(spec.copyWith(foreground: c)),
            onGradientChanged: (g) => _setNow(g == null
                ? spec.copyWith(flatForeground: true)
                : spec.copyWith(foregroundFade: g)),
          ),
          CanvasColorButton(
            label: "Accent",
            color: spec.accent,
            gradient: spec.accentFade,
            onChanged: (c) => _setNow(spec.copyWith(accent: c)),
            onGradientChanged: (g) => _setNow(g == null
                ? spec.copyWith(flatAccent: true)
                : spec.copyWith(accentFade: g)),
          ),
        ]),
        CanvasControlGroup(label: "Amount", children: [
          CanvasNumberField(
            label: "Density",
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            value: spec.density,
            onChanged: (v) {
              onBegin();
              _set(spec.copyWith(density: v));
            },
            onCommit: onCommit,
          ),
          // Size and Variation: the pattern's unit and how far it may differ
          // from itself. Not for Rings, which has its own width and jitter.
          if (spec.style != ProceduralStyle.rings &&
              spec.style != ProceduralStyle.pitch)
            CanvasNumberField(
              label: "Size",
              width: 62,
              value: spec.scale,
              min: 0.004,
              max: 0.25,
              decimals: 3,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(scale: v));
              },
              onCommit: onCommit,
            ),
          CanvasNumberField(
            label: "Brightness",
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            value: spec.intensity,
            onChanged: (v) {
              onBegin();
              _set(spec.copyWith(intensity: v));
            },
            onCommit: onCommit,
          ),
          if (spec.style != ProceduralStyle.rings)
            CanvasNumberField(
              label: "Variation",
              min: 0,
              max: 1,
              decimals: 2,
              width: 62,
              value: spec.variation,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(variation: v));
              },
              onCommit: onCommit,
            ),
          CanvasNumberField(
            label: "Rotation",
            value: spec.rotation,
            min: -360,
            max: 360,
            width: 54,
            suffix: "°",
            onChanged: (v) => _set(spec.copyWith(rotation: v)),
            onCommit: onCommit,
          ),
        ]),
        ..._ownGroups(),
        if (spec.style.usesGlyphs) _symbols(),
        // Metal's own settings: brushing and rust have no name among the five.
        if (spec.style == ProceduralStyle.metal) _metalGroup(),
        // Rings' own settings: where each ring starts and ends, and between.
        if (spec.style == ProceduralStyle.rings) ...[
          // Later sections stay shut until wanted: seventeen number fields,
          // each with state, focus node and controller, cost 40 ms a build.
          CanvasControlGroup(label: "Rings", children: [
            CanvasNumberField(
              key: const ValueKey("ringCount"),
              label: "How many",
              value: rings.count.toDouble(),
              min: 1,
              max: 200,
              width: 54,
              onChanged: (v) => _rings(rings.copyWith(count: v.round())),
              onCommit: onCommit,
            ),
            CanvasNumberField(
              key: const ValueKey("ringWidth"),
              label: "Width",
              decimals: 4,
              width: 66,
              // A thousandth a pixel, not the ten-thousandth the digits imply:
              // across a fifth of the page the last digit is two thousand
              // pixels of drag. Shift gives ten-thousandths.
              step: 0.001,
              value: rings.width,
              min: 0.0005,
              max: 0.2,
              onChanged: (v) {
                onBegin();
                _rings(rings.copyWith(width: v));
              },
              onCommit: onCommit,
            ),
            CanvasNumberField(
              key: const ValueKey("ringAccentEvery"),
              label: "Accent every",
              value: rings.accentEvery.toDouble(),
              min: 0,
              max: 50,
              width: 54,
              onChanged: (v) => _rings(rings.copyWith(accentEvery: v.round())),
              onCommit: onCommit,
            ),
            CanvasNumberField(
              key: const ValueKey("ringSpacing"),
              label: "Spacing",
              decimals: 2,
              width: 62,
              value: rings.spacing,
              min: 0.05,
              max: 0.95,
              onChanged: (v) {
                onBegin();
                _rings(rings.copyWith(spacing: v));
              },
              onCommit: onCommit,
            ),
          ]),
          CanvasExpander(
              label: "Where they run",
              remember: "rings.where",
              children: [
                CanvasControlGroup(
                    label: "Where they run",
                    hideCaption: true,
                    children: [
                      // Each end captioned by where a ring sets off:
                      // shrinking runs backwards, so the near end is where
                      // it arrives. Captioned the other way, sets get built
                      // that begin off the page.
                      for (var near in [!rings.inward, rings.inward])
                        if (near)
                          CanvasNumberField(
                            key: const ValueKey("ringFrom"),
                            label: rings.inward ? "Ends at" : "Starts at",
                            decimals: 2,
                            width: 62,
                            value: rings.from,
                            min: 0,
                            max: 2,
                            onChanged: (v) {
                              onBegin();
                              _rings(rings.copyWith(from: v));
                            },
                            onCommit: onCommit,
                          )
                        else
                          CanvasNumberField(
                            key: const ValueKey("ringTo"),
                            label: rings.inward ? "Starts at" : "Ends at",
                            decimals: 2,
                            width: 62,
                            value: rings.to,
                            min: 0,
                            max: 2,
                            onChanged: (v) {
                              onBegin();
                              _rings(rings.copyWith(to: v));
                            },
                            onCommit: onCommit,
                          ),
                      CanvasNumberField(
                        key: const ValueKey("ringCentreX"),
                        label: "From across",
                        decimals: 2,
                        width: 62,
                        value: rings.centreX,
                        min: -0.5,
                        max: 1.5,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(centreX: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringCentreY"),
                        label: "From down",
                        decimals: 2,
                        width: 62,
                        value: rings.centreY,
                        min: -0.5,
                        max: 1.5,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(centreY: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasToggle(
                        key: const ValueKey("ringInward"),
                        label: "Shrink",
                        value: rings.inward,
                        onChanged: (v) => _ringsNow(rings.copyWith(inward: v)),
                      ),
                      const CanvasHint(
                          "Nought is the middle of the page and one is its furthest "
                          "corner, so a ring that ends at one has left the picture. "
                          "Shrink runs the same journey backwards."),
                    ]),
              ]),
          CanvasExpander(
              label: "Arriving and leaving",
              remember: "rings.fade",
              children: [
                CanvasControlGroup(
                    label: "Arriving and leaving",
                    hideCaption: true,
                    children: [
                      CanvasToggle(
                        key: const ValueKey("ringBuildUp"),
                        label: "Build up",
                        value: rings.buildUp,
                        onChanged: (v) => _ringsNow(rings.copyWith(buildUp: v)),
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringFadeIn"),
                        label: "Fade in",
                        decimals: 2,
                        width: 62,
                        value: rings.fadeIn,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(fadeIn: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringFadeOut"),
                        label: "Fade out",
                        decimals: 2,
                        width: 62,
                        value: rings.fadeOut,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(fadeOut: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasDropdown<RingEdge>(
                        key: const ValueKey("ringEdge"),
                        label: "Edge",
                        value: rings.edge,
                        width: 92,
                        options: [for (var e in RingEdge.values) (e, e.label)],
                        onChanged: (v) => _ringsNow(rings.copyWith(edge: v)),
                      ),
                      const CanvasHint(
                          "Fade in and out are what happens at the two ends "
                          "of one ring's life. Build up is what happens at "
                          "the start of the animation: the page begins empty "
                          "and the rings arrive one at a time, rather than "
                          "opening on a set that is already there."),
                    ]),
              ]),
          CanvasExpander(
              label: "How much they differ",
              remember: "rings.jitter",
              children: [
                CanvasControlGroup(
                    label: "How much they differ",
                    hideCaption: true,
                    children: [
                      CanvasNumberField(
                        key: const ValueKey("ringSpacingJitter"),
                        label: "Spacing",
                        decimals: 2,
                        width: 62,
                        value: rings.spacingJitter,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(spacingJitter: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringWidthJitter"),
                        label: "Width",
                        decimals: 2,
                        width: 62,
                        value: rings.widthJitter,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(widthJitter: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringColorJitter"),
                        label: "Colour",
                        decimals: 2,
                        width: 62,
                        value: rings.colorJitter,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(colorJitter: v));
                        },
                        onCommit: onCommit,
                      ),
                    ]),
              ]),
          CanvasExpander(
              label: "Texture",
              remember: "rings.texture",
              children: [
                CanvasControlGroup(
                    label: "Texture",
                    hideCaption: true,
                    children: [
                      CanvasNumberField(
                        key: const ValueKey("ringNoise"),
                        label: "Noise",
                        decimals: 2,
                        width: 62,
                        value: rings.noise,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(noise: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringGlitch"),
                        label: "Glitch",
                        decimals: 2,
                        width: 62,
                        value: rings.glitch,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(glitch: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringDistortion"),
                        label: "Distortion",
                        decimals: 2,
                        width: 62,
                        value: rings.distortion,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(distortion: v));
                        },
                        onCommit: onCommit,
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringGrunge"),
                        label: "Grunge",
                        decimals: 2,
                        width: 62,
                        value: rings.grunge,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          onBegin();
                          _rings(rings.copyWith(grunge: v));
                        },
                        onCommit: onCommit,
                      ),
                    ]),
              ]),
          // What the rings carry: its own heading, shut until wanted, with room
          // under it so two headings do not read as one section.
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CanvasExpander(
              label: "Icons",
              remember: "rings.icons",
              trailing: rings.icons.isEmpty ? null : "${rings.icons.length}",
              children: [
                // Two and no more: one in the middle, one set round a ring.
                // More pictures join that set; they make no more sets.
                for (var place in RingIconPlace.values) ...[
                  if (place != RingIconPlace.values.first)
                    const CanvasSeparator(),
                  CanvasControlGroup(
                    label: place.label,
                    children: _iconSlot(context, rings, place),
                  ),
                ],
              ],
            ),
          ),
        ],
        _effects(),
        // A layer keeps the background's time, at a pace of its own.
        if (layer && spec.style.canAnimate)
          CanvasControlGroup(label: "Movement", children: [
            CanvasNumberField(
              key: const ValueKey("layerSpeed"),
              label: "Speed",
              decimals: 2,
              width: 62,
              value: spec.speed,
              min: 0,
              max: 6,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(speed: v));
              },
              onCommit: onCommit,
            ),
          ]),
        if (!layer && spec.style.canAnimate)
          CanvasControlGroup(label: "Movement", children: [
            CanvasToggle(
              key: const ValueKey("animate"),
              label: "Animate",
              value: spec.animated,
              onChanged: (v) => _setNow(spec.copyWith(animated: v)),
            ),
            // How many runs, and the rest between them. Nought times is for
            // ever, so there is no Loop switch. Either makes the movement
            // counted, so Frames replaces Speed.
            if (spec.animated) ...[
              CanvasNumberField(
                key: const ValueKey("loopTimes"),
                label: "Times",
                width: 54,
                value: spec.loopTimes.toDouble(),
                min: 0,
                max: 100000,
                onChanged: (v) {
                  onBegin();
                  _set(spec.copyWith(loopTimes: v.round()));
                },
                onCommit: onCommit,
              ),
              CanvasNumberField(
                key: const ValueKey("loopGap"),
                label: "Gap",
                width: 54,
                value: spec.loopGap.toDouble(),
                min: 0,
                max: 100000,
                onChanged: (v) {
                  onBegin();
                  _set(spec.copyWith(loopGap: v.round()));
                },
                onCommit: onCommit,
              ),
            ],
            if (spec.animated && !spec.inRuns)
              CanvasNumberField(
                key: const ValueKey("speed"),
                label: "Speed",
                decimals: 2,
                width: 62,
                value: spec.speed,
                min: 0.05,
                max: 6,
                onChanged: (v) {
                  onBegin();
                  _set(spec.copyWith(speed: v));
                },
                onCommit: onCommit,
              ),
            // A loop that comes back to where it began, for an export that
            // goes round without a jump. See paintProcedural.
            if (spec.animated && !spec.inRuns) ...[
              CanvasNumberField(
                key: const ValueKey("seamlessFrames"),
                label: "Loop every",
                width: 62,
                value: spec.loopFrames.toDouble(),
                min: 0,
                max: 100000,
                onChanged: (v) {
                  onBegin();
                  _set(spec.copyWith(loopFrames: v.round()));
                },
                onCommit: onCommit,
              ),
              if (canvasFrames != null)
                CanvasIconButton(
                  key: const ValueKey("seamlessFit"),
                  icon: Icons.all_inclusive,
                  tooltip: "Loop the canvas",
                  onPressed: () =>
                      _setNow(spec.copyWith(loopFrames: canvasFrames)),
                ),
              if (spec.loopFrames > 0)
                CanvasNumberField(
                  key: const ValueKey("seamlessBlend"),
                  label: "Blend",
                  decimals: 2,
                  width: 58,
                  value: spec.loopBlend,
                  min: 0.02,
                  max: 1,
                  onChanged: (v) {
                    onBegin();
                    _set(spec.copyWith(loopBlend: v));
                  },
                  onCommit: onCommit,
                ),
            ],
            if (spec.inRuns) ...[
              CanvasNumberField(
                key: const ValueKey("passFrames"),
                label: "Frames",
                width: 62,
                value: spec.passFrames.toDouble(),
                min: 1,
                max: 100000,
                onChanged: (v) {
                  onBegin();
                  _set(spec.copyWith(passFrames: v.round()));
                },
                onCommit: onCommit,
              ),
              // Fit the run to what it is under: a movement ending after the
              // last frame is never seen to end.
              if (canvasFrames != null)
                CanvasIconButton(
                  key: const ValueKey("passFramesFit"),
                  icon: Icons.fit_screen_outlined,
                  tooltip: "Make one run the length of the canvas "
                      "($canvasFrames frames)",
                  onPressed: () =>
                      _setNow(spec.copyWith(passFrames: canvasFrames)),
                ),
              const CanvasHint(
                  "How many frames one run takes, start to finish. Finished "
                  "means finished: for rings, every ring born, travelled and "
                  "gone, with nothing left on the page. Times is how many "
                  "runs there are -- nought is for ever -- and Gap is how "
                  "many frames of stillness sit between one and the next."),
            ],
            // A rest: the frame it stops on, how long it stays, and how long it
            // eases in and out. The pattern's clock is held while the
            // document's runs, so it picks up where it left off.
            if (spec.animated) ...[
              // On a line of their own: where it rests is a separate question.
              const CanvasLineBreak(),
              CanvasNumberField(
                key: const ValueKey("pauseAt"),
                label: "Pause at",
                width: 58,
                value: spec.pauseAt.toDouble(),
                min: 0,
                max: 100000,
                onChanged: (v) {
                  onBegin();
                  _set(spec.copyWith(pauseAt: v.round()));
                },
                onCommit: onCommit,
              ),
              CanvasNumberField(
                key: const ValueKey("pauseFor"),
                label: "Paused for",
                width: 58,
                value: spec.pauseFor.toDouble(),
                min: 0,
                max: 100000,
                onChanged: (v) {
                  onBegin();
                  _set(spec.copyWith(pauseFor: v.round()));
                },
                onCommit: onCommit,
              ),
              if (spec.pauseFor > 0)
                CanvasNumberField(
                  key: const ValueKey("pauseEase"),
                  label: "Easing",
                  width: 58,
                  value: spec.pauseEase.toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: (v) {
                    onBegin();
                    _set(spec.copyWith(pauseEase: v.round()));
                  },
                  onCommit: onCommit,
                ),
            ],
          ]),
        // The light, which every style has: shut until wanted, as most
        // backgrounds are unlit.
        if (!layer)
          CanvasExpander(
            label: "Lights",
            remember: "background.light",
            trailing: light.on ? "Spotlight" : "None",
            children: [
              CanvasControlGroup(label: "Lights", hideCaption: true, children: [
                CanvasToggle(
                  key: const ValueKey("lightOn"),
                  label: "Spotlight",
                  value: light.on,
                  onChanged: (v) => _lightNow(light.copyWith(on: v)),
                ),
                if (!light.on)
                  const CanvasHint("A single light thrown over the background, "
                      "whichever one it is. A pattern lit from somewhere reads "
                      "as a place rather than as wallpaper."),
                if (light.on) ...[
                  CanvasColorButton(
                    key: const ValueKey("lightColour"),
                    label: "Colour",
                    color: light.color,
                    onChanged: (c) => _lightNow(light.copyWith(color: c)),
                  ),
                  CanvasNumberField(
                    key: const ValueKey("lightBrightness"),
                    label: "Brightness",
                    value: light.brightness,
                    min: 0,
                    max: 2,
                    decimals: 2,
                    width: 62,
                    onChanged: (v) {
                      onBegin();
                      _light(light.copyWith(brightness: v));
                    },
                    onCommit: onCommit,
                  ),
                  CanvasNumberField(
                    key: const ValueKey("lightSize"),
                    label: "Size",
                    value: light.size,
                    min: 0.02,
                    max: 3,
                    decimals: 2,
                    width: 62,
                    onChanged: (v) {
                      onBegin();
                      _light(light.copyWith(size: v));
                    },
                    onCommit: onCommit,
                  ),
                  CanvasNumberField(
                    key: const ValueKey("lightFalloff"),
                    label: "Falloff",
                    value: light.falloff,
                    min: 0,
                    max: 1,
                    decimals: 2,
                    width: 62,
                    onChanged: (v) {
                      onBegin();
                      _light(light.copyWith(falloff: v));
                    },
                    onCommit: onCommit,
                  ),
                  const CanvasLineBreak(),
                  // A fraction of the frame, not pixels, so a light stays put
                  // in a bigger export.
                  CanvasNumberField(
                    key: const ValueKey("lightX"),
                    label: "X",
                    value: light.x,
                    min: -1,
                    max: 2,
                    decimals: 2,
                    width: 58,
                    onChanged: (v) {
                      onBegin();
                      _light(light.copyWith(x: v));
                    },
                    onCommit: onCommit,
                  ),
                  CanvasNumberField(
                    key: const ValueKey("lightY"),
                    label: "Y",
                    value: light.y,
                    min: -1,
                    max: 2,
                    decimals: 2,
                    width: 58,
                    onChanged: (v) {
                      onBegin();
                      _light(light.copyWith(y: v));
                    },
                    onCommit: onCommit,
                  ),
                  CanvasNumberField(
                    key: const ValueKey("lightDirection"),
                    label: "Direction",
                    value: light.direction,
                    min: -360,
                    max: 360,
                    width: 58,
                    suffix: "°",
                    onChanged: (v) {
                      onBegin();
                      _light(light.copyWith(direction: v));
                    },
                    onCommit: onCommit,
                  ),
                  CanvasNumberField(
                    key: const ValueKey("lightReach"),
                    label: "Reach",
                    value: light.reach,
                    min: 0,
                    max: 1,
                    decimals: 2,
                    width: 58,
                    onChanged: (v) {
                      onBegin();
                      _light(light.copyWith(reach: v));
                    },
                    onCommit: onCommit,
                  ),
                  CanvasHint(light.reach > 0
                      ? "Direction is which way the light is thrown, off a "
                          "compass. Reach is how far it rakes across the "
                          "surface, and the pool is thrown forward from X and "
                          "Y rather than sitting in the middle of it."
                      : "A light shone straight on lands as a circle whichever "
                          "way it is pointed. Turn Reach up to rake it across "
                          "the surface and the direction starts to show."),
                ],
              ]),
            ],
          ),
      ];
}
