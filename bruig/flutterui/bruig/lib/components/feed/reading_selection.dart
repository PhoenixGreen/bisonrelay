import 'package:bruig/writing_tools/writing_tools.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// reading_selection.dart puts the writing tools' word lookup on text that is
// being read rather than written.
//
// A composer gets it through its EditableTextState, which knows what is
// selected and can replace it. A post has neither: the words are somebody
// else's and the widget under the pointer is a SelectableRegion. So the
// selection is followed as it changes and kept, which is the only public way
// to know what a reader has picked out, and the lookup opens read-only.

/// ReadingSelectionArea is a SelectionArea that offers "Look up" on a word.
///
/// Everything a SelectionArea already does -- select, copy, share -- is kept
/// and the entry is added to it. With no thesaurus plugin enabled nothing is
/// added and this is a SelectionArea exactly.
class ReadingSelectionArea extends StatefulWidget {
  final Widget child;
  const ReadingSelectionArea({required this.child, super.key});

  @override
  State<ReadingSelectionArea> createState() => _ReadingSelectionAreaState();
}

class _ReadingSelectionAreaState extends State<ReadingSelectionArea> {
  /// _selected is the last thing the reader picked out.
  ///
  /// Followed rather than asked for: SelectableRegionState keeps what is
  /// selected to itself, and onSelectionChanged is the only way in from
  /// outside. Right-clicking a word selects it first and opens the menu
  /// after, so by the time the menu is built this is the word under the
  /// pointer.
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) => _selected = content?.plainText,
      contextMenuBuilder: (context, state) =>
          AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors,
        buttonItems: [
          ...state.contextMenuButtonItems,
          ..._lookUpItems(context, state),
        ],
      ),
      child: widget.child,
    );
  }

  /// _lookUpItems is the lookup entry, or nothing at all.
  ///
  /// Nothing is the common case and is deliberately silent: no thesaurus
  /// plugin enabled, or a selection that is not a single word. An entry that
  /// opened an empty sheet would be worse than no entry.
  List<ContextMenuButtonItem> _lookUpItems(
      BuildContext context, SelectableRegionState state) {
    var capability = context.read<ThesaurusCapability?>();
    if (capability == null || !capability.available) return const [];

    var word = ThesaurusCapability.normalizeWord(_selected ?? "");
    if (word == null) return const [];

    return [
      ContextMenuButtonItem(
        label: "Look up",
        onPressed: () {
          // The toolbar goes before the sheet arrives: two popups anchored
          // to the same selection is one too many.
          state.hideToolbar();
          showThesaurusSheet(context, capability: capability, word: word);
        },
      ),
    ];
  }
}
