import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// procedural_settings.dart is the controls for a generated background.
//
// The same widget serves both places a generator can be pointed: the canvas's
// own background and a background element. That is deliberate -- they are one
// recipe with one set of controls, and a reader who has learned to build a
// matrix rain on the canvas should not meet a different panel when they put
// one behind a title.
//
// The controls are the five shared ones (density, scale, intensity, variation,
// seed) plus the colours, and they are shown for every style. A generator that
// ignored one of them would leave a slider doing nothing, which is why each
// generator is written to make all five mean something -- see
// render/procedural/generators.dart.

/// ProceduralSettings edits a [ProceduralSpec].
class ProceduralSettings extends StatelessWidget {
  final ProceduralSpec spec;
  final ValueChanged<ProceduralSpec> onChanged;
  final VoidCallback onBegin;
  final VoidCallback onCommit;

  /// onReset puts the whole thing back to its default, where the caller has
  /// something for that to mean. Null leaves the button out.
  final VoidCallback? onReset;

  /// label names the group.
  ///
  /// Empty by default, and empty is what both callers want: the panel's own
  /// header says whether these are the canvas's background or an element's,
  /// and a caption underneath repeating it is the word twice. It stays a
  /// parameter because a third place showing these would need one.
  final String label;

  const ProceduralSettings({
    required this.spec,
    required this.onChanged,
    required this.onBegin,
    required this.onCommit,
    this.onReset,
    this.label = "",
    super.key,
  });

  void _set(ProceduralSpec next) => onChanged(next);

  /// _rings and _ringsNow are _set and _setNow for the Rings style's own
  /// settings, which live in a spec of their own. See RingSpec.
  void _rings(RingSpec next) => _set(spec.copyWith(rings: next));
  void _ringsNow(RingSpec next) => _setNow(spec.copyWith(rings: next));

  void _setNow(ProceduralSpec next) {
    onBegin();
    onChanged(next);
    onCommit();
  }

  @override
  Widget build(BuildContext context) {
    var groups = _groups();
    // Down the column like every other element's settings. A Row of five
    // groups in a 280px sidebar is a thousand pixels of overflow, and it does
    // not shrink -- the groups are sized to their controls.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: groups);
  }

  RingSpec get rings => spec.rings;

  List<Widget> _groups() => [
        CanvasControlGroup(label: label, hideCaption: label.isEmpty, children: [
          CanvasDropdown<ProceduralStyle>(
            label: "Style",
            value: spec.style,
            width: 138,
            options: [for (var s in ProceduralStyle.values) (s, s.label)],
            onChanged: (v) => _setNow(spec.copyWith(style: v)),
          ),
          // The seed and its shuffle sit together, because the number is
          // almost never typed -- what it is for is pressing the button
          // until something good appears, and then being able to write down
          // which one it was.
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
          // Back to the beginning. Beside the shuffle because they are the
          // two ways out of a pattern that has been fiddled with past the
          // point of remembering what it was -- one goes somewhere new, this
          // one goes back.
          if (onReset != null)
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
        CanvasControlGroup(label: "Colours", children: [
          CanvasColorButton(
            label: "Base",
            color: spec.background,
            onChanged: (c) => _setNow(spec.copyWith(background: c)),
          ),
          CanvasColorButton(
            label: "Main",
            color: spec.foreground,
            onChanged: (c) => _setNow(spec.copyWith(foreground: c)),
          ),
          CanvasColorButton(
            label: "Accent",
            color: spec.accent,
            onChanged: (c) => _setNow(spec.copyWith(accent: c)),
          ),
          CanvasToggle(
            label: "Gradient",
            value: spec.gradient,
            onChanged: (v) => _setNow(spec.copyWith(gradient: v)),
          ),
          if (spec.gradient) ...[
            CanvasColorButton(
              label: "To",
              color: spec.gradientTo,
              onChanged: (c) => _setNow(spec.copyWith(gradientTo: c)),
            ),
            CanvasNumberField(
              label: "Angle",
              value: spec.gradientAngle,
              min: -360,
              max: 360,
              width: 54,
              suffix: "°",
              onChanged: (v) => _set(spec.copyWith(gradientAngle: v)),
              onCommit: onCommit,
            ),
          ],
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
          // Size and Variation are the pattern's own unit and how far it is
          // allowed to differ from itself -- which the Rings style says in
          // its own words instead, as a width and three amounts of jitter.
          // Offered here as well, they were two controls that did nothing at
          // all on that style.
          if (spec.style != ProceduralStyle.rings)
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
        if (spec.style.usesGlyphs)
          CanvasControlGroup(label: "Symbols", children: [
            // The whole set as one string, so adding a character means
            // typing it. A picker of symbol categories would be a longer
            // walk to the same place, and would not let somebody use their
            // own initials as the rain.
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
          ]),
        // The Rings style's own settings. Its own group rather than more of
        // the shared five, because what a set of rings raises -- where each
        // one starts, where it ends, and what happens to it on the way -- is
        // not a question any other style has.
        if (spec.style == ProceduralStyle.rings) ...[
          // The four sections after the first are behind headings, and shut
          // until they are wanted: seventeen number fields is seventeen text
          // fields with their own state, their own focus node and their own
          // editing controller, and building them all costs forty
          // milliseconds of every build of this panel -- which is every time
          // the page is opened and every time the canvas changes. The squad
          // list is behind a heading for the same reason.
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
                      CanvasNumberField(
                        key: const ValueKey("ringFrom"),
                        label: "Starts at",
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
                      ),
                      CanvasNumberField(
                        key: const ValueKey("ringTo"),
                        label: "Ends at",
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
        ],
        if (spec.style.canAnimate)
          CanvasControlGroup(label: "Movement", children: [
            CanvasToggle(
              key: const ValueKey("animate"),
              label: "Animate",
              value: spec.animated,
              onChanged: (v) => _setNow(spec.copyWith(animated: v)),
            ),
            // Beside Animate, because it is the second half of the same
            // question: whether it moves, and whether it goes on moving.
            if (spec.animated)
              CanvasToggle(
                key: const ValueKey("loop"),
                label: "Loop",
                value: spec.loop,
                onChanged: (v) => _setNow(spec.copyWith(loop: v)),
              ),
            // How fast, or how long: they are the same question asked of two
            // different things. A movement that goes round for ever has a
            // speed; one that runs once is timed against whatever it is
            // under, and that is counted in frames.
            if (spec.animated && spec.loop)
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
            if (spec.animated && !spec.loop) ...[
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
              const CanvasHint(
                  "How many frames the movement takes from start to finish, "
                  "after which it holds. Finished means finished: for rings, "
                  "every ring born, travelled and gone, with nothing left on "
                  "the page."),
            ],
          ]),
      ];
}
