import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// document_picking.dart is choosing a document from the Writing library.
//
// A list rather than a file dialog: these are the user's own documents in the
// app's own library, and a system file picker would open on some folder deep
// in the application support directory with the .md files sitting in it under
// their internal names.

/// pickLibraryDocument asks which document a text element should read, and
/// returns a reference to it -- or null if the reader changed their mind.
Future<TextDocumentRef?> pickLibraryDocument(BuildContext context) async {
  // The library is one level deep: the documents at the top, and then the
  // documents in each folder. See PostStorage.list.
  var entries = <PostEntry>[];
  try {
    for (var entry in await PostStorage.list()) {
      if (!entry.isFolder) {
        entries.add(entry);
        continue;
      }
      for (var inside in await PostStorage.list(entry.name)) {
        if (!inside.isFolder) entries.add(inside);
      }
    }
  } catch (_) {
    // An unreadable library is an empty one here: the dialog says there is
    // nothing to choose and the reader is no worse off than with an error.
  }

  if (!context.mounted) return null;
  return showDialog<TextDocumentRef>(
    context: context,
    builder: (context) {
      var theme = ThemeNotifier.of(context);
      return AlertDialog(
        backgroundColor: theme.colors.surface,
        title: const Text("Choose a document", style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 360,
          height: 380,
          child: entries.isEmpty
              ? Center(
                  child: Text("There is nothing in the Writing library yet.",
                      style: TextStyle(
                          fontSize: 12, color: theme.colors.onSurfaceVariant)))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    var entry = entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.description_outlined,
                          size: 16, color: theme.colors.onSurfaceVariant),
                      title: Text(entry.name,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: entry.folder.isEmpty
                          ? null
                          : Text(entry.folder,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colors.onSurfaceVariant)),
                      onTap: () => Navigator.of(context).pop(TextDocumentRef(
                          folder: entry.folder, name: entry.name)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
        ],
      );
    },
  );
}
