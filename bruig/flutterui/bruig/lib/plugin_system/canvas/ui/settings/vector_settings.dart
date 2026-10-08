import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
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
          tooltip: e.hasDrawing ? "Use another drawing" : "Add a drawing",
          onPressed: () async {
            var id = await pickCanvasVector(context);
            if (id != null) await use(id);
          },
        ),
        CanvasIconButton(
          key: const ValueKey("vectorRecent"),
          icon: Icons.photo_library_outlined,
          tooltip: "Use a drawing you have already added",
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
        CanvasToggle(
          key: const ValueKey("vectorEdit"),
          label: "Edit points",
          value: editing,
          onChanged: (on) => on
              ? startVectorEditing(context, controller, e)
              : controller.editVector(null),
        ),
        if (editing)
          CanvasToggle(
            key: const ValueKey("vectorPen"),
            label: "Pen",
            value: controller.vectorPen,
            onChanged: (on) => controller.vectorPen = on,
          ),
        if (e.edited && e.assetId.isNotEmpty)
          CanvasIconButton(
            key: const ValueKey("vectorRevert"),
            icon: Icons.restore,
            tooltip: "Back to the original drawing",
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
            ? controller.vectorPen
                ? "Pen: click to put points down, dragging to pull a curve "
                    "out of each. Click the first point to close the shape, "
                    "or press Return to leave it open. Escape finishes the "
                    "shape, and again puts the pen away. P takes it out and "
                    "puts it away."
                : "Click a shape to pick it. Drag across the drawing -- or in "
                    "from outside it -- to pick the points in a box. "
                    "Click a point to pick it and show its handles; Shift and "
                    "a click picks several -- drag one of them to move them "
                    "all. Hold "
                    "Alt to move one handle on its own. Double-click a point "
                    "to make it a corner or smooth, and double-click a "
                    "shape's outline to add a point there. Delete takes out "
                    "the points picked. P takes out the pen. Escape, or a "
                    "click outside the drawing, finishes."
            : "Double-click the drawing, or switch on Edit points, to edit "
                "its points, handles and colours -- or, with no drawing in it "
                "yet, to draw one with the pen. A drawing from a file is "
                "drawn exactly as the file draws it until then."),
      ],
    ),
    if (e.edited && shown != null)
      CanvasMoreGroup(
        key: const ValueKey("vectorShapeGroup"),
        label: one ? "Shape ${picked + 1} of ${shapes.length}" : "All shapes",
        remember: "vectorShapeMore",
        tooltip: "Line ends, corners and how holes are filled",
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
          CanvasDropdown<StrokeCap>(
            key: const ValueKey("vectorCap"),
            label: "Ends",
            value: shown.cap,
            width: 80,
            options: const [
              (StrokeCap.butt, "Flat"),
              (StrokeCap.round, "Round"),
              (StrokeCap.square, "Square"),
            ],
            onChanged: (v) => change((s) => s.copyWith(cap: v)),
          ),
          CanvasDropdown<StrokeJoin>(
            key: const ValueKey("vectorJoin"),
            label: "Corners",
            value: shown.join,
            width: 80,
            options: const [
              (StrokeJoin.miter, "Sharp"),
              (StrokeJoin.round, "Round"),
              (StrokeJoin.bevel, "Cut"),
            ],
            onChanged: (v) => change((s) => s.copyWith(join: v)),
          ),
          CanvasToggle(
            key: const ValueKey("vectorEvenOdd"),
            label: "Holes",
            value: shown.evenOdd,
            onChanged: (v) => change((s) => s.copyWith(evenOdd: v)),
          ),
          const CanvasHint("Holes cuts out every outline inside another, "
              "whichever way round it was drawn -- SVG's even-odd fill."),
        ],
      ),
    if (e.edited)
      CanvasControlGroup(
        label: "Edit points",
        children: [
          CanvasColorButton(
            key: const ValueKey("vectorHandleColour"),
            label: "Colour",
            color: e.handleColor,
            onChanged: (c) => now(e.copyWith(handleColor: c)),
          ),
          CanvasNumberField(
            key: const ValueKey("vectorHandleSize"),
            label: "Size",
            value: e.handleSize,
            min: 4,
            max: 24,
            decimals: 0,
            width: 52,
            onChanged: (v) {
              begin();
              write(e.copyWith(handleSize: v));
            },
            onCommit: commit,
          ),
          const CanvasHint("How the points and handles look while the "
              "drawing is being edited -- so they stand out from it, "
              "whatever colour it is. They are never drawn on the page."),
        ],
      ),
  ];
}
