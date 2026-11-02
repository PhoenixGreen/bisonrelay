import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_asset.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/character_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_assets.dart is the library's characters in the Assets sidebar:
// each made once in the Character Studio, placed in a scene with a click.
// See character_asset.dart.

/// CharacterAssetSection lists the library's characters, each drawn as it
/// stands, for a click to place a copy of it in the middle of the canvas.
class CharacterAssetSection extends StatelessWidget {
  final CanvasController controller;
  const CharacterAssetSection({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return ValueListenableBuilder<int>(
      valueListenable: CharacterLibrary.changed,
      builder: (context, _, __) => FutureBuilder<List<CharacterAsset>>(
        future: CharacterLibrary.list(),
        builder: (context, snap) {
          var all = snap.data ?? const <CharacterAsset>[];
          if (all.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  "None yet. Add a character to the canvas and edit it in "
                  "the Character Studio: pressing Done keeps it here, for "
                  "any scene.",
                  key: const ValueKey("characterAssetsEmpty"),
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (var a in all)
                _CharacterTile(
                  key: ValueKey("characterAsset-${a.id}"),
                  asset: a,
                  onTap: () => controller.placeCharacter(a),
                ),
            ]),
          );
        },
      ),
    );
  }
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
                  child: CustomPaint(painter: _CharacterThumb(asset))),
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
