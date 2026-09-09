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
    // Four sections, each of which is one question: what the type looks like,
    // how it is laid out, which words are different, and how it arrives.
    // Flat, this was eight groups down one narrow column and the animation
    // settings were below the fold on any panel narrower than the screen.
    boxed(
      context,
      CanvasExpander(
        label: "Type",
        remember: "textType",
        initiallyOpen: true,
        trailing: "${e.textSpec.fontSize.round()}",
        children: [
          // No Content field. The words are typed on the canvas, in the box
          // they will appear in, at the size and face they will appear at --
          // see CanvasTextEditor. A two-line box in a settings panel could
          // show neither, so writing a headline meant typing it here and
          // looking over there.
          CanvasControlGroup(label: "Text", hideCaption: true, children: [
            CanvasToggle(
              label: "Fit to box",
              value: e.autoSize,
              onChanged: (v) => now(e.copyWith(autoSize: v)),
            ),
          ]),
          // The section's own heading says Type already, so the first group
          // inside it does not say it again.
          ...typeGroups(e.textSpec, (spec) => write(e.copyWith(textSpec: spec)),
              begin, commit,
              hideCaption: true),
          // The element's own marks: a band behind all of the words, a line
          // under all of them. Here rather than only on a part, because
          // highlighting a whole headline should not mean first making a part
          // that covers it.
          CanvasControlGroup(label: "Marks", children: [
            ..._markBits(
              highlight: e.highlight,
              underline: e.underline,
              textColor: e.textSpec.color,
              keyPrefix: "text",
              setHighlight: (h) => now(h == null
                  ? e.copyWith(clearHighlight: true)
                  : e.copyWith(highlight: h)),
              setUnderline: (u) => now(u == null
                  ? e.copyWith(clearUnderline: true)
                  : e.copyWith(underline: u)),
              liveHighlight: (h) {
                begin();
                write(e.copyWith(highlight: h));
              },
              liveUnderline: (u) {
                begin();
                write(e.copyWith(underline: u));
              },
              done: commit,
            ),
          ]),
          boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit),
        ],
      ),
    ),
    boxed(
      context,
      CanvasExpander(
        label: "Columns and on a line",
        remember: "textLayout",
        trailing: e.curve != null
            ? "On a line"
            : (e.columns.isSingle ? null : "${e.columns.count} columns"),
        children: [
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
                write(
                    e.copyWith(columns: e.columns.copyWith(count: v.round())));
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
                    write(
                        e.copyWith(columns: e.columns.copyWith(ruleWidth: v)));
                  },
                  onCommit: commit,
                ),
                CanvasColorButton(
                  label: "Colour",
                  color: e.columns.ruleColor,
                  onChanged: (c) => now(
                      e.copyWith(columns: e.columns.copyWith(ruleColor: c))),
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
                value: controller.valueAt(
                    e, KeyframeChannel.slide, e.curve!.offset),
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
                onChanged: (v) =>
                    now(e.copyWith(curve: e.curve!.copyWith(away: v))),
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
        ],
      ),
    ),
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
          // An outline on these words alone: a heavier one than the rest of
          // the headline has, a different colour, or -- at nothing -- none at
          // all inside a headline that otherwise has one.
          CanvasToggle(
            label: "Outline",
            value: part.outlineWidth != null,
            onChanged: (v) => set(replacing(
                i,
                v
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
          // The two marks, which a part has and the element has as well --
          // written once, in _markBits, so they cannot drift apart.
          ..._markBits(
            highlight: part.highlight,
            underline: part.underline,
            textColor: part.color ?? e.textSpec.color,
            keyPrefix: "part$i",
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
          // This part's own arrival, at its own moment. Not the element's
          // animation pointed here: the rest of the sentence has an arrival
          // of its own, and the point of animating one word is that it lands
          // after the line it is in rather than with it.
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
          // The mark's own timing, on a line of its own: it is a second
          // arrival -- the word lands and *then* gets underlined -- and run
          // on from the offset and length above it read as more of those.
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
            // After the two numbers it turns on, so it does not move about
            // between one state and the other -- and last, because it is the
            // switch on the end of the row rather than the heading of it.
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
          // The rest of the animation settings, which are the paragraph's own
          // — the copies of an echo, the look of a drawn mark, the timing.
          // The same ones rather than a chosen few: a part whose echo could
          // not be told to resolve is a part with half an animation.
          if (part.animation.on)
            ..._animationBits(
              part.animation.asAnimation,
              textColor: part.color ?? e.textSpec.color,
              live: (next) {
                begin();
                write(e.copyWith(
                    parts: replacing(
                        i,
                        part.copyWith(
                            animation: part.animation.fromAnimation(next)))));
              },
              done: commit,
            ),
          const CanvasLineBreak(),
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

/// _partPreset chooses a preset for a part, and the curve it was designed
/// around with it. See TextAnimationPreset.wants: a bounce played with the
/// ordinary ease-out is a slide with a misleading name.
TextPartAnimation _partPreset(
        TextPartAnimation animation, TextAnimationPreset preset) =>
    animation.copyWith(preset: preset, ease: preset.wants);

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
      ..._animationBits(
        animation,
        textColor: e.textSpec.color,
        live: (next) {
          begin();
          write(e.copyWith(animation: next));
        },
        done: commit,
        timingFirst: [
          // How long an arrival or an exit is laid down with, in frames. A
          // setting rather than a reading of the timeline: the default is
          // rarely the length wanted, and dragging a keyframe is a poor way
          // to ask for twelve frames.
          CanvasNumberField(
            key: const ValueKey("textAnimationLength"),
            label: "Length",
            min: 1,
            max: 3600,
            decimals: 0,
            width: 62,
            value: (animation.length > 0
                    ? animation.length
                    : controller.defaultAnimationFrames)
                .toDouble(),
            onChanged: (v) {
              begin();
              write(
                  e.copyWith(animation: animation.copyWith(length: v.round())));
            },
            onCommit: commit,
          ),
          const CanvasHint(
              "How many frames a new arrival or exit is laid down with. Once "
              "it is on the timeline the keyframes are where it is: changing "
              "this does not move them, and neither does trying another "
              "preset. Delete a keyframe and the animation is gone — the next "
              "one chosen is laid down at this length again."),
        ],
      ),
    ],
  );
}

/// valueDot is the diamond beside one animatable property.
///
/// Its own control rather than part of the pose diamond, because these are
/// real channels: a keyframe can pin a caption's slide without pinning where
/// its box sits, and the two are asked for at different moments.

/// _animationBits are the settings that depend on which preset was chosen:
/// what a drawn mark looks like, how an echo's copies are arranged, and the
/// timing.
///
/// Shared by the element's own arrival and by every part that arrives on its
/// own account, because they are the same animation -- a part offering half
/// the settings was a part whose echo could not be told to resolve. [live] is
/// handed the edited animation and writes it wherever it belongs; [done]
/// commits, so a number field can be dragged without filling the undo stack.
List<Widget> _animationBits(
  TextAnimation a, {
  required Color textColor,
  required void Function(TextAnimation) live,
  required VoidCallback done,
  List<Widget> timingFirst = const [],
}) {
  void now(TextAnimation next) {
    live(next);
    done();
  }

  return [
    // What a drawn mark looks like: an underline's line, a highlight's
    // band. Only where something is drawn -- on a fade there is no mark to
    // colour.
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
        // One field for all four sides, and the four on their own under it.
        // A band tight around the letters reads as a mistake; one with a
        // little air reads as a highlighter.
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
        const CanvasHint(
            "Padding is the room around the words the mark takes in: none "
            "of it for an underline tight under the letters, a few pixels "
            "for a highlighter. The one field sets all four sides; the four "
            "under it set one each."),
      ]),
    // How the copies of an echo are arranged: how many, how far apart, how
    // much quieter each one is, and whether they shrink away.
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
        const CanvasHint(
            "Resolves sends the copies on their way instead of leaving them "
            "there: they fan out, carry on in the direction they were "
            "headed, and are gone by the end — which turns the echo from a "
            "look into a way in."),
        const CanvasHint(
            "Apart is measured in line heights, so the same setting reads "
            "the same on a headline and on a caption. Fade is how much of "
            "one copy's strength the next one keeps — a little over half is "
            "a trail, 1 is a stack. The copies stay when the animation is "
            "over: it is a look as much as an arrival."),
      ]),
    if (a.on || a.closes)
      CanvasControlGroup(label: "Timing", children: [
        // Whatever the caller wants first in here -- the element's own
        // Length, which a part has no use for: a part has an offset and a
        // length of its own, measured against that one.
        ...timingFirst,
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
        if (a.preset.staggers || a.exit.staggers)
          const CanvasHint(
              "How long after one letter, word or line starts before the "
              "next does, as a share of one piece's own movement. 1 is "
              "strictly one after another; below 1 they overlap; above 1 "
              "leaves a pause between them."),
        // Where a scaling preset starts from, and on the way out where it
        // goes: above 1 it carries the words off the screen, at 0 it
        // shrinks them to nothing.
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
        if (a.scales)
          const CanvasHint(
              "1 is full size. Below it the words grow into place; above it "
              "they arrive too large and settle. On the way out it is where "
              "they go — 2 and above carries them off the screen, 0 shrinks "
              "them to nothing."),
        CanvasDropdown<ChartEase>(
          label: "End curve",
          value: a.ease,
          width: 118,
          options: [for (var c in ChartEase.values) (c, c.label)],
          onChanged: (v) {
            now(a.copyWith(ease: v));
          },
        ),
      ]),
  ];
}

/// _markBits are a highlight and an underline: the two marks that are simply
/// *there* on some words, as opposed to one an animation draws on.
///
/// Written once and shown twice -- for the element, where they apply to every
/// word, and for a part, where they apply to a few. They were the part's
/// alone, so highlighting a whole headline meant first making a part that
/// covered it.
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
}) {
  return [
    // A mark that is simply there, as opposed to one being drawn on by
    // an animation. Off until it is asked for: most parts are a colour
    // and nothing else, and two rows of padding fields under every one
    // of them would bury that.
    CanvasToggle(
      label: "Highlight",
      value: highlight != null,
      onChanged: (v) => setHighlight(v ? const PartHighlight() : null),
    ),
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
        onChanged: (c) => setHighlight(highlight.copyWith(color: c)),
      ),
      // One field for all four sides, and the four on their own under
      // it -- the same shape the drawn mark's padding takes, because it
      // is the same question about the same kind of band.
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
        onChanged: (c) => setUnderline(underline.copyWith(color: c)),
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
