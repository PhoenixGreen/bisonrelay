import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/vector_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';

// vector_saving.dart is the Data Studio's "Save it" as SVG or PDF: where to
// save asked, the file written by export/vector_export.dart.

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
