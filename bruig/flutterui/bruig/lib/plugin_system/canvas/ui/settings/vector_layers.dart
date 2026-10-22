import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_layer_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// vector_layers.dart is a drawing's layers: each shape it draws -- or each
// run of shapes combined into one -- as a layer, the way a picture's are
// (see ImageLayersList, which this follows). Shut, a strip that scrolls
// sideways, front first; opened, a list down the panel, front at the top,
// with each layer's eye and lock and the picked one's arrows, copy and
// delete. A layer is picked by pressing it, which opens the drawing; pressed
// again it is let go, for every shape at once.

/// VectorLayersList is [element]'s layers. [onChanged] writes a change to
/// the drawing as one step.
class VectorLayersList extends StatefulWidget {
  final CanvasController controller;
  final VectorElement element;
  final void Function(VectorElement) onChanged;

  const VectorLayersList(
      {required this.controller,
      required this.element,
      required this.onChanged,
      super.key});

  @override
  State<VectorLayersList> createState() => _VectorLayersListState();
}

/// _VectorAdd is what the strip's Add starts: a tool to make a layer with.
enum _VectorAdd {
  pen("Pen", Icons.draw_outlined, VectorTool.pen),
  pencil("Pencil", Icons.edit, VectorTool.pencil),
  shape("Shape", Icons.category_outlined, VectorTool.shapes),
  text("Text", Icons.text_fields, VectorTool.text);

  final String label;
  final IconData icon;
  final VectorTool tool;
  const _VectorAdd(this.label, this.icon, this.tool);
}

class _VectorLayersListState extends State<VectorLayersList> {
  static const _remember = "vectorLayersList";
  late bool _list = rememberedSection(_remember) ?? false;
  bool _adding = false;

  CanvasController get controller => widget.controller;
  VectorElement get e => widget.element;

  @override
  void initState() {
    super.initState();
    if (rememberedSection(_remember) == null) {
      restoreSection(_remember, (open) {
        if (mounted) setState(() => _list = open);
      });
    }
  }

  /// _picked is the first shape of the layer picked, or -1 for none: only
  /// while the drawing is open, as a picture's layers are.
  int get _picked {
    if (controller.vectorEditing != e.id) return -1;
    var at = controller.vectorShape;
    return at < 0 ? -1 : groupOf(e, at);
  }

  /// _pick picks the layer starting at [start], opening the drawing to do
  /// it -- or, picked already, lets it go: every shape, as none picked is.
  void _pick(int start) {
    if (controller.vectorEditing != e.id) controller.editVector(e.id);
    controller.pickVectorShape(_picked == start ? -1 : start);
  }

  /// _pickAll picks the whole drawing -- no layer, every shape at once --
  /// opening it to do it.
  void _pickAll() {
    if (controller.vectorEditing != e.id) controller.editVector(e.id);
    controller.pickVectorShape(-1);
  }

  Widget _wholeThumb(double w, double h, ThemeNotifier theme) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: theme.colors.surfaceContainerHighest,
        ),
        child: CustomPaint(painter: _WholePainter(e)),
      );

  /// _change is [e] with the layer at [start] given [edit] -- set on its
  /// first shape, which speaks for a combined run.
  void _change(int start, VectorShape Function(VectorShape) edit) =>
      widget.onChanged(e.withShape(start, edit(e.shapes![start])));

  /// _span is the shapes of the layer starting at [start]: it and whatever
  /// is combined into it.
  (int, int) _span(int start) {
    var starts = groupStarts(e);
    var at = starts.indexOf(start);
    var to = at + 1 < starts.length ? starts[at + 1] : e.shapes!.length;
    return (start, to);
  }

  void _remove(int start) {
    var (from, to) = _span(start);
    controller.pickVectorShape(-1);
    widget.onChanged(e.copyWith(shapes: [...e.shapes!]..removeRange(from, to)));
  }

  void _duplicate(int start) {
    var (from, to) = _span(start);
    var shapes = [...e.shapes!];
    // In front of the one copied, and picked, as a copied picture layer is.
    shapes.insertAll(to, shapes.sublist(from, to));
    widget.onChanged(e.copyWith(shapes: shapes));
    controller.pickVectorShape(to);
  }

  /// _name is what the layer [index] -- in drawing order, back first -- is
  /// called: its words, while it is still text, or its number.
  String _name(VectorDrawn d, int index) {
    if (d.style.liveText case var t?) {
      var words = t.text.trim().replaceAll(RegExp(r"\s+"), " ");
      if (words.isNotEmpty) return words;
    }
    return d.combined ? "Combined ${index + 1}" : "Shape ${index + 1}";
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var groups = vectorDrawn(e.shapes ?? const <VectorShape>[]);
    var starts = groupStarts(e);
    var n = groups.length;
    var muted = theme.colors.onSurfaceVariant;
    var picked = _picked;

    // Backspace or Delete takes out the layer picked -- here, where the
    // click that picked it put the keys.
    return Focus(
      debugLabel: "vectorLayers",
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || picked < 0) {
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
                key: const ValueKey("vectorLayers"),
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
                            key: const ValueKey("vectorLayersOpen"),
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
                                Text("Layers",
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colors.onSurface)),
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
                        key: const ValueKey("vectorLayersSolo"),
                        tight: true,
                        icon: Icons.center_focus_strong_outlined,
                        tooltip: controller.vectorSolo
                            ? "Solo on: only the picked layer can be edited"
                            : "Solo: lock every layer but the picked one",
                        active: controller.vectorSolo,
                        onPressed: () {
                          if (controller.vectorEditing != e.id) {
                            controller.editVector(e.id);
                          }
                          controller.vectorSolo = !controller.vectorSolo;
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: LayersAddButton(
                          tapKey: "vectorLayersAdd",
                          open: _adding,
                          onPressed: () => setState(() => _adding = !_adding),
                        ),
                      ),
                    ]),
                    // What a layer is made with, as a picture's kinds are
                    // shown: picking one takes up its tool.
                    if (_adding)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: CanvasTiles<_VectorAdd>(
                          key: const ValueKey("vectorAddTiles"),
                          tiles: [
                            for (var a in _VectorAdd.values)
                              CanvasTile(a, a.label, icon: a.icon),
                          ],
                          columns: 4,
                          previewHeight: 26,
                          selected: (_) => false,
                          keyOf: (a) => "vectorLayersAdd-${a.name}",
                          onPick: (a) {
                            setState(() => _adding = false);
                            if (controller.vectorEditing != e.id) {
                              controller.editVector(e.id);
                            }
                            controller.vectorTool = a.tool;
                          },
                        ),
                      ),
                    if (_list)
                      _rows(context, theme, groups, starts, picked)
                    else
                      _strip(context, theme, groups, starts, picked),
                  ],
                ),
              ))),
    );
  }

  Widget _thumb(VectorDrawn d, double w, double h, ThemeNotifier theme) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: theme.colors.surfaceContainerHighest,
        ),
        child: CustomPaint(painter: _ThumbPainter(d)),
      );

  /// _strip is the layers in a line, front first.
  Widget _strip(BuildContext context, ThemeNotifier theme,
      List<VectorDrawn> groups, List<int> starts, int picked) {
    var accent = theme.colors.primary;
    var all = picked < 0;
    // The whole drawing first, outside the order: every shape at once.
    var whole = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 6, 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey("vectorLayerAll"),
          borderRadius: BorderRadius.circular(8),
          onTap: _pickAll,
          child: Container(
            width: 70,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: all ? accent.withValues(alpha: 0.14) : null,
              border: Border.all(
                  color: all ? accent : theme.colors.outlineVariant,
                  width: all ? 1.5 : 1),
            ),
            child: Column(children: [
              _wholeThumb(60, 42, theme),
              const SizedBox(height: 2),
              // Short enough to read whole on a chip; the list says it in
              // full.
              Text("Drawing",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: all ? FontWeight.w600 : FontWeight.normal,
                      color: theme.colors.onSurface)),
            ]),
          ),
        ),
      ),
    );
    return SizedBox(
      height: 84,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        whole,
        Expanded(child: _chips(context, theme, groups, starts, picked)),
      ]),
    );
  }

  Widget _chips(BuildContext context, ThemeNotifier theme,
      List<VectorDrawn> groups, List<int> starts, int picked) {
    var n = groups.length;
    var accent = theme.colors.primary;
    return SizedBox(
      height: 84,
      child: ReorderableListView(
        key: const ValueKey("vectorLayersStrip"),
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
        onReorderItem: (from, to) {
          controller.pickVectorShape(-1);
          widget.onChanged(withGroupMoved(e, n - 1 - from, n - 1 - to));
        },
        children: [
          for (var row = 0; row < n; row++)
            Builder(
                key: ValueKey("vectorLayerChip-${starts[n - 1 - row]}"),
                builder: (context) {
                  var index = n - 1 - row;
                  var d = groups[index];
                  var start = starts[index];
                  var on = start == picked;
                  return ReorderableDelayedDragStartListener(
                      index: row,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Opacity(
                          opacity: d.style.hidden ? 0.5 : 1,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              key: ValueKey("vectorLayer-$start"),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                _pick(start);
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
                                    _thumb(d, 60, 42, theme),
                                    if (d.style.hidden || d.style.locked)
                                      Positioned(
                                        right: 2,
                                        top: 2,
                                        child: Icon(
                                            d.style.hidden
                                                ? Icons.visibility_off
                                                : Icons.lock,
                                            size: 12,
                                            color: theme.colors.onSurface),
                                      ),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(_name(d, index),
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

  /// _rows is the layers down the panel, front at the top.
  Widget _rows(BuildContext context, ThemeNotifier theme,
      List<VectorDrawn> groups, List<int> starts, int picked) {
    var n = groups.length;
    var muted = theme.colors.onSurfaceVariant;
    var all = picked < 0;
    // The whole drawing at the top, outside the order: every shape at once.
    var whole = Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: all ? theme.colors.primary.withValues(alpha: 0.12) : null,
      ),
      child: InkWell(
        key: const ValueKey("vectorLayerAll"),
        borderRadius: BorderRadius.circular(8),
        onTap: _pickAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            const SizedBox(width: 20),
            _wholeThumb(40, 30, theme),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Whole drawing",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: all ? FontWeight.w600 : FontWeight.normal,
                          color: theme.colors.onSurface)),
                  Text("Every shape at once",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: muted)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            whole,
            ReorderableListView(
              key: const ValueKey("vectorLayersRows"),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                controller.pickVectorShape(-1);
                widget.onChanged(withGroupMoved(e, n - 1 - from, n - 1 - to));
              },
              children: [
                for (var row = 0; row < n; row++)
                  _row(context, theme, groups[n - 1 - row], starts[n - 1 - row],
                      n - 1 - row, row, n, picked),
              ],
            ),
          ]),
    );
  }

  Widget _row(BuildContext context, ThemeNotifier theme, VectorDrawn d,
      int start, int index, int row, int n, int picked) {
    var muted = theme.colors.onSurfaceVariant;
    var on = start == picked;
    var style = d.style;

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

    Widget swatch(Color? c) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: muted.withValues(alpha: 0.6)),
          ),
        );

    var details = [
      if (style.liveText != null) "Text" else if (d.combined) "Combined",
      if (style.fill == null && style.stroke == null) "No paint",
      if (style.stroke != null) "line ${_width(style.strokeWidth)}",
    ].join(" · ");
    return Container(
      key: ValueKey("vectorLayerRow-$start"),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: on ? theme.colors.primary.withValues(alpha: 0.12) : null,
      ),
      child: InkWell(
        key: ValueKey("vectorLayer-$start"),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          _pick(start);
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
            Opacity(
              opacity: style.hidden ? 0.5 : 1,
              child: _thumb(d, 40, 30, theme),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_name(d, index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                          color:
                              style.hidden ? muted : theme.colors.onSurface)),
                  Row(children: [
                    if (style.fill != null) swatch(style.fill),
                    if (style.stroke != null) swatch(style.stroke),
                    Flexible(
                      child: Text(details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: muted)),
                    ),
                  ]),
                ],
              ),
            ),
            if (on) ...[
              tap(
                  "vectorLayerUp-$start",
                  Icons.arrow_upward,
                  index == n - 1
                      ? null
                      : () {
                          controller.pickVectorShape(-1);
                          widget.onChanged(withGroupMoved(e, index, index + 1));
                        },
                  label: "Move up"),
              tap(
                  "vectorLayerDown-$start",
                  Icons.arrow_downward,
                  index == 0
                      ? null
                      : () {
                          controller.pickVectorShape(-1);
                          widget.onChanged(withGroupMoved(e, index, index - 1));
                        },
                  label: "Move down"),
              tap("vectorLayerDuplicate", Icons.copy_all_outlined,
                  () => _duplicate(start),
                  label: "Duplicate"),
              tap("vectorLayerDelete", Icons.delete_outline,
                  () => _remove(start),
                  label: "Delete"),
            ],
            // Locked, it is kept as it is while the others are worked on:
            // nothing on the canvas picks it.
            tap(
                "vectorLayerLock-$start",
                style.locked
                    ? Icons.lock
                    : shapeHeld(e, start) && !style.hidden
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                () => _change(start, (s) => s.copyWith(locked: !s.locked)),
                label: style.locked ? "Unlock" : "Lock"),
            tap(
                "vectorLayerShow-$start",
                style.hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                () => _change(start, (s) => s.copyWith(hidden: !s.hidden)),
                label: style.hidden ? "Show" : "Hide"),
          ]),
        ),
      ),
    );
  }

  static String _width(double w) =>
      w == w.roundToDouble() ? "${w.round()}" : w.toStringAsFixed(1);
}

/// _ThumbPainter draws one layer, alone, filling its tile.
class _ThumbPainter extends CustomPainter {
  final VectorDrawn d;
  _ThumbPainter(this.d);

  @override
  void paint(Canvas canvas, Size size) => paintVectorThumbnail(canvas, size, d);

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      !identical(old.d.style, d.style) ||
      old.d.members.length != d.members.length ||
      !identical(old.d.outline, d.outline);
}

/// _WholePainter draws the whole drawing, filling its tile.
class _WholePainter extends CustomPainter {
  final VectorElement e;
  _WholePainter(this.e);

  @override
  void paint(Canvas canvas, Size size) => paintVector(
      canvas,
      (Offset.zero & size).deflate(3),
      e.copyWith(fit: VectorFit.contain),
      null);

  @override
  bool shouldRepaint(_WholePainter old) => !identical(old.e.shapes, e.shapes);
}
