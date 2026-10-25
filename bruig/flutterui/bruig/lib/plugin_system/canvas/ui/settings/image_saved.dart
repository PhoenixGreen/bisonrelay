import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/presets_section.dart';
import 'package:flutter/material.dart';

// image_saved.dart is what a picture keeps to use again: its looks -- the
// grade without the photograph: adjustments, textures, colour layers -- and
// its designs, the whole element as a preset. One card with a switch
// between the two, in Colour, since a look is a colour grade; the designs
// beside them, since both are a thing saved and worn again.

/// _showingLooks is which the card shows, for this run of the app: looks,
/// unless designs were last asked for.
bool _showingLooks = true;

/// ImageSaved is a picture's saved looks and designs.
class ImageSaved extends StatefulWidget {
  final CanvasController controller;
  final ImageElement element;
  const ImageSaved(
      {required this.controller, required this.element, super.key});

  @override
  State<ImageSaved> createState() => _ImageSavedState();
}

class _ImageSavedState extends State<ImageSaved> {
  final store = SavedPresetStore.looks;
  String? _name;

  /// _worn is the look last put on this picture, which can be deleted.
  String? _worn;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    var kind = CanvasControlGroup(
      key: const ValueKey("imageSaved"),
      label: "Saved",
      rule: false,
      children: [
        CanvasSegmented<bool>(
          key: const ValueKey("imageSavedKind"),
          options: const [(true, "Looks"), (false, "Designs")],
          value: _showingLooks,
          keyOf: (looks) => looks ? "imageSavedLooks" : "imageSavedDesigns",
          onChanged: (looks) => setState(() => _showingLooks = looks),
        ),
        const CanvasHint("Looks are a picture's adjustments, textures and "
            "colour layers -- never its pictures -- to put on another "
            "picture: point at one to see it on the canvas, click it to "
            "wear it. Designs are the whole element, to start another "
            "from."),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        kind,
        if (_showingLooks)
          ListenableBuilder(listenable: store, builder: (c, _) => _looks(c))
        else
          presetsSection(context, widget.controller, widget.element),
      ],
    );
  }

  Widget _looks(BuildContext context) {
    var controller = widget.controller;
    var e = widget.element;
    var saved = store.presets;
    var name = _name ?? "Look ${saved.length + 1}";
    var hasLook = e.stack.any((l) => lookKinds.contains(l.kind));
    var images = controller.images;
    // The tiles are drawn once and kept: drawn again when the picture
    // under them is, or comes in.
    var picture = e.hasImage ? images.resolve(e.assetId, e.removal) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (saved.isNotEmpty)
          CanvasTiles<String>(
            key: const ValueKey("imageLookTiles"),
            label: "Wear a look",
            help: "Each look on this picture. Point at one to see it on the "
                "canvas; click it to wear it.",
            columns: 3,
            previewHeight: 52,
            tiles: [
              for (var p in saved)
                CanvasTile(p.id, p.name,
                    drawnFrom: (p.id, e.assetId, e.removal, picture != null),
                    paint: (canvas, size) => _paintWearing(
                        canvas, size, withLookApplied(e, p.data), images)),
            ],
            selected: (id) => id == _worn,
            keyOf: (id) => "imageLook-$id",
            onPreview: (id) {
              var p = saved.where((p) => p.id == id).firstOrNull;
              controller
                  .tryElement(p == null ? null : withLookApplied(e, p.data));
            },
            onPick: (id) {
              var p = saved.where((p) => p.id == id).firstOrNull;
              if (p == null) return;
              setState(() => _worn = p.id);
              controller.changeImage(withLookApplied(e, p.data));
            },
          ),
        CanvasControlGroup(
          key: const ValueKey("imageLooks"),
          label: "Keep this look",
          rule: false,
          children: [
            CanvasTextField(
              key: const ValueKey("imageLookName"),
              label: "Name",
              value: name,
              width: 130,
              onChanged: (v) => setState(() => _name = v),
            ),
            CanvasIconButton(
              key: const ValueKey("imageLookSave"),
              icon: Icons.bookmark_add_outlined,
              tooltip: "Keep this picture's look",
              onPressed: name.trim().isEmpty || !hasLook
                  ? null
                  : () async {
                      // The same name again is the same look, changed.
                      for (var p in saved.where((p) => p.name == name.trim())) {
                        await store.remove(p);
                      }
                      await store.save(name, lookData(e));
                      if (mounted) setState(() => _name = null);
                    },
            ),
            if (saved.where((p) => p.id == _worn).firstOrNull case var worn?)
              CanvasIconButton(
                key: const ValueKey("imageLookDelete"),
                icon: Icons.delete_outline,
                tooltip: "Delete the look ${worn.name}",
                onPressed: () async {
                  await store.remove(worn);
                  if (mounted) setState(() => _worn = null);
                },
              ),
            CanvasHint(hasLook
                ? "Keeps this picture's adjustments, textures and colour "
                    "layers -- never its pictures -- as a look to wear on "
                    "another picture."
                : "Add adjustments or textures, then keep them as a look "
                    "for other pictures."),
          ],
        ),
      ],
    );
  }
}

/// _paintWearing draws [e] -- a picture wearing a look -- to fit [size], as
/// it settles: without its arrival or its loop, which would draw a picture
/// still to come in as nothing.
void _paintWearing(
    ui.Canvas canvas, Size size, ImageElement e, CanvasImageSource images) {
  var b = e.bounds;
  if (b.isEmpty) return;
  var k = math.min(size.width / b.width, size.height / b.height);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  canvas.translate(
      (size.width - b.width * k) / 2, (size.height - b.height * k) / 2);
  canvas.scale(k);
  canvas.translate(-b.left, -b.top);
  paintElement(canvas, e.copyWith(animation: const ElementAnimation()), 0,
      images: images);
  canvas.restore();
}
