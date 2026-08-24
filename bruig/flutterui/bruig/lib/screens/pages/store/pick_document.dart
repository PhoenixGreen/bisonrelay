import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/models/store_goods.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:flutter/material.dart';

// pick_document.dart offers the writing library as the file a product sends.
//
// A guide, a course, a set of notes -- the things somebody would actually
// sell as a download are the things they were already writing in Writing.
// Before this the only way to sell one was to find where the library keeps
// its files and type the path in by hand.

/// pickLibraryDocument asks which document, and publishes it.
///
/// Returns the name the product records, or null if nothing was chosen. The
/// document stays in the library: this writes the copy the shop sends, and
/// editing the document afterwards changes nothing until it is published
/// again -- the same bargain a page makes.
Future<String?> pickLibraryDocument(BuildContext context) async {
  var folders = await PostStorage.allFolderNames();
  if (!context.mounted) return null;

  var documents = <({String folder, String name})>[];
  for (var folder in ["", ...folders]) {
    for (var entry in await PostStorage.list(folder)) {
      if (!entry.isFolder) documents.add((folder: folder, name: entry.name));
    }
  }
  if (!context.mounted) return null;

  if (documents.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nothing written yet"),
        content: const Txt.M(
            "Write the document in Writing first, then come back and it "
            "will be here."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close")),
        ],
      ),
    );
    return null;
  }

  var chosen = await showDialog<({String folder, String name})>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text("Which document?"),
      children: [
        for (var doc in documents)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(doc),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Txt.M(doc.name)),
              if (doc.folder.isNotEmpty)
                Txt.S(folderLabel(doc.folder),
                    color: TextColor.onSurfaceVariant),
            ]),
          ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return null;

  var published = await StoreGoods.publish(chosen.folder, chosen.name);
  return published.recorded;
}
