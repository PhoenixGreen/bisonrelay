import 'package:bruig/plugin_system/capabilities/thesaurus.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// thesaurus_menu.dart is how the thesaurus capability reaches a composer:
// as an extra entry in the text-selection toolbar, which is the menu a
// right-click opens on desktop and a long-press on mobile.
//
// Living here rather than in each composer is what keeps the app's own text
// fields free of it: a composer adds `...thesaurusContextMenuItems(...)` to
// its menu and is done, and the entry disappears on its own when no plugin
// provides synonyms.

/// thesaurusContextMenuItems returns the "Synonyms" entry for a composer's
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

  return [
    ContextMenuButtonItem(
      label: "Synonyms",
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
                child: Text('No synonyms for "${widget.word}".',
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
          child: Text(widget.word,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
