import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

// spellcheck_actions.dart answers two questions for anything that presents
// writing issues: what was clicked, and how to apply what was chosen.
//
// Kept apart from the things that present them, because there are three --
// the explanatory popup, the sidebar and the thesaurus sheet -- and each has
// to act on the field identically.
//
// This file used to be larger. It held a routine that recomputed the flagged
// spans and wrote them back into the field by hand, because Flutter re-ran
// its spell check only when the text changed and an ignored word therefore
// kept its underline until the next keystroke. Nothing needs that any more:
// the field paints from the capability every time it builds, so ignoring a
// word repaints it in the same frame.

/// maxCorrections bounds how many corrections reach a menu. The checker ranks
/// them nearest-first, and a menu with a dozen near-identical words in it is
/// harder to use than one with the best three.
const int maxCorrections = 4;

/// issuesAtSelection is everything wrong with whatever the menu was opened
/// on, or nothing when it was not opened on a flagged span.
///
/// Everything, not just the issue that won the right to underline the word: a
/// word can be misspelled *and* caught by a style rule, or by two style
/// rules, and showing them one at a time -- each appearing only once the last
/// was fixed -- makes the popup look as though it had missed something.
///
/// The selection is treated as a range rather than a point. On desktop a
/// right-click selects the word under the pointer first, so testing a single
/// offset misses any span that overlaps the word without containing that
/// offset -- a missing capital, a space before punctuation -- which is why
/// clicking a flagged letter once offered nothing while clicking the
/// punctuation beside it worked.
List<WritingIssue> issuesAtSelection(
  BuildContext context,
  EditableTextState editableTextState,
) {
  var capability = context.read<SpellcheckCapability?>();
  if (capability == null) return const [];

  var value = editableTextState.textEditingValue;
  var selection = value.selection;
  if (!selection.isValid) return const [];

  // A collapsed caret is allowed to sit on either boundary of the span it
  // belongs to. issuesAt takes a half-open range, so a zero-width one would
  // overlap nothing at all -- and a caret placed by clicking a one-character
  // span, which is what a missing sentence capital is, sits exactly on a
  // boundary and would find nothing.
  if (selection.isCollapsed) {
    var at = selection.start;
    return capability.issuesAt(
        value.text, at - 1, (at + 1).clamp(0, value.text.length));
  }
  return capability.issuesAt(value.text, selection.start, selection.end);
}

/// applyCorrection replaces [range] with [replacement], mirroring what
/// Material's own spell-check toolbar does -- including scrolling the caret
/// back into view, since a correction can change the text's length and push
/// it off screen.
///
/// [expected] is what the range held when the choice was offered. The text
/// can change between a menu opening and an entry being pressed, and a range
/// is a pair of offsets into the text it was computed for -- so acting on a
/// stale one rewrites whatever now occupies those offsets.
void applyCorrection(
  EditableTextState editableTextState,
  TextRange range,
  String replacement, {
  String? expected,
}) {
  // Guarded rather than asserted: these actions are taken on whatever field
  // uses them, and a read-only or obscured one must not be rewritten.
  if (editableTextState.widget.readOnly ||
      editableTextState.widget.obscureText) {
    return;
  }

  var value = editableTextState.textEditingValue;
  if (range.start < 0 || range.end > value.text.length) {
    editableTextState.hideToolbar();
    return;
  }
  if (expected != null &&
      value.text.substring(range.start, range.end) != expected) {
    editableTextState.hideToolbar();
    return;
  }

  editableTextState.userUpdateTextEditingValue(
    value.replaced(range, replacement),
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
