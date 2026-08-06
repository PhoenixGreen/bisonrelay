import 'package:bruig/plugin_system/capabilities/spellcheck_actions.dart';
import 'package:bruig/plugin_system/capabilities/thesaurus.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// thesaurus_menu.dart is how the thesaurus capability reaches a composer for
// a word that is *not* flagged: as an extra entry in the text-selection
// toolbar, which is the menu a right-click opens on desktop and a long-press
// on mobile.
//
// A flagged word takes the explanatory popup in writing_popup.dart instead.
// The two are different questions -- "what did I get wrong" against "what
// does this mean, and what else could I have said" -- and answering the
// second in a sheet keeps the first uncluttered.
//
// Living here rather than in each composer is what keeps the app's own text
// fields free of it: a composer adds `...thesaurusContextMenuItems(...)` to
// its menu and is done, and the entry disappears on its own when no plugin
// provides synonyms.

/// thesaurusContextMenuItems returns the lookup entry for a composer's
/// selection toolbar, or nothing at all.
///
/// Nothing is the common case, and deliberately silent: no thesaurus plugin
/// enabled, or a selection that isn't a single word. An entry that opened an
/// empty menu would be worse than no entry.
List<ContextMenuButtonItem> thesaurusContextMenuItems(
  BuildContext context,
  EditableTextState editableTextState,
) {
  var capability = context.read<ThesaurusCapability?>();
  if (capability == null || !capability.available) return const [];

  var controller = editableTextState.textEditingValue;
  var selection = controller.selection;
  if (!selection.isValid || selection.isCollapsed) return const [];

  var selected = selection.textInside(controller.text);
  var word = ThesaurusCapability.normalizeWord(selected);
  if (word == null) return const [];

  // A word the dictionary doesn't have is not a word a thesaurus can answer
  // for, so offering the lookup would promise a list that is always empty.
  // The corrections shown in its place are what was actually wanted.
  //
  // Only a mistake suppresses it. A phrasing suggestion is an opinion about a
  // word that is spelled perfectly well, and looking it up is a reasonable
  // thing to want to do next.
  if (issuesAtSelection(context, editableTextState)
      .any((issue) => issue.kind.isMistake)) {
    return const [];
  }

  return [
    ContextMenuButtonItem(
      // "Look up" rather than "Synonyms", because the sheet now answers what
      // the word means as well as what could replace it, and a label naming
      // only half of that hides the other half from anyone reading the menu.
      label: "Look up",
      onPressed: () {
        // Close the toolbar before the sheet opens: leaving it up puts two
        // overlapping popups on screen, both anchored to the same selection.
        editableTextState.hideToolbar();
        showThesaurusSheet(
          context,
          capability: capability,
          word: word,
          onReplace: (replacement) =>
              _replaceSelection(editableTextState, selection, replacement),
        );
      },
    ),
  ];
}

/// _replaceSelection swaps the selected word for [replacement], leaving the
/// caret after it.
///
/// The selection is captured when the menu opens, not read back when the
/// replacement is chosen: opening the sheet takes focus off the field, which
/// on some platforms collapses the selection that was being acted on.
void _replaceSelection(
  EditableTextState state,
  TextSelection selection,
  String replacement,
) {
  var value = state.textEditingValue;
  var start = selection.start.clamp(0, value.text.length);
  var end = selection.end.clamp(0, value.text.length);
  var text = value.text.replaceRange(start, end, replacement);
  state.userUpdateTextEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    ),
    SelectionChangedCause.toolbar,
  );
}

/// showThesaurusSheet presents what a provider knows about [word] and calls
/// [onReplace] with whichever alternative is chosen.
Future<void> showThesaurusSheet(
  BuildContext context, {
  required ThesaurusCapability capability,
  required String word,
  required ValueChanged<String> onReplace,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _ThesaurusSheet(
      capability: capability,
      word: word,
      onReplace: onReplace,
    ),
  );
}

/// lookedUpAs names the form a provider answered for when it is not the form
/// that was asked about, or null when the two agree.
///
/// A provider reduces a word to the base form its data is keyed by, so
/// selecting "children" returns the entry for "child". Saying so matters:
/// without it the reader is left to work out for themselves whether a
/// definition headed by a different word is really about the one they picked,
/// and the answer looks like a mistake.
String? lookedUpAs(String asked, ThesaurusEntry entry) {
  var answered = entry.word.trim().toLowerCase();
  if (answered.isEmpty || answered == asked.trim().toLowerCase()) return null;
  return answered;
}

/// definitionList renders a word's meanings, or nothing when a provider
/// supplied none.
///
/// Shared with the writing sidebar, which shows the same thing in a narrower
/// space: two renderings of one list would drift apart, and the numbering and
/// the part-of-speech labels are exactly the details that would drift.
List<Widget> definitionList(
    ThemeNotifier theme, List<ThesaurusDefinition> definitions) {
  if (definitions.isEmpty) return const [];
  return [
    for (var i = 0; i < definitions.length; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Numbered, because a word's meanings are a list of alternatives
          // rather than one description in several parts, and unnumbered
          // lines read as the latter.
          SizedBox(
            width: 16,
            child: Text("${i + 1}.",
                style: TextStyle(
                    fontSize: 12, color: theme.colors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text.rich(
                TextSpan(children: [
                  if (definitions[i].partOfSpeech.isNotEmpty)
                    TextSpan(
                      text: "${definitions[i].partOfSpeech}  ",
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: theme.colors.onSurfaceVariant,
                      ),
                    ),
                  TextSpan(text: definitions[i].text),
                ]),
                style: const TextStyle(fontSize: 12, height: 1.35)),
          ),
        ]),
      ),
  ];
}

class _ThesaurusSheet extends StatefulWidget {
  final ThesaurusCapability capability;
  final String word;
  final ValueChanged<String> onReplace;

  const _ThesaurusSheet({
    required this.capability,
    required this.word,
    required this.onReplace,
  });

  @override
  State<_ThesaurusSheet> createState() => _ThesaurusSheetState();
}

class _ThesaurusSheetState extends State<_ThesaurusSheet> {
  late final Future<ThesaurusEntry?> _entry =
      widget.capability.lookUp(widget.word);

  void _choose(String replacement) {
    widget.onReplace(replacement);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: FutureBuilder<ThesaurusEntry?>(
          future: _entry,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            var entry = snapshot.data;
            if (entry == null || entry.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text('Nothing found for "${widget.word}".',
                    style: TextStyle(color: theme.colors.onSurfaceVariant)),
              );
            }
            return _entryList(context, entry, theme);
          },
        ),
      ),
    );
  }

  Widget _entryList(
      BuildContext context, ThesaurusEntry entry, ThemeNotifier theme) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: widget.word,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            if (lookedUpAs(widget.word, entry) case var base?)
              TextSpan(
                text: "  \u2192  $base",
                style: TextStyle(
                    fontSize: 14, color: theme.colors.onSurfaceVariant),
              ),
          ])),
        ),
        // Meanings first. Someone who does not know the word cannot judge a
        // list of replacements for it, and someone who does will read past
        // this in a glance.
        ...definitionList(theme, entry.definitions),
        if (entry.definitions.isNotEmpty && entry.senses.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
        for (var sense in entry.senses) ...[
          if (sense.partOfSpeech.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                sense.partOfSpeech,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.colors.onSurfaceVariant,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var synonym in sense.synonyms)
                ActionChip(
                  label: Text(synonym),
                  onPressed: () => _choose(synonym),
                ),
              // Antonyms are offered too, marked, because "the opposite of
              // what I wrote" is a thing people reach for -- but they are
              // never a like-for-like swap, so they must not sit unlabelled
              // among the synonyms.
              for (var antonym in sense.antonyms)
                ActionChip(
                  avatar: Icon(Icons.swap_horiz,
                      size: 16, color: theme.colors.onSurfaceVariant),
                  label: Text(antonym),
                  tooltip: "Opposite meaning",
                  onPressed: () => _choose(antonym),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
