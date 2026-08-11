import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:bruig/plugin_system/capabilities/thesaurus.dart';
import 'package:bruig/plugin_system/capabilities/thesaurus_menu.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:bruig/plugin_system/capabilities/writing_analysis.dart';
import 'package:bruig/plugin_system/capabilities/writing_prefs.dart';
import 'package:bruig/plugin_system/capabilities/writing_stats.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// writing_sidebar.dart is the post editor's writing tools, laid out as a
// sidebar rather than a strip under the text.
//
// A list of everything wrong with a post is a tall, narrow thing: it wants
// the height a column has and almost none of the width. Underneath the
// editor it competed with the text for vertical room and had to be capped;
// beside it, it can simply be as long as it needs to be, and the post keeps
// its full height.
//
// It is four pages behind an icon bar rather than one long column, because
// the four answer different questions and are wanted at different moments.
// Mistakes are read while finishing a draft; phrasing is read when the draft
// is already correct and could be better; the thesaurus is consulted a word
// at a time while writing; and the counts are checked once, at the end. Put
// end to end they made a column nobody would scroll to the bottom of, and
// the two that live below the fold are the two anyone would have to go
// looking for.

/// WritingSidebar lists every spelling and style issue in [controller]'s
/// text, each fixable in place, with the thesaurus for the current
/// selection underneath.
class WritingSidebar extends StatefulWidget {
  /// The composer under review, or null for the frame or two while one is
  /// being rebuilt -- see ComposerSidebarController.visible.
  final TextEditingController? controller;

  /// page is which of the four is showing, and onPageChanged asks for
  /// another.
  ///
  /// Held by the screen rather than in this widget's own State. In the
  /// collapsed drawer the sidebar is built from a stored builder and rebuilt
  /// from scratch whenever the drawer is told to redraw, so a selection kept
  /// here would be a selection the drawer could forget -- and the drawer is
  /// only ever told about things the screen knows it changed. Both problems
  /// go away when the screen owns it.
  final WritingSidebarPage page;
  final ValueChanged<WritingSidebarPage> onPageChanged;

  const WritingSidebar({
    required this.controller,
    this.page = WritingSidebarPage.mistakes,
    this.onPageChanged = _ignorePage,
    super.key,
  });

  /// A sidebar with nowhere to send the change simply does not move, which
  /// is the right behaviour for a caller that only wants one page.
  static void _ignorePage(WritingSidebarPage _) {}

  @override
  State<WritingSidebar> createState() => _WritingSidebarState();
}

/// WritingSidebarPage is one of the sidebar's four views.
enum WritingSidebarPage {
  /// What is wrong: misspellings and the grammar rules, which are the two
  /// things worth fixing before sending.
  mistakes(Icons.spellcheck, "Spelling & grammar", "Spelling"),

  /// What could be better: wordiness, cliches, the passive voice, a word used
  /// four times in a paragraph. Opinions, kept away from the mistakes so the
  /// list of things that are actually wrong stays short.
  phrasing(Icons.auto_fix_high, "Phrasing"),

  /// What else could have been said, and what the selected word means.
  thesaurus(Icons.menu_book_outlined, "Thesaurus"),

  /// How much there is of it.
  document(Icons.bar_chart, "Document", "Stats");

  final IconData icon;

  /// title names the page in full, for the tooltip and anywhere with room.
  final String title;

  /// short is what the tab itself says.
  ///
  /// A separate string rather than the title because "Spelling & grammar" is
  /// a description and not a tab: at the width this panel actually opens at,
  /// four of those cannot be shown at all, so the row fell back to icons
  /// almost always and the labels might as well not have existed.
  final String short;

  const WritingSidebarPage(this.icon, this.title, [String? short])
      : short = short ?? title;
}

class _WritingSidebarState extends State<WritingSidebar> {
  TextEditingController? get _editor => widget.controller;

  // Owned rather than left implicit, so the Scrollbar and the view it tracks
  // are certainly the same one.
  final ScrollController _alternativesScroll = ScrollController();

  // _lastText is what the list was last built from. The controller notifies
  // on selection changes too, and rebuilding the whole list every time the
  // caret moves is both wasted work and -- while a context menu is open --
  // enough to tear it down. Selection changes still matter for the thesaurus
  // row, so they rebuild that alone.
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
    }
  }

  @override
  void dispose() {
    _editor?.removeListener(_onChanged);
    _alternativesScroll.dispose();
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

  /// _apply replaces one issue's span.
  ///
  /// The text is re-read here rather than taken from when the list was
  /// built: applying one fix shifts every later issue's offsets, and the
  /// list the user is looking at may already be one edit stale. A span whose
  /// text no longer matches is left alone rather than spliced blindly.
  void _apply(WritingIssue issue, String replacement) {
    var editor = _editor;
    if (editor == null) return;
    var text = editor.text;
    if (issue.range.end > text.length) return;
    if (text.substring(issue.range.start, issue.range.end) != issue.text) {
      return;
    }
    editor.value = TextEditingValue(
      text: text.replaceRange(issue.range.start, issue.range.end, replacement),
      selection: TextSelection.collapsed(
          offset: issue.range.start + replacement.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    var spellcheck = context.watch<SpellcheckCapability>();
    var prefs = context.watch<WritingPreferences>();
    var theme = ThemeNotifier.of(context);
    var issues = prefs.enabled ? spellcheck.review(_editor?.text ?? "") : null;

    var mistakes = issues?.where((i) => i.kind.isMistake).toList() ?? const [];
    var phrasing = issues?.where((i) => !i.kind.isMistake).toList() ?? const [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _nav(theme, prefs, {
        WritingSidebarPage.mistakes: mistakes.length,
        WritingSidebarPage.phrasing: phrasing.length,
      }),
      const Divider(height: 1),
      Expanded(child: _page(context, theme, prefs, mistakes, phrasing)),
    ]);
  }

  Widget _page(
    BuildContext context,
    ThemeNotifier theme,
    WritingPreferences prefs,
    List<WritingIssue> mistakes,
    List<WritingIssue> phrasing,
  ) {
    // The document page is the exception: counting words needs no provider
    // and no rules, so it keeps working when everything else is switched off.
    if (widget.page == WritingSidebarPage.document) {
      return _documentPage(theme);
    }
    if (!prefs.enabled) {
      return _note(theme, "Writing tools are off for this session.");
    }
    switch (widget.page) {
      case WritingSidebarPage.mistakes:
        return _issueList(theme, prefs, mistakes,
            empty: "Nothing to fix in this post.");
      case WritingSidebarPage.phrasing:
        return _issueList(theme, prefs, phrasing,
            empty: "Nothing to suggest for this post.");
      case WritingSidebarPage.thesaurus:
        return _thesaurusPage(context, theme);
      case WritingSidebarPage.document:
        return _documentPage(theme);
    }
  }

  Widget _issueList(
    ThemeNotifier theme,
    WritingPreferences prefs,
    List<WritingIssue> issues, {
    required String empty,
  }) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          if (issues.isEmpty) _note(theme, empty),
          for (var issue in issues) _issueRow(theme, prefs, issue),
        ],
      );

  /// _nav is the row of icons that switches pages, with the feature's own
  /// switch on the end of it.
  ///
  /// The page's name is not repeated above this row. The icons say which
  /// page is showing, and a title that only ever restates the selected icon
  /// is a line of the sidebar's height spent on nothing -- in a column where
  /// the height is what the content needs.
  ///
  /// The counts sit on the two pages that have them, because the reason to
  /// look at this row is usually to find out whether there is anything to
  /// look at -- and a page with nothing on it should say so before it is
  /// opened, not after.
  // The secondary nav is deliberately built from a different set of parts to
  // the icon row above it, because for a long time it was built from the same
  // ones: both drew the selected item as a filled secondaryContainer
  // rectangle, so two navigations one on top of the other were saying "this
  // is the current thing" in identical language, and neither read as
  // subordinate to the other.
  //
  // Here the selection is a line rather than a block. Nothing is filled, the
  // active tab is the accent colour with a rule under it, and the rule sits
  // flush on the divider that closes the row -- which is what makes four
  // labels read as tabs belonging to the panel below rather than as four more
  // buttons.
  // Taller than the content needs, and the extra is all above it. The shell
  // closes its icon row with a divider, and with no padding here the tab
  // icons sat directly on that rule with nothing between the two rows at all.
  //
  // The gap cannot be repeated underneath: the underline has to reach the
  // divider that closes this row, and any padding below it would leave the
  // indicator floating clear of the baseline it is meant to sit on. That
  // asymmetry is what a tab row is -- space above, attached below, because
  // the tab belongs to the panel beneath it rather than to the row above.
  static const double _tabRowHeight = 42;
  static const double _tabTopSpace = 8;
  static const double _tabIconSize = 15;
  static const double _tabLabelGap = 5;
  static const double _tabPadding = 6;

  /// _switchSpace is what the on/off control and its divider take out of the
  /// row, reserved before the tabs are measured against what is left.
  static const double _switchSpace = 58;

  Widget _nav(ThemeNotifier theme, WritingPreferences prefs,
      Map<WritingSidebarPage, int> counts) {
    var labelStyle = TextStyle(fontSize: 11.5, color: theme.colors.onSurface);
    return SizedBox(
      height: _tabRowHeight,
      child: LayoutBuilder(builder: (context, box) {
        var forTabs = box.maxWidth - _switchSpace - 12;
        var showLabels = _labelsFit(context, forTabs, labelStyle);
        return Padding(
          // No bottom padding: the tab underline has to land on the divider
          // beneath this row, and a gap between them reads as two unrelated
          // lines rather than one selected tab.
          padding: const EdgeInsets.fromLTRB(8, _tabTopSpace, 4, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var page in WritingSidebarPage.values)
              Expanded(
                child: _navButton(
                    theme, page, counts[page] ?? 0, showLabels, labelStyle),
              ),
            // The switch keeps its place beside the results it governs --
            // turning the tools off from here is the obvious move when the
            // marks are in the way -- but it is not one of the tabs, and
            // until this divider existed it sat in the row looking like one.
            Center(
              child: Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: theme.colors.outlineVariant,
              ),
            ),
            // Centred rather than stretched: the row sets a height for the
            // tabs, and a switch told to fill it overflows -- Transform.scale
            // changes what is drawn and not what is laid out, so the size has
            // to come off the switch itself.
            Center(
              child: Tooltip(
                message: prefs.enabled ? "Turn writing tools off" : "Turn on",
                child: Transform.scale(
                  // Material's switch is built for a settings row and is half
                  // again the height of the row it now sits in.
                  scale: 0.7,
                  child: Switch(
                    value: prefs.enabled,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => prefs.enabled = v,
                  ),
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }

  /// _labelsFit reports whether every tab can show its name across [width].
  ///
  /// Measured rather than assumed from a breakpoint. The panel is 260 wide by
  /// default and resizable well past that, the labels are words of very
  /// different lengths, and the text scale is the reader's to set -- so the
  /// question is genuinely "does this text fit in this space", and the only
  /// honest way to answer it is to lay the text out and look.
  bool _labelsFit(BuildContext context, double width, TextStyle style) {
    if (width <= 0) return false;
    var scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (var page in WritingSidebarPage.values) {
      var painter = TextPainter(
        text: TextSpan(text: page.short, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    var needed =
        widest + _tabIconSize + _tabLabelGap + _tabPadding * 2 + _countSpace;
    return width >= needed * WritingSidebarPage.values.length;
  }

  /// _countSpace is room for a two-digit count beside a label. Reserved
  /// whether or not there is one, so the tabs do not shuffle sideways as the
  /// numbers come and go while typing.
  static const double _countSpace = 18;

  Widget _navButton(ThemeNotifier theme, WritingSidebarPage page, int count,
      bool showLabel, TextStyle labelStyle) {
    var selected = page == widget.page;
    var accent = theme.colors.primary;
    var colour = selected ? accent : theme.colors.onSurfaceVariant;

    Widget content;
    if (showLabel) {
      content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(page.icon, size: _tabIconSize, color: colour),
        const SizedBox(width: _tabLabelGap),
        Flexible(
          child: Text(
            page.short,
            overflow: TextOverflow.ellipsis,
            style: labelStyle.copyWith(
              color: colour,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        SizedBox(
          width: _countSpace,
          child: count == 0
              ? null
              : Text("  $count", style: TextStyle(fontSize: 10, color: colour)),
        ),
      ]);
    } else {
      // Too narrow for names. The underline still does the work the fill used
      // to, so the two navigations stay distinguishable at every width.
      content = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(page.icon, size: 17, color: colour),
        SizedBox(
          height: 12,
          child: count == 0
              ? null
              : Text("$count",
                  style: TextStyle(fontSize: 10, height: 1.2, color: colour)),
        ),
      ]);
    }

    return Tooltip(
      message: count > 0 ? "${page.title} ($count)" : page.title,
      child: InkWell(
        onTap: () => widget.onPageChanged(page),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: _tabPadding),
          decoration: BoxDecoration(
            border: Border(
              // Always present, transparent when unselected: a border that
              // appears only on the active tab changes the height of the
              // others, and the row twitches as the selection moves.
              bottom: BorderSide(
                  color: selected ? accent : Colors.transparent, width: 2),
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  /// _documentPage is the counts.
  ///
  /// Rebuilt from the text on every change rather than cached: everything on
  /// it is a single pass over a message, which is nothing beside the spell
  /// check already running on the same keystroke.
  Widget _documentPage(ThemeNotifier theme) {
    var stats = WritingStats.of(_editor?.text ?? "");
    var ease = stats.readingEaseLabel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        _stat(theme, "Words", "${stats.words}"),
        _stat(theme, "Characters", "${stats.characters}"),
        _stat(theme, "Characters (no spaces)", "${stats.charactersNoSpaces}"),
        _stat(theme, "Sentences", "${stats.sentences}"),
        _stat(theme, "Paragraphs", "${stats.paragraphs}"),
        _stat(theme, "Lines", "${stats.lines}"),
        _stat(theme, "Pages", stats.pages.toStringAsFixed(1)),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _stat(theme, "Reading time", _readingTime(stats)),
        // Absent rather than shown as a dash on text too short to score: a
        // reading-ease figure for one sentence is arithmetic, not
        // information, and printing it invites it to be believed.
        if (ease != null)
          _stat(theme, "Reading ease", "$ease (${stats.readingEase!.round()})"),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            ease == null
                ? "Reading ease appears once there is enough text to score."
                : "Reading ease runs 0 to 100; plain English scores 60-70. "
                    "Pages assume $wordsPerPage words; reading time assumes "
                    "$wordsPerMinute words a minute.",
            style: TextStyle(
                fontSize: 10,
                height: 1.4,
                color: theme.colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  String _readingTime(WritingStats stats) {
    var seconds = stats.readingTime.inSeconds;
    if (seconds < 60) return "$seconds sec";
    var minutes = stats.readingTime.inMinutes;
    return "$minutes min";
  }

  Widget _stat(ThemeNotifier theme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: theme.colors.onSurfaceVariant)),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _note(ThemeNotifier theme, String text) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text,
            style:
                TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant)),
      );

  Widget _issueRow(
      ThemeNotifier theme, WritingPreferences prefs, WritingIssue issue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            issue.kind == WritingIssueKind.spelling
                ? Icons.spellcheck
                : Icons.edit_note,
            size: 14,
            color: theme.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(issue.text,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 2),
          child: Text(issue.message,
              style: TextStyle(
                  fontSize: 11, color: theme.colors.onSurfaceVariant)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var suggestion in issue.suggestions)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(suggestion, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _apply(issue, suggestion),
                ),
              // A repeated word is the one counting check that can be
              // answered with a replacement, and it is the only one that has
              // to be asked for rather than computed. The count comes from
              // the paragraph; the alternatives come from the thesaurus, one
              // wasm call away, so they are fetched when the issue is on
              // screen rather than while the text is being checked.
              if (issue.checkId == repeatedWordCheckId)
                _synonymChips(context, theme, issue),
              // The same two ways out the context menu offers, since the
              // panel is where someone works through a whole post and is
              // exactly where "stop telling me about this" belongs.
              if (issue.checkId != null) ...[
                // Dismissing this phrase, against turning the rule off
                // everywhere -- see the note in writing_popup.dart.
                _dismissChip(theme, "Ignore once",
                    () => prefs.ignoreMatch(issue.checkId!, issue.text)),
                _dismissChip(
                    theme,
                    "Turn off",
                    // The description is what names the rule in Settings.
                    // Without it the list there reads "check 1, check 2".
                    () => prefs.disableCheck(issue.checkId!,
                        description: issue.ruleMessage)),
              ] else ...[
                _dismissChip(
                    theme, "Ignore", () => prefs.ignoreOnce(issue.text)),
                _dismissChip(theme, "Add to dictionary",
                    () => prefs.addToDictionary(issue.text)),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  /// _synonymChips offers other words for a repeated one.
  ///
  /// Nothing is shown while the lookup runs and nothing is shown when it
  /// comes back empty: this sits inside a row that already says what the
  /// problem is, and a "Looking up..." line that resolves to nothing would
  /// make every repeated word in a long post flicker.
  ///
  /// Capped at four. The thesaurus returns everything it has, and a paragraph
  /// with six repetitions in it would otherwise fill the panel with chips.
  Widget _synonymChips(
      BuildContext context, ThemeNotifier theme, WritingIssue issue) {
    var thesaurus = context.read<ThesaurusCapability?>();
    var word = ThesaurusCapability.normalizeWord(issue.text);
    if (thesaurus == null || !thesaurus.available || word == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<ThesaurusEntry?>(
      key: ValueKey(word),
      future: thesaurus.lookUp(word),
      builder: (context, snapshot) {
        var entry = snapshot.data;
        if (entry == null) return const SizedBox.shrink();
        var words = <String>[];
        for (var sense in entry.senses) {
          for (var synonym in sense.synonyms) {
            // The word itself comes back among its own synonyms, and
            // replacing it with itself would leave the count where it was.
            if (synonym.toLowerCase() == word ||
                words.contains(synonym) ||
                synonym.contains(" ")) {
              continue;
            }
            words.add(synonym);
            if (words.length == 4) break;
          }
          if (words.length == 4) break;
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var synonym in words)
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(synonym, style: const TextStyle(fontSize: 12)),
                // Case carried over, so replacing a word that opens a
                // sentence does not lower-case it.
                onPressed: () => _apply(issue, matchCase(issue.text, synonym)),
              ),
          ],
        );
      },
    );
  }

  Widget _dismissChip(ThemeNotifier theme, String label, VoidCallback onTap) =>
      ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: theme.colors.outlineVariant),
        label: Text(label,
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
        onPressed: onTap,
      );

  /// _thesaurusPage shows what the selected word means and what else could
  /// have been said.
  ///
  /// Selection-driven rather than search-driven: the word wanted is almost
  /// always the one under the cursor, and typing it again into a box to ask
  /// about it is a step for nothing. The lookup only runs while a word is
  /// actually selected, so an idle page asks the provider nothing.
  Widget _thesaurusPage(BuildContext context, ThemeNotifier theme) {
    var thesaurus = context.read<ThesaurusCapability?>();
    if (thesaurus == null || !thesaurus.available) {
      return _note(theme, "No plugin provides a thesaurus.");
    }

    var selection =
        _editor?.selection ?? const TextSelection.collapsed(offset: -1);
    var text = _editor?.text ?? "";
    String? word;
    if (selection.isValid && !selection.isCollapsed) {
      word = ThesaurusCapability.normalizeWord(selection.textInside(text));
    }

    if (word == null) {
      return _note(theme,
          "Select a word to see what it means and what else could be said.");
    }
    return Scrollbar(
      controller: _alternativesScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _alternativesScroll,
        // Room for the scrollbar at the sidebar's edge, so the chips are not
        // printed underneath it.
        padding: const EdgeInsets.fromLTRB(12, 10, 18, 16),
        child: FutureBuilder<ThesaurusEntry?>(
          // Keyed by the word so a new selection starts a new lookup rather
          // than showing the previous word's answer while it loads.
          key: ValueKey(word),
          future: thesaurus.lookUp(word),
          builder: (context, snapshot) =>
              _alternatives(theme, word!, selection, snapshot),
        ),
      ),
    );
  }

  Widget _alternatives(ThemeNotifier theme, String word,
      TextSelection selection, AsyncSnapshot<ThesaurusEntry?> snapshot) {
    var muted = TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant);

    if (snapshot.connectionState != ConnectionState.done) {
      return Text('Looking up "$word"...', style: muted);
    }
    var entry = snapshot.data;
    if (entry == null || entry.isEmpty) {
      return Text('Nothing found for "$word".', style: muted);
    }

    var base = lookedUpAs(word, entry);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(
            text: '"$word"',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        // The provider reduced the word to the form its data is keyed by, so
        // "children" is answered as "child". Left unsaid, an entry headed by
        // a different word reads as a mistake.
        if (base != null) TextSpan(text: "  \u2192  $base", style: muted),
      ])),
      // What the word means, before what could replace it. Choosing between
      // alternatives is guesswork without knowing which sense of the word was
      // meant, and this is the only place the panel says.
      if (entry.definitions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: definitionList(theme, entry.definitions),
          ),
        ),
      if (entry.senses.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text("Alternatives",
              style: muted.copyWith(fontWeight: FontWeight.w600)),
        ),
      for (var sense in entry.senses) ...[
        if (sense.partOfSpeech.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(sense.partOfSpeech,
                style: muted.copyWith(fontStyle: FontStyle.italic)),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var synonym in sense.synonyms)
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(synonym, style: const TextStyle(fontSize: 12)),
                onPressed: () => _replaceSelection(selection, synonym),
              ),
            // Marked, because an opposite is never a like-for-like swap and
            // must not sit unlabelled among words that are.
            for (var antonym in sense.antonyms)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.swap_horiz,
                    size: 14, color: theme.colors.onSurfaceVariant),
                label: Text(antonym, style: const TextStyle(fontSize: 12)),
                tooltip: "Opposite meaning",
                onPressed: () => _replaceSelection(selection, antonym),
              ),
          ],
        ),
      ],
    ]);
  }

  void _replaceSelection(TextSelection selection, String replacement) {
    var editor = _editor;
    if (editor == null) return;
    if (!selection.isValid || selection.end > editor.text.length) return;
    editor.value = TextEditingValue(
      text:
          editor.text.replaceRange(selection.start, selection.end, replacement),
      selection:
          TextSelection.collapsed(offset: selection.start + replacement.length),
    );
  }
}
