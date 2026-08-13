import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/writing_tools/engine/checks/repetition.dart';
import 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:bruig/plugin_system/writing_tools/thesaurus_capability.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/composer_edits.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/sidebar_chips.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// issue_list_page.dart is the sidebar's mistakes page and its phrasing page,
// which are the same page over different issues.
//
// One widget for both rather than two, because the difference between them is
// entirely which issues they were handed and what to say when there are none.
// Written as two they would have drifted, and the row -- which is where all
// the detail is -- would have been the thing that drifted.

/// IssueListPage lists issues, each with its corrections and its two ways out.
class IssueListPage extends StatelessWidget {
  final List<WritingIssue> issues;
  final ComposerEdits edits;

  /// empty is what to say when there is nothing to list, which differs by
  /// page: nothing to fix is not the same news as nothing to suggest.
  final String empty;

  const IssueListPage({
    required this.issues,
    required this.edits,
    required this.empty,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var prefs = context.watch<WritingPreferences>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        if (issues.isEmpty) sidebarNote(theme, empty),
        for (var issue in issues) _IssueRow(issue: issue, edits: edits, prefs: prefs),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  final WritingIssue issue;
  final ComposerEdits edits;
  final WritingPreferences prefs;

  const _IssueRow({
    required this.issue,
    required this.edits,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
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
              style:
                  TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var suggestion in issue.suggestions)
                suggestionChip(
                    suggestion, () => edits.applyToIssue(issue, suggestion)),
              // A repeated word is the one counting check that can be answered
              // with a replacement, and it is the only one that has to be
              // asked for rather than computed. The count comes from the
              // paragraph; the alternatives come from the thesaurus, one wasm
              // call away, so they are fetched when the issue is on screen
              // rather than while the text is being checked.
              if (issue.checkId == repeatedWordCheckId)
                _SynonymChips(issue: issue, edits: edits),
              ..._waysOut(theme),
            ],
          ),
        ),
      ]),
    );
  }

  /// _waysOut are the same two the context menu offers, since the panel is
  /// where someone works through a whole post and is exactly where "stop
  /// telling me about this" belongs.
  List<Widget> _waysOut(ThemeNotifier theme) {
    var checkId = issue.checkId;
    if (checkId == null) {
      return [
        dismissChip(theme, "Ignore", () => prefs.ignoreOnce(issue.text)),
        dismissChip(theme, "Add to dictionary",
            () => prefs.addToDictionary(issue.text)),
      ];
    }
    return [
      // Dismissing this phrase, against turning the rule off everywhere --
      // see the note in writing_popup.dart.
      dismissChip(
          theme, "Ignore once", () => prefs.ignoreMatch(checkId, issue.text)),
      // The description is what names the rule in Settings. Without it the
      // list there reads "check 1, check 2".
      dismissChip(
          theme,
          "Turn off",
          () =>
              prefs.disableCheck(checkId, description: issue.ruleMessage)),
    ];
  }
}

/// _SynonymChips offers other words for a repeated one.
///
/// Nothing is shown while the lookup runs and nothing is shown when it comes
/// back empty: this sits inside a row that already says what the problem is,
/// and a "Looking up..." line that resolves to nothing would make every
/// repeated word in a long post flicker.
class _SynonymChips extends StatelessWidget {
  final WritingIssue issue;
  final ComposerEdits edits;

  const _SynonymChips({required this.issue, required this.edits});

  /// _maxSynonyms caps what is offered. The thesaurus returns everything it
  /// has, and a paragraph with six repetitions in it would otherwise fill the
  /// panel with chips.
  static const int _maxSynonyms = 4;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
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
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var synonym in _pick(entry, word))
              alternativeChip(
                theme,
                synonym,
                // Case carried over, so replacing a word that opens a sentence
                // does not lower-case it.
                () =>
                    edits.applyToIssue(issue, matchCase(issue.text, synonym)),
              ),
          ],
        );
      },
    );
  }

  /// _pick takes the first few single-word alternatives that are not the word
  /// itself -- which comes back among its own synonyms, and replacing it with
  /// itself would leave the count where it was.
  List<String> _pick(ThesaurusEntry entry, String word) {
    var words = <String>[];
    for (var sense in entry.senses) {
      for (var synonym in sense.synonyms) {
        if (synonym.toLowerCase() == word ||
            words.contains(synonym) ||
            synonym.contains(" ")) {
          continue;
        }
        words.add(synonym);
        if (words.length == _maxSynonyms) return words;
      }
    }
    return words;
  }
}
