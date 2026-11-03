import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_asset.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/character_designs.dart';
import 'package:bruig/plugin_system/canvas/storage/character_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// character_assets.dart is the library's characters in the Assets sidebar:
// each made once in the Character Studio, placed in a scene with a click.
// See character_asset.dart.

/// CharacterAssetSection lists the library's characters, each drawn as it
/// stands, for a click to place a copy of it in the middle of the canvas.
class CharacterAssetSection extends StatelessWidget {
  final CanvasController controller;

  /// designs stands in for the library's 3D characters, for tests.
  final Future<List<CharacterDesign>> Function()? designs;
  const CharacterAssetSection(
      {required this.controller, this.designs, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return _Listed<List<CharacterAsset>>(
        changes: CharacterLibrary.changed,
        read: CharacterLibrary.list,
        builder: (context, listed) {
          var all = listed ?? const <CharacterAsset>[];
          // The new characters, in 3D: made in the new Studio, and placed
          // from here as the others are.
          var new3d =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          ]);
          // The panel is as tall as the sidebar gives it, and the two lists
          // can be taller: scrolled, not cut off.
          Widget scrolled(List<Widget> children) => SingleChildScrollView(
              key: const ValueKey("characterAssetsScroll"),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children));
          if (all.isEmpty) {
            return scrolled([
              new3d,
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    "None yet. Add a character to the canvas and edit it in "
                    "the Character Studio: pressing Done keeps it here, for "
                    "any scene.",
                    key: const ValueKey("characterAssetsEmpty"),
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurfaceVariant)),
              ),
            ]);
          }
          return scrolled([
            new3d,
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (var a in all)
                  _CharacterTile(
                    key: ValueKey("characterAsset-${a.id}"),
                    asset: a,
                    onTap: () => controller.placeCharacter(a),
                  ),
              ]),
            ),
          ]);
        });
  }
}

/// _Listed reads a library's list once for each change to it, however
/// often it is built: the sidebar is built again as it is scrolled and
/// resized, and reading the folder each time held every frame up.
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

class _CharacterTile extends StatelessWidget {
  final CharacterAsset asset;
  final VoidCallback onTap;
  const _CharacterTile({required this.asset, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Tooltip(
      message: "Place ${asset.name.isEmpty ? "it" : asset.name} on the canvas",
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 84,
            child: Column(children: [
              SizedBox(
                  width: 84,
                  height: 104,
                  // Painted once, not again on every frame of a scroll: a
                  // character is a costly drawing.
                  child: RepaintBoundary(
                      child: CustomPaint(painter: _CharacterThumb(asset)))),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(asset.name.isEmpty ? "Character" : asset.name,
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

/// _CharacterThumb draws a library character standing in its tile.
class _CharacterThumb extends CustomPainter {
  final CharacterAsset asset;
  _CharacterThumb(this.asset);

  @override
  void paint(ui.Canvas canvas, Size size) {
    var h = size.height * 0.92, w = h * 0.5;
    var e = asset.element(ElementBase(
        id: "thumb-${asset.id}",
        x: (size.width - w) / 2,
        y: size.height * 0.04,
        width: w,
        height: h));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintElement(canvas, e, 0);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CharacterThumb old) => old.asset != asset;
}

/// Character3dAssetList is the library's 3D characters, each as it was last
/// drawn in the Studio, for a click to place one in the middle of the
/// canvas.
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
          if (all.isEmpty) return const SizedBox.shrink();
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
  const _Character3dTile(
      {required this.design, required this.onTap, super.key});

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
                child: FutureBuilder<Uint8List?>(
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
