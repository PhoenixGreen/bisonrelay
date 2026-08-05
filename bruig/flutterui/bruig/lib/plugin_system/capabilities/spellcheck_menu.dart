import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

// spellcheck_menu.dart puts a misspelled word's corrections into the
// composer's own context menu, beside Paste and Synonyms.
//
// Flutter can show corrections itself, but only in a *separate* toolbar, and
// only when SpellCheckConfiguration.spellCheckSuggestionsToolbarBuilder is
// set -- at which point right-clicking a misspelled word shows that toolbar
// INSTEAD of the ordinary menu. That trade is wrong here: the corrections
// are the most likely reason to right-click a flagged word, but they should
// not cost the user everything else the menu offers.
//
// So the suggestions are read off the same spell-check results Flutter has
// already computed for the underline, and offered as ordinary menu items.

/// maxCorrections bounds how many corrections reach the menu. The service
/// ranks them nearest-first, and a context menu with a dozen near-identical
/// words in it is harder to use than one with the best three.
const int maxCorrections = 4;

/// spellingContextMenuItems returns the corrections for whichever misspelled
/// word the menu was opened on, or nothing when it wasn't opened on one.
///
/// These belong at the top of the menu: on a flagged word they are what was
/// being asked for.
List<ContextMenuButtonItem> spellingContextMenuItems(
  BuildContext context,
  EditableTextState editableTextState,
) {
  var span = misspellingAt(editableTextState);
  if (span == null) return const [];

  return [
    for (var suggestion in span.suggestions.take(maxCorrections))
      ContextMenuButtonItem(
        label: suggestion,
        onPressed: () =>
            _applyCorrection(editableTextState, span.range, suggestion),
      ),
  ];
}

/// misspellingAt returns the flagged span under the cursor, or null if the
/// word there is spelled fine (or nothing has been checked yet).
///
/// Exposed because it answers a question the thesaurus also needs: there is
/// no point offering synonyms for a word that isn't a word.
SuggestionSpan? misspellingAt(EditableTextState editableTextState) {
  var value = editableTextState.textEditingValue;
  var selection = value.selection;
  if (!selection.isValid) return null;

  // Spell check runs asynchronously, so the results can describe text that
  // has since been edited -- and their ranges are byte offsets into the text
  // they were computed for. Acting on a stale one rewrites whatever now
  // occupies those offsets. Flutter records which text produced them
  // precisely so this can be checked.
  var results = editableTextState.spellCheckResults;
  if (results == null || results.spellCheckedText != value.text) return null;

  // Any span the selection touches, rather than one containing a single
  // cursor offset.
  //
  // Flutter's own findSuggestionSpanAtCursorIndex takes one offset, which is
  // enough for a caret but not for a right-click: on desktop that selects
  // the word under the pointer first, so the offset to test with is a whole
  // range, and using either end of it alone misses spans that overlap the
  // word without containing that end. A flagged word whose span does not
  // line up with word boundaries -- a missing capital, a space before
  // punctuation -- then offered nothing when clicked directly, while
  // clicking the punctuation beside it worked.
  var start = selection.start;
  var end = selection.end;
  for (var span in results.suggestionSpans) {
    if (span.suggestions.isEmpty) continue;
    // Half-open overlap, except for a collapsed caret, which is allowed to
    // sit on either boundary of the span it belongs to.
    var touches = selection.isCollapsed
        ? span.range.start <= start && start <= span.range.end
        : span.range.start < end && span.range.end > start;
    if (touches) return span;
  }
  return null;
}

/// _applyCorrection replaces the flagged span, mirroring what Material's own
/// spell-check toolbar does -- including scrolling the caret back into view,
/// since a correction can change the text's length and push it off screen.
void _applyCorrection(
  EditableTextState editableTextState,
  TextRange range,
  String replacement,
) {
  // Guarded rather than asserted: these items are built for whatever field
  // adds them, and a read-only or obscured one must not be rewritten.
  if (editableTextState.widget.readOnly ||
      editableTextState.widget.obscureText) {
    return;
  }
  // Re-checked at the moment of the edit, not just when the menu was built:
  // the text can change in between, and misspellingAt's guard only covered
  // the first of those.
  var results = editableTextState.spellCheckResults;
  if (results == null ||
      results.spellCheckedText != editableTextState.textEditingValue.text) {
    editableTextState.hideToolbar();
    return;
  }

  editableTextState.userUpdateTextEditingValue(
    editableTextState.textEditingValue.replaced(range, replacement),
    SelectionChangedCause.toolbar,
  );

  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (editableTextState.mounted) {
      editableTextState
          .bringIntoView(editableTextState.textEditingValue.selection.extent);
    }
  }, debugLabel: "spellcheck correction bringIntoView");

  editableTextState.hideToolbar();
}
