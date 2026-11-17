import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/glb_info.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// model_picking.dart puts a 3D object in the library: a .glb from a file or
// a stock site, kept in the model store with the animations it brings --
// see glbAnimations -- under the 3D objects.

/// ModelAdded is a 3D object stored, or why it was not.
typedef ModelAdded = ({String? id, String? problem});

/// addCanvasModel keeps the .glb at [filePath] as a 3D object called
/// [name]: its id, or what was wrong with it. A .gltf of several files is
/// not taken -- only a model that is one file can go with a canvas.
Future<ModelAdded> addCanvasModel(String filePath, String name,
    {String author = "",
    String license = "",
    String origin = "",
    String from = ""}) async {
  var file = File(filePath);
  if (await CanvasMedia.sniffExtension(filePath) != ".glb") {
    return (
      id: null,
      problem: "${path.basename(filePath)} is not a .glb model: a 3D object "
          "is kept as one file, with its pictures in it."
    );
  }
  var animations = glbAnimations(await file.readAsBytes());
  if (animations == null) {
    return (id: null, problem: "${path.basename(filePath)} could not be read.");
  }
  var id = await CanvasMedia.saveFile(MediaKind.model, filePath);
  if (id == null) {
    return (
      id: null,
      problem: "${path.basename(filePath)} is too large for a canvas."
    );
  }
  await CanvasLibrary.addModel(id, name, animations,
      author: author, license: license, origin: origin, from: from);
  return (id: id, problem: null);
}

/// pickCanvasModel asks for a .glb and keeps it: its id, or null.
Future<String?> pickCanvasModel(BuildContext context) async {
  var picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ["glb"],
    withData: false,
  );
  var chosen = picked?.files.singleOrNull?.path?.trim();
  if (chosen == null || chosen.isEmpty) return null;
  var added =
      await addCanvasModel(chosen, path.basenameWithoutExtension(chosen));
  if (added.problem case var problem? when context.mounted) {
    try {
      SnackBarModel.of(context).error(problem);
    } catch (_) {
      debugPrint(problem);
    }
  }
  return added.id;
}
