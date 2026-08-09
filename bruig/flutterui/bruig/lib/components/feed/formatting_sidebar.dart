import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
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
  // A callout has no Markdown of its own; a blockquote opening with a bold
  // word is how every renderer that lacks the extension still shows one
  // sensibly, and Bison Relay's does.
  _Snippet(Icons.info_outline, "Callout", "> **Note** \n> ",
      placeholder: "text", block: true),
];

/// FormattingSidebar offers embeds and Markdown, applied to the composer the
/// controller is attached to.
class FormattingSidebar extends StatelessWidget {
  final ComposerSidebarController controller;
  const FormattingSidebar({required this.controller, super.key});

  /// _viewToggle chooses between the source and the rendering of it.
  ///
  /// Two buttons rather than a switch, because neither state is the
  /// "on" one -- raw and preview are both ways of looking at the post, and a
  /// switch would have to be labelled with only one of them.
  Widget _viewToggle(ThemeNotifier theme) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text("Raw"),
                  icon: Icon(Icons.code, size: 16)),
              ButtonSegment(
                  value: true,
                  label: Text("Preview"),
                  icon: Icon(Icons.visibility_outlined, size: 16)),
            ],
            selected: {controller.preview},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
            ),
            onSelectionChanged: (chosen) => controller.preview = chosen.first,
          ),
        ),
      );

  /// _guidePicker chooses the style guide the post is written in.
  ///
  /// The choice goes with the post, not with this sidebar: it is what the
  /// post will carry when it is published, and a reader who has that guide
  /// sees the post as it was written. One who does not falls back to their
  /// own, which is why only the built-ins are offered here -- they are the
  /// ones every device has.
  Widget _guidePicker(BuildContext context) {
    var post = controller.post;
    if (post == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DropdownButton<String>(
        value: builtInGuideFor(post.styleGuideId) == null
            ? defaultGuideId
            : post.styleGuideId,
        isExpanded: true,
        style: const TextStyle(fontSize: 12),
        items: [
          for (var guide in builtInGuides)
            DropdownMenuItem(value: guide.id, child: Text(guide.name)),
        ],
        onChanged: (v) {
          if (v == null) return;
          post.styleGuideId = v;
          // The field paints from the guide, so it has to be told to
          // repaint -- nothing about the text itself has changed.
          controller.notifyStyleChanged();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var editor = controller.editor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
      children: [
        _section(theme, "View"),
        _viewToggle(theme),
        _section(theme, "Style guide"),
        _guidePicker(context),
        _section(theme, "Content"),
        // Delegated to the composer: picking a file means tracking an embed
        // and re-estimating the post's size, which is its business.
        _wide(
          theme,
          Icons.attach_file,
          "Add Embed",
          controller.onAddEmbed,
        ),
        _section(theme, "Headings"),
        _grid(theme, editor, _headings),
        _section(theme, "Text"),
        _grid(theme, editor, _inline),
        _section(theme, "Blocks"),
        _grid(theme, editor, _blocks),
      ],
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
