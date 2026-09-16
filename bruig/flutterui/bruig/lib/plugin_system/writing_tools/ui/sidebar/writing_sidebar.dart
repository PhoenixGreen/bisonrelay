import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:bruig/plugin_system/writing_tools/spellcheck_capability.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/composer_edits.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/document_page.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/issue_list_page.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/sidebar_chips.dart';
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
// The four are a column of panels that open, shut, resize and change places,
// the same one the canvas's design sidebar is -- see PanelStack. They were a
// row of four tabs, which is a shape with one thing wrong with it: the four
// answer different questions and are wanted at different moments, but two of
// them are wanted at the *same* moment. Mistakes are read while finishing a
// draft and the thesaurus is consulted a word at a time while writing, and a
// tab is a place you have to leave to reach another.
//
// Panels also mean the arrangement belongs to the reader. Somebody who never
// looks at the counts shuts that panel once; somebody who lives in the
// thesaurus drags it to the top. Which are open, how tall each is and what
// order they come in are all written down and come back next time.
//
// This file is only the shell: it watches the composer and decides what each
// panel is handed. The panels themselves are the four files beside it, and
// adding a fifth is a value on the enum below and one entry in _panels.

/// WritingSidebarPage is one of the sidebar's four views.
enum WritingSidebarPage {
  /// What is wrong: misspellings and the grammar rules, which are the two
  /// things worth fixing before sending.
  mistakes(Icons.spellcheck, "Spelling & grammar", "Spelling"),

  /// What could be better: wordiness, cliches, the passive voice, a word used
  /// four times in a paragraph. Opinions, kept away from the mistakes so the
  /// list of things that are actually wrong stays short.
  ///
  /// Called "Suggestions and Checks" rather than "Phrasing", which is what it
  /// held when it was only the style rules. It now also carries the checks
  /// that count -- repetition, sentence length, mixed spellings and
  /// apostrophes -- and none of those is phrasing, so a reader whose repeated
  /// word was not under "Phrasing" had no reason to look again. The name is
  /// also the distinction being drawn: every issue here comes from a rule the
  /// provider marked as a suggestion rather than an error, and saying so is
  /// what earns the page the right to be wrong occasionally. "Checks" is the
  /// half that invites a look -- a homophone the rules cannot decide is right
  /// or wrong is listed here to be checked, not corrected.
  ///
  /// The tab itself still says "Suggestions": the full title is a tooltip and
  /// a heading, and four tabs of that length do not fit the width this panel
  /// opens at.
  ///
  /// The enum value keeps its name, which matches WritingIssueKind.phrasing --
  /// the kind is still what decides which page an issue lands on.
  phrasing(Icons.auto_fix_high, "Suggestions and Checks", "Suggestions"),

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

  const WritingSidebar({required this.controller, super.key});

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
  late String _lastText;
  late TextSelection _lastSelection;

  @override
  void initState() {
    super.initState();
    // Read here rather than as a late initialiser on the fields.
    //
    // A late field is worked out when it is first touched, and the only thing
    // that touches these is _onChanged -- which runs *after* the text has
    // changed. So the first change initialised them to the text it was
    // reporting, compared it against itself, found no difference and dropped
    // the rebuild: the sidebar showed the post as it was when it opened until
    // something else happened to rebuild it. With four tabs, tapping one was
    // enough to hide it.
    _remember();
    _editor?.addListener(_onChanged);
  }

  /// _remember notes what the list was last built from.
  void _remember() {
    _lastText = _editor?.text ?? "";
    _lastSelection =
        _editor?.selection ?? const TextSelection.collapsed(offset: -1);
  }

  @override
  void didUpdateWidget(covariant WritingSidebar old) {
    super.didUpdateWidget(old);
    // The composer can be swapped underneath this -- a rebuild of the editor
    // hands over a new controller -- and the listener has to move with it.
    if (!identical(old.controller, widget.controller)) {
      old.controller?.removeListener(_onChanged);
      _editor?.addListener(_onChanged);
      _remember();
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

    var issues =
        prefs.enabled ? spellcheck.review(edits.text) : const <WritingIssue>[];
    var mistakes = issues.where((i) => i.kind.isMistake).toList();
    var phrasing = issues.where((i) => !i.kind.isMistake).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _onOff(theme, prefs),
      Divider(height: 1, color: theme.colors.outlineVariant),
      Expanded(
        child: PanelStack(
          storageKey: "writingTools",
          panels: _panels(theme, prefs, edits, mistakes, phrasing),
        ),
      ),
    ]);
  }

  /// _onOff is the whole feature's switch, on a line of its own above the
  /// panels.
  ///
  /// It used to sit on the end of the tab row, which is gone. A line of its
  /// own rather than a panel header's trailing corner: it governs all four
  /// panels, and a control that lives on one of them looks like it belongs to
  /// that one. Turning the tools off from here is the obvious move when the
  /// marks are in the way, so it stays at the top where it was.
  Widget _onOff(ThemeNotifier theme, WritingPreferences prefs) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        child: Row(children: [
          Expanded(
            child: Text(
              "Writing tools",
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
                color: theme.colors.onSurfaceVariant,
              ),
            ),
          ),
          Tooltip(
            message: prefs.enabled ? "Turn writing tools off" : "Turn on",
            child: Transform.scale(
              // Material's switch is built for a settings row and is half
              // again the height of the line it sits in here.
              scale: 0.7,
              child: Switch(
                value: prefs.enabled,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => prefs.enabled = v,
              ),
            ),
          ),
        ]),
      );

  List<StackPanel> _panels(
    ThemeNotifier theme,
    WritingPreferences prefs,
    ComposerEdits edits,
    List<WritingIssue> mistakes,
    List<WritingIssue> phrasing,
  ) {
    /// off is what a panel shows when the writing tools are switched off for
    /// the session. The counts are the exception -- counting words needs no
    /// provider and no rules -- so they keep working.
    Widget guarded(Widget page) => prefs.enabled
        ? page
        : sidebarNote(theme, "Writing tools are off for this session.");

    // The count on the heading rather than only inside the list, so a shut
    // panel still says how much is behind it. Nothing rather than a nought:
    // a panel saying 0 invites a look at a list with nothing in it.
    String? count(int n) => n == 0 ? null : "$n";

    return [
      StackPanel(
        id: WritingSidebarPage.mistakes.name,
        label: WritingSidebarPage.mistakes.short,
        icon: WritingSidebarPage.mistakes.icon,
        trailing: count(mistakes.length),
        hint: "Misspellings and broken grammar: the things that are actually "
            "wrong, kept apart from the things that could merely be better.",
        body: guarded(IssueListPage(
            issues: mistakes,
            edits: edits,
            empty: "Nothing to fix in this post.")),
      ),
      StackPanel(
        id: WritingSidebarPage.phrasing.name,
        label: WritingSidebarPage.phrasing.short,
        icon: WritingSidebarPage.phrasing.icon,
        trailing: count(phrasing.length),
        hint: "Wordiness, cliches, the passive voice, a word used four times "
            "in a paragraph. Opinions, and a few things to check rather than "
            "correct.",
        body: guarded(IssueListPage(
            issues: phrasing,
            edits: edits,
            empty: "Nothing to suggest for this post.")),
      ),
      // Shut to begin with, both of them. The thesaurus has nothing to say
      // until a word is selected and the counts are read once, at the end --
      // so open they are two holes in a column the issue lists want the room
      // from. Once either has been opened by hand that is what comes back.
      StackPanel(
        id: WritingSidebarPage.thesaurus.name,
        label: WritingSidebarPage.thesaurus.short,
        icon: WritingSidebarPage.thesaurus.icon,
        hint: "What else could have been said. Select a word to look it up.",
        startsOpen: false,
        body: guarded(ThesaurusPage(edits: edits)),
      ),
      StackPanel(
        id: WritingSidebarPage.document.name,
        label: WritingSidebarPage.document.short,
        icon: WritingSidebarPage.document.icon,
        hint: "How much there is of it.",
        startsOpen: false,
        // Not guarded: counting words needs no provider and no rules, so it
        // keeps working when everything else is switched off.
        body: DocumentPage(text: edits.text),
      ),
    ];
  }
}
