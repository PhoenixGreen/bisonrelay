import 'package:bruig/components/text.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

// store_templates.dart edits the pages a shop renders.
//
// Here rather than in Writing, which is where this was argued down before
// and rightly: these are Go templates with loops and conditions in them, and
// the writing tools are built for prose -- a preview that drew
// {{range .Products}} as three words, a spellchecker on template syntax, and
// an element panel that cannot see any of it.
//
// A plain editor beside the shop is a different proposition. It is next to
// the thing it affects, it is plainly advanced, and a page that will not
// render is refused before it is written -- so the way to break a shop from
// here is to write something that renders and says the wrong thing, which is
// what Restore default pages is for.

class StoreTemplates extends StatefulWidget {
  final StoreModel store;
  const StoreTemplates({super.key, required this.store});

  @override
  State<StoreTemplates> createState() => _StoreTemplatesState();
}

class _StoreTemplatesState extends State<StoreTemplates> {
  StoreTemplate? editing;
  final body = TextEditingController();
  bool loading = false;
  bool saving = false;

  /// _saved is what the page said when it was opened, so the editor knows
  /// whether anything has been typed since.
  String _saved = "";

  bool get changed => editing != null && body.text != _saved;

  @override
  void initState() {
    super.initState();
    widget.store.loadTemplates();
  }

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> _open(StoreTemplate template) async {
    if (changed && !await _confirmDiscard()) return;
    setState(() => loading = true);
    try {
      var text = await widget.store.readTemplate(template.name);
      if (!mounted) return;
      setState(() {
        editing = template;
        body.text = text;
        _saved = text;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Leave without saving?"),
          content: Txt.M("${editing?.name} has been changed."),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Keep editing")),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Discard")),
          ],
        ),
      ) ??
      false;

  Future<void> _save() async {
    var template = editing;
    if (template == null || saving) return;
    var snackbar = SnackBarModel.of(context);
    setState(() => saving = true);
    try {
      await widget.store.writeTemplate(template.name, body.text);
      if (!mounted) return;
      setState(() => _saved = body.text);
      snackbar.success("${template.name} saved. The shop is serving it now.");
    } catch (exception) {
      // The shop refuses a page that will not render, so this is where a
      // typo is caught -- while the person who wrote it is still looking.
      snackbar.error("$exception");
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var templates = widget.store.templates;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Txt.L("The pages the shop renders"),
      const SizedBox(height: 6),
      const Txt.S(
          "The front, a product, the cart and the rest. These are templates: "
          "{{ }} is filled in when the page is served. A page that will not "
          "render is refused rather than saved.",
          color: TextColor.onSurfaceVariant),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var template in templates)
          OutlinedButton(
            onPressed: loading ? null : () => _open(template),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              visualDensity: VisualDensity.compact,
              backgroundColor: template.name == editing?.name
                  ? theme.colors.surfaceContainerHighest
                  : null,
            ),
            child: Txt.S(template.name),
          ),
      ]),
      if (editing != null) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Txt.M(editing!.name)),
          if (changed)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Txt.S("Not saved", color: TextColor.onSurfaceVariant),
            ),
          FilledButton(
            onPressed: !changed || saving ? null : _save,
            child: Txt.S(saving ? "Saving…" : "Save"),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: body,
          maxLines: 20,
          minLines: 10,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: "RobotoMono", fontSize: 12),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ],
    ]);
  }
}
