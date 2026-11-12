import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart' show MotionKind;
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/preset_pair.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/presets_section.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stage_spot_settings.dart';
import 'package:flutter/material.dart';

// element_panel.dart is the panel every rebuilt element's settings share
// (Ken, 2026-11-11: "all consistent"; the Text panel's prototype set it): a
// quick strip of what is changed most, then Content, Look, Layout, Motion
// and More, always in that order, an empty one left out -- drawn at the
// prototype's measure (CanvasDense). An element says what goes where with
// PanelBits; the panel adds what every element has: where it is (Layout),
// its looks (Look), how it arrives and leaves (Motion), and its presets
// (More).

/// PanelSection is one of a rebuilt panel's sections.
enum PanelSection { content, look, layout, more }

/// PanelBit is what an element puts in one of its panel's sections: its
/// groups, and a word on them for the section's heading.
class PanelBit extends StatelessWidget {
  final PanelSection into;
  final String summary;
  final List<Widget> children;
  const PanelBit(this.into, {this.summary = "", required this.children})
      : super(key: null);

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: children);
}

/// looksSaid is [e]'s looks on all of it, by name, for a heading.
String looksSaid(CanvasElement e) => [
      for (var d in e.base.motion.devices)
        if (d.on && d.side == MotionDeviceSide.look && d.layer.isEmpty)
          d.kind.label
    ].join(", ");

/// motionSaid is how [e] moves, in a few words, for the Motion heading.
String motionSaid(CanvasElement e) {
  var kinds = {
    for (var p in e.base.motion.placed)
      if (e.base.motion.clip(p.clip) case var c?) c.kind
  };
  if (kinds.isEmpty) return "Still";
  return [
    if (kinds.contains(MotionKind.arrive)) "arrives",
    if (kinds.contains(MotionKind.loop)) "loops",
    if (kinds.contains(MotionKind.leave)) "leaves",
    if (kinds.any((k) =>
        k != MotionKind.arrive &&
        k != MotionKind.loop &&
        k != MotionKind.leave))
      "moves",
  ].join(", ").replaceFirstMapped(RegExp(r"^."), (m) => m[0]!.toUpperCase());
}

/// elementPanel is [e]'s settings as the Text panel's are laid out: [quick]
/// over its sections, each section the [bits] put into it with what every
/// element has besides. [contentOpen] starts Content open: an element's
/// Content that is why its settings are opened (a path's points).
Widget elementPanel(
  BuildContext context,
  CanvasController controller,
  CanvasElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit, {
  Widget? quick,
  List<PanelBit> bits = const [],
  bool contentOpen = false,
}) {
  List<Widget> into(PanelSection s) => [
        for (var b in bits)
          if (b.into == s) ...b.children,
      ];
  String said(PanelSection s) => [
        for (var b in bits)
          if (b.into == s && b.summary.isNotEmpty) b.summary,
      ].join(" · ");
  var kind = elementKindKey(e);
  var content = into(PanelSection.content);
  var looks = looksSaid(e);
  var animates = CanvasController.animates(e);
  return CanvasDense(
    child: CanvasSections(
      key: const ValueKey("elementSections"),
      quick: quick,
      children: [
        if (content.isNotEmpty)
          section(e, "content",
              glyph: SectionGlyph.content,
              icon: Icons.notes,
              title: "Content",
              summary: said(PanelSection.content),
              initiallyOpen: contentOpen,
              children: content),
        section(e, "look",
            glyph: SectionGlyph.look,
            icon: Icons.palette_outlined,
            title: "Look",
            summary: [
              said(PanelSection.look),
              if (looks.isNotEmpty) looks,
            ].where((s) => s.isNotEmpty).join(" · "),
            initiallyOpen: true,
            children: [
              ...into(PanelSection.look),
              LooksGroup(
                  key: ValueKey("${kind}Looks"),
                  controller: controller,
                  element: e,
                  title: "Looks"),
            ]),
        section(e, "layout",
            glyph: SectionGlyph.layout,
            icon: Icons.open_with,
            title: "Layout",
            summary: [positionSummary(e), said(PanelSection.layout)]
                .where((s) => s.isNotEmpty)
                .join(" · "),
            children: [
              positionGroup(controller, e, write, begin, commit, compact: true),
              ...into(PanelSection.layout),
            ]),
        ...stageSpotSettings(context, controller, e, write, begin, commit),
        section(e, "motion",
            glyph: SectionGlyph.motion,
            icon: Icons.animation,
            title: "Motion",
            summary: motionSaid(e),
            children: [
              MotionSummary(controller: controller, element: e),
              // How it comes in and goes, chosen here as in its Chain: its
              // own arrival and way out, each its family and which of them.
              if (animates)
                CanvasControlGroup(
                    key: ValueKey("${kind}MotionPick"),
                    label: "Arrival and leaving",
                    hideCaption: true,
                    rule: false,
                    children: [
                      panelRow([
                        for (var w in canvasPresetPair<ElementAnimationPreset>(
                            key: "${kind}Arrival",
                            familyLabel: "Arrival",
                            pair: PresetPair(
                                elementPresetOptions(),
                                CanvasController.elementAnimationOf(e).preset,
                                ElementAnimationPreset.none),
                            onChanged: (v) =>
                                controller.applyElementAnimation(e, v)))
                          cell(w),
                      ]),
                      panelRow([
                        for (var w in canvasPresetPair<ElementAnimationPreset>(
                            key: "${kind}Leaving",
                            familyLabel: "Leaving",
                            pair: PresetPair(
                                elementPresetOptions(),
                                CanvasController.elementAnimationOf(e).exit,
                                ElementAnimationPreset.none),
                            onChanged: (v) =>
                                controller.applyElementExit(e, v)))
                          cell(w),
                      ]),
                    ]),
              if (controller.cues.isNotEmpty) elementCueCard(controller, e),
            ]),
        section(e, "more",
            glyph: SectionGlyph.more,
            icon: Icons.more_horiz,
            title: "More",
            summary: [said(PanelSection.more), "presets"]
                .where((s) => s.isNotEmpty)
                .join(", "),
            children: [
              ...into(PanelSection.more),
              CanvasControlGroup(
                  key: ValueKey("${kind}Presets"),
                  label: "Presets",
                  rule: false,
                  children: [presetsSection(context, controller, e)]),
            ]),
      ],
    ),
  );
}
