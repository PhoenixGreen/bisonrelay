import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// character_hair_settings.dart is a sketch's hair as strokes, in its hair
// layers' settings: hair made of strokes or as its style draws it, each
// group's length, volume, curl and width, and each stroke -- where on the
// scalp it grows, how long, leaning and curling, and how wide at its root,
// middle and tip -- to add, take away and mirror. See character_hair.dart.

/// HairStrokesEditor edits [character]'s hair strokes.
class HairStrokesEditor extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
  final SettingsWrite write;
  final VoidCallback commit;
  const HairStrokesEditor(
      {required this.controller,
      required this.character,
      required this.write,
      required this.commit,
      super.key});

  /// group and stroke are the group and the stroke of it picked, kept from
  /// one character to the next.
  static HairGroup group = HairGroup.fringe;
  static int stroke = 0;

  @override
  State<HairStrokesEditor> createState() => _HairStrokesEditorState();
}

class _HairStrokesEditorState extends State<HairStrokesEditor> {
  CharacterElement get e => widget.character;

  /// _seen is the stroke picked on the canvas when last seen.
  int? _seen;

  void _rig(HairRig? rig, {bool live = false}) {
    widget.controller.beginInteraction();
    widget.write(e.copyWith(
        dna: rig == null
            ? e.dna.copyWith(noHairRig: true)
            : e.dna.copyWith(hairRig: rig)));
    if (!live) widget.commit();
  }

  @override
  Widget build(BuildContext context) {
    var rig = e.dna.hairRig;
    var presets = hairPresets;
    var made = CanvasControlGroup(
        key: const ValueKey("characterHairMade"),
        label: "Made of",
        help: "Hair as its style draws it, or made of strokes: each one "
            "growing from the scalp, so it turns with the head on every view, "
            "in front of the face where it grows on the near side and behind "
            "it on the far side. Start from one of these and shape it.",
        children: [
          CanvasDropdown<String>(
            key: const ValueKey("characterHairPreset"),
            label: "Hair",
            value: rig == null
                ? ""
                : (presets.any((p) => p.name == rig.name) ? rig.name : "*"),
            options: [
              ("", "As its style draws it"),
              for (var p in presets) (p.name, "Strokes: ${p.name}"),
              if (rig != null && !presets.any((p) => p.name == rig.name))
                ("*", "Strokes: ${rig.name}"),
            ],
            onChanged: (name) {
              if (name == "*") return;
              _rig(name.isEmpty
                  ? null
                  : presets.firstWhere((p) => p.name == name));
            },
          ),
          if (rig != null)
            CanvasToggle(
              key: const ValueKey("characterHairEdit"),
              label: "Shape it on the canvas",
              value: widget.controller.editHair,
              onChanged: (v) => widget.controller.editHair = v,
            ),
        ]);
    if (rig == null) return made;

    // A stroke picked on the canvas: its group and it, here.
    if (widget.controller.hairPick case var i?
        when i != _seen && i < rig.strokes.length) {
      HairStrokesEditor.group = rig.strokes[i].group;
      HairStrokesEditor.stroke =
          rig.inGroup(rig.strokes[i].group).indexWhere((s) => s.$1 == i);
    }
    _seen = widget.controller.hairPick;
    var group = HairStrokesEditor.group;
    var strokes = rig.inGroup(group);
    if (HairStrokesEditor.stroke >= strokes.length) {
      HairStrokesEditor.stroke = 0;
    }
    var picked = strokes.isEmpty ? null : strokes[HairStrokesEditor.stroke];
    var look = rig.lookOf(group);

    Widget slider(String key, String label, double value, double min,
            double max, void Function(double) set) =>
        CanvasSlider(
          key: ValueKey(key),
          label: label,
          value: value,
          min: min,
          max: max,
          decimals: 2,
          width: 150,
          onChanged: set,
          onCommit: widget.commit,
        );

    void setStroke(HairStroke s) =>
        _rig(rig.withStroke(picked!.$1, s), live: true);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      made,
      CanvasControlGroup(
          key: const ValueKey("characterHairGroup"),
          label: "Group",
          help: "The fringe, the sides, the top and the back: each group's "
              "strokes made longer, fuller, curlier or wider together.",
          children: [
            CanvasDropdown<HairGroup>(
              key: const ValueKey("characterHairGroupPick"),
              label: "Group",
              value: group,
              options: [
                for (var g in HairGroup.values)
                  (g, "${g.label} · ${rig.inGroup(g).length}"),
              ],
              onChanged: (g) => setState(() {
                HairStrokesEditor.group = g;
                HairStrokesEditor.stroke = 0;
              }),
            ),
            slider(
                "characterHairGroupLength",
                "Length",
                look.length,
                0.1,
                4,
                (v) => _rig(rig.withGroup(group, look.copyWith(length: v)),
                    live: true)),
            slider(
                "characterHairGroupVolume",
                "Volume",
                look.volume,
                0,
                3,
                (v) => _rig(rig.withGroup(group, look.copyWith(volume: v)),
                    live: true)),
            slider(
                "characterHairGroupCurl",
                "Curl",
                look.curl,
                -1,
                1,
                (v) => _rig(rig.withGroup(group, look.copyWith(curl: v)),
                    live: true)),
            slider(
                "characterHairGroupWidth",
                "Width",
                look.width,
                0.2,
                3,
                (v) => _rig(rig.withGroup(group, look.copyWith(width: v)),
                    live: true)),
          ]),
      CanvasControlGroup(
          key: const ValueKey("characterHairStroke"),
          label: picked == null
              ? "No strokes"
              : "Stroke ${HairStrokesEditor.stroke + 1} of ${strokes.length}",
          help: "One stroke of the group: where on the scalp it grows -- round "
              "the head from the front, and up from the middle -- how long it "
              "is, how it leans and curls, and how wide it is at its root, its "
              "middle and its tip.",
          children: [
            if (strokes.length > 1)
              CanvasStepper(
                key: const ValueKey("characterHairStrokePick"),
                label: "Stroke",
                value: HairStrokesEditor.stroke + 1.0,
                min: 1,
                max: strokes.length.toDouble(),
                step: 1,
                onChanged: (v) =>
                    setState(() => HairStrokesEditor.stroke = v.round() - 1),
              ),
            if (picked != null) ...[
              slider("characterHairLon", "Round the head", picked.$2.lon, -180,
                  180, (v) => setStroke(picked.$2.copyWith(lon: v))),
              slider("characterHairLat", "Up the head", picked.$2.lat, -60, 90,
                  (v) => setStroke(picked.$2.copyWith(lat: v))),
              slider("characterHairLength", "Length", picked.$2.length, 0.02, 3,
                  (v) => setStroke(picked.$2.copyWith(length: v))),
              slider("characterHairLean", "Lean", picked.$2.lean, -1.5, 1.5,
                  (v) => setStroke(picked.$2.copyWith(lean: v))),
              slider("characterHairCurl", "Curl", picked.$2.curl, -1.5, 1.5,
                  (v) => setStroke(picked.$2.copyWith(curl: v))),
              slider("characterHairW0", "Root width", picked.$2.w0, 0, 0.5,
                  (v) => setStroke(picked.$2.copyWith(w0: v))),
              slider("characterHairW1", "Middle width", picked.$2.w1, 0, 0.5,
                  (v) => setStroke(picked.$2.copyWith(w1: v))),
              slider("characterHairW2", "Tip width", picked.$2.w2, 0, 0.5,
                  (v) => setStroke(picked.$2.copyWith(w2: v))),
            ],
            CanvasTextButton(
              key: const ValueKey("characterHairAdd"),
              label: "Add stroke",
              icon: Icons.add,
              onPressed: () {
                if (picked == null) {
                  _rig(HairRig(rig.name,
                      [...rig.strokes, HairStroke(group, 0, 40)], rig.groups));
                  return;
                }
                var (next, _) = rig.withAdded(picked.$1);
                HairStrokesEditor.stroke++;
                _rig(next);
              },
            ),
            if (picked != null) ...[
              CanvasTextButton(
                key: const ValueKey("characterHairRemove"),
                label: "Remove stroke",
                icon: Icons.remove,
                onPressed: () {
                  if (HairStrokesEditor.stroke > 0) HairStrokesEditor.stroke--;
                  _rig(rig.without(picked.$1));
                },
              ),
              CanvasTextButton(
                key: const ValueKey("characterHairMirror"),
                label: "Mirror to the other side",
                icon: Icons.flip,
                onPressed: () => _rig(HairRig(rig.name,
                    [...rig.strokes, picked.$2.mirrored], rig.groups)),
              ),
            ],
          ]),
    ]);
  }
}
