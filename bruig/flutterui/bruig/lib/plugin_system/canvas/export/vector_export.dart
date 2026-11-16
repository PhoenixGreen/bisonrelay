import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';
import 'package:bruig/plugin_system/canvas/export/vector_writers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';

// vector_export.dart is a chart or a table saved as an SVG or a PDF that
// stays sharp at any size and keeps its words as words (Ken, 2026-11-17,
// the improvements report's vector export): drawn as it finally stands --
// arrived, every step's words as the chart shows now -- by its own painter
// onto a VectorCanvas.

/// VectorFormat is what it is saved as.
enum VectorFormat {
  svg("SVG", "svg"),
  pdf("PDF", "pdf");

  final String label, extension;
  const VectorFormat(this.label, this.extension);
}

/// vectorOf is [e] drawn as [format]; null for an element that is neither
/// a chart nor a table.
Future<Uint8List?> vectorOf(CanvasElement e, VectorFormat format,
    {CanvasImageSource? images, Color? ground}) async {
  var size = Size(e.width, e.height);
  if (size.isEmpty) return null;
  var v = VectorCanvas(size);
  try {
    var rect = Offset.zero & size;
    // The canvas behind it, where it has no ground of its own: its words
    // were set to read on that.
    if (ground != null && ground.a > 0) {
      v.drawRect(rect, Paint()..color = ground);
    }
    switch (e) {
      case ChartElement c:
        paintChart(v, rect, c);
      case TableElement t:
        paintTable(v, rect, t, images: images);
      default:
        return null;
    }
    return switch (format) {
      VectorFormat.svg => utf8.encode(await vectorSvg(v)),
      VectorFormat.pdf => await vectorPdf(v),
    };
  } finally {
    v.dispose();
  }
}

/// saveVector asks where to save [e] as [format], and saves it there.
Future<void> saveVector(
    BuildContext context, CanvasElement e, VectorFormat format,
    {CanvasImageSource? images, Color? ground}) async {
  var snack = SnackBarModel.of(context);
  var name = (e.name.isEmpty ? e.kind.label : e.name)
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), "-");
  var path = await FilePicker.platform.saveFile(
    dialogTitle: "Save ${e.name.isEmpty ? "it" : e.name} as ${format.label}",
    fileName: "$name.${format.extension}",
    type: FileType.custom,
    allowedExtensions: [format.extension],
  );
  if (path == null) return;
  try {
    var bytes = await vectorOf(e, format, images: images, ground: ground);
    if (bytes == null) return;
    await File(path).writeAsBytes(bytes);
    snack.success("Saved ${path.split(Platform.pathSeparator).last}.");
  } catch (err) {
    snack.error("It couldn't be saved: $err");
  }
}
