import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:bruig/plugin_system/writing_tools/spellcheck_capability.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/composer_edits.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/document_page.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/issue_list_page.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/sidebar_chips.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/sidebar_tabs.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/thesaurus_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// writing_sidebar.dart is the post editor's writing tools, laid out as a
// sidebar rather than a strip under the text.
//
// A list of everything wrong with a post is a tall, narrow thing: it wants the
// height a column has and almost none of the width. Underneath the editor it
// competed with the text for vertical room and had to be capped; beside it, it
// can simply be as long as it needs to be, and the post keeps its full height.
//
// It is four pages behind an icon bar rather than one long column, because the
// four answer different questions and are wanted at different moments.
// Mistakes are read while finishing a draft; phrasing is read when the draft is
// already correct and could be better; the thesaurus is consulted a word at a
// time while writing; and the counts are checked once, at the end. Put end to
// end they made a column nobody would scroll to the bottom of, and the two that
// live below the fold are the two anyone would have to go looking for.
//
// This file is only the shell: it watches the composer, decides what each page
// is handed, and draws the tab row. The pages themselves are the four files
// beside it, and adding a fifth is a value on the enum below and one case in
// _body.

/// WritingSidebarPage is one of the sidebar's four views.
enum WritingSidebarPage {
  /// What is wrong: misspellings and the grammar rules, which are the two
  /// things worth fixing before sending.
  mistakes(Icons.spellcheck, "Spelling & grammar", "Spelling"),

  /// What could be better: wordiness, cliches, the passive voice, a word used
  /// four times in a paragraph. Opinions, kept away from the mistakes so the
  /// list of things that are actually wrong stays short.
  ///
  /// Called "Suggestions" rather than "Phrasing", which is what it held when
  /// it was only the style rules. It now also carries the checks that count --
  /// repetition, sentence length, mixed spellings and apostrophes -- and none
  /// of those is phrasing, so a reader whose repeated word was not under
  /// "Phrasing" had no reason to look again. "Suggestions" is also the name of
  /// the distinction being drawn: every issue here comes from a rule the
  /// provider marked as a suggestion rather than an error, and saying so is
  /// what earns the page the right to be wrong occasionally.
  ///
  /// The enum value keeps its name, which matches WritingIssueKind.phrasing --
  /// the kind is still what decides which page an issue lands on.
  phrasing(Icons.auto_fix_high, "Suggestions"),

  /// What else could have been said, and what the selected word means.
  thesaurus(Icons.menu_book_outlined, "Thesaurus"),

  /// How much there is of it.
  document(Icons.bar_chart, "Document", "Stats");

  final IconData icon;

  /// title names the page in full, for the tooltip and anywhere with room.
  final String title;

  /// short is what the tab itself says.
  ///
  /// A separate string rather than the title because "Spelling & grammar" is a
  /// description and not a tab: at the width this panel actually opens at,
  /// four of those cannot be shown at all, so the row fell back to icons
  /// almost always and the labels might as well not have existed.
  final String short;

  const WritingSidebarPage(this.icon, this.title, [String? short])
      : short = short ?? title;
}

/// WritingSidebar lists every spelling and style issue in [controller]'s text,
/// each fixable in place, with the thesaurus for the current selection
/// alongside.
class WritingSidebar extends StatefulWidget {
  /// The composer under review, or null for the frame or two while one is
  /// being rebuilt -- see ComposerSidebarController.visible.
  final TextEditingController? controller;

  /// page is which of the four is showing, and onPageChanged asks for another.
  ///
  /// Held by the screen rather than in this widget's own State. In the
  /// collapsed drawer the sidebar is built from a stored builder and rebuilt
  /// from scratch whenever the drawer is told to redraw, so a selection kept
  /// here would be a selection the drawer could forget -- and the drawer is
  /// only ever told about things the screen knows it changed. Both problems go
  /// away when the screen owns it.
  final WritingSidebarPage page;
  final ValueChanged<WritingSidebarPage> onPageChanged;

  const WritingSidebar({
    required this.controller,
    this.page = WritingSidebarPage.mistakes,
    this.onPageChanged = _ignorePage,
    super.key,
  });

  /// A sidebar with nowhere to send the change simply does not move, which is
  /// the right behaviour for a caller that only wants one page.
  static void _ignorePage(WritingSidebarPage _) {}

  @override
  State<WritingSidebar> createState() => _WritingSidebarState();
}

class _WritingSidebarState extends State<WritingSidebar> {
  TextEditingController? get _editor => widget.controller;

  // _lastText is what the list was last built from. The controller notifies on
  // selection changes too, and rebuilding the whole list every time the caret
  // moves is both wasted work and -- while a context menu is open -- enough to
  // tear it down. Selection changes still matter for the thesaurus page, so
  // they rebuild too, but they are compared separately so a repaint that
  // changed neither is dropped.
  late String _lastText = _editor?.text ?? "";
  late TextSelection _lastSelection =
      _editor?.selection ?? const TextSelection.collapsed(offset: -1);

  @override
  void initState() {
    super.initState();
    _editor?.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant WritingSidebar old) {
    super.didUpdateWidget(old);
    // The composer can be swapped underneath this -- a rebuild of the editor
    // hands over a new controller -- and the listener has to move with it.
    if (!identical(old.controller, widget.controller)) {
      old.controller?.removeListener(_onChanged);
      _editor?.addListener(_onChanged);
      _lastText = _editor?.text ?? "";
      _lastSelection =
          _editor?.selection ?? const TextSelection.collapsed(offset: -1);
    }
  }

  @override
  void dispose() {
    _editor?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    var text = _editor?.text ?? "";
    var selection =
        _editor?.selection ?? const TextSelection.collapsed(offset: -1);
    if (text == _lastText && selection == _lastSelection) return;
    setState(() {
      _lastText = text;
      _lastSelection = selection;
    });
  }

  @override
  Widget build(BuildContext context) {
    var spellcheck = context.watch<SpellcheckCapability>();
    var prefs = context.watch<WritingPreferences>();
    var theme = ThemeNotifier.of(context);
    var edits = ComposerEdits(_editor);

    var issues = prefs.enabled
        ? spellcheck.review(edits.text)
        : const <WritingIssue>[];
    var mistakes = issues.where((i) => i.kind.isMistake).toList();
    var phrasing = issues.where((i) => !i.kind.isMistake).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SidebarTabs(
        current: widget.page,
        onChanged: widget.onPageChanged,
        prefs: prefs,
        counts: {
          WritingSidebarPage.mistakes: mistakes.length,
          WritingSidebarPage.phrasing: phrasing.length,
        },
      ),
      const Divider(height: 1),
      Expanded(child: _body(theme, prefs, edits, mistakes, phrasing)),
    ]);
  }

  Widget _body(
    ThemeNotifier theme,
    WritingPreferences prefs,
    ComposerEdits edits,
    List<WritingIssue> mistakes,
    List<WritingIssue> phrasing,
  ) {
    // The document page is the exception: counting words needs no provider and
    // no rules, so it keeps working when everything else is switched off.
    if (widget.page == WritingSidebarPage.document) {
      return DocumentPage(text: edits.text);
    }
    if (!prefs.enabled) {
      return sidebarNote(theme, "Writing tools are off for this session.");
    }
    switch (widget.page) {
      case WritingSidebarPage.mistakes:
        return IssueListPage(
            issues: mistakes,
            edits: edits,
            empty: "Nothing to fix in this post.");
      case WritingSidebarPage.phrasing:
        return IssueListPage(
            issues: phrasing,
            edits: edits,
            empty: "Nothing to suggest for this post.");
      case WritingSidebarPage.thesaurus:
        return ThesaurusPage(edits: edits);
      case WritingSidebarPage.document:
        return DocumentPage(text: edits.text);
    }
  }
}
