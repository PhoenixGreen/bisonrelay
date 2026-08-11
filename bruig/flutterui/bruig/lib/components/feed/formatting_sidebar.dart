import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// formatting_sidebar.dart is the composer's formatting and content panel:
// the things that put something into the post rather than say something
// about it.
//
// Every entry works the same way -- take the selection, wrap or prefix it,
// put the caret somewhere useful -- so they are described as data and one
// routine applies them. Adding a new one is a line in a list.

/// _Snippet is one formatting action.
class _Snippet {
  final IconData icon;
  final String label;

  /// before and after wrap the selection. With nothing selected they still
  /// go in, with [placeholder] between them, selected so it can be typed
  /// straight over.
  final String before;
  final String after;
  final String placeholder;

  /// lineStart marks the action as a prefix on the line rather than a wrap:
  /// a heading, a quote, a list item. Applied to every line of a multi-line
  /// selection, since that is what somebody selecting three lines and
  /// pressing "list" means.
  final bool lineStart;

  /// block puts the snippet on its own lines, separated from what surrounds
  /// it -- a table dropped into the middle of a paragraph is not a table.
  final bool block;

  const _Snippet(
    this.icon,
    this.label,
    this.before, {
    this.after = "",
    this.placeholder = "",
    this.lineStart = false,
    this.block = false,
  });
}

const _headings = [
  _Snippet(Icons.title, "Heading 1", "# ",
      placeholder: "Heading", lineStart: true),
  _Snippet(Icons.title, "Heading 2", "## ",
      placeholder: "Heading", lineStart: true),
  _Snippet(Icons.title, "Heading 3", "### ",
      placeholder: "Heading", lineStart: true),
];

const _inline = [
  _Snippet(Icons.format_bold, "Bold", "**", after: "**", placeholder: "bold"),
  _Snippet(Icons.format_italic, "Italic", "_",
      after: "_", placeholder: "italic"),
  _Snippet(Icons.strikethrough_s, "Strikethrough", "~~",
      after: "~~", placeholder: "struck"),
  _Snippet(Icons.code, "Code", "`", after: "`", placeholder: "code"),
  _Snippet(Icons.link, "Link", "[", after: "](https://)", placeholder: "text"),
];

const _blocks = [
  _Snippet(Icons.format_list_bulleted, "Bulleted list", "- ",
      placeholder: "item", lineStart: true),
  _Snippet(Icons.format_list_numbered, "Numbered list", "1. ",
      placeholder: "item", lineStart: true),
  _Snippet(Icons.format_quote, "Quote", "> ",
      placeholder: "quoted", lineStart: true),
  _Snippet(Icons.data_array, "Code block", "```\n",
      after: "\n```", placeholder: "code", block: true),
  _Snippet(Icons.horizontal_rule, "Divider", "---", block: true),
  _Snippet(
    Icons.table_chart_outlined,
    "Table",
    "| Column | Column |\n| --- | --- |\n| ",
    after: " |  |",
    placeholder: "cell",
    block: true,
  ),
  // A callout and a card are the same thing with a different amount filled
  // in, so one syntax writes both. Every field is optional -- a callout with
  // only a title and some text is a card with two fields.
  _Snippet(
    Icons.info_outline,
    "Callout",
    "--card--\nicon: info\ntitle: ",
    after: "\ntext: What it says.\n--/card--",
    placeholder: "Something worth knowing",
    block: true,
  ),
  _Snippet(
    Icons.credit_card_outlined,
    "Cards",
    "--cards[2]--\n--card--\nicon: announce\ntitle: ",
    after: "\ntext: What this one says.\nbutton: Read more\n"
        "link: https://\n--/card--\n--card--\nicon: star\n"
        "title: Second card\ntext: What that one says.\n--/card--\n"
        "--/cards--",
    placeholder: "First card",
    block: true,
  ),
  // Columns have no Markdown of their own either, and unlike a callout there
  // is nothing to borrow -- so they are Bison Relay's own block syntax, in
  // the shape the app already uses for what Markdown has no word for.
  //
  // The count in the marker means "divide this between that many", so the
  // selection is simply wrapped and the writing is shared out between the
  // columns rather than all of it landing in the first one beside an empty
  // second. A break can still be forced by hand -- that is what the button
  // below these two puts in.
  _Snippet(
    Icons.view_column_outlined,
    "Two columns",
    "--columns[2]--\n",
    after: "\n--/columns--",
    placeholder: "Your text",
    block: true,
  ),
  _Snippet(
    Icons.view_week_outlined,
    "Three columns",
    "--columns[3]--\n",
    after: "\n--/columns--",
    placeholder: "Your text",
    block: true,
  ),
  _Snippet(Icons.splitscreen_outlined, "Column break", "--col--", block: true),
];

/// FormattingSidebar offers embeds and Markdown, applied to the composer the
/// controller is attached to.
class FormattingSidebar extends StatelessWidget {
  final ComposerSidebarController controller;
  const FormattingSidebar({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    // Rebuilt with the controller, so switching between Raw and Preview
    // reaches the buttons below and not only the toggle itself.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Nothing to insert into while the post is being read rather than
        // written: the snippets edit the markdown, and in Preview the
        // markdown is not on screen. Left visible and disabled rather than
        // taken away, so the panel does not change shape under the pointer.
        var editor = controller.preview ? null : controller.editor;

        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
          children: [
            _section(theme, "Content"),
            // Delegated to the composer: picking a file means tracking an
            // embed and re-estimating the post's size, which is its
            // business.
            _wide(
              theme,
              Icons.attach_file,
              "Add Embed",
              controller.preview ? null : controller.onAddEmbed,
            ),
            _section(theme, "Headings"),
            _grid(theme, editor, _headings),
            _section(theme, "Text"),
            _grid(theme, editor, _inline),
            _section(theme, "Blocks"),
            _grid(theme, editor, _blocks),
          ],
        );
      },
    );
  }

  Widget _section(ThemeNotifier theme, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colors.onSurfaceVariant)),
      );

  Widget _grid(ThemeNotifier theme, TextEditingController? editor,
          List<_Snippet> snippets) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var snippet in snippets)
            Tooltip(
              message: snippet.label,
              child: OutlinedButton(
                onPressed:
                    editor == null ? null : () => _apply(editor, snippet),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  visualDensity: VisualDensity.compact,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(snippet.icon, size: 15),
                  // The heading buttons share an icon, so the level has to
                  // be on the face of the button rather than in a tooltip
                  // nobody hovers for.
                  if (snippet.label.startsWith("Heading"))
                    Text(snippet.label.split(" ").last,
                        style: const TextStyle(fontSize: 11)),
                ]),
              ),
            ),
        ],
      );

  Widget _wide(ThemeNotifier theme, IconData icon, String label,
          VoidCallback? onTap) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );

  /// _apply inserts a snippet around the selection.
  ///
  /// Everything here is done through the controller's value rather than by
  /// rewriting text and hoping: the caret has to end up somewhere the writer
  /// can carry on from, which for an empty snippet means selecting the
  /// placeholder so the next keystroke replaces it.
  static void _apply(TextEditingController editor, _Snippet snippet) {
    var value = editor.value;
    var selection = value.selection;
    var start = selection.isValid ? selection.start : value.text.length;
    var end = selection.isValid ? selection.end : value.text.length;
    var selected = value.text.substring(start, end);

    if (snippet.lineStart) {
      _applyLinePrefix(editor, snippet, start, end, selected);
      return;
    }

    var body = selected.isEmpty ? snippet.placeholder : selected;
    var core = "${snippet.before}$body${snippet.after}";

    var before = value.text.substring(0, start);
    var after = value.text.substring(end);

    // A block is separated from what surrounds it, without piling up blank
    // lines where there already are some.
    var lead = "";
    var tail = "";
    if (snippet.block) {
      lead = before.isEmpty || before.endsWith("\n\n")
          ? ""
          : (before.endsWith("\n") ? "\n" : "\n\n");
      tail = after.isEmpty || after.startsWith("\n") ? "" : "\n";
    }

    var bodyStart = before.length + lead.length + snippet.before.length;
    editor.value = TextEditingValue(
      text: "$before$lead$core$tail$after",
      // The body is selected rather than the caret merely placed, so the
      // next keystroke replaces the placeholder -- and so a real selection
      // stays highlighted after being wrapped.
      selection: body.isEmpty
          ? TextSelection.collapsed(offset: bodyStart)
          : TextSelection(
              baseOffset: bodyStart, extentOffset: bodyStart + body.length),
    );
  }

  /// _applyLinePrefix puts the prefix on every line the selection touches.
  static void _applyLinePrefix(TextEditingController editor, _Snippet snippet,
      int start, int end, String selected) {
    var text = editor.text;
    var lineStart = text.lastIndexOf("\n", start > 0 ? start - 1 : 0) + 1;
    var lineEnd = text.indexOf("\n", end);
    if (lineEnd < 0) lineEnd = text.length;

    var lines = text.substring(lineStart, lineEnd).split("\n");
    var prefixed = [
      for (var line in lines)
        // Already prefixed: left alone rather than doubled, so pressing the
        // same button twice is not a way to write "## ## ".
        line.startsWith(snippet.before)
            ? line
            : "${snippet.before}${line.isEmpty ? snippet.placeholder : line}",
    ].join("\n");

    var updated = text.replaceRange(lineStart, lineEnd, prefixed);
    editor.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: lineStart + prefixed.length),
    );
  }
}
