import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/tablet_input.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:flutter/material.dart';

// vector_settings.dart is a drawing's settings: which drawing, how it sits in
// its box, editing it point by point -- and while it is being edited, how
// the picked shape is painted and how the edit points themselves look.

/// startVectorEditing opens [e] for editing point by point.
///
/// A drawing not yet taken apart is taken apart first. Where that would lose
/// something -- a gradient made solid, words left out -- the reader is told
/// what and asked first, since from then on the shapes are what is drawn.
Future<void> startVectorEditing(
    BuildContext context, CanvasController controller, VectorElement e) async {
  if (e.edited) {
    controller.editVector(e.id);
    return;
  }
  // Nothing in it yet: a blank drawing, for the pen.
  if (!e.hasDrawing) {
    controller.replaceElement(blankDrawing(e));
    controller.editVector(e.id);
    controller.vectorPen = true;
    return;
  }
  var parts = await takeApart(e);
  if (!context.mounted) return;
  if (parts == null || parts.shapes.isEmpty) {
    SnackBarModel.of(context).error(parts == null
        ? "This drawing could not be read."
        : "This drawing has no shapes that can be edited.");
    return;
  }
  if (parts.dropped.isNotEmpty) {
    var sure = await askToConfirm(context,
        title: "Edit this drawing?",
        message: "Editing turns the drawing into shapes you can change. "
            "Some of it cannot be kept as it is: "
            "${parts.dropped.join(", ")}. "
            "Those parts will look different from now on. "
            "Back to the original puts the file's drawing back.",
        confirm: "Edit it");
    if (!sure || !context.mounted) return;
  }
  // The element as it is now: the read took time, and it may have moved.
  var now = controller.document.elementById(e.id);
  if (now is! VectorElement) return;
  controller.replaceElement(
      now.copyWith(viewBox: parts.viewBox, shapes: parts.shapes));
  controller.editVector(e.id);
}

/// _drawingAspect is a drawing's own proportions, read from its file, or
/// null where it says none.
Future<double?> _drawingAspect(String id) async {
  var bytes = await CanvasMedia.load(MediaKind.vector, id);
  if (bytes == null) return null;
  var parts = importSvg(utf8.decode(bytes, allowMalformed: true));
  var box = parts?.viewBox;
  if (box == null || box.width <= 0 || box.height <= 0) return null;
  return box.width / box.height;
}

List<Widget> vectorSettings(
    BuildContext context,
    CanvasController controller,
    VectorElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(VectorElement next) {
    begin();
    write(next);
    commit();
  }

  var editing = controller.vectorEditing == e.id && e.edited;
  var shapes = e.shapes ?? const <VectorShape>[];
  var picked = controller.vectorShape;
  var one = picked >= 0 && picked < shapes.length;

  /// change applies [edit] to the shape picked, or to every shape where none
  /// is: recolouring a whole one-colour icon is one change, not twelve.
  void change(VectorShape Function(VectorShape) edit, {bool live = false}) {
    if (shapes.isEmpty) return;
    var next = [
      for (var (i, s) in shapes.indexed) one && i != picked ? s : edit(s),
    ];
    begin();
    write(e.copyWith(shapes: next));
    if (!live) commit();
  }

  /// use puts the drawing [id] in, given the drawing's proportions as a
  /// picture is -- the box shrunk to them, never grown.
  Future<void> use(String id) async {
    var aspect = await _drawingAspect(id);
    var next =
        e.copyWith(assetId: id, viewBox: ui.Rect.zero, clearShapes: true);
    if (aspect != null) {
      var b = e.bounds;
      var w = b.width, h = b.height;
      if (w / h > aspect) {
        w = h * aspect;
      } else {
        h = w / aspect;
      }
      next = next.withBase(
          x: b.center.dx - w / 2,
          y: b.center.dy - h / 2,
          width: w,
          height: h) as VectorElement;
    }
    controller.editVector(null);
    now(next);
  }

  // What the shape controls show: the picked shape's, or the first's.
  var shown = one ? shapes[picked] : (shapes.isEmpty ? null : shapes.first);

  return [
    CanvasControlGroup(
      label: "Drawing",
      hideCaption: true,
      rule: false,
      children: [
        CanvasIconButton(
          key: const ValueKey("vectorChoose"),
          icon: e.hasDrawing ? Icons.draw_outlined : Icons.add,
          tooltip: e.hasDrawing ? "Change drawing" : "Add drawing",
          onPressed: () async {
            var id = await pickCanvasVector(context);
            if (id != null) await use(id);
          },
        ),
        CanvasIconButton(
          key: const ValueKey("vectorRecent"),
          icon: Icons.photo_library_outlined,
          tooltip: "Recent drawings",
          onPressed: () async {
            var id = await showRecentPictures(context, drawings: true);
            if (id != null) await use(id);
          },
        ),
        CanvasDropdown<VectorFit>(
          label: "Fit",
          value: e.fit,
          width: 86,
          options: [for (var f in VectorFit.values) (f, f.label)],
          onChanged: (v) => now(e.copyWith(fit: v)),
        ),
        CanvasIconButton(
          key: const ValueKey("vectorEdit"),
          icon: Icons.edit_outlined,
          tooltip: editing ? "Stop editing" : "Edit points",
          active: editing,
          onPressed: () => editing
              ? controller.editVector(null)
              : startVectorEditing(context, controller, e),
        ),
        if (e.edited && e.assetId.isNotEmpty)
          CanvasIconButton(
            key: const ValueKey("vectorRevert"),
            icon: Icons.restore,
            tooltip: "Revert drawing",
            onPressed: () async {
              var sure = await askToConfirm(context,
                  title: "Back to the original?",
                  message: "Every change made to this drawing's points and "
                      "colours will be lost.",
                  confirm: "Put it back");
              if (!sure) return;
              controller.editVector(null);
              now(e.copyWith(viewBox: ui.Rect.zero, clearShapes: true));
            },
          ),
        CanvasHint(editing
            ? _toolHint(controller.vectorTool)
            : "Double-click the drawing, or press Edit points, to edit its "
                "points, handles and colours -- or, with no drawing in it "
                "yet, to draw one with the pen. A drawing from a file is "
                "drawn exactly as the file draws it until then."),
      ],
    ),
    // The tools, while it is being edited: what a press on it does -- and,
    // on a row of their own below, the one in hand's settings.
    if (editing) ...[
      CanvasControlGroup(
        label: "Tools",
        hideCaption: true,
        rule: false,
        children: [
          for (var (tool, icon) in const [
            (VectorTool.select, Icons.near_me_outlined),
            (VectorTool.pen, Icons.draw_outlined),
            (VectorTool.scale, Icons.open_in_full),
            (VectorTool.tint, Icons.brush_outlined),
            (VectorTool.boolean, Icons.join_inner),
            (VectorTool.align, Icons.align_horizontal_center),
            (VectorTool.corner, Icons.rounded_corner),
            (VectorTool.pencil, Icons.edit),
            (VectorTool.eraser, Icons.cleaning_services_outlined),
          ])
            CanvasIconButton(
              key: ValueKey("vectorTool-${tool.name}"),
              icon: icon,
              tooltip: "${tool.label} (${_toolKey(tool)})",
              active: controller.vectorTool == tool,
              onPressed: () => controller.vectorTool = tool,
            ),
        ],
      ),
      if (_toolSettings(e, controller) case var settings
          when settings.isNotEmpty)
        CanvasControlGroup(
          key: const ValueKey("vectorToolSettings"),
          label: "${controller.vectorTool.label} settings",
          hideCaption: true,
          rule: false,
          children: settings,
        ),
      ..._toolMore(controller),
    ],
    if (e.edited && shown != null)
      _shapeGroup(e, shapes, picked, one, shown, change, commit,
          points: editing ? controller.vectorPicks : const {},
          onPoints: (which, edit) {
        var next = e;
        // A joint is one point: every end lying there takes it.
        for (var pick in joinedTo(e, which)) {
          if (vectorNodeAt(next, pick) case var n?) {
            next = withVectorNode(next, pick, edit(n));
          }
        }
        now(next);
      }),
  ];
}

/// _toolSettings is the settings of the tool in hand, for the row under
/// the tools -- empty for a tool with none just now.
List<Widget> _toolSettings(VectorElement e, CanvasController controller) {
  var picks = controller.vectorPicks;
  switch (controller.vectorTool) {
    // The handles of the points picked: how the pair move together, what a
    // drag of one may change, and two quick fixes.
    case VectorTool.select || VectorTool.pen:
      if (picks.isEmpty) return const [];
      var first = vectorNodeAt(e, picks.first);
      return [
        CanvasDropdown<VectorHandles>(
          key: const ValueKey("vectorHandles"),
          label: "Handles",
          value: first?.handles ?? VectorHandles.free,
          width: 92,
          options: [for (var h in VectorHandles.values) (h, h.label)],
          onChanged: (h) => controller
              .editPickedPoints((e, picks) => withHandles(e, picks, h)),
        ),
        CanvasDropdown<VectorHandleDrag>(
          key: const ValueKey("vectorHandleDrag"),
          label: "Dragging one",
          value: controller.vectorHandleDrag,
          width: 104,
          options: [for (var d in VectorHandleDrag.values) (d, d.label)],
          onChanged: (d) => controller.vectorHandleDrag = d,
        ),
        CanvasToggle(
          key: const ValueKey("vectorHandleSnap"),
          label: "Snap 15°",
          value: controller.vectorHandleSnap,
          onChanged: (v) => controller.vectorHandleSnap = v,
        ),
        CanvasIconButton(
          key: const ValueKey("vectorHandlesEven"),
          icon: Icons.straighten,
          tooltip: "Even handles",
          onPressed: () => controller.editPickedPoints(withEvenHandles),
        ),
      ];
    case VectorTool.align:
      return [
        for (var (how, icon) in const [
          (VectorAlign.left, Icons.align_horizontal_left),
          (VectorAlign.centreX, Icons.align_horizontal_center),
          (VectorAlign.right, Icons.align_horizontal_right),
          (VectorAlign.top, Icons.align_vertical_top),
          (VectorAlign.centreY, Icons.align_vertical_center),
          (VectorAlign.bottom, Icons.align_vertical_bottom),
          (VectorAlign.spreadX, Icons.horizontal_distribute),
          (VectorAlign.spreadY, Icons.vertical_distribute),
        ])
          CanvasIconButton(
            key: ValueKey("vectorAlign-${how.name}"),
            icon: icon,
            tooltip: how.label,
            onPressed: picks.length < 2
                ? null
                : () => controller
                    .editPickedPoints((e, picks) => withAligned(e, picks, how)),
          ),
      ];
    case VectorTool.corner:
      return [
        CanvasDropdown<bool>(
          key: const ValueKey("vectorCornerRound"),
          label: "Corner",
          value: controller.vectorCornerRound,
          width: 80,
          options: const [(true, "Round"), (false, "Cut")],
          onChanged: (v) => controller.vectorCornerRound = v,
        ),
        CanvasNumberField(
          key: const ValueKey("vectorCornerSize"),
          label: "Size",
          value: controller.vectorCornerSize,
          min: 0.5,
          max: 2000,
          decimals: 0,
          width: 56,
          onChanged: (v) => controller.vectorCornerSize = v,
        ),
      ];
    // The brush: its colour, where it shows -- by the colour, as the colour
    // is what it is shown on -- and its size and edge.
    case VectorTool.tint:
      return [
        CanvasColorButton(
          key: const ValueKey("vectorTintColour"),
          label: "Tint",
          color: controller.vectorTint.color,
          gradient: controller.vectorTint.gradient,
          onChanged: (c) =>
              controller.vectorTint = controller.vectorTint.copyWith(color: c),
          onGradientChanged: (g) => controller.vectorTint = g == null
              ? controller.vectorTint.copyWith(plain: true)
              : controller.vectorTint.copyWith(gradient: g),
        ),
        CanvasIconButton(
          key: const ValueKey("vectorTintLine"),
          icon: Icons.border_outer,
          tooltip: "Tint lines",
          active: controller.vectorTintLine,
          onPressed: () =>
              controller.vectorTintLine = !controller.vectorTintLine,
        ),
        CanvasIconButton(
          key: const ValueKey("vectorTintFill"),
          icon: Icons.square_rounded,
          tooltip: "Tint fills",
          active: controller.vectorTintFill,
          onPressed: () =>
              controller.vectorTintFill = !controller.vectorTintFill,
        ),
        CanvasNumberField(
          key: const ValueKey("vectorBrushSize"),
          label: "Size",
          value: controller.vectorBrushSize,
          min: 1,
          max: 400,
          decimals: 0,
          width: 52,
          onChanged: (v) => controller.vectorBrushSize = v,
        ),
        CanvasSlider(
          key: const ValueKey("vectorBrushSoft"),
          label: "Soft",
          value: controller.vectorBrushSoft,
          width: 80,
          onChanged: (v) => controller.vectorBrushSoft = v,
        ),
        if (hasTints(e))
          CanvasIconButton(
            key: const ValueKey("vectorTintClear"),
            icon: Icons.layers_clear_outlined,
            tooltip: "Clear tints",
            onPressed: controller.clearVectorTints,
          ),
      ];
    // The operators: what the shapes picked are combined by.
    case VectorTool.boolean:
      return [
        for (var (op, icon) in const [
          (VectorCombine.unite, Icons.join_full),
          (VectorCombine.subtract, Icons.join_left),
          (VectorCombine.intersect, Icons.join_inner),
          (VectorCombine.exclude, Icons.join_right),
        ])
          CanvasIconButton(
            key: ValueKey("vectorCombine-${op.name}"),
            icon: icon,
            tooltip: op.label,
            onPressed: controller.vectorCombining.length < 2
                ? null
                : () => controller.combineVector(op),
          ),
        CanvasIconButton(
          key: const ValueKey("vectorSeparate"),
          icon: Icons.call_split,
          tooltip: "Separate",
          onPressed: controller.vectorCombining
                  .any((b) => groupMembers(e, b).length > 1)
              ? controller.separateVector
              : null,
        ),
      ];
    case VectorTool.pencil:
      return [_brushPicker(controller)];
    // The eraser: rubbing out, or taking out whole lines; how big, how soft,
    // and what it rubs out.
    case VectorTool.eraser:
      var rub = !controller.vectorEraseWhole;
      return [
        CanvasDropdown<bool>(
          key: const ValueKey("vectorEraseWhole"),
          label: "Erase",
          value: controller.vectorEraseWhole,
          width: 104,
          options: const [(false, "Rub out"), (true, "Whole lines")],
          onChanged: (v) => controller.vectorEraseWhole = v,
        ),
        CanvasNumberField(
          key: const ValueKey("vectorEraseSize"),
          label: "Size",
          value: controller.vectorEraseSize,
          min: 1,
          max: 400,
          decimals: 0,
          width: 52,
          onChanged: (v) => controller.vectorEraseSize = v,
        ),
        if (rub) ...[
          CanvasSlider(
            key: const ValueKey("vectorEraseSoft"),
            label: "Soft",
            value: controller.vectorEraseSoft,
            width: 80,
            onChanged: (v) => controller.vectorEraseSoft = v,
          ),
          CanvasIconButton(
            key: const ValueKey("vectorEraseLine"),
            icon: Icons.border_outer,
            tooltip: "Erase lines",
            active: controller.vectorEraseLine,
            onPressed: () =>
                controller.vectorEraseLine = !controller.vectorEraseLine,
          ),
          CanvasIconButton(
            key: const ValueKey("vectorEraseFill"),
            icon: Icons.square_rounded,
            tooltip: "Erase fills",
            active: controller.vectorEraseFill,
            onPressed: () =>
                controller.vectorEraseFill = !controller.vectorEraseFill,
          ),
          if (hasErasures(e))
            CanvasIconButton(
              key: const ValueKey("vectorEraseClear"),
              icon: Icons.restore,
              tooltip: "Undo rub-outs",
              onPressed: controller.clearVectorErasures,
            ),
        ],
      ];
    // The picked points' own thickness, to type: a share of the shape's
    // stroke width -- 1 as set, 2 twice as thick.
    case VectorTool.scale:
      if (picks.isEmpty) return const [];
      var width = vectorNodeAt(e, picks.first)?.width ?? 1;
      VectorElement thick(VectorElement e, Set<VectorPick> picks, double v) =>
          withWidths(e, {for (var p in joinedTo(e, picks)) p: 1}, v);
      return [
        CanvasNumberField(
          key: const ValueKey("vectorPointWidth"),
          label: "Thickness",
          value: width,
          min: 0,
          max: 20,
          decimals: 2,
          width: 64,
          onChanged: (v) =>
              controller.editPickedPoints((e, picks) => thick(e, picks, v)),
        ),
        CanvasIconButton(
          key: const ValueKey("vectorPointWidthReset"),
          icon: Icons.restart_alt,
          tooltip: "Reset thickness",
          onPressed: width == 1
              ? null
              : () =>
                  controller.editPickedPoints((e, picks) => thick(e, picks, 1)),
        ),
      ];
  }
}

/// _brushPicker is the pencil's main row: which brush, its colour and size,
/// how see-through and how steadied, and keeping it as a brush of one's
/// own. Watches the saved brushes as well as the controller.
Widget _brushPicker(CanvasController controller) {
  var store = SavedPresetStore.brushes;
  store.load();
  return ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      var brush = controller.vectorBrush;
      var saved = [
        for (var p in store.presets) (p, VectorBrush.fromJson(p.data)),
      ];
      // Which entry the brush in hand is: the saved one or the built-in one
      // it still draws exactly as, by name -- or itself, changed.
      String? picked;
      for (var (p, b) in saved) {
        if (p.name == brush.name && b.sameAs(brush)) picked = "saved:${p.id}";
      }
      for (var b in builtInBrushes) {
        if (picked == null && b.name == brush.name && b.sameAs(brush)) {
          picked = "built:${b.name}";
        }
      }
      var mine = saved.where((s) => s.$1.name == brush.name).firstOrNull;
      Widget slider(String key, String label, double value,
              VectorBrush Function(double) set,
              {double min = 0, double max = 1}) =>
          CanvasSlider(
            key: ValueKey(key),
            label: label,
            value: value.clamp(min, max),
            min: min,
            max: max,
            width: 80,
            onChanged: (v) => controller.vectorBrush = set(v),
          );
      return CanvasWrap(children: [
        CanvasDropdown<String>(
          key: const ValueKey("vectorBrush"),
          label: "Brush",
          value: picked ?? "current",
          width: 130,
          options: [
            if (picked == null) ("current", "${brush.name} (changed)"),
            for (var b in builtInBrushes) ("built:${b.name}", b.name),
            for (var (p, _) in saved) ("saved:${p.id}", p.name),
          ],
          onChanged: (key) {
            if (key.startsWith("built:")) {
              var name = key.substring(6);
              controller.vectorBrush =
                  builtInBrushes.firstWhere((b) => b.name == name);
            } else if (key.startsWith("saved:")) {
              var id = key.substring(6);
              var (p, b) = saved.firstWhere((s) => s.$1.id == id);
              controller.vectorBrush = b.copyWith(name: p.name);
            }
          },
        ),
        // A fill with no line has no line colour to choose.
        if (brush.line || !brush.fill)
          CanvasColorButton(
            key: const ValueKey("vectorPencilColour"),
            label: "Line",
            color: controller.vectorPencilColour,
            onChanged: (c) => controller.vectorPencilColour = c,
          ),
        CanvasToggle(
          key: const ValueKey("vectorBrushFill"),
          label: "Fill",
          value: brush.fill,
          onChanged: (v) => controller.vectorBrush = brush.copyWith(fill: v),
        ),
        // The fill colour by the Fill switch, and the quick fill by that:
        // both fill with it.
        CanvasColorButton(
          key: const ValueKey("vectorPencilFill"),
          label: "Fill",
          color: controller.vectorPencilFill,
          onChanged: (c) => controller.vectorPencilFill = c,
        ),
        CanvasIconButton(
          key: const ValueKey("vectorQuickFill"),
          icon: Icons.format_color_fill,
          tooltip: "Quick fill",
          active: controller.vectorQuickFill,
          onPressed: () =>
              controller.vectorQuickFill = !controller.vectorQuickFill,
        ),
        if (controller.vectorQuickFill)
          CanvasNumberField(
            key: const ValueKey("vectorFillGap"),
            label: "Gap",
            value: controller.vectorFillGap,
            min: 0,
            max: 50,
            decimals: 0,
            width: 48,
            onChanged: (v) => controller.vectorFillGap = v,
          ),
        CanvasNumberField(
          key: const ValueKey("vectorBrushWidth"),
          label: "Size",
          value: brush.size,
          min: 0.5,
          max: 400,
          decimals: 1,
          width: 56,
          onChanged: (v) => controller.vectorBrush = brush.copyWith(size: v),
        ),
        slider("vectorBrushOpacity", "Opacity", brush.opacity,
            (v) => brush.copyWith(opacity: v)),
        slider("vectorBrushSmoothing", "Steady", brush.smoothing,
            (v) => brush.copyWith(smoothing: v)),
        CanvasIconButton(
          key: const ValueKey("vectorMirrorAcross"),
          icon: Icons.swap_horiz,
          tooltip: "Vertical mirror",
          active: controller.vectorMirrorAcross,
          onPressed: () =>
              controller.vectorMirrorAcross = !controller.vectorMirrorAcross,
        ),
        CanvasIconButton(
          key: const ValueKey("vectorMirrorDown"),
          icon: Icons.swap_vert,
          tooltip: "Horizontal mirror",
          active: controller.vectorMirrorDown,
          onPressed: () =>
              controller.vectorMirrorDown = !controller.vectorMirrorDown,
        ),
        const _PenMeter(key: ValueKey("vectorPenMeter")),
        CanvasIconButton(
          key: const ValueKey("vectorPencilPoints"),
          icon: Icons.scatter_plot_outlined,
          tooltip:
              controller.vectorPencilPoints ? "Hide points" : "Show points",
          active: controller.vectorPencilPoints,
          onPressed: () =>
              controller.vectorPencilPoints = !controller.vectorPencilPoints,
        ),
        CanvasTextField(
          key: const ValueKey("vectorBrushName"),
          label: "Name",
          value: brush.name,
          width: 110,
          grow: false,
          onChanged: (v) => controller.vectorBrush = brush.copyWith(name: v),
        ),
        CanvasIconButton(
          key: const ValueKey("vectorBrushSave"),
          icon: Icons.bookmark_add_outlined,
          tooltip: mine != null ? "Save changes" : "Save brush",
          onPressed: brush.name.trim().isEmpty
              ? null
              : () async {
                  var name = brush.name.trim();
                  // A built-in brush's name is the built-in brush's.
                  if (builtInBrushes.any((b) => b.name == name)) {
                    name = "$name (mine)";
                  }
                  if (mine != null) await store.remove(mine.$1);
                  await store.save(name, brush.copyWith(name: name).toJson());
                  controller.vectorBrush = brush.copyWith(name: name);
                },
        ),
        if (mine != null)
          CanvasIconButton(
            key: const ValueKey("vectorBrushDelete"),
            icon: Icons.delete_outline,
            tooltip: "Delete brush",
            onPressed: () async {
              await store.remove(mine.$1);
              controller.vectorBrush = builtInBrushes.first;
            },
          ),
      ]);
    },
  );
}

/// _toolMore is the tool in hand's settings beyond its row: for the pencil,
/// what shapes its line, and what the pen's buttons do.
List<Widget> _toolMore(CanvasController controller) {
  if (controller.vectorTool != VectorTool.pencil) return const [];
  var brush = controller.vectorBrush;
  Widget slider(String key, String label, double value,
          VectorBrush Function(double) set,
          {double min = 0, double max = 1}) =>
      CanvasSlider(
        key: ValueKey(key),
        label: label,
        value: value.clamp(min, max),
        min: min,
        max: max,
        width: 80,
        onChanged: (v) => controller.vectorBrush = set(v),
      );
  return [
    CanvasMoreGroup(
      key: const ValueKey("vectorBrushMore"),
      label: "Brush shape",
      remember: "vectorBrushMore",
      tooltip: "Brush shape",
      rule: false,
      row: [
        CanvasToggle(
          key: const ValueKey("vectorBrushPressure"),
          label: "Pressure",
          value: brush.pressure,
          onChanged: (v) =>
              controller.vectorBrush = brush.copyWith(pressure: v),
        ),
        if (brush.pressure) ...[
          slider("vectorBrushThinnest", "Lightest", brush.thinnest,
              (v) => brush.copyWith(thinnest: v)),
          slider("vectorBrushCurve", "Firmness", brush.curve,
              (v) => brush.copyWith(curve: v),
              min: 0.3, max: 3),
        ],
      ],
      more: [
        slider("vectorBrushTaperIn", "Taper in", brush.taperIn,
            (v) => brush.copyWith(taperIn: v),
            max: 0.5),
        slider("vectorBrushTaperOut", "Taper out", brush.taperOut,
            (v) => brush.copyWith(taperOut: v),
            max: 0.5),
        slider("vectorBrushTilt", "Tilt", brush.tilt,
            (v) => brush.copyWith(tilt: v),
            max: 2),
        slider(
            "vectorBrushNib", "Nib", brush.nib, (v) => brush.copyWith(nib: v)),
        if (brush.nib > 0)
          CanvasNumberField(
            key: const ValueKey("vectorBrushNibAngle"),
            label: "Nib angle",
            value: brush.nibAngle,
            min: -180,
            max: 180,
            decimals: 0,
            width: 56,
            onChanged: (v) =>
                controller.vectorBrush = brush.copyWith(nibAngle: v),
          ),
        if (brush.fill)
          CanvasToggle(
            key: const ValueKey("vectorBrushLine"),
            label: "Line",
            value: brush.line,
            onChanged: (v) => controller.vectorBrush = brush.copyWith(line: v),
          ),
        CanvasToggle(
          key: const ValueKey("vectorBrushFlat"),
          label: "Flat ends",
          value: brush.flat,
          onChanged: (v) => controller.vectorBrush = brush.copyWith(flat: v),
        ),
        const CanvasHint("Pressure makes the line thicker the harder the pen "
            "presses -- or, with a mouse or where the pen's pressure does "
            "not reach the app, the slower it moves. Lightest is how thin "
            "the lightest touch goes; Firmness how hard a press it takes to "
            "go wide. Tapers swell the start and fade the end. Tilt widens "
            "the line as the pen leans over, for shading. Nib makes it a "
            "broad nib, thin along its angle and wide across it."),
      ],
    ),
    CanvasMoreGroup(
      key: const ValueKey("vectorPenButtons"),
      label: "Pen buttons",
      remember: "vectorPenButtons",
      tooltip: "Pen buttons",
      rule: false,
      row: const [],
      more: [
        for (var (i, label) in const [
          (0, "Button 1"),
          (1, "Button 2"),
          (2, "Button 3"),
        ])
          CanvasDropdown<StylusAction>(
            key: ValueKey("vectorStylus-$i"),
            label: label,
            value: controller.stylusButtons[i],
            width: 120,
            options: [for (var a in StylusAction.values) (a, a.label)],
            onChanged: (a) => controller.setStylusButton(i, a),
          ),
        CanvasToggle(
          key: const ValueKey("vectorReadTablet"),
          label: "Read the tablet",
          value: TabletInput.instance.reading,
          onChanged: (v) {
            TabletInput.instance.reading = v;
            // The reader is not the controller's, so nothing else tells the
            // panel to redraw the switch: setting the brush to itself does.
            controller.vectorBrush = controller.vectorBrush;
          },
        ),
        CanvasDropdown<StylusAction>(
          key: const ValueKey("vectorStylusEraser"),
          label: "Other end",
          value: controller.stylusEraser,
          width: 120,
          options: [for (var a in StylusAction.values) (a, a.label)],
          onChanged: (a) => controller.stylusEraser = a,
        ),
        const CanvasHint("A tablet's driver acts on the pen's buttons itself "
            "unless it is told to send them on as clicks. In Wacom Center, "
            "give Bison Relay settings of its own and set the pen's buttons "
            "to Right click (Button 1), Middle click (Button 2) and 4th "
            "click (Button 3); other apps keep theirs. Or hold a key as the "
            "pen touches: Shift for Button 1, Option for Button 2, Control "
            "for Button 3 -- the way on a pen display whose buttons are its "
            "own, such as a MovinkPad, whose sidebar has these keys. The "
            "other end is the eraser end, on a pen that has one."),
      ],
    ),
  ];
}

String _capName(StrokeCap c) => switch (c) {
      StrokeCap.butt => "Flat",
      StrokeCap.round => "Round",
      StrokeCap.square => "Square",
    };

String _joinName(StrokeJoin j) => switch (j) {
      StrokeJoin.miter => "Sharp",
      StrokeJoin.round => "Round",
      StrokeJoin.bevel => "Cut",
    };

/// _toolKey is the key that picks [tool] while a drawing is edited.
String _toolKey(VectorTool tool) => switch (tool) {
      VectorTool.select => "V",
      VectorTool.pen => "P",
      VectorTool.scale => "S",
      VectorTool.tint => "I",
      VectorTool.boolean => "B",
      VectorTool.align => "A",
      VectorTool.corner => "C",
      VectorTool.pencil => "N",
      VectorTool.eraser => "E",
    };

/// _toolHint is how [tool] is used, said where the reader is looking.
String _toolHint(VectorTool tool) => switch (tool) {
      VectorTool.select => "Click a shape to pick it. Drag across the drawing "
          "-- or in from outside it -- to pick the points in a box. Click a "
          "point to pick it and show its handles; Shift and a click picks "
          "several, and dragging one of them, or the box round them, moves "
          "them all. Hold Alt to move one handle on its own. Double-click a "
          "point to make it a corner or smooth, and double-click a shape's "
          "outline to add a point there. Delete takes out the points picked. "
          "Escape, or a click outside the drawing, finishes. With points "
          "picked, the row below sets how their handles move: free, aligned "
          "or mirrored; what dragging one may change; and snapping.",
      VectorTool.pen => "Click to put points down, dragging to pull a curve "
          "out of each. Points and handles are taken hold of and moved as "
          "with picking -- and the next point put down joins on from the "
          "point taken: from the end of a line the line goes on, from the "
          "middle a new line branches off, joined there, and moved, the "
          "joint moves as one point. Click the first point to close the "
          "shape. Double-click, Return or Escape finishes the line, ready "
          "to start another; Escape again puts the pen away.",
      VectorTool.scale => "Drag right or up to make the line thicker, left "
          "or down to make it thinner. Click a point to pick it -- Shift and "
          "a click picks several -- and a drag, or Thickness, changes those "
          "points alone; click off the points to let them go. With nothing "
          "picked, drag across a line to thicken or thin every point the "
          "drag passes near. The points are hidden while you drag.",
      VectorTool.tint => "Paint over the drawing to tint it. The tint shows "
          "only where the drawing is: on its lines, in its fills, or both -- "
          "Tint line and Tint fill. A soft brush blends into what is under "
          "it; a gradient from the colour button is laid across each stroke. "
          "Hold Alt to rub tint off.",
      VectorTool.boolean => "Click shapes to pick them -- click again to "
          "unpick -- then press an operator: Unite makes one shape round "
          "them all; Subtract cuts the others out of the lowest, which is "
          "how a hole is made; Intersect keeps only where they overlap; "
          "Exclude keeps where they do not. The result takes the lowest "
          "shape's colours. The shapes keep their own points, to edit with "
          "the other tools, and Separate makes them shapes of their own "
          "again.",
      VectorTool.align => "Pick points as with the select tool -- a box, or "
          "Shift and a click -- then line them up: to the left, middle or "
          "right of the box round them, its top, middle or bottom, or "
          "spread out with even gaps across or down.",
      VectorTool.eraser => "Rub out what the eraser goes over -- the lines, "
          "the fills, or both -- soft-edged if you like; or set Erase to "
          "Whole lines to take out every line and shape it touches. Undo "
          "rub-outs takes every rub-out back, leaving what was rubbed out "
          "whole again.",
      VectorTool.pencil => "Draw freehand: each stroke is a line of its own, "
          "thick and thin as the brush and the pen say, to edit like any "
          "other. Pick a brush -- or make one: change it, name it, and keep "
          "it with the bookmark. The pen's buttons do what Pen buttons sets.",
      VectorTool.corner => "Click a point between two others to round its "
          "corner -- or cut it, with Corner set to Cut -- as far back along "
          "each side as Size says. Drag out from the point as you press to "
          "set how far by eye. Elsewhere a click picks, as the select tool "
          "does.",
    };

/// _shapeGroup is how the picked shape -- or every shape, with none picked
/// -- is painted. Line ends and corners are offered only where they would
/// change something: ends on a line that has ends, corners on a line.
Widget _shapeGroup(
    VectorElement e,
    List<VectorShape> shapes,
    int picked,
    bool one,
    VectorShape shown,
    void Function(VectorShape Function(VectorShape), {bool live}) change,
    VoidCallback commit,
    {Set<VectorPick> points = const {},
    void Function(Set<VectorPick>, VectorNode Function(VectorNode))?
        onPoints}) {
  var considered = one ? [shapes[picked]] : shapes;
  var lined = considered.any((s) => s.stroke != null);
  var open = considered.any((s) => s.paths.any((p) => !p.closed));

  // With points picked, their own end and corner: the ends of open lines
  // among them take an end, the rest a corner. Each can go back to the
  // shape's.
  var ends = <VectorPick>{}, corners = <VectorPick>{};
  for (var pick in points) {
    if (pick.shape >= shapes.length) continue;
    var runs = shapes[pick.shape].paths;
    if (pick.path >= runs.length) continue;
    var run = runs[pick.path];
    if (pick.node >= run.nodes.length) continue;
    var atEnd =
        !run.closed && (pick.node == 0 || pick.node == run.nodes.length - 1);
    (atEnd ? ends : corners).add(pick);
  }
  VectorNode? nodeOf(VectorPick p) =>
      shapes[p.shape].paths[p.path].nodes[p.node];
  var pointLined = points
      .any((p) => p.shape < shapes.length && shapes[p.shape].stroke != null);
  var mine = points.isNotEmpty && onPoints != null;
  var several = points.length > 1;
  return CanvasMoreGroup(
    key: const ValueKey("vectorShapeGroup"),
    label: one ? "Shape ${picked + 1} of ${shapes.length}" : "All shapes",
    remember: "vectorShapeMore",
    tooltip: "Ends & corners",
    rule: false,
    row: [
      CanvasToggle(
        key: const ValueKey("vectorFillOn"),
        label: "Fill",
        value: shown.fill != null,
        onChanged: (on) => change((s) => on
            ? s.copyWith(fill: s.fill ?? const Color(0xFF888888))
            : s.copyWith(clearFill: true)),
      ),
      if (shown.fill != null)
        CanvasColorButton(
          key: const ValueKey("vectorFill"),
          label: "Fill",
          color: shown.fill!,
          onChanged: (c) => change((s) => s.copyWith(fill: c)),
        ),
      CanvasToggle(
        key: const ValueKey("vectorStrokeOn"),
        label: "Stroke",
        value: shown.stroke != null,
        onChanged: (on) => change((s) => on
            ? s.copyWith(
                stroke: s.stroke ?? const Color(0xFF000000),
                strokeWidth: s.strokeWidth > 0 ? s.strokeWidth : 1)
            : s.copyWith(clearStroke: true)),
      ),
      if (shown.stroke != null) ...[
        CanvasColorButton(
          key: const ValueKey("vectorStroke"),
          label: "Stroke",
          color: shown.stroke!,
          onChanged: (c) => change((s) => s.copyWith(stroke: c)),
        ),
        CanvasNumberField(
          key: const ValueKey("vectorStrokeWidth"),
          label: "Width",
          value: shown.strokeWidth,
          min: 0,
          max: 500,
          decimals: 1,
          width: 56,
          onChanged: (v) =>
              change((s) => s.copyWith(strokeWidth: v), live: true),
          onCommit: commit,
        ),
      ],
    ],
    more: [
      if (mine && pointLined && ends.isNotEmpty)
        CanvasDropdown<StrokeCap?>(
          key: const ValueKey("vectorPointCap"),
          label: several ? "Points' line end" : "Point's line end",
          value: nodeOf(ends.first)?.cap,
          width: 96,
          options: [
            (null, "As shape (${_capName(shown.cap)})"),
            (StrokeCap.butt, "Flat"),
            (StrokeCap.round, "Round"),
            (StrokeCap.square, "Square"),
          ],
          onChanged: (v) => onPoints(
              ends,
              (n) =>
                  v == null ? n.copyWith(clearCap: true) : n.copyWith(cap: v)),
        ),
      if (mine && pointLined && corners.isNotEmpty)
        CanvasDropdown<StrokeJoin?>(
          key: const ValueKey("vectorPointJoin"),
          label: several ? "Points' line corner" : "Point's line corner",
          value: nodeOf(corners.first)?.join,
          width: 96,
          options: [
            (null, "As shape (${_joinName(shown.join)})"),
            (StrokeJoin.miter, "Sharp"),
            (StrokeJoin.round, "Round"),
            (StrokeJoin.bevel, "Cut"),
          ],
          onChanged: (v) => onPoints(
              corners,
              (n) => v == null
                  ? n.copyWith(clearJoin: true)
                  : n.copyWith(join: v)),
        ),
      if (lined && open)
        CanvasDropdown<StrokeCap>(
          key: const ValueKey("vectorCap"),
          label: "Line ends",
          value: shown.cap,
          width: 80,
          options: const [
            (StrokeCap.butt, "Flat"),
            (StrokeCap.round, "Round"),
            (StrokeCap.square, "Square"),
          ],
          onChanged: (v) => change((s) => s.copyWith(cap: v)),
        ),
      if (lined)
        CanvasDropdown<StrokeJoin>(
          key: const ValueKey("vectorJoin"),
          label: "Line corners",
          value: shown.join,
          width: 80,
          options: const [
            (StrokeJoin.miter, "Sharp"),
            (StrokeJoin.round, "Round"),
            (StrokeJoin.bevel, "Cut"),
          ],
          onChanged: (v) => change((s) => s.copyWith(join: v)),
        ),
      if (lined)
        CanvasHint([
          if (mine && pointLined)
            "With points picked, the point's own end or corner: the shape's "
                "below say how every other point ends and turns. A point "
                "that is smooth has no corner to show.",
          if (lined && open)
            "Line ends is how an open line finishes: cut square at the "
                "point, rounded, or squared off past it.",
          if (lined)
            "Line corners is how the line turns where it bends sharply: a "
                "point, a curve, or cut off.",
        ].join(" ")),
    ],
  );
}

/// _PenMeter shows what the pen is telling the app: its pressure as a bar
/// and a number, and its tilt -- or that no pen reading is arriving, which
/// is what a mouse, or a tablet the app cannot hear, looks like. It says,
/// at a glance, whether the pencil is getting the pen's pressure or making
/// do with speed.
class _PenMeter extends StatefulWidget {
  const _PenMeter({super.key});

  @override
  State<_PenMeter> createState() => _PenMeterState();
}

class _PenMeterState extends State<_PenMeter> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // A tenth of a second: quick enough to follow a press, and nothing like
    // the couple of hundred readings a second the pen sends.
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var tablet = TabletInput.instance;
    var theme = Theme.of(context);
    var live = tablet.fresh;
    var heard = tablet.heard;
    var held = [
      for (var (bit, n) in const [(2, 1), (4, 2), (8, 3)])
        if (tablet.buttons & bit != 0) n,
    ];
    var label = live
        ? "Pen \u2013 pressure ${(tablet.pressure * 100).round()}%, "
            "tilt ${(tablet.tilt * 180 / math.pi).round()}\u00b0"
            "${held.isEmpty ? "" : ", button ${held.join("+")}"}"
        : heard
            ? (tablet.eraser ? "Pen \u2013 eraser end" : "Pen \u2013 lifted")
            : "No pen pressure yet";
    return Tooltip(
      message: "Pen pressure",
      child: SizedBox(
        width: 150,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.bodySmall, overflow: TextOverflow.fade),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: live ? tablet.pressure : 0,
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
