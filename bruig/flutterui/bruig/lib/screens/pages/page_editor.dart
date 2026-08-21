import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// page_editor.dart is the editor My Site falls back to.
//
// It exists for running without the writing tools. With them on, New and Edit
// go to the Writing page instead -- see MySiteTab.openInWriting -- which is
// the app's place for writing and has the formatting panel and the checks
// beside it.

/// PageEditor writes one markdown file. A name of "" is a new page.
class PageEditor extends StatefulWidget {
  final PagesModel pages;
  final VoidCallback onDone;
  const PageEditor({super.key, required this.pages, required this.onDone});

  @override
  State<PageEditor> createState() => PageEditorState();
}

class PageEditorState extends State<PageEditor> {
  final nameCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();
  bool saving = false;

  PageDraft get draft => widget.pages.pageDraft ?? const PageDraft(editing: "");
  bool get isNew => draft.isNew;

  @override
  void initState() {
    super.initState();
    // Whatever was typed before, which is there when coming back to a draft
    // left open. The boxes are the draft's, not the file's.
    nameCtrl.text = draft.name;
    bodyCtrl.text = draft.body;
    nameCtrl.addListener(remember);
    bodyCtrl.addListener(remember);
    if (!draft.loaded) load();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    bodyCtrl.dispose();
    super.dispose();
  }

  /// remember hands what is in the boxes to the model, which outlives this
  /// screen. Deliberately not notifying -- see PagesModel's draft section.
  void remember() => widget.pages.updatePageDraft(
      draft.copyWith(name: nameCtrl.text, body: bodyCtrl.text));

  void load() async {
    var name = draft.editing;
    try {
      // The document is what is edited. A page that is only being served --
      // written before any of this existed -- is brought into the library
      // first, so there is always a document behind the editor.
      await PageDocuments.adopt(
          widget.pages, PageDocuments.forName(widget.pages, name));
      var content =
          await PostStorage.read(pagesFolderName, documentNameFor(name)) ?? "";
      if (!mounted) return;
      bodyCtrl.text = content;
    } catch (exception) {
      if (mounted) {
        SnackBarModel.of(context).error("Unable to read page: $exception");
      }
    }
    if (!mounted) return;
    // Marked loaded either way: a page that could not be read is not going
    // to read on the second attempt either, and retrying on every rebuild
    // would overwrite whatever was typed in the meantime.
    widget.pages.updatePageDraft(draft.copyWith(loaded: true));
    setState(() {});
  }

  /// save writes the document. It does not publish: what visitors are
  /// reading only changes when somebody says so.
  ///
  void save() async {
    var snackbar = SnackBarModel.of(context);
    var name = nameCtrl.text.trim();
    if (name.isEmpty) {
      snackbar.error("The page needs a name.");
      return;
    }
    var doc = documentNameFor(name);

    setState(() => saving = true);
    try {
      await PostStorage.write(pagesFolderName, doc, bodyCtrl.text);

      // Renaming through the name field leaves the old one behind, so drop
      // it -- both the document and anything published under it -- once the
      // new one is safely written.
      var wasPublished = false;
      if (!isNew && doc != documentNameFor(draft.editing)) {
        var old = PageDocuments.forName(widget.pages, draft.editing);
        wasPublished = old.state.live;
        if (wasPublished) {
          await PageDocuments.unpublish(widget.pages, old);
        }
        var entry =
            PostEntry(name: old.name, folder: pagesFolderName, isFolder: false);
        await PostStorage.delete(entry);
      }

      // A rename of something that was published republishes under the new
      // name, or renaming a live page would silently take it down.
      if (wasPublished) {
        await PageDocuments.publish(
            widget.pages, PageDocuments.forName(widget.pages, doc));
      }
      widget.onDone();
    } catch (exception) {
      snackbar.error("Unable to save page: $exception");
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!draft.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: "Back to pages",
            onPressed: widget.onDone,
          ),
          Expanded(child: Txt.L(isNew ? "New page" : draft.editing)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            isDense: true,
            labelText: "File name",
            helperText: "index.md is the page visitors land on",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: bodyCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              labelText: "Markdown",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // One button. Saving keeps the writing; publishing is done from the
        // list this returns to, where the page's state is shown beside it --
        // so there is one place a page is published from rather than two
        // that have to agree.
        Row(children: [
          ElevatedButton(
            style: raisedButtonStyle(ThemeNotifier.of(context)),
            onPressed: saving ? null : () => save(),
            child: Text(saving ? "Saving…" : "Save"),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: widget.onDone, child: const Text("Cancel")),
        ]),
      ]),
    );
  }
}
