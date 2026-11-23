part of 'text_settings.dart';

// Parts, ranges of words with what differs on them, and the animation and
// highlight controls written once for the element and its parts. Part of
// text_settings.dart.

/// _partsSection is "these words, not the others": ranges with what
/// differs, which echoes and animations also target.
Widget _partsSection(TextElement e, SettingsWrite write, VoidCallback begin,
    VoidCallback commit) {
  void set(List<TextPart> parts) {
    begin();
    write(e.copyWith(parts: parts));
    commit();
  }

  // The row shows before anything is added, at its defaults, and setting
  // anything adds it: no plus to press first.
  var shown = e.parts.isEmpty ? const [TextPart()] : e.parts;

  List<TextPart> replacing(int index, TextPart part) => [
        for (var i = 0; i < shown.length; i++) i == index ? part : shown[i],
      ];

  return CanvasExpander(
    label: "Parts of the text",
    remember: "textParts",
    trailing: e.parts.isEmpty ? null : "${e.parts.length}",
    children: [
      const CanvasHint(
          "A part is some of the words — the sixth one, the first five, the "
          "tenth to the end — and what is different about them. Counted from "
          "one, and \"to\" left at nothing means to the end, so a part still "
          "means what it said after the words are edited."),
      for (var (i, part) in shown.indexed)
        CanvasControlGroup(label: part.says, children: [
          CanvasDropdown<TextUnit>(
            label: "Counting",
            value: part.unit,
            width: 118,
            options: [for (var u in TextUnit.values) (u, u.label)],
            onChanged: (v) => set(replacing(i, part.copyWith(unit: v))),
          ),
          CanvasNumberField(
            label: "From",
            value: part.from.toDouble(),
            min: 1,
            max: 9999,
            decimals: 0,
            width: 56,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  parts: replacing(i, part.copyWith(from: v.round()))));
            },
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "To",
            value: part.to.toDouble(),
            min: 0,
            max: 9999,
            decimals: 0,
            width: 56,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  parts: replacing(i, part.copyWith(to: v.round()))));
            },
            onCommit: commit,
          ),
          CanvasColorButton(
            label: "Colour",
            color: part.color ?? e.textSpec.color,
            onChanged: (c) => set(replacing(i, part.copyWith(color: c))),
          ),
          // Icons, not worded switches: five words in a row make a column.
          // The words are on the tooltips.
          CanvasIconButton(
            key: ValueKey("partBold$i"),
            icon: Icons.format_bold,
            tooltip: "Bold",
            active: (part.weight ?? e.textSpec.weight) >= 600,
            onPressed: () => set(replacing(
                i,
                part.copyWith(
                    weight: (part.weight ?? e.textSpec.weight) >= 600
                        ? 400
                        : 700))),
          ),
          CanvasIconButton(
            key: ValueKey("partItalic$i"),
            icon: Icons.format_italic,
            tooltip: "Italic",
            active: part.italic ?? e.textSpec.italic,
            onPressed: () => set(replacing(
                i, part.copyWith(italic: !(part.italic ?? e.textSpec.italic)))),
          ),
          // An outline on these words alone: heavier, another colour, or at
          // nothing, none inside a headline that otherwise has one.
          CanvasIconButton(
            key: ValueKey("partOutline$i"),
            icon: Icons.font_download_outlined,
            tooltip: "Outline these words",
            active: part.outlineWidth != null,
            onPressed: () => set(replacing(
                i,
                part.outlineWidth == null
                    ? part.copyWith(
                        outlineWidth: e.textSpec.outlineWidth > 0
                            ? e.textSpec.outlineWidth
                            : 2)
                    : part.copyWith(clearOutline: true))),
          ),
          if (part.outlineWidth != null) ...[
            CanvasNumberField(
              label: "Amount",
              value: part.outlineWidth!,
              min: 0,
              max: 40,
              decimals: 1,
              width: 58,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(i, part.copyWith(outlineWidth: v))));
              },
              onCommit: commit,
            ),
            CanvasColorButton(
              label: "Outline colour",
              color: part.outlineColor ?? e.textSpec.outlineColor,
              onChanged: (c) =>
                  set(replacing(i, part.copyWith(outlineColor: c))),
            ),
          ],
          // The two marks a part and the element both have, written once in
          // _markBits so they cannot drift.
          ..._markBits(
            highlight: part.highlight,
            underline: part.underline,
            textColor: part.color ?? e.textSpec.color,
            keyPrefix: "part$i",
            icons: true,
            setHighlight: (h) => set(replacing(
                i,
                h == null
                    ? part.copyWith(clearHighlight: true)
                    : part.copyWith(highlight: h))),
            setUnderline: (u) => set(replacing(
                i,
                u == null
                    ? part.copyWith(clearUnderline: true)
                    : part.copyWith(underline: u))),
            liveHighlight: (h) {
              begin();
              write(
                  e.copyWith(parts: replacing(i, part.copyWith(highlight: h))));
            },
            liveUnderline: (u) {
              begin();
              write(
                  e.copyWith(parts: replacing(i, part.copyWith(underline: u))));
            },
            done: commit,
          ),
          // This part's own arrival at its own moment, not the element's
          // animation retargeted: one animated word lands after its line.
          const CanvasLineBreak(),
          CanvasDropdown<TextAnimationFamily?>(
            key: ValueKey("partAnimationFamily$i"),
            label: "Arrives",
            value: part.animation.on ? part.animation.preset.family : null,
            width: 128,
            options: [
              (null, "With the rest"),
              for (var family in TextAnimationFamily.values)
                (family, family.label),
            ],
            onChanged: (family) => set(replacing(
                i,
                part.copyWith(
                    animation: _partPreset(
                        part.animation,
                        family == null
                            ? TextAnimationPreset.none
                            : TextAnimationPreset.inFamily(family).first)))),
          ),
          if (part.animation.on) ...[
            CanvasDropdown<TextAnimationPreset>(
              key: ValueKey("partAnimationPreset$i"),
              label: "Which",
              value: part.animation.preset,
              width: 168,
              options: [
                for (var preset in TextAnimationPreset.inFamily(
                    part.animation.preset.family))
                  (preset, preset.label),
              ],
              onChanged: (v) => set(replacing(
                  i, part.copyWith(animation: _partPreset(part.animation, v)))),
            ),
            CanvasNumberField(
              label: "Offset",
              value: part.animation.offset.toDouble(),
              min: -600,
              max: 600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation:
                                part.animation.copyWith(offset: v.round())))));
              },
              onCommit: commit,
            ),
            CanvasNumberField(
              label: "Length",
              value: part.animation.length.toDouble(),
              min: 0,
              max: 3600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation:
                                part.animation.copyWith(length: v.round())))));
              },
              onCommit: commit,
            ),
            const CanvasHint(
                "Offset is how many frames after the element's own arrival "
                "this one starts — nothing lands them together, a few frames "
                "makes the word land after the line it is in, and a negative "
                "number brings it forward. Length is how long it takes; "
                "nothing means as long as the arrival."),
          ],
          // The mark's own timing, on its own line: a second arrival (the
          // word lands, then is underlined).
          if (part.highlight != null || part.underline != null) ...[
            const CanvasLineBreak(),
            CanvasNumberField(
              label: "Mark offset",
              value: part.animation.markOffset.toDouble(),
              min: -600,
              max: 600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation: part.animation
                                .copyWith(markOffset: v.round())))));
              },
              onCommit: commit,
            ),
            CanvasNumberField(
              label: "Mark length",
              value: part.animation.markLength.toDouble(),
              min: 0,
              max: 3600,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation: part.animation
                                .copyWith(markLength: v.round())))));
              },
              onCommit: commit,
            ),
            // After the two numbers it enables, so it stays put between
            // states, and last, as the row's end switch.
            CanvasToggle(
              label: "Draw the mark on",
              value: part.animation.marks,
              onChanged: (v) => set(replacing(i,
                  part.copyWith(animation: part.animation.copyWith(marks: v)))),
            ),
            const CanvasHint(
                "Off, the highlight or underline is simply there. On, it is "
                "drawn across the words — after them by whatever the mark's "
                "own offset says, since the usual thing is a word that "
                "arrives and then gets underlined."),
          ],
          // All of the part's own animation settings (an echo's copies, a
          // drawn mark's look, the timing), not a few.
          if (part.animation.on)
            ..._animationBits(
              part.animation.arrival,
              textColor: part.color ?? e.textSpec.color,
              live: (next) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation:
                                part.animation.copyWith(arrival: next)))));
              },
              done: commit,
            ),
          const CanvasLineBreak(),
          if (e.parts.isNotEmpty)
            CanvasIconButton(
              icon: Icons.delete_outline,
              tooltip: "Remove this part",
              onPressed: () => set([
                for (var j = 0; j < e.parts.length; j++)
                  if (j != i) e.parts[j],
              ]),
            ),
        ]),
      CanvasControlGroup(label: "Add", hideCaption: true, children: [
        CanvasIconButton(
          key: const ValueKey("addTextPart"),
          icon: Icons.add,
          tooltip: "Pick out some of the words",
          onPressed: () => set([...e.parts, const TextPart()]),
        ),
      ]),
    ],
  );
}

/// _partPreset picks a part's preset with its designed curve (see
/// TextAnimationPreset.wants), a bounce with ease-out being just a slide,
/// and its designed cut, as the element's own arrival does.
TextPartAnimation _partPreset(
        TextPartAnimation animation, TextAnimationPreset preset) =>
    animation.copyWith(
        arrival: animation.arrival.copyWith(
            preset: preset, ease: preset.wants, effect: preset.effect));

/// _animationBits are a part's preset-dependent settings (drawn mark, echo,
/// timing). [live] writes; [done] commits, so a drag is one undo step.
List<Widget> _animationBits(
  TextAnimation a, {
  required Color textColor,
  required void Function(TextAnimation) live,
  required VoidCallback done,
}) {
  void now(TextAnimation next) {
    live(next);
    done();
  }

  return [
    // A destruction is an exit, said here as in a shape's panel: people look
    // for one in the arrival list.
    if (a.cuts)
      ...effectBits(a.effect, a.scatters, done,
          live: (next) => live(a.copyWith(effect: next))),
    // A drawn mark's look (an underline's line, a highlight's band), only
    // where something is drawn.
    if (a.draws)
      CanvasControlGroup(label: "The mark", children: [
        CanvasColorButton(
          label: "Colour",
          color: a.draw.color ?? textColor,
          onChanged: (c) => now(a.copyWith(draw: a.draw.copyWith(color: c))),
        ),
        CanvasDropdown<TextDrawStart>(
          key: const ValueKey("textDrawStart"),
          label: "The words are",
          value: a.draw.start,
          width: 148,
          options: [for (var s in TextDrawStart.values) (s, s.label)],
          onChanged: (v) => now(a.copyWith(draw: a.draw.copyWith(start: v))),
        ),
        const CanvasLineBreak(),
        // The room round the words is a band's and a line's; a stroke
        // follows the letterform and has nowhere to put it.
        if (a.preset != TextAnimationPreset.strokeOn) ...[
          // One field for all four sides, the four alone under it: a little
          // air round the letters reads as a highlighter.
          CanvasNumberField(
            label: "Padding",
            value: a.draw.evenPad ?? 0,
            min: 0,
            max: 200,
            decimals: 0,
            width: 62,
            onChanged: (v) {
              live(a.copyWith(draw: a.draw.withEvenPad(v)));
            },
            onCommit: done,
          ),
          for (var (name, at, set)
              in <(String, double, TextDrawSpec Function(double))>[
            ("Left", a.draw.padLeft, (v) => a.draw.copyWith(padLeft: v)),
            ("Top", a.draw.padTop, (v) => a.draw.copyWith(padTop: v)),
            ("Right", a.draw.padRight, (v) => a.draw.copyWith(padRight: v)),
            ("Bottom", a.draw.padBottom, (v) => a.draw.copyWith(padBottom: v)),
          ])
            CanvasNumberField(
              label: name,
              value: at,
              min: 0,
              max: 200,
              decimals: 0,
              width: 56,
              onChanged: (v) {
                live(a.copyWith(draw: set(v)));
              },
              onCommit: done,
            ),
          // A band's corners, as a part's own highlight has, so the two are
          // the same mark.
          if (a.preset == TextAnimationPreset.highlight)
            CanvasNumberField(
              key: const ValueKey("textMarkRadius"),
              label: "Corners",
              value: a.draw.radius,
              min: 0,
              max: 200,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                live(a.copyWith(draw: a.draw.copyWith(radius: v)));
              },
              onCommit: done,
            ),
        ],
      ]),
    // An echo's copies: how many, how far apart, how much quieter each, and
    // whether they shrink away.
    if (a.echoes)
      CanvasControlGroup(label: "The copies", children: [
        CanvasNumberField(
          label: "How many",
          value: a.echo.copies.toDouble(),
          min: 1,
          max: 24,
          decimals: 0,
          width: 56,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(copies: v.round())));
          },
          onCommit: done,
        ),
        CanvasNumberField(
          label: "Apart",
          value: a.echo.spacing,
          min: 0.05,
          max: 8,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(spacing: v)));
          },
          onCommit: done,
        ),
        CanvasNumberField(
          label: "Fade",
          value: a.echo.fade,
          min: 0.05,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(fade: v)));
          },
          onCommit: done,
        ),
        CanvasNumberField(
          label: "Shrink",
          value: a.echo.shrink,
          min: 0.2,
          max: 1,
          decimals: 2,
          width: 62,
          onChanged: (v) {
            live(a.copyWith(echo: a.echo.copyWith(shrink: v)));
          },
          onCommit: done,
        ),
        CanvasToggle(
          label: "Resolves",
          value: a.echo.resolve,
          onChanged: (v) => now(a.copyWith(echo: a.echo.copyWith(resolve: v))),
        ),
      ]),
    if (a.on || a.closes)
      CanvasControlGroup(label: "Timing", children: [
        if (a.preset.staggers || a.exit.staggers)
          CanvasNumberField(
            label: "Gap",
            min: 0,
            max: 4,
            decimals: 2,
            width: 62,
            value: a.gap,
            onChanged: (v) {
              live(a.copyWith(gap: v));
            },
            onCommit: done,
          ),
        // Where a scaling preset starts from, as in _animationCards.
        if (a.scales)
          CanvasNumberField(
            label: "From size",
            min: 0,
            max: 8,
            decimals: 2,
            width: 66,
            value: a.scale > 0 ? a.scale : a.preset.from,
            onChanged: (v) {
              live(a.copyWith(scale: v));
            },
            onCommit: done,
          ),
        easeDropdown<ChartEase>(
          label: "End curve",
          value: a.ease,
          values: ChartEase.values,
          name: (c) => c.label,
          curve: (c) => c.apply,
          onChanged: (v) {
            now(a.copyWith(ease: v));
          },
        ),
      ]),
  ];
}

/// _markBits are a static highlight and underline on some words, written
/// once for the element and its parts.
List<Widget> _markBits({
  required PartHighlight? highlight,
  required PartUnderline? underline,
  required Color textColor,
  required String keyPrefix,
  required void Function(PartHighlight?) setHighlight,
  required void Function(PartUnderline?) setUnderline,
  required void Function(PartHighlight) liveHighlight,
  required void Function(PartUnderline) liveUnderline,
  required VoidCallback done,

  /// icons draws the two switches as buttons, not words, for a part's row,
  /// which carries five.
  bool icons = false,
}) {
  return [
    // A mark simply there, not animated. Off until asked: most parts are
    // a colour and nothing else.
    if (icons)
      CanvasIconButton(
        key: ValueKey("${keyPrefix}HighlightOn"),
        icon: Icons.format_color_fill,
        tooltip: "Highlight these words",
        active: highlight != null,
        onPressed: () =>
            setHighlight(highlight == null ? const PartHighlight() : null),
      )
    else
      CanvasToggle(
        label: "Highlight",
        value: highlight != null,
        onChanged: (v) => setHighlight(v ? const PartHighlight() : null),
      ),
    if (icons)
      CanvasIconButton(
        key: ValueKey("${keyPrefix}UnderlineOn"),
        icon: Icons.format_underlined,
        tooltip: "Underline these words",
        active: underline != null,
        onPressed: () =>
            setUnderline(underline == null ? const PartUnderline() : null),
      )
    else
      CanvasToggle(
        label: "Underline",
        value: underline != null,
        onChanged: (v) => setUnderline(v ? const PartUnderline() : null),
      ),
    if (highlight != null) ...[
      const CanvasLineBreak(),
      CanvasColorButton(
        label: "Highlight",
        color: highlight.color,
        gradient: highlight.fade,
        onChanged: (c) => setHighlight(highlight.copyWith(color: c)),
        onGradientChanged: (g) => setHighlight(g == null
            ? highlight.copyWith(flat: true)
            : highlight.copyWith(fade: g)),
      ),
      // One field for all four sides, the four alone under it, as the drawn
      // mark's padding.
      CanvasNumberField(
        label: "Padding",
        value: highlight.evenPad ?? 0,
        min: 0,
        max: 200,
        decimals: 0,
        width: 62,
        onChanged: (v) {
          liveHighlight(highlight.withEvenPad(v));
        },
        onCommit: done,
      ),
      for (var (name, at, make)
          in <(String, double, PartHighlight Function(double))>[
        ("Left", highlight.padLeft, (v) => highlight.copyWith(padLeft: v)),
        ("Top", highlight.padTop, (v) => highlight.copyWith(padTop: v)),
        ("Right", highlight.padRight, (v) => highlight.copyWith(padRight: v)),
        (
          "Bottom",
          highlight.padBottom,
          (v) => highlight.copyWith(padBottom: v)
        ),
      ])
        CanvasNumberField(
          label: name,
          value: at,
          min: 0,
          max: 200,
          decimals: 0,
          width: 56,
          onChanged: (v) {
            liveHighlight(make(v));
          },
          onCommit: done,
        ),
      CanvasNumberField(
        label: "Corners",
        value: highlight.radius,
        min: 0,
        max: 200,
        decimals: 0,
        width: 62,
        onChanged: (v) {
          liveHighlight(highlight.copyWith(radius: v));
        },
        onCommit: done,
      ),
    ],
    if (underline != null) ...[
      const CanvasLineBreak(),
      CanvasDropdown<PartLineStyle>(
        key: ValueKey("${keyPrefix}UnderlineStyle"),
        label: "Line",
        value: underline.style,
        width: 130,
        options: [for (var v in PartLineStyle.values) (v, v.label)],
        onChanged: (v) => setUnderline(underline.copyWith(style: v)),
      ),
      CanvasColorButton(
        label: "Line colour",
        color: underline.color ?? textColor,
        gradient: underline.fade,
        onChanged: (c) => setUnderline(underline.copyWith(color: c)),
        onGradientChanged: (g) => setUnderline(g == null
            ? underline.copyWith(flat: true)
            : underline.copyWith(fade: g)),
      ),
      CanvasNumberField(
        label: "Width",
        value: underline.width,
        min: 0.5,
        max: 60,
        decimals: 1,
        width: 58,
        onChanged: (v) {
          liveUnderline(underline.copyWith(width: v));
        },
        onCommit: done,
      ),
      CanvasNumberField(
        label: "Away",
        value: underline.away,
        min: -40,
        max: 120,
        decimals: 0,
        width: 58,
        onChanged: (v) {
          liveUnderline(underline.copyWith(away: v));
        },
        onCommit: done,
      ),
      const CanvasHint(
          "The last four line styles are drawn rather than ruled: they "
          "wander, lean and overshoot the last letter the way a line "
          "drawn by hand does. Marker is a brush — thick in the middle "
          "and tapered at both ends. Width sets how heavy the line is, "
          "and Away how far under the letters it sits."),
    ],
  ];
}
