import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
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

  /// canvasFrames is how long the canvas is, for the button that makes one
  /// run of the movement fit it. Null where the caller has no such thing to
  /// offer.
  final int? canvasFrames;

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
    this.canvasFrames,
    this.label = "",
    super.key,
  });

  void _set(ProceduralSpec next) => onChanged(next);

  /// _rings and _ringsNow are _set and _setNow for the Rings style's own
  /// settings, which live in a spec of their own. See RingSpec.
  void _rings(RingSpec next) => _set(spec.copyWith(rings: next));

  void _ringsNow(RingSpec next) => _setNow(spec.copyWith(rings: next));

  /// _put is the icon for one of the two placings, replaced or taken away.
  ///
  /// One of each, kept in the order the two placings are written in: a
  /// document that carries more than one of a placing -- there used to be a
  /// button for it -- is collapsed to the first of them the moment anything
  /// is touched.
  void _put(RingSpec rings, RingIconPlace place, RingIcon? next) {
    var kept = {
      for (var p in RingIconPlace.values)
        p: p == place
            ? next
            : rings.icons.where((icon) => icon.place == p).firstOrNull,
    };
    _ringsNow(rings.copyWith(icons: [
      for (var p in RingIconPlace.values)
        if (kept[p] != null) kept[p]!,
    ]));
  }

  /// _iconSlot is one of the two: the picture, what it is drawn like, and --
  /// around a ring -- the other pictures it may be drawn as and how far each
  /// of them is allowed to differ from the rest.
  List<Widget> _iconSlot(
      BuildContext context, RingSpec rings, RingIconPlace place) {
    var at = place.name;
    var icon = rings.icons.where((i) => i.place == place).firstOrNull;
    var around = place == RingIconPlace.around;

    void set(RingIcon next) => _put(rings, place, next);

    // Nothing chosen yet: the two ways of choosing one, and what it would do.
    if (icon == null) {
      return [
        CanvasIconButton(
          key: ValueKey("ringIconPick-$at"),
          icon: Icons.add_photo_alternate,
          tooltip: "Choose a picture from a file",
          onPressed: () async {
            var id = await pickCanvasImage(context);
            if (id == null) return;
            set(RingIcon(asset: id, place: place));
          },
        ),
        CanvasIconButton(
          key: ValueKey("ringIconLibrary-$at"),
          icon: Icons.photo_library_outlined,
          tooltip: "Use a picture you have already added",
          onPressed: () async {
            var id = await showRecentPictures(context);
            if (id == null) return;
            set(RingIcon(asset: id, place: place));
          },
        ),
        CanvasHint(around
            ? "Pictures spaced around a ring like beads on it, each turned to "
                "face out of it. They inherit the ring: where it is, how big "
                "it has grown and how far through its fade it is."
            : "One picture in the middle of the rings, sized against the ring "
                "it is tied to -- so it arrives, swells and dissolves with "
                "it."),
      ];
    }

    return [
      CanvasIconButton(
        key: ValueKey("ringIconPick-$at"),
        icon: Icons.image_outlined,
        tooltip: "Choose a different picture from a file",
        onPressed: () async {
          var id = await pickCanvasImage(context);
          if (id == null) return;
          set(icon.copyWith(asset: id));
        },
      ),
      // And out of the pictures this canvas already has, which is where an
      // icon usually comes from: the badge is already in the folder, and
      // going and finding the file again is the long way round.
      CanvasIconButton(
        key: ValueKey("ringIconLibrary-$at"),
        icon: Icons.photo_library_outlined,
        tooltip: "Use a picture you have already added",
        onPressed: () async {
          var id = await showRecentPictures(context);
          if (id == null) return;
          set(icon.copyWith(asset: id));
        },
      ),
      CanvasNumberField(
        key: ValueKey("ringIconRing-$at"),
        label: "On ring",
        width: 54,
        value: icon.ring.toDouble(),
        // Nought is no ring at all, for the one in the middle: a picture tied
        // to the movement rather than to a ring, which is the only way to
        // have one that is simply there while rings come and go.
        min: around ? 1 : 0,
        max: 200,
        onChanged: (v) => set(icon.copyWith(ring: v.round())),
        onCommit: onCommit,
      ),
      if (!around && icon.ring <= 0)
        const CanvasHint(
            "On no ring. It lives the length of one run rather than of a "
            "ring, and its size is a fraction of the page rather than of a "
            "radius. With both fades held it is simply there, for the whole "
            "animation."),
      if (around)
        CanvasNumberField(
          key: ValueKey("ringIconCount-$at"),
          label: "How many",
          width: 54,
          value: icon.count.toDouble(),
          min: 1,
          max: 60,
          onChanged: (v) => set(icon.copyWith(count: v.round())),
          onCommit: onCommit,
        ),
      CanvasNumberField(
        key: ValueKey("ringIconSize-$at"),
        label: "Size",
        decimals: 2,
        width: 58,
        value: icon.size,
        min: 0.01,
        max: 4,
        onChanged: (v) {
          onBegin();
          set(icon.copyWith(size: v));
        },
        onCommit: onCommit,
      ),
      CanvasNumberField(
        key: ValueKey("ringIconTurn-$at"),
        label: "Turn",
        width: 54,
        suffix: "\u00b0",
        value: icon.turn,
        min: -360,
        max: 360,
        onChanged: (v) {
          onBegin();
          set(icon.copyWith(turn: v));
        },
        onCommit: onCommit,
      ),
      // One colour rather than its own, which is what a line drawing usually
      // wants: an SVG carried by a ring should be the colour of the design
      // rather than whatever it was drawn in.
      CanvasToggle(
        key: ValueKey("ringIconTinted-$at"),
        label: "Colour it",
        value: icon.tinted,
        onChanged: (v) => set(icon.copyWith(tinted: v)),
      ),
      if (icon.tinted)
        CanvasColorButton(
          key: ValueKey("ringIconTint-$at"),
          label: "Colour",
          color: icon.tint,
          onChanged: (c) => set(icon.copyWith(tint: c)),
        ),
      CanvasIconButton(
        key: ValueKey("ringIconRemove-$at"),
        icon: Icons.close,
        tooltip: "Take this picture off the rings",
        onPressed: () => _put(rings, place, null),
      ),
      if (around) ...[
        // What it may be drawn as instead, and how often. Six of one picture
        // round a ring is a pattern; a crest, a ball and a boot is a set.
        const CanvasLineBreak(),
        for (var (n, pick) in icon.also.indexed) ...[
          CanvasIconButton(
            key: ValueKey("ringIconAlsoPick-$at$n"),
            icon: pick.asset.isEmpty
                ? Icons.add_photo_alternate
                : Icons.image_outlined,
            tooltip: "Choose this picture from a file",
            onPressed: () async {
              var id = await pickCanvasImage(context);
              if (id == null) return;
              set(_withPick(icon, n, pick.copyWith(asset: id)));
            },
          ),
          CanvasIconButton(
            key: ValueKey("ringIconAlsoLibrary-$at$n"),
            icon: Icons.photo_library_outlined,
            tooltip: "Use a picture you have already added",
            onPressed: () async {
              var id = await showRecentPictures(context);
              if (id == null) return;
              set(_withPick(icon, n, pick.copyWith(asset: id)));
            },
          ),
          CanvasNumberField(
            key: ValueKey("ringIconAlsoWeight-$at$n"),
            label: "How often",
            decimals: 1,
            width: 58,
            value: pick.weight,
            min: 0,
            max: 100,
            onChanged: (v) {
              onBegin();
              set(_withPick(icon, n, pick.copyWith(weight: v)));
            },
            onCommit: onCommit,
          ),
          CanvasIconButton(
            key: ValueKey("ringIconAlsoRemove-$at$n"),
            icon: Icons.close,
            tooltip: "Stop using this picture",
            onPressed: () => set(icon.copyWith(also: [
              for (var (m, other) in icon.also.indexed)
                if (m != n) other,
            ])),
          ),
          // A line each: two pictures' buttons side by side are four buttons
          // in a row, and which of them belongs to which is a guess.
          const CanvasLineBreak(),
        ],
        // The first picture's own share, which only means anything once there
        // is something to share with.
        if (icon.also.isNotEmpty)
          CanvasNumberField(
            key: ValueKey("ringIconWeight-$at"),
            label: "First one",
            decimals: 1,
            width: 58,
            value: icon.weight,
            min: 0,
            max: 100,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(weight: v));
            },
            onCommit: onCommit,
          ),
        CanvasIconButton(
          key: ValueKey("ringIconAlsoAdd-$at"),
          icon: Icons.library_add_outlined,
          tooltip: "Another picture to use around this ring",
          onPressed: () =>
              set(icon.copyWith(also: [...icon.also, const RingPick()])),
        ),
        if (icon.also.isNotEmpty)
          const CanvasHint(
              "Each place around the ring takes one of these pictures at "
              "random. How often is how much of the draw it gets: one at two "
              "comes up twice as often as one at one, and one at nought "
              "never."),
        // How far each one is allowed to differ from the rest, which is the
        // difference between pictures threaded on a wire and pictures that
        // happen to be near a ring.
        const CanvasLineBreak(),
        ..._drift(icon, place, "When", "Time", icon.driftWhen,
            (d) => icon.copyWith(driftWhen: d)),
        ..._drift(icon, place, "Where", "Position", icon.driftWhere,
            (d) => icon.copyWith(driftWhere: d)),
        ..._drift(icon, place, "Size", "Size", icon.driftSize,
            (d) => icon.copyWith(driftSize: d),
            limit: 4),
        ..._drift(icon, place, "Turn", "Turn", icon.driftTurn,
            (d) => icon.copyWith(driftTurn: d),
            limit: 360, decimals: 0, suffix: "\u00b0"),
        // A share of what the ring is drawn at rather than something added to
        // it, so nought is invisible and one is the ring's own strength.
        // Never more than the ring: the other way round had a dead half,
        // since a ring already at full strength cannot be made brighter.
        ..._drift(icon, place, "Fade", "Fade", icon.driftFade,
            (d) => icon.copyWith(driftFade: d),
            least: 0),
        const CanvasHint(
            "How far each of these pictures is allowed to differ from the "
            "rest, and every one of them takes its own place in the range. "
            "Time is measured in the ring's life, so a picture moved through "
            "it sits off the line -- ahead of the ring or behind it -- and "
            "arrives and leaves at its own moment. One moved past either end "
            "of the life is not born yet, or gone. Position is measured in "
            "the gap to the next picture. Size is added to one: a half is "
            "half as big again. Fade is a share of the strength its ring is "
            "drawn at, so a half is half of it and nought is nothing."),
      ],
      // The things a picture in the middle may be told rather than inheriting
      // from its ring. Each is off until it is switched on, and off is
      // inherit. Only in the middle: one of a set going round a ring differs
      // from its neighbours by the ranges above, and telling the whole set
      // one strength is what those ranges are for.
      if (!around) ...[
        const CanvasLineBreak(),
        CanvasToggle(
          key: ValueKey("ringIconOwnFade-$at"),
          label: "Own opacity",
          value: icon.opacity != null,
          onChanged: (v) =>
              set(icon.copyWith(setOpacity: true, opacity: v ? 1.0 : null)),
        ),
        if (icon.opacity != null)
          CanvasNumberField(
            key: ValueKey("ringIconOpacity-$at"),
            label: "Opacity",
            decimals: 2,
            width: 58,
            value: icon.opacity!,
            min: 0,
            max: 1,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(setOpacity: true, opacity: v));
            },
            onCommit: onCommit,
          ),
        CanvasToggle(
          key: ValueKey("ringIconOwnSmallest-$at"),
          label: "Smallest",
          value: icon.smallest != null,
          onChanged: (v) =>
              set(icon.copyWith(setSmallest: true, smallest: v ? 0.1 : null)),
        ),
        if (icon.smallest != null)
          CanvasNumberField(
            key: ValueKey("ringIconSmallest-$at"),
            label: "No smaller than",
            decimals: 2,
            width: 58,
            value: icon.smallest!,
            min: 0,
            max: 4,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(setSmallest: true, smallest: v));
            },
            onCommit: onCommit,
          ),
        CanvasToggle(
          key: ValueKey("ringIconOwnLargest-$at"),
          label: "Largest",
          value: icon.largest != null,
          onChanged: (v) =>
              set(icon.copyWith(setLargest: true, largest: v ? 0.4 : null)),
        ),
        if (icon.largest != null)
          CanvasNumberField(
            key: ValueKey("ringIconLargest-$at"),
            label: "No bigger than",
            decimals: 2,
            width: 58,
            value: icon.largest!,
            min: 0,
            max: 4,
            onChanged: (v) {
              onBegin();
              set(icon.copyWith(setLargest: true, largest: v));
            },
            onCommit: onCommit,
          ),
        CanvasToggle(
          key: ValueKey("ringIconHoldIn-$at"),
          label: "No fade in",
          value: icon.holdIn,
          onChanged: (v) => set(icon.copyWith(holdIn: v)),
        ),
        CanvasToggle(
          key: ValueKey("ringIconHoldOut-$at"),
          label: "No fade out",
          value: icon.holdOut,
          onChanged: (v) => set(icon.copyWith(holdOut: v)),
        ),
        CanvasToggle(
          key: ValueKey("ringIconFirstRun-$at"),
          label: "First run only",
          value: icon.firstRunOnly,
          onChanged: (v) => set(icon.copyWith(firstRunOnly: v)),
        ),
        const CanvasHint(
            "Off, each of these is inherited from the ring the picture is "
            "tied to. Own opacity draws it at one strength whatever the ring "
            "is doing. Smallest and largest hold its size between two "
            "fractions of the page, so it stops growing with the ring rather "
            "than growing out of the picture. The two fades leave out the "
            "ring's arrival or its departure, and first run only says it "
            "once."),
      ],
    ];
  }

  /// _withPick is [icon] with one of its other pictures replaced.
  RingIcon _withPick(RingIcon icon, int which, RingPick next) =>
      icon.copyWith(also: [
        for (var (n, pick) in icon.also.indexed)
          if (n == which) next else pick,
      ]);

  /// _drift is the two ends of one of an icon's scatter ranges.
  ///
  /// A pair rather than one number, because the useful thing to say is
  /// usually lopsided: a little smaller and a lot bigger, late but never
  /// early. See RingDrift.
  List<Widget> _drift(
    RingIcon icon,
    RingIconPlace place,
    String name,
    String label,
    RingDrift value,
    RingIcon Function(RingDrift) put, {
    double limit = 1,
    double? least,
    int decimals = 2,
    String suffix = "",
  }) =>
      [
        for (var (which, end) in [("Least", value.least), ("Most", value.most)])
          CanvasNumberField(
            key: ValueKey("ringIcon$name$which-${place.name}"),
            label: which == "Least" ? "$label from" : "to",
            decimals: decimals,
            width: 54,
            suffix: suffix,
            value: end,
            min: least ?? -limit,
            max: limit,
            onChanged: (v) {
              onBegin();
              _put(
                  spec.rings,
                  place,
                  put(which == "Least"
                      ? value.copyWith(least: v)
                      : value.copyWith(most: v)));
            },
            onCommit: onCommit,
          ),
      ];

  void _setNow(ProceduralSpec next) {
    onBegin();
    onChanged(next);
    onCommit();
  }

  @override
  Widget build(BuildContext context) {
    var groups = _groups(context);
    // Down the column like every other element's settings. A Row of five
    // groups in a 280px sidebar is a thousand pixels of overflow, and it does
    // not shrink -- the groups are sized to their controls.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: groups);
  }

  RingSpec get rings => spec.rings;
  LightSpec get light => spec.light;
  MetalSpec get metal => spec.metal;

  /// _light, _lightNow and _metalSet are _set and _setNow for the two specs
  /// of their own, the way _rings is for the rings.
  void _light(LightSpec next) => _set(spec.copyWith(light: next));
  void _lightNow(LightSpec next) => _setNow(spec.copyWith(light: next));
  void _metalSet(MetalSpec next) => _set(spec.copyWith(metal: next));

  List<Widget> _groups(BuildContext context) => [
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
          // The base colour, and the second one it fades to if it fades: both
          // in the picker, which is where a gradient is set now. That is
          // three controls out of this group -- a Gradient toggle, a To
          // swatch and an Angle field -- for something most backgrounds do
          // not do at all.
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
            onChanged: (c) => _setNow(spec.copyWith(foreground: c)),
          ),
          CanvasColorButton(
            label: "Accent",
            color: spec.accent,
            onChanged: (c) => _setNow(spec.copyWith(accent: c)),
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
        // The Metal texture's own settings, for the same reason the Rings
        // style has its own: "more" and "bigger" are not the questions
        // anybody has about a sheet of metal. What the shared five would have
        // to stand in for -- how coarse the brushing is, how far the rust has
        // got -- has no sensible name among them.
        if (spec.style == ProceduralStyle.metal)
          CanvasControlGroup(label: "Metal", children: [
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
              // A thousandth a pixel rather than the ten-thousandth the
              // digits imply: the whole range is a fifth of the page, and at
              // the last digit dragging across it is two thousand pixels.
              // Shift still gives the ten-thousandths for the last nudge.
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
                      // The near end and the far end, captioned by which of
                      // them a ring sets off from. Shrinking runs the journey
                      // the other way, so the near end is where a ring
                      // arrives -- and a field labelled "starts at" that is
                      // in fact where the ring stops is how a set nobody can
                      // see gets built: rings told to begin at the far corner
                      // begin off the page.
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
          // What the rings are carrying. Its own heading, and shut until it
          // is wanted, like the rest of them.
          //
          // With room under it: shut, a heading sitting straight on top of
          // the next heading reads as one section with two names.
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CanvasExpander(
              label: "Icons",
              remember: "rings.icons",
              trailing: rings.icons.isEmpty ? null : "${rings.icons.length}",
              children: [
                // Two of them and no more: one in the middle of the rings,
                // and one set spaced around a ring. It was a list anybody
                // could add to, which asked a question nobody was asking --
                // several pictures means several pictures in the one set
                // going round, not several sets of them.
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
        if (spec.style.canAnimate)
          CanvasControlGroup(label: "Movement", children: [
            CanvasToggle(
              key: const ValueKey("animate"),
              label: "Animate",
              value: spec.animated,
              onChanged: (v) => _setNow(spec.copyWith(animated: v)),
            ),
            // How many runs, and how long a rest between them. Nought times
            // is for ever, which is why there is no separate Loop switch --
            // it asked the same question twice. Either setting makes the
            // movement a thing that is counted rather than one that simply
            // goes round, which is why Frames takes over from Speed as soon
            // as one of them is set.
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
              // The run made to fit what it is under, which is the answer
              // nearly everybody wants and is otherwise a sum: a movement
              // that finishes after the last frame is a movement nobody ever
              // sees the end of.
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
            // A rest in the middle of it: which frame it stops on, how long
            // it stays stopped, and how long it takes to slow down into the
            // stop and speed up out of it. The pattern's own clock is held
            // still while the document's goes on, so everything picks up
            // exactly where it left off.
            if (spec.animated) ...[
              // On a line of their own: whether it moves, how fast and how
              // long are one question, and where it rests in the middle of
              // that is another.
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
        // The light, which every style has. Behind a heading and shut until
        // it is wanted, because most backgrounds are not lit and a switch
        // plus seven numbers at the foot of the panel would be in the way of
        // the ones that do the work.
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
                // Where it is, as a fraction of the frame rather than in
                // pixels, so a light set on the stage is in the same place in
                // an export four times the width.
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
