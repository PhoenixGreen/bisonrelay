import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_layer_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// text_layers.dart is a text element's layers: its own words first, then
// each piece added to the box -- more words, or a picture -- in the order
// they stack, the way a picture's and a drawing's layers are shown (see
// ImageLayersList and VectorLayersList, which this follows). Shut, a strip
// that scrolls sideways; opened, a list down the panel, with each piece's
// eye and lock and the picked one's arrows, copy and delete. The layer
// picked is the one whose settings the panel shows.
//
// In reading order rather than front first: pieces in one slot stack in the
// order they are in the list, so first in the list is first down the box.

/// TextLayersList is [element]'s layers. [onChanged] writes a change to the
/// element as one step.
class TextLayersList extends StatefulWidget {
  final CanvasController controller;
  final TextElement element;
  final void Function(TextElement) onChanged;

  const TextLayersList(
      {required this.controller,
      required this.element,
      required this.onChanged,
      super.key});

  @override
  State<TextLayersList> createState() => _TextLayersListState();
}

/// _TextAdd is what the strip's Add puts in the box.
enum _TextAdd {
  text("Text", Icons.text_fields),
  picture("Picture", Icons.add_photo_alternate_outlined);

  final String label;
  final IconData icon;
  const _TextAdd(this.label, this.icon);
}

class _TextLayersListState extends State<TextLayersList> {
  static const _remember = "textLayersList";
  late bool _list = rememberedSection(_remember) ?? false;
  bool _adding = false;

  CanvasController get controller => widget.controller;
  TextElement get e => widget.element;

  @override
  void initState() {
    super.initState();
    if (rememberedSection(_remember) == null) {
      restoreSection(_remember, (open) {
        if (mounted) setState(() => _list = open);
      });
    }
  }

  /// _picked is the piece picked, or null for the element's own words.
  TextItem? get _picked => controller.textLayer(e);

  void _pick(TextItem? item) => controller.pickTextLayer(e.id, item?.id);

  int _indexOf(TextItem item) => e.items.indexWhere((i) => i.id == item.id);

  void _change(TextItem item, TextItem Function(TextItem) edit) =>
      widget.onChanged(e.copyWith(items: [
        for (var i in e.items) i.id == item.id ? edit(i) : i,
      ]));

  void _remove(TextItem item) {
    _pick(null);
    widget.onChanged(e.copyWith(items: [
      for (var i in e.items)
        if (i.id != item.id) i,
    ]));
  }

  void _duplicate(TextItem item) {
    var at = _indexOf(item);
    // A copy of what it says and how, under a new id: the editor on the
    // canvas holds a piece by its id, so two with one id would be one.
    var copy = TextItem.fromJson({...item.toJson(), "id": newElementId()});
    var items = [...e.items]..insert(at + 1, copy);
    widget.onChanged(e.copyWith(items: items));
    _pick(copy);
  }

  void _move(int from, int to) {
    if (from == to || to < 0 || to >= e.items.length) return;
    var items = [...e.items];
    var item = items.removeAt(from);
    items.insert(to, item);
    widget.onChanged(e.copyWith(items: items));
  }

  void _add(_TextAdd what) {
    var slot = freeTextSlot(e);
    var item = what == _TextAdd.text
        ? TextItem.fresh(slot, e.textSpec)
        : TextItem.freshIcon(slot);
    widget.onChanged(e.copyWith(items: [...e.items, item]));
    _pick(item);
  }

  /// _bodyName is what the element's own words are called: what they say,
  /// cut short.
  String get _bodyName {
    var words = e.displayText.trim().replaceAll(RegExp(r"\s+"), " ");
    if (words.isEmpty) return "Text";
    return words.length <= 24 ? words : "${words.substring(0, 23)}…";
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var n = e.items.length + 1;
    var muted = theme.colors.onSurfaceVariant;
    var picked = _picked;

    // Backspace or Delete takes out the piece picked -- here, where the
    // click that picked it put the keys. The element's own words stay.
    return Focus(
      debugLabel: "textLayers",
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || picked == null || picked.locked) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey != LogicalKeyboardKey.backspace &&
            event.logicalKey != LogicalKeyboardKey.delete) {
          return KeyEventResult.ignored;
        }
        _remove(picked);
        return KeyEventResult.handled;
      },
      child: Builder(
          builder: (context) => RepaintBoundary(
                  child: Container(
                key: const ValueKey("textLayers"),
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
                            key: const ValueKey("textLayersOpen"),
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
                                  child: Text("$n layer${n == 1 ? "" : "s"}",
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
                      // The picked piece taken out, from the strip as well
                      // as the list: a tablet has no Delete key.
                      CanvasIconButton(
                        key: const ValueKey("textLayersDelete"),
                        tight: true,
                        icon: Icons.delete_outline,
                        tooltip: "Delete the picked layer",
                        onPressed: picked == null || picked.locked
                            ? null
                            : () => _remove(picked),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: LayersAddButton(
                          tapKey: "textLayersAdd",
                          open: _adding,
                          onPressed: () => setState(() => _adding = !_adding),
                        ),
                      ),
                    ]),
                    if (_adding)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: CanvasTiles<_TextAdd>(
                          key: const ValueKey("textAddTiles"),
                          tiles: [
                            for (var a in _TextAdd.values)
                              CanvasTile(a, a.label, icon: a.icon),
                          ],
                          columns: 2,
                          previewHeight: 26,
                          selected: (_) => false,
                          keyOf: (a) => "textLayersAdd-${a.name}",
                          onPick: (a) {
                            setState(() => _adding = false);
                            _add(a);
                          },
                        ),
                      ),
                    if (_list)
                      _rows(context, theme, picked)
                    else
                      _strip(context, theme, picked),
                  ],
                ),
              ))),
    );
  }

  /// _thumb is a layer's picture: the piece's picture, or its words' face
  /// in their colour.
  Widget _thumb(TextItem? item, double w, double h, ThemeNotifier theme) {
    var muted = theme.colors.onSurfaceVariant;
    Widget inside;
    var icon = item?.icon;
    if (icon != null) {
      var image = icon.on
          ? controller.images.resolve(icon.assetId, const BackgroundRemoval())
          : null;
      inside = image == null
          ? Icon(Icons.image_outlined, size: h * 0.55, color: muted)
          : CustomPaint(
              size: Size.infinite,
              painter: _ContainPainter(controller.images.thumbnail(image)));
    } else {
      var spec = item?.spec ?? e.textSpec;
      inside = Text("Aa",
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontFamily: spec.fontFamily,
            fontWeight: FontWeight
                .values[((spec.weight / 100).round() - 1).clamp(0, 8).toInt()],
            fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
            fontSize: h * 0.5,
            height: 1,
            color: spec.color.a < 0.1 ? theme.colors.onSurface : spec.color,
          ));
    }
    return Container(
      width: w,
      height: h,
      padding: const EdgeInsets.all(2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: theme.colors.surfaceContainerHighest,
      ),
      child: inside,
    );
  }

  /// _name is what [item] is called on its chip or row.
  String _name(TextItem? item) => item == null ? _bodyName : item.says;

  /// _detail is the second line of a row: what kind of layer, and where.
  String _detail(TextItem? item) {
    if (item == null) {
      return [
        "Text",
        e.slot?.label ?? "fills the box",
      ].join(" · ");
    }
    return [
      item.isIcon ? "Picture" : "Text",
      item.slot.label,
    ].join(" · ");
  }

  /// _chip is one layer on the strip.
  Widget _chip(BuildContext context, ThemeNotifier theme, TextItem? item,
      bool on, String key) {
    var accent = theme.colors.primary;
    var hidden = item?.hidden ?? false;
    var locked = item?.locked ?? false;
    return Opacity(
      opacity: hidden ? 0.5 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _pick(item);
            Focus.of(context).requestFocus();
          },
          child: Container(
            width: 70,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: on ? accent.withValues(alpha: 0.14) : null,
              border: Border.all(
                  color: on ? accent : theme.colors.outlineVariant,
                  width: on ? 1.5 : 1),
            ),
            child: Column(children: [
              Stack(children: [
                _thumb(item, 60, 42, theme),
                if (hidden || locked)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Icon(hidden ? Icons.visibility_off : Icons.lock,
                        size: 12, color: theme.colors.onSurface),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(_name(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                      color: theme.colors.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }

  /// _strip is the layers in a line, the element's own words first and
  /// held there; the pieces after them can be dragged into another order.
  Widget _strip(BuildContext context, ThemeNotifier theme, TextItem? picked) {
    var items = e.items;
    return SizedBox(
      height: 84,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 6, 8),
          child: _chip(context, theme, null, picked == null, "textLayer-body"),
        ),
        Expanded(
          child: ReorderableListView(
            key: const ValueKey("textLayersStrip"),
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
            onReorderItem: _move,
            children: [
              for (var (i, item) in items.indexed)
                ReorderableDelayedDragStartListener(
                  key: ValueKey("textLayerChip-${item.id}"),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Builder(
                        builder: (context) => _chip(context, theme, item,
                            picked?.id == item.id, "textLayer-${item.id}")),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  /// _rows is the layers down the panel, the element's own words at the top.
  Widget _rows(BuildContext context, ThemeNotifier theme, TextItem? picked) {
    var items = e.items;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(context, theme, null, -1, picked == null),
            ReorderableListView(
              key: const ValueKey("textLayersRows"),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: _move,
              children: [
                for (var (i, item) in items.indexed)
                  _row(context, theme, item, i, picked?.id == item.id),
              ],
            ),
          ]),
    );
  }

  /// _row is one layer in the list: [item] at [index], or the element's own
  /// words with null -- which has no handle, eye or lock, being the element.
  Widget _row(BuildContext context, ThemeNotifier theme, TextItem? item,
      int index, bool on) {
    var muted = theme.colors.onSurfaceVariant;
    var hidden = item?.hidden ?? false;
    var id = item?.id ?? "body";

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

    return Container(
      key: ValueKey("textLayerRow-$id"),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: on ? theme.colors.primary.withValues(alpha: 0.12) : null,
      ),
      child: Builder(
        builder: (context) => InkWell(
          key: ValueKey("textLayer-$id"),
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _pick(item);
            Focus.of(context).requestFocus();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              if (item == null)
                const SizedBox(width: 20)
              else
                ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: "Drag to move",
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child:
                            Icon(Icons.drag_indicator, size: 16, color: muted),
                      ),
                    ),
                  ),
                ),
              Opacity(
                opacity: hidden ? 0.5 : 1,
                child: _thumb(item, 40, 30, theme),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_name(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                on ? FontWeight.w600 : FontWeight.normal,
                            color: hidden ? muted : theme.colors.onSurface)),
                    Text(_detail(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: muted)),
                  ],
                ),
              ),
              if (on && item != null) ...[
                tap("textLayerUp-$id", Icons.arrow_upward,
                    index == 0 ? null : () => _move(index, index - 1),
                    label: "Move up"),
                tap(
                    "textLayerDown-$id",
                    Icons.arrow_downward,
                    index == e.items.length - 1
                        ? null
                        : () => _move(index, index + 1),
                    label: "Move down"),
                tap("textLayerDuplicate", Icons.copy_all_outlined,
                    () => _duplicate(item),
                    label: "Duplicate"),
                tap("textLayerDelete", Icons.delete_outline,
                    item.locked ? null : () => _remove(item),
                    label: "Delete"),
              ],
              if (item != null) ...[
                tap(
                    "textLayerLock-$id",
                    item.locked ? Icons.lock : Icons.lock_open_outlined,
                    () => _change(item, (i) => i.copyWith(locked: !i.locked)),
                    label: item.locked ? "Unlock" : "Lock"),
                tap(
                    "textLayerShow-$id",
                    item.hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    () => _change(item, (i) => i.copyWith(hidden: !i.hidden)),
                    label: item.hidden ? "Show" : "Hide"),
              ] else
                // Level with the pieces' eye and lock below it.
                const SizedBox(width: 50),
            ]),
          ),
        ),
      ),
    );
  }
}

/// freeTextSlot is where the next piece of [e] goes: the first slot nothing
/// is in, so two pieces added one after another do not land on top of each
/// other.
TextSlot freeTextSlot(TextElement e) {
  var taken = {for (var item in e.items) item.slot};
  for (var slot in const [
    TextSlot.topLeft,
    TextSlot.bottomLeft,
    TextSlot.middleRight,
    TextSlot.topRight,
    TextSlot.bottomRight,
    TextSlot.topCentre,
    TextSlot.bottomCentre,
    TextSlot.middleLeft,
    TextSlot.middleCentre,
  ]) {
    if (!taken.contains(slot)) return slot;
  }
  return TextSlot.topLeft;
}

/// _ContainPainter draws [image] whole inside its box.
class _ContainPainter extends CustomPainter {
  final ui.Image image;
  _ContainPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    var iw = image.width.toDouble(), ih = image.height.toDouble();
    var scale = math.min(size.width / iw, size.height / ih);
    var dw = iw * scale, dh = ih * scale;
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, iw, ih),
        Rect.fromLTWH((size.width - dw) / 2, (size.height - dh) / 2, dw, dh),
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_ContainPainter old) => !identical(old.image, image);
}
