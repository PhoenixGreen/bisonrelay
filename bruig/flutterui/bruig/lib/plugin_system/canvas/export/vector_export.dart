import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';
import 'package:bruig/plugin_system/canvas/export/vector_writers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/painting.dart';

// vector_export.dart saves a chart or a table as an SVG or a PDF that stays
// sharp at any size and keeps its words as words. It is drawn as it finally
// stands, every step arrived, by its own painter onto a VectorCanvas.

/// VectorFormat is the file format it is saved as.
enum VectorFormat {
  svg("SVG", "svg"),
  pdf("PDF", "pdf");

  final String label, extension;
  const VectorFormat(this.label, this.extension);
}

/// vectorOf is [e] drawn as [format]; null unless a chart or a table.
Future<Uint8List?> vectorOf(CanvasElement e, VectorFormat format,
    {CanvasImageSource? images, Color? ground}) async {
  var size = Size(e.width, e.height);
  if (size.isEmpty) return null;
  var v = VectorCanvas(size);
  try {
    var rect = Offset.zero & size;
    // The canvas behind it, without its own ground: its words suit that.
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
