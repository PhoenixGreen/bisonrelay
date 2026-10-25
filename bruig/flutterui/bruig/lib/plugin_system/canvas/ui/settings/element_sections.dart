import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/edge_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/presets_section.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// element_sections.dart is the sections every element's panel has, whatever
// else it has: where it is, how it arrives, and the designs saved of its
// kind. A picture's panel was the first in sections -- see
// image_sections.dart -- and the rest follow it, so these say the same
// things the same way in every panel. Each section is remembered open or
// shut per kind of element: "shape.position", not "position".

/// elementKindKey is how [e]'s kind names its sections' remembered state.
String elementKindKey(CanvasElement e) => e.kind.name;

/// positionSummary is where [e] is and how big, in a line.
String positionSummary(CanvasElement e) => "${e.x.round()}, ${e.y.round()} · "
    "${e.width.round()} × ${e.height.round()}"
    "${e.base.rotation != 0 ? " · ${e.base.rotation.round()}°" : ""}";

/// positionSection is where [e] is: its place, its size, its turn and how
/// solid it is -- and [extra], for an element with more to say about its
/// place.
Widget positionSection(CanvasController controller, CanvasElement e,
        SettingsWrite write, VoidCallback begin, VoidCallback commit,
        {List<Widget> extra = const [], String? summary}) =>
    CanvasSection(
      key: const ValueKey("elementSection-position"),
      icon: Icons.open_with,
      title: "Position",
      summary: summary ?? positionSummary(e),
      remember: "${elementKindKey(e)}.position",
      initiallyOpen: true,
      children: [
        positionGroup(controller, e, write, begin, commit),
        ...extra,
      ],
    );

/// presetsPanelSection is the designs saved of [e]'s kind, to start from or
/// to keep this one as.
Widget presetsPanelSection(
    BuildContext context, CanvasController controller, CanvasElement e,
    {List<Widget> extra = const []}) {
  var store = ElementPresetStore.instance;
  var n = store.forKind(e.kind).length;
  return CanvasSection(
    key: const ValueKey("elementSection-presets"),
    icon: Icons.bookmarks_outlined,
    title: "Presets",
    summary: n == 0
        ? "Keep this design to use again"
        : "$n design${n == 1 ? "" : "s"} to start from",
    remember: "${elementKindKey(e)}.presets",
    children: [presetsSection(context, controller, e), ...extra],
  );
}

/// animationSummary is how [a] arrives and leaves, in a line.
String animationSummary(ElementAnimation a) => !a.any
    ? "Arrives with the scene"
    : [
        if (a.on) "In: ${presetName(a.preset)}",
        if (a.closes) "Out: ${presetName(a.exit)}",
        if (a.loop.on) "Loops",
      ].join(" · ");

/// animationPanelSection is how [e] arrives and leaves -- the same cards in
/// every panel, from elementAnimationSection -- with the cue it waits for,
/// and [extra] for an element with timing of its own.
Widget animationPanelSection(
  CanvasController controller,
  CanvasElement e,
  ElementAnimation animation,
  void Function(ElementAnimation) write,
  VoidCallback begin,
  VoidCallback commit, {
  void Function(ElementAnimationPreset)? arrive,
  void Function(ElementAnimationPreset)? leave,
  List<Widget> heading = const [],
  List<Widget> extra = const [],
  bool timing = true,
  String? summary,
}) =>
    CanvasSection(
      key: const ValueKey("elementSection-animation"),
      icon: Icons.play_circle_outline,
      title: "Animation",
      summary: summary ?? animationSummary(animation),
      remember: "${elementKindKey(e)}.animation",
      children: [
        elementAnimationSection(controller, e, animation, write, begin, commit,
            arrive: arrive, leave: leave, heading: heading, timing: timing),
        ...elementTimingCards(controller, e),
        ...extra,
      ],
    );

/// elementTimingCards are what [e]'s arrival is timed against and does to
/// the rest: the cue it waits for, where there are cues or words to wait
/// on, and dimming what is already there, where it has an arrival.
List<Widget> elementTimingCards(CanvasController controller, CanvasElement e) =>
    [
      if (controller.cues.isNotEmpty || controller.words.isNotEmpty)
        elementCueCard(controller, e),
      if (bandsIn(e.base.track)
          .any((b) => b.channel == KeyframeChannel.reveal))
        elementDimCard(controller, e),
    ];

/// elementDimCard fades everything already on the canvas as [e] arrives.
Widget elementDimCard(CanvasController controller, CanvasElement e) =>
    CanvasControlGroup(
        key: const ValueKey("elementDim"),
        label: "The rest",
        help: "Fades everything already on the canvas to 30% as this "
            "arrives, and keeps it there -- the next point of an argument "
            "taking the light while the last stays readable.",
        rule: false,
        children: [
          CanvasTextButton(
            key: const ValueKey("elementDimOthers"),
            label: "Dim the others",
            icon: Icons.brightness_medium_outlined,
            grow: false,
            onPressed: () => controller.dimOthers(e.id),
          ),
        ]);

/// elementCueCard is which cue [e] arrives on.
Widget elementCueCard(CanvasController controller, CanvasElement e) =>
    CanvasControlGroup(
        key: const ValueKey("elementCue"),
        label: "Cue",
        help: "Tied to a cue, it arrives when the cue does, wherever the cue "
            "is moved to on the timeline.",
        rule: false,
        children: [
          CanvasDropdown<String>(
            label: "Arrives on cue",
            value: controller.cues.any((c) => c.id == e.base.cue)
                ? e.base.cue
                : "",
            width: 150,
            options: [
              ("", "None"),
              for (var c in controller.cues) (c.id, c.name),
            ],
            onChanged: (v) => controller.cueTo(e.id, v.isEmpty ? null : v),
          ),
          // Or straight onto a word, where the voice has been heard: a cue
          // is made where the word is said, named by it.
          if (controller.words.isNotEmpty) ...[
            const CanvasLineBreak(),
            CanvasTextField(
              key: const ValueKey("elementCueWord"),
              label: "On a word",
              hint: "\$300, hardware…",
              value: controller.wordQuery,
              width: 150,
              onChanged: (v) => controller.wordQuery = v,
            ),
            for (var w in controller.wordsMatching(controller.wordQuery))
              CanvasTextButton(
                key: ValueKey("elementCueWord-${w.frame}"),
                label: "${controller.wordInContext(w)} · "
                    "${(w.frame / math.max(1, controller.document.frameRate)).toStringAsFixed(1)}s",
                tooltip: "Arrive as \"${w.text}\" is said",
                grow: false,
                onPressed: () {
                  controller.cueOnWord(e.id, w);
                  controller.wordQuery = "";
                },
              ),
          ],
        ]);

/// section is one of an element's own sections: [icon], [title], a line
/// saying how it is set, remembered as "kind.name".
Widget section(CanvasElement e, String name,
        {required IconData icon,
        required String title,
        String summary = "",
        int changes = 0,
        VoidCallback? onReset,
        bool initiallyOpen = false,
        bool forceOpen = false,
        Widget? action,
        required List<Widget> children}) =>
    CanvasSection(
      key: ValueKey("elementSection-$name"),
      action: action,
      icon: icon,
      title: title,
      summary: summary,
      changes: changes,
      onReset: onReset,
      remember: "${elementKindKey(e)}.$name",
      initiallyOpen: initiallyOpen,
      forceOpen: forceOpen,
      children: children,
    );

/// boxSummary is how a box round words is drawn, in a line.
String boxSummary(BoxSpec b) {
  var filled = b.painted.kind != TextFillKind.color || b.fill.a > 0;
  return [
    filled ? "Filled" : "No fill",
    b.borderWidth > 0 ? "border ${shortNumber(b.borderWidth)}" : "no border",
    if (b.borderRadius > 0) "corners ${shortNumber(b.borderRadius)}",
  ].join(" · ");
}

/// typeSummary is how words are set, in a line.
String typeSummary(TextSpec t) =>
    "${t.fontFamily} · ${shortNumber(t.fontSize)}";

/// expanderSection is a part of a panel that was an expander of its own --
/// its name, how it is set and the button in its heading -- as a section:
/// a section is the fold now, and a fold inside a fold is two presses for
/// one thing.
Widget expanderSection(CanvasElement e, IconData icon, Widget expander,
        {String? summary, List<Widget> extra = const []}) =>
    expanderAsSection(icon, expander,
        summary: summary, extra: extra, prefix: "${elementKindKey(e)}.");

/// expanderAsSection is expanderSection for a part of a panel that is not an
/// element's -- the canvas's own background -- remembered under [prefix].
Widget expanderAsSection(IconData icon, Widget expander,
    {String? summary, List<Widget> extra = const [], String prefix = ""}) {
  var x = expander as CanvasExpander;
  var name = x.remember ?? x.label;
  return CanvasSection(
      // The expander's own key, where it had one, so what found it still
      // finds the part of the panel it was.
      key: x.key ?? ValueKey("elementSection-$name"),
      icon: icon,
      title: x.label,
      summary: summary ?? x.trailing ?? "",
      remember: "$prefix$name",
      initiallyOpen: x.initiallyOpen,
      action: x.action,
      children: [...x.children, ...extra]);
}

/// notInCards is [child] outside a sectioned panel, and nothing inside one,
/// where tiles ask the same question -- an animation's kinds, say.
Widget notInCards(Widget child) => Builder(
    builder: (context) =>
        CanvasCards.on(context) ? const SizedBox.shrink() : child);

/// onlyInCards is [child] inside a sectioned panel, and nothing outside one.
Widget onlyInCards(Widget child) => Builder(
    builder: (context) =>
        CanvasCards.on(context) ? child : const SizedBox.shrink());

/// edgeMaskSection is [mask], the edges of [e]'s box softened and faded --
/// for a video or a pattern, whose hard rectangle is so often what needs
/// taking away.
Widget edgeMaskSection(CanvasElement e, EdgeMask mask,
    ValueChanged<EdgeMask> write, VoidCallback begin, VoidCallback commit) {
  void now(EdgeMask next) {
    begin();
    write(next);
    commit();
  }

  return section(e, "mask",
      icon: Icons.blur_on,
      title: "Mask",
      summary: !mask.on
          ? "Hard edges"
          : [
              if (mask.feather > 0) "soft ${(mask.feather * 100).round()}%",
              if (mask.fade != EdgeFade.none) mask.fade.label.toLowerCase(),
            ].join(" · "),
      changes: mask.on ? 1 : 0,
      onReset: () => now(const EdgeMask()),
      children: [
        CanvasControlGroup(
            key: const ValueKey("edgeMask"),
            label: "Edges",
            help: "Soft edges fade the whole box out round its rim. A fade "
                "takes it away from one side, from two, or from the rim in "
                "-- whole in the middle. Reach is how far in the fade runs.",
            rule: false,
            children: [
              CanvasNumberField(
                key: const ValueKey("edgeMaskFeather"),
                label: "Soft",
                value: mask.feather * 100,
                min: 0,
                max: 50,
                decimals: 0,
                suffix: "%",
                width: 52,
                onChanged: (v) {
                  begin();
                  write(mask.copyWith(feather: v / 100));
                },
                onCommit: commit,
              ),
              CanvasDropdown<EdgeFade>(
                key: const ValueKey("edgeMaskFade"),
                label: "Fade",
                value: mask.fade,
                width: 140,
                options: [for (var f in EdgeFade.values) (f, f.label)],
                onChanged: (v) => now(mask.copyWith(fade: v)),
              ),
              if (mask.fade != EdgeFade.none)
                CanvasNumberField(
                  key: const ValueKey("edgeMaskReach"),
                  label: "Reach",
                  value: mask.reach * 100,
                  min: 1,
                  max: 100,
                  decimals: 0,
                  suffix: "%",
                  width: 52,
                  onChanged: (v) {
                    begin();
                    write(mask.copyWith(reach: v / 100));
                  },
                  onCommit: commit,
                ),
            ]),
      ]);
}
