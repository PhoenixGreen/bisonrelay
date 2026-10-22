import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/image_masking.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// image_layer_settings.dart is a picture's layers and what works on them:
// the strip of layers that opens into a list, adding one, the tools as tiles
// with the settings of the one in hand, the picked layer's blend and
// strength, and its place. The sections they are laid out in are
// image_sections.dart's.

/// layerAdds are the kinds of layer that can be added, as the Add tiles
/// show them.
enum LayerAdd {
  picture("Picture", Icons.add_photo_alternate_outlined, "imageAddPicture"),
  recent("Your pictures", Icons.photo_library_outlined, "imageAddRecent"),
  adjustment("Adjustment", Icons.tune, "imageAddAdjustment"),
  texture("Texture", Icons.grain, "imageAddTexture"),
  paint("Paint", Icons.brush, "imageAddPaint"),
  fill("Colour fill", Icons.format_color_fill, "imageAddFill");

  final String label;
  final IconData icon;
  final String key;
  const LayerAdd(this.label, this.icon, this.key);
}

/// addImageLayerOf adds a layer of the kind [what] to [e], opening its layers
/// first so the new one is there to be worked on.
Future<void> addImageLayerOf(BuildContext context, CanvasController controller,
    ImageElement e, LayerAdd what) async {
  var editing = controller.imageEditing == e.id;
  var inner = e.box.inner(e.bounds);
  Future<void> picture(String? id) async {
    if (id == null) return;
    var size = await pictureSize(id) ?? const Size(1, 1);
    if (controller.imageEditing != e.id) controller.editImage(e.id);
    // An empty base is filled first: the first picture is what the others
    // go over, and the frame takes its shape.
    var now = controller.editingImage ?? e;
    if (!now.hasImage) {
      controller.changeImage(fitToPicture(now.copyWith(assetId: id), size));
      controller.pickImageLayer(baseLayerId);
      return;
    }
    controller.addImageLayer(ImageLayer.picture(id, placeFor(inner, size)));
  }

  switch (what) {
    case LayerAdd.picture:
      await picture(await pickCanvasImage(context, vectors: false));
      return;
    case LayerAdd.recent:
      await picture(await showRecentPictures(context));
      return;
    default:
  }
  if (!editing) controller.editImage(e.id);
  // Over an empty base, anything else is the bottom of the picture: added
  // just over the base, whatever was picked.
  if (!e.hasImage) controller.pickImageLayer(baseLayerId);
  switch (what) {
    case LayerAdd.adjustment:
      controller.addImageLayer(ImageLayer.adjusting(AdjustKind.hueSaturation));
    case LayerAdd.texture:
      controller.addImageLayer(ImageLayer.texturing(TextureKind.grain));
    case LayerAdd.paint:
      controller.addImageLayer(ImageLayer.painting());
      controller.imageTool = ImageTool.paint;
    case LayerAdd.fill:
      // Half strength, so what it does to the layers under it is seen the
      // moment it arrives instead of a frame of flat colour.
      controller.addImageLayer(
          ImageLayer.solid(const PaintSpec(Color(0xFF1E2A38)))
              .copyWith(opacity: 0.5));
    default:
  }
}

/// layerKindLabel is what kind of layer [layer] is, in a word or two.
String layerKindLabel(ImageLayer layer) => switch (layer.kind) {
      LayerKind.base => "Base picture",
      LayerKind.picture => "Picture",
      LayerKind.fill => "Colour fill",
      LayerKind.adjustment => "Adjustment",
      LayerKind.texture => "Texture",
      LayerKind.paint => "Paint",
    };

/// LayerThumbnail is a small picture of a layer: its picture, its colour, or
/// an icon for what it does.
class LayerThumbnail extends StatelessWidget {
  final CanvasController controller;
  final ImageElement element;
  final ImageLayer layer;
  final double width, height;

  const LayerThumbnail(
      {required this.controller,
      required this.element,
      required this.layer,
      this.width = 36,
      this.height = 28,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var muted = theme.colors.onSurfaceVariant;
    var size = math.min(width, height) * 0.55;
    Widget inside;
    switch (layer.kind) {
      case LayerKind.paint:
        inside = Icon(Icons.brush, size: size, color: muted);
      case LayerKind.texture:
        inside = Icon(Icons.grain, size: size, color: muted);
      case LayerKind.adjustment:
        inside = Icon(Icons.tune, size: size, color: muted);
      case LayerKind.fill:
        var fill = layer.fill;
        inside = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: fill.fades ? null : fill.color,
            gradient:
                fill.fades ? LinearGradient(colors: fill.rampFor().$1) : null,
          ),
        );
      case LayerKind.base || LayerKind.picture:
        var look = layer.isBase ? element : layer.look;
        var image = look == null || !look.hasImage
            ? null
            : controller.images.resolve(look.assetId, look.removal);
        inside = image == null
            ? Icon(Icons.image_outlined, size: size, color: muted)
            : CustomPaint(
                size: Size.infinite,
                painter: _CoverPainter(controller.images.thumbnail(image)));
    }
    // No clip of its own: the picture rounds its own corners as it is
    // drawn. A clip a chip was a pass of its own every frame the strip
    // scrolled.
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: theme.colors.surfaceContainerHighest,
        border: Border.all(color: muted.withValues(alpha: 0.4)),
      ),
      child: inside,
    );
  }
}

/// _CoverPainter draws [image] covering its box, corners rounded -- inside
/// its own drawing, so a strip of them needs no clipping layer.
class _CoverPainter extends CustomPainter {
  final ui.Image image;
  _CoverPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    var all = Offset.zero & size;
    var iw = image.width.toDouble(), ih = image.height.toDouble();
    var scale = math.max(size.width / iw, size.height / ih);
    var sw = size.width / scale, sh = size.height / scale;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(all, const Radius.circular(3)));
    canvas.drawImageRect(
        image,
        Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh),
        all,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter old) => !identical(old.image, image);
}

/// staggerLayers brings [e]'s layers in one after another over its arrival
/// -- giving it one, in the same step, where it has none to stagger them
/// over.
void staggerLayers(CanvasController controller, ImageElement e) {
  var span = _arrivalSpanOf(e);
  if (span != null && e.animation.on) {
    controller.changeImage(withLayersStaggered(e, span));
    return;
  }
  controller.beginInteraction();
  controller.replaceElement(
      withLayersStaggered(e, controller.defaultAnimationFrames),
      transient: true);
  if (controller.document.elementById(e.id) case var fresh?) {
    controller.applyElementAnimation(fresh,
        e.animation.on ? e.animation.preset : ElementAnimationPreset.fadeUp);
  }
  controller.endInteraction();
}

/// _arrivalSpanOf is how many frames [e]'s arrival takes, by its reveal
/// keyframes, or null where it has none.
int? _arrivalSpanOf(ImageElement e) {
  int? from, to;
  for (var key in e.track?.keys ?? const <Keyframe>[]) {
    if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
    from = from == null ? key.frame : math.min(from, key.frame);
    to = to == null ? key.frame : math.max(to, key.frame);
  }
  if (from == null || to == null || to <= from) return null;
  return to - from;
}

/// ImageLayersList is every layer of the picture. Shut, it is a strip that
/// scrolls sideways, what is in front first; opened, it is a list down the
/// panel, what is in front at the top -- as the canvas's own layers list has
/// it -- with each layer's eye, and the picked one's arrows, copy and delete.
/// Either way, a layer is picked by pressing it, which opens the layers.
///
/// Nothing in a row opens anything over the page -- no tooltip, no menu: a
/// row is moved, not rebuilt, as it is dragged, and anything floating over
/// it comes apart. See the drawing's playlist, which this follows.
class ImageLayersList extends StatefulWidget {
  final CanvasController controller;
  final ImageElement element;

  const ImageLayersList(
      {required this.controller, required this.element, super.key});

  @override
  State<ImageLayersList> createState() => _ImageLayersListState();
}

class _ImageLayersListState extends State<ImageLayersList> {
  static const _remember = "imageLayersList";
  late bool _list = rememberedSection(_remember) ?? false;
  bool _adding = false;

  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (rememberedSection(_remember) == null) {
      restoreSection(_remember, (open) {
        if (mounted) setState(() => _list = open);
      });
    }
  }

  /// _picks are the layers picked, the first one's settings in the panel.
  Set<String> get _picks => controller.imageEditing == widget.element.id
      ? controller.imageLayers.toSet()
      : const {};

  /// _pick picks [id] -- with Shift or Command held, as well as the layers
  /// picked already, to line them up or move them together.
  void _pick(String id) {
    var e = widget.element;
    var keys = HardwareKeyboard.instance;
    var add =
        keys.isShiftPressed || keys.isMetaPressed || keys.isControlPressed;
    if (controller.imageEditing == e.id) {
      controller.pickImageLayer(id, add: add);
    } else {
      controller.editImage(e.id, layer: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var e = widget.element;
    var stack = e.stack;
    var n = stack.length;
    // Nothing is picked until the layers are open: the strip is always there
    // to start from, but a layer lit while nothing is being edited would say
    // otherwise.
    var picked = controller.imageEditing == e.id ? controller.imageLayer : "";
    var muted = theme.colors.onSurfaceVariant;

    // Backspace or Delete takes out the layer picked -- here, where the
    // click that picked it put the keys.
    return Focus(
      debugLabel: "imageLayers",
      onKeyEvent: (node, event) {
        // The arrows move the layers picked, as they do with the canvas in
        // focus -- a layer picked here is a layer picked.
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            picked.isNotEmpty) {
          var step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
          var by = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
            LogicalKeyboardKey.arrowRight => Offset(step, 0),
            LogicalKeyboardKey.arrowUp => Offset(0, -step),
            LogicalKeyboardKey.arrowDown => Offset(0, step),
            _ => null,
          };
          if (by != null) {
            controller.nudgeSelected(by.dx, by.dy);
            return KeyEventResult.handled;
          }
        }
        if (event is! KeyDownEvent || picked == baseLayerId || picked.isEmpty) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey != LogicalKeyboardKey.backspace &&
            event.logicalKey != LogicalKeyboardKey.delete) {
          return KeyEventResult.ignored;
        }
        controller.removeImageLayer(picked);
        return KeyEventResult.handled;
      },
      // A context under the Focus, so a press on a layer can take the keys.
      // Painted on its own, as each section is.
      child: Builder(
          builder: (context) => RepaintBoundary(
                  child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            key: const ValueKey("imageLayersOpen"),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() => _list = !_list);
                              keepSection(_remember, _list);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                              child: Row(children: [
                                AnimatedRotation(
                                  turns: _list ? 0.25 : 0,
                                  duration: const Duration(milliseconds: 120),
                                  child: Icon(Icons.chevron_right,
                                      size: 18, color: muted),
                                ),
                                const SizedBox(width: 4),
                                // Giving way before the buttons beside it,
                                // in the narrowest sidebar.
                                Flexible(
                                  child: Text("Layers",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colors.onSurface)),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                      "$n layer${n == 1 ? "" : "s"} · "
                                      "${_list ? "front at the top" : "front first"}",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10.5, color: muted)),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      // Solo: only the picked layer can be worked on, the
                      // rest held as if locked, whichever is picked.
                      CanvasIconButton(
                        key: const ValueKey("imageLayersSolo"),
                        tight: true,
                        icon: Icons.center_focus_strong_outlined,
                        tooltip: controller.imageSolo
                            ? "Solo on: only the picked layer can be edited"
                            : "Solo: lock every layer but the picked one",
                        active: controller.imageSolo,
                        onPressed: () =>
                            controller.imageSolo = !controller.imageSolo,
                      ),
                      // The picked layer taken out, from the strip as well
                      // as the list: a tablet has no Delete key.
                      CanvasIconButton(
                        key: const ValueKey("imageLayersDelete"),
                        tight: true,
                        icon: Icons.delete_outline,
                        tooltip: "Delete the picked layer",
                        onPressed: picked.isEmpty ||
                                picked == baseLayerId ||
                                (e.layerById(picked)?.locked ?? true)
                            ? null
                            : () => controller.removeImageLayer(picked),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: LayersAddButton(
                          open: _adding,
                          onPressed: () => setState(() => _adding = !_adding),
                        ),
                      ),
                    ]),
                    if (_adding)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: CanvasTiles<LayerAdd>(
                          key: const ValueKey("imageAddTiles"),
                          tiles: [
                            for (var a in LayerAdd.values)
                              CanvasTile(a, a.label, icon: a.icon),
                          ],
                          columns: 3,
                          previewHeight: 26,
                          selected: (_) => false,
                          keyOf: (a) => a.key,
                          onPick: (a) async {
                            setState(() => _adding = false);
                            await addImageLayerOf(context, controller, e, a);
                          },
                        ),
                      ),
                    if (_list)
                      _column(context, theme, e, picked)
                    else
                      _strip(context, theme, e, picked),
                  ],
                ),
              ))),
    );
  }

  /// _thumbOf is the picture [layer]'s thumbnail is of, if it has one.
  Object? _thumbOf(ImageElement e, ImageLayer layer) {
    var look = layer.isBase ? e : layer.look;
    if (look == null || !look.hasImage) return null;
    return controller.images.resolve(look.assetId, look.removal);
  }

  /// _strip is the layers in a line, front first.
  Widget _strip(BuildContext context, ThemeNotifier theme, ImageElement e,
      String picked) {
    var stack = e.stack;
    var n = stack.length;
    var accent = theme.colors.primary;
    // Pressed and held, a layer lifts and is carried along the strip to its
    // new place in the stack -- front first, as the strip reads. A press
    // that lets go picks it, as before.
    return SizedBox(
      height: 84,
      child: ReorderableListView(
        key: const ValueKey("imageLayersStrip"),
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        onReorderItem: (from, to) {
          controller.changeImage(withLayerMoved(e, n - 1 - from, n - 1 - to));
        },
        children: [
          for (var row = 0; row < n; row++)
            // Each chip kept until what it shows changes: an edit to one
            // layer rebuilt all of them. See CanvasKept -- a press picks
            // through this state, so a kept chip picks as it is now.
            CanvasKept(
                key: ValueKey("imageLayerChip-${stack[n - 1 - row].id}"),
                deps: [
                  stack[n - 1 - row],
                  _picks.contains(stack[n - 1 - row].id),
                  row,
                  n,
                  _thumbOf(e, stack[n - 1 - row]),
                  theme.colors,
                ],
                builder: (context) {
                  var layer = stack[n - 1 - row];
                  var on = _picks.contains(layer.id);
                  return ReorderableDelayedDragStartListener(
                      index: row,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Opacity(
                          opacity: layer.visible ? 1 : 0.5,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              key: ValueKey("imageLayer-${layer.id}"),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                _pick(layer.id);
                                Focus.of(context).requestFocus();
                              },
                              child: Container(
                                width: 70,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: on
                                      ? accent.withValues(alpha: 0.14)
                                      : null,
                                  border: Border.all(
                                      color: on
                                          ? accent
                                          : theme.colors.outlineVariant,
                                      width: on ? 1.5 : 1),
                                ),
                                child: Column(children: [
                                  Stack(children: [
                                    LayerThumbnail(
                                        controller: controller,
                                        element: e,
                                        layer: layer,
                                        width: 60,
                                        height: 42),
                                    if (!layer.visible)
                                      Positioned(
                                        right: 2,
                                        top: 2,
                                        child: Icon(Icons.visibility_off,
                                            size: 12,
                                            color: theme.colors.onSurface),
                                      ),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(layerName(layer, n - 1 - row),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: on
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: theme.colors.onSurface)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ));
                }),
        ],
      ),
    );
  }

  /// _list_ is the layers down the panel, front at the top.
  Widget _column(BuildContext context, ThemeNotifier theme, ImageElement e,
      String picked) {
    var stack = e.stack;
    var n = stack.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: ReorderableListView(
        key: const ValueKey("imageLayersRows"),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (from, to) {
          controller.changeImage(withLayerMoved(e, n - 1 - from, n - 1 - to));
        },
        children: [
          for (var row = 0; row < n; row++)
            _row(context, theme, stack[n - 1 - row], n - 1 - row, row, picked),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ThemeNotifier theme, ImageLayer layer,
      int index, int row, String picked) {
    var e = widget.element;
    var n = e.stack.length;
    var muted = theme.colors.onSurfaceVariant;
    var on = _picks.contains(layer.id);
    void change(ImageElement next) => controller.changeImage(next);

    Widget tap(String key, IconData icon, VoidCallback? onTap,
            {String label = ""}) =>
        Semantics(
          button: true,
          label: label,
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(icon,
                  size: 15,
                  color: onTap == null ? muted.withValues(alpha: 0.3) : muted),
            ),
          ),
        );

    var details = [
      layerKindLabel(layer),
      if (layer.blend != LayerBlend.normal) layer.blend.label,
      if (layer.opacity < 1) "${(layer.opacity * 100).round()}%",
    ].join(" · ");
    var masked = switch (layer.kind) {
      LayerKind.base => !e.mask.empty,
      LayerKind.picture => !(layer.look?.mask.empty ?? true),
      _ => !layer.mask.empty,
    };
    return Container(
      key: ValueKey("imageLayerRow-${layer.id}"),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: on ? theme.colors.primary.withValues(alpha: 0.12) : null,
      ),
      child: InkWell(
        key: ValueKey("imageLayer-${layer.id}"),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          _pick(layer.id);
          Focus.of(context).requestFocus();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            ReorderableDragStartListener(
              index: row,
              child: Semantics(
                label: "Drag to move",
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.drag_indicator, size: 16, color: muted),
                  ),
                ),
              ),
            ),
            // A clipped layer sits in from the one it clips to, as it does
            // in any editor.
            if (layer.clip && index > 0)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(Icons.subdirectory_arrow_right,
                    size: 14, color: muted),
              ),
            Opacity(
              opacity: layer.visible ? 1 : 0.5,
              child: LayerThumbnail(
                  controller: controller,
                  element: e,
                  layer: layer,
                  width: 40,
                  height: 30),
            ),
            if (masked)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.content_cut, size: 12, color: muted),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(layerName(layer, index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                          color:
                              layer.visible ? theme.colors.onSurface : muted)),
                  Text(details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: muted)),
                ],
              ),
            ),
            if (layer.id == picked) ...[
              tap(
                  "imageLayerUp-${layer.id}",
                  Icons.arrow_upward,
                  index == n - 1
                      ? null
                      : () => change(withLayerMoved(e, index, index + 1)),
                  label: "Move up"),
              tap(
                  "imageLayerDown-${layer.id}",
                  Icons.arrow_downward,
                  index == 0
                      ? null
                      : () => change(withLayerMoved(e, index, index - 1)),
                  label: "Move down"),
              tap(
                  "imageLayerDuplicate",
                  Icons.copy_all_outlined,
                  layer.isBase
                      ? null
                      : () => controller.duplicateImageLayer(layer.id),
                  label: "Duplicate"),
              tap(
                  "imageLayerDelete",
                  Icons.delete_outline,
                  layer.isBase
                      ? null
                      : () => controller.removeImageLayer(layer.id),
                  label: "Delete"),
            ],
            // Locked, it is kept as it is while the others are worked on; a
            // soloed picture holds every other layer the same way, and they
            // say so with the lock shut but faint.
            tap(
                "imageLayerLock-${layer.id}",
                layer.locked
                    ? Icons.lock
                    : controller.layerLocked(layer)
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                () => change(e.withLayer(
                    layer.id, (l) => l.copyWith(locked: !l.locked))),
                label: layer.locked ? "Unlock" : "Lock"),
            tap(
                "imageLayerShow-${layer.id}",
                layer.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                () => change(e.withLayer(
                    layer.id, (l) => l.copyWith(visible: !l.visible))),
                label: layer.visible ? "Hide" : "Show"),
          ]),
        ),
      ),
    );
  }
}

/// LayersAddButton is a layers strip's "+ Add", which opens the kinds of
/// layer: a picture's, and a drawing's. Never shortened -- it is one word.
class LayersAddButton extends StatelessWidget {
  final bool open;
  final VoidCallback onPressed;
  final String tapKey;
  const LayersAddButton(
      {required this.open,
      required this.onPressed,
      this.tapKey = "imageLayersAdd",
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey(tapKey),
        borderRadius: BorderRadius.circular(7),
        onTap: onPressed,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: open ? accent.withValues(alpha: 0.14) : null,
            border:
                Border.all(color: open ? accent : theme.colors.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(open ? Icons.close : Icons.add,
                size: 14, color: theme.colors.onSurface),
            const SizedBox(width: 3),
            Text("Add",
                style:
                    TextStyle(fontSize: 11.5, color: theme.colors.onSurface)),
          ]),
        ),
      ),
    );
  }
}

/// toolIcon is each tool's icon, on its tile and on the canvas's hint.
IconData toolIcon(ImageTool tool) => switch (tool) {
      ImageTool.move => Icons.open_with,
      ImageTool.subject => Icons.person_search_outlined,
      ImageTool.crop => Icons.crop,
      ImageTool.edge => Icons.deblur,
      ImageTool.quick => Icons.auto_fix_normal_outlined,
      ImageTool.refine => Icons.blur_on,
      ImageTool.brush => Icons.brush_outlined,
      ImageTool.lasso => Icons.gesture,
      ImageTool.fade => Icons.gradient,
      ImageTool.paint => Icons.brush,
      ImageTool.erase => Icons.auto_fix_off_outlined,
      ImageTool.clone => Icons.copy_all,
      ImageTool.heal => Icons.healing,
      ImageTool.dodge => Icons.exposure,
      ImageTool.soften => Icons.blur_circular,
      ImageTool.sharpen => Icons.details,
      ImageTool.smudge => Icons.touch_app_outlined,
    };

/// toolShort is each tool's name on its tile, where there is room for a
/// word.
String toolShort(ImageTool tool) => switch (tool) {
      ImageTool.move => "Move",
      ImageTool.subject => "Subject",
      ImageTool.crop => "Crop",
      ImageTool.edge => "Edge",
      ImageTool.quick => "Quick",
      ImageTool.refine => "Refine",
      ImageTool.brush => "Brush",
      ImageTool.lasso => "Lasso",
      ImageTool.fade => "Fade",
      ImageTool.paint => "Paint",
      ImageTool.erase => "Erase",
      ImageTool.clone => "Clone",
      ImageTool.heal => "Heal",
      ImageTool.dodge => "Light",
      ImageTool.soften => "Blur",
      ImageTool.sharpen => "Sharpen",
      ImageTool.smudge => "Smudge",
    };

/// maskTools, retouchTools and paintTools are which tools each section
/// holds.
const maskTools = [
  ImageTool.crop,
  ImageTool.edge,
  ImageTool.subject,
  ImageTool.quick,
  ImageTool.refine,
  ImageTool.brush,
  ImageTool.lasso,
  ImageTool.fade,
];
const framedMaskTools = [
  ImageTool.edge,
  ImageTool.brush,
  ImageTool.lasso,
  ImageTool.fade,
];
const retouchTools = [
  ImageTool.clone,
  ImageTool.heal,
  ImageTool.dodge,
  ImageTool.soften,
  ImageTool.sharpen,
  ImageTool.smudge,
];
const paintTools = [ImageTool.paint, ImageTool.erase];

/// imageToolTiles is [tools] as tiles, with the settings of the one in hand
/// under them. Picking one opens [e]'s layers on [picked] if they are not
/// open; picking the one in hand puts it down.
Widget imageToolTiles(CanvasController controller, ImageElement e,
    ImageLayer picked, List<ImageTool> tools, List<Widget> settings,
    {String help = ""}) {
  var editing = controller.imageEditing == e.id;
  var active = editing && tools.contains(controller.imageTool)
      ? controller.imageTool
      : null;
  return CanvasToolTiles<ImageTool>(
    key: ValueKey("imageTools-${tools.first.name}"),
    tools: [for (var t in tools) (t, toolIcon(t), toolShort(t))],
    active: active,
    keyOf: (t) => "imageTool-${t.name}",
    tooltipOf: (t) => "${t.label} (${t.key})",
    onPick: (t) {
      if (!editing) controller.editImage(e.id, layer: picked.id);
      controller.imageTool = t ?? ImageTool.move;
    },
    settings: active == null ? const [] : settings,
    help: help,
  );
}

/// blendPreview is a picture of what [blend] does: a colour laid by it over
/// a run from dark to light.
Widget blendPreview(LayerBlend blend) =>
    CustomPaint(painter: _BlendPainter(blend));

class _BlendPainter extends CustomPainter {
  final LayerBlend blend;
  _BlendPainter(this.blend);

  @override
  void paint(Canvas canvas, Size size) {
    var all = Offset.zero & size;
    canvas.saveLayer(all, Paint());
    canvas.drawRect(
        all,
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0xFF1C2230),
            Color(0xFF5A6C86),
            Color(0xFFD8DEE8),
          ]).createShader(all));
    var over = Rect.fromLTWH(size.width * 0.18, size.height * 0.18,
        size.width * 0.64, size.height * 0.64);
    canvas.drawRRect(
        RRect.fromRectAndRadius(over, Radius.circular(size.height * 0.2)),
        Paint()
          ..blendMode = blend.flutter
          ..shader = const LinearGradient(
                  colors: [Color(0xFFE8B630), Color(0xFFD9573B)])
              .createShader(over));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlendPainter old) => old.blend != blend;
}

/// layerBlendTiles is the picked layer's blend, as pictures of each mode --
/// each tried on the canvas as the pointer passes over it.
Widget layerBlendTiles(
    CanvasController controller,
    ImageElement e,
    ImageLayer picked,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  return CanvasTiles<LayerBlend>(
    key: const ValueKey("imageLayerBlend"),
    foldAs: "image.tiles.blend",
    label: "Blend mode",
    help: "How this layer mixes with the layers under it. Click one to "
        "use it.",
    columns: 4,
    previewHeight: 26,
    tiles: [
      for (var b in LayerBlend.values)
        CanvasTile(b, b.label,
            drawnFrom: b,
            paint: (canvas, size) => _BlendPainter(b).paint(canvas, size)),
    ],
    selected: (b) => picked.blend == b,
    keyOf: (b) => "imageLayerBlend-${b.name}",
    onPreview: (b) => controller.tryElement(
        b == null ? null : e.withLayer(picked.id, (l) => l.copyWith(blend: b))),
    onPick: (b) {
      begin();
      write(e.withLayer(picked.id, (l) => l.copyWith(blend: b)));
      commit();
    },
  );
}

/// layerStrengthGroup is how much of the picked layer shows, and whether it
/// shows only over the layer under it.
Widget layerStrengthGroup(ImageElement e, ImageLayer picked,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var at = e.stack.indexWhere((l) => l.id == picked.id);
  return CanvasControlGroup(
    key: const ValueKey("imageLayerGroup"),
    label: "Strength",
    help: "How much of the layer shows, and whether it shows only where the "
        "layer under it does.",
    rule: false,
    children: [
      CanvasStepper(
        key: const ValueKey("imageLayerOpacity"),
        label: "Opacity",
        min: 0,
        max: 100,
        step: 5,
        dragStep: 1,
        suffix: "%",
        defaultValue: 100,
        value: picked.opacity * 100,
        onChanged: (v) {
          begin();
          write(e.withLayer(picked.id, (l) => l.copyWith(opacity: v / 100)));
        },
        onCommit: commit,
      ),
      // Nothing to clip to at the bottom of the stack.
      if (at > 0)
        CanvasToggle(
          key: const ValueKey("imageLayerClip"),
          label: "Only over the layer below",
          value: picked.clip,
          onChanged: (v) {
            begin();
            write(e.withLayer(picked.id, (l) => l.copyWith(clip: v)));
            commit();
          },
        ),
    ],
  );
}

/// QuickMove is one press that places a picture: mirrored, filling or
/// fitted to its frame, centred, or given back its own proportions.
enum QuickMove {
  flipX("Flip across", Icons.swap_horiz, "imageLayerFlipX"),
  flipY("Flip down", Icons.swap_vert, "imageLayerFlipY"),
  fill("Cover frame", Icons.fullscreen, "imageLayerFill"),
  fit("Inside frame", Icons.fit_screen_outlined, "imageLayerFit"),
  centre("Centre", Icons.filter_center_focus, "imageLayerCentre"),
  shape("Own shape", Icons.aspect_ratio, "imageLayerProportions");

  final String label;
  final IconData icon;
  final String key;
  const QuickMove(this.label, this.icon, this.key);
}

/// quickMover is what each quick move does to [picked]: a flip, sized to
/// cover the frame or sit inside it, put in the middle, or given back the
/// picture's own proportions -- each one step.
void Function(QuickMove) quickMover(
    CanvasController controller,
    ImageElement e,
    ImageLayer picked,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var inner = e.box.inner(e.bounds);
  void now(ImageLayer next) {
    begin();
    write(e.withLayer(picked.id, (_) => next));
    commit();
  }

  var place = picked.place;
  // The picture's own proportions in the frame's units, where it has loaded:
  // what "fit" and "fill" keep, and what a squashed layer goes back to.
  var image = controller.images.original((picked.look ?? e).assetId);
  double? aspect;
  if (image != null && inner.width > 0 && inner.height > 0) {
    aspect = image.width / image.height;
  }

  /// fitted is the layer's place at the picture's proportions, inside the
  /// frame or covering it, about the frame's middle.
  Rect fitted({required bool cover}) {
    var a = aspect ??
        layerRect(inner, place).width /
            math.max(1e-9, layerRect(inner, place).height);
    var w = inner.width, h = w / a;
    if (cover ? h < inner.height : h > inner.height) {
      h = inner.height;
      w = h * a;
    }
    return layerPlace(
        inner, Rect.fromCenter(center: inner.center, width: w, height: h));
  }

  return (m) {
    switch (m) {
      case QuickMove.flipX:
        now(picked.copyWith(flipX: !picked.flipX));
      case QuickMove.flipY:
        now(picked.copyWith(flipY: !picked.flipY));
      case QuickMove.fill:
        now(picked.placed(fitted(cover: true), turn: 0));
      case QuickMove.fit:
        now(picked.placed(fitted(cover: false), turn: 0));
      case QuickMove.centre:
        now(picked.placed(
            Rect.fromCenter(
                center: const Offset(layerUnits / 2, layerUnits / 2),
                width: place.width,
                height: place.height),
            turn: picked.turn));
      case QuickMove.shape:
        if (image == null) return;
        now(picked.isBase
            ? picked.placed(fitted(cover: false))
            : picked.copyWith(
                look: withPictureProportions(picked.look!, inner,
                    Size(image.width.toDouble(), image.height.toDouble()))));
    }
  };
}

/// flipControls are the Flip tool's settings: a switch each way, on while
/// the picture is mirrored that way.
List<Widget> flipControls(
    CanvasController controller,
    ImageElement e,
    ImageLayer picked,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var move = quickMover(controller, e, picked, write, begin, commit);
  return [
    CanvasToggle(
      key: const ValueKey("imageLayerFlipX"),
      label: "Flip across",
      value: picked.flipX,
      onChanged: (_) => move(QuickMove.flipX),
    ),
    CanvasToggle(
      key: const ValueKey("imageLayerFlipY"),
      label: "Flip down",
      value: picked.flipY,
      onChanged: (_) => move(QuickMove.flipY),
    ),
  ];
}

/// fitButtons are the Fit tool's one-press moves: sized to cover the frame
/// or to sit inside it, put in the middle, or given back the picture's own
/// proportions -- for a picture with a place of its own in the frame.
List<Widget> fitButtons(
    CanvasController controller,
    ImageElement e,
    ImageLayer picked,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var move = quickMover(controller, e, picked, write, begin, commit);
  var image = controller.images.original((picked.look ?? e).assetId);
  return [
    for (var m in [
      QuickMove.fill,
      QuickMove.fit,
      QuickMove.centre,
      if (image != null) QuickMove.shape,
    ])
      CanvasTextButton(
        key: ValueKey(m.key),
        icon: m.icon,
        label: m.label,
        onPressed: () => move(m),
      ),
  ];
}

/// fillLayerSettings is a colour layer's colour, or its fade.
List<Widget> fillLayerSettings(ImageElement e, ImageLayer picked,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(PaintSpec fill) {
    begin();
    write(e.withLayer(picked.id, (l) => l.copyWith(fill: fill)));
    commit();
  }

  return [
    CanvasControlGroup(label: "Colour", rule: false, children: [
      CanvasColorButton(
        key: const ValueKey("imageLayerColour"),
        label: "Colour",
        color: picked.fill.color,
        gradient: picked.fill.gradient,
        onChanged: (c) => now(picked.fill.copyWith(color: c)),
        onGradientChanged: (g) => now(g == null
            ? picked.fill.copyWith(plain: true)
            : picked.fill.copyWith(gradient: g)),
      ),
    ]),
  ];
}

/// layerPositionGroup is where the picked picture layer is, how big and how
/// turned -- in the same canvas units as an element's own, so a layer is
/// placed the way anything else is.
///
/// Measured in the picture's frame as it is before the element is turned,
/// which is the canvas's own units for a picture that is not.
Widget layerPositionGroup(
    CanvasController controller,
    ImageElement e,
    ImageLayer layer,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var inner = e.box.inner(e.bounds);
  var rect = layerRect(inner, layer.place);
  // The base picture's own settings are the element's.
  var look = layer.look ?? e;
  void live(ImageLayer next) {
    begin();
    write(e.withLayer(layer.id, (_) => next));
  }

  void place(Rect next) =>
      live(layer.placed(layerPlace(inner, next), turn: layer.turn));

  void resize({double? width, double? height}) {
    var w = width ?? rect.width, h = height ?? rect.height;
    if (look.base.lockAspect && rect.width > 0 && rect.height > 0) {
      var by = width != null ? w / rect.width : h / rect.height;
      w = rect.width * by;
      h = rect.height * by;
    }
    place(Rect.fromLTWH(rect.left, rect.top, math.max(1, w), math.max(1, h)));
  }

  return CanvasControlGroup(
    key: const ValueKey("layerPosition"),
    label: "Place and size",
    help: "Where the layer sits in the picture, in the canvas's own units. "
        "Or drag it on the canvas: a corner resizes it, the round handle "
        "turns it.",
    rule: false,
    children: [
      CanvasStepper(
        key: const ValueKey("layerX"),
        // Two to a line, as an element's are -- see positionGroup.
        width: 104,
        label: "X",
        value: rect.left,
        onChanged: (v) => place(rect.translate(v - rect.left, 0)),
        onCommit: commit,
      ),
      CanvasStepper(
        key: const ValueKey("layerY"),
        // Two to a line, as an element's are -- see positionGroup.
        width: 104,
        label: "Y",
        value: rect.top,
        onChanged: (v) => place(rect.translate(0, v - rect.top)),
        onCommit: commit,
      ),
      const CanvasLineBreak(),
      CanvasStepper(
        key: const ValueKey("layerW"),
        // Two to a line, as an element's are -- see positionGroup.
        width: 104,
        label: "Width",
        value: rect.width,
        min: 1,
        onChanged: (v) => resize(width: v),
        onCommit: commit,
      ),
      CanvasStepper(
        key: const ValueKey("layerH"),
        // Two to a line, as an element's are -- see positionGroup.
        width: 104,
        label: "Height",
        value: rect.height,
        min: 1,
        onChanged: (v) => resize(height: v),
        onCommit: commit,
      ),
      // The angle on a line of its own, the whole width: a turn is read
      // more finely than a position. Not for the base picture, which is
      // turned with the element.
      if (!layer.isBase) const CanvasBlockBreak(),
      if (!layer.isBase)
        CanvasStepper(
          key: const ValueKey("layerAngle"),
          // Two to a line, as an element's are -- see positionGroup.
          width: 104,
          label: "Angle",
          value: layer.turn,
          min: -360,
          max: 360,
          suffix: "°",
          step: 15,
          dragStep: 1,
          defaultValue: 0,
          onChanged: (v) => live(layer.placed(layer.place, turn: v)),
          onCommit: commit,
        ),
      CanvasToggle(
        key: const ValueKey("layerLockAspect"),
        label: "Keep its proportions",
        value: look.base.lockAspect,
        onChanged: (v) {
          if (layer.isBase) {
            begin();
            write(e.withProportionsKept(v));
          } else {
            live(layer.copyWith(look: look.withProportionsKept(v)));
          }
          commit();
        },
      ),
    ],
  );
}

/// maskToolSettings is the row under the tools while a mask tool is in
/// hand: whether it takes away or puts back, the tool's own settings, and
/// how the mask is shown.
List<Widget> maskToolSettings(
    CanvasController controller, ImageElement e, ImageLayer picked) {
  var tool = controller.imageTool;
  // A frame-masked layer -- adjustment, texture, colour, paint -- is masked
  // by hand: there is no picture in it to find a subject in.
  if (picked.framed &&
      (tool == ImageTool.subject ||
          tool == ImageTool.quick ||
          tool == ImageTool.refine)) {
    return [
      CanvasHint("${tool.label} looks for a subject in a picture. On this "
          "layer, mask with the brush, the lasso or a gradient -- where it "
          "shows, it does what it does."),
    ];
  }
  Widget percent(String key, String label, double value, double min, double max,
          ValueChanged<double> set,
          {int decimals = 0}) =>
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        decimals: decimals,
        min: min,
        max: max,
        step: decimals == 0 ? 5 : 0.5,
        dragStep: decimals == 0 ? 1 : 0.1,
        suffix: "%",
        value: value * 100,
        onChanged: (v) => set(v / 100),
      );
  return [
    if (tool == ImageTool.subject) ...[
      const CanvasLineBreak(),
      _SubjectButton(controller: controller),
      const CanvasLineBreak(),
      CanvasHint(controller.maskBusy ??
          controller.maskNote ??
          "Click a person or thing to keep only it. Shift-click adds another, "
              "Option-click takes one away."),
    ] else if (tool == ImageTool.refine) ...[
      percent("maskRefineSize", "Size", controller.maskBrushSize, 0.1, 50,
          (v) => controller.maskBrushSize = v,
          decimals: 1),
      CanvasHint(controller.maskBusy ??
          controller.maskNote ??
          "Brush along a soft edge -- hair, fur, a blurred shoulder -- and "
              "it works out from the colours how much of each pixel is the "
              "subject. Keep the brush over the edge, not inside."),
    ] else if (tool == ImageTool.quick) ...[
      percent("maskQuickSize", "Size", controller.maskBrushSize, 0.1, 50,
          (v) => controller.maskBrushSize = v,
          decimals: 1),
      CanvasHint(controller.maskBusy ??
          controller.maskNote ??
          "Brush over what to keep and it grows to the edges near it. "
              "Option-brush over what to take away."),
    ] else ...[
      CanvasSegmented<bool>(
        key: const ValueKey("maskHideShow"),
        options: const [(true, "Hide"), (false, "Show")],
        value: controller.maskHide,
        keyOf: (hide) => hide ? "maskHide" : "maskShow",
        onChanged: (hide) => controller.maskHide = hide,
      ),
      const CanvasHint("Hide takes the picture away where you mark it, Show "
          "puts it back. X swaps them; Option swaps them for one stroke."),
    ],
    if (tool == ImageTool.brush) ...[
      percent("maskBrushSize", "Size", controller.maskBrushSize, 0.1, 50,
          (v) => controller.maskBrushSize = v,
          decimals: 1),
      percent("maskHardness", "Hardness", controller.maskHardness, 0, 100,
          (v) => controller.maskHardness = v),
      percent("maskStrength", "Strength", controller.maskStrength, 1, 100,
          (v) => controller.maskStrength = v),
    ],
    if (tool == ImageTool.fade) ...[
      CanvasSegmented<bool>(
        key: const ValueKey("maskRadial"),
        label: "Fades",
        options: const [(false, "Across a line"), (true, "From a middle")],
        value: controller.maskRadial,
        onChanged: (radial) => controller.maskRadial = radial,
      ),
      percent("maskFadeStrength", "Strength", controller.maskStrength, 1, 100,
          (v) => controller.maskStrength = v),
      // Which end is which is the one thing a fade cannot show before it
      // is drawn, and the wrong guess is the picture gone where it was meant
      // to stay.
      CanvasHint(switch ((controller.maskRadial, controller.maskHide)) {
        (false, true) => "Press where the picture is to be gone and drag to "
            "where it is to be whole: hidden where you press, shown where "
            "you let go.",
        (false, false) => "Press where the picture is to come back fully "
            "and drag to where it stays as it was: shown where you press, "
            "unchanged where you let go.",
        (true, true) => "Press in the middle, which stays whole, and drag "
            "out to where it is to be gone: shown in the middle, hidden past "
            "where you let go.",
        (true, false) => "Press in the middle and drag out: the middle "
            "stays as it was, and everything past where you let go comes "
            "back.",
      }),
    ],
  ];
}

/// _SubjectButton finds every subject in the picture at once -- or says why
/// it cannot, on a machine that has no way to.
class _SubjectButton extends StatelessWidget {
  final CanvasController controller;
  const _SubjectButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return FutureBuilder<bool>(
      future: SubjectFinder.available(),
      initialData: SubjectFinder.known,
      builder: (context, available) {
        var can = available.data ?? false;
        var busy = controller.maskBusy != null;
        var enabled = can && !busy;
        return Padding(
          padding: const EdgeInsets.only(bottom: canvasRowGap),
          child: Tooltip(
            message: can ? "" : "Finding a subject needs macOS 14 or later",
            child: Material(
              color: enabled
                  ? theme.colors.primary
                  : theme.colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                key: const ValueKey("maskSubjectAll"),
                borderRadius: BorderRadius.circular(8),
                onTap: enabled ? () => controller.findSubject() : null,
                child: SizedBox(
                  height: 32,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 16,
                            color: enabled
                                ? theme.colors.onPrimary
                                : theme.colors.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                            busy
                                ? "Finding the subject…"
                                : "Select the subject",
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: enabled
                                    ? theme.colors.onPrimary
                                    : theme.colors.onSurfaceVariant)),
                      ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// maskGroupsFor is the mask groups for any [mask], written by [put] --
/// a picture's, or a frame-masked layer's. Its edge is the Edge tool's:
/// see maskEdgeControls.
List<Widget> maskGroupsFor(ImageMask mask, void Function(ImageMask) put,
    VoidCallback begin, VoidCallback commit,
    {bool framed = false, CanvasController? controller}) {
  void now(ImageMask next) {
    begin();
    put(next);
    commit();
  }

  return [
    CanvasControlGroup(
      key: const ValueKey("maskGroup"),
      label: "Mask",
      help: mask.empty
          ? framed
              ? "Showing everywhere. Paint, lasso or fade it away with the "
                  "mask tools to have it only where it is wanted."
              : "Nothing hidden yet. Use Select subject, the mask brush, the "
                  "lasso or a gradient from the tools."
          : "What the tools have marked. Switch it off to see the whole "
              "layer again -- nothing is lost. The arrow takes back the last "
              "mark; the bin clears the mask.",
      rule: false,
      children: [
        CanvasToggle(
          key: const ValueKey("maskOn"),
          label: "Use the mask",
          value: mask.on,
          onChanged: (v) => now(mask.copyWith(on: v)),
        ),
        CanvasToggle(
          key: const ValueKey("maskInvert"),
          label: "Swap what shows",
          value: mask.invert,
          onChanged: (v) => now(mask.copyWith(invert: v)),
        ),
        const CanvasLineBreak(),
        if (controller != null)
          CanvasDropdown<MaskView>(
            key: const ValueKey("maskView"),
            label: "Show the mask as",
            value: controller.maskView,
            width: 132,
            options: [for (var v in MaskView.values) (v, v.short)],
            onChanged: (v) => controller.maskView = v,
          ),
        CanvasIconButton(
          key: const ValueKey("maskUndoMark"),
          icon: Icons.undo,
          tooltip: "Undo the last mark",
          onPressed: mask.marks.isEmpty
              ? null
              : () => now(mask.copyWith(
                  marks: mask.marks.sublist(0, mask.marks.length - 1))),
        ),
        CanvasIconButton(
          key: const ValueKey("maskClear"),
          icon: Icons.delete_sweep_outlined,
          tooltip: "Clear the mask",
          onPressed: mask.empty ? null : () => now(const ImageMask()),
        ),
      ],
    ),
  ];
}

/// maskEdgeControls is the Edge tool's settings for any [mask], written by
/// [put]: how its edge is softened, moved, smoothed and hardened, and --
/// on a picture's own mask -- the old background's tint taken out of it.
List<Widget> maskEdgeControls(ImageMask mask, void Function(ImageMask) put,
    VoidCallback begin, VoidCallback commit,
    {bool framed = false}) {
  void live(ImageMask next) {
    begin();
    put(next);
  }

  Widget refine(String key, String label, double value, double min, double max,
          MaskRefine Function(double) apply,
          {int decimals = 1, double factor = 1}) =>
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        decimals: decimals,
        min: min,
        max: max,
        step: decimals == 0 ? 5 : 0.5,
        dragStep: decimals == 0 ? 1 : 0.1,
        suffix: factor == 100 ? "%" : " px",
        defaultValue: 0,
        value: value * factor,
        onChanged: (v) => live(mask.copyWith(refine: apply(v / factor))),
        onCommit: commit,
      );

  return [
    refine("maskFeather", "Feather", mask.refine.feather, 0, 100,
        (v) => mask.refine.copyWith(feather: v)),
    refine("maskShift", "Shift", mask.refine.shift, -50, 50,
        (v) => mask.refine.copyWith(shift: v)),
    // Cleaning colours is a picture's: a layer with none has none.
    if (!framed)
      refine("maskDecontaminate", "Clean colour", mask.refine.decontaminate, 0,
          100, (v) => mask.refine.copyWith(decontaminate: v),
          decimals: 0, factor: 100),
    refine("maskSmooth", "Smooth", mask.refine.smooth, 0, 50,
        (v) => mask.refine.copyWith(smooth: v)),
    refine("maskContrast", "Contrast", mask.refine.contrast, 0, 100,
        (v) => mask.refine.copyWith(contrast: v),
        decimals: 0, factor: 100),
    const CanvasHint("In the picture's own pixels: Feather softens the edge, "
        "Shift moves it out or in, Smooth rounds off jags and Contrast "
        "hardens it. Clean colour takes the old background's tint out of the "
        "edge -- the green on hair cut from a pitch."),
  ];
}

/// brushToolSettings is the row under the tools while a paint or
/// retouching brush is in hand.
List<Widget> brushToolSettings(CanvasController controller, ImageLayer picked) {
  var tool = controller.imageTool;
  var picture =
      picked.kind == LayerKind.base || picked.kind == LayerKind.picture;
  var scope = <Widget>[
    if (tool.retouches && picture) ...[
      CanvasSegmented<bool>(
        key: const ValueKey("retouchScope"),
        label: "Works on",
        options: const [(false, "This picture"), (true, "Every layer")],
        value: controller.retouchWholeFrame,
        keyOf: (whole) => whole ? "retouchWhole" : "retouchPicture",
        onChanged: (whole) => controller.retouchWholeFrame = whole,
      ),
      if (controller.retouchWholeFrame)
        const CanvasHint("Works on everything in the frame as it looks, "
            "anywhere in the frame. The strokes go on a Retouch layer of "
            "their own, at the top of the picture."),
    ],
    if (tool.retouches && !picture)
      CanvasHint(picked.kind == LayerKind.paint
          ? "Works on everything under this layer, anywhere in the frame."
          : "Works on everything under this layer, anywhere in the frame. "
              "The strokes go on a Retouch layer of their own, at the top "
              "of the picture."),
  ];
  Widget percent(String key, String label, double value, double min, double max,
          ValueChanged<double> set,
          {int decimals = 0}) =>
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        decimals: decimals,
        min: min,
        max: max,
        step: decimals == 0 ? 5 : 0.5,
        dragStep: decimals == 0 ? 1 : 0.1,
        suffix: "%",
        value: value * 100,
        onChanged: (v) => set(v / 100),
      );
  var hint = switch (tool) {
    ImageTool.paint => "Paints on a paint layer -- one is made over the layer "
        "picked if it is not one. Option rubs out. The pen's pressure "
        "thins the line.",
    ImageTool.erase => "Takes paint off the paint layer picked.",
    ImageTool.clone => controller.cloneFrom == null
        ? "To pick the point to copy from, hold Option and click on it -- a "
            "cross marks it. Then paint where the copy is to go."
        : "Copying from the cross. To move it, Option-click somewhere else; "
            "to deselect it, press Escape or the clear button.",
    ImageTool.heal => "Paint over a spot, a speck or a stray hair, and it is "
        "filled with what is round it.",
    ImageTool.dodge => "Lightens what it goes over; Option, or Burn, darkens.",
    ImageTool.sharpen => "Crisps the edges it goes over -- eyes, a badge, "
        "lettering. Strength is how much.",
    ImageTool.smudge => "Drags the colour it starts on along the way it goes, "
        "like a finger through wet paint.",
    _ => "Softens what it goes over.",
  };
  return [
    ...scope,
    if (tool == ImageTool.paint)
      CanvasColorButton(
        key: const ValueKey("paintColour"),
        label: "Colour",
        color: controller.paintColour,
        onChanged: (c) => controller.paintColour = c,
      ),
    percent("paintSize", "Size", controller.paintSize, 0.1, 50,
        (v) => controller.paintSize = v,
        decimals: 1),
    percent("paintHardness", "Hardness", controller.paintHardness, 0, 100,
        (v) => controller.paintHardness = v),
    percent("paintStrength", "Strength", controller.paintStrength, 1, 100,
        (v) => controller.paintStrength = v),
    if (tool == ImageTool.clone && controller.cloneFrom != null)
      CanvasTextButton(
        key: const ValueKey("cloneClear"),
        icon: Icons.close,
        label: "Clear the point · Esc",
        onPressed: () => controller.cloneFrom = null,
      ),
    if (tool == ImageTool.dodge)
      CanvasSegmented<bool>(
        key: const ValueKey("paintBurn"),
        options: const [(false, "Lighten"), (true, "Darken")],
        value: controller.burning,
        onChanged: (v) => controller.burning = v,
      ),
    CanvasHint(controller.maskNote ?? hint),
  ];
}

/// strokesGroup is a list of strokes -- a paint layer's, or the retouching
/// done to a picture -- with the last taken back, or all of them cleared.
Widget strokesGroup(String label, List<StrokeMark> strokes,
    void Function(List<StrokeMark>) set) {
  return CanvasControlGroup(
    key: ValueKey("strokes-$label"),
    label: label,
    rule: false,
    children: [
      CanvasTextButton(
        key: ValueKey("strokesUndo-$label"),
        icon: Icons.undo,
        label: "Take back a stroke",
        onPressed: strokes.isEmpty
            ? null
            : () => set(strokes.sublist(0, strokes.length - 1)),
      ),
      CanvasTextButton(
        key: ValueKey("strokesClear-$label"),
        label: "Clear all",
        onPressed: strokes.isEmpty ? null : () => set(const []),
      ),
      CanvasHint(strokes.isEmpty
          ? "Nothing yet."
          : "${strokes.length} stroke${strokes.length == 1 ? "" : "s"}."),
    ],
  );
}

/// warpControls are the Warp tool's settings: how many cells the grid has
/// across and down -- the shape already made kept -- and the button that
/// flattens it again. The grid is on the canvas while the tool is open.
/// See ImageWarp.
List<Widget> warpControls(
    CanvasController controller, ImageElement e, ImageLayer picked) {
  var warp = controller.warpOf(e, picked.id);
  return [
    for (var (key, label, value, across) in [
      ("imageWarpCols", "Columns", warp.cols, true),
      ("imageWarpRows", "Rows", warp.rows, false),
    ])
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        value: value.toDouble(),
        min: 1,
        max: mostWarpCells.toDouble(),
        step: 1,
        dragStep: 1,
        defaultValue: 4,
        width: 96,
        onChanged: (v) {
          controller.warpPicks = const {};
          controller.changeWarp((w) => across
              ? w.regridded(v.round(), w.rows)
              : w.regridded(w.cols, v.round()));
        },
      ),
    CanvasTextButton(
      key: const ValueKey("imageWarpReset"),
      icon: Icons.grid_on,
      label: "Flatten",
      onPressed: warp.active
          ? () {
              controller.warpPicks = const {};
              controller.changeWarp((w) => w.reset);
            }
          : null,
    ),
    const CanvasHint("Drag a point on the canvas to bend the picture. Click "
        "points or drag a box round them to pick them, Shift to add more. "
        "With two or more picked, the box's corners size them and its knob "
        "turns them; the arrow keys nudge them. More cells bend it more "
        "finely, keeping the shape already made."),
  ];
}
