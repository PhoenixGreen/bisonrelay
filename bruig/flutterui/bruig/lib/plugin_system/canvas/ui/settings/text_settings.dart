import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// text settings.dart is a text element's settings.

List<Widget> textSettings(
    BuildContext context,
    CanvasController controller,
    TextElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(TextElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    // No Content field. The words are typed on the canvas, in the box they
    // will appear in, at the size and face they will appear at -- see
    // CanvasTextEditor. A two-line box in a settings panel could show neither,
    // so writing a headline meant typing it here and looking over there.
    // No caption: the panel header says "Text settings" already, and a
    // group called Text directly under it was the word twice.
    CanvasControlGroup(label: "Text", hideCaption: true, children: [
      CanvasToggle(
        label: "Fit to box",
        value: e.autoSize,
        onChanged: (v) => now(e.copyWith(autoSize: v)),
      ),
    ]),
    ...typeGroups(
        e.textSpec, (spec) => write(e.copyWith(textSpec: spec)), begin, commit),
    CanvasControlGroup(label: "Columns", children: [
      CanvasNumberField(
        key: const ValueKey("textColumns"),
        label: "Columns",
        value: e.columns.count.toDouble(),
        min: 1,
        max: 12,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(columns: e.columns.copyWith(count: v.round())));
        },
        onCommit: commit,
      ),
      // The rest only means something once there is a gutter to put it in.
      if (!e.columns.isSingle) ...[
        CanvasNumberField(
          label: "Gap",
          value: e.columns.gap,
          min: 0,
          max: 400,
          width: 54,
          onChanged: (v) {
            begin();
            write(e.copyWith(columns: e.columns.copyWith(gap: v)));
          },
          onCommit: commit,
        ),
        CanvasDropdown<ColumnRuleStyle>(
          label: "Rule",
          value: e.columns.ruleStyle,
          width: 92,
          options: [for (var v in ColumnRuleStyle.values) (v, v.label)],
          onChanged: (v) =>
              now(e.copyWith(columns: e.columns.copyWith(ruleStyle: v))),
        ),
        if (e.columns.ruleStyle != ColumnRuleStyle.none) ...[
          CanvasNumberField(
            label: "Width",
            value: e.columns.ruleWidth,
            min: 0,
            max: 40,
            decimals: 1,
            width: 54,
            onChanged: (v) {
              begin();
              write(e.copyWith(columns: e.columns.copyWith(ruleWidth: v)));
            },
            onCommit: commit,
          ),
          CanvasColorButton(
            label: "Colour",
            color: e.columns.ruleColor,
            onChanged: (c) =>
                now(e.copyWith(columns: e.columns.copyWith(ruleColor: c))),
          ),
        ],
      ],
    ]),
    CanvasControlGroup(label: "On a line", children: [
      CanvasDropdown<String>(
        label: "Follow",
        value: e.curve?.elementId ?? "",
        width: 156,
        options: curveOptions(controller),
        onChanged: (v) => now(v.isEmpty
            ? e.copyWith(clearCurve: true)
            : e.copyWith(
                curve: (e.curve ?? const TextOnCurve(elementId: ""))
                    .copyWith(elementId: v))),
      ),
      if (e.curve != null) ...[
        CanvasNumberField(
          label: "Slide",
          decimals: 2,
          width: 62,
          value: controller.valueAt(e, KeyframeChannel.slide, e.curve!.offset),
          min: -1,
          max: 1,
          onChanged: (v) {
            begin();
            // Written as a keyframe once this frame has one, so dragging the
            // slider while animating retimes the caption's travel rather than
            // moving the whole run.
            if (controller.hasValueKey(e, KeyframeChannel.slide)) {
              controller.setValueKey(e, KeyframeChannel.slide, v);
              return;
            }
            write(e.copyWith(curve: e.curve!.copyWith(offset: v)));
          },
          onCommit: commit,
        ),
        valueDot(
            controller,
            e,
            KeyframeChannel.slide,
            "the slide along the "
            "line",
            e.curve!.offset),
        CanvasNumberField(
          label: "Spacing",
          value: e.curve!.spacing,
          min: -20,
          max: 60,
          decimals: 1,
          width: 58,
          onChanged: (v) {
            begin();
            write(e.copyWith(curve: e.curve!.copyWith(spacing: v)));
          },
          onCommit: commit,
        ),
        CanvasToggle(
          label: "Below",
          value: e.curve!.away,
          onChanged: (v) => now(e.copyWith(curve: e.curve!.copyWith(away: v))),
        ),
        CanvasToggle(
          // Not the line element's own Hide: a hidden element is skipped
          // everywhere, this one included, so the text would go with it.
          label: "Hide line",
          value: e.curve!.hideHost,
          onChanged: (v) =>
              now(e.copyWith(curve: e.curve!.copyWith(hideHost: v))),
        ),
      ],
    ]),
    boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit),
    boxed(context, _partsSection(e, write, begin, commit)),
    // Boxed like every other section: a bare expander among boxed ones reads
    // as something that has come loose.
    boxed(context, _animationSection(controller, e, write, begin, commit)),
  ];
}

/// _partsSection is "these words, not the others": a list of ranges, each
/// with what is different about it.
///
/// Its own section because it is not an animation and not type: it is a fact
/// about some of the words -- the sixth one is white, the first five are
/// bold -- and the same ranges are what an echo or an animation will be
/// pointed at.
Widget _partsSection(TextElement e, SettingsWrite write, VoidCallback begin,
    VoidCallback commit) {
  void set(List<TextPart> parts) {
    begin();
    write(e.copyWith(parts: parts));
    commit();
  }

  List<TextPart> replacing(int index, TextPart part) => [
        for (var i = 0; i < e.parts.length; i++) i == index ? part : e.parts[i],
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
      for (var (i, part) in e.parts.indexed)
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
          CanvasToggle(
            label: "Bold",
            value: (part.weight ?? e.textSpec.weight) >= 600,
            onChanged: (v) =>
                set(replacing(i, part.copyWith(weight: v ? 700 : 400))),
          ),
          CanvasToggle(
            label: "Italic",
            value: part.italic ?? e.textSpec.italic,
            onChanged: (v) => set(replacing(i, part.copyWith(italic: v))),
          ),
          // A mark that is simply there, as opposed to one being drawn on by
          // an animation. Off until it is asked for: most parts are a colour
          // and nothing else, and two rows of padding fields under every one
          // of them would bury that.
          CanvasToggle(
            label: "Highlight",
            value: part.highlight != null,
            onChanged: (v) => set(replacing(
                i,
                v
                    ? part.copyWith(highlight: const PartHighlight())
                    : part.copyWith(clearHighlight: true))),
          ),
          CanvasToggle(
            label: "Underline",
            value: part.underline != null,
            onChanged: (v) => set(replacing(
                i,
                v
                    ? part.copyWith(underline: const PartUnderline())
                    : part.copyWith(clearUnderline: true))),
          ),
          if (part.highlight != null) ...[
            const CanvasLineBreak(),
            CanvasColorButton(
              label: "Highlight",
              color: part.highlight!.color,
              onChanged: (c) => set(replacing(
                  i,
                  part.copyWith(
                      highlight: part.highlight!.copyWith(color: c)))),
            ),
            // One field for all four sides, and the four on their own under
            // it -- the same shape the drawn mark's padding takes, because it
            // is the same question about the same kind of band.
            CanvasNumberField(
              label: "Padding",
              value: part.highlight!.evenPad ?? 0,
              min: 0,
              max: 200,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            highlight: part.highlight!.withEvenPad(v)))));
              },
              onCommit: commit,
            ),
            for (var (name, at, make)
                in <(String, double, PartHighlight Function(double))>[
              (
                "Left",
                part.highlight!.padLeft,
                (v) => part.highlight!.copyWith(padLeft: v)
              ),
              (
                "Top",
                part.highlight!.padTop,
                (v) => part.highlight!.copyWith(padTop: v)
              ),
              (
                "Right",
                part.highlight!.padRight,
                (v) => part.highlight!.copyWith(padRight: v)
              ),
              (
                "Bottom",
                part.highlight!.padBottom,
                (v) => part.highlight!.copyWith(padBottom: v)
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
                  begin();
                  write(e.copyWith(
                      parts: replacing(i, part.copyWith(highlight: make(v)))));
                },
                onCommit: commit,
              ),
            CanvasNumberField(
              label: "Corners",
              value: part.highlight!.radius,
              min: 0,
              max: 200,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            highlight: part.highlight!.copyWith(radius: v)))));
              },
              onCommit: commit,
            ),
          ],
          if (part.underline != null) ...[
            const CanvasLineBreak(),
            CanvasDropdown<PartLineStyle>(
              key: ValueKey("partUnderlineStyle$i"),
              label: "Line",
              value: part.underline!.style,
              width: 130,
              options: [for (var v in PartLineStyle.values) (v, v.label)],
              onChanged: (v) => set(replacing(
                  i,
                  part.copyWith(
                      underline: part.underline!.copyWith(style: v)))),
            ),
            CanvasColorButton(
              label: "Line colour",
              color: part.underline!.color ?? part.color ?? e.textSpec.color,
              onChanged: (c) => set(replacing(
                  i,
                  part.copyWith(
                      underline: part.underline!.copyWith(color: c)))),
            ),
            CanvasNumberField(
              label: "Width",
              value: part.underline!.width,
              min: 0.5,
              max: 60,
              decimals: 1,
              width: 58,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            underline: part.underline!.copyWith(width: v)))));
              },
              onCommit: commit,
            ),
            CanvasNumberField(
              label: "Away",
              value: part.underline!.away,
              min: -40,
              max: 120,
              decimals: 0,
              width: 58,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            underline: part.underline!.copyWith(away: v)))));
              },
              onCommit: commit,
            ),
            const CanvasHint(
                "The last four line styles are drawn rather than ruled: they "
                "wander, lean and overshoot the last letter the way a line "
                "drawn by hand does. Marker is a brush — thick in the middle "
                "and tapered at both ends. Width sets how heavy the line is, "
                "and Away how far under the letters it sits."),
          ],
          CanvasIconButton(
            icon: Icons.delete_outline,
            tooltip: "Remove this part",
            onPressed: () {
              // An animation pointed at a part that has gone would be
              // pointed at whichever part moved up into its place, which is
              // a setting quietly changing its own meaning.
              var at = e.animation.part;
              var next = at == i
                  ? -1
                  : at > i
                      ? at - 1
                      : at;
              begin();
              write(e.copyWith(
                parts: [
                  for (var j = 0; j < e.parts.length; j++)
                    if (j != i) e.parts[j],
                ],
                animation: e.animation.copyWith(part: next),
              ));
              commit();
            },
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

/// _animationSection is how the words arrive, and how they leave.
///
/// Its own section, like a chart's, and for the same reason: it is a handful
/// of choices made once and then left alone, and open by default it would be
/// half a screen of names between the type settings and the box.
///
/// The presets are grouped by family because the flat list is thirty long.
/// Grouped, the question is "what kind of arrival" and then "which one",
/// which is how somebody actually chooses.
Widget _animationSection(CanvasController controller, TextElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(TextElement next) {
    begin();
    write(next);
    commit();
  }

  var animation = e.animation;
  return CanvasExpander(
    label: "Animation",
    remember: "textAnimation",
    trailing: animation.on
        ? (animation.closes
            ? "${animation.preset.label} · ${animation.exit.label}"
            : animation.preset.label)
        : (animation.closes ? animation.exit.label : null),
    children: [
      const CanvasHint(
          "Choosing one draws the words on over two seconds and puts a "
          "keyframe at each end of it on the timeline. Drag those to decide "
          "how long it takes and when it happens — the same two keyframes a "
          "chart's animation uses, so a headline and a chart can arrive "
          "together."),
      // The family first, then the animation. Thirty names in one list is a
      // wall of text nobody reads to the end of; asked in two steps the
      // question is "what kind of arrival" and then "which one", which is how
      // somebody actually chooses.
      //
      // Choosing a family applies the first of its presets rather than
      // waiting for a second choice, so the canvas shows something
      // immediately and the second box refines it.
      CanvasControlGroup(label: "Arriving", children: [
        CanvasDropdown<TextAnimationFamily?>(
          key: const ValueKey("textAnimationFamily"),
          label: "Kind",
          value: animation.on ? animation.preset.family : null,
          width: 132,
          options: [
            (null, "None"),
            for (var family in TextAnimationFamily.values)
              (family, family.label),
          ],
          onChanged: (family) => controller.applyTextAnimation(
              e,
              family == null
                  ? TextAnimationPreset.none
                  : TextAnimationPreset.inFamily(family).first),
        ),
        if (animation.on)
          CanvasDropdown<TextAnimationPreset>(
            key: const ValueKey("textAnimationPreset"),
            label: "Which",
            value: animation.preset,
            width: 168,
            options: [
              for (var preset
                  in TextAnimationPreset.inFamily(animation.preset.family))
                (preset, preset.label),
            ],
            onChanged: (v) => controller.applyTextAnimation(e, v),
          ),
      ]),
      // Which words it happens to. All of them unless one of the parts is
      // named, which is what makes a headline where one word echoes and the
      // rest of the line sits still.
      if (animation.on && e.parts.isNotEmpty)
        CanvasControlGroup(label: "Applies to", children: [
          CanvasDropdown<int>(
            key: const ValueKey("textAnimationPart"),
            label: "",
            value: animation.part < e.parts.length ? animation.part : -1,
            width: 190,
            options: [
              (-1, "All the words"),
              for (var (i, part) in e.parts.indexed) (i, part.says),
            ],
            onChanged: (v) =>
                now(e.copyWith(animation: animation.copyWith(part: v))),
          ),
        ]),
      if (animation.on || animation.closes)
        CanvasControlGroup(label: "Leaving", children: [
          CanvasDropdown<TextAnimationFamily?>(
            key: const ValueKey("textAnimationExitFamily"),
            label: "Kind",
            value: animation.closes ? animation.exit.family : null,
            width: 132,
            options: [
              (null, "None"),
              for (var family in TextAnimationFamily.values)
                (family, family.label),
            ],
            onChanged: (family) => controller.applyTextExit(
                e,
                family == null
                    ? TextAnimationPreset.none
                    : TextAnimationPreset.inFamily(family).first),
          ),
          if (animation.closes) ...[
            CanvasDropdown<TextAnimationPreset>(
              key: const ValueKey("textAnimationExit"),
              label: "Which",
              value: animation.exit,
              width: 168,
              options: [
                for (var preset
                    in TextAnimationPreset.inFamily(animation.exit.family))
                  (preset, "${preset.label}, reversed"),
              ],
              onChanged: (v) => controller.applyTextExit(e, v),
            ),
            CanvasToggle(
              label: "In the same order",
              value: animation.exitInOrder,
              onChanged: (v) => now(
                  e.copyWith(animation: animation.copyWith(exitInOrder: v))),
            ),
          ],
        ]),
      // What a drawn mark looks like: an underline's line, a highlight's
      // band. Only where something is drawn -- on a fade there is no mark to
      // colour.
      if (animation.draws)
        CanvasControlGroup(label: "The mark", children: [
          CanvasColorButton(
            label: "Colour",
            color: animation.draw.color ?? e.textSpec.color,
            onChanged: (c) => now(e.copyWith(
                animation: animation.copyWith(
                    draw: animation.draw.copyWith(color: c)))),
          ),
          CanvasDropdown<TextDrawStart>(
            key: const ValueKey("textDrawStart"),
            label: "The words are",
            value: animation.draw.start,
            width: 148,
            options: [for (var s in TextDrawStart.values) (s, s.label)],
            onChanged: (v) => now(e.copyWith(
                animation: animation.copyWith(
                    draw: animation.draw.copyWith(start: v)))),
          ),
          const CanvasLineBreak(),
          // One field for all four sides, and the four on their own under it.
          // A band tight around the letters reads as a mistake; one with a
          // little air reads as a highlighter.
          CanvasNumberField(
            label: "Padding",
            value: animation.draw.evenPad ?? 0,
            min: 0,
            max: 200,
            decimals: 0,
            width: 62,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  animation:
                      animation.copyWith(draw: animation.draw.withEvenPad(v))));
            },
            onCommit: commit,
          ),
          for (var (name, at, set)
              in <(String, double, TextDrawSpec Function(double))>[
            (
              "Left",
              animation.draw.padLeft,
              (v) => animation.draw.copyWith(padLeft: v)
            ),
            (
              "Top",
              animation.draw.padTop,
              (v) => animation.draw.copyWith(padTop: v)
            ),
            (
              "Right",
              animation.draw.padRight,
              (v) => animation.draw.copyWith(padRight: v)
            ),
            (
              "Bottom",
              animation.draw.padBottom,
              (v) => animation.draw.copyWith(padBottom: v)
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
                begin();
                write(e.copyWith(animation: animation.copyWith(draw: set(v))));
              },
              onCommit: commit,
            ),
          const CanvasHint(
              "Padding is the room around the words the mark takes in: none "
              "of it for an underline tight under the letters, a few pixels "
              "for a highlighter. The one field sets all four sides; the four "
              "under it set one each."),
        ]),
      // How the copies of an echo are arranged: how many, how far apart, how
      // much quieter each one is, and whether they shrink away.
      if (animation.echoes)
        CanvasControlGroup(label: "The copies", children: [
          CanvasNumberField(
            label: "How many",
            value: animation.echo.copies.toDouble(),
            min: 1,
            max: 24,
            decimals: 0,
            width: 56,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  animation: animation.copyWith(
                      echo: animation.echo.copyWith(copies: v.round()))));
            },
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Apart",
            value: animation.echo.spacing,
            min: 0.05,
            max: 8,
            decimals: 2,
            width: 62,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  animation: animation.copyWith(
                      echo: animation.echo.copyWith(spacing: v))));
            },
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Fade",
            value: animation.echo.fade,
            min: 0.05,
            max: 1,
            decimals: 2,
            width: 62,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  animation: animation.copyWith(
                      echo: animation.echo.copyWith(fade: v))));
            },
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Shrink",
            value: animation.echo.shrink,
            min: 0.2,
            max: 1,
            decimals: 2,
            width: 62,
            onChanged: (v) {
              begin();
              write(e.copyWith(
                  animation: animation.copyWith(
                      echo: animation.echo.copyWith(shrink: v))));
            },
            onCommit: commit,
          ),
          const CanvasHint(
              "Apart is measured in line heights, so the same setting reads "
              "the same on a headline and on a caption. Fade is how much of "
              "one copy's strength the next one keeps — a little over half is "
              "a trail, 1 is a stack. The copies stay when the animation is "
              "over: it is a look as much as an arrival."),
        ]),
      if (animation.on || animation.closes)
        CanvasControlGroup(label: "Timing", children: [
          if (animation.preset.staggers || animation.exit.staggers)
            CanvasNumberField(
              label: "Gap",
              min: 0,
              max: 4,
              decimals: 2,
              width: 62,
              value: animation.gap,
              onChanged: (v) {
                begin();
                write(e.copyWith(animation: animation.copyWith(gap: v)));
              },
              onCommit: commit,
            ),
          if (animation.preset.staggers || animation.exit.staggers)
            const CanvasHint(
                "How long after one letter, word or line starts before the "
                "next does, as a share of one piece's own movement. 1 is "
                "strictly one after another; below 1 they overlap; above 1 "
                "leaves a pause between them."),
          // Where a scaling preset starts from, and on the way out where it
          // goes: above 1 it carries the words off the screen, at 0 it
          // shrinks them to nothing.
          if (animation.scales)
            CanvasNumberField(
              label: "From size",
              min: 0,
              max: 8,
              decimals: 2,
              width: 66,
              value:
                  animation.scale > 0 ? animation.scale : animation.preset.from,
              onChanged: (v) {
                begin();
                write(e.copyWith(animation: animation.copyWith(scale: v)));
              },
              onCommit: commit,
            ),
          if (animation.scales)
            const CanvasHint(
                "1 is full size. Below it the words grow into place; above it "
                "they arrive too large and settle. On the way out it is where "
                "they go — 2 and above carries them off the screen, 0 shrinks "
                "them to nothing."),
          CanvasDropdown<ChartEase>(
            label: "End curve",
            value: animation.ease,
            width: 118,
            options: [for (var c in ChartEase.values) (c, c.label)],
            onChanged: (v) {
              begin();
              write(e.copyWith(animation: animation.copyWith(ease: v)));
              commit();
            },
          ),
        ]),
    ],
  );
}

/// valueDot is the diamond beside one animatable property.
///
/// Its own control rather than part of the pose diamond, because these are
/// real channels: a keyframe can pin a caption's slide without pinning where
/// its box sits, and the two are asked for at different moments.
