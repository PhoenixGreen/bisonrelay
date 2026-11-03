import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_shape_panel.dart is the Character base step of the new
// Character Studio: its parts down the left, and the open part's settings
// on the right (the clothes' are in character_outfit_panel.dart). Apart
// from the stage, so it is tested without Flutter GPU.

/// The list's ids for what is not a shaping part: the body to start from,
/// the whole outfit, and each piece of it.
const String startPartId = "start";
const String outfitPartId = "outfit";
String wearPartId(WearSlot s) => "wear-${s.name}";
WearSlot? wearSlotOf(String id) =>
    WearSlot.values.where((s) => wearPartId(s) == id).firstOrNull;

/// CharacterShapeList is every part under its heading, then the clothes,
/// a dot beside each one changed from how the body was made.
class CharacterShapeList extends StatelessWidget {
  final CharacterShape shape;
  final CharacterOutfit outfit;

  /// styled is whether the Drawing style is not the one started from;
  /// decorated whether any decals are on.
  final bool styled, decorated;
  final String selected;
  final ValueChanged<String> onSelect;
  const CharacterShapeList(
      {required this.shape,
      this.outfit = CharacterOutfit.asDesigned,
      this.styled = false,
      this.decorated = false,
      required this.selected,
      required this.onSelect,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    final rows = <Widget>[];
    void heading(String text) => rows.add(Padding(
          padding: EdgeInsets.fromLTRB(16, rows.isEmpty ? 14 : 20, 16, 6),
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant)),
        ));
    void row(String id, String name, bool changed) {
      final on = id == selected;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color:
              on ? colors.primary.withValues(alpha: 0.14) : Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
              side: BorderSide(
                  color: on ? colors.primary : Colors.transparent, width: 1.2)),
          child: InkWell(
            key: ValueKey("shapePart-$id"),
            borderRadius: BorderRadius.circular(7),
            onTap: () => onSelect(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(children: [
                Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface)),
                ),
                if (changed)
                  Container(
                    key: ValueKey("shapeChanged-$id"),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: colors.primary, shape: BoxShape.circle),
                  ),
              ]),
            ),
          ),
        ),
      ));
    }

    String? group;
    for (final p in characterShapeParts) {
      if (p.group != group) {
        heading(group = p.group);
        if (rows.length == 1) row(startPartId, "Start from", false);
      }
      row(p.id, p.name, shape.changed(p));
      if (p.id == "figure") row("style", "Drawing style", styled);
    }
    heading("Clothes");
    row(outfitPartId, "Outfit", outfit != CharacterOutfit.asDesigned);
    for (final s in WearSlot.values) {
      row(wearPartId(s), s.label, outfit.changed(s));
    }
    row("decals", "Decals and tattoos", decorated);
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: rows);
  }
}

/// CharacterShapeControls are [part]'s settings: what it changes, its
/// presets and choices as pills, its numbers as sliders, and a way back to
/// how it was made.
class CharacterShapeControls extends StatelessWidget {
  final ShapePart part;
  final CharacterShape shape;
  final ValueChanged<CharacterShape> onChanged;
  const CharacterShapeControls(
      {required this.part,
      required this.shape,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    Widget control(ShapeControl c) => switch (c) {
          ShapePresets() => StudioPills<String>(
              key: ValueKey("shape-${c.key}"),
              id: c.key,
              label: c.label,
              value: shape.choice(c.key),
              options: [for (final n in c.presets.keys) (n, n)],
              onChanged: (n) => onChanged(shape.withPreset(c, n)),
            ),
          ShapeChoice() => StudioPills<String>(
              key: ValueKey("shape-${c.key}"),
              id: c.key,
              label: c.label,
              value: shape.choice(c.key),
              options: c.options,
              onChanged: (v) => onChanged(shape.withChoice(c.key, v)),
            ),
          ShapeColour() => StudioSwatches(
              key: ValueKey("shape-${c.key}"),
              id: "shape-${c.key}",
              label: c.label,
              palette: c.palette,
              value: shape.colour(c.key),
              asMade: true,
              onPick: (v) => onChanged(shape.withColour(c.key, v)),
            ),
          ShapeHairStyles() => StudioPills<String>(
              key: const ValueKey("shape-hair.style"),
              id: "hair.style",
              label: "Hairstyle",
              value: shape.choice("hair.style"),
              options: [for (final h in hairStyles) (h.id, h.name)],
              onChanged: (id) => onChanged(shape
                  .withHairStyle(hairStyles.firstWhere((h) => h.id == id))),
            ),
          ShapeSlider() => StudioSlider(
              key: ValueKey("shape-${c.key}"),
              label: c.label,
              value: shape.get(c.key),
              min: c.min,
              max: c.max,
              rest: CharacterShape.defaultOf(c.key),
              format: c.whole ? (v) => "${v.round()}" : null,
              onChanged: (v) => onChanged(
                  shape.withValue(c.key, c.whole ? v.roundToDouble() : v)),
            ),
        };
    final controls = <Widget>[];
    for (final c in part.controls) {
      // A run of sliders after a row of pills sits a little way under it.
      if (c is ShapeSlider &&
          controls.isNotEmpty &&
          controls.last is! StudioSlider) {
        controls.add(const SizedBox(height: 8));
      }
      controls.add(control(c));
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          StudioPanelHead(
            title: part.name,
            says: part.says,
            onReset:
                shape.changed(part) ? () => onChanged(shape.reset(part)) : null,
          ),
          const SizedBox(height: 6),
          ...controls,
        ]);
  }
}
