import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/human_wear.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_body.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_appearance_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// character_appearance_settings.dart is the Appearance editor: every part
// of the body and the face, a tab at a time, as a game's character editor
// has it -- quick starts drawn on this character, then a slider for each
// thing that can be shaped. Sliders here, steppers elsewhere: there are
// seventy of them, and they are dragged until it looks right.

/// AppearanceEditor edits [character]'s Appearance.
class AppearanceEditor extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
  final SettingsWrite write;
  final VoidCallback commit;

  /// only is the one part shaped here, for a layer's settings -- see
  /// character_layers_settings.dart -- with no Part to pick.
  final AppearanceGroup? only;

  /// keyed is the sliders a layer's keyforms follow, marked so.
  final Set<Look> keyed;

  const AppearanceEditor({
    required this.controller,
    required this.character,
    required this.write,
    required this.commit,
    this.only,
    this.keyed = const {},
    super.key,
  });

  /// tab is the part open, kept from one character to the next: someone
  /// shaping noses shapes the next one's nose too.
  static AppearanceGroup tab = AppearanceGroup.body;

  @override
  State<AppearanceEditor> createState() => AppearanceEditorState();
}

class AppearanceEditorState extends State<AppearanceEditor> {
  /// _focus is what was picked on the canvas when last seen: picking
  /// something new there opens its part here.
  AppearanceGroup? _focus;

  @override
  void initState() {
    super.initState();
    _focus = appearanceFocus(widget.controller);
  }

  CharacterElement get e => widget.character;
  CharacterDna get dna => e.dna;
  AppearanceGroup get group => widget.only ?? AppearanceEditor.tab;

  void _dna(CharacterDna next, {bool live = false}) {
    widget.controller.beginInteraction();
    widget.write(e.copyWith(dna: next));
    if (!live) widget.commit();
  }

  void _look(Appearance next, {bool live = false}) =>
      _dna(dna.copyWith(look: next), live: live);

  /// _groups is the tabs this character has: no facial hair or hairstyles
  /// on a fish.
  List<AppearanceGroup> get _groups => [
        for (var g in AppearanceGroup.values)
          if (dna.kind.person ||
              !(g == AppearanceGroup.facialHair ||
                  g == AppearanceGroup.hair ||
                  g == AppearanceGroup.brows ||
                  g == AppearanceGroup.nose ||
                  g == AppearanceGroup.mouth))
            g,
      ];

  @override
  Widget build(BuildContext context) {
    var groups = _groups;
    // A feature of the face or a point of a limb picked on the canvas opens
    // the part it is shaped in.
    var focus = appearanceFocus(widget.controller);
    if (focus != _focus) {
      _focus = focus;
      if (focus != null && groups.contains(focus)) AppearanceEditor.tab = focus;
    }
    if (widget.only == null && !groups.contains(group)) AppearanceEditor.tab = groups.first;
    var drawn = "${dna.toJson()}|${e.style.name}";
    var presets = presetsFor(group);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (presets.isNotEmpty)
          CanvasTiles<int>(
            label: group == AppearanceGroup.body ? "Body type" : "Start from",
            help: "A starting point for the ${group.label.toLowerCase()}, "
                "drawn on this character. Everything it sets is a slider "
                "below.",
            columns: 4,
            previewHeight: group == AppearanceGroup.body ? 72 : 56,
            tiles: [
              for (var (i, p) in presets.indexed)
                CanvasTile(i, p.name,
                    drawnFrom: "$drawn|${group.name}|$i",
                    paint: (canvas, size) =>
                        _presetTile(canvas, size, _withPreset(p))),
            ],
            selected: (i) => _isPreset(presets[i]),
            keyOf: (i) => "appearancePreset-${group.name}-${presets[i].name}",
            onPick: (i) => _dna(_withPreset(presets[i])),
          ),
        // Which part the sliders below shape: one dropdown across the row,
        // with the settings it chooses between.
        if (widget.only == null) CanvasControlGroup(
            key: const ValueKey("appearanceTabs"),
            label: "Part",
            help: "Which part of the character to shape. Each starts from "
                "how the character's type has it; Reset on a part puts it "
                "back.",
            children: [
              CanvasDropdown<AppearanceGroup>(
                key: const ValueKey("appearancePart"),
                label: "Part",
                value: group,
                options: [for (var g in groups) (g, g.label)],
                onChanged: (g) => setState(() => AppearanceEditor.tab = g),
              ),
            ]),
        ..._extras(drawn),
        CanvasControlGroup(
            key: ValueKey("appearanceSliders-${group.name}"),
            label: group.label,
            help: [
              for (var l in Look.inGroup(group)) "${l.label}: ${l.low} to ${l.high}",
            ].join(". "),
            children: [
              for (var l in Look.inGroup(group))
                CanvasSlider(
                  key: ValueKey("appearance-${l.name}"),
                  label: (l.needs != null && dna.look[l.needs!] == 0
                          ? "${l.label} (with a ${l.needs!.label.toLowerCase()})"
                          : l.label) +
                      (widget.keyed.contains(l) ? " ◆ keyed" : ""),
                  value: dna.look[l] * 100,
                  min: l.min * 100,
                  max: 100,
                  decimals: 0,
                  width: 150,
                  onChanged: (v) =>
                      _look(dna.look.withValue(l, v / 100), live: true),
                  onCommit: widget.commit,
                ),
              CanvasTextButton(
                key: ValueKey("appearanceReset-${group.name}"),
                icon: Icons.restart_alt,
                label: "Reset ${group.label.toLowerCase()}",
                grow: false,
                onPressed: () => _dna(_resetGroup()),
              ),
            ]),
        // What the canvas shapes it with: the face rig of the panel seen,
        // the puppet and the limbs' points.
        ...appearanceRigControls(
            widget.controller, e, group, widget.write, widget.commit),
      ],
    );
  }

  /// _resetGroup is this character with the open part as its type has it.
  CharacterDna _resetGroup() {
    var typed = dna.kind.dna.look;
    var next = dna.look.without(group).over(Appearance({
      for (var l in Look.inGroup(group))
        if (typed[l] != 0) l: typed[l],
    }));
    return dna.copyWith(
        look: next,
        build: group == AppearanceGroup.body ? dna.kind.dna.build : null);
  }

  CharacterDna _withPreset(AppearancePreset p) => dna.copyWith(
      look: dna.look.without(p.group).over(p.look), build: p.build);

  bool _isPreset(AppearancePreset p) {
    for (var l in Look.inGroup(p.group)) {
      if ((dna.look[l] - p.look[l]).abs() > 0.005) return false;
    }
    return p.build == null || (dna.build - p.build!).abs() < 0.005;
  }

  /// _extras is what a part has besides its sliders: its colours, a hair
  /// style, how tall and broad.
  List<Widget> _extras(String drawn) => switch (group) {
        AppearanceGroup.body => [
            CanvasControlGroup(
                key: const ValueKey("appearanceBodySize"),
                label: "Size",
                help: "How tall the character is in head lengths -- about "
                    "2½ for a chibi, 5½ for a cartoon, 7½ for a real adult "
                    "-- and how broad.",
                children: [
                  CanvasSlider(
                    key: const ValueKey("characterHeads"),
                    label: "Heads tall",
                    value: dna.headsTall,
                    min: CharacterDna.minHeads,
                    max: CharacterDna.maxHeads,
                    decimals: 1,
                    width: 150,
                    onChanged: (v) =>
                        _dna(dna.copyWith(headsTall: v), live: true),
                    onCommit: widget.commit,
                  ),
                  CanvasSlider(
                    key: const ValueKey("characterBuild"),
                    label: "Build",
                    value: dna.build * 100,
                    min: 0,
                    max: 100,
                    decimals: 0,
                    width: 150,
                    onChanged: (v) =>
                        _dna(dna.copyWith(build: v / 100), live: true),
                    onCommit: widget.commit,
                  ),
                ]),
          ],
        AppearanceGroup.skin => [
            CanvasControlGroup(label: "Colour", children: [
              CanvasColorButton(
                label: dna.species.animal ? "Fur" : "Skin",
                color: dna.skin,
                onChanged: (c) => _dna(dna.copyWith(skin: c)),
              ),
              if (dna.species.animal || dna.species == Species.monster)
                CanvasColorButton(
                  label: "Second",
                  color: dna.fur2,
                  onChanged: (c) => _dna(dna.copyWith(fur2: c)),
                ),
            ]),
          ],
        AppearanceGroup.eyes => [
            CanvasControlGroup(label: "Colour", children: [
              CanvasColorButton(
                label: "Eyes",
                color: dna.eyes,
                onChanged: (c) => _dna(dna.copyWith(eyes: c)),
              ),
            ]),
          ],
        AppearanceGroup.hair => [
            CanvasTiles<HairStyle>(
              label: "Style",
              help: "How the hair is cut. The sliders below shape any of "
                  "them.",
              columns: 5,
              previewHeight: 48,
              tiles: [
                for (var h in HairStyle.values)
                  CanvasTile(h, h.label,
                      drawnFrom: "$drawn|${h.name}",
                      paint: (canvas, size) =>
                          _presetTile(canvas, size, dna.copyWith(hairStyle: h))),
              ],
              selected: (h) => dna.hairStyle == h,
              keyOf: (h) => "characterHair-${h.name}",
              onPick: (h) => _dna(dna.copyWith(hairStyle: h)),
            ),
            // A sculpted body wears real hair: which, and which brows.
            if (e.body.kind == BodyKind.mannequin && HumanBody.instance.wearReady)
              CanvasControlGroup(label: "Sculpted", children: [
                CanvasDropdown<String>(
                  key: const ValueKey("characterHairModel"),
                  label: "Hair",
                  value: dna.hairModel,
                  options: [
                    ("", "As the style"),
                    for (var w in wearOfKind(WearKind.hair)) (w.id, w.label),
                  ],
                  onChanged: (id) => _dna(dna.copyWith(hairModel: id)),
                ),
                CanvasDropdown<String>(
                  key: const ValueKey("characterBrowModel"),
                  label: "Brows",
                  value: dna.browModel,
                  options: [
                    ("", "Usual"),
                    for (var w in wearOfKind(WearKind.eyebrows)) (w.id, w.label),
                  ],
                  onChanged: (id) => _dna(dna.copyWith(browModel: id)),
                ),
              ]),
            CanvasControlGroup(label: "Colours", children: [
              CanvasColorButton(
                label: "Hair",
                color: dna.hair,
                onChanged: (c) => _dna(dna.copyWith(hair: c)),
              ),
              CanvasColorButton(
                label: "Highlights",
                color: dna.hair2,
                onChanged: (c) => _dna(dna.copyWith(hair2: c)),
              ),
            ]),
          ],
        _ => const [],
      };

  /// _presetTile draws [d] for a tile of the open part: the whole figure
  /// for the body, the head close up for the rest.
  void _presetTile(ui.Canvas canvas, Size size, CharacterDna d) {
    var pose = d.fourLegs
        ? CharacterElement.restPose.withTurn(65)
        : CharacterElement.restPose;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (group == AppearanceGroup.body) {
      var h = size.height * 0.92;
      paintCharacterFigure(
          canvas,
          Rect.fromCenter(
              center: size.center(Offset.zero),
              width: d.fourLegs ? h * 0.9 : h * 0.45,
              height: h),
          d,
          pose,
          style: e.style);
    } else {
      // A head about the tile's height, the face in the middle of it.
      var h = size.height * 0.95 * d.headsTall;
      paintCharacterFigure(
          canvas,
          Rect.fromLTWH(size.width / 2 - h / 4, size.height * 0.1, h / 2, h),
          d,
          pose,
          style: e.style);
    }
    canvas.restore();
  }
}
