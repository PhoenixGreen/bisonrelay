import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/writing_tools/thesaurus_capability.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/composer_edits.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/sidebar_chips.dart';
import 'package:bruig/plugin_system/writing_tools/ui/thesaurus_menu.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// thesaurus_page.dart shows what the selected word means and what else could
// have been said.
//
// Selection-driven rather than search-driven: the word wanted is almost always
// the one under the cursor, and typing it again into a box to ask about it is
// a step for nothing. The lookup only runs while a word is actually selected,
// so an idle page asks the provider nothing.

class ThesaurusPage extends StatefulWidget {
  final ComposerEdits edits;
  const ThesaurusPage({required this.edits, super.key});

  @override
  State<ThesaurusPage> createState() => _ThesaurusPageState();
}

class _ThesaurusPageState extends State<ThesaurusPage> {
  // Owned rather than left implicit, so the Scrollbar and the view it tracks
  // are certainly the same one.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var thesaurus = context.read<ThesaurusCapability?>();
    if (thesaurus == null || !thesaurus.available) {
      return sidebarNote(theme, "No plugin provides a thesaurus.");
    }

    var selection = widget.edits.selection;
    String? word;
    if (selection.isValid && !selection.isCollapsed) {
      word = ThesaurusCapability.normalizeWord(
          selection.textInside(widget.edits.text));
    }
    if (word == null) {
      return sidebarNote(theme,
          "Select a word to see what it means and what else could be said.");
    }

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        // Room for the scrollbar at the sidebar's edge, so the chips are not
        // printed underneath it.
        padding: const EdgeInsets.fromLTRB(12, 10, 18, 16),
        child: FutureBuilder<ThesaurusEntry?>(
          // Keyed by the word so a new selection starts a new lookup rather
          // than showing the previous word's answer while it loads.
          key: ValueKey(word),
          future: thesaurus.lookUp(word),
          builder: (context, snapshot) =>
              _entry(theme, word!, selection, snapshot),
        ),
      ),
    );
  }

  Widget _entry(ThemeNotifier theme, String word, TextSelection selection,
      AsyncSnapshot<ThesaurusEntry?> snapshot) {
    var muted = TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant);

    if (snapshot.connectionState != ConnectionState.done) {
      return Text('Looking up "$word"...', style: muted);
    }
    var entry = snapshot.data;
    if (entry == null || entry.isEmpty) {
      return Text('Nothing found for "$word".', style: muted);
    }

    void replace(String replacement) => widget.edits.replaceRange(
        selection.start, selection.end, replacement);

    var base = lookedUpAs(word, entry);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(
            text: '"$word"',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        // The provider reduced the word to the form its data is keyed by, so
        // "children" is answered as "child". Left unsaid, an entry headed by a
        // different word reads as a mistake.
        if (base != null) TextSpan(text: "  →  $base", style: muted),
      ])),
      // What the word means, before what could replace it. Choosing between
      // alternatives is guesswork without knowing which sense of the word was
      // meant, and this is the only place the panel says.
      if (entry.definitions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...inflectionLine(theme, entry.inflections),
              ...definitionList(theme, entry.definitions),
            ],
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
              alternativeChip(theme, synonym, () => replace(synonym)),
            for (var antonym in sense.antonyms)
              alternativeChip(theme, antonym, () => replace(antonym),
                  opposite: true),
          ],
        ),
      ],
    ]);
  }
}
