import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

// model_picking.dart brings a 3D character in from a file: read first, so
// what is not a model is turned away rather than kept, then stored with the
// models and listed in the library's Models.

/// modelExtensions is the files a model can be picked from.
const List<String> modelExtensions = ["glb", "gltf", "vrm"];

/// StoredModel is a model brought in: its stored id, its name, and the
/// file as read.
typedef StoredModel = ({String id, String name, Gltf gltf});

/// storeModel reads the model at [file], stores it, and adds it to the
/// library. Throws a GltfError, with a message fit to show, for a file it
/// cannot read or keep.
Future<StoredModel> storeModel(String file) async {
  Gltf gltf;
  try {
    gltf = parseGltf(await File(file).readAsBytes());
  } on FormatException {
    throw const GltfError("It is not a glTF, GLB or VRM file.");
  } on FileSystemException {
    throw const GltfError("The file could not be opened.");
  }
  var id = await CanvasMedia.saveFile(MediaKind.model, file);
  if (id == null) {
    throw GltfError("It could not be stored: it may be bigger than "
        "${MediaKind.model.maxBytes >> 20} MB.");
  }
  var name = gltf.title.isNotEmpty
      ? gltf.title
      : path.basenameWithoutExtension(file);
  await CanvasLibrary.add(LibraryAsset(
      id: id, kind: AssetKind.model, name: name, added: DateTime.now()));
  return (id: id, name: name, gltf: gltf);
}

/// pickCanvasModel asks for a model file and brings it in, saying so where
/// it cannot.
Future<StoredModel?> pickCanvasModel(BuildContext context) async {
  var picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: modelExtensions,
    withData: false,
  );
  var file = picked?.files.singleOrNull?.path;
  if (file == null || file.trim().isEmpty) return null;
  try {
    return await storeModel(file.trim());
  } on GltfError catch (error) {
    debugPrint("Unable to bring in ${path.basename(file)}: $error");
    if (context.mounted) {
      try {
        SnackBarModel.of(context)
            .error("${path.basename(file)} could not be brought in: $error");
      } catch (_) {}
    }
    return null;
  }
}
