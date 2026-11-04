import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_cast3d.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/storage/character_designs.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// character_assets.dart is the library's characters in the Assets sidebar,
// made in the Character Studio and placed with a click. See
// character_designs.dart.

/// CharacterAssetSection lists the library's 3D characters as last drawn in
/// the Studio, for a click to place a copy in the middle of the canvas, and a
/// way to make a new one.
class CharacterAssetSection extends StatelessWidget {
  final CanvasController controller;

  /// designs stands in for the library's 3D characters, for tests.
  final Future<List<CharacterDesign>> Function()? designs;
  const CharacterAssetSection(
      {required this.controller, this.designs, super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        // Scrolled, not cut off, when the list is taller than the panel.
        key: const ValueKey("characterAssetsScroll"),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: TextButton.icon(
              key: const ValueKey("characterAssetsNew3d"),
              onPressed: () => controller.openStudio3d(),
              icon: const Icon(Icons.view_in_ar_outlined, size: 16),
              label: const Text("New 3D character"),
            ),
          ),
          Character3dAssetList(
              onPlace: controller.placeCharacter3d, designs: designs),
          // And the ready-made cast, to place as they are.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text("Ready-made",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ThemeNotifier.of(context).colors.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in readyMadeCast)
                _Character3dTile(
                    key: ValueKey("characterCast-${m.design.name}"),
                    design: m.design,
                    picture: m.picture,
                    onTap: () => controller.placeCharacter3d(m.design)),
            ]),
          ),
        ]),
      );
}

/// _Listed reads a library's list once per change to it, not per build: the
/// sidebar rebuilds as it scrolls and resizes, and reading the folder each
/// time held frames up.
class _Listed<T> extends StatefulWidget {
  final ValueListenable<int> changes;
  final Future<T> Function() read;
  final Widget Function(BuildContext context, T? listed) builder;
  const _Listed(
      {required this.changes, required this.read, required this.builder});

  @override
  State<_Listed<T>> createState() => _ListedState<T>();
}

class _ListedState<T> extends State<_Listed<T>> {
  Future<T>? _future;
  int? _at;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: widget.changes,
        builder: (context, at, _) {
          if (_future == null || at != _at) {
            _at = at;
            _future = widget.read();
          }
          return FutureBuilder<T>(
              future: _future,
              builder: (context, snap) => widget.builder(context, snap.data));
        },
      );
}

/// Character3dAssetList is the library's 3D characters as last drawn in the
/// Studio, for a click to place one in the middle of the canvas.
class Character3dAssetList extends StatelessWidget {
  final void Function(CharacterDesign design) onPlace;
  final Future<List<CharacterDesign>> Function()? designs;
  const Character3dAssetList({required this.onPlace, this.designs, super.key});

  @override
  Widget build(BuildContext context) => _Listed<List<CharacterDesign>>(
        changes: CharacterDesigns.changed,
        read: designs ?? CharacterDesigns.list,
        builder: (context, listed) {
          var all = listed ?? const <CharacterDesign>[];
          if (all.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  "None yet. Make one with New 3D character: pressing Done "
                  "in the Character Studio keeps it here, for any scene.",
                  key: const ValueKey("characterAssetsEmpty"),
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          ThemeNotifier.of(context).colors.onSurfaceVariant)),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (var d in all)
                _Character3dTile(
                    key: ValueKey("character3dAsset-${d.id}"),
                    design: d,
                    onTap: () => onPlace(d)),
            ]),
          );
        },
      );
}

class _Character3dTile extends StatefulWidget {
  final CharacterDesign design;
  final VoidCallback onTap;

  /// picture is its picture among the app's assets, for one of the
  /// ready-made cast; otherwise the one kept with it in the library.
  final String? picture;
  const _Character3dTile(
      {required this.design, required this.onTap, this.picture, super.key});

  @override
  State<_Character3dTile> createState() => _Character3dTileState();
}

class _Character3dTileState extends State<_Character3dTile> {
  /// _picture is the character's picture, read once and again only when
  /// the character is kept again.
  late Future<Uint8List?> _picture = CharacterDesigns.picture(widget.design.id);

  @override
  void didUpdateWidget(_Character3dTile old) {
    super.didUpdateWidget(old);
    if (old.design.id != widget.design.id ||
        old.design.updated != widget.design.updated) {
      _picture = CharacterDesigns.picture(widget.design.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    var design = widget.design, onTap = widget.onTap;
    var colors = ThemeNotifier.of(context).colors;
    var name = design.name.isEmpty ? "Character" : design.name;
    return Tooltip(
      message: "Place $name on the canvas",
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 84,
            child: Column(children: [
              SizedBox(
                width: 84,
                height: 112,
                child: widget.picture != null
                    ? Image.asset(widget.picture!,
                        fit: BoxFit.cover,
                        cacheWidth: 168,
                        errorBuilder: (_, __, ___) => Center(
                            child: Icon(Icons.view_in_ar_outlined,
                                size: 32, color: colors.onSurfaceVariant)))
                    : FutureBuilder<Uint8List?>(
                        future: _picture,
                        builder: (context, snap) {
                          var icon = Center(
                              child: Icon(Icons.view_in_ar_outlined,
                                  size: 32, color: colors.onSurfaceVariant));
                          var png = snap.data;
                          if (png == null) return icon;
                          return Image.memory(png,
                              fit: BoxFit.cover,
                              cacheWidth: 168,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => icon);
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.onSurface)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
