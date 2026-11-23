import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/storage/writing_library.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// document_picking.dart is choosing a document from the Writing library. A
// list rather than a file dialog: a system picker would open deep in the
// application support folder, on .md files under their internal names.

/// pickTextDocument asks which Writing library document a text or a Speech
/// device should read its words from, and returns a reference to it -- or
/// null if the reader changed their mind.
Future<TextDocumentRef?> pickTextDocument(BuildContext context) async {
  var library = WritingLibrary.current;
  var entries = <TextDocumentRef>[];
  try {
    entries = await library.documents();
  } catch (_) {
    // An unreadable library is shown as an empty one, not as an error.
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
                  child: Text(
                      library.here
                          ? "There is nothing in the Writing library yet."
                          : "There is no Writing library here to read from.",
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
                      onTap: () => Navigator.of(context).pop(entry),
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
