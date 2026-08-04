import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:bruig/plugin_system/capabilities/thesaurus.dart';
import 'package:bruig/plugin_system/capabilities/thesaurus_menu.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// writing_panel.dart lists everything the writing capabilities have to say
// about a whole message at once, for the post editor -- where there is room
// for it and where people write at length.
//
// The chat composer deliberately has no equivalent: it is a bottom bar a few
// lines tall, and a panel there would take the room the message needs. It
// gets the same capabilities through the selection toolbar instead (see
// thesaurus_menu.dart), which costs no space at all.
//
// The panel is built from the capabilities, not from any plugin: with none
// enabled it renders nothing and the editor around it is unchanged.

/// WritingPanel reviews [controller]'s text and lists what it finds, letting
/// each fix be applied in place.
///
/// It collapses to nothing when no provider is enabled, so an editor can
/// include it unconditionally.
class WritingPanel extends StatefulWidget {
  final TextEditingController controller;

  /// maxHeight bounds the list, since a long post can produce a lot of
  /// issues and the panel must not push the editor off screen.
  final double maxHeight;

  const WritingPanel({
    required this.controller,
    this.maxHeight = 220,
    super.key,
  });

  @override
  State<WritingPanel> createState() => _WritingPanelState();
}

class _WritingPanelState extends State<WritingPanel> {
  // _expanded starts false: the panel is a tool you reach for, not a running
  // commentary on what you are typing. The inline underlines already carry
  // the live feedback.
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // Only while open: reviewing text nobody is looking at is pure cost, and
    // this fires on every keystroke.
    if (_expanded && mounted) setState(() {});
  }

  /// _apply replaces one issue's span with [replacement].
  ///
  /// The controller's text is re-read here rather than captured when the
  /// list was built: the panel is live, and a fix applied after an edit
  /// elsewhere in the message would otherwise splice at a stale offset.
  /// Ranges that no longer fit the text are dropped rather than forced.
  void _apply(WritingIssue issue, String replacement) {
    var text = widget.controller.text;
    if (issue.range.end > text.length) return;
    if (text.substring(issue.range.start, issue.range.end) != issue.text) {
      return;
    }
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(issue.range.start, issue.range.end, replacement),
      selection: TextSelection.collapsed(
          offset: issue.range.start + replacement.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    var spellcheck = context.watch<SpellcheckCapability>();
    var thesaurus = context.read<ThesaurusCapability?>();
    var hasSpellcheck = spellcheck.configuration != null;
    var hasThesaurus = thesaurus?.available ?? false;

    // Nothing to offer: render nothing at all, rather than an empty box.
    if (!hasSpellcheck && !hasThesaurus) return const SizedBox.shrink();

    var issues = _expanded && hasSpellcheck
        ? spellcheck.review(widget.controller.text)
        : const <WritingIssue>[];
    var theme = ThemeNotifier.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, theme, hasSpellcheck, issues.length),
        if (_expanded)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: _body(context, theme, issues, hasSpellcheck, hasThesaurus),
          ),
      ],
    );
  }

  Widget _header(BuildContext context, ThemeNotifier theme, bool hasSpellcheck,
      int issueCount) {
    // The count is only meaningful once the panel has actually reviewed the
    // text, which it only does while open.
    var label = !_expanded
        ? "Writing suggestions"
        : hasSpellcheck
            ? (issueCount == 0
                ? "Writing suggestions -- nothing to flag"
                : "Writing suggestions -- $issueCount to review")
            : "Writing suggestions";
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(_expanded ? Icons.expand_less : Icons.expand_more,
              size: 18, color: theme.colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: theme.colors.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, ThemeNotifier theme,
      List<WritingIssue> issues, bool hasSpellcheck, bool hasThesaurus) {
    return ListView(
      shrinkWrap: true,
      children: [
        if (hasSpellcheck && issues.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text("Nothing to flag in this post.",
                style: TextStyle(
                    fontSize: 13, color: theme.colors.onSurfaceVariant)),
          ),
        for (var issue in issues) _issueRow(theme, issue),
        if (hasThesaurus) _wordChoiceRow(context, theme),
      ],
    );
  }

  Widget _issueRow(ThemeNotifier theme, WritingIssue issue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          issue.kind == WritingIssueKind.spelling
              ? Icons.spellcheck
              : Icons.edit_note,
          size: 16,
          color: theme.colors.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: issue.text,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(
                text: "  ${issue.message}",
                style: TextStyle(
                    fontSize: 12, color: theme.colors.onSurfaceVariant),
              ),
            ])),
            if (issue.suggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var suggestion in issue.suggestions)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(suggestion,
                          style: const TextStyle(fontSize: 12)),
                      onPressed: () => _apply(issue, suggestion),
                    ),
                ],
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  /// _wordChoiceRow is the thesaurus's entry point for a whole post: the
  /// selection toolbar reaches it a word at a time, but someone rereading a
  /// draft wants to ask about a word without hunting for it in the text.
  Widget _wordChoiceRow(BuildContext context, ThemeNotifier theme) {
    var selection = widget.controller.selection;
    var text = widget.controller.text;
    String? word;
    if (selection.isValid && !selection.isCollapsed) {
      word = ThesaurusCapability.normalizeWord(selection.textInside(text));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Icon(Icons.menu_book_outlined,
            size: 16, color: theme.colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: word == null
              ? Text("Select a word in the post to see alternatives.",
                  style: TextStyle(
                      fontSize: 12, color: theme.colors.onSurfaceVariant))
              : Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.search, size: 14),
                    label: Text('Alternatives for "$word"',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => _showFor(context, word!, selection),
                  ),
                ),
        ),
      ]),
    );
  }

  void _showFor(BuildContext context, String word, TextSelection selection) {
    var capability = context.read<ThesaurusCapability>();
    showThesaurusSheet(
      context,
      capability: capability,
      word: word,
      onReplace: (replacement) {
        var text = widget.controller.text;
        if (selection.end > text.length) return;
        widget.controller.value = TextEditingValue(
          text: text.replaceRange(selection.start, selection.end, replacement),
          selection: TextSelection.collapsed(
              offset: selection.start + replacement.length),
        );
      },
    );
  }
}
