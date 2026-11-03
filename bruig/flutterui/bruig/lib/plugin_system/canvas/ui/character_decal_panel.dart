import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_decal_panel.dart is the new Character Studio's decals: pictures
// and vectors from the canvas library laid on the skin or the clothes -- a
// tattoo, a brand on a shirt -- placed on a part of the body, sized, turned
// and drawn as printed, tattooed, faded or in one ink. See character_decal.dart.

/// The list's id for the decals.
const String decalsPartId = "decals";

/// CharacterDecalControls are the decals: the library's pictures and
/// vectors to add, the decals on the character, and the open one's settings.
class CharacterDecalControls extends StatelessWidget {
  final List<CharacterDecal> decals;

  /// open is the decal being set, if any.
  final String? open;
  final CharacterOutfit outfit;
  final void Function(List<CharacterDecal> decals, String? open) onChanged;

  /// library stands in for the canvas library's pictures and vectors, for
  /// tests.
  final Future<List<LibraryAsset>> Function()? library;

  const CharacterDecalControls(
      {required this.decals,
      required this.open,
      required this.outfit,
      required this.onChanged,
      this.library,
      super.key});

  static const _inks = [
    0x1b1a22,
    0x263552,
    0x3e6145,
    0x9c3a32,
    0x6a3d6e,
    0xf4f1ea
  ];

  Future<List<LibraryAsset>> _library() async => [
        ...await CanvasLibrary.list(kind: AssetKind.picture),
        ...await CanvasLibrary.list(kind: AssetKind.vector),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    final d = decals.where((x) => x.id == open).firstOrNull;
    void put(CharacterDecal n) =>
        onChanged([for (final x in decals) x.id == n.id ? n : x], n.id);
    Widget slider(String key, String label, double value,
            CharacterDecal Function(double) change,
            {double min = 0,
            double max = 1,
            double rest = 0,
            String Function(double)? format}) =>
        StudioSlider(
          key: ValueKey("decal-$key"),
          label: label,
          value: value,
          min: min,
          max: max,
          rest: rest,
          format: format,
          onChanged: (v) => put(change(v)),
        );
    String turns(double v) => "${(v * 180).round()}°";
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const StudioPanelHead(
            title: "Decals and tattoos",
            says:
                "Pictures and vectors from your library, laid on the skin or the "
                "clothes. They lie on the surface itself, so they follow the body's "
                "shape and move with it, and clothes cover a tattoo.",
          ),
          const StudioLabel("Add from your library"),
          ValueListenableBuilder<int>(
            valueListenable: CanvasLibrary.changes,
            builder: (context, _, __) => FutureBuilder<List<LibraryAsset>>(
              future: (library ?? _library)(),
              builder: (context, snap) {
                final all = snap.data ?? const <LibraryAsset>[];
                if (all.isEmpty) {
                  return Text(
                      "Pictures and vectors you add to the canvas library show here.",
                      key: const ValueKey("decalLibraryEmpty"),
                      style: TextStyle(
                          fontSize: 12, color: colors.onSurfaceVariant));
                }
                // Six and a half rows at most, scrolled: a long library
                // would push the decal's own settings off the panel.
                return ConstrainedBox(
                  key: const ValueKey("decalLibrary"),
                  constraints: const BoxConstraints(maxHeight: 6.5 * 58),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      primary: false,
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final a in all)
                          Tooltip(
                            message: a.name,
                            child: InkWell(
                              key: ValueKey("decalAdd-${a.id}"),
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                final n = CharacterDecal(
                                  id: "${DateTime.now().microsecondsSinceEpoch}",
                                  source:
                                      "${a.kind == AssetKind.vector ? "vector" : "picture"}:${a.id}",
                                  name: a.name,
                                );
                                onChanged([...decals, n], n.id);
                              },
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: colors.outlineVariant),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: AssetThumb(id: a.id),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          if (decals.isNotEmpty)
            StudioPills<String>(
              key: const ValueKey("decalList"),
              id: "decal",
              label: "On the character",
              value: open ?? "",
              options: [
                for (final (i, x) in decals.indexed)
                  (x.id, x.name.isEmpty ? "Decal ${i + 1}" : x.name),
              ],
              onChanged: (id) => onChanged(decals, id),
            ),
          if (d != null) ...[
            StudioPills<String>(
              key: const ValueKey("decal-on"),
              id: "decal-on",
              label: "On",
              value: d.on,
              options: [
                ("skin", "Skin"),
                for (final s in WearSlot.values)
                  if (outfit[s].source != WearSource.none) (s.name, s.label),
              ],
              onChanged: (v) => put(d.copyWith(on: v)),
            ),
            StudioPills<DecalArea>(
              key: const ValueKey("decal-area"),
              id: "decal-area",
              label: "Where",
              value: d.area,
              options: [for (final a in DecalArea.values) (a, a.label)],
              onChanged: (v) => put(d.copyWith(area: v)),
            ),
            const SizedBox(height: 6),
            slider(
                "along",
                d.area == DecalArea.torso ||
                        d.area == DecalArea.neck ||
                        d.area == DecalArea.head
                    ? "Up"
                    : "Along",
                d.along,
                (v) => d.copyWith(along: v),
                rest: 0.6),
            slider("around", "Around", d.around, (v) => d.copyWith(around: v),
                min: -1, format: turns),
            slider("size", "Size", d.size, (v) => d.copyWith(size: v),
                min: 0.01,
                max: 0.5,
                rest: 0.08,
                format: (v) => "${(v * 100).round()}%"),
            slider("turn", "Turn", d.turn, (v) => d.copyWith(turn: v),
                min: -1, format: turns),
            slider(
                "opacity", "Opacity", d.opacity, (v) => d.copyWith(opacity: v),
                rest: 1),
            StudioPills<String>(
              key: const ValueKey("decal-mode"),
              id: "decal-mode",
              label: "Look",
              value: d.mode,
              options: decalModes,
              onChanged: (v) => put(d.copyWith(mode: v)),
            ),
            if (d.mode == "ink")
              StudioSwatches(
                id: "decal-ink",
                label: "Ink",
                palette: _inks,
                value: d.ink,
                onPick: (c) => put(d.copyWith(ink: c ?? d.ink)),
              ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: StudioPill(
                key: const ValueKey("decalRemove"),
                label: "Take it off",
                onTap: () => onChanged([
                  for (final x in decals)
                    if (x.id != d.id) x
                ], null),
              ),
            ),
          ],
        ]);
  }
}
